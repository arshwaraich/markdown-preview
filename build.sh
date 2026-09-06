#!/bin/bash
# Builds Markdown.app next to this script.
set -e
cd "$(dirname "$0")"
APP="Markdown.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
# Compile the Icon Composer icon into an asset catalog. macOS 26 renders a
# compiled .icon natively; a bare .icns gets the legacy inset treatment.
ACTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/actool"
if [ -x "$ACTOOL" ]; then
    "$ACTOOL" Icon.icon --compile "$APP/Contents/Resources" \
        --platform macosx --minimum-deployment-target 26.0 --target-device mac \
        --app-icon Icon --output-partial-info-plist /dev/null \
        --errors --warnings > /dev/null
else
    echo "warning: Xcode not found, falling back to legacy .icns"
    cp icon/AppIcon.icns "$APP/Contents/Resources/Icon.icns"
fi
swiftc -O \
    Sources/Markdown.swift Sources/main.swift \
    -o "$APP/Contents/MacOS/Markdown"
codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"
