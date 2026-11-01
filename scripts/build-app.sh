#!/bin/bash
# Build AI Battery.app bundle from source
set -euo pipefail

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

cd "$(dirname "$0")/.."

echo "Building release binary..."
swift build -c release

APP_DIR=".build/AIBattery.app"

# Clear release artifacts that are only valid for the current build.
# Otherwise stale signatures/appcasts can survive and make verification misleading.
rm -f .build/sparkle-signature.txt .build/appcast.xml

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
# SPM resource bundle (provider brand marks, AIBattery/Resources/*.svg). The app resolves
# it explicitly from Contents/Resources (AIProvider.markURL — NOT Bundle.module, whose
# generated accessor only checks the .app root and an absolute build-machine path, then
# traps). Without this copy the header badges silently fall back to SF symbols.
cp -R .build/release/AIBattery_AIBatteryCore.bundle "$APP_DIR/Contents/Resources/"

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
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${SPARKLE_EDDSA_PUBLIC_KEY}" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${SPARKLE_EDDSA_PUBLIC_KEY}" "$APP_DIR/Contents/Info.plist"
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

# Codesign inside-out: XPC services → frameworks → app bundle.
# Each layer must be signed before its parent. Avoid --deep on the outer
# bundle — it would re-sign nested bundles with the app's identifier,
# breaking Sparkle's XPC services (macOS requires codesign identifier to
# match CFBundleIdentifier for XPC launch).
echo "Codesigning..."
if [ -d "$APP_DIR/Contents/Frameworks" ]; then
  for item in "$APP_DIR/Contents/Frameworks"/*.framework; do
    [ -e "$item" ] || continue
    # Sign XPC services first (innermost)
    for xpc in "$item"/Versions/Current/XPCServices/*.xpc; do
      [ -e "$xpc" ] || continue
      echo "  Signing XPC: $(basename "$xpc")"
      codesign --sign "$SIGN_IDENTITY" --force --options runtime "$xpc"
    done
    # Sign framework (without --deep — XPCs already signed)
    echo "  Signing: $(basename "$item")"
    codesign --sign "$SIGN_IDENTITY" --force --options runtime "$item"
  done
fi

# Select entitlements file (App Store builds use sandboxed entitlements)
ENTITLEMENTS="AIBattery/AIBattery.entitlements"
if [ -n "${APP_STORE_BUILD:-}" ]; then
  ENTITLEMENTS="AIBattery/AIBattery-AppStore.entitlements"
fi

# `com.apple.security.cs.disable-library-validation` lets the process holding live
# tokens load libraries signed by ANY identity — worth removing, and the bundle meets
# the condition for doing so (Sparkle.framework and its XPC services are re-signed
# above with this same identity). It can only come off a REAL identity, though: an
# ad-hoc signature ("-") has no Team ID, so library validation could never pass and
# Sparkle would fail to load at launch. So: strip it when signing for real, keep it
# for ad-hoc local builds.
if [ "$SIGN_IDENTITY" != "-" ] && [ -z "${KEEP_LIBRARY_VALIDATION_EXEMPTION:-}" ]; then
  HARDENED_ENTITLEMENTS=".build/AIBattery-hardened.entitlements"
  cp "$ENTITLEMENTS" "$HARDENED_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.cs.disable-library-validation" \
    "$HARDENED_ENTITLEMENTS" >/dev/null 2>&1 || true
  ENTITLEMENTS="$HARDENED_ENTITLEMENTS"
  echo "Signing with library validation ENABLED (set KEEP_LIBRARY_VALIDATION_EXEMPTION=1 to opt out)"
fi

# Codesign the outer bundle (without --deep — inner bundles already signed)
codesign --sign "$SIGN_IDENTITY" --force \
  --entitlements "$ENTITLEMENTS" \
  --identifier com.KyleNesium.AIBattery \
  --options runtime \
  "$APP_DIR"

# Verify XPC services retained their original bundle identifiers
for xpc in "$APP_DIR"/Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/*.xpc; do
  [ -e "$xpc" ] || continue
  EXPECTED_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$xpc/Contents/Info.plist")
  ACTUAL_ID=$(codesign -dv "$xpc" 2>&1 | grep "^Identifier=" | cut -d= -f2)
  if [ "$EXPECTED_ID" != "$ACTUAL_ID" ]; then
    echo "ERROR: $(basename "$xpc") identifier mismatch: expected=$EXPECTED_ID actual=$ACTUAL_ID"
    exit 1
  fi
  echo "  Verified: $(basename "$xpc") → $ACTUAL_ID"
done

echo "Done! App bundle at: $APP_DIR"

# Create distribution artifacts
echo "Packaging zip..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" .build/AIBattery.zip

# EdDSA-sign the zip for Sparkle (when SPARKLE_EDDSA_KEY env is set).
#
# A function, not a straight-line block, because the notarization path below
# REPLACES the zip after stapling. Signing only once, before that, left
# sparkle-signature.txt describing a file that no longer existed — and
# generate-appcast.sh copies both `edSignature` and `length` straight out of it.
# verify-release.sh catches the length mismatch, so this would have hard-failed
# the first signed release rather than shipping a bad update.
sign_zip_for_sparkle() {
  [ -n "${SPARKLE_EDDSA_KEY:-}" ] || return 0
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
}

sign_zip_for_sparkle

# Build the distributable DMG: volume icon, Finder icon-view layout, then compress.
#
# A function because the notarization path repackages after stapling. That path used
# to call a bare `hdiutil create ... UDZO`, silently dropping the volume icon and the
# drag-to-Applications layout from exactly the builds users download.
package_dmg() {
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
    # Finder can still hold the volume for a few seconds after the AppleScript
    # returns; a single detach then fails with "Resource busy" (hdiutil exit 16)
    # and `set -e` kills the whole build. Seen on the macos-15 runner (main CI run
    # 38137172281) while the release run on the same commit sailed through.
    # Retry, then force — the layout is already written, so a forced eject is safe.
    detached=0
    for attempt in 1 2 3 4 5; do
      if hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null; then
        detached=1
        break
      fi
      echo "  detach attempt $attempt failed (volume busy) — retrying"
      sleep 2
    done
    if [ "$detached" -eq 0 ]; then
      # The volume can finish unmounting between the last retry and this line, and a
      # forced detach of something already gone exits non-zero with "No such file or
      # directory" — which `set -e` then turned into a failed release. The retry loop
      # added in #194 handled "busy" but not "already unmounted"; this is the other half.
      echo "  forcing detach of $MOUNT_DIR"
      hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    fi

    # Only one thing actually matters: the volume must be gone before we convert. A
    # detach that reported failure because it had already unmounted is a success.
    if [ -d "$MOUNT_DIR" ]; then
      echo "  ERROR: $MOUNT_DIR is still mounted after detach attempts"
      exit 1
    fi
  fi

  hdiutil convert "$DMG_RW" -format UDZO -ov -o .build/AIBattery.dmg
  rm -f "$DMG_RW"
}

package_dmg

# Optional notarization (requires Apple Developer credentials)
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo "Submitting for notarization..."
  for attempt in 1 2 3; do
    echo "Notarization attempt $attempt..."
    if xcrun notarytool submit .build/AIBattery.zip \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "${APPLE_APP_PASSWORD}" \
      --wait; then
      break
    fi
    [ "$attempt" -lt 3 ] && sleep 30
    [ "$attempt" -eq 3 ] && { echo "Notarization failed after 3 attempts"; exit 1; }
  done
  xcrun stapler staple "$APP_DIR"

  # Re-package after stapling, then re-sign: the zip signed before notarization
  # describes a file that no longer exists.
  rm -f .build/AIBattery.zip .build/AIBattery.dmg
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" .build/AIBattery.zip
  sign_zip_for_sparkle

  # Re-create the DMG with the stapled app, through the same packaging as above so
  # the notarized DMG keeps its volume icon and Finder layout.
  package_dmg
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
