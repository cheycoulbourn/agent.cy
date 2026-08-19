# Agent.cy audit handoff to Claude

## Assignment

Continue the app audit page by page, beginning with `PAGE-MAIN-06` (Cy), which is the only page currently marked `In review`. Keep exactly one page in review at a time. Do not reopen completed pages or begin a cross-page journey until the current page has a complete function trace, runtime-state matrix, performance evidence, and audit classification.

The creator specifically wants a clear picture of what every page is supposed to do and where it links. Treat granular behavioral bugs, accessibility, heaviness, stutter, and poor scrolling/transition smoothness as first-class audit concerns.

## Authority and safety boundaries

- Preserve the extensive dirty working tree and all local app data. Do not reset, delete, clean, or rebuild completed work.
- Audit and diagnose first. Do not make source-code fixes, commits, pushes, deployments, Paper edits, or device installs unless the creator explicitly authorizes that next action.
- Distinguish product-contract drift, missing coverage, confirmed defects, and performance risks. Do not label static risk as a confirmed bug without reproduction.
- For a confirmed defect, use the repository gate: resolve contract, reproduce, add a focused failing regression, make the smallest patch, verify neighboring behavior, then perform runtime verification.
- Use the existing Paper file only as design evidence. Code, behavior-map, page-contract, runtime, and test evidence must be reconciled before changing Paper.

## Current audit state

- Canonical map: `docs/APP_BEHAVIOR_MAP.md`
- Atomic page ledger: `docs/APP_PAGE_CONTRACTS.md`
- Audit queue and performance register: `docs/APP_AUDIT_QUEUE.md`
- Existing page records: `docs/audits/`
- Active contract: `PAGE-MAIN-06`, Cy / `AskCyView`
- Frozen contract: contextual conversation; every mutation remains an explicit proposal; exits go to history, work, review, access, or canonical tabs.
- Contract states to inspect: empty, streaming, cancel, provider error, pending proposal, revised proposal, dismissed proposal, restored conversation, workspace switch, accessibility sizes, Reduce Motion, offline/unavailable provider, and relaunch.
- `PAGE-MAIN-01` through `PAGE-MAIN-05` are classified as `Coverage gap`, not unreviewed. Respect the exact remaining runtime evidence recorded in their audit files.

## Most recent scoped change

The Agenda monthly calendar change is complete and is not the active audit page:

- `ios/AgentCy/Views/Agenda/AgendaView.swift` places recurring pillar color only behind assigned weekday letters in the monthly calendar header.
- Month-date cells no longer show pillar colors. Selected dates and post counts remain neutral.
- `ios/AgentCyTests/PageMain02Tests.swift` contains `testMonthCalendarPlacesPillarColorsOnlyInWeekdayHeaders`.
- All nine `PageMain02Tests` passed, the simulator fixture passed visually, and `git diff --check` passed for the two files.
- Signed Debug build 210, bundle `com.agentcy.app`, was rebuilt from the current workspace, codesign-verified, upgrade-installed over the existing app on Chey's iPhone, and launched on 2026-08-18. The upgrade preserved the bundle identity and local data.

Do not redo or undo this change while auditing Cy.

## Performance and smoothness handoff

The creator reports that both the physical iPhone app and desktop app feel extremely slow and glitchy. This is not acceptable final behavior. Debug configuration can exaggerate slowness, but current code has concrete performance-risk signals that require measured Release profiling before broad refactoring.

Start from `PERF-RISK-02` and `PERF-RISK-07` through `PERF-RISK-13` in `docs/APP_AUDIT_QUEUE.md`. Confirm current source before relying on recorded counts. Important signals already observed:

1. The phone shell retains all six root `NavigationStack`s in a `ZStack`; hidden page roots may continue SwiftData observation and background work.
2. The shell polls on a four-second cadence, while `AskCyView` has its own four-second pending-review/availability loop. Determine whether hidden Cy and shell work overlap in real use.
3. `AskCyView` owns nine whole-table root `@Query` collections. The Catalyst shell also owns nine whole-table root queries and simultaneously presents more projections.
4. Large state-heavy SwiftUI owners perform filtering, sorting, grouping, and lookup work during body invalidation. Production-sized data may amplify this.
5. Simulator runs reproduced SwiftUI's `NavigationRequestObserver` "update multiple times per frame" warning on more than one root page, so it is a root-wide navigation signal rather than proof of one page-specific cause.
6. Synchronous/deprecated media thumbnail extraction and media decode paths remain separate risk areas.

Do not present Debug simulator memory, CPU, or launch timing as shipping evidence. Establish the dominant physical-device and Mac bottlenecks with Release measurements:

- Time Profiler and SwiftUI/body-update instrumentation during launch, tab switching, scrolling, Cy streaming, proposal review, search, and window resizing.
- SwiftData fetch/query invalidation counts, including hidden-tab activity.
- Allocations, peak/resident memory, image/video decode, and idle energy.
- Four-second poll activity and main-actor work on phone and Catalyst.
- Small, medium, and production-sized workspaces; cold/warm launch; foreground/background; offline/reconnect.

## First deliverable

Return a concise `PAGE-MAIN-06` audit memo containing:

1. Frozen expected behavior and every exit/link.
2. Function-by-function trace from UI events through persistence, API/MCP, streaming, proposal handling, cancellation, and restoration.
3. Reproduced defects versus contract drift versus remaining coverage gaps.
4. Focused regression tests and runtime fixtures required before any patch.
5. Cy-specific performance findings plus a prioritized, measured phone/Catalyst profiling plan for the broader slow-app report.

End with the exact next safe action. Do not silently advance to `PAGE-MAIN-07` until `PAGE-MAIN-06` has a recorded classification and evidence.

## First Claude static pass

Claude Code session `fa156aef-1e27-4858-ae0d-3edac67f7c51` completed a read-only static trace on 2026-08-18. Claude's result event was `success` and the effective model was `claude-fable-5`, but the local handoff helper's fail-closed guard reported a possible blocked/unavailable/routed-away signature. Treat the memo as advisory evidence, not a clean Fable-only verification, and do not retry the same run automatically.

Static conclusions to reproduce before any patch:

- The explicit-proposal boundary appears intact; no pre-acceptance mutation was found in the traced send/proposal path.
- `PAGE-MAIN-06` remains a coverage gap because it has no dedicated page audit record or page-level runtime replay.
- Highest-priority suspected defect: `AskCyView` retains its `@State` conversation thread across a workspace switch while the shell retains the Cy root. Reproduce whether a send after switching appends to the prior workspace's thread.
- Other static risks: hosted availability can appear healthy without a reachability check, and several conversation persistence calls use silent `try?` saves.
- Performance risks: hidden Cy can keep four-second polling alive alongside the shell; availability polling performs bridge/network/keychain work; nine whole-table queries and transcript markdown/task scans create a broad invalidation surface.

Correction to the first Claude memo: there is no `PageMain06Tests.swift`, but neighboring Cy coverage already exists in `ios/AgentCyTests/DomainTests.swift` for `ConversationTitleFormatter`, `CyChatActionPolicy`, `CyBriefReferencePolicy`, `CyPostCreationPolicy`, `CyPostSchedulingPolicy`, and `CyMarkdownParser`, plus `testAskCyReceivesIncompletePostsAndCurrentTaskContext` in `ios/AgentCyTests/ServiceTests.swift`. Extend these deliberately rather than duplicating them.

Exact next safe action: use a disposable two-workspace simulator fixture to reproduce the stale-thread suspicion and capture the empty, sending, cancel, provider-error, pending-review, accessibility, Reduce Motion, offline, and relaunch states. Do not patch until the behavior is reproduced and recorded.
