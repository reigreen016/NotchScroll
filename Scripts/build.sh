#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/NotchScroll.app/Contents/MacOS build/NotchScroll.app/Contents/Resources build/ModuleCache
module_cache=$(cd build/ModuleCache && pwd -P)
cp Resources/Info.plist build/NotchScroll.app/Contents/Info.plist
swift -module-cache-path "$module_cache" Scripts/draw-icon.swift build/NotchScroll.iconset
python3 Scripts/package-icon.py build/NotchScroll.iconset build/NotchScroll.app/Contents/Resources/AppIcon.icns
swiftc -O -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit \
  -target arm64-apple-macos14.0 -module-cache-path "$module_cache" \
  Sources/main.swift -o build/NotchScroll.app/Contents/MacOS/NotchScroll
plutil -lint build/NotchScroll.app/Contents/Info.plist
codesign --force --sign - build/NotchScroll.app
codesign --verify --strict build/NotchScroll.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ditto -c -k --sequesterRsrc --keepParent build/NotchScroll.app "build/NotchScroll-${version}.zip"
echo "Built build/NotchScroll.app and build/NotchScroll-${version}.zip"
