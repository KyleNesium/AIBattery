#!/bin/bash
# Build AI Battery.app bundle from source
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building release binary..."
swift build -c release

APP_DIR=".build/AIBattery.app"

# Kill any existing instance before replacing the binary
echo "Stopping existing AI Battery instances..."
pkill -f "AIBattery.app/Contents/MacOS/AIBattery" 2>/dev/null || true
sleep 1

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "Creating .app bundle..."
cp .build/release/AIBattery "$APP_DIR/Contents/MacOS/AIBattery"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>AI Battery</string>
	<key>CFBundleExecutable</key>
	<string>AIBattery</string>
	<key>CFBundleIdentifier</key>
	<string>com.KyleNesium.AIBattery</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>AI Battery</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

echo "Done! App bundle at: $APP_DIR"

# Create distribution artifacts
echo "Packaging zip..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" .build/AIBattery.zip

echo "Packaging DMG..."
DMG_DIR=".build/dmg"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "AI Battery" -srcfolder "$DMG_DIR" -ov -format UDZO .build/AIBattery.dmg
rm -rf "$DMG_DIR"

echo ""
echo "Artifacts:"
echo "  .build/AIBattery.zip"
echo "  .build/AIBattery.dmg"
echo ""
echo "To launch:"
echo "  open $APP_DIR"
