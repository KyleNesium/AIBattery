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
mkdir -p "$APP_DIR/Contents/Frameworks"

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
  # Align CFBundleVersion with semver so Sparkle's version comparison works correctly
  # (Sparkle compares sparkle:version from appcast against CFBundleVersion)
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP_DIR/Contents/Info.plist"
  echo "Injected version ${VERSION} from tag ${GIT_TAG}"
fi

# Copy entitlements into bundle
cp AIBattery/AIBattery.entitlements "$APP_DIR/Contents/Resources/"

# --- Sparkle framework bundling ---
# Find SPM-built Sparkle.framework (SPM places it under .build/<arch>/release/)
SPARKLE_BUILD_DIR=$(find .build -path "*/release/Sparkle.framework" -type d 2>/dev/null | head -n1 || true)
if [ -z "$SPARKLE_BUILD_DIR" ]; then
  # Fallback: check the xcframework in artifacts
  SPARKLE_BUILD_DIR=$(find .build/artifacts -path "*/macos-*/Sparkle.framework" -type d 2>/dev/null | head -n1 || true)
fi

if [ -n "$SPARKLE_BUILD_DIR" ]; then
  echo "Bundling Sparkle framework from: $SPARKLE_BUILD_DIR"
  cp -R "$SPARKLE_BUILD_DIR" "$APP_DIR/Contents/Frameworks/"
  # XPC services (Downloader.xpc, Installer.xpc) are inside the framework bundle
else
  echo "Warning: Sparkle.framework not found in build artifacts — update functionality requires it"
fi

# Codesign inner frameworks before signing the outer bundle
echo "Codesigning..."
if [ -d "$APP_DIR/Contents/Frameworks" ]; then
  for item in "$APP_DIR/Contents/Frameworks"/*.framework; do
    [ -e "$item" ] || continue
    echo "  Signing: $(basename "$item")"
    codesign --sign - --force --deep \
      --options runtime \
      "$item"
  done
fi

# Ad-hoc codesign the outer bundle — gives the app a stable identity for Keychain ACL
codesign --sign - --deep --force \
  --entitlements AIBattery/AIBattery.entitlements \
  --identifier com.KyleNesium.AIBattery \
  --options runtime \
  "$APP_DIR"

echo "Done! App bundle at: $APP_DIR"

# Create distribution artifacts
echo "Packaging zip..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" .build/AIBattery.zip

# EdDSA-sign the zip for Sparkle (when SPARKLE_EDDSA_KEY env is set)
if [ -n "${SPARKLE_EDDSA_KEY:-}" ]; then
  echo "EdDSA-signing zip for Sparkle..."
  SIGN_UPDATE=""

  # Try to find sign_update from SPM build artifacts
  SIGN_UPDATE=$(find .build/artifacts -name "sign_update" -type f 2>/dev/null | head -n1 || true)
  if [ -z "$SIGN_UPDATE" ]; then
    # Fall back to Sparkle's installed location
    SIGN_UPDATE=$(command -v sign_update 2>/dev/null || true)
  fi

  if [ -n "$SIGN_UPDATE" ]; then
    SIGNATURE=$(echo "$SPARKLE_EDDSA_KEY" | "$SIGN_UPDATE" .build/AIBattery.zip --ed-key-file - 2>&1)
    echo "$SIGNATURE" > .build/sparkle-signature.txt
    echo "Sparkle signature saved to .build/sparkle-signature.txt"
  else
    echo "Warning: sign_update not found — skipping EdDSA signing"
  fi
fi

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
if [ -f .build/sparkle-signature.txt ]; then
  echo "  .build/sparkle-signature.txt"
fi
echo ""
echo "To launch:"
echo "  open $APP_DIR"
