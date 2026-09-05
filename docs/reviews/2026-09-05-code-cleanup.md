# Code cleanup and responsiveness review

Reviewed September 5, 2026 against `d522519` plus the 12 files already modified when this task began. Existing edits were preserved. This review covers local source changes; no deployment was performed.

## Changes

1. **Load phone tabs on first use.** `Views/Shell/RetainedTab.swift` defers each tab's view construction until selection, preserving its state after that. The phone previously mounted all six tab roots at launch. Hidden Cy tabs now suspend their periodic bridge/availability polling; the shell continues to receive pending approvals. A hosted SwiftUI regression test verifies deferred mounting, preserved state, and the inactive signal.
2. **Remove idle and repeated work.** Home and Cy use the existing static asterisk instead of an always-running animation timeline. Actual thinking indicators remain. Home no longer repeats the shell's reminder reconciliation. Export uses one ISO-8601 formatter per archive, replacing 41 allocations inside collection transforms without changing the date format.
3. **Remove confirmed unused code.** Deleted the unreachable Today screen, its unused PlanHeader, nine unused AppModel methods, the unused recurrence materializer, unused Local Cy helpers, unused Quick Capture/Pillars/desktop helpers, unused design declarations, and two unreferenced image sets. The live Today output classification policy moved to `Services/TodayOutputPresentation.swift` and remains covered by domain tests.
4. **Complete the approved Creator Session retirement.** Removed its screen, floating timer, unregistered Live Activity, shared implementation, routes, and gated entry points on phone and desktop. Removed the unused background-audio and Live Activity declarations. This follows DEC-05 and DEC-17 in `docs/refinement/02-decisions.md`. Old launch requests are consumed safely; old deep links are ignored. No saved creator content or SwiftData schema fields were deleted.
5. **Separate source ownership.** Moved Activity Center and its filters out of Home into `Views/Activity/NotificationActivityCenterView.swift`. Preview seed data and its preview caller are Debug-only. Regenerated the Xcode project from `ios/project.yml`; README now maps the source folders and documents an external Derived Data location.

The first cleanup pass removed **3,692 net Swift lines** relative to the starting workspace, including retirement of obsolete tests and addition of two regression tests. The Activity Center move is included in both sides of that comparison. The follow-up below adds a shared query boundary and three regression tests.

## Approved follow-up: workspace loading and Customize

The six main screens now apply **28 workspace predicates in SwiftData**, before loading records into view collections. Previously these queries fetched whole tables and then filtered them in memory. `Services/WorkspaceQueryScope.swift` centralizes database ownership rules; `Views/Shared/WorkspaceQueryScopeReader.swift` updates each screen's query configuration when account selection, workspace order, or archive state changes. It preserves the screen's identity and local state. Sort order and complete active-workspace result sets remain unchanged; no fetch limit truncates counts, calendar entries, or search results.

| Screen | Queries scoped at the database |
| --- | --- |
| Home | Briefs, outputs, tasks, pillars, daily-focus templates and overrides, brand partners |
| Tasks | Tasks and pillars |
| Pillars | Pillars, briefs, outputs |
| Ideas | Briefs, saved references, pillars |
| Agenda | Briefs, outputs, pillars, series, episode slots, tasks, daily-focus templates and overrides |
| Cy | Threads, briefs, outputs, tasks, pillars |

Legacy unowned records still belong to the default workspace. Saved references retain their stricter explicit-ownership rule. Existing view-level ownership guards remain. Shared activity counts, conversation messages, and related-record lookups keep their existing scope so legacy links and history are not lost. The post editor was inspected and already predicates its main queries by brief ID; its existing query behavior was retained.

`WorkspaceQueryScopeTests` exercises all 11 model predicates against a file-backed SQLite store, including invalid selection, empty workspace lists, archive fallback, reordered defaults, and legacy records. A hosted SwiftUI test verifies account switching and default-workspace changes without resetting view state. A separate 2,000-brief SQLite fixture returns exactly the 40 active-workspace records instead of all 2,000. That is a returned-row reduction for this fixture, not a measured production latency or memory claim.

Home's Customize action now uses `AgentRadius.control` for its background, hit shape, and border. This resolves the capsule-button design gate failure while retaining its label, colors, dimensions, and action.

## Verification

- iOS Debug: **758 tests passed**, including exports, navigation, workspace boundaries, dashboard customization, tab retention, retired-route handling, SQLite predicate equivalence, and query reconfiguration.
- iOS Simulator Release and Mac Catalyst Release: **builds passed**. The Release builds also validate exclusion of the Debug-only seed data and preview caller.
- TypeScript: **140 tests passed** across contracts, MCP, and server; typecheck and build passed in the first pass using the repository's bundled Node 24 runtime. The query follow-up changes no TypeScript files.
- Inter typography, the design ratchet, and `git diff --check` passed. The ratchet permits existing baseline violations; this is not a claim of zero design debt. The starting workspace's Customize capsule failure was reproduced before the approved follow-up fixed it.

During the first pass, each of the six tab launch fixtures stayed running; Home and Cy screenshots were inspected. An attempted deep-link navigation smoke check encountered the simulator's system confirmation prompt, so it is not counted as verified navigation. Tab switching/state preservation is covered by the hosted SwiftUI test.

## Launch sample

First-pass sample, before the query follow-up: same iPhone 17 Pro simulator, iOS 26.5, Debug configuration, and `-agentCyPreviewData` fixture. Recorded the existing `RootLaunchDiagnostics.destination_app` checkpoint, measured from process initialization. Excluded the first launch in each group; the simulator was freshly booted before each group. No compiler process ran during these samples.

| Checkpoint | Before | After |
| --- | ---: | ---: |
| Warm run 1 | 651.1 ms | 474.0 ms |
| Warm run 2 | 498.0 ms | 469.1 ms |
| Warm run 3 | 499.9 ms | 467.2 ms |
| Median | 499.9 ms | 469.1 ms |

The median improved about **6%** on this small fixture. These are three-run observations of a SwiftUI appearance checkpoint, not frame-presentation instrumentation or a controlled device benchmark. No battery or memory improvement is claimed from the timing result.

## Remaining limits

- Visited phone tabs remain mounted to preserve navigation and unsaved view state. This improves first launch and stops hidden Cy polling, but it does not bound memory after visiting every tab.
- The main screens now scope 28 queries, but detail screens and some shared or related-record lookups still use broader fetches. Large single-workspace libraries still load all matching records; paging, indexing, and per-device profiling were not part of this change.
- Compiler warnings already present in image extraction and older tests remain. This pass does not certify the entire pre-beta refinement backlog or remove symbols that may be required by persistence, protocols, or legacy icon mapping.
- No app was installed on a physical device and no production service was changed. Simulator timing does not establish device frame rate, memory pressure, battery use, or performance with a large creator library.
