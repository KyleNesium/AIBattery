#!/bin/bash
# Build AI Battery.app bundle from source
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building release binary..."
swift build -c release

APP_DIR=".build/AIBattery.app"

# Kill any existing instance before replacing the binary (skip in CI)
if [ -z "${CI:-}" ]; then
  echo "Stopping existing AI Battery instances..."
  pkill -f "AIBattery.app/Contents/MacOS/AIBattery" 2>/dev/null || true
  sleep 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "Generating app icon..."
swift scripts/generate-icon.swift .build

echo "Creating .app bundle..."
cp .build/release/AIBattery "$APP_DIR/Contents/MacOS/AIBattery"
cp .build/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cp AIBattery/Info.plist "$APP_DIR/Contents/Info.plist"

# Inject version from git tag if available (e.g. v1.2.4 → 1.2.4)
GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || true)
if [ -n "$GIT_TAG" ]; then
  VERSION="${GIT_TAG#v}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_DIR/Contents/Info.plist"
  echo "Injected version ${VERSION} from tag ${GIT_TAG}"
fi

# Copy entitlements into bundle
cp AIBattery/AIBattery.entitlements "$APP_DIR/Contents/Resources/"

# Ad-hoc codesign — gives the app a stable identity for Keychain ACL
echo "Codesigning..."
codesign --sign - --deep --force \
  --entitlements AIBattery/AIBattery.entitlements \
  --identifier com.KyleNesium.AIBattery \
  --options runtime \
  "$APP_DIR"

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

# Set volume icon on the DMG
cp .build/AppIcon.icns "$DMG_DIR/.VolumeIcon.icns"
SetFile -a C "$DMG_DIR" 2>/dev/null || true

hdiutil create -volname "AI Battery" -srcfolder "$DMG_DIR" -ov -format UDZO .build/AIBattery.dmg
rm -rf "$DMG_DIR"

echo ""
echo "Artifacts:"
echo "  .build/AIBattery.zip"
echo "  .build/AIBattery.dmg"
echo ""
echo "To launch:"
echo "  open $APP_DIR"
