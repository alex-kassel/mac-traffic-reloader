#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC="$PROJECT_DIR/build/TrafficReloader.app"
DEST_APP="/Applications/TrafficReloader.app"

if [ ! -d "$APP_SRC" ]; then
    echo "App bundle not found. Building first..."
    bash "$SCRIPT_DIR/build_app.sh"
fi

echo "-> Stopping any running TrafficReloader processes..."
pkill -f "TrafficReloader.app/Contents/MacOS/TrafficReloader" 2>/dev/null || true
sleep 1

echo "-> Installing to $DEST_APP..."
rm -rf "$DEST_APP"
cp -R "$APP_SRC" "$DEST_APP"

xattr -d com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "-> Launching $DEST_APP..."
open "$DEST_APP"

echo ""
echo "================================================"
echo " [OK] Traffic Reloader installed successfully!"
echo "================================================"
echo "Check the menu bar for the antenna icon (📶)."
echo "Click Settings... to configure your credentials."
echo "================================================"
