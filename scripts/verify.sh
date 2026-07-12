#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5}"
IOS_SOURCE_ONLY="${IOS_SOURCE_ONLY:-0}"

cd "$ROOT"

pnpm install --frozen-lockfile
pnpm typecheck
pnpm test
pnpm build

cd "$ROOT/ios"
xcodegen generate

if [[ "$IOS_SOURCE_ONLY" == "1" ]]; then
  COMMON_SOURCE_SETTINGS=(
    -project AgentCy.xcodeproj
    -sdk iphonesimulator
    -configuration Debug
    CODE_SIGNING_ALLOWED=NO
    EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets
    ASSETCATALOG_COMPILER_APPICON_NAME=
    ARCHS=arm64
    ONLY_ACTIVE_ARCH=YES
  )
  xcodebuild -target AgentCy "${COMMON_SOURCE_SETTINGS[@]}" build
  xcodebuild -target AgentCyTests "${COMMON_SOURCE_SETTINGS[@]}" build
  exit 0
fi

xcodebuild \
  -project AgentCy.xcodeproj \
  -scheme AgentCy \
  -destination "$IOS_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project AgentCy.xcodeproj \
  -scheme AgentCy \
  -destination "$IOS_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  test
