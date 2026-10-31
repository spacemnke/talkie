#!/usr/bin/env bash
# Builds Talkie and wraps it into build/Talkie.app, build/Talkie.zip and build/Talkie.dmg.
# Usage: scripts/bundle.sh [debug|release]
#
# Signed with Developer ID and notarized by Apple when these are set (CI sets them from the
# repository's secrets; the same Apple ID, team and app-specific password as DiscordDeck):
#   DEVELOPER_ID        "Developer ID Application: Name (TEAMID)", in the keychain
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   for notarytool
#   (or NOTARY_PROFILE, a notarytool keychain profile, on your own Mac)
# Without DEVELOPER_ID it's signed ad hoc, and macOS asks people to Open Anyway the first time.
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
# Each build gets its own number, so the updater can tell a newer one (CI passes its run number).
BUILD="${TALKIE_BUILD:-1}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" -c "Set :CFBundleShortVersionString 0.1.$BUILD" "$APP/Contents/Info.plist"
echo "Talkie 0.1.$BUILD (build $BUILD)"
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

if [ -n "${DEVELOPER_ID:-}" ]; then
  # Developer ID, inside out: Sparkle's helpers, then each framework, then the app. Hardened
  # runtime and a secure timestamp are what notarization asks for; every framework carries our
  # signature so the hardened runtime lets Talkie load it.
  sign() { codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$@"; }
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  if [ -e "$SPARKLE/XPCServices/Installer.xpc" ]; then sign "$SPARKLE/XPCServices/Installer.xpc"; fi
  if [ -e "$SPARKLE/XPCServices/Downloader.xpc" ]; then sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"; fi
  if [ -e "$SPARKLE/Autoupdate" ]; then sign "$SPARKLE/Autoupdate"; fi
  if [ -e "$SPARKLE/Updater.app" ]; then sign "$SPARKLE/Updater.app"; fi
  for framework in "$APP/Contents/Frameworks"/*.framework; do
    if [ -d "$framework" ]; then sign "$framework"; fi
  done
  sign --entitlements Support/Talkie.entitlements "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  codesign --force --deep --sign - "$APP"
  # Test builds are signed ad hoc, so by default macOS knows each one only by its exact hash and
  # forgets microphone access with every new build. Naming the app by its bundle id instead keeps
  # the permission from one test build to the next (Developer ID builds don't need this).
  codesign --force --sign - --requirements '=designated => identifier "com.spacemnke.talkie"' "$APP"
fi
codesign --display --requirements - "$APP"

# Sends a file to Apple's notary service and waits; stops the build if Apple doesn't accept it.
NOTARIZE=""
if [ -n "${DEVELOPER_ID:-}" ] && { [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${APPLE_ID:-}" ]; }; then NOTARIZE=1; fi
notarize() {
  local creds out id
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    creds=(--keychain-profile "$NOTARY_PROFILE")
  else
    creds=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi
  echo "Notarizing $(basename "$1")..."
  out=$(xcrun notarytool submit "$1" "${creds[@]}" --wait 2>&1) || true
  echo "$out"
  id=$(echo "$out" | sed -n 's/^ *id: //p' | head -1)
  if ! echo "$out" | grep -q "status: Accepted"; then
    if [ -n "$id" ]; then xcrun notarytool log "$id" "${creds[@]}" || true; fi
    echo "Apple didn't accept $(basename "$1")" >&2
    exit 1
  fi
}

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

# Apple checks the app and issues a ticket, which is stapled on so it opens even offline.
if [ -n "$NOTARIZE" ]; then
  (cd build && ditto -c -k --keepParent Talkie.app Talkie-notarize.zip)
  notarize build/Talkie-notarize.zip
  rm build/Talkie-notarize.zip
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=4 "$APP"
fi
(cd build && ditto -c -k --keepParent Talkie.app Talkie.zip)

# A disk image with the app and a shortcut to Applications, ready to drag across.
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Talkie" -srcfolder "$STAGE" -ov -format UDZO "build/Talkie.dmg"
rm -rf "$STAGE"
if [ -n "$NOTARIZE" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" build/Talkie.dmg
  notarize build/Talkie.dmg
  xcrun stapler staple build/Talkie.dmg
  spctl --assess --type open --context context:primary-signature --verbose=4 build/Talkie.dmg
  # Tells CI the downloads are notarized (the release notes say so).
  touch build/notarized
fi

echo "Built $APP, build/Talkie.zip and build/Talkie.dmg${NOTARIZE:+ (signed and notarized)}"
