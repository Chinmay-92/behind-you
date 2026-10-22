#!/bin/sh
# Builds a double-clickable "Behind You.app" (so the camera prompt names the app, not your terminal).
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Behind You.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/behindyou "$APP/Contents/MacOS/behindyou"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
echo "run it with:  open \"$APP\" --args --debug     (or double-click)"
