# L4 · Code health lane

Read `docs/refinement/briefs/_common.md` first. Outputs: `docs/refinement/findings-deadcode.md`, `docs/refinement/findings-codehealth.md`.

Chey's words: "Is there any dead code? Is anything making it feel heavy?" (the heaviness measurement belongs to L2; you find structural weight).

## Dead code method

1. Across the four Xcode targets (`ios/AgentCy`, `ios/AgentCyShared`, `ios/AgentCyWidgets`, `ios/AgentCyInspirationShare`) and tests, list every top-level and nested type, function, computed property, and stored property declaration, then search for references outside the declaring line. Report every symbol with zero references, grouped by file, with file:line. Exclude SwiftUI `body`, `PreviewProvider`/`#Preview`, entry points, protocol requirements, `@main`, Codable keys, and SwiftData model properties (those are schema; flag them separately as "unused model fields").
2. Assets: every imageset and colorset in `Assets.xcassets` versus references in code (including `AgentIcon` cases). List unreferenced assets.
3. Files with no referenced symbols at all. Files in the project that are not in any target.
4. `#if DEBUG` and preview-fixture code: confirm none of it changes release behavior; list any fixture hook that lives outside a DEBUG guard.
5. Duplicated implementations: two or more types doing the same job (close buttons, headers, section rules, empty states, chips, date formatting helpers, relative-date strings). Name each cluster and the canonical one.
6. Compiler warnings: read the iOS test build log at `docs/refinement/evidence/baseline/ios-build.log` if present, otherwise build under scratchpad derived data; list warnings by kind with counts and sites. Deprecated APIs included.
7. Files over 2,000 lines: list with line counts and a one-paragraph split proposal each (by responsibility, not by line number).
8. Scripts and CI: `scripts/verify.sh` calls `pnpm`, which is not installed on this Mac, and `scripts/check_inter_typography.sh` printed "passed" while `rg` was missing. Verify both claims, check `.github/workflows/ci.yml` for the same fragility, and write findings.

If a network install of a dead-code tool (Periphery) would materially improve accuracy, say so in a "gate G-tools" note with the expected gain; do not install it.

## Deliverables

- `findings-deadcode.md` (batch B4): symbol list, asset list, file list, each with a removal fix; mark anything you are not certain is dead as "verify by build after removal".
- `findings-codehealth.md`: duplicates, warnings, oversized files, scripts, with fixes and the batch each belongs to (duplicates that are design components go to B1; the rest B4).
