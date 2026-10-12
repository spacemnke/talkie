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

# LiveKit's WebRTC (and anything else linked dynamically) ships as frameworks next to the binary.
# They're universal already, so the Apple silicon build's copies serve both.
mkdir -p "$APP/Contents/Frameworks"
for framework in "$BIN"/*.framework; do
  if [ -d "$framework" ]; then cp -R "$framework" "$APP/Contents/Frameworks/"; fi
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Talkie"
ls "$APP/Contents/Frameworks"

codesign --force --deep --sign - "$APP"

# Open it once: if a framework is missing, dyld stops it here instead of on your Mac.
TALKIE_SMOKE_TEST=1 "$APP/Contents/MacOS/Talkie" &
SMOKE=$!
for _ in $(seq 1 30); do
  kill -0 "$SMOKE" 2>/dev/null || break
  sleep 1
done
if kill -0 "$SMOKE" 2>/dev/null; then
  kill "$SMOKE"
  echo "Talkie didn't quit after its launch check" >&2
  exit 1
fi
wait "$SMOKE"
(cd build && ditto -c -k --keepParent Talkie.app Talkie.zip)

# A disk image with the app and a shortcut to Applications, ready to drag across.
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Talkie" -srcfolder "$STAGE" -ov -format UDZO "build/Talkie.dmg"
rm -rf "$STAGE"

echo "Built $APP, build/Talkie.zip and build/Talkie.dmg"
