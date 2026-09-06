#!/bin/bash
# Builds Markdown.app next to this script.
set -e
cd "$(dirname "$0")"
APP="Markdown.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# Compile the Icon Composer icon into an asset catalog. macOS 26 renders a
# compiled .icon natively; a bare .icns gets inset onto a generated tile.
ACTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/actool"
if [ ! -x "$ACTOOL" ]; then
    echo "error: needs Xcode for actool to compile Icon.icon" >&2
    exit 1
fi
"$ACTOOL" Icon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --target-device mac \
    --app-icon Icon --output-partial-info-plist /dev/null \
    --errors --warnings > /dev/null

swiftc -O \
    Sources/Markdown.swift Sources/Style.swift Sources/Render.swift Sources/main.swift \
    -o "$APP/Contents/MacOS/Markdown"
codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"
