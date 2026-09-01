# L4 script-gate reproduction — 2026-09-01

## `scripts/check_inter_typography.sh` passes with zero coverage

```
$ export PATH=/opt/homebrew/bin:$PATH
$ command -v rg; echo "exit=$?"
# (no output)  exit=1        <- ripgrep is not installed on this Mac
$ bash scripts/check_inter_typography.sh; echo "EXIT=$?"
scripts/check_inter_typography.sh: line 14: rg: command not found
Inter typography check passed.
EXIT=0
```

Cause: line 14 puts `rg` in an `if` condition, which suppresses `set -e`. `rg` exits 127 (not found),
the condition is false, the failure branch is skipped, and the script prints "passed".

## What the check would have caught (same pattern run through grep)

```
ios/AgentCy/App/RootView.swift:439:                            .font(.agentBody.monospaced())
ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:269:                    .font(.caption.weight(.semibold))
ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:274:                    .font(.caption.monospacedDigit())
ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:357:                    .font(.caption)
ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:473:                                            .font(.caption)
ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:478:                                        .font(.caption)
ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:645:                    .font(.caption2.weight(.semibold))
ios/AgentCy/Views/Shell/DesktopAppShellView.swift:340:                .font(.system(size: 15, weight: .medium))
```

## `scripts/verify.sh` cannot run on this Mac

```
$ command -v pnpm corepack
pnpm not found
corepack not found
$ grep packageManager package.json
  "packageManager": "pnpm@11.7.0",
```

verify.sh line 13 is `pnpm install --frozen-lockfile` under `set -euo pipefail`, so the run aborts there.
Lines 18-49 (xcodegen, xcodebuild build, xcodebuild test) are unreachable locally.

## CI does not compensate

`.github/workflows/ci.yml` never invokes `scripts/verify.sh` or `scripts/check_inter_typography.sh`.
The `workspace` job runs pnpm install/typecheck/test (no `pnpm build`); the `apps` job runs xcodebuild
test and the Catalyst build. Neither job fails on compiler warnings, and neither runs the typography gate.
