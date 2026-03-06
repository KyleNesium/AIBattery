#!/bin/bash
# Build AI Battery for App Store submission via XcodeGen + xcodebuild archive
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Generating Xcode project..."
xcodegen generate

# Strip Sparkle feed URL — App Store rejects apps with third-party update mechanisms
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" AIBattery/Info.plist 2>/dev/null || true

# Inject version from git tag if available
GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || true)
VERSION_OVERRIDE=""
if [ -n "$GIT_TAG" ]; then
  VERSION="${GIT_TAG#v}"
  VERSION_OVERRIDE="MARKETING_VERSION=${VERSION} CURRENT_PROJECT_VERSION=${VERSION}"
  echo "Using version ${VERSION} from tag ${GIT_TAG}"
fi

echo "Archiving for App Store..."
# shellcheck disable=SC2086
xcodebuild archive \
  -project AIBattery.xcodeproj \
  -scheme AIBattery \
  -configuration AppStore \
  -archivePath .build/AIBattery.xcarchive \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  ${VERSION_OVERRIDE} \
  -quiet

echo "Exporting for App Store Connect..."
xcodebuild -exportArchive \
  -archivePath .build/AIBattery.xcarchive \
  -exportPath .build/appstore \
  -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
  -quiet

# Restore source Info.plist (avoid leaving modified working tree)
git checkout -- AIBattery/Info.plist 2>/dev/null || true

echo ""
echo "App Store build ready at: .build/appstore/"
echo "Upload with: xcrun altool --upload-app -f .build/appstore/AIBattery.pkg -t macos --apiKey \$KEY_ID --apiIssuer \$ISSUER_ID"
