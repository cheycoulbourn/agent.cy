#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# "Inter only, no SF" — anything that names a non-Inter font family, a monospaced
# variant, or a bare system-font call is banned from shipped Swift/config sources.
PATTERN='agentMono|paperMono|widgetMono|IBMPlexMono|IBM Plex Mono|\.monospaced\(\)|\.fontDesign\(\.monospaced\)|\.font\(\.system|\.font\(\.caption|UIFont\.systemFont'

REQUIRED_TOOLS=(grep find)

preflight() {
  local missing=()
  local tool
  for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "check_inter_typography.sh: missing required tool(s): ${missing[*]}" >&2
    exit 1
  fi
}

# Runs the ban-pattern scan against the given paths (files or directories).
# Exit status 0 means it found at least one match; 1 means clean. Prints
# file:line matches to stdout as it goes (grep's normal behavior).
run_typography_scan() {
  grep -rnE \
    --include='*.swift' --include='*.yml' \
    --exclude-dir='build-device' --exclude-dir='*.xcodeproj' \
    "$PATTERN" \
    "$@"
}

self_test() {
  local failures=0
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Fixture that must fail: a raw system-font call, one of the eight live
  # violation shapes this gate exists to catch.
  cat > "$tmp/Fail.swift" <<'EOF'
import SwiftUI
struct Fail: View {
    var body: some View {
        Text("hi").font(.system(size: 10, weight: .medium))
    }
}
EOF

  # Fixture that must pass: a semantic Inter token, no banned pattern.
  cat > "$tmp/Pass.swift" <<'EOF'
import SwiftUI
struct Pass: View {
    var body: some View {
        Text("hi").font(.agentBody)
    }
}
EOF

  if run_typography_scan "$tmp/Fail.swift" >/dev/null; then
    echo "self-test ok: Fail.swift correctly flagged"
  else
    echo "self-test FAIL: Fail.swift did not trigger the typography ban" >&2
    failures=$((failures + 1))
  fi

  if run_typography_scan "$tmp/Pass.swift" >/dev/null; then
    echo "self-test FAIL: Pass.swift was incorrectly flagged" >&2
    failures=$((failures + 1))
  else
    echo "self-test ok: Pass.swift correctly clean"
  fi

  # Missing-tool preflight: restrict PATH to /bin (has bash, lacks grep/find,
  # which live in /usr/bin on macOS) and confirm the script exits non-zero
  # instead of silently reporting success, per L4-11.
  if PATH=/bin "$ROOT/scripts/check_inter_typography.sh" >/tmp/check_inter_typography.self-test.out 2>&1; then
    echo "self-test FAIL: script did not exit non-zero with grep/find missing from PATH" >&2
    failures=$((failures + 1))
  else
    echo "self-test ok: missing-tool preflight exits non-zero"
  fi
  rm -f /tmp/check_inter_typography.self-test.out

  if [[ $failures -gt 0 ]]; then
    echo "check_inter_typography.sh self-test: $failures failure(s)" >&2
    exit 1
  fi
  echo "check_inter_typography.sh self-test: all checks passed."
  exit 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
fi

preflight

SEARCH_PATHS=(
  "$ROOT/ios/AgentCy"
  "$ROOT/ios/AgentCyWidgets"
  "$ROOT/ios/AgentCyShared"
  "$ROOT/ios/AgentCyInspirationShare"
  "$ROOT/ios/AgentCyTests"
  "$ROOT/ios/project.yml"
)

if run_typography_scan "${SEARCH_PATHS[@]}"; then
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
