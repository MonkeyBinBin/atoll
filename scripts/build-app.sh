#!/usr/bin/env bash
# Build build/Herdr Island.app (ad-hoc signed, LSUIElement menu bar app).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product HerdrIsland
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Herdr Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/HerdrIsland" "$APP/Contents/MacOS/HerdrIsland"
cp -R Sources/HerdrIsland/Resources/Sprites "$APP/Contents/Resources/Sprites"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.herdr-island</string>
  <key>CFBundleName</key><string>Herdr Island</string>
  <key>CFBundleDisplayName</key><string>Herdr Island</string>
  <key>CFBundleExecutable</key><string>HerdrIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "$APP"
