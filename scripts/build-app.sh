#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Build this app on macOS 13+ with Xcode Command Line Tools." >&2
    exit 1
fi
# Defaults to the machine architecture (arm64 on Apple Silicon).
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Dynamic Notch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MusicIsland" "$APP/Contents/MacOS/MusicIsland"
for resource in "$BIN_DIR"/*.bundle; do
    [[ -d "$resource" ]] && cp -R "$resource" "$APP/Contents/Resources/"
done
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - --entitlements Resources/MusicIsland.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
echo 'Run: open "dist/Dynamic Notch.app"'
