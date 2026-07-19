#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="${BUILD_NUMBER:-$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' "$ROOT/ios/project.yml" | head -1)}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/AgentCy-TestFlight-${BUILD_NUMBER}-${TIMESTAMP}.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-/tmp/AgentCy-TestFlight-${BUILD_NUMBER}-${TIMESTAMP}}"
VERIFY="${VERIFY:-1}"
EXPORT="${EXPORT:-0}"

if [[ -z "$BUILD_NUMBER" ]]; then
  echo "Could not determine CURRENT_PROJECT_VERSION from ios/project.yml." >&2
  exit 1
fi

if [[ "$VERIFY" == "1" ]]; then
  "$ROOT/scripts/verify.sh"
fi

cd "$ROOT/ios"
xcodegen generate

xcodebuild archive \
  -project AgentCy.xcodeproj \
  -scheme AgentCy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Automatic

echo "Archive ready: $ARCHIVE_PATH"

if [[ "$EXPORT" != "1" ]]; then
  echo "Set EXPORT=1 to verify App Store Connect distribution signing and create an IPA."
  exit 0
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT/ios/ExportOptions-TestFlight.plist" \
  -allowProvisioningUpdates

echo "App Store Connect export ready: $EXPORT_PATH"
