#!/bin/bash
# Builds a release binary with SwiftPM and wraps it into build/PixelEarth.app (double-clickable, unsigned).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/PixelEarth.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PixelEarth" "$APP/Contents/MacOS/PixelEarth"
# SwiftPM's generated Bundle.module accessor looks for the resource bundle at Bundle.main.bundleURL
# (= the .app root) and falls back to the absolute .build path, so place a copy at the app root.
for b in "$BIN"/*.bundle; do cp -R "$b" "$APP/"; cp -R "$b" "$APP/Contents/Resources/"; done
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
cp App/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Pixel Earth</string>
  <key>CFBundleDisplayName</key><string>Pixel Earth</string>
  <key>CFBundleIdentifier</key><string>com.leeo.pixelearth</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleExecutable</key><string>PixelEarth</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
