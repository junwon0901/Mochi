#!/bin/bash
# Mochi를 빌드해서 응용 프로그램 폴더(/Applications)에 바로 설치하고 실행해요.
# 사용법: 이 폴더에서 ./build.sh
set -e
cd "$(dirname "$0")"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"          # /Applications에 쓸 권한이 없으면 내 응용 프로그램 폴더로
  mkdir -p "$DEST"
fi
WORK="$(mktemp -d)"
APP="$WORK/Mochi.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "🐱 컴파일 중... (1분 정도 걸릴 수 있어요)"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/Mochi" Mochi.swift

cp -R sprites "$APP/Contents/Resources/sprites"

if [ -f icon.png ]; then
  ICONSET="$WORK/Mochi.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Mochi.icns" || true
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Mochi</string>
  <key>CFBundleIdentifier</key><string>com.junwon.mochi</string>
  <key>CFBundleName</key><string>Mochi</string>
  <key>CFBundleDisplayName</key><string>Mochi</string>
  <key>CFBundleIconFile</key><string>Mochi</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# 켜져 있는 모찌를 끄고 새 버전으로 바꾸기
pkill -x Mochi 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Mochi.app"
cp -R "$APP" "$DEST/Mochi.app"
rm -rf "$WORK"

echo "✅ 설치 완료: $DEST/Mochi.app"
open "$DEST/Mochi.app"
