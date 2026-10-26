#!/usr/bin/env bash
#
# Build the FaceKeySpikes executable in release and wrap it in a signed .app
# bundle. Running the spikes as a bundled, stably-signed .app makes macOS bind
# the Camera (TCC) permission to the bundle identity instead of to Terminal, and
# keeps that grant across rebuilds (CLAUDE.md: stable signing identity).
#
# Signing: uses the "FaceKey Dev" identity if it exists in the keychain,
# otherwise falls back to ad-hoc (-) with a warning. Ad-hoc works for the camera
# spike but the permission is re-prompted whenever the binary changes.
#
# Usage:  spikes/build-app.sh
#         ./FaceKeySpikes.app/Contents/MacOS/FaceKeySpikes camera --now
#     or  open FaceKeySpikes.app --args camera --now
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"   # spikes/
APP="FaceKeySpikes.app"
IDENTITY="FaceKey Dev"

echo "swift build -c release ..."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/FaceKeySpikes"
[ -x "$BIN" ] || { echo "build produced no FaceKeySpikes binary" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FaceKeySpikes"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "signing with \"$IDENTITY\""
  codesign --force --options runtime --identifier dev.facekey.spikes \
           --sign "$IDENTITY" "$APP"
else
  echo "WARNING: \"$IDENTITY\" identity not found — signing ad-hoc. Camera permission"
  echo "         will be re-prompted on each rebuild. To create a stable identity, make a"
  echo "         self-signed 'Code Signing' certificate named \"$IDENTITY\" in Keychain Access."
  codesign --force --identifier dev.facekey.spikes --sign - "$APP"
fi

echo
echo "Built $(pwd)/$APP"
echo "Run:   open $APP --args camera --now"
echo "       open $APP --args camera --on-wake"
echo "Logs:  ~/Library/Logs/FaceKeySpikes/"
