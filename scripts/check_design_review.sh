#!/usr/bin/env bash

set -euo pipefail

# check_design_review.sh — a ratchet, not a hard gate.
#
# Greps shipped Swift UI sources for ten design-consistency bans and compares
# each rule's current violation count against a checked-in baseline
# (scripts/design-review-baseline.txt). It fails (exit 1) only when a rule's
# count goes UP from its baseline; it passes when counts are equal or lower.
# Every violation is printed with file:line either way, pass or fail, so the
# output is useful even on a passing run.
#
# Three rules (pill_background, accent_control_fill, accent_shape_fill) ban a
# *solid* brand fill but not the brand-as-a-mark the contract allows (a bullet
# dot, an unread dot, a count badge, Cy's identity avatar, the walkthrough coach
# mark). Those are indistinguishable from a filled button by grep, so a mark
# opts out by carrying the marker
#
#   // design-review-allow: accent-mark -- <reason>
#
# on the SAME line as the fill. The marker is deliberately only available to the
# fill rules: accent_glow has no escape hatch, because design.md bans glow
# outright with no exception.
#
# Usage:
#   check_design_review.sh                 run the ratchet against the baseline
#   check_design_review.sh --update-baseline   rewrite the baseline from current counts
#   check_design_review.sh --self-test     run this script's own fixture tests

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_FILE="$ROOT/scripts/design-review-baseline.txt"

REQUIRED_TOOLS=(grep find)

# Parallel arrays (bash 3.2 on this Mac has no associative arrays) —
# RULE_IDS[i] / RULE_PATTERNS[i] / RULE_DESCRIPTIONS[i] / RULE_EXCLUDES[i]
# describe the same rule. RULE_EXCLUDES holds one filename the rule is allowed
# to live in (empty = the rule applies everywhere).
RULE_IDS=(
  sf_symbols
  animation_curves
  banned_fonts
  corner_radius
  pill_background
  glass_circle
  bordered_prominent
  accent_control_fill
  accent_shape_fill
  accent_glow
)
RULE_PATTERNS=(
  'Image\(systemName:|systemImage:'
  '\.animation\(\.(easeIn|easeOut|easeInOut|linear|spring|interactiveSpring|interpolatingSpring)\b|withAnimation\(\.(easeIn|easeOut|easeInOut|linear|spring|interactiveSpring|interpolatingSpring)\b'
  'Font\.custom\(|paperInter|paperMetadata|\.font\(\.system'
  'cornerRadius: (3|5|6|9|13|14|18|22)\b'
  'background\([^)]*Color\.(cyAccent|actionAccent)[^)]*in: *\.(capsule|circle)'
  'glassEffect\(.*in: *\.circle'
  '\.buttonStyle\(\.borderedProminent\)'
  'background\([^)]*Color\.cyAccent[^)]*in: *\.(capsule|circle)'
  '\.fill\([^)]*Color\.cyAccent([^A-Za-z0-9_.]|$)'
  'shadow\(color: *[^)]*\.cyAccent'
)
RULE_DESCRIPTIONS=(
  "SF Symbols in shipped UI (Image(systemName:) / systemImage:) — design.md bans SF Symbols outright"
  "Raw animation curve outside AgentMotion (.animation/.withAnimation with a literal curve)"
  "Non-Inter or off-token font reference (Font.custom / paperInter / paperMetadata / .font(.system)"
  "Off-scale cornerRadius literal (3/5/6/9/13/14/18/22 — not an AgentRadius token)"
  "Accent-filled capsule/circle background, in any argument position (solid-fill pill button banned per design.md)"
  "Hand-rolled circular glassEffect outside DesignTokens.swift — every glass circle goes through .agentGlassCircle() / AgentToolbarIconContainer"
  "Bordered-prominent button style anywhere in shipped UI — SwiftUI renders it as a solid accent fill (design.md: quiet ink tints only); AgentToolbarSaveButton / AgentToolbarIconButton are the shared replacement"
  "Solid brick-red behind a control (design.md: \"No solid accent fills, anywhere\", decided 2026-08-14) — the accent action is AgentQuietAccentButtonStyle / AgentQuietAccentIconLabel: cy@12% fill, 0.75pt cy@40% border, brick label. A brand *mark* opts out with // design-review-allow: accent-mark"
  "Solid brick-red shape fill (Circle()/Capsule().fill(Color.cyAccent), including the ternary form) — same ban, same escape hatch for a real mark"
  "Brick-red glow (design.md: \"No glow\", rejected 2026-08-14) — accent shadows are banned outright and have no escape hatch; use the shared ambient shadow or nothing"
)
# One allowed filename per rule; empty means the rule applies to every file.
RULE_EXCLUDES=(
  ''
  ''
  ''
  ''
  ''
  'DesignTokens.swift'
  ''
  ''
  ''
  ''
)

# 1 = the rule honours the `// design-review-allow: accent-mark` line marker.
# Only the solid-fill rules do; glow has no sanctioned exception.
RULE_ALLOW_MARKER=(
  0
  0
  0
  0
  1
  0
  0
  1
  1
  0
)

ALLOW_MARKER='design-review-allow'

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

# Scans the given search paths for one rule's pattern, skipping $2 if it names
# a file the rule is allowed to live in. Prints file:line matches to stdout.
# Never fails the script on "no matches" (grep's exit 1).
#
# $3 is the allow-marker flag: when it is 1, a matching line that also carries
# `// design-review-allow: ...` is dropped, so a brand mark can opt out of a
# solid-fill rule in the source itself rather than in a baseline number.
scan_rule() {
  local pattern="$1"
  local exclude_file="$2"
  local allow_marker="${3:-0}"
  shift 3
  local exclude_args=()
  if [[ -n "$exclude_file" ]]; then
    exclude_args=(--exclude="$exclude_file")
  fi
  local matches
  matches="$(grep -rnE --include='*.swift' --exclude-dir='build-device' --exclude-dir='*.xcodeproj' "${exclude_args[@]+"${exclude_args[@]}"}" "$pattern" "$@" 2>/dev/null || true)"
  if [[ "$allow_marker" -eq 1 && -n "$matches" ]]; then
    matches="$(printf '%s\n' "$matches" | grep -v "$ALLOW_MARKER" || true)"
  fi
  printf '%s' "$matches"
}

# glass_circle needs more than a single-line grep: `.glassEffect(` is
# routinely written with its arguments split across lines, e.g.
#   .glassEffect(
#       .clear.interactive(),
#       in: .circle
#   )
# RULE_PATTERNS[5] only catches the single-line form. This scans for a line
# that ends in "glassEffect(" and looks ahead a few lines for "in: .circle"
# before the call closes, so a wrapped circle glassEffect is caught too.
# Non-circle wrapped calls (capsule, rect) are left alone, and the exclude
# file (DesignTokens.swift) is skipped the same way scan_rule skips it.
scan_glass_circle() {
  local exclude_file="$1"
  shift
  local exclude_args=()
  if [[ -n "$exclude_file" ]]; then
    exclude_args=(--exclude="$exclude_file")
  fi

  local single
  single="$(scan_rule "${RULE_PATTERNS[5]}" "$exclude_file" 0 "$@")"

  local files
  files="$(grep -rlE --include='*.swift' --exclude-dir='build-device' --exclude-dir='*.xcodeproj' "${exclude_args[@]+"${exclude_args[@]}"}" 'glassEffect\($' "$@" 2>/dev/null || true)"

  local multi=""
  if [[ -n "$files" ]]; then
    local f hit
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      hit="$(awk '
        /glassEffect\($/ {
          start = NR
          startline = $0
          found = 0
          for (i = 1; i <= 6; i++) {
            if ((getline nextline) <= 0) break
            if (nextline ~ /in: *\.circle/) { found = 1; break }
            if (nextline ~ /^[[:space:]]*\)/) break
          }
          if (found) print start ":" startline
        }
      ' "$f" 2>/dev/null || true)"
      if [[ -n "$hit" ]]; then
        local line lineno content
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          lineno="${line%%:*}"
          content="${line#*:}"
          multi+="$f:$lineno:$content"$'\n'
        done <<< "$hit"
      fi
    done <<< "$files"
  fi
  multi="${multi%$'\n'}"

  if [[ -n "$single" && -n "$multi" ]]; then
    printf '%s\n%s' "$single" "$multi"
  elif [[ -n "$single" ]]; then
    printf '%s' "$single"
  else
    printf '%s' "$multi"
  fi
}

# accent_glow has the same multi-line problem glass_circle has: a banned
# accent shadow is routinely written as
#   .shadow(
#       color: Color.cyAccent.opacity(0.24),
#       radius: 12
#   )
# which RULE_PATTERNS[9] (single-line) cannot see. This scans for a line ending
# in ".shadow(" and looks ahead a few lines for a `color:` argument naming the
# accent before the call closes. A non-accent wrapped shadow (ink, pure black)
# is left alone, so the check is about the accent, not about shadows.
scan_accent_glow() {
  local single
  single="$(scan_rule "${RULE_PATTERNS[9]}" '' 0 "$@")"

  local files
  files="$(grep -rlE --include='*.swift' --exclude-dir='build-device' --exclude-dir='*.xcodeproj' '\.shadow\($' "$@" 2>/dev/null || true)"

  local multi=""
  if [[ -n "$files" ]]; then
    local f hit
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      hit="$(awk '
        /\.shadow\($/ {
          start = NR
          startline = $0
          found = 0
          for (i = 1; i <= 6; i++) {
            if ((getline nextline) <= 0) break
            if (nextline ~ /color:.*\.cyAccent/) { found = 1; break }
            if (nextline ~ /^[[:space:]]*\)/) break
          }
          if (found) print start ":" startline
        }
      ' "$f" 2>/dev/null || true)"
      if [[ -n "$hit" ]]; then
        local line lineno content
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          lineno="${line%%:*}"
          content="${line#*:}"
          multi+="$f:$lineno:$content"$'\n'
        done <<< "$hit"
      fi
    done <<< "$files"
  fi
  multi="${multi%$'\n'}"

  if [[ -n "$single" && -n "$multi" ]]; then
    printf '%s\n%s' "$single" "$multi"
  elif [[ -n "$single" ]]; then
    printf '%s' "$single"
  else
    printf '%s' "$multi"
  fi
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
    if [[ "$rule_id" == "glass_circle" ]]; then
      matches="$(scan_glass_circle "${RULE_EXCLUDES[$i]}" "${search_paths[@]}")"
    elif [[ "$rule_id" == "accent_glow" ]]; then
      matches="$(scan_accent_glow "${search_paths[@]}")"
    else
      matches="$(scan_rule "$pattern" "${RULE_EXCLUDES[$i]}" "${RULE_ALLOW_MARKER[$i]}" "${search_paths[@]}")"
    fi
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

  # glass_circle
  cat > "$tmp/GlassFail.swift" <<'EOF'
import SwiftUI
struct GlassFail: View {
    var body: some View { Color.clear.glassEffect(.clear.interactive(), in: .circle) }
}
EOF
  cat > "$tmp/GlassPass.swift" <<'EOF'
import SwiftUI
struct GlassPass: View {
    var body: some View { Color.clear.agentGlassCircle() }
}
EOF
  # The one file the glass_circle rule is allowed to live in. Same violating
  # line as GlassFail.swift; it must be skipped purely because of its name.
  mkdir -p "$tmp/allowed"
  cat > "$tmp/allowed/DesignTokens.swift" <<'EOF'
import SwiftUI
struct AllowedGlass: View {
    var body: some View { Color.clear.glassEffect(.clear.interactive(), in: .circle) }
}
EOF

  # glass_circle multi-line fixtures: the same call written across several
  # lines, the form the single-line pattern alone would miss (this repo
  # already writes glassEffect multi-line at AppShellView.swift:778,
  # ScheduledPostDetailView.swift:940, ResumablePostEditorView.swift:824 —
  # all capsule/rect, none circle). Fail fixture wraps a circle; pass fixture
  # wraps a capsule the same way, so the check proves shape still matters
  # once the call spans lines, not just presence of "glassEffect(".
  cat > "$tmp/GlassMultilineFail.swift" <<'EOF'
import SwiftUI
struct GlassMultilineFail: View {
    var body: some View {
        Color.clear
            .glassEffect(
                .clear.interactive(),
                in: .circle
            )
    }
}
EOF
  cat > "$tmp/GlassMultilinePass.swift" <<'EOF'
import SwiftUI
struct GlassMultilinePass: View {
    var body: some View {
        Color.clear
            .glassEffect(
                .clear.interactive(),
                in: .capsule
            )
            .glassEffect(
                .clear,
                in: .rect(cornerRadius: 14)
            )
    }
}
EOF

  # bordered_prominent
  cat > "$tmp/BorderedProminentFail.swift" <<'EOF'
import SwiftUI
struct BorderedProminentFail: View {
    var body: some View {
        Button("Save") {}
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(Color.agentPureWhite)
    }
}
EOF
  cat > "$tmp/BorderedProminentPass.swift" <<'EOF'
import SwiftUI
struct BorderedProminentPass: View {
    var body: some View { AgentToolbarSaveButton(title: "Save", action: {}) }
}
EOF

  # accent_control_fill — the two call shapes the old pill_background pattern
  # missed: a ternary before Color.cyAccent, and a solid accent circle. The
  # pass fixture is the quiet accent action the migration replaced them with.
  cat > "$tmp/AccentControlFillFail.swift" <<'EOF'
import SwiftUI
struct AccentControlFillFail: View {
    var body: some View {
        VStack {
            Text("Send").background(canSend ? Color.cyAccent : Color.agentSurface, in: .circle)
            Text("Go").background(Color.cyAccent, in: .capsule)
        }
    }
}
EOF
  cat > "$tmp/AccentControlFillPass.swift" <<'EOF'
import SwiftUI
struct AccentControlFillPass: View {
    var body: some View {
        VStack {
            Button("Go") {}.buttonStyle(AgentQuietAccentButtonStyle())
            Text("Badge")
                .background(Color.cyAccent, in: .capsule) // design-review-allow: accent-mark -- unread count
            Text("Tint").background(Color.cyAccent.opacity(0.12), in: .capsule)
        }
    }
}
EOF

  # accent_shape_fill — a solid brick shape used as a control ground. The pass
  # fixture keeps the two shapes the contract does allow: an opacity tint, and
  # a real mark carrying the allow marker.
  cat > "$tmp/AccentShapeFillFail.swift" <<'EOF'
import SwiftUI
struct AccentShapeFillFail: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.cyAccent)
            Circle().fill(isOn ? Color.cyAccent : Color.clear)
        }
    }
}
EOF
  cat > "$tmp/AccentShapeFillPass.swift" <<'EOF'
import SwiftUI
struct AccentShapeFillPass: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.cyAccent.opacity(0.12))
            Circle().fill(Color.cyAccent).frame(width: 5) // design-review-allow: accent-mark -- bullet
        }
    }
}
EOF

  # accent_glow — single-line and wrapped forms both banned, with no marker
  # escape hatch. The pass fixture proves a non-accent shadow still passes and
  # that the marker does NOT buy an exemption here.
  cat > "$tmp/AccentGlowFail.swift" <<'EOF'
import SwiftUI
struct AccentGlowFail: View {
    var body: some View {
        Text("hi")
            .shadow(color: Color.cyAccent.opacity(0.26), radius: 14, y: 6)
    }
}
EOF
  cat > "$tmp/AccentGlowPass.swift" <<'EOF'
import SwiftUI
struct AccentGlowPass: View {
    var body: some View {
        Text("hi")
            .shadow(color: Color.agentPureBlack.opacity(0.14), radius: 14, y: 6)
    }
}
EOF
  cat > "$tmp/AccentGlowMultilineFail.swift" <<'EOF'
import SwiftUI
struct AccentGlowMultilineFail: View {
    var body: some View {
        Text("hi")
            .shadow(
                color: Color.cyAccent.opacity(0.24),
                radius: 12
            )
    }
}
EOF
  cat > "$tmp/AccentGlowMultilinePass.swift" <<'EOF'
import SwiftUI
struct AccentGlowMultilinePass: View {
    var body: some View {
        Text("hi")
            .shadow(
                color: Color.agentPureBlack.opacity(0.12),
                radius: 12
            )
            .shadow(color: Color.cyAccent, radius: 0) // design-review-allow: accent-mark -- no escape hatch here
    }
}
EOF

  local rule_fail_file=(SfFail AnimFail FontFail RadiusFail PillFail GlassFail BorderedProminentFail AccentControlFillFail AccentShapeFillFail AccentGlowFail)
  local rule_pass_file=(SfPass AnimPass FontPass RadiusPass PillPass GlassPass BorderedProminentPass AccentControlFillPass AccentShapeFillPass AccentGlowPass)

  local i
  for i in "${!RULE_IDS[@]}"; do
    local rule_id="${RULE_IDS[$i]}"
    local pattern="${RULE_PATTERNS[$i]}"
    local fail_file="$tmp/${rule_fail_file[$i]}.swift"
    local pass_file="$tmp/${rule_pass_file[$i]}.swift"

    if [[ "$rule_id" == "accent_glow" ]]; then
      if [[ -n "$(scan_accent_glow "$fail_file")" ]]; then
        echo "self-test ok: $rule_id correctly flags its fail fixture"
      else
        echo "self-test FAIL: $rule_id did not flag ${rule_fail_file[$i]}.swift" >&2
        failures=$((failures + 1))
      fi

      if [[ -z "$(scan_accent_glow "$pass_file")" ]]; then
        echo "self-test ok: $rule_id correctly clears its pass fixture"
      else
        echo "self-test FAIL: $rule_id incorrectly flagged ${rule_pass_file[$i]}.swift" >&2
        failures=$((failures + 1))
      fi
      continue
    fi

    if [[ "$rule_id" == "glass_circle" ]]; then
      if [[ -n "$(scan_glass_circle "${RULE_EXCLUDES[$i]}" "$fail_file")" ]]; then
        echo "self-test ok: $rule_id correctly flags its fail fixture"
      else
        echo "self-test FAIL: $rule_id did not flag ${rule_fail_file[$i]}.swift" >&2
        failures=$((failures + 1))
      fi

      if [[ -z "$(scan_glass_circle "${RULE_EXCLUDES[$i]}" "$pass_file")" ]]; then
        echo "self-test ok: $rule_id correctly clears its pass fixture"
      else
        echo "self-test FAIL: $rule_id incorrectly flagged ${rule_pass_file[$i]}.swift" >&2
        failures=$((failures + 1))
      fi
      continue
    fi

    if [[ -n "$(scan_rule "$pattern" "${RULE_EXCLUDES[$i]}" "${RULE_ALLOW_MARKER[$i]}" "$fail_file")" ]]; then
      echo "self-test ok: $rule_id correctly flags its fail fixture"
    else
      echo "self-test FAIL: $rule_id did not flag ${rule_fail_file[$i]}.swift" >&2
      failures=$((failures + 1))
    fi

    if [[ -z "$(scan_rule "$pattern" "${RULE_EXCLUDES[$i]}" "${RULE_ALLOW_MARKER[$i]}" "$pass_file")" ]]; then
      echo "self-test ok: $rule_id correctly clears its pass fixture"
    else
      echo "self-test FAIL: $rule_id incorrectly flagged ${rule_pass_file[$i]}.swift" >&2
      failures=$((failures + 1))
    fi
  done

  # The exclusion itself: the same violating line inside the rule's allowed
  # filename must not be reported.
  if [[ -z "$(scan_glass_circle "${RULE_EXCLUDES[5]}" "$tmp/allowed")" ]]; then
    echo "self-test ok: glass_circle skips its allowed file (DesignTokens.swift)"
  else
    echo "self-test FAIL: glass_circle flagged its allowed file DesignTokens.swift" >&2
    failures=$((failures + 1))
  fi

  # Multi-line glassEffect: a wrapped circle call must still be flagged, and
  # a wrapped capsule/rect call must not be — proves the look-ahead checks
  # shape, not just the presence of a multi-line "glassEffect(".
  if [[ -n "$(scan_glass_circle '' "$tmp/GlassMultilineFail.swift")" ]]; then
    echo "self-test ok: glass_circle flags a multi-line wrapped circle glassEffect"
  else
    echo "self-test FAIL: glass_circle did not flag GlassMultilineFail.swift (multi-line circle)" >&2
    failures=$((failures + 1))
  fi

  if [[ -z "$(scan_glass_circle '' "$tmp/GlassMultilinePass.swift")" ]]; then
    echo "self-test ok: glass_circle clears a multi-line wrapped capsule/rect glassEffect"
  else
    echo "self-test FAIL: glass_circle incorrectly flagged GlassMultilinePass.swift (multi-line capsule/rect)" >&2
    failures=$((failures + 1))
  fi

  # Multi-line accent glow: a wrapped .shadow() naming the accent must still be
  # flagged, a wrapped ink shadow must not be, and the allow marker must NOT
  # exempt a glow (the fill rules honour it; accent_glow deliberately does not).
  if [[ -n "$(scan_accent_glow "$tmp/AccentGlowMultilineFail.swift")" ]]; then
    echo "self-test ok: accent_glow flags a multi-line wrapped accent shadow"
  else
    echo "self-test FAIL: accent_glow did not flag AccentGlowMultilineFail.swift" >&2
    failures=$((failures + 1))
  fi

  if [[ -n "$(scan_accent_glow "$tmp/AccentGlowMultilinePass.swift")" ]]; then
    echo "self-test ok: accent_glow ignores the allow marker (glow has no escape hatch)"
  else
    echo "self-test FAIL: accent_glow honoured the allow marker; glow must have no escape hatch" >&2
    failures=$((failures + 1))
  fi

  # The marker itself, on the rules that do honour it: the same violating line
  # is reported without the marker and dropped with it.
  cat > "$tmp/MarkerUnmarked.swift" <<'EOF'
import SwiftUI
struct MarkerUnmarked: View {
    var body: some View { Circle().fill(Color.cyAccent) }
}
EOF
  cat > "$tmp/MarkerMarked.swift" <<'EOF'
import SwiftUI
struct MarkerMarked: View {
    var body: some View { Circle().fill(Color.cyAccent) } // design-review-allow: accent-mark -- dot
}
EOF
  if [[ -n "$(scan_rule "${RULE_PATTERNS[8]}" '' 1 "$tmp/MarkerUnmarked.swift")" ]]; then
    echo "self-test ok: allow marker absent -- accent_shape_fill still reports the line"
  else
    echo "self-test FAIL: accent_shape_fill missed MarkerUnmarked.swift" >&2
    failures=$((failures + 1))
  fi

  if [[ -z "$(scan_rule "${RULE_PATTERNS[8]}" '' 1 "$tmp/MarkerMarked.swift")" ]]; then
    echo "self-test ok: allow marker present -- accent_shape_fill drops the line"
  else
    echo "self-test FAIL: accent_shape_fill ignored the allow marker" >&2
    failures=$((failures + 1))
  fi

  if [[ -n "$(scan_rule "${RULE_PATTERNS[8]}" '' 0 "$tmp/MarkerMarked.swift")" ]]; then
    echo "self-test ok: allow marker only applies to rules that opt in"
  else
    echo "self-test FAIL: the allow marker was honoured by a rule that did not opt in" >&2
    failures=$((failures + 1))
  fi

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
  printf 'sf_symbols=2\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\nglass_circle=0\nbordered_prominent=0\naccent_control_fill=0\naccent_shape_fill=0\naccent_glow=0\n' > "$equal_baseline"
  if run_design_review "$equal_baseline" 0 "$ratchet_dir" >/dev/null 2>&1; [[ "$RATCHET_EXIT_CODE" -eq 0 ]]; then
    echo "self-test ok: count == baseline passes"
  else
    echo "self-test FAIL: count == baseline should pass, exit code was $RATCHET_EXIT_CODE" >&2
    failures=$((failures + 1))
  fi

  # Baseline below current count (1 < 2) must fail.
  local low_baseline="$tmp/baseline-low.txt"
  printf 'sf_symbols=1\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\nglass_circle=0\nbordered_prominent=0\naccent_control_fill=0\naccent_shape_fill=0\naccent_glow=0\n' > "$low_baseline"
  if run_design_review "$low_baseline" 0 "$ratchet_dir" >/dev/null 2>&1; [[ "$RATCHET_EXIT_CODE" -eq 1 ]]; then
    echo "self-test ok: count > baseline fails"
  else
    echo "self-test FAIL: count > baseline should fail, exit code was $RATCHET_EXIT_CODE" >&2
    failures=$((failures + 1))
  fi

  # Baseline above current count (3 > 2) must pass (ratchet only tightens).
  local high_baseline="$tmp/baseline-high.txt"
  printf 'sf_symbols=3\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\nglass_circle=0\nbordered_prominent=0\naccent_control_fill=0\naccent_shape_fill=0\naccent_glow=0\n' > "$high_baseline"
  if run_design_review "$high_baseline" 0 "$ratchet_dir" >/dev/null 2>&1; [[ "$RATCHET_EXIT_CODE" -eq 0 ]]; then
    echo "self-test ok: count < baseline passes"
  else
    echo "self-test FAIL: count < baseline should pass, exit code was $RATCHET_EXIT_CODE" >&2
    failures=$((failures + 1))
  fi

  # --update-baseline rewrites the file from current counts.
  local update_target="$tmp/baseline-update.txt"
  printf 'sf_symbols=0\nanimation_curves=0\nbanned_fonts=0\ncorner_radius=0\npill_background=0\nglass_circle=0\nbordered_prominent=0\naccent_control_fill=0\naccent_shape_fill=0\naccent_glow=0\n' > "$update_target"
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
