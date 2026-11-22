# Mochi 🐾

A desktop cat for macOS that wanders around your screen. Choose a Ragdoll, a Siamese or a Norwegian Forest cat.

![Ragdoll, Siamese and Norwegian Forest sprite preview](docs/breeds-1.7-preview.png)

Version 1.7.1 gives the Siamese a denser short coat, a darker seal mask, and rounder blue eyes. It also fixes the direction changes on the way to a nap spot.

<p>
  <img src="docs/closeup-parkour.png" width="49%" alt="A ragdoll leaping off the top of a window">
  <img src="docs/closeup-peek.png" width="49%" alt="A siamese peeking out from behind a window">
</p>

## What it does
- Walks, runs, grooms, stretches, yawns, kneads, rolls over, tilts its head, loafs, and sleeps (when it gets sleepy it curls up in a corner of the screen)
- Parkour: leaps between windows like jumping across rooftops
- Hides behind windows and peeks out from the top, the sides, the bottom (upside down) and near the corners
- Chases your cursor, wiggles its bottom and pounces, or hangs from the cursor (shake the cursor and it swings)
- Builds invisible stepping stones in mid-air, but only to climb up to a high window or to your cursor
- Leave the cursor still for a while and it comes over, waits next to it, then dozes off there
- Watches videos with you: when a browser or video player is playing with a big window, it sits by the screen and looks up at it. With music only, it bobs its head. A sudden sound wakes a sleeping cat with a start
- Reacts to typing: flicks its tail while you type, hops when you press Enter, tilts its head at a flurry of Deletes, and after a long typing session comes to loaf on top of your window (Enter and Delete need Accessibility permission; typing rhythm needs none)
- Roams freely across multiple monitors
- Crazy cat mode: type the word `cat` (with key permission) or pick it from the menu, and it goes wild for 10 seconds — zoomies, huge jumps, spins and rolls — then grooms as if nothing happened
- Gets sleepier at night, and runs over to greet you when you wake or unlock your Mac
- Pick it up and carry it, or throw it
- Several cats at once. Pick a breed under **Add a cat**, or right-click a cat to change its breed individually.
- Settings: activity level (calm / normal / playful), size, language (system / 한국어 / English), open at login

## Build and install
Requires Xcode or the Command Line Tools (`xcode-select --install`). Runs on macOS 12 or later.

```bash
./build.sh
```

The script first validates all 117 transparent sprite frames, then builds the app, installs it straight into `/Applications/Mochi.app` and launches it. If an older Mochi is running, it is replaced with the new version.

## Updates
Mochi checks GitHub for a new release once a day and asks before updating. You can also pick **Check for Updates…** from the menu. Updating downloads the new build, replaces the app and restarts it, so you don't need the project folder for this either.

Every push to `main` is built on macOS by a GitHub Action. To publish a new version, bump the number in `VERSION`; the build is then published as `Mochi.zip` in release `v<VERSION>`.

## Uninstall
You don't need the project folder to remove Mochi. Once it is installed, you can delete the folder.

- **From the app**: click the menu bar icon (or right-click the cat) and pick **Uninstall Mochi…**. It removes the login item and settings and moves the app to the Trash.
- **By hand**: quit Mochi, then drag `Mochi.app` from Applications to the Trash.
- If you still have the project folder, `./uninstall.sh` does the same as the menu item.

## Controls
- Click: pet the cat
- Drag: pick it up and carry it (flick to throw)
- Right-click the cat, or click the menu bar icon: open the menu

## Project layout
- `Mochi.swift`: the whole app (AppKit, single file)
- `sprites/<breed>/*.png`: the artwork for each behavior
- `build.sh`: builds `Mochi.app` and installs it into Applications
- `validate_sprites.sh`: checks that all breed frames exist, use alpha, and keep compatible canvas sizes
- `uninstall.sh`: removes the app, its settings and its login item
- `VERSION`: the app version; `.github/workflows/release.yml` builds every push and publishes new versions
