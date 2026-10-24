#!/usr/bin/env bash
set -euo pipefail

DEST_APP="/Applications/TrafficReloader.app"

echo "-> Stopping Traffic Reloader..."
pkill -f "TrafficReloader.app/Contents/MacOS/TrafficReloader" 2>/dev/null || true

echo "-> Removing $DEST_APP..."
rm -rf "$DEST_APP"

echo "[OK] Traffic Reloader uninstalled."
