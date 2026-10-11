#!/usr/bin/env bash
# Builds Talkie and wraps it into build/Talkie.app (ad-hoc signed) plus build/Talkie.zip.
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
cd "$(dirname "$0")/.."

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Talkie.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Talkie" "$APP/Contents/MacOS/Talkie"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Fonts ship inside the SwiftPM resource bundle; keep it under Resources so the app stays signable.
if [ -d "$BIN/Talkie_Talkie.bundle" ]; then
  cp -R "$BIN/Talkie_Talkie.bundle" "$APP/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent Talkie.app Talkie.zip)
echo "Built $APP"
