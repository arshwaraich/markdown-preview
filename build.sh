#!/bin/bash
# Builds Markdown.app next to this script.
set -e
cd "$(dirname "$0")"
APP="Markdown.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O \
    Sources/Markdown.swift Sources/main.swift \
    -o "$APP/Contents/MacOS/Markdown"
codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"
