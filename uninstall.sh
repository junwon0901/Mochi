#!/bin/bash
# Removes Mochi: quits it, deletes the app, its settings and its login item.
# Usage: ./uninstall.sh
BUNDLE_ID="com.junwon.mochi"

echo "🐱 Uninstalling Mochi..."
pkill -x Mochi 2>/dev/null || true
sleep 0.5

for DIR in /Applications "$HOME/Applications"; do
  if [ -d "$DIR/Mochi.app" ]; then
    rm -rf "$DIR/Mochi.app" && echo "Removed $DIR/Mochi.app"
  fi
done

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
echo "Removed settings"

echo "✅ Mochi has been uninstalled."
echo "   If it still shows under System Settings > General > Login Items, it will disappear on its own after a restart."
