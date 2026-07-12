#!/usr/bin/env bash

set -euo pipefail

: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to a bootable iPhone simulator UUID}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT/ios/build/Debug-iphonesimulator/agent.cy.app}"
LAUNCH_RUNS="${LAUNCH_RUNS:-3}"
BUNDLE_ID="com.agentcy.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

for ((run = 1; run <= LAUNCH_RUNS; run++)); do
  xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
  launch_output="$(xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID")"
  pid="${launch_output##*: }"
  sleep 1
  process_info="$(xcrun simctl spawn "$SIMULATOR_UDID" launchctl procinfo "$pid")"
  if ! grep -q "job state = running" <<<"$process_info"; then
    echo "Launch $run failed to remain running (pid $pid)." >&2
    exit 1
  fi
  echo "Launch $run remained running (pid $pid)."
done

