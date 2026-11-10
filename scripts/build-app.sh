#!/usr/bin/env bash
# Build build/Atoll.app (ad-hoc signed, LSUIElement menu bar app).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Atoll
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Atoll.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Atoll" "$APP/Contents/MacOS/Atoll"
cp -R Sources/Atoll/Resources/Sprites "$APP/Contents/Resources/Sprites"
# App icon: compile the Icon Composer source (needs Xcode's actool) into Assets.car
# + AppIcon.icns; fall back to the prebuilt icns when actool is unavailable.
# actool runs through a daemon with its own cwd, so paths must be absolute.
RES="$PWD/$APP/Contents/Resources"
if ! xcrun actool "$PWD/assets/AppIcon.icon" --compile "$RES" \
    --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
    --output-partial-info-plist "$PWD/build/actool-partial.plist" >/dev/null 2>&1 \
    || [ ! -f "$RES/Assets.car" ]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.atoll</string>
  <key>CFBundleName</key><string>Atoll</string>
  <key>CFBundleDisplayName</key><string>Atoll</string>
  <key>CFBundleExecutable</key><string>Atoll</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
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
