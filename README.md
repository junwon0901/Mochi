# Mochi 🐾

A desktop cat for macOS that wanders around your screen. Choose a Ragdoll or a Siamese.

<p>
  <img src="docs/closeup-parkour.png" width="49%" alt="A ragdoll leaping off the top of a window">
  <img src="docs/closeup-peek.png" width="49%" alt="A siamese peeking out from behind a window">
</p>

## What it does
- Walks, runs, grooms, stretches, yawns, kneads, rolls over, tilts its head, loafs, and sleeps (when it gets sleepy it curls up in a corner of the screen)
- Parkour: leaps between windows like jumping across rooftops
- Hides behind windows and peeks out from the top, the sides, the bottom (upside down) and near the corners
- Chases your cursor, wiggles its bottom and pounces, or hangs from the cursor (shake the cursor and it swings)
- Pick it up and carry it, or throw it
- Several cats at once, each with its own breed
- Settings: activity level (calm / normal / playful), size, language (system / 한국어 / English), open at login

## Build and install
Requires Xcode or the Command Line Tools (`xcode-select --install`). Runs on macOS 12 or later.

```bash
./build.sh
```

The script builds the app, installs it straight into `/Applications/Mochi.app` and launches it. If an older Mochi is running, it is replaced with the new version.

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
- `uninstall.sh`: removes the app, its settings and its login item
