#!/usr/bin/env bash
# Builds Talkie and wraps it into build/Talkie.app (ad-hoc signed), build/Talkie.zip and build/Talkie.dmg.
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
cd "$(dirname "$0")/.."

# Build for Apple Silicon and Intel, then join them into one universal binary.
swift build -c "$CONFIG" --arch arm64
swift build -c "$CONFIG" --arch x86_64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
INTEL_BIN="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)"

APP="build/Talkie.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$BIN/Talkie" "$INTEL_BIN/Talkie" -output "$APP/Contents/MacOS/Talkie"
lipo -info "$APP/Contents/MacOS/Talkie"
cp Support/Info.plist "$APP/Contents/Info.plist"
iconutil -c icns Support/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Fonts ship inside the SwiftPM resource bundle; keep it under Resources so the app stays signable.
if [ -d "$BIN/Talkie_Talkie.bundle" ]; then
  cp -R "$BIN/Talkie_Talkie.bundle" "$APP/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent Talkie.app Talkie.zip)

# A disk image with the app and a shortcut to Applications, ready to drag across.
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Talkie" -srcfolder "$STAGE" -ov -format UDZO "build/Talkie.dmg"
rm -rf "$STAGE"

echo "Built $APP, build/Talkie.zip and build/Talkie.dmg"
