#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEARCH_PATHS=(
  "$ROOT/ios/AgentCy"
  "$ROOT/ios/AgentCyWidgets"
  "$ROOT/ios/AgentCyShared"
  "$ROOT/ios/AgentCyTests"
  "$ROOT/ios/project.yml"
)

if rg -n \
  'agentMono|paperMono|widgetMono|IBMPlexMono|IBM Plex Mono|\.monospaced\(\)|\.fontDesign\(\.monospaced\)|\.font\(\.system|\.font\(\.caption|UIFont\.systemFont' \
  "${SEARCH_PATHS[@]}" \
  --glob '!build-device/**' \
  --glob '!*.xcodeproj/**'; then
  echo "Non-Inter typography reference found." >&2
  exit 1
fi

font_assets="$(find "$ROOT/ios/AgentCy/Resources/Fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print)"
expected_font="$ROOT/ios/AgentCy/Resources/Fonts/InterVariable.ttf"
if [[ "$font_assets" != "$expected_font" ]]; then
  echo "InterVariable.ttf must be the only bundled font asset." >&2
  printf '%s\n' "$font_assets" >&2
  exit 1
fi

echo "Inter typography check passed."
