#!/bin/bash
# Pre-release verification — run before tagging/releasing to catch common issues.
# Usage: ./scripts/verify-release.sh <version>
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: verify-release.sh <version>}"
ERRORS=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; ERRORS=$((ERRORS + 1)); }

echo "=== AIBattery Pre-Release Verification: v${VERSION} ==="
echo ""

# 1. Check Info.plist version matches
echo "── Version consistency"
PLIST_VERSION=$(grep -A1 'CFBundleShortVersionString' AIBattery/Info.plist | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
if [ "$PLIST_VERSION" = "$VERSION" ]; then
  pass "Info.plist version: $PLIST_VERSION"
else
  fail "Info.plist version ($PLIST_VERSION) does not match expected ($VERSION)"
fi

# Check CHANGELOG has the version
if grep -q "## \[${VERSION}\]" CHANGELOG.md; then
  pass "CHANGELOG.md has entry for v${VERSION}"
else
  fail "CHANGELOG.md missing entry for v${VERSION}"
fi

# 2. Check build artifacts exist
echo ""
echo "── Build artifacts"
if [ -f .build/AIBattery.zip ]; then
  ZIP_SIZE=$(stat -f%z .build/AIBattery.zip 2>/dev/null || stat -c%s .build/AIBattery.zip 2>/dev/null)
  pass "AIBattery.zip exists (${ZIP_SIZE} bytes)"
else
  fail "AIBattery.zip not found — run build-app.sh first"
fi

if [ -f .build/AIBattery.dmg ]; then
  pass "AIBattery.dmg exists"
else
  fail "AIBattery.dmg not found"
fi

# 3. Check Sparkle signature
echo ""
echo "── Sparkle signing"
if [ -f .build/sparkle-signature.txt ]; then
  SIG_LINE=$(cat .build/sparkle-signature.txt)
  if echo "$SIG_LINE" | grep -q 'sparkle:edSignature='; then
    pass "Sparkle EdDSA signature present"
  else
    fail "Sparkle signature file exists but doesn't contain edSignature"
  fi
  # Check signature length matches ZIP size
  SIG_LENGTH=$(echo "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
  if [ -n "$SIG_LENGTH" ] && [ -n "${ZIP_SIZE:-}" ]; then
    if [ "$SIG_LENGTH" = "$ZIP_SIZE" ]; then
      pass "Signature length ($SIG_LENGTH) matches ZIP size"
    else
      fail "Signature length ($SIG_LENGTH) does not match ZIP size ($ZIP_SIZE)"
    fi
  fi
else
  fail "sparkle-signature.txt not found — was SPARKLE_EDDSA_KEY set during build?"
fi

# 4. Check app bundle
echo ""
echo "── App bundle"
APP_BUNDLE=".build/AIBattery.app"
if [ -d "$APP_BUNDLE" ]; then
  pass "AIBattery.app bundle exists"

  # Check Sparkle framework
  if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
    pass "Sparkle.framework present"
  else
    fail "Sparkle.framework missing from bundle"
  fi

  # Check Info.plist keys
  BUNDLE_PLIST="$APP_BUNDLE/Contents/Info.plist"
  if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$BUNDLE_PLIST" &>/dev/null; then
    FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$BUNDLE_PLIST")
    pass "SUFeedURL: $FEED_URL"
  else
    fail "SUFeedURL missing from bundled Info.plist"
  fi

  if /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$BUNDLE_PLIST" &>/dev/null; then
    pass "SUPublicEDKey present"
  else
    fail "SUPublicEDKey missing from bundled Info.plist"
  fi

  # Check bundled version matches
  BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUNDLE_PLIST")
  if [ "$BUNDLE_VERSION" = "$VERSION" ]; then
    pass "Bundle version: $BUNDLE_VERSION"
  else
    fail "Bundle version ($BUNDLE_VERSION) does not match expected ($VERSION)"
  fi

  # Check codesign
  if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    pass "Codesign verification passed"
  else
    fail "Codesign verification failed"
  fi
else
  fail "AIBattery.app not found in .build/"
fi

# 5. Check appcast (if generated)
echo ""
echo "── Appcast"
if [ -f .build/appcast.xml ]; then
  APPCAST_VERSION=$(grep 'sparkle:version' .build/appcast.xml | sed 's/.*>\(.*\)<.*/\1/')
  if [ "$APPCAST_VERSION" = "$VERSION" ]; then
    pass "Local appcast version: $APPCAST_VERSION"
  else
    fail "Local appcast version ($APPCAST_VERSION) does not match expected ($VERSION)"
  fi
else
  echo "  ⚠ No local appcast.xml — run generate-appcast.sh after build"
fi

# Check live appcast
echo ""
echo "── Live appcast"
LIVE_APPCAST=$(curl -s https://kylenesium.github.io/AIBattery/appcast.xml 2>/dev/null || echo "")
if [ -n "$LIVE_APPCAST" ]; then
  LIVE_VERSION=$(echo "$LIVE_APPCAST" | grep 'sparkle:version' | sed 's/.*>\(.*\)<.*/\1/')
  echo "  Live appcast version: $LIVE_VERSION"
  if [ "$LIVE_VERSION" = "$VERSION" ]; then
    pass "Live appcast matches release version"
  else
    echo "  ⚠ Live appcast ($LIVE_VERSION) not yet updated to $VERSION"
    echo "    Run: ./scripts/generate-appcast.sh $VERSION && push to gh-pages"
  fi
else
  echo "  ⚠ Could not fetch live appcast (network issue?)"
fi

# Summary
echo ""
echo "════════════════════════════"
if [ $ERRORS -eq 0 ]; then
  echo "  All checks passed ✓"
else
  echo "  $ERRORS check(s) FAILED ✗"
fi
echo "════════════════════════════"
exit $ERRORS
