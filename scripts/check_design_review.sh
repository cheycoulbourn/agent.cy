#!/usr/bin/env bash

set -euo pipefail

# check_design_review.sh — a ratchet, not a hard gate.
#
# Greps shipped Swift UI sources for five design-consistency bans and compares
# each rule's current violation count against a checked-in baseline
# (scripts/design-review-baseline.txt). It fails (exit 1) only when a rule's
# count goes UP from its baseline; it passes when counts are equal or lower.
# Every violation is printed with file:line either way, pass or fail, so the
# output is useful even on a passing run.
#
# Usage:
#   check_design_review.sh                 run the ratchet against the baseline
#   check_design_review.sh --update-baseline   rewrite the baseline from current counts
#   check_design_review.sh --self-test     run this script's own fixture tests

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_FILE="$ROOT/scripts/design-review-baseline.txt"

REQUIRED_TOOLS=(grep find)

# Parallel arrays (bash 3.2 on this Mac has no associative arrays) —
# RULE_IDS[i] / RULE_PATTERNS[i] / RULE_DESCRIPTIONS[i] describe the same rule.
RULE_IDS=(
  sf_symbols
  animation_curves
  banned_fonts
  corner_radius
  pill_background
)
RULE_PATTERNS=(
  'Image\(systemName:|systemImage:'
  '\.animation\(\.(easeIn|easeOut|easeInOut|linear|spring|interactiveSpring|interpolatingSpring)\b|withAnimation\(\.(easeIn|easeOut|easeInOut|linear|spring|interactiveSpring|interpolatingSpring)\b'
  'Font\.custom\(|paperInter|paperMetadata|\.font\(\.system'
  'cornerRadius: (3|5|6|9|13|14|18|22)\b'
  'background\(Color\.(cyAccent|actionAccent)[^)]*in: *\.(capsule|circle)'
)
RULE_DESCRIPTIONS=(
  "SF Symbols in shipped UI (Image(systemName:) / systemImage:) — design.md bans SF Symbols outright"
  "Raw animation curve outside AgentMotion (.animation/.withAnimation with a literal curve)"
  "Non-Inter or off-token font reference (Font.custom / paperInter / paperMetadata / .font(.system)"
  "Off-scale cornerRadius literal (3/5/6/9/13/14/18/22 — not an AgentRadius token)"
  "Accent-filled capsule/circle background (solid-fill pill button banned per design.md)"
)

preflight() {
  local missing=()
  local tool
  for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "check_design_review.sh: missing required tool(s): ${missing[*]}" >&2
    exit 1
  fi
}

# Scans the given search paths for one rule's pattern. Prints file:line
# matches to stdout. Never fails the script on "no matches" (grep's exit 1).
scan_rule() {
  local pattern="$1"
  shift
  local matches
  matches="$(grep -rnE --include='*.swift' --exclude-dir='build-device' --exclude-dir='*.xcodeproj' "$pattern" "$@" 2>/dev/null || true)"
  printf '%s' "$matches"
}

count_lines() {
  local text="$1"
  if [[ -z "$text" ]]; then
    echo 0
  else
    printf '%s\n' "$text" | grep -c '' || true
  fi
}

# Reads a rule's baseline count out of a baseline file. Echoes -1 if the rule
# has no entry (treated as "unknown baseline", handled by the caller).
baseline_for() {
  local file="$1"
  local rule_id="$2"
  local line
  if [[ ! -f "$file" ]]; then
    echo -1
    return
  fi
  line="$(grep -E "^${rule_id}=" "$file" 2>/dev/null || true)"
  if [[ -z "$line" ]]; then
    echo -1
  else
    echo "${line#*=}"
  fi
}

# Runs every rule against the given search paths, prints violations and a
# summary, and compares against $baseline_file. Sets the global
# RATCHET_EXIT_CODE (0 or 1). If update_mode=1, writes fresh baseline counts
# to $baseline_file instead of failing on regressions.
RATCHET_EXIT_CODE=0

run_design_review() {
  local baseline_file="$1"
  local update_mode="$2"
  shift 2
  local search_paths=("$@")

  RATCHET_EXIT_CODE=0
  local new_baseline_lines=()
  local i
  local any_violations=0

  for i in "${!RULE_IDS[@]}"; do
    local rule_id="${RULE_IDS[$i]}"
    local pattern="${RULE_PATTERNS[$i]}"
    local description="${RULE_DESCRIPTIONS[$i]}"

    local matches
    matches="$(scan_rule "$pattern" "${search_paths[@]}")"
    local count
    count="$(count_lines "$matches")"

    echo "== $rule_id — $description =="
    if [[ "$count" -gt 0 ]]; then
      any_violations=1
      printf '%s\n' "$matches"
    else
      echo "(no matches)"
    fi

    local baseline
    baseline="$(baseline_for "$baseline_file" "$rule_id")"

    if [[ "$update_mode" -eq 1 ]]; then
      new_baseline_lines+=("${rule_id}=${count}")
      echo "-- $rule_id: $count violation(s), baseline updated"
    elif [[ "$baseline" -lt 0 ]]; then
      echo "-- $rule_id: $count violation(s), NO BASELINE ENTRY (treated as 0, so any hit fails)" >&2
      if [[ "$count" -gt 0 ]]; then
        RATCHET_EXIT_CODE=1
      fi
    elif [[ "$count" -gt "$baseline" ]]; then
      echo "-- $rule_id: $count violation(s) > baseline $baseline -- FAIL" >&2
      RATCHET_EXIT_CODE=1
    else
      echo "-- $rule_id: $count violation(s) <= baseline $baseline -- ok"
    fi
    echo
  done

  if [[ "$update_mode" -eq 1 ]]; then
    {
      printf '# design-review ratchet baseline — per-rule violation counts.\n'
      printf '# Regenerate with: scripts/check_design_review.sh --update-baseline\n'
      printf '%s\n' "${new_baseline_lines[@]}"
    } > "$baseline_file"
    echo "Baseline written to $baseline_file"
    RATCHET_EXIT_CODE=0
  fi

  if [[ "$any_violations" -eq 0 && "$update_mode" -ne 1 ]]; then
    echo "No violations found for any rule."
  fi
}

self_test() {
  local failures=0
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  echo "--- per-rule fixtures ---"

  # sf_symbols
  cat > "$tmp/SfFail.swift" <<'EOF'
import SwiftUI
struct SfFail: View { var body: some View { Image(systemName: "star") } }
EOF
  cat > "$tmp/SfPass.swift" <<'EOF'
import SwiftUI
struct SfPass: View { var body: some View { Image("star-icon") } }
EOF

  # animation_curves
  cat > "$tmp/AnimFail.swift" <<'EOF'
import SwiftUI
struct AnimFail: View {
    var body: some View {
        Text("hi").onAppear { withAnimation(.easeInOut(duration: 0.2)) {} }
    }
}
EOF
  cat > "$tmp/AnimPass.swift" <<'EOF'
import SwiftUI
struct AnimPass: View {
    var body: some View {
        Text("hi").onAppear { withAnimation(AgentMotion.standard) {} }
    }
}
EOF

  # banned_fonts
  cat > "$tmp/FontFail.swift" <<'EOF'
import SwiftUI
struct FontFail: View { var body: some View { Text("hi").font(.system(size: 10)) } }
EOF
  cat > "$tmp/FontPass.swift" <<'EOF'
import SwiftUI
struct FontPass: View { var body: some View { Text("hi").font(.agentBody) } }
EOF

  # corner_radius
  cat > "$tmp/RadiusFail.swift" <<'EOF'
import SwiftUI
struct RadiusFail: View {
    var body: some View { Color.clear.clipShape(.rect(cornerRadius: 14)) }
}
EOF
  cat > "$tmp/RadiusPass.swift" <<'EOF'
import SwiftUI
struct RadiusPass: View {
    var body: some View { Color.clear.clipShape(.rect(cornerRadius: AgentRadius.panel)) }
}
EOF

  # pill_background
  cat > "$tmp/PillFail.swift" <<'EOF'
import SwiftUI
struct PillFail: View {
    var body: some View { Text("Go").background(Color.cyAccent, in: .capsule) }
}
EOF
  cat > "$tmp/PillPass.swift" <<'EOF'
import SwiftUI
struct PillPass: View {
    var body: some View { Text("Go").background(Color.cyAccent.opacity(0.08), in: .rect(cornerRadius: 12)) }
}
EOF

  local rule_fail_file=(SfFail AnimFail FontFail RadiusFail PillFail)
  local rule_pass_file=(SfPass AnimPass FontPass RadiusPass PillPass)

  local i
  for i in "${!RULE_IDS[@]}"; do
    local rule_id="${RULE_IDS[$i]}"
    local pattern="${RULE_PATTERNS[$i]}"
    local fail_file="$tmp/${rule_fail_file[$i]}.swift"
    local pass_file="$tmp/${rule_pass_file[$i]}.swift"

    if [[ -n "$(scan_rule "$pattern" "$fail_file")" ]]; then
      echo "self-test ok: $rule_id correctly flags its fail fixture"
    else
      echo "self-test FAIL: $rule_id did not flag ${rule_fail_file[$i]}.swift" >&2
      failures=$((failures + 1))
    fi

    if [[ -z "$(scan_rule "$pattern" "$pass_file")" ]]; then
      echo "self-test ok: $rule_id correctly clears its pass fixture"
    else
      echo "self-test FAIL: $rule_id incorrectly flagged ${rule_pass_file[$i]}.swift" >&2
      failures=$((failures + 1))
    fi
  done

  echo
  echo "--- ratchet mechanics ---"

  # One rule, one fixture directory with exactly 2 violations.
  local ratchet_dir="$tmp/ratchet"
  mkdir -p "$ratchet_dir"
  cat > "$ratchet_dir/One.swift" <<'EOF'
import SwiftUI
struct One: View { var body: some View { Image(systemName: "a") } }
EOF
  cat > "$ratchet_dir/Two.swift" <<'EOF'
import SwiftUI
struct Two: View { var body: some View { Image(systemName: "b") } }
EOF

  # Baseline equal to current count (2) must pass.
  local equal_baseline="$tmp/baseline-equal.txt"
  printf 'sf_symbols=2\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\n' > "$equal_baseline"
  if run_design_review "$equal_baseline" 0 "$ratchet_dir" >/dev/null 2>&1; [[ "$RATCHET_EXIT_CODE" -eq 0 ]]; then
    echo "self-test ok: count == baseline passes"
  else
    echo "self-test FAIL: count == baseline should pass, exit code was $RATCHET_EXIT_CODE" >&2
    failures=$((failures + 1))
  fi

  # Baseline below current count (1 < 2) must fail.
  local low_baseline="$tmp/baseline-low.txt"
  printf 'sf_symbols=1\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\n' > "$low_baseline"
  if run_design_review "$low_baseline" 0 "$ratchet_dir" >/dev/null 2>&1; [[ "$RATCHET_EXIT_CODE" -eq 1 ]]; then
    echo "self-test ok: count > baseline fails"
  else
    echo "self-test FAIL: count > baseline should fail, exit code was $RATCHET_EXIT_CODE" >&2
    failures=$((failures + 1))
  fi

  # Baseline above current count (3 > 2) must pass (ratchet only tightens).
  local high_baseline="$tmp/baseline-high.txt"
  printf 'sf_symbols=3\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\n' > "$high_baseline"
  if run_design_review "$high_baseline" 0 "$ratchet_dir" >/dev/null 2>&1; [[ "$RATCHET_EXIT_CODE" -eq 0 ]]; then
    echo "self-test ok: count < baseline passes"
  else
    echo "self-test FAIL: count < baseline should pass, exit code was $RATCHET_EXIT_CODE" >&2
    failures=$((failures + 1))
  fi

  # --update-baseline rewrites the file from current counts.
  local update_target="$tmp/baseline-update.txt"
  printf 'sf_symbols=0\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\n' > "$update_target"
  run_design_review "$update_target" 1 "$ratchet_dir" >/dev/null 2>&1
  if grep -q '^sf_symbols=2$' "$update_target"; then
    echo "self-test ok: --update-baseline rewrites counts from a fresh scan"
  else
    echo "self-test FAIL: --update-baseline did not write sf_symbols=2" >&2
    failures=$((failures + 1))
  fi

  echo
  echo "--- missing-tool preflight ---"
  if PATH=/bin "$ROOT/scripts/check_design_review.sh" >/tmp/check_design_review.self-test.out 2>&1; then
    echo "self-test FAIL: script did not exit non-zero with grep/find missing from PATH" >&2
    failures=$((failures + 1))
  else
    echo "self-test ok: missing-tool preflight exits non-zero"
  fi
  rm -f /tmp/check_design_review.self-test.out

  echo
  if [[ $failures -gt 0 ]]; then
    echo "check_design_review.sh self-test: $failures failure(s)" >&2
    exit 1
  fi
  echo "check_design_review.sh self-test: all checks passed."
  exit 0
}

MODE="check"
case "${1:-}" in
  --self-test)
    self_test
    ;;
  --update-baseline)
    MODE="update"
    ;;
  "")
    MODE="check"
    ;;
  *)
    echo "check_design_review.sh: unknown argument: $1" >&2
    echo "usage: check_design_review.sh [--update-baseline|--self-test]" >&2
    exit 2
    ;;
esac

preflight

SEARCH_PATHS=(
  "$ROOT/ios/AgentCy"
  "$ROOT/ios/AgentCyWidgets"
  "$ROOT/ios/AgentCyShared"
  "$ROOT/ios/AgentCyInspirationShare"
)

if [[ "$MODE" == "update" ]]; then
  run_design_review "$BASELINE_FILE" 1 "${SEARCH_PATHS[@]}"
else
  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "check_design_review.sh: no baseline file at $BASELINE_FILE — run with --update-baseline first." >&2
    exit 1
  fi
  run_design_review "$BASELINE_FILE" 0 "${SEARCH_PATHS[@]}"
fi

exit "$RATCHET_EXIT_CODE"
