#!/bin/bash
# Updates the Homebrew cask formula in KyleNesium/homebrew-tap after a release.
# Called by the release GitHub Action — requires GH_TOKEN with repo scope.

set -euo pipefail

VERSION="${1:?Usage: update-homebrew.sh <version>}"
VERSION="${VERSION#v}"  # Strip leading 'v' if present

ZIP_URL="https://github.com/KyleNesium/AIBattery/releases/download/v${VERSION}/AIBattery.zip"

echo "Downloading AIBattery.zip for v${VERSION}..."
curl -sL "$ZIP_URL" -o /tmp/aibattery-release.zip
SHA256=$(shasum -a 256 /tmp/aibattery-release.zip | awk '{print $1}')
echo "SHA256: ${SHA256}"

echo "Cloning homebrew-tap..."
WORKDIR=$(mktemp -d)
git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/KyleNesium/homebrew-tap.git" "$WORKDIR"

CASK_FILE="$WORKDIR/Casks/aibattery.rb"

# Update version and sha256
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK_FILE"
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"

echo "Updated cask formula:"
head -5 "$CASK_FILE"

cd "$WORKDIR"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/aibattery.rb
git commit -m "Update aibattery to v${VERSION}"
git push

echo "Homebrew cask updated to v${VERSION}"
rm -rf "$WORKDIR" /tmp/aibattery-release.zip
