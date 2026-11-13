// Mochi — 화면을 돌아다니는 블루 바이컬러 랙돌 고양이 (macOS)
// 빌드: ./build.sh   (또는 swiftc -O -parse-as-library -o Mochi Mochi.swift)

import AppKit
import QuartzCore
import ServiceManagement
import CoreAudio
import ApplicationServices

// MARK: - 도우미

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func clampf(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    hi < lo ? (lo + hi) / 2 : min(max(v, lo), hi)
}
func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    a.blended(withFraction: clampf(t, 0, 1), of: b) ?? a
}
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ cols: [NSColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: cols.map { $0.cgColor } as CFArray, locations: locs)!
}

/// 복슬복슬한 타원. spiky면 끝이 뾰족한 털 뭉치, cheek은 아래 양옆(볼살) 털을 더 키움
func tufty(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ n: CGFloat = 14, _ amp: CGFloat = 0.04,
           rot: CGFloat = 0, cheek: CGFloat = 0, spiky: Bool = false, steps: Int = 120) -> NSBezierPath {
    let p = NSBezierPath()
    let a = rot * .pi / 180
    let ca = cos(a), sa = sin(a)
    for i in 0..<steps {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
        let tuft: CGFloat
        if spiky {
            let q = 1 - abs(sin(n * t / 2)); tuft = q * q - 0.3
        } else {
            let q = 0.5 * (1 + cos(n * t)); tuft = q * q * q - 0.3
        }
        let am = amp + cheek * max(0, -sin(t)) * abs(cos(t)) * 2
        let k = 1 + am * tuft
        let x = cos(t) * w / 2 * k, y = sin(t) * h / 2 * k
        let q = P(cx + x * ca - y * sa, cy + x * sa + y * ca)
        if i == 0 { p.move(to: q) } else { p.line(to: q) }
    }
    p.close()
    return p
}
func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    let rr = min(r, w / 2, h / 2)
    return NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: max(h, 0.1)), xRadius: rr, yRadius: rr)
}
func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: a); p.line(to: b); p.line(to: c); p.close()
    return p
}
func seg(_ a: CGPoint, _ b: CGPoint) -> NSBezierPath {
    let p = NSBezierPath(); p.move(to: a); p.line(to: b); return p
}
func rotation(about c: CGPoint, degrees: CGFloat) -> AffineTransform {
    let a = degrees * .pi / 180
    let cs = cos(a), sn = sin(a)
    return AffineTransform(m11: cs, m12: sn, m21: -sn, m22: cs,
                           tX: c.x - cs * c.x + sn * c.y, tY: c.y - sn * c.x - cs * c.y)
}
/// a에서 b까지 둥근 캡슐 (다리, 팔)
func limb(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) -> NSBezierPath {
    let L = hypot(b.x - a.x, b.y - a.y)
    let ang = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
    let p = rrect(a.x - w / 2, a.y - w / 2, L + w, w, w / 2)
    p.transform(using: rotation(about: a, degrees: ang))
    return p
}
func bez(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) -> (CGFloat) -> CGPoint {
    return { t in
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return P(a * p0.x + b * c1.x + c * c2.x + d * p1.x, a * p0.y + b * c1.y + c * c2.y + d * p1.y)
    }
}
/// 곡선을 따라 굵어졌다 가늘어지는 복슬 꼬리 모양
func plume(_ f: (CGFloat) -> CGPoint, _ r0: CGFloat, _ r1: CGFloat) -> (NSBezierPath, CGPoint, CGPoint) {
    let N = 40
    let pts = (0...N).map { f(CGFloat($0) / CGFloat(N)) }
    var left: [CGPoint] = [], right: [CGPoint] = [], rads: [CGFloat] = []
    for i in 0...N {
        let t = CGFloat(i) / CGFloat(N)
        let a = pts[max(0, i - 1)], b = pts[min(N, i + 1)]
        let dx = b.x - a.x, dy = b.y - a.y
        let L = max(0.0001, hypot(dx, dy))
        let nx = -dy / L, ny = dx / L
        var rr = r0 + (r1 - r0) * sin(min(1, t * 1.25) * .pi * 0.55)
        let tipT = max(0, (t - 0.75) / 0.25)
        rr *= 1 - 0.55 * tipT * tipT
        let q = 1 - abs(sin(t * 22))
        let tuft = 1 + 0.10 * (q * q - 0.3)
        left.append(P(pts[i].x + nx * rr * tuft, pts[i].y + ny * rr * tuft))
        right.append(P(pts[i].x - nx * rr * tuft, pts[i].y - ny * rr * tuft))
        rads.append(rr)
    }
    let p = NSBezierPath()
    p.move(to: left[0])
    for q in left.dropFirst() { p.line(to: q) }
    let tip = pts[N], a = pts[N - 1]
    let ang = atan2(tip.y - a.y, tip.x - a.x)
    let rt = rads[N]
    for k in 1..<12 {
        let th = ang + .pi / 2 - .pi * CGFloat(k) / 12
        p.line(to: P(tip.x + cos(th) * rt, tip.y + sin(th) * rt))
    }
    for q in right.reversed() { p.line(to: q) }
    p.close()
    return (p, pts[0], tip)
}

/// 점들을 부드럽게 잇는 닫힌 곡선
func smooth(_ pts: [CGPoint], k: CGFloat = 0.22) -> NSBezierPath {
    let p = NSBezierPath()
    let n = pts.count
    p.move(to: pts[0])
    for i in 0..<n {
        let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
        let c1 = P(p1.x + (p2.x - p0.x) * k, p1.y + (p2.y - p0.y) * k)
        let c2 = P(p2.x - (p3.x - p1.x) * k, p2.y - (p3.y - p1.y) * k)
        p.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
    }
    p.close()
    return p
}

/// 털이 있는 다리: 위(a)는 굵고 아래로 가늘어지다가 끝(b)에서 둥근 발로 볼록
func furleg(_ a: CGPoint, _ b: CGPoint, _ w0: CGFloat, _ w1: CGFloat, paw: CGFloat = 1.25, fur: CGFloat = 0.10, seed: CGFloat = 0) -> NSBezierPath {
    let dx = b.x - a.x, dy = b.y - a.y
    let L = max(0.0001, hypot(dx, dy))
    let nx = -dy / L, ny = dx / L
    let N = 14
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0...N {
        let t = CGFloat(i) / CGFloat(N)
        var w = (w0 + (w1 - w0) * t) / 2
        if t > 0.72 { w *= 1 + (paw - 1) * sin((t - 0.72) / 0.28 * .pi / 2) }
        let tuft = 1 + fur * (sin(t * 19 + seed) * 0.5 + 0.5) * sqrt(1 - t)
        let cxp = a.x + dx * t, cyp = a.y + dy * t
        left.append(P(cxp + nx * w * tuft, cyp + ny * w * tuft))
        let rt = 2 - tuft * 0.98
        right.append(P(cxp - nx * w * rt, cyp - ny * w * rt))
    }
    let wp = (w1 / 2) * paw
    let base = atan2(ny, nx)
    var pts = left
    for k in 1..<9 {
        let th = base - .pi * CGFloat(k) / 9
        pts.append(P(b.x + cos(th) * wp, b.y + sin(th) * wp * 0.92))
    }
    pts += right.reversed()
    let back = atan2(-ny, -nx)
    for k in 1..<9 {
        let th = back - .pi * CGFloat(k) / 9
        pts.append(P(a.x + cos(th) * w0 / 2, a.y + sin(th) * w0 / 2))
    }
    let p = NSBezierPath()
    p.move(to: pts[0])
    for q in pts.dropFirst() { p.line(to: q) }
    p.close()
    return p
}

/// 위는 좁고 아래는 넓은 복슬 몸통
func pear(_ cx: CGFloat, _ cy: CGFloat, _ wt: CGFloat, _ wb: CGFloat, _ h: CGFloat,
          _ n: CGFloat = 12, _ amp: CGFloat = 0.04, steps: Int = 120) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<steps {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
        let q = 0.5 * (1 + cos(n * t))
        let k = 1 + amp * (q * q * q - 0.3)
        let wy = (1 - sin(t)) / 2
        let w = wt + (wb - wt) * pow(wy, 0.8)
        let x = cos(t) * w / 2 * k
        var y = sin(t) * h / 2 * k
        if y < 0 { y *= 1 - 0.15 * abs(cos(t)) }
        if i == 0 { p.move(to: P(cx + x, cy + y)) } else { p.line(to: P(cx + x, cy + y)) }
    }
    p.close()
    return p
}

// MARK: - 언어

/// 앱 언어: "system"(시스템 설정 따름), "ko", "en"
func isKorean() -> Bool {
    let pref = UserDefaults.standard.string(forKey: "language") ?? "system"
    if pref == "ko" { return true }
    if pref == "en" { return false }
    return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
}
/// 한국어 / 영어 문구 고르기
func L(_ ko: String, _ en: String) -> String { isKorean() ? ko : en }

// MARK: - Updates

/// Checks GitHub Releases for a newer build and installs it in place.
@MainActor
final class Updater {
    static let shared = Updater()
    let repo = "junwon0901/Mochi"
    private var busy = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// true if version a is newer than b ("1.10" > "1.9")
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            let t = s.hasPrefix("v") ? String(s.dropFirst()) : s
            return t.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Checks once a day at most, quietly (only speaks up when there is an update).
    func checkDaily() {
        let d = UserDefaults.standard
        let last = d.double(forKey: "lastUpdateCheck")
        let now = Date().timeIntervalSince1970
        if now - last < 24 * 3600 { return }
        d.set(now, forKey: "lastUpdateCheck")
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        if busy { return }
        busy = true
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { busy = false; return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Mochi-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, error in
            var tag: String? = nil
            var zipURL: URL? = nil
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                tag = json["tag_name"] as? String
                if let assets = json["assets"] as? [[String: Any]] {
                    for a in assets {
                        let name = a["name"] as? String ?? ""
                        if name.hasSuffix(".zip"), let s = a["browser_download_url"] as? String {
                            zipURL = URL(string: s)
                            break
                        }
                    }
                }
            }
            let failed = error != nil || tag == nil
            DispatchQueue.main.async {
                self.busy = false
                self.handle(tag: tag, zipURL: zipURL, failed: failed, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(tag: String?, zipURL: URL?, failed: Bool, userInitiated: Bool) {
        if failed {
            if userInitiated {
                info(L("업데이트를 확인하지 못했어요", "Couldn't check for updates"),
                     L("인터넷 연결을 확인하고 잠시 후 다시 시도해 주세요.", "Check your internet connection and try again later."))
            }
            return
        }
        guard let tag = tag, Updater.isNewer(tag, than: currentVersion), let zipURL = zipURL else {
            if userInitiated {
                info(L("최신 버전이에요", "You're up to date"),
                     L("지금 쓰고 있는 Mochi \(currentVersion)이 최신 버전이에요.", "Mochi \(currentVersion) is the latest version."))
            }
            return
        }
        let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("새 버전이 있어요 (\(ver))", "A new version is available (\(ver))")
        alert.informativeText = L("지금 쓰고 있는 버전은 \(currentVersion)이에요. 업데이트하면 Mochi가 잠깐 꺼졌다가 다시 켜져요.",
                                  "You have \(currentVersion). Mochi will restart after updating.")
        alert.addButton(withTitle: L("업데이트", "Update"))
        alert.addButton(withTitle: L("나중에", "Later"))
        if alert.runModal() == .alertFirstButtonReturn { install(from: zipURL) }
    }

    private func install(from zipURL: URL) {
        busy = true
        URLSession.shared.downloadTask(with: zipURL) { tmp, _, error in
            var newApp: URL? = nil
            var workDir: URL? = nil
            if let tmp = tmp, error == nil {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("MochiUpdate-\(UUID().uuidString)")
                workDir = work
                try? fm.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("Mochi.zip")
                try? fm.moveItem(at: tmp, to: zip)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-x", "-k", zip.path, work.path]
                if (try? p.run()) != nil {
                    p.waitUntilExit()
                    let app = work.appendingPathComponent("Mochi.app")
                    if p.terminationStatus == 0 && fm.fileExists(atPath: app.path) { newApp = app }
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                guard let newApp = newApp else {
                    if let w = workDir { try? FileManager.default.removeItem(at: w) }
                    self.info(L("업데이트를 받지 못했어요", "Couldn't download the update"),
                              L("잠시 후 다시 시도해 주세요.", "Please try again later."))
                    return
                }
                self.swap(to: newApp)
            }
        }.resume()
    }

    /// Replaces the running app after it quits, then opens the new one.
    private func swap(to newApp: URL) {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            info(L("업데이트할 권한이 없어요", "No permission to update"),
                 L("\(parent.path) 폴더에 쓸 수 없어요.", "Mochi can't write to \(parent.path)."))
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$2"
        /usr/bin/ditto "$1" "$2"
        /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
        rm -rf "$3"
        /usr/bin/open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "mochi-update", newApp.path, target.path,
                       newApp.deletingLastPathComponent().path]
        do {
            try p.run()
        } catch {
            info(L("업데이트를 설치하지 못했어요", "Couldn't install the update"), error.localizedDescription)
            return
        }
        NSApp.terminate(nil)
    }

    private func info(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

// MARK: - Time of day, sound

/// Sleepier at night: 1 by day, 1.35 in the evening, 1.8 late at night
func nightFactor() -> Double {
    let h = Calendar.current.component(.hour, from: Date())
    if h >= 23 || h < 6 { return 1.8 }
    if h >= 21 { return 1.35 }
    return 1
}

/// true while any app is playing sound through the default output (no permission needed)
func audioPlaying() -> Bool {
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return false }
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}

/// Browsers and video players (when one of these is in front with a big window and sound is on, it's "watching")
let videoApps: Set<String> = [
    "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary", "company.thebrowser.Browser",
    "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "com.naver.Whale",
    "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen", "com.kagi.kagimacOS",
    "com.colliderli.iina", "org.videolan.vlc", "com.apple.QuickTimePlayerX", "com.apple.TV",
    "com.firecore.infuse", "com.netflix.Netflix",
]

/// Why the cat is travelling: chase the cursor, visit an idle cursor, greet after wake, or go to a spot
enum ComeMode { case chase, visit, greet, spot }

/// Invisible stepping stone the cat makes for itself in mid-air
struct Plat { let minX: CGFloat; let maxX: CGFloat; let y: CGFloat; var until: Double }

// MARK: - 털색 (랙돌 포인트 컬러)

enum PointColor: String, CaseIterable {
    case blue, seal, lilac, chocolate, flame

    var label: String {
        switch self {
        case .blue: return "블루 바이컬러 (회색)"
        case .seal: return "씰 바이컬러 (갈색)"
        case .lilac: return "라일락 바이컬러 (연보라 회색)"
        case .chocolate: return "초콜릿 바이컬러"
        case .flame: return "플레임 바이컬러 (주황)"
        }
    }
    private var v: (point: UInt32, light: UInt32, ear: UInt32, saddle: UInt32, tail: UInt32, body: UInt32) {
        switch self {
        case .blue: return (0x858A9B, 0xAEB3C0, 0x7C8192, 0xC6C9D2, 0xCDD0D8, 0xF7F6F4)
        case .seal: return (0x8B7262, 0xB49C89, 0x7C6556, 0xDCCBB8, 0xE3D6C6, 0xF9F5EF)
        case .lilac: return (0xA2949A, 0xC2B7BB, 0x96888E, 0xDDD5D7, 0xE5DFE0, 0xFAF8F7)
        case .chocolate: return (0x9A7357, 0xC09F84, 0x8C664B, 0xE0CFBA, 0xE8DACA, 0xFBF6EF)
        case .flame: return (0xD99A62, 0xE9BE93, 0xCF8B52, 0xF0D9BE, 0xF3E3CF, 0xFDF8F0)
        }
    }
    var point: NSColor { rgb(v.point) }
    var pointLight: NSColor { rgb(v.light) }
    var ear: NSColor { rgb(v.ear) }
    var saddle: NSColor { rgb(v.saddle) }
    var tailBase: NSColor { rgb(v.tail) }
    var body: NSColor { rgb(v.body) }
}

let cWhite = rgb(0xFFFFFE)
let cFar = rgb(0xE4E3E6)
let cOut = rgb(0x3E3B4C)
let cShade = rgb(0x5A5470)
let cInnerEar = rgb(0xF2B8C4)
let cNose = rgb(0xF29AAE)
let cBlush = rgb(0xFF9DB2, 0.5)
let lw: CGFloat = 1.5

// MARK: - 그리기

enum Pose { case stand, sit, loaf, sleep, groom, stretch, jump, dangle, roll, peek, hang }
enum EyeState { case open, wide, closed, happy, slow }

struct Particle {
    var p: CGPoint; var v: CGPoint; var life: CGFloat
    let maxLife: CGFloat; let text: String; let color: NSColor; let size: CGFloat
}

enum Fill { case color(NSColor), tail(CGPoint, CGPoint) }
struct Part { let path: NSBezierPath; let fill: Fill }

/// 머리 중심 (오른쪽을 볼 때, 100x100 단위)
func headUnit(_ pose: Pose) -> CGPoint {
    switch pose {
    case .sit, .groom: return P(58, 61)
    case .stand, .jump: return P(75, 50)
    case .loaf: return P(70, 38)
    case .sleep: return P(70, 21)
    case .stretch: return P(80, 25)
    case .dangle: return P(51, 70)
    case .roll: return P(76, 22)
    case .peek: return P(60, 58)
    case .hang: return P(50, 60)
    }
}

// MARK: - 스프라이트 (그림 파일로 그리는 고양이)

/// 캔버스 여백 (단위). 고양이 논리 영역은 100x100, 실제 창은 좌우로 MX, 위로 MT만큼 더 큼
let MX: CGFloat = 100
let MT: CGFloat = 120
/// 그림 1px(앱에 넣은 절반 크기 기준)이 몇 단위인지
let spriteK: CGFloat = 0.3125

struct SpriteInfo {
    let img: CGImage
    let w: CGFloat, h: CGFloat      // 픽셀
    let ax: CGFloat, base: CGFloat  // 몸 중심 x, 발바닥 y (위에서부터)
    let hx: CGFloat, hy: CGFloat, hr: CGFloat   // 머리 중심, 반지름
    let faceRight: Bool
    let paw: CGPoint?
}

/// 고양이 종
enum Breed: String, CaseIterable {
    case ragdoll, siamese
    var label: String {
        switch self {
        case .ragdoll: return L("랙돌 (블루 바이컬러)", "Ragdoll (blue bicolor)")
        case .siamese: return L("샴", "Siamese")
        }
    }
    /// 달리기 그림 순서와 프레임마다 튀어 오르는 높이
    var gallop: [String] { self == .ragdoll ? ["run1", "jump", "run2"] : ["run1", "run2", "run3", "run0"] }
    var bounces: [CGFloat] { self == .ragdoll ? [0, 5, 1.2] : [0, 4, 0.5, 4] }
}

@MainActor
final class Sprites {
    static let shared = Sprites()
    var sets: [String: [String: SpriteInfo]] = [:]
    /// 그림 모드인지 (랙돌 그림이 있으면 켜짐)
    var ok: Bool { usable(sets["ragdoll"]) }

    private func usable(_ m: [String: SpriteInfo]?) -> Bool { m?["sit"] != nil && m?["stand"] != nil }

    /// 이 종의 그림 묶음 (없으면 랙돌)
    func set(_ breed: Breed) -> [String: SpriteInfo] {
        if let m = sets[breed.rawValue], usable(m) { return m }
        return sets["ragdoll"] ?? [:]
    }
    func has(_ breed: Breed) -> Bool { usable(sets[breed.rawValue]) }

    init() {
        // 이름: (몸 중심 x, 발바닥 y, 머리 x, 머리 y, 머리 반지름, 오른쪽을 보는지, 앞발 끝)
        typealias Row = (String, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, CGPoint?)
        let ragdoll: [Row] = [
            ("stand", 134.1, 279.0, 69.2, 95.9, 52.2, false, nil),
            ("loaf", 177.6, 229.0, 79.7, 100.3, 64.6, false, nil),
            ("lie", 228.7, 212.0, 76.1, 57.1, 76.7, false, P(9.8, 98.9)),
            ("front", 118.9, 310.0, 76.5, 68.2, 56.3, false, nil),
            ("play", 175.4, 285.0, 244.3, 105.5, 65.0, true, nil),
            ("sit", 146.5, 253.0, 82.8, 62.7, 56.5, false, nil),
            ("back", 169.2, 331.0, 204.2, 118.7, 59.9, true, nil),
            ("lookup", 150.0, 317.0, 206.0, 64.2, 57.6, true, nil),
            ("sleep", 202.5, 219.0, 76.8, 106.5, 72.5, false, nil),
            ("run0", 164.9, 308.0, 59.5, 121.2, 55.8, false, nil),
            ("run1", 162.7, 293.0, 64.0, 117.3, 54.4, false, nil),
            ("run2", 163.3, 309.0, 54.8, 121.3, 56.0, false, nil),
            ("run3", 167.8, 308.0, 54.6, 120.4, 56.0, false, nil),
            ("walk0", 150.6, 320.0, 53.8, 120.1, 58.0, false, nil),
            ("walk1", 146.0, 322.0, 57.3, 121.0, 58.5, false, nil),
            ("walk2", 142.1, 322.0, 55.7, 120.7, 58.5, false, nil),
            ("walk3", 158.6, 324.0, 58.4, 121.5, 58.7, false, nil),
            ("blink", 118.8, 313.0, 65.9, 73.4, 56.7, false, nil),
            ("groom", 156.5, 292.0, 228.9, 70.9, 55.4, true, nil),
            ("wash", 148.3, 299.0, 213.3, 67.0, 54.4, true, nil),
            ("stretch", 219.2, 327.0, 84.7, 211.8, 74.2, false, nil),
            ("yawn", 137.2, 334.0, 118.6, 94.7, 60.5, false, nil),
            ("happywalk", 156.2, 339.0, 57.8, 123.5, 61.4, false, nil),
            ("loafclosed", 135.1, 205.0, 72.1, 48.6, 52.4, false, nil),
            ("belly", 221.2, 203.0, 64.3, 171.4, 75.8, false, nil),
            ("tilt", 110.5, 335.0, 61.2, 85.8, 60.7, false, nil),
            ("jump", 214.3, 246.0, 73.6, 98.1, 76.0, false, nil),
            ("land", 166.5, 267.0, 68.4, 136.8, 69.8, false, nil),
            ("crouch", 181.5, 193.0, 86.6, 136.1, 62.8, false, nil),
            ("sitt1", 117.4, 261.1, 73.6, 48.4, 49.5, false, nil),
            ("sitt2", 117.4, 261.1, 73.6, 48.4, 49.5, false, nil),
            ("sitt3", 117.4, 261.1, 73.6, 48.4, 49.5, false, nil),
            ("startle", 156.1, 312.0, 95.8, 107.4, 56.5, false, nil),
            ("hang1", 89.5, 467.0, 55.2, 106.4, 84.4, false, P(28.4, 0.0)),
            ("hang2", 80.4, 489.0, 83.0, 147.3, 88.4, false, P(78.1, 0.0)),
            ("peek", 92.7, 107.0, 92.5, 48.6, 33.3, false, nil),
            ("peektilt", 98.4, 122.0, 92.5, 55.4, 33.3, false, nil),
            ("peekeyes", 92.7, 77.0, 93.0, 35.1, 33.5, false, nil),
        ]
        let siamese: [Row] = [
            ("stand", 168.1, 302.0, 244.7, 85.6, 54.7, true, nil),
            ("loaf", 124.1, 234.0, 60.3, 69.5, 48.1, false, nil),
            ("lie", 213.3, 175.0, 141.3, 52.7, 71.1, false, P(1.0, 164.0)),
            ("front", 90.5, 335.0, 48.8, 77.2, 60.8, false, nil),
            ("play", 125.2, 238.0, 179.0, 58.8, 49.0, true, nil),
            ("sit", 108.1, 303.0, 57.9, 72.8, 55.1, false, nil),
            ("back", 136.2, 357.0, 201.3, 105.7, 64.6, true, nil),
            ("lookup", 105.8, 326.0, 144.3, 82.7, 59.0, true, nil),
            ("sleep", 160.4, 214.0, 79.8, 118.8, 57.4, false, nil),
            ("run0", 211.5, 235.0, 107.5, 66.2, 80.1, false, nil),
            ("run1", 158.6, 213.0, 74.2, 60.3, 64.3, false, nil),
            ("run2", 227.1, 229.0, 129.1, 64.8, 81.5, false, nil),
            ("run3", 153.0, 258.0, 71.3, 68.9, 65.0, false, nil),
            ("walk0", 158.9, 288.0, 60.0, 96.9, 57.6, false, nil),
            ("walk1", 159.2, 287.0, 59.9, 96.0, 57.6, false, nil),
            ("walk2", 160.4, 286.0, 60.0, 95.3, 57.4, false, nil),
            ("walk3", 155.1, 287.0, 58.4, 96.0, 55.4, false, nil),
            ("blink", 93.3, 315.0, 51.0, 74.0, 57.1, false, nil),
            ("groom", 117.5, 288.0, 61.9, 69.7, 52.2, false, nil),
            ("wash", 140.4, 288.0, 78.6, 72.7, 52.2, false, nil),
            ("stretch", 189.3, 324.0, 60.4, 202.1, 58.7, false, nil),
            ("yawn", 79.7, 332.0, 43.7, 79.9, 60.1, false, nil),
            ("happywalk", 144.4, 307.0, 214.0, 87.6, 55.6, true, nil),
            ("loafclosed", 114.7, 199.0, 59.2, 48.5, 44.5, false, nil),
            ("belly", 184.3, 198.0, 41.0, 110.6, 61.6, false, nil),
            ("tilt", 72.6, 362.0, 42.1, 88.8, 65.5, false, nil),
            ("jump", 187.3, 279.0, 105.2, 71.6, 73.4, false, nil),
            ("land", 152.2, 275.0, 75.4, 99.9, 57.8, false, nil),
            ("crouch", 144.8, 170.0, 43.6, 86.5, 52.4, false, nil),
            ("sitt1", 101.3, 303.8, 55.6, 55.9, 40.1, false, nil),
            ("sitt2", 101.3, 303.8, 55.6, 55.9, 40.1, false, nil),
            ("sitt3", 101.3, 303.8, 55.6, 55.9, 40.1, false, nil),
            ("croucht1", 130.3, 230.4, 47.6, 128.0, 31.1, false, nil),
            ("croucht2", 130.3, 230.4, 47.6, 128.0, 31.1, false, nil),
            ("croucht3", 130.3, 230.4, 47.6, 128.0, 31.1, false, nil),
            ("startle", 145.7, 234.0, 82.8, 56.3, 49.0, false, nil),
            ("hang1", 66.6, 426.0, 41.3, 98.8, 77.0, false, P(32.4, 0.0)),
            ("hang2", 75.3, 420.0, 74.0, 126.6, 76.0, false, P(75.5, 0.0)),
            ("peek", 91.7, 101.0, 93.0, 45.9, 33.5, false, nil),
            ("peektilt", 100.5, 118.0, 93.0, 53.6, 33.5, false, nil),
            ("peekeyes", 92.5, 75.0, 93.0, 34.2, 33.5, false, nil),
        ]
        load("ragdoll", ragdoll)
        load("siamese", siamese)
    }

    private func load(_ breed: String, _ table: [(String, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, CGPoint?)]) {
        var m: [String: SpriteInfo] = [:]
        for (name, ax, base, hx, hy, hr, fr, paw) in table {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "sprites/" + breed),
                  let ns = NSImage(contentsOf: url),
                  let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            m[name] = SpriteInfo(img: cg, w: CGFloat(cg.width), h: CGFloat(cg.height), ax: ax, base: base,
                                 hx: hx, hy: hy, hr: hr, faceRight: fr, paw: paw)
        }
        sets[breed] = m
    }
}

final class CatView: NSView {
    weak var cat: Cat?
    var colors: PointColor = .blue
    var pose: Pose = .sit
    var facingRight = true
    var phase: CGFloat = 0
    var tailSway: CGFloat = 0
    var eye: EyeState = .open
    var blink = false
    var look = CGPoint.zero
    var breathe: CGFloat = 0
    var mouth: CGFloat = 0
    var lick: CGFloat = 0
    var tilt: CGFloat = 0
    var earTwitch: CGFloat = 0
    var crouch: CGFloat = 0
    var wiggle: CGFloat = 0
    var butt: CGFloat = 0        // 덮치기 전 엉덩이 씰룩 (앞발을 축으로 흔드는 각도)
    var kick: CGFloat = 0
    var knead: CGFloat = 0
    var peekRot: CGFloat = 0
    var hangAngle: CGFloat = 0
    var particles: [Particle] = []
    // 고양이가 서 있는 투명 발판 (단위 좌표, 고양이 발 높이)
    var platL: CGFloat = 0
    var platR: CGFloat = 0
    var platA: CGFloat = 0

    private var downLoc = CGPoint.zero
    private var downOrigin = CGPoint.zero
    private var dragging = false

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 마우스

    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.control) { rightMouseDown(with: e); return }
        downLoc = NSEvent.mouseLocation
        downOrigin = cat?.origin ?? .zero
        dragging = false
    }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        if !dragging && hypot(m.x - downLoc.x, m.y - downLoc.y) > 4 {
            dragging = true
            NSCursor.closedHand.push()
            cat?.dragBegan()
        }
        if dragging {
            cat?.dragTo(P(downOrigin.x + m.x - downLoc.x, downOrigin.y + m.y - downLoc.y))
        }
    }
    override func mouseUp(with e: NSEvent) {
        if dragging {
            dragging = false
            NSCursor.pop()
            cat?.dragEnded()
        } else if e.clickCount == 1 {
            cat?.petted()
        }
    }
    override func rightMouseDown(with e: NSEvent) {
        guard let cat = cat else { return }
        NSMenu.popUpContextMenu(cat.app.makeMenu(for: cat), with: e, for: self)
    }

    // MARK: 그리기 기본

    private var ctx: CGContext { NSGraphicsContext.current!.cgContext }

    private func fill(_ p: NSBezierPath, _ c: NSColor) { c.setFill(); p.fill() }
    private func stroke(_ p: NSBezierPath, _ c: NSColor, _ w: CGFloat) {
        c.setStroke()
        p.lineWidth = w
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }
    private func softspot(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor, hard: CGFloat = 0.6) {
        let g = gradient([c, c, c.withAlphaComponent(0)], [0, hard, 1])
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.scaleBy(x: max(w, 0.01) / 2, y: max(h, 0.01) / 2)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
    }
    private func clip(_ paths: [NSBezierPath]) {
        let u = NSBezierPath()
        for p in paths { u.append(p) }
        u.windingRule = .nonZero
        u.addClip()
    }
    /// 바깥 윤곽선만 그리고, 안쪽은 순서대로 채움 → 다리와 몸이 한 덩어리처럼 보임
    private func sil(_ parts: [Part]) {
        for p in parts { stroke(p.path, cOut, lw * 2) }
        for p in parts {
            switch p.fill {
            case .color(let c): fill(p.path, c)
            case .tail(let a, let b):
                NSGraphicsContext.saveGraphicsState()
                p.path.addClip()
                let g = gradient([colors.tailBase, colors.pointLight, colors.point], [0, 0.5, 1])
                ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    private func shade(_ paths: [NSBezierPath]) {
        NSGraphicsContext.saveGraphicsState()
        clip(paths)
        let g = gradient([cShade.withAlphaComponent(0.11), cShade.withAlphaComponent(0), cShade.withAlphaComponent(0)], [0, 0.45, 1])
        ctx.drawLinearGradient(g, start: P(0, 0), end: P(0, 95), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        NSGraphicsContext.restoreGraphicsState()
    }
    private func spots(_ paths: [NSBezierPath], _ sp: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)]) {
        NSGraphicsContext.saveGraphicsState()
        clip(paths)
        for s in sp { softspot(s.0, s.1, s.2, s.3, s.4) }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func detail(_ p: NSBezierPath, _ w: CGFloat = lw * 0.85) { stroke(p, cOut.withAlphaComponent(0.85), w) }
    private func shadow(_ x: CGFloat, _ w: CGFloat) { softspot(x, 5, w, 5, rgb(0x3A3040, 0.14), hard: 0.3) }
    private func tail(_ f: (CGFloat) -> CGPoint, _ r0: CGFloat, _ r1: CGFloat) -> Part {
        let (p, a, b) = plume(f, r0, r1)
        return Part(path: p, fill: .tail(a, b))
    }
    private func part(_ p: NSBezierPath, _ c: NSColor) -> Part { Part(path: p, fill: .color(c)) }

    // MARK: 스프라이트 그리기

    var spriteKey = "sit"
    var breed: Breed = .ragdoll
    var bounce: CGFloat = 0
    var animT: CGFloat = 0

    /// 그림의 한 점(sp, 픽셀·위에서부터)을 화면 단위 좌표 u에 맞춰 그림. 좌우 반전 → 크기 → 회전 순
    private func blit(_ info: SpriteInfo, sp: CGPoint, u: CGPoint, mirror: Bool, rot: CGFloat = 0,
                      sx: CGFloat = 1, sy: CGFloat = 1) {
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: u.x, y: u.y)
        ctx.rotate(by: rot * .pi / 180)
        ctx.scaleBy(x: (mirror ? -1 : 1) * spriteK * sx, y: spriteK * sy)
        ctx.draw(info.img, in: CGRect(x: -sp.x, y: sp.y - info.h, width: info.w, height: info.h))
        ctx.restoreGState()
    }

    /// 오른쪽을 본다고 할 때 머리 위치 (단위)
    func headFR() -> CGPoint {
        guard Sprites.shared.ok, let info = Sprites.shared.set(breed)[spriteKey] else { return headUnit(pose) }
        if pose == .peek { return spriteKey.hasPrefix("peek") ? P(50, 52) : P(60, 58) }
        if pose == .hang || pose == .dangle { return P(50, 134) }
        let m: CGFloat = info.faceRight ? 1 : -1
        return P(50 + m * (info.hx - info.ax) * spriteK, 6 + (info.base - info.hy) * spriteK)
    }

    private func drawSprites() {
        let sp = Sprites.shared.set(breed)
        guard let info = sp[spriteKey] ?? sp["sit"] else { return }
        let mirror = facingRight != info.faceRight
        let foot = P(info.ax, info.base)
        switch pose {
        case .stand:
            if crouch > 0 && butt != 0 {
                // 앞발은 땅에 붙인 채 뒷몸만 씰룩
                let frontPx = info.faceRight ? max(info.w * 0.82, info.w - (info.w - info.ax) * 0.4) : min(info.w * 0.18, info.ax * 0.4)
                let ux = 50 + (frontPx - info.ax) * spriteK * (mirror ? -1 : 1)
                blit(info, sp: P(frontPx, info.base), u: P(ux, 6), mirror: mirror, rot: butt, sy: 1 - crouch * 0.07)
            } else if crouch > 0 {
                blit(info, sp: foot, u: P(50 + wiggle * 0.8, 6), mirror: mirror, rot: wiggle * 0.6, sy: 1 - crouch * 0.07)
            } else if spriteKey.hasPrefix("walk") || spriteKey.hasPrefix("run") || spriteKey == "jump" {
                // 프레임 그림이 다리를 움직이니 살짝만 출렁 (달리기는 통통 튀어오름)
                let r: CGFloat = spriteKey == "jump" ? 4 : (spriteKey == "run1" ? -2 : 0)
                blit(info, sp: foot, u: P(50, 6 + bounce), mirror: mirror, rot: bounce > 0 ? r * (facingRight ? 1 : -1) : 0)
            } else {
                let bob = abs(sin(phase)) * 2.4
                blit(info, sp: foot, u: P(50, 6 + bob), mirror: mirror, rot: sin(phase) * 1.8, sy: 1 + abs(cos(phase)) * 0.015)
            }
        case .jump:
            blit(info, sp: foot, u: P(50, 6), mirror: mirror, rot: tilt)
        case .stretch:
            let k = sin(min(1, animT / 1.8) * .pi)
            blit(info, sp: foot, u: P(50, 6), mirror: mirror, sx: 1 + 0.07 * k, sy: 1 - 0.06 * k)
        case .sit, .groom, .loaf, .sleep:
            var rot: CGFloat = 0
            var sy: CGFloat = 1 + breathe * (pose == .sleep ? 0.012 : 0.007)
            if pose == .groom { rot = lick * 1.6 }
            if pose == .loaf { rot = knead * 1.2 }
            if eye == .happy && pose == .sit { sy += abs(sin(animT * 9)) * 0.03 }
            if eye == .wide && pose == .sit { sy += 0.05 }
            blit(info, sp: foot, u: P(50, 6), mirror: mirror, rot: rot + tilt * 0.25, sy: sy)
        case .roll:
            blit(info, sp: foot, u: P(50, 6), mirror: mirror, rot: kick * 2.5)
        case .dangle, .hang:
            // 앞발 끝을 위쪽 고리에 걸고 축 늘어진 채 매달림 (랙돌!)
            let paw = info.paw ?? P(info.hx, info.hy)
            let upright = spriteKey.hasPrefix("hang")      // 매달린 그림은 이미 세로
            let base: CGFloat = upright ? 0 : (mirror ? 90 : -90)
            let swing = hangAngle
            blit(info, sp: paw, u: P(50, 158), mirror: mirror, rot: base + swing)
        case .peek:
            if spriteKey.hasPrefix("peek") {
                // 그림의 잘린 아랫면을 창 가장자리에 맞추고, 바깥 방향(peekRot)으로 세움
                blit(info, sp: P(info.w / 2, info.h - 1), u: P(50, 40), mirror: !facingRight, rot: peekRot - 90)
            } else {
                let rr = facingRight ? peekRot - 90 : 90 - peekRot
                blit(info, sp: P(info.hx, info.hy), u: facingRight ? P(60, 58) : P(40, 58), mirror: mirror, rot: rr)
            }
        }
    }

    /// 허공의 투명 발판: 발밑의 은은한 그림자 + 양끝이 흐려지는 가는 선 하나
    private func drawPlatform() {
        let a = platA
        let l = platL, r = platR, y: CGFloat = 6
        // 발이 닿은 곳의 부드러운 그림자
        let sh = NSBezierPath(ovalIn: CGRect(x: 50 - 24, y: y - 2.6, width: 48, height: 5.2))
        NSGradient(colors: [rgb(0x2A2438, 0.22 * a), rgb(0x2A2438, 0)])?.draw(in: sh, relativeCenterPosition: .zero)
        // 가는 선: 가운데는 또렷하고 양끝은 사라짐
        let line = CGRect(x: l, y: y - 0.9, width: r - l, height: 0.9)
        let c = rgb(0xFFFFFF, 0.55 * a), z = rgb(0xFFFFFF, 0)
        let g = NSGradient(colors: [z, c, c, z], atLocations: [0, 0.3, 0.7, 1], colorSpace: .sRGB)
        g?.draw(in: NSBezierPath(roundedRect: line, xRadius: 0.45, yRadius: 0.45), angle: 0)
    }

    // MARK: draw

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let s = bounds.width / (100 + 2 * MX)

        if platA > 0.01 {
            NSGraphicsContext.saveGraphicsState()
            let tp = NSAffineTransform()
            tp.scale(by: s)
            tp.translateX(by: MX, yBy: 0)
            tp.concat()
            drawPlatform()
            NSGraphicsContext.restoreGraphicsState()
        }

        if Sprites.shared.ok {
            NSGraphicsContext.saveGraphicsState()
            let ts = NSAffineTransform()
            ts.scale(by: s)
            ts.translateX(by: MX, yBy: 0)
            ts.concat()
            drawSprites()
            NSGraphicsContext.restoreGraphicsState()
        } else {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.scale(by: s)
        t.translateX(by: MX, yBy: 0)
        if !facingRight {
            t.translateX(by: 100, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
        }
        if pose == .hang {
            t.translateX(by: 50, yBy: 96)
            t.rotate(byDegrees: hangAngle)
            t.translateX(by: -50, yBy: -96)
        }
        t.concat()
        switch pose {
        case .stand: drawStand(jump: false)
        case .jump: drawStand(jump: true)
        case .sit, .groom: drawSit()
        case .loaf: drawLoaf()
        case .sleep: drawSleep()
        case .stretch: drawStretch()
        case .dangle: drawDangle()
        case .roll: drawRoll()
        case .peek: drawPeek()
        case .hang: drawHang()
        }
        NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        let t2 = NSAffineTransform()
        t2.scale(by: s)
        t2.translateX(by: MX, yBy: 0)
        t2.concat()
        for p in particles {
            let a = max(0, min(1, p.life / p.maxLife * 1.5))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: p.size, weight: .heavy),
                .foregroundColor: p.color.withAlphaComponent(a),
                .strokeColor: NSColor.white.withAlphaComponent(a * 0.9),
                .strokeWidth: -3.0,
            ]
            let str = NSAttributedString(string: p.text, attributes: attrs)
            let sz = str.size()
            str.draw(at: P(p.p.x - sz.width / 2, p.p.y - sz.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: 자세들

    private func toesAt(_ b: CGPoint, _ w: CGFloat) {
        for dx in [-w * 0.17, w * 0.17] { detail(seg(P(b.x + dx, b.y - w * 0.55), P(b.x + dx, b.y - w * 0.3)), lw * 0.6) }
    }

    private func drawSit() {
        let sw = tailSway, b = breathe
        let groom = pose == .groom
        shadow(50, 62)
        let tl = tail(bez(P(36, 13), P(16, 5), P(6, 22), P(14 + sw * 3, 42 + sw * 2)), 4, 10.5)
        let haunch = tufty(37, 18, 38, 28, 10, 0.06)
        let body = pear(50, 31 + b * 0.3, 30, 42, 46 + b, 12, 0.04)
        let hpaw = tufty(30, 8, 18, 8, 6, 0.06)
        let legL = furleg(P(49, 30), P(49, 9), 13, 10)
        let legR = furleg(P(60, 30), P(61, 9), 13, 10, seed: 2)
        let chest = tufty(58, 34, 32, 34, 11, 0.13, spiky: true)
        var parts: [Part] = [tl, part(haunch, colors.body), part(body, colors.body), part(hpaw, cWhite), part(legL, cFar), part(chest, cWhite)]
        if !groom { parts.append(part(legR, cWhite)) }
        sil(parts)
        spots([haunch, body], [(30, 28, 32, 20, colors.saddle), (38, 46, 28, 28, colors.saddle)])
        shade([haunch, body, legL, chest])
        let thigh = NSBezierPath()
        thigh.move(to: P(23, 13)); thigh.curve(to: P(38, 25), controlPoint1: P(23, 21), controlPoint2: P(30, 26))
        detail(thigh)
        toesAt(P(49, 9), 10)
        if groom {
            head(P(58, 61), 21, tilt: tilt)
            sil([part(furleg(P(58, 26), P(64, 45 + lick * 3), 12, 10, seed: 1), cWhite)])
        } else {
            toesAt(P(61, 9), 10)
            head(P(58, 61), 21, tilt: tilt)
        }
    }

    private func drawStand(jump: Bool) {
        let s = sin(phase), c = cos(phase), sw = tailSway
        let dy = -crouch * 6, wg = wiggle
        if !jump { shadow(50, 64) }
        let tl = tail(bez(P(26 + wg, 34 + dy), P(12 + wg, 36 + dy), P(6 + sw * 2, 52 + dy), P(14 + sw * 4, 66 + dy)), 4, 10.5)
        var fl: [NSBezierPath] = [], nl: [NSBezierPath] = []
        if jump {
            fl = [furleg(P(40, 26), P(32, 13), 13, 9), furleg(P(66, 28), P(78, 17), 13, 9, seed: 2)]
            nl = [furleg(P(33, 26), P(22, 14), 14, 10, seed: 1), furleg(P(60, 28), P(72, 14), 14, 10, seed: 3)]
        } else {
            func L(_ x: CGFloat, _ lift: CGFloat, _ sd: CGFloat, _ top: CGFloat = 27) -> NSBezierPath {
                furleg(P(x, top + dy), P(x + sd, 9 + lift), 14, 10, seed: x)
            }
            fl = [L(38 - s * 2 + wg, max(0, -c) * 3, -s * 4), L(66 + s * 2, max(0, c) * 3, s * 4)]
            nl = [L(31 + s * 2 + wg, max(0, c) * 3, s * 4, 25), L(59 - s * 2, max(0, -c) * 3, -s * 4, 25)]
        }
        let body = tufty(48 + wg * 0.5, 31 + dy, 58, 30, 12, 0.04)
        let chest = tufty(67, 32 + dy, 24, 28, 10, 0.14, spiky: true)
        var parts: [Part] = [tl]
        parts += fl.map { part($0, cFar) }
        parts.append(part(body, colors.body))
        parts += nl.map { part($0, cWhite) }
        parts.append(part(chest, cWhite))
        sil(parts)
        spots([body], [(44 + wg * 0.5, 45 + dy, 52, 22, colors.saddle)])
        var sh: [NSBezierPath] = [body, chest]
        sh += nl
        sh += fl
        shade(sh)
        let thigh = NSBezierPath()
        thigh.move(to: P(24 + wg, 22 + dy))
        thigh.curve(to: P(36 + wg, 32 + dy), controlPoint1: P(23 + wg, 28 + dy), controlPoint2: P(28 + wg, 32 + dy))
        detail(thigh)
        head(P(75, 50 + dy * 1.1), 20, tilt: tilt)
    }

    private func drawLoaf() {
        let k = knead
        shadow(50, 66)
        let body = tufty(48, 21, 62, 32, 12, 0.04)
        let p1 = furleg(P(60, 16), P(60, 8 + max(0, k) * 4), 12, 10, paw: 1.2)
        let p2 = furleg(P(71, 16), P(72, 8 + max(0, -k) * 4), 12, 10, paw: 1.2, seed: 2)
        sil([part(body, colors.body), part(p1, cFar), part(p2, cWhite)])
        spots([body], [(42, 34, 52, 20, colors.saddle)])
        shade([body])
        sil([tail(bez(P(22, 10), P(12, 4), P(30, 1), P(54, 6)), 3.5, 8)])
        head(P(70, 38 + breathe * 0.4), 20, tilt: tilt)
    }

    private func drawSleep() {
        let b = breathe
        shadow(50, 68)
        let body = tufty(46, 19, 66, 28 + b * 1.4, 12, 0.04)
        sil([part(body, colors.body)])
        spots([body], [(40, 30, 54, 18, colors.saddle)])
        shade([body])
        let thigh = NSBezierPath()
        thigh.move(to: P(25, 12)); thigh.curve(to: P(40, 24), controlPoint1: P(25, 20), controlPoint2: P(32, 24))
        detail(thigh)
        head(P(70, 21 + b * 0.4), 19, tilt: -12)
        sil([tail(bez(P(20, 11), P(6, 4), P(34, -1), P(64, 8)), 3.5, 8.5)])
    }

    private func drawRoll() {
        let k = kick
        shadow(50, 66)
        let tl = tail(bez(P(22, 12), P(12, 6), P(8, 14), P(10 + tailSway * 2, 26)), 3.5, 8.5)
        let lf = [furleg(P(40, 18), P(37, 34 + k * 2), 14, 10, seed: 1), furleg(P(60, 18), P(63, 35 - k * 2), 14, 10, seed: 2)]
        let ln = [furleg(P(33, 18), P(28, 32 - k * 2), 14, 10, seed: 3), furleg(P(54, 18), P(54, 34 + k * 2), 14, 10, seed: 4)]
        let body = tufty(48, 17, 60, 26, 12, 0.04)
        let belly = tufty(50, 22, 42, 14, 10, 0.12, spiky: true)
        var parts: [Part] = [tl]
        parts += lf.map { part($0, cFar) }
        parts.append(part(body, colors.body))
        parts += ln.map { part($0, cWhite) }
        parts.append(part(belly, cWhite))
        sil(parts)
        spots([body], [(46, 9, 56, 14, colors.saddle)])
        shade([body])
        head(P(76, 22), 19, tilt: -15 + tilt)
    }

    private func drawStretch() {
        shadow(52, 70)
        let tl = tail(bez(P(28, 34), P(18, 44), P(12, 58), P(20 + tailSway * 3, 72)), 4, 10.5)
        let h1 = furleg(P(34, 30), P(32, 9), 14, 10, seed: 1), h2 = furleg(P(41, 30), P(40, 9), 14, 10, seed: 2)
        let a1 = furleg(P(60, 16), P(90, 11), 12, 9.5, seed: 3), a2 = furleg(P(62, 11), P(93, 7), 12, 9.5, seed: 4)
        let body = tufty(48, 27, 56, 26, 12, 0.04, rot: -16)
        sil([tl, part(h1, cFar), part(a1, cFar), part(body, colors.body), part(h2, cWhite), part(a2, cWhite)])
        spots([body], [(42, 40, 46, 20, colors.saddle)])
        shade([body, h1, h2])
        head(P(80, 26), 19, tilt: -8)
    }

    /// 들어 올리면 축 늘어짐 (랙돌!)
    private func drawDangle() {
        let sw = tailSway
        let tl = tail(bez(P(52, 18), P(54, 8), P(60 + sw * 3, 4), P(68 + sw * 6, 3)), 3.5, 8)
        let lf = [furleg(P(43, 22), P(43, 6), 13, 10, seed: 1), furleg(P(58, 22), P(58, 7), 13, 10, seed: 2)]
        let body = pear(50, 36, 30, 40, 50, 12, 0.05)
        let ruff = tufty(51, 47, 36, 26, 12, 0.15, spiky: true)
        let arms = [furleg(P(41, 44), P(39, 28), 12, 9.5, seed: 3), furleg(P(60, 44), P(62, 28), 12, 9.5, seed: 4)]
        var parts: [Part] = [tl]
        parts += lf.map { part($0, cFar) }
        parts += [part(body, colors.body), part(ruff, cWhite)]
        parts += arms.map { part($0, cWhite) }
        sil(parts)
        spots([body], [(36, 30, 18, 30, colors.saddle), (66, 30, 16, 26, colors.saddle)])
        shade([body, lf[0], lf[1], arms[0], arms[1]])
        toesAt(P(43, 6), 10); toesAt(P(58, 7), 10); toesAt(P(39, 28), 9.5); toesAt(P(62, 28), 9.5)
        head(P(50, 66), 21, tilt: sw * 4)
    }

    /// 커서에 앞발로 매달리기 (갈고리 지점 50, 96)
    private func drawHang() {
        let k = kick, sw = tailSway
        let arms = [furleg(P(40, 62), P(46, 93), 13, 9.5, paw: 1.2, seed: 1), furleg(P(60, 62), P(54, 93), 13, 9.5, paw: 1.2, seed: 2)]
        let body = pear(50, 36, 32, 40, 44, 12, 0.05)
        let ruff = tufty(50, 46, 34, 22, 12, 0.15, spiky: true)
        let legs = [furleg(P(41, 24), P(38 + k * 3, 6), 14, 10, seed: 3), furleg(P(59, 24), P(62 - k * 3, 6), 14, 10, seed: 4)]
        let tl = tail(bez(P(50, 20), P(54, 10), P(60 + sw * 4, 5), P(68 + sw * 8, 2)), 3.5, 8)
        var parts: [Part] = [tl]
        parts += legs.map { part($0, cWhite) }
        parts += [part(body, colors.body), part(ruff, cWhite)]
        parts += arms.map { part($0, cWhite) }
        sil(parts)
        spots([body], [(36, 34, 18, 28, colors.saddle), (64, 34, 18, 28, colors.saddle)])
        shade([body, legs[0], legs[1]])
        head(P(50, 60), 19, tilt: sw * 3)
        sil([part(tufty(46, 93.5, 9, 7.5, 6, 0.06), cWhite), part(tufty(54, 93.5, 9, 7.5, 6, 0.06), cWhite)])
    }

    /// 창 가장자리에서 빼꼼 (몸은 창 뒤, 앞발로 가장자리를 잡음)
    private func drawPeek() {
        let hc = P(60, 58)
        NSGraphicsContext.saveGraphicsState()
        let r = NSAffineTransform()
        r.translateX(by: hc.x, yBy: hc.y)
        r.rotate(byDegrees: peekRot)
        r.translateX(by: -hc.x, yBy: -hc.y)
        r.concat()
        let body = tufty(20, 56, 44, 34, 12, 0.04)
        sil([part(body, colors.body),
             part(furleg(P(48, 36), P(57, 33), 11, 10, paw: 1.2), cFar),
             part(furleg(P(54, 32), P(65, 30), 11, 10, paw: 1.25, seed: 2), cWhite)])
        NSGraphicsContext.restoreGraphicsState()
        head(hc, 21, tilt: tilt)
    }

    // MARK: 머리 (랙돌 얼굴: 눈을 감싸는 회색 마스크 + 이마까지 올라가는 흰 V자 + 흰 주둥이)

    private func head(_ c: CGPoint, _ r: CGFloat, tilt: CGFloat = 0) {
        NSGraphicsContext.saveGraphicsState()
        let tr = NSAffineTransform()
        tr.translateX(by: c.x, yBy: c.y)
        tr.rotate(byDegrees: tilt)
        tr.concat()

        let tw = earTwitch * r * 0.12
        let pl = colors.pointLight, pt = colors.point
        let ears = [tri(P(-1.08 * r, 0.25 * r), P(-0.86 * r, 1.25 * r), P(-0.20 * r, 0.92 * r)),
                    tri(P(0.36 * r, 0.92 * r), P(0.98 * r, 1.25 * r + tw), P(1.16 * r, 0.25 * r))]
        let hp = tufty(0, -0.04 * r, 2.42 * r, 2.0 * r, 18, 0.03, cheek: 0.16, spiky: true)
        for e in ears { stroke(e, cOut, r * 0.2 + lw * 2) }
        stroke(hp, cOut, lw * 2)
        for e in ears { stroke(e, colors.ear, r * 0.2); fill(e, colors.ear) }
        fill(hp, cWhite)

        let inners: [[CGPoint]] = [[P(-0.90 * r, 0.42 * r), P(-0.80 * r, 1.04 * r), P(-0.38 * r, 0.82 * r)],
                      [P(0.52 * r, 0.82 * r), P(0.92 * r, 1.04 * r + tw * 0.8), P(1.0 * r, 0.42 * r)]]
        for inner in inners {
            let t = tri(inner[0], inner[1], inner[2])
            stroke(t, cInnerEar, r * 0.09); fill(t, cInnerEar)
            let bx = (inner[0].x + inner[2].x) / 2, by = (inner[0].y + inner[2].y) / 2
            for k: CGFloat in [-1, 0, 1] {
                let q0 = P(bx + k * r * 0.08, by - r * 0.06)
                let q1 = P(bx + k * r * 0.1 + (inner[1].x - bx) * 0.5, by + (inner[1].y - by) * 0.5)
                stroke(seg(q0, q1), NSColor.white.withAlphaComponent(0.9), r * 0.045)
            }
        }

        let fx = 0.12 * r
        // 회색 마스크 (아래쪽 경계는 부드럽게)
        NSGraphicsContext.saveGraphicsState()
        hp.addClip()
        let g = gradient([pl.withAlphaComponent(0), pl, mix(pl, pt, 0.5), pt], [0, 0.30, 0.75, 1])
        ctx.drawLinearGradient(g, start: P(0, -0.55 * r), end: P(0, 1.1 * r), options: [.drawsAfterEndLocation])
        softspot(-1.05 * r, 0.55 * r, 1.0 * r, 1.0 * r, pt.withAlphaComponent(0.8), hard: 0.3)
        softspot(1.15 * r, 0.55 * r, 1.0 * r, 1.0 * r, pt.withAlphaComponent(0.8), hard: 0.3)
        // 흰 V자: 이마의 가는 줄 → 눈 사이 → 주둥이와 볼까지 넓어짐
        var vp: [CGPoint] = []
        vp.append(P(fx, 1.08 * r)); vp.append(P(fx + 0.12 * r, 0.62 * r)); vp.append(P(fx + 0.2 * r, 0.22 * r))
        vp.append(P(fx + 0.34 * r, -0.10 * r)); vp.append(P(fx + 0.82 * r, -0.40 * r)); vp.append(P(fx + 1.25 * r, -0.55 * r))
        vp.append(P(fx + 1.3 * r, -1.3 * r)); vp.append(P(fx - 1.3 * r, -1.3 * r)); vp.append(P(fx - 1.25 * r, -0.55 * r))
        vp.append(P(fx - 0.80 * r, -0.40 * r)); vp.append(P(fx - 0.32 * r, -0.10 * r)); vp.append(P(fx - 0.18 * r, 0.22 * r))
        vp.append(P(fx - 0.11 * r, 0.62 * r))
        let v = smooth(vp, k: 0.18)
        fill(v, cWhite)
        stroke(v, cWhite.withAlphaComponent(0.45), r * 0.08)
        let furs: [(CGFloat, CGFloat, CGFloat)] = [(-0.75, 0.55, 1), (-0.95, 0.25, 1), (0.95, 0.55, -1), (1.1, 0.25, -1), (-0.35, 0.9, 1), (0.6, 0.92, -1)]
        for (x, y, d) in furs {
            stroke(seg(P(x * r, y * r), P(x * r + d * 0.12 * r, y * r + 0.16 * r)), NSColor.white.withAlphaComponent(0.25), r * 0.035)
        }
        NSGraphicsContext.restoreGraphicsState()

        for sx: CGFloat in [-1, 1] {
            for k in 0..<3 {
                let kk = CGFloat(k)
                let y = -0.45 * r - kk * 0.11 * r
                let x0 = sx * (1.02 * r - kk * 0.07 * r) + fx * 0.3
                detail(seg(P(x0, y), P(x0 + sx * 0.13 * r, y - 0.07 * r)), lw * 0.55)
            }
        }
        softspot(fx - 0.78 * r, -0.30 * r, 0.40 * r, 0.20 * r, rgb(0xFFA3B8, 0.45), hard: 0.2)
        softspot(fx + 0.82 * r, -0.30 * r, 0.40 * r, 0.20 * r, rgb(0xFFA3B8, 0.45), hard: 0.2)
        drawEye(P(fx - 0.47 * r, 0.04 * r), r)
        drawEye(P(fx + 0.49 * r, 0.04 * r), r)

        // 주둥이 볼록 + 턱
        softspot(fx, -0.62 * r, 0.75 * r, 0.30 * r, rgb(0x8C8AA0, 0.16), hard: 0.2)
        for sx: CGFloat in [-1, 1] { fill(oval(fx + sx * 0.17 * r, -0.44 * r, 0.40 * r, 0.30 * r), cWhite) }
        fill(oval(fx, -0.63 * r, 0.28 * r, 0.16 * r), cWhite)
        // 코
        let n = smooth([P(fx - 0.14 * r, -0.20 * r), P(fx + 0.14 * r, -0.20 * r), P(fx + 0.03 * r, -0.33 * r), P(fx - 0.03 * r, -0.33 * r)], k: 0.25)
        fill(n, rgb(0xEE97AA))
        stroke(n, rgb(0xD77D93), 0.5)
        fill(oval(fx - 0.04 * r, -0.235 * r, 0.1 * r, 0.05 * r), NSColor.white.withAlphaComponent(0.55))
        if mouth > 0.05 {
            fill(oval(fx, -0.56 * r, 0.22 * r, 0.26 * r * mouth), rgb(0x9C4A5E))
            fill(oval(fx, -0.62 * r, 0.14 * r, 0.10 * r * mouth), rgb(0xFF9AAE))
        } else {
            let m = NSBezierPath()
            m.move(to: P(fx, -0.33 * r)); m.line(to: P(fx, -0.42 * r))
            m.move(to: P(fx, -0.42 * r))
            m.curve(to: P(fx - 0.17 * r, -0.47 * r), controlPoint1: P(fx - 0.02 * r, -0.52 * r), controlPoint2: P(fx - 0.12 * r, -0.53 * r))
            m.move(to: P(fx, -0.42 * r))
            m.curve(to: P(fx + 0.17 * r, -0.47 * r), controlPoint1: P(fx + 0.02 * r, -0.52 * r), controlPoint2: P(fx + 0.12 * r, -0.53 * r))
            stroke(m, cOut.withAlphaComponent(0.75), lw * 0.6)
        }
        // 수염
        let wc = rgb(0x9A97A8, 0.4)
        let rows: [(CGFloat, CGFloat)] = [(-0.42, -0.36), (-0.50, -0.62)]
        for sx: CGFloat in [-1, 1] {
            for (dy, ey) in rows {
                let x0 = fx + sx * 0.30 * r
                let w = NSBezierPath()
                w.move(to: P(x0, dy * r))
                w.curve(to: P(x0 + sx * 1.15 * r, ey * r), controlPoint1: P(x0 + sx * 0.5 * r, dy * r + 0.02 * r),
                        controlPoint2: P(x0 + sx * 0.9 * r, ey * r + 0.04 * r))
                stroke(w, wc, 0.5)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawEye(_ p: CGPoint, _ r: CGFloat) {
        let state: EyeState = (blink && (eye == .open || eye == .wide)) ? .closed : eye
        switch state {
        case .open, .wide, .slow:
            let big: CGFloat = state == .wide ? 1.08 : 1.0
            let w = r * 0.46 * big, h = r * 0.47 * big
            let lx = look.x * r * 0.05, ly = look.y * r * 0.04
            let cx = p.x + lx * 0.4, cy = p.y + ly * 0.4
            fill(oval(cx, cy, w * 1.12, h * 1.12), rgb(0x4A4E60, 0.55))
            fill(oval(cx, cy, w, h), rgb(0x1B2142))
            NSGraphicsContext.saveGraphicsState()
            oval(cx, cy, w * 0.86, h * 0.86).addClip()
            let g = gradient([rgb(0x8CCBF5), rgb(0x3F7FD2), rgb(0x1D3C8A)], [0, 0.55, 1])
            ctx.drawRadialGradient(g, startCenter: P(cx, cy - h * 0.25), startRadius: 0, endCenter: P(cx, cy), endRadius: w * 0.5,
                                   options: [.drawsAfterEndLocation])
            NSGraphicsContext.restoreGraphicsState()
            fill(oval(p.x + lx, p.y + ly, w * 0.58, h * 0.60), rgb(0x10121C))
            fill(oval(p.x + lx - w * 0.2, p.y + ly + h * 0.2, w * 0.34, h * 0.30), .white)
            fill(oval(p.x + lx + w * 0.2, p.y + ly - h * 0.18, w * 0.13, w * 0.13), NSColor.white.withAlphaComponent(0.95))
            if state == .slow {   // 반쯤 감은 눈 (천천히 눈 깜빡임 = 고양이식 사랑 표현)
                NSGraphicsContext.saveGraphicsState()
                oval(cx, cy, w * 1.15, h * 1.15).addClip()
                fill(NSBezierPath(rect: CGRect(x: cx - w, y: cy + h * 0.02, width: 2 * w, height: h)), colors.pointLight)
                NSGraphicsContext.restoreGraphicsState()
                stroke(seg(P(cx - w * 0.55, cy + h * 0.02), P(cx + w * 0.55, cy + h * 0.02)), cOut, lw)
            }
        case .closed, .happy:
            let up: CGFloat = state == .happy ? 1 : -1
            let y0 = state == .happy ? p.y - 0.05 * r : p.y + 0.02 * r
            let a = NSBezierPath()
            a.move(to: P(p.x - 0.19 * r, y0))
            a.curve(to: P(p.x + 0.19 * r, y0),
                    controlPoint1: P(p.x - 0.09 * r, y0 + up * 0.19 * r),
                    controlPoint2: P(p.x + 0.09 * r, y0 + up * 0.19 * r))
            stroke(a, cOut, lw * 1.1)
        }
    }
}

// MARK: - 고양이 (행동)

/// 활동량 설정별 행동 확률
struct Energy {
    let sleepBase: Double, sleepCap: Double, awakeDiv: Double
    let sleepDur: ClosedRange<Double>, idle: ClosedRange<Double>
    let chase: Double, parkour: Double, hops: ClosedRange<Int>
    let hideTop: Double, hideFloor: Double, climb: Double
    let move: Double      // 걷기·빙글·우다다 비율

    static let levels: [Energy] = [
        // 차분하게: 대부분 구석에서 자고, 가끔 나와서 조금 놀다가 다시 잠
        Energy(sleepBase: 0.35, sleepCap: 0.75, awakeDiv: 120, sleepDur: 90...240, idle: 5...14,
               chase: 0.10, parkour: 0.14, hops: 1...3, hideTop: 0.2, hideFloor: 0.05, climb: 0.14, move: 0.6),
        // 보통
        Energy(sleepBase: 0.15, sleepCap: 0.5, awakeDiv: 250, sleepDur: 40...120, idle: 3...9,
               chase: 0.22, parkour: 0.22, hops: 1...4, hideTop: 0.3, hideFloor: 0.1, climb: 0.15, move: 0.85),
        // 활발하게 (예전 그대로)
        Energy(sleepBase: 0.0, sleepCap: 0.4, awakeDiv: 400, sleepDur: 20...50, idle: 2.5...7,
               chase: 0.35, parkour: 0.4, hops: 2...6, hideTop: 0.35, hideFloor: 0.15, climb: 0.22, move: 1.0),
    ]
}

struct Surface { var minX: CGFloat; var maxX: CGFloat; var y: CGFloat; var isFloor: Bool }
struct Win { let rect: CGRect; let id: Int; var pid: Int = 0 }

enum HideKind { case top, bottom, left, right, cornerL, cornerR }
struct PeekSpot {
    let kind: HideKind
    let edge: CGPoint        // 창 가장자리 위의 점
    let dir: CGPoint         // 바깥쪽 방향
    let facingRight: Bool
    let rot: CGFloat         // 몸 방향 (그림 기준)
    let tilt: CGFloat        // 머리 기울기
    let hidden: CGFloat      // 완전히 숨었을 때 머리가 가장자리 안쪽으로 들어가는 거리 (머리 반지름 배수)
}
struct SideEntry { let id: Int; let right: Bool; let edge: CGFloat }
enum HidePhase { case sinking, walkingIn, peeking }

enum CatState {
    case idle, walk, run, crouch, jump, fall, sleep, groom, stretch, dragged, happy, surprised
    case knead, roll, spin, hide, hang, zoom, land, yawn, watch
}

final class CatWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// macOS가 메뉴바와 겹치는 창을 아래로 밀어내지 않게 (고양이 창은 위쪽 여백이 커서 화면 위쪽에서 밀려 내려갔음)
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

let gravity: CGFloat = 2400

@MainActor
final class Cat {
    unowned let app: AppDelegate
    let window: CatWindow
    let view: CatView
    var colors: PointColor { didSet { view.colors = colors; view.needsDisplay = true } }
    var breed: Breed { didSet { view.breed = breed; view.needsDisplay = true } }
    var s: CGFloat
    var origin: CGPoint
    var vel = CGPoint.zero
    var state: CatState = .fall
    var stateT: Double = 0
    var stateDur: Double = 0
    var targetX: CGFloat = 0
    var surface = Surface(minX: 0, maxX: 0, y: 0, isFloor: true)
    var idlePose: Pose = .sit
    var facingRight = Bool.random()
    var t = Double.random(in: 0...10)
    var nextBlink: Double = 2
    var blinkUntil: Double = 0
    var earUntil: Double = 0
    var fxT: Double = 0
    var awake: Double = 0
    var supportT: Double = 0
    var fallStartY: CGFloat = 0
    var dragHist: [(Double, CGPoint)] = []
    var pounce = CGPoint.zero
    var grabbing = false
    var tiltNow: CGFloat = 0
    var lastMouse = CGPoint.zero
    var stillT: Double = 0
    var askedTilt = false
    var pendingSleep = false
    var pendingSide: SideEntry?
    var zoomLeft = 0
    var parkourHops = 0
    var strideT: Double = 0
    var pendingJump: CGPoint?
    var pounceLand: CGFloat?
    var loafKey = "loaf"
    var hangKey = "hang1"
    var peekKey = "peek"
    var idleKey = "sit"
    // 숨기
    var hideWin: Int?
    var hideRect = CGRect.zero
    var hidePhase: HidePhase = .peeking
    var spot: PeekSpot?
    var spotsLeft = 0
    var peek: CGFloat = 0
    var plan: [(CGFloat, Double)] = []
    var planHold: Double = 0
    var sinkTo: CGFloat = 0
    var launchRect: CGRect?
    // 매달리기
    var hangA: CGFloat = 0
    var hangW: CGFloat = 0
    var prevMouse = CGPoint.zero
    var prevMouseV = CGPoint.zero
    // 투명 발판으로 이동 · 커서 찾아가기 · 같이 보기
    var comeMode: ComeMode?
    var comeSpot = CGPoint.zero
    var trekHops = 0
    var waitingCursor = false
    var waitSleepAt: Double = 25
    var waitLoafAt: Double = 25
    var waitT: Double = 0
    var waitKey: String?
    var waitKeyUntil: Double = 0
    var waitNextAct: Double = 0
    var visited = false
    var pendingWatch = false
    var groomNext = false
    var buttWiggle = false
    var lastKeyReact: Double = -10   // 키보드 반응 쿨타임
    var tiltUntil: Double = 0        // 이때까지 갸웃 (지우기 연타 등)
    var companyPending = false       // 타자 치는 창 위로 같이 있으러 가는 중
    var crazyUntil: Double = 0       // Crazy cat mode 끝나는 시각
    var crazyOn = false
    var crazy: Bool { t < crazyUntil }
    let tailPhase = Double.random(in: 0...3)   // 고양이마다 꼬리 박자가 다르게          // 이번 웅크림은 덮치기 전 엉덩이 씰룩           // 들려서 옮겨진 뒤 내려오면 털 정리
    // 제자리 걷기·달리기 감지
    var progX: CGFloat = 0
    var progT: Double = 0
    var moveStartX: CGFloat = -9999
    var moveStartT: Double = 0
    var moveRepeats = 0

    var R: CGFloat { (Sprites.shared.ok ? 17 : 21) * s }
    /// 숨을 때 머리를 더 깊이 넣어야 하는 배수 (그림은 귀와 털이 큼)
    var hideDepth: CGFloat { Sprites.shared.ok ? 1.45 : 1 }

    func syncWindow() { window.setFrameOrigin(P(origin.x - MX * s, origin.y)) }
    var cx: CGFloat { origin.x + 50 * s }
    var footY: CGFloat { origin.y + 6 * s }

    init(app: AppDelegate, breed: Breed, scale: CGFloat, at p: CGPoint) {
        self.app = app
        self.colors = .blue
        self.breed = breed
        self.s = scale
        origin = P(p.x - 50 * scale, p.y - 6 * scale)
        let frame = CGRect(x: origin.x - MX * scale, y: origin.y, width: (100 + 2 * MX) * scale, height: (100 + MT) * scale)
        window = CatWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        view = CatView(frame: CGRect(origin: .zero, size: frame.size))
        view.colors = colors
        view.breed = breed
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.cat = self
        window.orderFrontRegardless()
        startFall()
    }

    // MARK: 상태 전환

    func enter(_ st: CatState, dur: Double? = nil) {
        if st != .crouch { buttWiggle = false }
        if st == .walk || st == .run || st == .zoom {
            if abs(cx - moveStartX) < 6 * s && t - moveStartT < 4 { moveRepeats += 1 } else { moveRepeats = 0 }
            moveStartX = cx
            moveStartT = t
        }
        state = st
        stateT = 0
        fxT = 0
        switch st {
        case .idle:
            stateDur = dur ?? Double.random(in: app.energy.idle)
            idlePose = chance(0.3) ? .loaf : .sit
            idleKey = ["sit", "front", "lookup", "tilt", "blink"].randomElement()!
            loafKey = chance(0.5) ? "loaf" : "loafclosed"
            askedTilt = false
            waitingCursor = false
            waitKey = nil
        case .sleep: stateDur = dur ?? Double.random(in: app.energy.sleepDur) * nightFactor()
        case .watch: stateDur = Double.random(in: 240...480) / nightFactor()
        case .groom: stateDur = Double.random(in: 5...10)
        case .stretch: stateDur = 1.8
        case .happy: stateDur = 2.6
        case .surprised:
            stateDur = 0.9
            emit("!", color: rgb(0xFF5A5A), size: 16, dy: 22, vel: P(0, 8), life: 0.9)
        case .run: stateDur = 7
        case .crouch: stateDur = dur ?? 0.75
        case .land: stateDur = 0.35
        case .yawn: stateDur = 1.6
        case .knead: stateDur = Double.random(in: 5...9)
        case .roll: stateDur = Double.random(in: 5...9)
        case .spin:
            stateDur = 2.4
            emit("?", color: rgb(0x8A7BD8), size: 13, dy: 20, vel: P(0, 10), life: 1.2)
        case .hang: stateDur = Double.random(in: 4...9)
        default: stateDur = .infinity
        }
        if crazy {
            // 발광 중엔 쉬지 않고 다음 행동으로
            switch st {
            case .idle: stateDur = 0.12
            case .spin, .roll: stateDur = 0.9
            case .land: stateDur = 0.12
            case .groom, .stretch, .yawn, .knead, .happy, .surprised: stateDur = min(stateDur, 0.3)
            default: break
            }
        }
    }

    func startFall() {
        pendingJump = nil
        state = .fall
        stateT = 0
        fallStartY = footY
    }

    func land(on g: Surface) {
        origin.y = g.y - 6 * s
        vel = .zero
        surface = g
        if launchRect != nil { restoreLevel() }
        if pendingSleep && g.isFloor {
            goSleepInCorner()
        } else if pendingWatch && g.isFloor {
            goWatch()
        } else if state == .fall && fallStartY - g.y > 350 {
            enter(.surprised)
        } else if state == .fall && groomNext {
            groomNext = false
            enter(.groom)                    // 들려 다녀서 흐트러진 털 정리
        } else if state == .jump || comeMode != nil {
            if comeMode == nil && parkourHops > 0 { parkourHops -= 1 }
            enter(.land)
        } else {
            enter(.idle, dur: Double.random(in: 1.2...3.5))
        }
    }

    var margin: CGFloat { surface.isFloor ? 45 * s : 12 * s }

    func clearPlans() {
        pendingSleep = false; pendingSide = nil; pendingJump = nil; parkourHops = 0
        comeMode = nil; trekHops = 0; pendingWatch = false; waitingCursor = false; companyPending = false
    }

    /// 창 사이를 건물 옥상처럼 뛰어다니기: 가장자리까지 달려가서 → 웅크렸다가 → 다음 창으로 점프
    @discardableResult
    func startParkourHop() -> Bool {
        guard app.climb, let tg = app.parkourTarget(cx: cx, footY: footY, surface: surface, s: s) else {
            parkourHops = 0
            return false
        }
        let rise = tg.y - footY
        if rise > 170 * s || (rise > 90 * s && abs(tg.x - cx) > 420 * s) {
            startCome(.spot, spot: tg)      // 한 번에 못 가는 곳은 투명 발판을 밟고 올라감
            return true
        }
        let dir: CGFloat = tg.x > cx ? 1 : -1
        var takeoff: CGFloat
        if surface.isFloor {
            takeoff = tg.x - dir * min(abs(tg.x - cx), CGFloat.random(in: 70...160) * s)
        } else if tg.x > surface.maxX || tg.x < surface.minX {
            takeoff = dir > 0 ? surface.maxX - 8 * s : surface.minX + 8 * s
        } else {
            takeoff = cx
        }
        takeoff = clampf(takeoff, surface.minX + 8 * s, surface.maxX - 8 * s)
        pendingJump = tg
        targetX = takeoff
        if abs(takeoff - cx) < 4 * s { beginLeap() } else { enter(.walk) }
        return true
    }

    private func beginLeap() {
        guard let tg = pendingJump else { enter(.idle); return }
        pendingJump = nil
        let extra = CGFloat.random(in: 50...110) * s
        pounce = P(tg.x, max(tg.y, footY) + extra)
        pounceLand = tg.y
        enter(.crouch, dur: 0.22)
    }

    func startWalkRandom() {
        clearPlans()
        let lo = surface.minX + margin, hi = surface.maxX - margin
        let d = CGFloat.random(in: 80...350) * (Bool.random() ? 1 : -1)
        targetX = clampf(cx + d, lo, hi)
        enter(.walk)
    }

    func jump(toX x: CGFloat, landY: CGFloat, peak: CGFloat? = nil) {
        let pk = max(peak ?? (max(landY, footY) + 70 * s), footY + 20, landY + 20)
        let vy = sqrt(2 * gravity * (pk - footY))
        let t1 = vy / gravity
        let t2 = sqrt(2 * (pk - landY) / gravity)
        vel = P((x - cx) / (t1 + t2), vy)
        facingRight = vel.x >= 0
        state = .jump
        stateT = 0
        fallStartY = pk
    }

    /// 졸리면 화면 구석으로 가서 잠
    func goSleepInCorner() {
        guard surface.isFloor else {
            pendingSleep = true
            leaveSurface()
            return
        }
        comeMode = nil
        let jitter = CGFloat(app.cats.firstIndex { $0 === self } ?? 0) * 70 * s + CGFloat.random(in: 0...15) * s
        let left = surface.minX + 48 * s + jitter
        let right = surface.maxX - 48 * s - jitter
        let goLeft = abs(cx - left) < abs(cx - right)
        targetX = goLeft ? left : right
        if abs(targetX - cx) < 4 * s {
            facingRight = goLeft
            pendingSleep = false
            awake = 0
            enter(.sleep)
        } else {
            pendingSleep = true
            enter(.walk)
        }
    }

    func chooseNext(_ mouse: CGPoint) {
        if crazy { crazyNext(); return }
        let dist = hypot(mouse.x - cx, mouse.y - footY)
        let e = app.energy
        // 영상을 보고 있으면 옆에 와서 같이 봄
        if app.watching && chance(0.8) { goWatch(); return }
        // 커서가 오래 가만히 있으면 곁으로 찾아감
        if app.chase && !visited && stillT > 25 && dist > 160 * s {
            visited = true          // 커서가 멈춰 있는 동안 한 번만 고민함
            let needsJumps = mouse.y - footY > 120 * s
            if chance(needsJumps ? 0.2 : 0.4) { startCome(.visit); return }
        }
        // 졸리면 먼저 구석으로 가서 잠 (차분할수록 자주, 오래 · 밤에는 더 자주)
        let nf = nightFactor()
        let sleepChance = min(nf > 1 ? min(0.92, e.sleepCap * 1.25) : e.sleepCap, (e.sleepBase + awake / e.awakeDiv) * nf)
        if chance(sleepChance) { goSleepInCorner(); return }
        // 모니터가 여러 개면 가끔 다른 모니터로 놀러 감
        if NSScreen.screens.count > 1 && surface.isFloor && chance(0.02 + 0.05 * e.move), let spot = app.otherScreenSpot(from: self) {
            startCome(.spot, spot: spot)
            return
        }
        if app.chase && chance(e.chase) {
            let high = mouse.y - footY > 200 * s || (!surface.isFloor && mouse.y < footY - 60 * s)
            if high && dist < 1300 && chance(0.25) { startCome(.chase); return }     // 높은 곳의 커서는 가끔만 발판을 밟고 쫓아감
            if dist < 420 { enter(.run); return }
        }
        if app.climb && chance(e.parkour) {
            parkourHops = Int.random(in: e.hops)
            if startParkourHop() { return }
        }

        if app.hideEnabled {
            if !surface.isFloor && chance(e.hideTop), let w = app.windowUnder(surface: surface, x: cx, s: s),
               !app.peekSpots(id: w.id, rect: w.rect, s: s).isEmpty {
                beginSink(w)
                return
            }
            if surface.isFloor && chance(e.hideFloor), let se = app.sideEntry(cx: cx, footY: footY, s: s) {
                clearPlans()
                pendingSide = se
                targetX = se.edge
                enter(.walk)
                return
            }
        }
        if app.climb && chance(e.climb), let tg = app.jumpTarget(fromX: cx, footY: footY, s: s) {
            if tg.y - footY > 170 * s { startCome(.spot, spot: tg) } else { jump(toX: tg.x, landY: tg.y) }
            return
        }
        // 투명 발판 위에서는 아래(창이나 바닥)로 한 번에 뛰어내림
        if app.onPlatform(self) && chance(0.35) {
            jumpDown()
            return
        }
        if !surface.isFloor && chance(0.2) {
            clearPlans()
            leaveSurface()
            return
        }
        let r = Double.random(in: 0..<1)
        if r < 0.24 * e.move { startWalkRandom() }
        else if r < 0.24 * e.move + 0.22 { enter(.groom) }
        else if r < 0.24 * e.move + 0.28 { enter(.stretch) }
        else if r < 0.24 * e.move + 0.37 { enter(.knead) }
        else if r < 0.24 * e.move + 0.44 { enter(.roll) }
        else if r < 0.24 * e.move + 0.44 + 0.04 * e.move { enter(.spin) }
        else if r < 0.24 * e.move + 0.44 + 0.08 * e.move && surface.isFloor { startZoomies() }
        else { enter(.idle) }
    }

    func startZoomies() {
        clearPlans()
        zoomLeft = Int.random(in: 3...5)
        targetX = Bool.random() ? surface.minX + margin : surface.maxX - margin
        enter(.zoom)
    }

    // MARK: 투명 발판으로 이동

    func startCome(_ mode: ComeMode, spot: CGPoint = .zero) {
        let hops = parkourHops, sleepy = pendingSleep, watch = pendingWatch
        clearPlans()
        if mode == .spot { parkourHops = hops; pendingSleep = sleepy; pendingWatch = watch }
        comeMode = mode
        comeSpot = spot
        trekHops = 0
        continueCome()
    }

    private func comeGoal() -> CGPoint {
        if comeMode == .spot { return comeSpot }
        return app.cursorGoal(for: self, mouse: NSEvent.mouseLocation)
    }

    /// 목표까지 한 단계: 같은 높이면 걸어가고, 아니면 허공에 투명 발판을 만들어 폴짝
    func continueCome() {
        guard let mode = comeMode else { enter(.idle); return }
        let g = comeGoal()
        let dx = g.x - cx, dy = g.y - footY
        if abs(dy) < 14 * s && abs(dx) < 30 * s { arriveCome(mode); return }
        if abs(dy) < 14 * s && g.x > surface.minX + 4 * s && g.x < surface.maxX - 4 * s {
            targetX = g.x
            enter(.walk)
            return
        }
        trekHops += 1
        if trekHops > 16 { arriveCome(mode); return }
        let vis = app.visFor(P(cx, footY + 1))
        let stepX = CGFloat.random(in: 260...420) * s
        let stepUp = CGFloat.random(in: 130...190) * s
        // 투명 발판은 화면 가장자리에서 충분히 떨어뜨림 (끝에서 떨어질 때 벽에 막혀 되돌아오지 않게)
        var pLo = vis.minX + 130 * s, pHi = vis.maxX - 130 * s
        var tx: CGFloat
        var ty: CGFloat
        if abs(dx) <= stepX * 1.7 && dy <= stepUp * 1.3 && dy > -520 {
            tx = g.x
            ty = g.y
        } else if dy > 0 {
            ty = footY + min(dy, stepUp)
            if abs(dx) < stepX * 0.6 {
                // 거의 수직이면 계단처럼 좌우로 크게 지그재그 (막힌 쪽이면 반대쪽으로)
                var side: CGFloat = trekHops % 2 == 0 ? 1 : -1
                let w = CGFloat.random(in: 200...320) * s
                if cx + side * w > pHi || cx + side * w < pLo { side = -side }
                tx = cx + side * w
            } else {
                tx = cx + clampf(dx, -stepX, stepX)
            }
        } else {
            ty = max(g.y, footY - 360 * s)
            tx = cx + clampf(dx, -stepX * 1.4, stepX * 1.4)
        }
        // 다음 발 디딜 곳이 있는 모니터 안으로 (여러 모니터 사이도 건너감)
        let tvis = app.visFor(P(tx, ty))
        pLo = tvis.minX + 130 * s
        pHi = tvis.maxX - 130 * s
        tx = clampf(tx, tvis.minX + 60 * s, tvis.maxX - 60 * s)
        ty = max(tvis.minY, min(ty, tvis.maxY - 115 * s))
        if hypot(tx - cx, ty - footY) < 20 * s { arriveCome(mode); return }   // 더는 못 감
        let final = tx == g.x && ty == g.y
        // 창 윗면 가까이면 발판 대신 창 윗면에 정확히 착지. 바로 밑이 바닥이면 바닥, 아니면 투명 발판
        if let top = app.windowTopNear(x: tx, y: ty, tol: 90 * s) {
            ty = top
        } else {
            let real = app.ground(x: tx, fromY: ty + 3 * s, allowWindows: app.climb)
            if ty - real.y < 30 * s {
                ty = real.y
            } else {
                tx = clampf(tx, pLo, pHi)
                app.addPlatform(x: tx, y: ty, width: 150 * s)
            }
        }
        if final && mode == .spot { comeSpot = P(tx, ty) }   // 목표를 실제 착지점으로 맞춤
        leap(to: P(tx, ty))
    }

    /// 창이나 발판에서 내려가기. 끝에서 떨어져도 화면 벽에 막혀 같은 자리로 되돌아오지 않는 쪽으로만 걸어감.
    /// 양쪽이 다 막혔으면 (화면 끝에 붙은 발판·창) 투명 발판을 밟고 내려감
    func leaveSurface() {
        let all = app.allFrame
        var opts: [CGFloat] = []
        if surface.maxX + 6 * s < all.maxX - 45 * s { opts.append(surface.maxX + 30 * s) }
        if surface.minX - 6 * s > all.minX + 45 * s { opts.append(surface.minX - 30 * s) }
        if let x = opts.randomElement() {
            targetX = x
            enter(.walk)
            return
        }
        jumpDown(towardCenter: true)
    }

    /// 발판 없이 아래쪽 창 윗면이나 바닥으로 한 번에 뛰어내림
    func jumpDown(towardCenter: Bool = false) {
        let vis = app.screen(x: cx, y: footY + 1).visibleFrame
        let dir: CGFloat = towardCenter ? (cx > vis.midX ? -1 : 1) : (Bool.random() ? 1 : -1)
        let tx = clampf(cx + dir * CGFloat.random(in: 160...380) * s, vis.minX + 60 * s, vis.maxX - 60 * s)
        let g = app.ground(x: tx, fromY: footY - 40 * s, allowWindows: app.climb)
        jump(toX: tx, landY: g.y)
    }

    private func leap(to tg: CGPoint) {
        let top = app.screen(x: tg.x, y: tg.y).visibleFrame.maxY
        let low = max(tg.y, footY)
        let arc = CGFloat.random(in: 40...80) * s + abs(tg.x - cx) * 0.15
        let peak = min(low + arc, top - 95 * s)
        grabbing = false
        pounce = P(tg.x, max(peak, low + 20))
        pounceLand = tg.y
        facingRight = tg.x >= cx
        enter(.crouch, dur: 0.25)
    }

    private func arriveCome(_ mode: ComeMode) {
        comeMode = nil
        trekHops = 0
        let m = NSEvent.mouseLocation
        switch mode {
        case .chase:
            arrivedChase(m)
        case .greet:
            facingRight = m.x >= cx
            enter(.happy)
        case .visit:
            facingRight = m.x >= cx
            enter(.idle, dur: 3600)
            idlePose = .sit
            idleKey = "front"
            startWaiting()
        case .spot:
            if pendingSleep && surface.isFloor { goSleepInCorner(); return }
            if pendingWatch && surface.isFloor { goWatch(); return }
            if companyPending {
                // 타자 치는 창 위에서 식빵 자세로 같이 있어 줌
                companyPending = false
                enter(.idle, dur: Double.random(in: 60...150))
                idlePose = .loaf
                loafKey = "loaf"
                return
            }
            if parkourHops > 0 { parkourHops -= 1 }
            enter(.land)
        }
    }

    /// 커서 곁에서 시간 보내기 시작: 구경 → 이것저것 → 식빵 → 잠
    func startWaiting() {
        waitingCursor = true
        waitT = 0
        waitKey = nil
        waitNextAct = Double.random(in: 3...6)
        waitSleepAt = Double.random(in: 45...90) / nightFactor()
        waitLoafAt = waitSleepAt * Double.random(in: 0.5...0.65)
    }

    /// 커서 곁에서 할 작은 행동 하나 고르기 (그림 이름, 길이)
    private func pickWaitAct(_ m: CGPoint) {
        var opts: [(String, Double)] = [("groom", 3.2), ("blink", 1.6), ("tilt", 1.8), ("lookup", 2.2), ("front", 2.0)]
        let reach = abs(m.x - cx) < 110 * s && m.y > footY + 15 * s && m.y < footY + 150 * s
        if reach && breed == .siamese { opts += [("play", 1.1), ("play", 1.1)] }   // 앞발로 커서 툭
        if waitT > 15 { opts.append(("yawn", 1.4)) }
        let o = opts.randomElement()!
        waitKey = o.0
        waitKeyUntil = waitT + o.1
        if o.0 == "play" { facingRight = m.x > cx }
    }

    /// 꼬리 그림 번호 (1: 늘어뜨림, 2: 반쯤 듦, 3: 끝을 말아 올림).
    /// 평소에는 몇 초에 한 번 천천히, 집중할 땐 빠르게 탁탁 튕김
    func tailFrame(fast: Bool) -> Int {
        let period = fast ? 0.9 : 3.4
        let flick = fast ? 0.36 : 0.6
        let p = (t + tailPhase).truncatingRemainder(dividingBy: period)
        guard p < flick else { return 1 }
        let seq = [2, 3, 3, 2]
        return seq[min(seq.count - 1, Int(p / flick * Double(seq.count)))]
    }

    // MARK: Crazy cat mode

    /// 10초 동안 발광: 우다다, 붕붕 점프, 빙글빙글, 데굴데굴
    func goCrazy() {
        switch state {
        case .dragged, .hang: return
        default: break
        }
        if state == .hide { abortHide() }
        clearPlans()
        crazyUntil = t + 10
        crazyOn = true
        awake = 0
        emit("!", color: rgb(0xFF5A5A), size: 18, dy: 24, vel: P(0, 10), life: 0.9)
        switch state {
        case .jump, .fall, .crouch, .hide: return     // 착지하면 바로 시작
        default: crazyNext()
        }
    }

    func crazyNext() {
        let vis = app.visFor(P(cx, footY + 1))
        if !surface.isFloor && chance(0.5) { jumpDown(); return }
        let r = Double.random(in: 0..<1)
        if r < 0.3 && surface.isFloor {
            startZoomies()
            zoomLeft = Int.random(in: 2...3)
            return
        }
        if r < 0.62 {
            // 제자리에서 붕 높이 뛰기
            let tx = clampf(cx + CGFloat.random(in: -380...380) * s, vis.minX + 60 * s, vis.maxX - 60 * s)
            let g = app.ground(x: tx, fromY: footY + 5 * s, allowWindows: app.climb)
            jump(toX: tx, landY: g.y, peak: max(g.y, footY) + CGFloat.random(in: 120...240) * s)
            return
        }
        if r < 0.74, app.climb, let tg = app.jumpTarget(fromX: cx, footY: footY, s: s), tg.y - footY < 450 * s {
            jump(toX: tg.x, landY: tg.y)
            return
        }
        enter(r < 0.88 ? .spin : .roll)
    }

    // MARK: 키보드 반응

    private var keyCalm: Bool {
        switch state {
        case .idle, .groom, .knead, .happy, .land: return true
        default: return false
        }
    }

    /// Enter: 같이 신나서 제자리에서 폴짝
    func onEnter() {
        guard keyCalm, t - lastKeyReact > 1.2, chance(0.7) else { return }
        lastKeyReact = t
        if state == .idle && (waitingCursor || idlePose == .loaf) {
            // 커서 곁에서 쉬거나 식빵 중이면 귀만 쫑긋 (눈 깜빡)
            if waitingCursor { waitKey = "blink"; waitKeyUntil = waitT + 1.0 }
            return
        }
        jump(toX: cx + (facingRight ? 3 : -3) * s, landY: footY, peak: footY + CGFloat.random(in: 26...40) * s)
    }

    /// Enter를 연달아 누르거나 지우기를 마구 누르면: 갸웃 "?"
    func onConfusingKeys() {
        guard keyCalm, t - lastKeyReact > 1.5 else { return }
        lastKeyReact = t
        if state != .idle { enter(.idle, dur: 2.5) }
        if idlePose == .loaf { return }
        tiltUntil = t + 1.6
        emit("?", color: rgb(0x8A7BD8), size: 13, dy: 20, vel: P(0, 8), life: 1.1)
    }

    /// 한동안 타자를 치면, 그 창 위로 올라와 식빵 자세로 곁에 있어 줌
    func keepCompany(on r: CGRect) -> Bool {
        guard app.climb, keyCalm, !waitingCursor else { return false }
        let x = clampf(r.midX + CGFloat.random(in: -0.25...0.25) * r.width, r.minX + 60 * s, r.maxX - 60 * s)
        guard let top = app.windowTopNear(x: x, y: r.maxY, tol: 4) else { return false }
        startCome(.spot, spot: P(x, top))
        companyPending = true
        return true
    }

    /// 오래 타자를 치다 멈추면: 수고했다는 듯 기지개나 하품
    func typingBreak() {
        guard state == .idle, chance(0.6) else { return }
        enter(chance(0.5) ? .stretch : .yawn)
    }

    /// 갑자기 난 소리에 깜짝 놀라 깸
    func wakeStartled() {
        guard state == .sleep else { return }
        awake = 0
        facingRight.toggle()        // 소리 난 쪽으로 홱 돌아봄
        enter(.surprised)
    }

    /// 맥을 깨우면 반갑게 달려옴
    func greet() {
        switch state {
        case .dragged, .hang, .jump, .fall, .crouch: return
        default: break
        }
        awake = 0
        emit("!", color: rgb(0xFF5A5A), size: 16, dy: 22, vel: P(0, 8), life: 0.9)
        if state == .hide {
            abortHide()
            clearPlans()
            comeMode = .greet
            return
        }
        startCome(.greet)
    }

    // MARK: 같이 보기

    func startWatchingIfFree() {
        if crazy { return }
        switch state {
        case .idle, .groom, .knead, .roll, .spin, .happy, .land, .stretch: break
        case .walk:
            if comeMode != nil || pendingJump != nil || pendingSide != nil || pendingSleep { return }
        default: return
        }
        clearPlans()
        goWatch()
    }

    /// 영상 창 아래 모서리 쪽으로 가서 앉아 화면을 올려다봄
    func goWatch() {
        guard app.watching else { enter(.idle); return }
        let (x, fr) = app.watchSpot(for: self)
        if !surface.isFloor {
            pendingWatch = true
            leaveSurface()
            return
        }
        comeMode = nil
        if x < surface.minX || x > surface.maxX {
            // 영상이 다른 모니터에 있으면 그 모니터 바닥으로 건너감
            let v = app.visFor(P(x, app.watchRect.midY))
            pendingWatch = true
            startCome(.spot, spot: P(clampf(x, v.minX + 60 * s, v.maxX - 60 * s), v.minY))
            return
        }
        targetX = clampf(x, surface.minX + 45 * s, surface.maxX - 45 * s)
        if abs(targetX - cx) < 6 * s {
            pendingWatch = false
            facingRight = fr
            enter(.watch)
        } else {
            pendingWatch = true
            enter(.walk)
        }
    }

    func arrivedChase(_ m: CGPoint) {
        let dy = m.y - footY
        if abs(m.x - cx) < 70 * s && dy > -20 && dy < 320 {
            grabbing = dy > 60 * s && chance(0.6)       // 높이 있으면 매달리기 시도
            pounce = P(m.x, max(m.y, footY + 40 * s))
            enter(.crouch, dur: Double.random(in: 1.3...2.1))
            buttWiggle = true           // 몸을 낮추고 → 엉덩이 씰룩씰룩 → 잠깐 멈췄다가 → 덮침
        } else {
            enter(.idle, dur: Double.random(in: 2...4))
            idlePose = .sit
        }
    }

    // MARK: 숨기

    private func toBehind(_ id: Int, _ rect: CGRect) {
        hideWin = id
        hideRect = rect
        window.level = .normal
        window.order(.below, relativeTo: id)
    }

    func restoreLevel() {
        window.level = .floating
        window.orderFrontRegardless()
        hideWin = nil
        spot = nil
        launchRect = nil
    }

    /// 창 위에 있다가 창 뒤로 쏙
    func beginSink(_ w: Win) {
        clearPlans()
        toBehind(w.id, w.rect)
        hidePhase = .sinking
        sinkTo = w.rect.maxY - (Sprites.shared.ok ? 100 : 80) * s
        spotsLeft = Int.random(in: 2...4)
        idlePose = .sit
        state = .hide
        stateT = 0
    }

    /// 바닥에서 창 옆으로 걸어 들어가기
    func beginWalkIn(_ e: SideEntry) {
        guard let w = app.wins.first(where: { $0.id == e.id }) else { enter(.idle); return }
        pendingSide = nil
        toBehind(w.id, w.rect)
        hidePhase = .walkingIn
        let inward: CGFloat = (Sprites.shared.ok ? 100 : 80) * s
        targetX = e.right ? e.edge - inward : e.edge + inward
        facingRight = !e.right
        spotsLeft = Int.random(in: 2...4)
        state = .hide
        stateT = 0
    }

    private func placeAtSpot() {
        guard let sp = spot else { return }
        if Sprites.shared.ok, let info = Sprites.shared.set(breed)[peekKey] {
            let hU = (info.h * spriteK + 4) * s
            let dist = -(1 - peek) * hU
            let a = P(sp.edge.x + sp.dir.x * dist, sp.edge.y + sp.dir.y * dist)
            origin = P(a.x - 50 * s, a.y - 40 * s)
            return
        }
        let hid = sp.hidden * hideDepth
        let dist = -hid * R + peek * (hid + 0.3) * R
        let h = P(sp.edge.x + sp.dir.x * dist, sp.edge.y + sp.dir.y * dist)
        origin = P(h.x - (facingRight ? 60 : 40) * s, h.y - 58 * s)
    }

    private func nextSpot() {
        guard let id = hideWin else { enter(.idle); return }
        let all = app.peekSpots(id: id, rect: hideRect, s: s)
        let cands = all.filter { $0.kind != spot?.kind }
        guard let sp = cands.randomElement() ?? all.randomElement() else { abortHide(); return }
        spot = sp
        facingRight = sp.facingRight
        tiltNow = sp.tilt
        peekKey = (sp.kind == .cornerL || sp.kind == .cornerR) ? "peektilt" : ["peek", "peek", "peektilt", "peekeyes"].randomElement()!
        peek = 0
        placeAtSpot()
        hidePhase = .peeking
        var p: [(CGFloat, Double)] = []
        if chance(0.6) { p.append((0.45, Double.random(in: 0.6...1.4))) }
        p.append((1, Double.random(in: 1.6...3.2)))
        if chance(0.4) { p.append((0.5, Double.random(in: 0.4...0.9))); p.append((1, Double.random(in: 1...2))) }
        spotsLeft -= 1
        if spotsLeft <= 0 { p.append((-1, 0)) } else { p.append((0, 0.4)) }   // -1 = 튀어나오기
        plan = p
        planHold = Double.random(in: 0.3...0.9)
    }

    /// 숨어 있던 자리에서 밖으로 튀어나옴
    func launchFromHide() {
        guard let sp = spot else { abortHide(); return }
        launchRect = hideRect
        spot = nil
        hideWin = nil
        switch sp.kind {
        case .top, .cornerL, .cornerR:
            let up = max(30 * s, sp.edge.y - footY + 45 * s)
            vel = P(sp.dir.x * 160 + CGFloat.random(in: -40...40), sqrt(2 * gravity * up))
        case .left, .right:
            vel = P(sp.dir.x * 320, 520)
        case .bottom:
            vel = P(CGFloat.random(in: -60...60), 0)
        }
        state = .jump
        stateT = 0
        fallStartY = footY
    }

    func abortHide() {
        restoreLevel()
        vel = .zero
        startFall()
    }

    private func updateHide(_ dt: Double, _ fdt: CGFloat) {
        guard let id = hideWin else { enter(.idle); return }
        supportT += dt
        if supportT > 0.3 {
            supportT = 0
            guard let w = app.wins.first(where: { $0.id == id }), w.id == id,
                  abs(w.rect.minX - hideRect.minX) < 3, abs(w.rect.maxY - hideRect.maxY) < 3,
                  abs(w.rect.width - hideRect.width) < 3, abs(w.rect.height - hideRect.height) < 3 else {
                abortHide()
                return
            }
        }
        switch hidePhase {
        case .sinking:
            origin.y -= 140 * s * fdt
            if origin.y <= sinkTo { nextSpot() }
        case .walkingIn:
            let d = targetX - cx
            let step = min(abs(d), 90 * s * fdt) * (d > 0 ? 1 : -1)
            origin.x += step
            view.phase += abs(step) / (4.5 * s)
            if abs(d) < 2 * s { nextSpot() }
        case .peeking:
            if planHold > 0 {
                planHold -= dt
            } else if let step = plan.first {
                if step.0 < 0 { launchFromHide(); return }
                let d = step.0 - peek
                let sp: CGFloat = 2.2
                peek += d > 0 ? min(d, sp * fdt) : max(d, -sp * fdt)
                if abs(step.0 - peek) < 0.01 {
                    planHold = step.1
                    plan.removeFirst()
                }
            } else {
                nextSpot()
                return
            }
            placeAtSpot()
        }
    }

    // MARK: 매달리기

    private var hookOffset: CGPoint { P(50 * s, (Sprites.shared.ok ? 158 : 95) * s) }

    func startHang(_ m: CGPoint) {
        grabbing = false
        hangA = 0
        hangKey = chance(0.5) ? "hang1" : "hang2"
        hangW = vel.x * 0.002
        prevMouse = m
        prevMouseV = .zero
        enter(.hang)
    }

    /// 커서에 매달린 진자: 커서를 흔들면(가속) 몸이 반대로 쏠렸다가 흔들흔들
    func swing(_ mv: CGPoint, _ ax: CGFloat, _ fdt: CGFloat) {
        let push = clampf(ax * 0.0009, -60, 60)
        hangW += (-16 * sin(hangA) - push) * fdt
        hangW *= pow(0.55, fdt)
        hangA = clampf(hangA + hangW * fdt, -0.95, 0.95)
    }

    func dropFromHang(_ v: CGPoint = .zero) {
        vel = P(v.x * 0.3, max(0, v.y * 0.3))
        startFall()
    }

    // MARK: 상호작용

    func petted() {
        awake = max(0, awake - 30)
        switch state {
        case .sleep: enter(.surprised)
        case .hide:
            if hidePhase == .peeking && peek > 0.3 {
                emit("!", color: rgb(0xFF5A5A), size: 16, dy: 22, vel: P(0, 8), life: 0.9)
                launchFromHide()
            }
        case .hang:
            dropFromHang()
        case .roll, .knead:
            stateDur = max(stateDur, stateT + 3)
        case .jump, .fall, .dragged, .crouch: break
        default:
            comeMode = nil
            pendingWatch = false
            enter(.happy)
        }
    }


    func dragBegan() {
        if hideWin != nil || launchRect != nil { restoreLevel() }
        clearPlans()
        grabbing = false
        state = .dragged
        stateT = 0
        dragHist = []
        vel = .zero
        awake = 0
        hangA = 0
        hangW = 0
        prevMouse = NSEvent.mouseLocation
        prevMouseV = .zero
        dragTo(origin)
    }

    func dragTo(_ proposed: CGPoint) {
        // 그림 모드에서는 고양이 앞발이 커서에 오도록 (커서에 매달린 채로 옮겨짐)
        let m = NSEvent.mouseLocation
        let o = Sprites.shared.ok ? P(m.x - hookOffset.x, m.y - hookOffset.y) : proposed
        origin = o
        syncWindow()
        let now = CACurrentMediaTime()
        dragHist.append((now, o))
        dragHist.removeAll { now - $0.0 > 0.1 }
    }

    func dragEnded() {
        vel = .zero
        if let f = dragHist.first, let l = dragHist.last, l.0 - f.0 > 0.01 {
            let dt = CGFloat(l.0 - f.0)
            var v = P((l.1.x - f.1.x) / dt, (l.1.y - f.1.y) / dt)
            let mag = hypot(v.x, v.y)
            if mag > 2600 { v = P(v.x / mag * 2600, v.y / mag * 2600) }
            vel = v
        }
        groomNext = chance(0.5)
        startFall()
    }

    func teleport(to p: CGPoint) {
        if hideWin != nil || launchRect != nil { restoreLevel() }
        clearPlans()
        origin = P(p.x - 50 * s, p.y + 10)
        vel = .zero
        syncWindow()
        startFall()
    }

    func setScale(_ ns: CGFloat) {
        if hideWin != nil { abortHide() }
        let fx = cx, fy = footY
        s = ns
        origin = P(fx - 50 * s, fy - 6 * s)
        window.setFrame(CGRect(x: origin.x - MX * s, y: origin.y, width: (100 + 2 * MX) * s, height: (100 + MT) * s), display: true)
    }

    // MARK: 효과

    func emit(_ text: String, color: NSColor, size: CGFloat, dy: CGFloat = 18,
              vel v: CGPoint = P(0, 14), life: CGFloat = 1.6, dx: CGFloat = 0) {
        let h = view.headFR()
        var x = h.x + dx + CGFloat.random(in: -5...5)
        var vx = v.x
        if !facingRight { x = 100 - x; vx = -vx }
        view.particles.append(Particle(p: P(x, min(Sprites.shared.ok ? 112 : 90, h.y + dy)), v: P(vx, v.y), life: life,
                                       maxLife: life, text: text, color: color, size: size))
    }
    func emitText(_ str: String) {
        emit(str, color: rgb(0x6E6880), size: 10, dy: 24, vel: P(0, 10), life: 1.8)
    }

    // MARK: 매 프레임

    func update(_ dt: Double) {
        t += dt
        stateT += dt
        let fdt = CGFloat(dt)
        let mouse = NSEvent.mouseLocation
        var moved = false

        if hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 2 { stillT = 0; lastMouse = mouse } else { stillT += dt }
        if stillT < 1 { visited = false }
        if crazyOn && !crazy {
            // 발광이 끝나면 아무 일 없었다는 듯 그루밍
            crazyOn = false
            switch state {
            case .idle, .walk, .run, .zoom, .spin, .roll, .land:
                clearPlans()
                enter(.groom)
            default: break
            }
        }

        // 안전장치: 걷기·달리기가 제자리에서 반복되면 계획을 버리고 잠시 앉음
        if state == .walk || state == .run || state == .zoom {
            if abs(cx - progX) > 2 * s { progX = cx; progT = 0 } else { progT += dt }
            if progT > 1.0 || moveRepeats >= 3 {
                progT = 0
                moveRepeats = 0
                moveStartX = -9999
                clearPlans()
                enter(.idle, dur: Double.random(in: 3...6))
            }
        } else {
            progX = cx
            progT = 0
        }

        switch state {
        case .idle:
            awake += dt
            if stateT > stateDur { chooseNext(mouse) }
            if abs(mouse.x - cx) > 30 * s && (mouse.x > cx) != facingRight
                && hypot(mouse.x - cx, mouse.y - footY) < 500 && chance(dt * 0.8) {
                facingRight.toggle()
            }
            let near = hypot(mouse.x - cx, mouse.y - footY) < 260
            if stillT > 1.5 && near && !askedTilt {
                askedTilt = true
                emit("?", color: rgb(0x8A7BD8), size: 12, dy: 22, vel: P(0, 8), life: 1.2)
            }
            // 커서가 곁에 가만히 있으면 같이 시간을 보냄 (계속 쳐다보기만 하지 않음)
            if stillT > 4 && near && !waitingCursor { startWaiting() }
            if waitingCursor {
                waitT += dt
                if waitKey == nil && abs(mouse.x - cx) > 10 * s { facingRight = mouse.x > cx }
                if stillT < 0.3 {
                    waitingCursor = false
                    waitKey = nil
                    stateDur = stateT + Double.random(in: 1.5...3)
                } else if waitT > waitSleepAt {
                    // 그대로 커서 옆에서 잠듦
                    waitingCursor = false
                    waitKey = nil
                    awake = 0
                    enter(.sleep, dur: Double.random(in: 60...180) * nightFactor())
                } else {
                    stateDur = max(stateDur, stateT + 1)
                    if waitT > waitLoafAt {
                        waitKey = nil
                        idlePose = .loaf
                        loafKey = waitT > waitSleepAt - 10 ? "loafclosed" : "loaf"
                    } else {
                        if waitKey != nil && waitT > waitKeyUntil {
                            waitKey = nil
                            waitNextAct = waitT + Double.random(in: 4...8)
                        }
                        if waitKey == nil && waitT > waitNextAct { pickWaitAct(mouse) }
                    }
                }
            }
            if app.musicPlaying && idlePose != .loaf && chance(dt * 0.22) {
                emit("♪", color: rgb(0x8A7BD8), size: 11, dy: 22, vel: P(6, 12), life: 1.6)
            }

        case .walk, .run:
            awake += dt
            if state == .run {
                targetX = clampf(mouse.x, surface.minX + margin, surface.maxX - margin)
            }
            let fast = state == .run || pendingJump != nil || comeMode == .chase || comeMode == .greet
            let speed: CGFloat = (fast ? 230 : (pendingSide != nil || comeMode != nil ? 110 : 65)) * s * (crazy ? 1.7 : 1)
            let dx = targetX - cx
            if abs(dx) < 3 * s {
                if state == .run {
                    arrivedChase(mouse)
                } else if pendingJump != nil {
                    beginLeap()
                } else if comeMode != nil {
                    continueCome()
                } else if pendingWatch && surface.isFloor {
                    goWatch()
                } else if let e = pendingSide {
                    beginWalkIn(e)
                } else if pendingSleep && surface.isFloor {
                    goSleepInCorner()
                } else {
                    enter(.idle)
                }
            } else {
                facingRight = dx > 0
                let step = min(abs(dx), speed * fdt) * (dx > 0 ? 1 : -1)
                origin.x += step
                moved = true
                view.phase += abs(step) / (4.5 * s)
                if !surface.isFloor && (cx < surface.minX || cx > surface.maxX) {
                    vel = P(step / max(fdt, 0.001) * 0.5, 0)
                    pendingSide = nil
                    pendingJump = nil
                    startFall()
                }
            }
            if state == .run && stateT > stateDur { enter(.idle) }

        case .zoom:
            let dx = targetX - cx
            if abs(dx) < 3 * s {
                zoomLeft -= 1
                if zoomLeft <= 0 {
                    enter(.idle, dur: Double.random(in: 2...4))
                    idlePose = .sit
                } else {
                    targetX = targetX < cx + 1 ? surface.maxX - margin : surface.minX + margin
                    targetX = clampf(cx + (targetX - cx) * CGFloat.random(in: 0.4...1), surface.minX + margin, surface.maxX - margin)
                }
            } else {
                facingRight = dx > 0
                let step = min(abs(dx), 420 * s * fdt * (crazy ? 1.5 : 1)) * (dx > 0 ? 1 : -1)
                origin.x += step
                moved = true
                view.phase += abs(step) / (4.5 * s)
            }

        case .crouch:
            facingRight = pounce.x >= cx
            if stateT > stateDur {
                jump(toX: pounce.x, landY: pounceLand ?? footY, peak: pounce.y)
                pounceLand = nil
            }

        case .jump, .fall:
            let prevFoot = footY
            vel.y -= gravity * fdt
            origin.x += vel.x * fdt
            origin.y += vel.y * fdt
            moved = true
            if abs(vel.x) > 30 { facingRight = vel.x > 0 }
            if grabbing {
                let hook = P(origin.x + hookOffset.x, origin.y + hookOffset.y)
                if hypot(hook.x - mouse.x, hook.y - mouse.y) < 40 * s { startHang(mouse); break }
                if vel.y < -200 { grabbing = false }
            }
            if let lr = launchRect {
                let body = CGRect(x: origin.x + 20 * s, y: origin.y + 6 * s, width: 60 * s, height: 60 * s)
                if !body.intersects(lr) || stateT > 0.6 { restoreLevel() }
            }
            let all = app.allFrame
            if cx < all.minX + 40 * s { origin.x = all.minX + 40 * s - 50 * s; vel.x = abs(vel.x) * 0.3 }
            if cx > all.maxX - 40 * s { origin.x = all.maxX - 40 * s - 50 * s; vel.x = -abs(vel.x) * 0.3 }
            if origin.y + 90 * s > all.maxY { origin.y = all.maxY - 90 * s; if vel.y > 0 { vel.y = 0 } }
            if vel.y <= 0 {
                let g = app.ground(x: cx, fromY: prevFoot, allowWindows: app.climb)
                if footY <= g.y { land(on: g) }
            }

        case .hang:
            let mv = P((mouse.x - prevMouse.x) / max(fdt, 0.001), (mouse.y - prevMouse.y) / max(fdt, 0.001))
            let ax = (mv.x - prevMouseV.x) / max(fdt, 0.001)
            prevMouse = mouse
            prevMouseV = mv
            swing(mv, ax, fdt)
            origin = P(mouse.x - hookOffset.x, mouse.y - hookOffset.y)
            moved = true
            if hypot(mv.x, mv.y) > 4500 {
                emit("!", color: rgb(0xFF5A5A), size: 16, dy: 10, vel: P(0, 8), life: 0.9)
                dropFromHang(mv)
            } else if stateT > stateDur {
                dropFromHang(mv)
            }

        case .sleep:
            fxT += dt
            if fxT > 1.4 {
                fxT = 0
                emit(chance(0.5) ? "z" : "Z", color: rgb(0x7A8CC8), size: CGFloat.random(in: 9...12),
                     dy: 10, vel: P(7, 10), life: 2.0, dx: 8)
            }
            if stateT > stateDur { enter(.yawn) }

        case .happy:
            // 쓰다듬은 자리 털을 다시 정리하기도 함
            if stateT > stateDur { if chance(0.35) { enter(.groom) } else { enter(.idle) } }

        case .knead:
            fxT += dt
            if stateT > stateDur { enter(.idle) }

        case .roll:
            if stateT > stateDur { enter(.idle) }

        case .spin:
            view.phase += fdt * 14
            facingRight = Int(stateT / 0.22) % 2 == 0
            if stateT > stateDur {
                emit("@_@", color: rgb(0x8A7BD8), size: 10, dy: 20, vel: P(0, 8), life: 1.2)
                enter(.idle, dur: Double.random(in: 1.5...3))
            }

        case .groom:
            if stateT > stateDur { if comeMode != nil { continueCome() } else { enter(.idle) } }

        case .surprised:
            // 놀란 뒤엔 아무 일 없었다는 듯 그루밍하는 경우가 많음
            if stateT > stateDur {
                if comeMode != nil { continueCome() }
                else if chance(0.45) { enter(.groom) }
                else { enter(.idle) }
            }

        case .watch:
            awake += dt * 0.3
            if !app.watching { enter(.stretch) }
            else if stateT > stateDur { awake = 0; enter(.sleep) }

        case .yawn:
            if stateT > stateDur { enter(.stretch) }

        case .land:
            if stateT > stateDur {
                if comeMode != nil { continueCome() }
                else if parkourHops > 0 && startParkourHop() {}
                else { enter(.idle, dur: Double.random(in: 1.2...3)) }
            }

        case .stretch:
            // 기지개 뒤엔 그루밍으로 하루를 시작하기도 함
            if stateT > stateDur { if chance(0.45) { enter(.groom) } else { startWalkRandom() } }

        case .hide:
            updateHide(dt, fdt)
            moved = true

        case .dragged:
            // 옮기는 동안 커서 움직임에 따라 대롱대롱 흔들림
            let mv = P((mouse.x - prevMouse.x) / max(fdt, 0.001), (mouse.y - prevMouse.y) / max(fdt, 0.001))
            let ax = (mv.x - prevMouseV.x) / max(fdt, 0.001)
            prevMouse = mouse
            prevMouseV = mv
            swing(mv, ax, fdt)
        }

        // 발 밑이 사라졌는지 확인
        let grounded: Bool
        switch state {
        case .jump, .fall, .dragged, .hide, .hang: grounded = false
        default: grounded = true
        }
        if grounded {
            supportT += dt
            if supportT > 0.3 {
                supportT = 0
                if surface.isFloor {
                    let g = app.ground(x: cx, fromY: footY + 2, allowWindows: false)
                    if g.y < footY - 1 { startFall() }
                    else if g.y > footY + 1 { origin.y = g.y - 6 * s; moved = true }
                    surface.minX = g.minX; surface.maxX = g.maxX
                } else {
                    let g = app.ground(x: cx, fromY: surface.y + 2, allowWindows: true)
                    if g.isFloor || abs(g.y - surface.y) > 2 {
                        vel = .zero
                        pendingSide = nil
                        startFall()
                    } else {
                        surface = g
                    }
                }
            }
        }

        animate(dt, mouse)

        if !view.particles.isEmpty {
            for i in view.particles.indices {
                view.particles[i].p.x += view.particles[i].v.x * fdt
                view.particles[i].p.y += view.particles[i].v.y * fdt
                view.particles[i].life -= fdt
            }
            view.particles.removeAll { $0.life <= 0 }
        }

        if moved { syncWindow() }
        view.needsDisplay = true
    }

    private func animate(_ dt: Double, _ m: CGPoint) {
        let v = view
        v.facingRight = facingRight

        var plat: Plat? = nil
        switch state {
        case .jump, .fall, .dragged, .hang, .hide: break
        default:
            if !surface.isFloor {
                plat = app.plats.first { abs($0.y - surface.y) < 1 && cx >= $0.minX - 2 && cx <= $0.maxX + 2 }
            }
        }
        if let p = plat {
            v.platL = (p.minX - origin.x) / s
            v.platR = (p.maxX - origin.x) / s
            v.platA = min(1, v.platA + CGFloat(dt) * 5)
        } else {
            v.platA = 0
        }

        switch state {
        case .idle: v.pose = idlePose
        case .walk, .run, .crouch, .spin, .zoom: v.pose = .stand
        case .jump, .fall: v.pose = .jump
        case .sleep: v.pose = .sleep
        case .groom: v.pose = .groom
        case .stretch: v.pose = .stretch
        case .dragged: v.pose = .dangle
        case .happy, .surprised, .yawn, .land: v.pose = .sit
        case .knead: v.pose = .loaf
        case .roll: v.pose = .roll
        case .hang: v.pose = .hang
        case .watch: v.pose = stateT > 120 ? .loaf : .sit
        case .hide:
            switch hidePhase {
            case .sinking: v.pose = .sit
            case .walkingIn: v.pose = .stand
            case .peeking: v.pose = .peek
            }
        }
        if let sp = spot {
            v.peekRot = Sprites.shared.ok ? atan2(sp.dir.y, sp.dir.x) * 180 / .pi : sp.rot
        }
        v.animT = CGFloat(stateT)

        // 그림 고르기
        let running = state == .run || state == .zoom
            || (state == .walk && (pendingJump != nil || pendingSide != nil || comeMode == .chase || comeMode == .greet))
        let walking = running || state == .walk || state == .spin
        if walking { strideT += dt * (running ? 9 : 6.5) }
        let frame = Int(strideT) % 4
        // 달리기: 웅크림 → 쭉 뻗어 날기 → 착지 (전력 질주 느낌)
        let gallop = breed.gallop
        let gi = Int(strideT) % gallop.count
        v.bounce = running ? breed.bounces[gi % breed.bounces.count] : 0
        var key = "sit"
        switch state {
        case .idle:
            key = idlePose == .loaf ? loafKey : idleKey
            if idlePose != .loaf && m.y > footY + 110 * s && abs(m.x - cx) < 320 { key = "lookup" }   // 위에 있는 커서 올려다보기
            if idlePose != .loaf && askedTilt && stillT > 1.5 { key = "tilt" }                      // 갸웃
            if idlePose != .loaf && t < tiltUntil { key = "tilt" }                                    // 키보드 보고 갸웃
            if idlePose != .loaf, waitingCursor, let wk = waitKey {
                key = wk == "groom" ? (Int(stateT / 0.9) % 2 == 0 ? "groom" : "wash") : wk
            }
        case .walk:
            key = running ? gallop[gi] : "walk" + String(frame)
        case .run, .zoom: key = gallop[gi]
        case .spin: key = "walk" + String(frame)
        case .jump, .fall: key = "jump"
        case .land: key = "land"
        case .stretch: key = "stretch"
        case .crouch: key = "crouch"
        case .sleep: key = "sleep"
        case .yawn: key = "yawn"
        case .groom: key = Int(stateT / 0.9) % 2 == 0 ? "groom" : "wash"
        case .dragged: key = "hang1"
        case .hang: key = hangKey
        case .roll: key = "belly"
        case .happy: key = "blink"
        case .surprised: key = "startle"
        case .knead: key = "loaf"
        case .watch:
            // 화면을 올려다보다가, 갸웃했다가, 가끔 앞발로 툭. 오래 보면 식빵 자세로 졸기
            let c = stateT.truncatingRemainder(dividingBy: 18)
            if stateT > 120 { key = stateT > 200 ? "loafclosed" : "loaf" }
            else if stateT > 15 && c > 15.5 && c < 16.4 && breed == .siamese { key = "play" }
            else if c > 9 && c < 11 { key = "tilt" }
            else { key = "lookup" }
        case .hide:
            switch hidePhase {
            case .sinking: key = "sit"
            case .peeking: key = peekKey
            case .walkingIn: key = "back"
            }
        }
        // 꼬리를 따로 그린 그림이 있으면 꼬리를 움직임: 평소엔 가끔 살랑, 커서에 집중하거나 덮치기 직전엔 탁탁
        let spset = Sprites.shared.set(breed)
        if state == .idle && key == "sit" && spset["sitt1"] != nil {
            let focused = (hypot(m.x - cx, m.y - footY) < 260 * s && stillT < 2) || app.typingRate > 3
            key = "sitt" + String(tailFrame(fast: focused))
        } else if state == .crouch && key == "crouch" && spset["croucht1"] != nil {
            key = "croucht" + String(tailFrame(fast: true))
        }
        if Sprites.shared.set(breed)[key] == nil {   // 그림이 없으면 예전 그림으로
            key = key.hasPrefix("walk") || key.hasPrefix("run") || key == "jump" || key == "land" ? "stand" : "sit"
        }
        v.spriteKey = key
        v.hangAngle = hangA * 180 / .pi

        let near = hypot(m.x - cx, m.y - footY) < 260
        switch state {
        case .sleep, .groom, .stretch, .yawn: v.eye = .closed
        case .happy, .knead, .roll: v.eye = .happy
        case .surprised, .crouch, .zoom: v.eye = .wide
        case .dragged: v.eye = stateT.truncatingRemainder(dividingBy: 4) < 3 ? .happy : .open   // 랙돌은 안기면 축~
        case .hang: v.eye = stateT.truncatingRemainder(dividingBy: 3) < 1.8 ? .wide : .happy
        case .fall: v.eye = vel.y < -900 ? .wide : .open
        case .idle:
            // 커서가 곁에 오래 있으면 천천히 눈 깜빡임 (고양이식 "좋아해")
            v.eye = (stillT > 4 && near && t.truncatingRemainder(dividingBy: 3.2) < 1.3) ? .slow : .open
        default: v.eye = .open
        }

        if t > nextBlink {
            blinkUntil = t + 0.13
            nextBlink = t + Double.random(in: 2...6)
        }
        v.blink = t < blinkUntil

        let h = v.headFR()
        let hx = origin.x + (facingRight ? h.x : 100 - h.x) * s
        let hy = origin.y + h.y * s
        var dx = m.x - hx, dy = m.y - hy
        let d = max(1, hypot(dx, dy))
        let k = min(1, d / 120)
        dx = dx / d * k
        dy = dy / d * k
        v.look = (state == .walk || state == .run || state == .zoom) ? P(0.6, 0) : P(facingRight ? dx : -dx, dy)
        if state == .hang { v.look = P(0, 0.8) }

        let tf: Double
        switch state {
        case .happy, .crouch: tf = 9
        case .sleep: tf = 0.8
        case .run, .spin, .zoom: tf = 6
        case .dragged, .hang: tf = 3
        default: tf = 2.2
        }
        v.tailSway = CGFloat(sin(t * tf)) * (state == .sleep ? 0.3 : 1)
        v.breathe = state == .sleep ? CGFloat(sin(t * 1.3)) * 1.2 : CGFloat(sin(t * 2.4)) * 0.6

        var tiltGoal: CGFloat = 0
        v.mouth = 0
        switch state {
        case .stretch, .yawn:
            v.mouth = CGFloat(sin(Double.pi * min(1, stateT / stateDur)))
        case .groom:
            v.lick = CGFloat(sin(t * 9))
            v.mouth = 0.5 + 0.25 * CGFloat(sin(t * 9))
            tiltGoal = -12
        case .happy:
            tiltGoal = CGFloat(sin(t * 3)) * 7
        case .idle:
            if askedTilt && stillT > 1.5 { tiltGoal = 14 }   // 갸웃?
            else if app.musicPlaying && idlePose != .loaf { tiltGoal = CGFloat(sin(t * 4.2)) * 14 }   // 음악에 맞춰 까딱
        case .jump, .fall:
            if Sprites.shared.ok { tiltGoal = clampf(vel.y * 0.008, -14, 14) * (facingRight ? 1 : -1) }
        case .hide:
            tiltGoal = (spot?.tilt ?? 0) + (hidePhase == .peeking && peek > 0.8 ? CGFloat(sin(t * 1.7)) * 4 : 0)
        default: break
        }
        tiltNow += (tiltGoal - tiltNow) * min(1, CGFloat(dt) * 8)
        v.tilt = tiltNow

        v.crouch = state == .crouch ? min(1, CGFloat(stateT) * 5) : 0
        if state == .crouch && buttWiggle {
            v.wiggle = 0
            let w0 = 0.3, w1 = stateDur - 0.25
            if stateT > w0 && stateT < w1 {
                let env = min(1, (stateT - w0) / 0.2) * min(1, (w1 - stateT) / 0.15)
                v.butt = CGFloat(sin((stateT - w0) * 2 * .pi * 3.4) * 3.8 * env)
            } else {
                v.butt = 0
            }
        } else {
            v.wiggle = state == .crouch ? CGFloat(sin(t * 32)) * 2.2 : 0
            v.butt = 0
        }
        v.kick = (state == .roll || state == .hang) ? CGFloat(sin(t * (state == .hang ? 7 : 5))) : 0
        v.knead = state == .knead ? CGFloat(sin(t * 6)) : 0

        if chance(dt * 0.3) { earUntil = t + 0.15 }
        v.earTwitch = t < earUntil ? 1 : 0
    }
}

// MARK: - 앱

final class BreedChoice: NSObject {
    let breed: Breed
    weak var cat: Cat?
    init(breed: Breed, cat: Cat?) { self.breed = breed; self.cat = cat }
}

final class Choice: NSObject {
    let colors: PointColor?
    let scale: CGFloat
    weak var cat: Cat?
    init(colors: PointColor? = nil, scale: CGFloat = 0, cat: Cat? = nil) {
        self.colors = colors; self.scale = scale; self.cat = cat
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var cats: [Cat] = []
    var statusItem: NSStatusItem?
    var timer: Timer?
    var lastTick = CACurrentMediaTime()
    var wins: [Win] = []            // 화면에 보이는 창들 (앞에 있는 것부터)
    var allFrame = CGRect.zero
    var winT: Double = 0
    let d = UserDefaults.standard

    var scale: CGFloat {
        get { CGFloat(d.double(forKey: "scale")) }
        set { d.set(Double(newValue), forKey: "scale") }
    }
    var chase: Bool { get { d.bool(forKey: "chase") } set { d.set(newValue, forKey: "chase") } }
    var climb: Bool { get { d.bool(forKey: "climb") } set { d.set(newValue, forKey: "climb") } }
    var hideEnabled: Bool { get { d.bool(forKey: "hide") } set { d.set(newValue, forKey: "hide") } }
    var hideIcon: Bool { get { d.bool(forKey: "hideIcon") } set { d.set(newValue, forKey: "hideIcon") } }
    /// 활동량: 0 차분하게, 1 보통, 2 활발하게
    var language: String { get { d.string(forKey: "language") ?? "system" } set { d.set(newValue, forKey: "language") } }
    var energyLevel: Int { get { d.integer(forKey: "energy") } set { d.set(newValue, forKey: "energy") } }
    var energy: Energy { Energy.levels[max(0, min(2, energyLevel))] }
    var watchEnabled: Bool { get { d.bool(forKey: "watch") } set { d.set(newValue, forKey: "watch") } }

    var plats: [Plat] = []          // 고양이가 허공에 만든 투명 발판
    var watching = false            // 영상 시청 중
    var musicPlaying = false        // 음악만 나오는 중
    var watchRect = CGRect.zero
    var videoT: Double = 0, noVideoT: Double = 0, musicT: Double = 0, noMusicT: Double = 0
    var silentT: Double = 0          // 소리가 안 난 시간
    var keysEnabled: Bool { get { d.bool(forKey: "keys") } set { d.set(newValue, forKey: "keys") } }
    // 타자 감지 (권한 없이: 마지막 키 입력 뒤 지난 시간만 봄)
    var lastKeySince: Double = 1e9
    var keyTimes: [Double] = []
    var typingRate: Double = 0       // 최근 3초 동안 초당 타자 수
    var typingFor: Double = 0        // 쉬지 않고 타자 친 시간
    var typingGap: Double = 0
    var companyDone = false
    // 키 구분 (손쉬운 사용 권한이 있을 때)
    var keyMonitor: Any?
    var enterTimes: [Double] = []
    var deleteTimes: [Double] = []
    var lastConfuse: Double = 0
    var trustCheckT: Double = 0
    var wordKeys: [UInt16] = []      // 지금 치고 있는 단어의 글자 키 (자판 위치 기준이라 한글 입력 중에도 됨)
    var catPendingAt: Double?        // "cat"까지 쳤고, 단어가 끝나는지 보는 중
    var lastGreet: Double = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        d.register(defaults: ["scale": 0.8, "chase": true, "climb": true, "hide": true,
                              "hideIcon": false, "cats": ["blue"], "energy": 0, "watch": true, "keys": true])
        refreshWindows()
        var list = (d.stringArray(forKey: "breeds") ?? []).compactMap { Breed(rawValue: $0) }
        if list.isEmpty { list = [.ragdoll] }
        for (i, c) in list.enumerated() { spawn(c, offset: CGFloat(i) * 120) }
        updateStatusItem()
        let tm = Timer(timeInterval: 1.0 / 50, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { Updater.shared.checkDaily() }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(didWake(_:)),
                                                            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    /// 잠자기·잠금에서 돌아오면 고양이들이 반갑게 달려옴
    @objc func didWake(_ n: Notification) {
        let now = CACurrentMediaTime()
        guard now - lastGreet > 20 else { return }
        lastGreet = now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.cats.forEach { $0.greet() }
        }
    }

    func spawn(_ c: Breed, offset: CGFloat = 0) {
        let scr = NSScreen.main ?? NSScreen.screens[0]
        let v = scr.visibleFrame
        let x = clampf(v.midX + offset + CGFloat.random(in: -200...200), v.minX + 80, v.maxX - 80)
        cats.append(Cat(app: self, breed: c, scale: scale, at: P(x, v.maxY - 150)))
    }

    func saveCats() { d.set(cats.map { $0.breed.rawValue }, forKey: "breeds") }

    @objc func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTick)
        lastTick = now
        winT += dt
        if winT > 0.5 { winT = 0; refreshWindows(); updateMedia(0.5) }
        updateTyping(now, dt)
        updatePlatforms()
        for c in cats { c.update(dt) }
    }

    // MARK: 창 정보

    func refreshWindows() {
        allFrame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.visibleFrame) }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            wins = []
            return
        }
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        var out: [Win] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let pid = info[kCGWindowOwnerPID as String] as? Int, pid == me { continue }
            if let a = info[kCGWindowAlpha as String] as? Double, a < 0.05 { continue }
            guard let num = info[kCGWindowNumber as String] as? Int,
                  let bd = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
            guard r.width >= 160, r.height >= 90 else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
            out.append(Win(rect: CGRect(x: r.minX, y: mainH - r.maxY, width: r.width, height: r.height), id: num, pid: pid))
        }
        wins = out
    }

    func screen(x: CGFloat, y: CGFloat) -> NSScreen {
        let scr = NSScreen.screens
        if let s = scr.first(where: { $0.frame.contains(P(x, y)) }) { return s }
        if let s = scr.first(where: { x >= $0.frame.minX && x < $0.frame.maxX }) { return s }
        return NSScreen.main ?? scr[0]
    }

    /// 점이 들어 있는 모니터의 보이는 영역. 어느 모니터에도 없으면 가장 가까운 모니터
    func visFor(_ p: CGPoint) -> CGRect {
        let scr = NSScreen.screens
        if let s = scr.first(where: { $0.visibleFrame.contains(p) }) { return s.visibleFrame }
        func dist(_ r: CGRect) -> CGFloat {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            return hypot(dx, dy)
        }
        return (scr.min { dist($0.visibleFrame) < dist($1.visibleFrame) } ?? NSScreen.main ?? scr[0]).visibleFrame
    }

    /// 나란히 붙은 모니터의 바닥 높이가 같으면 바닥을 하나로 이어 걸어서 건너갈 수 있게
    func floorSpan(_ vis: CGRect) -> (CGFloat, CGFloat) {
        var lo = vis.minX, hi = vis.maxX
        var changed = true
        while changed {
            changed = false
            for sc in NSScreen.screens {
                let v = sc.visibleFrame
                guard abs(v.minY - vis.minY) < 2 else { continue }
                if abs(v.maxX - lo) < 3 && v.minX < lo { lo = v.minX; changed = true }
                if abs(v.minX - hi) < 3 && v.maxX > hi { hi = v.maxX; changed = true }
            }
        }
        return (lo, hi)
    }

    /// 다른 모니터 바닥의 아무 지점 (모니터가 하나면 nil)
    func otherScreenSpot(from c: Cat) -> CGPoint? {
        let scr = NSScreen.screens
        guard scr.count > 1 else { return nil }
        let here = visFor(P(c.cx, c.footY + 1))
        let others = scr.map { $0.visibleFrame }.filter { $0 != here }
        guard let v = others.min(by: { hypot($0.midX - c.cx, $0.midY - c.footY) < hypot($1.midX - c.cx, $1.midY - c.footY) }) else { return nil }
        let x = CGFloat.random(in: (v.minX + 130 * c.s)...max(v.minX + 131 * c.s, v.maxX - 130 * c.s))
        return P(x, v.minY)
    }

    private func covered(_ p: CGPoint, before i: Int) -> Bool {
        wins[0..<i].contains { $0.rect.contains(p) }
    }

    func ground(x: CGFloat, fromY: CGFloat, allowWindows: Bool) -> Surface {
        let vis = screen(x: x, y: fromY).visibleFrame
        let (flo, fhi) = floorSpan(vis)
        var best = Surface(minX: flo, maxX: fhi, y: vis.minY, isFloor: true)
        for p in plats {
            guard x >= p.minX, x <= p.maxX, p.y <= fromY + 1, p.y > best.y else { continue }
            best = Surface(minX: p.minX, maxX: p.maxX, y: p.y, isFloor: false)
        }
        guard allowWindows else { return best }
        for (i, w) in wins.enumerated() {
            let r = w.rect, top = r.maxY
            guard x >= r.minX + 6, x <= r.maxX - 6, top <= fromY + 1, top > best.y,
                  top < vis.maxY - 40 else { continue }
            if covered(P(x, top + 2), before: i) { continue }
            best = Surface(minX: r.minX + 6, maxX: r.maxX - 6, y: top, isFloor: false)
        }
        return best
    }

    func jumpTarget(fromX x: CGFloat, footY: CGFloat, s: CGFloat) -> CGPoint? {
        let vis = screen(x: x, y: footY + 1).visibleFrame
        var cands: [CGPoint] = []
        for (i, w) in wins.enumerated() {
            let r = w.rect, top = r.maxY
            let dy = top - footY
            guard dy > 40, top < vis.maxY - 90 * s else { continue }
            let lo = max(r.minX + 30 * s, vis.minX + 45 * s)
            let hi = min(r.maxX - 30 * s, vis.maxX - 45 * s)
            guard hi > lo else { continue }
            let lx = clampf(x + CGFloat.random(in: -200...200), lo, hi)
            guard abs(lx - x) < 1100 else { continue }
            if covered(P(lx, top + 2), before: i) { continue }
            cands.append(P(lx, top))
        }
        return cands.randomElement()
    }

    /// 파쿠르: 지금 있는 곳에서 뛰어갈 만한 다른 창 윗면 (위로도 아래로도), 가끔은 바닥
    func parkourTarget(cx: CGFloat, footY: CGFloat, surface: Surface, s: CGFloat) -> CGPoint? {
        let vis = screen(x: cx, y: footY + 1).visibleFrame
        var cands: [(CGPoint, CGFloat)] = []
        for (i, w) in wins.enumerated() {
            let r = w.rect, top = r.maxY
            if !surface.isFloor && abs(top - surface.y) < 2 && cx >= r.minX && cx <= r.maxX { continue }   // 지금 서 있는 창
            let dy = top - footY
            guard dy > -520, top < vis.maxY - 90 * s, top > vis.minY + 30 * s else { continue }
            let lo = max(r.minX + 30 * s, vis.minX + 45 * s)
            let hi = min(r.maxX - 30 * s, vis.maxX - 45 * s)
            guard hi > lo else { continue }
            let nearLo = cx < (lo + hi) / 2
            let lx = clampf(nearLo ? lo + CGFloat.random(in: 0...90) * s : hi - CGFloat.random(in: 0...90) * s, lo, hi)
            let dx = abs(lx - cx)
            guard dx > 50 * s, dx < 1100 else { continue }
            if covered(P(lx, top + 2), before: i) { continue }
            cands.append((P(lx, top), dx + abs(dy) * 0.6))
        }
        if !surface.isFloor && (cands.isEmpty || chance(0.2)) {
            let fx = clampf(cx + CGFloat.random(in: 140...320) * (Bool.random() ? 1 : -1), vis.minX + 60 * s, vis.maxX - 60 * s)
            cands.append((P(fx, vis.minY), 9999))
        }
        guard !cands.isEmpty else { return nil }
        cands.sort { $0.1 < $1.1 }
        return cands.prefix(3).randomElement()?.0
    }

    // MARK: 투명 발판

    func addPlatform(x: CGFloat, y: CGFloat, width: CGFloat) {
        plats.append(Plat(minX: x - width / 2, maxX: x + width / 2, y: y, until: CACurrentMediaTime() + 6))
    }

    /// x 위치에서 높이 y 근처(±tol)에 있는, 올라설 수 있는 창 윗면
    func windowTopNear(x: CGFloat, y: CGFloat, tol: CGFloat) -> CGFloat? {
        guard climb else { return nil }
        let vis = screen(x: x, y: y).visibleFrame
        var best: CGFloat? = nil
        for (i, w) in wins.enumerated() {
            let r = w.rect, top = r.maxY
            guard x >= r.minX + 6, x <= r.maxX - 6, abs(top - y) < tol, top < vis.maxY - 40 else { continue }
            if covered(P(x, top + 2), before: i) { continue }
            if best == nil || abs(top - y) < abs(best! - y) { best = top }
        }
        return best
    }

    func onPlatform(_ c: Cat) -> Bool {
        !c.surface.isFloor && plats.contains { abs($0.y - c.surface.y) < 1 && c.cx >= $0.minX - 2 && c.cx <= $0.maxX + 2 }
    }

    /// 고양이가 올라가 있는 발판은 유지, 비어 있는 발판은 잠시 뒤 사라짐
    func updatePlatforms() {
        guard !plats.isEmpty else { return }
        let now = CACurrentMediaTime()
        for i in plats.indices {
            let p = plats[i]
            let used = cats.contains { c in
                switch c.state {
                case .jump, .fall, .dragged, .hang, .hide: return false
                default: return !c.surface.isFloor && abs(c.surface.y - p.y) < 1 && c.cx >= p.minX - 2 && c.cx <= p.maxX + 2
                }
            }
            if used { plats[i].until = max(p.until, now + 2.5) }
        }
        plats.removeAll { $0.until < now }
    }

    /// 커서 바로 옆, 고양이가 앉을 자리 (발 위치)
    func cursorGoal(for c: Cat, mouse m: CGPoint) -> CGPoint {
        let s = c.s
        let vis = screen(x: m.x, y: m.y).visibleFrame
        let idx = CGFloat(cats.firstIndex { $0 === c } ?? 0)
        let side: CGFloat = c.cx < m.x ? -1 : 1
        let gx = clampf(m.x + side * (55 + idx * 50) * s, vis.minX + 130 * s, vis.maxX - 130 * s)
        var gy = max(vis.minY, min(m.y - 55 * s, vis.maxY - 115 * s))
        if let top = windowTopNear(x: gx, y: gy, tol: 60 * s) {
            gy = top                            // 창 윗면 근처면 그 위에 앉음
        } else {
            let g = ground(x: gx, fromY: gy + 30 * s, allowWindows: climb)
            if gy - g.y < 45 * s { gy = g.y }  // 바로 밑에 바닥이 있으면 거기 앉음
        }
        return P(gx, gy)
    }

    // MARK: 같이 보기

    /// 소리가 나고, 앞에 있는 브라우저·영상 앱 창이 크면 "영상 보는 중". 소리만 나면 "음악"
    func updateMedia(_ dt: Double) {
        let audio = watchEnabled && audioPlaying()
        // 조용하다가 소리가 나기 시작하면 자던 고양이가 깜짝 놀라 깸
        if audio {
            if silentT >= 2 {
                for c in cats where c.state == .sleep {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...0.3)) { c.wakeStartled() }
                }
            }
            silentT = 0
        } else {
            silentT += dt
        }
        var video: CGRect? = nil
        if audio, let front = NSWorkspace.shared.frontmostApplication,
           videoApps.contains(front.bundleIdentifier ?? "") {
            let pid = Int(front.processIdentifier)
            let mine = wins.filter { $0.pid == pid }
            if let big = mine.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) {
                let f = screen(x: big.rect.midX, y: big.rect.midY).frame
                if big.rect.width * big.rect.height >= f.width * f.height * 0.3 { video = big.rect }
            }
        }
        if let r = video { watchRect = r; videoT += dt; noVideoT = 0 } else { noVideoT += dt; videoT = 0 }
        let was = watching
        if !watching && videoT >= 3 { watching = true }
        if watching && noVideoT >= 5 { watching = false }
        let music = audio && video == nil
        if music { musicT += dt; noMusicT = 0 } else { noMusicT += dt; musicT = 0 }
        if !musicPlaying && musicT >= 3 { musicPlaying = true }
        if musicPlaying && noMusicT >= 4 { musicPlaying = false }
        if watching && !was { for c in cats { c.startWatchingIfFree() } }
    }

    // MARK: 키보드

    /// 타자 치는 리듬 보기 (권한 필요 없음). 손쉬운 사용 권한이 생기면 키 구분도 켬
    func updateTyping(_ now: Double, _ dt: Double) {
        guard keysEnabled else { typingRate = 0; typingFor = 0; return }
        let since = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if since < lastKeySince - 0.0005 { keyTimes.append(now) }
        lastKeySince = since
        keyTimes.removeAll { now - $0 > 3 }
        typingRate = Double(keyTimes.count) / 3
        if since < 2.5 {
            typingFor += dt
            typingGap = 0
        } else {
            typingGap += dt
            if typingGap > 8 && typingFor > 60 {
                for c in cats { c.typingBreak() }      // 오래 치다 쉬면 같이 기지개
            }
            if typingGap > 8 { typingFor = 0; companyDone = false }
        }
        // 1분 반쯤 계속 치면, 한 마리가 그 창 위로 와서 곁에 있어 줌
        if typingFor > 90 && !companyDone && !watching {
            companyDone = true
            if chance(0.6), let front = NSWorkspace.shared.frontmostApplication {
                let pid = Int(front.processIdentifier)
                let mine = wins.filter { $0.pid == pid }
                if let r = mine.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })?.rect {
                    for c in cats.shuffled() where c.keepCompany(on: r) { break }
                }
            }
        }
        if let p = catPendingAt, now - p > 0.7 {         // "cat" 치고 잠깐 멈춤 → 단어 끝
            catPendingAt = nil
            wordKeys.removeAll()
            crazyMode()
        }
        trustCheckT -= dt
        if trustCheckT <= 0 {
            trustCheckT = 3
            if keyMonitor == nil && AXIsProcessTrusted() { installKeyMonitor() }
        }
    }

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let code = e.keyCode
            let rep = e.isARepeat
            let cmd = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control)
            DispatchQueue.main.async { self?.handleKey(code, isRepeat: rep, cmd: cmd) }
        }
    }

    func handleKey(_ code: UInt16, isRepeat: Bool, cmd: Bool = false) {
        guard keysEnabled else { return }
        let now = CACurrentMediaTime()
        // "cat"이라는 단어를 치면 Crazy cat mode (category 같은 단어 안의 cat은 무시)
        let letters: Set<UInt16> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 45, 46]
        if letters.contains(code) && !cmd {
            catPendingAt = nil
            wordKeys.append(code)
            if wordKeys.count > 8 { wordKeys.removeFirst() }
            if wordKeys == [8, 0, 17] { catPendingAt = now }      // c, a, t
        } else {
            if catPendingAt != nil && code != 51 && code != 117 { crazyMode() }
            catPendingAt = nil
            wordKeys.removeAll()
        }
        switch code {
        case 36, 76:   // Return, Enter
            if isRepeat { return }
            enterTimes.append(now)
            enterTimes.removeAll { now - $0 > 2 }
            if enterTimes.count >= 3 { confuse(now) } else { for c in cats { c.onEnter() } }
        case 51, 117:  // Delete, Forward Delete
            deleteTimes.append(now)
            deleteTimes.removeAll { now - $0 > 2 }
            if deleteTimes.count >= 8 { confuse(now) }
        default: break
        }
    }

    private func confuse(_ now: Double) {
        guard now - lastConfuse > 3 else { return }
        lastConfuse = now
        for c in cats { c.onConfusingKeys() }
    }

    /// 영상 창 아래 모서리 근처 자리와 바라볼 방향
    func watchSpot(for c: Cat) -> (CGFloat, Bool) {
        let r = watchRect
        let vis = screen(x: r.midX, y: r.midY).visibleFrame
        let idx = CGFloat(cats.firstIndex { $0 === c } ?? 0)
        let lo = max(r.minX, vis.minX) + (70 + idx * 60) * c.s
        let hi = min(r.maxX, vis.maxX) - (70 + idx * 60) * c.s
        let left = abs(c.cx - lo) <= abs(c.cx - hi)
        return (left ? lo : hi, left)
    }

    /// 고양이가 올라가 있는 창
    func windowUnder(surface: Surface, x: CGFloat, s: CGFloat) -> Win? {
        wins.first { abs($0.rect.maxY - surface.y) < 2 && x > $0.rect.minX && x < $0.rect.maxX }
    }

    /// 바닥까지 내려온 창의 옆 가장자리 (걸어서 창 뒤로 들어가기)
    func sideEntry(cx: CGFloat, footY: CGFloat, s: CGFloat) -> SideEntry? {
        let vis = screen(x: cx, y: footY + 1).visibleFrame
        var cands: [SideEntry] = []
        for (i, w) in wins.enumerated() {
            let r = w.rect
            guard r.minY <= footY + 3 * s, r.maxY >= footY + 95 * s, r.width > 200 * s, r.height > 130 * s,
                  !peekSpots(id: w.id, rect: r, s: s).isEmpty else { continue }
            let y = footY + 30 * s
            if r.maxX < vis.maxX - 60 * s && r.maxX > vis.minX + 60 * s && abs(r.maxX - cx) < 900
                && !covered(P(r.maxX + 4, y), before: i) && !covered(P(r.maxX - 20 * s, y), before: i) {
                cands.append(SideEntry(id: w.id, right: true, edge: r.maxX))
            }
            if r.minX > vis.minX + 60 * s && r.minX < vis.maxX - 60 * s && abs(r.minX - cx) < 900
                && !covered(P(r.minX - 4, y), before: i) && !covered(P(r.minX + 20 * s, y), before: i) {
                cands.append(SideEntry(id: w.id, right: false, edge: r.minX))
            }
        }
        return cands.randomElement()
    }

    /// 창 뒤에서 빼꼼할 수 있는 곳들: 위, 아래(거꾸로), 왼쪽/오른쪽 옆, 위쪽 두 모서리
    func peekSpots(id: Int, rect r: CGRect, s: CGFloat) -> [PeekSpot] {
        let R = (Sprites.shared.ok ? 17 : 21) * s
        let need: CGFloat = Sprites.shared.ok ? 8 : 5
        guard r.width > need * R, r.height > (need + 0.6) * R, let idx = wins.firstIndex(where: { $0.id == id }) else { return [] }
        func visible(_ p: CGPoint) -> Bool {
            NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: 4, dy: 4).contains(p) } && !covered(p, before: idx)
        }
        var out: [PeekSpot] = []
        func add(_ k: HideKind, _ e: CGPoint, _ d: CGPoint, _ fr: Bool, _ rot: CGFloat, _ tilt: CGFloat, _ hidden: CGFloat = 1.6) {
            let near = P(e.x + d.x * 0.3 * R, e.y + d.y * 0.3 * R)
            let far = P(e.x + d.x * 1.4 * R, e.y + d.y * 1.4 * R)
            if visible(near) && visible(far) {
                out.append(PeekSpot(kind: k, edge: e, dir: d, facingRight: fr, rot: rot, tilt: tilt, hidden: hidden))
            }
        }
        let xr = (r.minX + 2.2 * R)...(r.maxX - 2.2 * R)
        let yr = (r.minY + 2.6 * R)...(r.maxY - 2.6 * R)
        add(.top, P(CGFloat.random(in: xr), r.maxY), P(0, 1), Bool.random(), 90, 0)
        add(.bottom, P(CGFloat.random(in: xr), r.minY), P(0, -1), Bool.random(), -90, 180)
        add(.right, P(r.maxX, CGFloat.random(in: yr)), P(1, 0), true, 0, -8)
        add(.left, P(r.minX, CGFloat.random(in: yr)), P(-1, 0), false, 0, -8)
        // 모서리: 모서리 바로 옆 윗면에서 바깥쪽으로 고개를 기울이며 빼꼼
        add(.cornerR, P(r.maxX - 1.6 * R, r.maxY), P(0, 1), true, 110, 20)
        add(.cornerL, P(r.minX + 1.6 * R, r.maxY), P(0, 1), false, 110, 20)
        return out
    }

    // MARK: 메뉴

    func makeMenu(for target: Cat?) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        func item(_ title: String, _ sel: Selector, _ obj: Any? = nil, on: Bool = false) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            it.representedObject = obj
            it.state = on ? .on : .off
            return it
        }
        m.addItem(item(L("고양이 부르기", "Call the cat"), #selector(summon)))
        m.addItem(item(L("고양이 한 마리 더", "Add a cat"), #selector(addCat)))
        if cats.count > 1 {
            m.addItem(item(target != nil ? L("이 고양이 보내기", "Send this cat home") : L("고양이 한 마리 보내기", "Remove a cat"),
                           #selector(removeCat(_:)), Choice(cat: target)))
        }
        m.addItem(.separator())

        let breedMenu = NSMenu()
        for br in Breed.allCases {
            let on = target.map { $0.breed == br } ?? cats.allSatisfy { $0.breed == br }
            let it = item(br.label, #selector(setBreed(_:)), BreedChoice(breed: br, cat: target), on: on)
            it.isEnabled = Sprites.shared.has(br)
            breedMenu.addItem(it)
        }
        let ci = NSMenuItem(title: target != nil ? L("이 고양이 종", "This cat's breed") : L("고양이 종", "Breed"), action: nil, keyEquivalent: "")
        ci.submenu = breedMenu
        m.addItem(ci)

        let sizeMenu = NSMenu()
        let sizes: [(String, CGFloat)] = [(L("아주 작게", "Tiny"), 0.45), (L("작게", "Small"), 0.6), (L("보통", "Medium"), 0.8), (L("크게", "Large"), 1.1), (L("아주 크게", "Huge"), 1.5)]
        for (name, v) in sizes {
            sizeMenu.addItem(item(name, #selector(setSize(_:)), Choice(scale: v), on: abs(scale - v) < 0.01))
        }
        let si = NSMenuItem(title: L("크기", "Size"), action: nil, keyEquivalent: "")
        si.submenu = sizeMenu
        m.addItem(si)

        m.addItem(.separator())
        let energyMenu = NSMenu()
        for (i, name) in [L("차분하게 (자주 구석에서 잠)", "Calm (naps in a corner a lot)"), L("보통", "Normal"), L("활발하게", "Playful")].enumerated() {
            energyMenu.addItem(item(name, #selector(setEnergy(_:)), i, on: energyLevel == i))
        }
        let ei = NSMenuItem(title: L("활동량", "Activity"), action: nil, keyEquivalent: "")
        ei.submenu = energyMenu
        m.addItem(ei)
        m.addItem(item(L("커서 쫓아가기 · 매달리기", "Chase & hang on the cursor"), #selector(toggleChase), on: chase))
        m.addItem(item(L("창 사이 뛰어다니기 (파쿠르)", "Jump between windows (parkour)"), #selector(toggleClimb), on: climb))
        m.addItem(item(L("창 뒤에 숨기", "Hide behind windows"), #selector(toggleHide), on: hideEnabled))
        m.addItem(item(L("영상 같이 보기 · 소리에 반응", "Watch videos & react to sound"), #selector(toggleWatch), on: watchEnabled))
        m.addItem(item(L("키보드에 반응", "React to typing"), #selector(toggleKeys), on: keysEnabled))
        m.addItem(item(L("🙀 Crazy cat mode (10초)", "🙀 Crazy cat mode (10 s)"), #selector(crazyMode)))
        if keysEnabled {
            let trusted = AXIsProcessTrusted()
            m.addItem(item(L("Enter·지우기 키도 알아보기", "Also recognize Enter & Delete"), #selector(askKeyAccess), on: trusted))
        }
        m.addItem(.separator())
        if #available(macOS 13.0, *) {
            m.addItem(item(L("로그인 시 자동 실행", "Open at login"), #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        }
        let langMenu = NSMenu()
        let langs: [(String, String)] = [("system", L("시스템 설정 따르기", "Same as system")), ("ko", "한국어"), ("en", "English")]
        for (code, name) in langs {
            langMenu.addItem(item(name, #selector(setLanguage(_:)), code, on: language == code))
        }
        let li = NSMenuItem(title: L("언어", "Language"), action: nil, keyEquivalent: "")
        li.submenu = langMenu
        m.addItem(li)
        m.addItem(item(L("메뉴바 아이콘 숨기기", "Hide menu bar icon"), #selector(toggleIcon), on: hideIcon))
        let tip = NSMenuItem(title: L("아이콘을 숨겨도 고양이를 우클릭하면 이 메뉴가 열려요", "Right-click the cat to open this menu any time"), action: nil, keyEquivalent: "")
        tip.isEnabled = false
        m.addItem(tip)
        m.addItem(.separator())
        m.addItem(item(L("업데이트 확인… (현재 \(Updater.shared.currentVersion))", "Check for Updates… (\(Updater.shared.currentVersion))"), #selector(checkUpdates)))
        m.addItem(item(L("Mochi 삭제…", "Uninstall Mochi…"), #selector(uninstall)))
        m.addItem(item(L("종료", "Quit"), #selector(quit)))
        return m
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let src = makeMenu(for: nil)
        let items = src.items
        src.removeAllItems()
        for it in items { menu.addItem(it) }
    }

    @objc func summon() {
        let m = NSEvent.mouseLocation
        for (i, c) in cats.enumerated() { c.teleport(to: P(m.x + CGFloat(i) * 40 * scale, m.y)) }
    }
    @objc func setBreed(_ it: NSMenuItem) {
        guard let ch = it.representedObject as? BreedChoice else { return }
        if let cat = ch.cat { cat.breed = ch.breed } else { for c in cats { c.breed = ch.breed } }
        saveCats()
    }
    @objc func addCat() {
        spawn(cats.last?.breed ?? .ragdoll)
        saveCats()
    }
    @objc func removeCat(_ it: NSMenuItem) {
        guard cats.count > 1 else { return }
        let c = (it.representedObject as? Choice)?.cat ?? cats.last!
        c.window.orderOut(nil)
        c.window.close()
        cats.removeAll { $0 === c }
        saveCats()
    }
    @objc func setColors(_ it: NSMenuItem) {
        guard let ch = it.representedObject as? Choice, let c = ch.colors else { return }
        if let cat = ch.cat { cat.colors = c } else { for cat in cats { cat.colors = c } }
        saveCats()
    }
    @objc func setSize(_ it: NSMenuItem) {
        guard let ch = it.representedObject as? Choice else { return }
        scale = ch.scale
        for c in cats { c.setScale(scale) }
    }
    @objc func toggleChase() { chase.toggle() }
    @objc func setLanguage(_ it: NSMenuItem) {
        guard let code = it.representedObject as? String else { return }
        language = code
    }
    @objc func setEnergy(_ it: NSMenuItem) {
        guard let i = it.representedObject as? Int else { return }
        energyLevel = i
    }
    @objc func toggleClimb() {
        climb.toggle()
        if !climb { for c in cats where !c.surface.isFloor && c.state != .hide { c.startFall() } }
    }
    @objc func toggleKeys() { keysEnabled.toggle() }
    @objc func crazyMode() { for c in cats { c.goCrazy() } }

    /// Enter 등 키를 구분하려면 손쉬운 사용 권한이 필요
    @objc func askKeyAccess() {
        if AXIsProcessTrusted() {
            installKeyMonitor()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("손쉬운 사용 권한이 필요해요", "Accessibility permission needed")
        a.informativeText = L("Enter나 지우기 키를 눌렀을 때 고양이가 반응하려면, 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 Mochi를 켜 주세요.\n\n모찌는 어떤 키를 눌렀는지만 보고, 입력한 내용은 저장하거나 보내지 않아요. 앱을 업데이트하면 권한을 다시 켜야 할 수 있어요.",
                                "To react when you press Enter or Delete, turn on Mochi in System Settings › Privacy & Security › Accessibility.\n\nMochi only looks at which key was pressed. It never stores or sends what you type. You may need to turn this on again after an update.")
        a.addButton(withTitle: L("설정 열기", "Open Settings"))
        a.addButton(withTitle: L("취소", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func toggleWatch() {
        watchEnabled.toggle()
        if !watchEnabled {
            watching = false
            musicPlaying = false
            for c in cats where c.state == .watch { c.enter(.stretch) }
        }
    }
    @objc func toggleHide() {
        hideEnabled.toggle()
        if !hideEnabled { for c in cats where c.state == .hide { c.abortHide() } }
    }
    @objc func toggleLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch {
                NSSound.beep()
            }
        }
    }
    @objc func toggleIcon() { hideIcon.toggle(); updateStatusItem() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func checkUpdates() { Updater.shared.check(userInitiated: true) }

    /// Removes the login item and settings, moves the app to the Trash, then quits.
    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Mochi를 삭제할까요?", "Uninstall Mochi?")
        alert.informativeText = L("앱은 휴지통으로 옮겨지고, 설정과 로그인 시 자동 실행 항목도 함께 지워져요.",
                                  "The app will be moved to the Trash, and its settings and login item will be removed.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("삭제", "Uninstall"))
        alert.addButton(withTitle: L("취소", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            UserDefaults.standard.synchronize()
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(id).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([appURL]) { _, error in
            DispatchQueue.main.async {
                if error != nil {
                    let fail = NSAlert()
                    fail.messageText = L("휴지통으로 옮기지 못했어요", "Couldn't move Mochi to the Trash")
                    fail.informativeText = L("Finder에서 \(appURL.path)를 직접 휴지통으로 옮겨 주세요.",
                                             "Please drag \(appURL.path) to the Trash in Finder.")
                    fail.runModal()
                }
                exit(0)
            }
        }
    }

    func updateStatusItem() {
        if hideIcon {
            if let si = statusItem { NSStatusBar.system.removeStatusItem(si); statusItem = nil }
        } else if statusItem == nil {
            let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            si.button?.image = AppDelegate.icon()
            si.button?.toolTip = "Mochi"
            let menu = NSMenu()
            menu.delegate = self
            si.menu = menu
            statusItem = si
        }
    }

    /// 메뉴바 아이콘: 앉아서 등을 보인 고양이 실루엣 (18pt 템플릿, 라이트/다크 모드에 맞춰 색이 바뀜)
    static func icon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            do {
                // 앉아서 등을 보인 고양이 실루엣 (보내주신 로고를 따라 그린 윤곽)
                let pts: [CGPoint] = [
            P(5.44, 0.60), P(5.32, 0.70), P(5.24, 0.99), P(5.24, 1.79), P(5.39, 2.99), P(5.22, 3.53),
            P(5.17, 4.18), P(5.29, 4.77), P(5.61, 5.40), P(5.66, 5.79), P(5.20, 7.01), P(4.78, 8.65),
            P(4.17, 9.91), P(3.83, 10.84), P(3.64, 11.91), P(3.64, 12.77), P(3.73, 13.40), P(3.98, 14.16),
            P(4.54, 15.11), P(4.54, 15.82), P(4.76, 16.06), P(5.20, 16.33), P(8.56, 17.28), P(10.51, 17.38),
            P(11.66, 17.28), P(12.80, 17.01), P(13.02, 16.81), P(12.90, 16.45), P(13.66, 15.74), P(14.12, 15.01),
            P(14.32, 14.35), P(14.34, 13.55), P(14.12, 12.89), P(13.68, 12.23), P(13.17, 11.94), P(12.78, 12.04),
            P(12.66, 12.26), P(12.66, 12.50), P(13.12, 13.30), P(13.24, 13.69), P(13.24, 14.13), P(13.15, 14.47),
            P(12.85, 14.96), P(12.34, 15.40), P(11.66, 15.72), P(11.37, 15.74), P(11.29, 15.67), P(11.07, 14.96),
            P(11.46, 14.23), P(11.71, 13.52), P(11.85, 12.11), P(11.63, 10.79), P(10.68, 8.62), P(10.32, 7.13),
            P(9.83, 5.87), P(9.85, 5.45), P(10.15, 4.84), P(10.29, 4.28), P(10.29, 3.77), P(10.10, 3.04),
            P(10.24, 1.65), P(10.17, 0.72), P(10.05, 0.60), P(9.71, 0.70), P(8.68, 1.65), P(8.51, 1.72),
            P(6.98, 1.72), P(6.81, 1.65), P(5.78, 0.70)
                ]
                let p = NSBezierPath()
                p.move(to: pts[0])
                for q in pts.dropFirst() { p.line(to: q) }
                p.close()
                p.lineJoinStyle = .round
                p.fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - 시작

@main
struct MochiMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(appDelegate) { application.run() }
    }
}
