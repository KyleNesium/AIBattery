#!/bin/bash
# Build AI Battery.app bundle from source
set -euo pipefail

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

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

# Add rpath so the binary can find frameworks in Contents/Frameworks at runtime
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/AIBattery"
cp .build/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cp AIBattery/Info.plist "$APP_DIR/Contents/Info.plist"
cp AIBattery/PrivacyInfo.xcprivacy "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"

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

# Strip Sparkle feed URL for App Store builds
if [ -n "${APP_STORE_BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
  echo "Stripped SUFeedURL for App Store build"
fi

# Inject Sparkle EdDSA public key (required for signature verification)
if [ -n "${SPARKLE_EDDSA_PUBLIC_KEY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${SPARKLE_EDDSA_PUBLIC_KEY}" "$APP_DIR/Contents/Info.plist"
  echo "Injected Sparkle EdDSA public key"
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
    codesign --sign "$SIGN_IDENTITY" --force --deep \
      --options runtime \
      "$item"
  done
fi

# Select entitlements file (App Store builds use sandboxed entitlements)
ENTITLEMENTS="AIBattery/AIBattery.entitlements"
if [ -n "${APP_STORE_BUILD:-}" ]; then
  ENTITLEMENTS="AIBattery/AIBattery-AppStore.entitlements"
fi

# Codesign the outer bundle — gives the app a stable identity for Keychain ACL
codesign --sign "$SIGN_IDENTITY" --deep --force \
  --entitlements "$ENTITLEMENTS" \
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

  # Try to find sign_update from SPM build artifacts (exclude deprecated DSA script)
  SIGN_UPDATE=$(find .build/artifacts -name "sign_update" -not -path "*/old_dsa_scripts/*" -type f 2>/dev/null | head -n1 || true)
  if [ -z "$SIGN_UPDATE" ]; then
    # Fall back to Sparkle's installed location
    SIGN_UPDATE=$(command -v sign_update 2>/dev/null || true)
  fi

  if [ -n "$SIGN_UPDATE" ]; then
    SIGNATURE=$(echo "$SPARKLE_EDDSA_KEY" | "$SIGN_UPDATE" .build/AIBattery.zip --ed-key-file -)
    echo "$SIGNATURE" > .build/sparkle-signature.txt
    echo "Sparkle signature saved to .build/sparkle-signature.txt"
  else
    echo "Warning: sign_update not found — skipping EdDSA signing"
  fi
fi

echo "Packaging DMG..."
DMG_DIR=".build/dmg"
DMG_RW=".build/AIBattery-rw.dmg"
rm -rf "$DMG_DIR" "$DMG_RW"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Set volume icon on the DMG
cp .build/AppIcon.icns "$DMG_DIR/.VolumeIcon.icns"
SetFile -a C "$DMG_DIR" 2>/dev/null || true

# Create read-write DMG, configure Finder layout, then convert to compressed
hdiutil create -volname "AI Battery" -srcfolder "$DMG_DIR" -ov -format UDRW "$DMG_RW"
rm -rf "$DMG_DIR"

# Mount the read-write DMG and configure Finder window layout
MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify | grep '/Volumes/' | tail -1 | awk -F'\t' '{print $NF}')
if [ -n "$MOUNT_DIR" ]; then
  # AppleScript configures icon view with drag-to-Applications layout.
  # May fail in headless CI (no Finder) — tolerate failure gracefully.
  osascript <<APPLESCRIPT || true
tell application "Finder"
  tell disk "AI Battery"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 540, 380}
    set opts to icon view options of container window
    set icon size of opts to 80
    set arrangement of opts to not arranged
    set position of item "AIBattery.app" of container window to {110, 140}
    set position of item "Applications" of container window to {330, 140}
    close
  end tell
end tell
APPLESCRIPT
  # Let Finder write .DS_Store
  sync
  sleep 1
  hdiutil detach "$MOUNT_DIR" -quiet
fi

hdiutil convert "$DMG_RW" -format UDZO -ov -o .build/AIBattery.dmg
rm -f "$DMG_RW"

# Optional notarization (requires Apple Developer credentials)
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo "Submitting for notarization..."
  xcrun notarytool submit .build/AIBattery.zip \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait
  xcrun stapler staple "$APP_DIR"

  # Re-package after stapling
  rm -f .build/AIBattery.zip .build/AIBattery.dmg
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" .build/AIBattery.zip

  # Re-create DMG with stapled app
  DMG_DIR=".build/dmg"
  DMG_RW=".build/AIBattery-rw.dmg"
  rm -rf "$DMG_DIR" "$DMG_RW"
  mkdir -p "$DMG_DIR"
  cp -R "$APP_DIR" "$DMG_DIR/"
  ln -s /Applications "$DMG_DIR/Applications"
  cp .build/AppIcon.icns "$DMG_DIR/.VolumeIcon.icns"
  SetFile -a C "$DMG_DIR" 2>/dev/null || true
  hdiutil create -volname "AI Battery" -srcfolder "$DMG_DIR" -ov -format UDZO .build/AIBattery.dmg
  rm -rf "$DMG_DIR"

  # Notarize and staple the DMG itself (allows offline Gatekeeper verification of the .dmg)
  xcrun notarytool submit .build/AIBattery.dmg \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait
  xcrun stapler staple .build/AIBattery.dmg
  echo "Notarization + stapling complete."
fi

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
