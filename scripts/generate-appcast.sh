#!/bin/bash
# Generate appcast.xml for Sparkle auto-updates
# Usage: ./scripts/generate-appcast.sh <version> [signature-file]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?Usage: generate-appcast.sh <version> [signature-file]}"
SIGNATURE_FILE="${2:-.build/sparkle-signature.txt}"

# Validate version looks like semver (digits and dots)
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
  echo "Error: VERSION '$VERSION' does not look like semver (expected X.Y.Z)"
  exit 1
fi

# Read EdDSA signature (contains sparkle:edSignature="..." sparkle:length="...")
if [ ! -f "$SIGNATURE_FILE" ]; then
  echo "Error: Signature file not found: $SIGNATURE_FILE"
  echo "Run build-app.sh with SPARKLE_EDDSA_KEY set first."
  exit 1
fi

SIGNATURE_LINE=$(cat "$SIGNATURE_FILE")

# Parse sparkle:edSignature and length from the sign_update output
# (macOS grep doesn't support -P, so use sed)
ED_SIGNATURE=$(echo "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_LENGTH=$(echo "$SIGNATURE_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

# Fallback: if sign_update outputs just the signature string
if [ -z "$ED_SIGNATURE" ]; then
  ED_SIGNATURE="$SIGNATURE_LINE"
fi

# Get file length from zip if not parsed from signature output
if [ -z "$FILE_LENGTH" ]; then
  if [ ! -f .build/AIBattery.zip ]; then
    echo "Error: .build/AIBattery.zip not found — cannot determine file length"
    exit 1
  fi
  FILE_LENGTH=$(stat -f%z .build/AIBattery.zip 2>/dev/null || stat -c%s .build/AIBattery.zip 2>/dev/null)
fi

if [ -z "$ED_SIGNATURE" ] || [ -z "$FILE_LENGTH" ]; then
  echo "Error: Could not determine EdDSA signature or file length"
  exit 1
fi

DOWNLOAD_URL="https://github.com/KyleNesium/AIBattery/releases/download/v${VERSION}/AIBattery.zip"

cat > .build/appcast.xml << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>AI Battery</title>
    <link>https://kylenesium.github.io/AIBattery/appcast.xml</link>
    <description>AI Battery update feed</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${FILE_LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
APPCAST_EOF

echo "Generated .build/appcast.xml for v${VERSION}"
echo "  Download URL: ${DOWNLOAD_URL}"
echo "  File length:  ${FILE_LENGTH}"
