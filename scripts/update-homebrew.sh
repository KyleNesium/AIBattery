#!/bin/bash
# Updates the Homebrew cask formula in KyleNesium/homebrew-tap after a release.
# Called by the release GitHub Action — requires GH_TOKEN with repo scope.

set -euo pipefail

VERSION="${1:?Usage: update-homebrew.sh <version>}"
VERSION="${VERSION#v}"  # Strip leading 'v' if present

ZIP_URL="https://github.com/KyleNesium/AIBattery/releases/download/v${VERSION}/AIBattery.zip"

echo "Downloading AIBattery.zip for v${VERSION}..."
curl -fSL "$ZIP_URL" -o /tmp/aibattery-release.zip
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

# Validation gate: the cask must pass `brew style` before we publish it, so
# deprecated syntax (e.g. the `depends_on macos: ">= :ventura"` string-comparison
# form) can never reach users through the tap again. Auto-correct what Homebrew
# can fix, then hard-fail the release if any offense remains.
if command -v brew >/dev/null 2>&1; then
  echo "Validating cask with brew style..."
  brew style --fix "$CASK_FILE" || true
  if ! brew style "$CASK_FILE"; then
    echo "ERROR: brew style reported offenses in ${CASK_FILE} — aborting release." >&2
    echo "Fix the cask in KyleNesium/homebrew-tap (or the generator) and re-run." >&2
    exit 1
  fi
  echo "brew style: clean."
else
  echo "ERROR: brew not found on PATH — cannot validate cask. Aborting." >&2
  echo "The release runner must have Homebrew installed to gate cask style." >&2
  exit 1
fi

cd "$WORKDIR"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Casks/aibattery.rb
git commit -m "Update aibattery to v${VERSION}"
git push

echo "Homebrew cask updated to v${VERSION}"
rm -rf "$WORKDIR" /tmp/aibattery-release.zip
