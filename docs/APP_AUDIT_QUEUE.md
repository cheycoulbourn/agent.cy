# Agent.cy App Audit Queue

This is the execution queue for the [App Behavior Map](APP_BEHAVIOR_MAP.md), atomic [Page Contract Ledger](APP_PAGE_CONTRACTS.md), and [Paper view](https://app.paper.design/file/01KZXJTBBVJ33MD84G0HKB2HRX/1F-0). It is deliberately not a bug list. Items move to confirmed defects only after product intent is resolved and runtime behavior is reproduced.

## Page-by-page execution rule

Only one `PAGE-*` contract may be `In review` at a time. Finish its function trace, required runtime states, performance evidence, and audit record before opening another page. Cross-page journeys are reviewed only after their participating pages are individually closed.

## Initial performance risk register

These are static risk signals to measure under the owning page IDs. None is a confirmed performance defect yet.

| ID | Pages | Signal | Measurement needed |
| --- | --- | --- | --- |
| `PERF-RISK-01` | `PAGE-ROOT-01` | Root startup delays credential resolution until after legacy cleanup and full-store recurrence/task repair work; bootstrap and structured-field migrations also run synchronously before `RootView` appears. Later startup work overlaps work repeated on scene activation. | Signpost cold/warm production launch with realistic stores; time store open/bootstrap, pre-credential work, first non-launch destination, and duplicated activation work separately. |
| `PERF-RISK-02` | `PAGE-ROOT-05`, `PAGE-ROOT-07`, `PAGE-MAIN-01`, `PAGE-MAIN-06`, `PAGE-CAP-02`, `PAGE-PLAN-01`, `PAGE-WORK-02` | Several state-heavy SwiftUI owners are 1,600 to 4,800 lines and combine many queries, derived collections, sheets, and navigation paths. | Count body updates and query invalidations during typing, tab changes, scrolling, and sheet presentation; profile hitches before refactoring. |
| `PERF-RISK-03` | Home, Plan, Tasks, Pillars, Idea Bank, Feed, Brand Cabinet | Current views frequently derive filtered/sorted/grouped collections in computed state. | Measure repeated work per body update with realistic large workspaces; verify stable identity and lazy containers. |
| `PERF-RISK-04` | `PAGE-CAP-07`, `PAGE-CAP-08` | App and share-extension video thumbnail paths use deprecated synchronous `AVAssetImageGenerator.copyCGImage`. | Time thumbnail extraction off the main actor; measure extension memory/time limits and cancellation. |
| `PERF-RISK-05` | `PAGE-CAP-04`, `PAGE-WORK-07`, `PAGE-WORK-08`, Feed and widgets | Audio, image, video, preview, and externally stored attachment data can trigger decoding, I/O, and memory pressure near scrolling or presentation. | Profile decode size, peak memory, cache lifetime, paging, player cleanup, and missing-file recovery. |
| `PERF-RISK-06` | `PAGE-ROOT-05` | **Resolved 2026-08-18:** bridge status-file decoding moved to a detached utility task; local runtime status remains actor-isolated; the step-scoped polling loop is structured and cancellation-aware. | Cause closed by focused regression and runtime replay. Continue production-sized body-update and memory profiling under `PERF-RISK-02`. |
| `PERF-RISK-07` | `PAGE-ROOT-06` | The phone shell retains all six root `NavigationStack`s. Their root files contain 74 static query/task/receiver/timeline signal lines, so hidden tabs may keep observing data or doing work. A DEBUG simulator preview used about 341 MB resident memory, which is not shipping evidence. PAGE-MAIN-03 also reproduced SwiftUI's `NavigationRequestObserver` invalid-configuration warning on both Tasks and Home preview launches, so the signal is root-wide rather than task-row specific. | On a Release device with production-sized workspaces, measure per-tab body updates, SwiftData fetches, memory, tab latency, scrolling, energy, path restoration, and launch/navigation warnings. Compare retained roots with a lazy or state-preserving alternative before refactoring. |
| `PERF-RISK-08` | `PAGE-ROOT-07` | The 1,698-line Catalyst shell owns nine whole-table root queries and repeatedly scans outputs while linearly resolving briefs across seven-day and eight-week utility projections. Narrow windows still retain the root query owner even when the Control Center is absent. | Use a Release Apple-silicon Mac with production-sized data to measure query fetches, body updates, resize latency, scrolling, memory, and four-second poll energy. Only then evaluate a conditional utility child owner and one duplicate-safe brief index per derivation pass. |
| `PERF-RISK-09` | `PAGE-MAIN-01` | **Measured on-device 2026-08-18 (Release build 212, iPhone 17 Pro Max, iOS 27.0, the creator's real workspace, creator-driven 120s Time Profiler session):** the main thread froze for a 442.8 ms microhang immediately followed by a **1.00 s full hang**, and effectively all of the app's CPU samples in the trace land in `HomeDashboardView`'s derived-collection getters — `scoped<A>(_:)` 587 samples, `todayTasksSection` closures 482, `todayMyTasks` 248, `todayPostTasks` 243, `dashboardCard` 218, `reorderableDashboardCard` 120 — inside `_UIHostingView.layoutSubviews` body invalidation (trace: session scratchpad `home-interaction.trace`, hang window 01:50.3–01:52.4, coinciding with a scene event). One Home body pass re-derives every card from 12 whole-table queries and costs ~1.4 s of main-thread work on shipping-configuration hardware. This is now a confirmed, measured cause of the reported heaviness — no longer only a static risk. **Repaired and re-measured the same day (creator authorization "Fix and approve"):** `HomeWorkspaceScopePolicy` resolves the active workspace once per scope pass (the old path re-resolved and re-sorted the workspace list per record); `brief(for:)` linear scans inside eight derivation loops became one `DuplicateSafeIndex` lookup captured per pass; the today-tasks section derives its list once instead of four times. Two focused regressions (scope-parity, no-workspace case) watched red first; **624 tests, 0 failures**. Re-measured creator-driven 120s Release session (build 213): total main-thread hang time fell **1,447 ms → 676 ms**, and app derivation samples inside the remaining hang fell **~1,800 → ~60** — the residual hang is dominated by system scene-event handling at backgrounding (`UIApplicationSceneClientAgent`, 345 samples), not Home derivation; `scoped` no longer appears in the profile at all. | Remaining: the backgrounding scene-event hang (system-side snapshot work — investigate `sceneDidEnterBackground` app work before blaming UIKit), cold-launch trace (App Launch template times out against iOS 27.0), idle energy, medium/large synthetic workspaces, and Catalyst. |
| `PERF-RISK-10` | `PAGE-MAIN-02`, `PAGE-PLAN-01` | The 3,756-line Agenda owner holds 12 whole-table root queries and derives week, month, and list projections with remaining linear lookups. PAGE-MAIN-02 removed one task query/grouping pass and repeated full list-snapshot construction, but no Release-device measurement exists. | Profile a Release device with production-sized small, medium, and large workspaces. Measure Plan/Agenda body invalidations, SwiftData fetches, snapshot/projection time, scrolling/frame hitches, retained-tab background work, and memory in Week, Calendar, and List before splitting owners or adding indexes. |
| `PERF-RISK-11` | `PAGE-MAIN-03`, `PAGE-TASK-01` | The 2,367-line Tasks owner holds six whole-table root queries and retains linear output/brief/pillar/title and subtask scans. PAGE-MAIN-03 removed a duplicate full filter/group pass, per-task archive-index construction, and per-row lazy navigation destinations, but no Release-device measurement exists. | Profile a Release device with production-sized small, medium, and large workspaces. Measure body invalidations, SwiftData fetches, filter/group time, row work, collection switching, task-toggle redraw, scrolling/frame hitches, retained-tab background work, and memory before splitting owners or adding indexes. |
| `PERF-RISK-12` | `PAGE-MAIN-04`, `PAGE-WORK-11` | The 2,370-line Pillars owner combines a five-query root with a separate five-query detail owner and remaining derived collection work. PAGE-MAIN-04 replaced repeated per-pillar usage scans with one root projection and structured sheet/guide state, but no Release-device measurement exists. | Profile a Release device with production-sized small, medium, and large workspaces. Measure root/deeper body invalidations, SwiftData fetches, projection time, scrolling/frame hitches, retained-tab background work, sheet latency, detail-tab switching, and memory before splitting query owners or adding indexes. |
| `PERF-RISK-13` | `PAGE-MAIN-05`, `PAGE-MAIN-08` | The 991-line Idea Bank root owns five whole-table queries and searches full notes synchronously per keystroke. PAGE-MAIN-05 replaced repeated root projections and per-row pillar scans with one duplicate-safe projection and ID index, but thumbnail hydration, full-library behavior, and Release-device cost remain unmeasured. | Profile small, medium, and production-sized libraries on a Release device. Measure typing latency, projection time, query/body invalidations, scrolling/frame hitches, thumbnail network/decode work, memory, retained-tab background activity, and full Saved Posts library hydration before splitting query owners or adding indexes. |

## Defect gate

`Queued → Contract resolved → Reproduced → Regression added → Patch verified → Runtime verified`

| State | Required evidence |
| --- | --- |
| Queued | The surface, user outcome, and reason for review are named. |
| Contract resolved | Product and design sources agree on the expected behavior. |
| Reproduced | Exact steps, data/state, platform, build, expected result, and actual result are recorded. |
| Regression added | A focused externally observable test fails for the reproduced cause. |
| Patch verified | The focused test and relevant neighboring suites pass with the smallest targeted change. |
| Runtime verified | The complete user journey passes on its intended simulator/device/platform and survives relaunch when applicable. |

## Current baseline

- Repository snapshot: 2026-08-18 working tree with extensive pre-existing modifications.
- Paper map: eight artboards on the active Agent.cy design-system file.
- Automated baseline on 2026-08-18: `pnpm typecheck`, `pnpm test` (140 tests), and `pnpm build` passed; the Xcode project passed 611 tests on iPhone 17 Pro / iOS 26.5 with isolated Derived Data, and the Catalyst desktop build passed.
- Baseline warnings: deprecated synchronous `AVAssetImageGenerator.copyCGImage` calls in the app and share extension, plus deprecated `UIWindow(frame:)` test setup. They are performance/maintenance risks to measure under their owning page IDs, not confirmed defects from this pass.
- Confirmed defects from this mapping pass: none. Source drift and missing runtime evidence are not confirmed defects.
- `PAGE-ROOT-01` is `Verified`: 12 focused root tests, a file-backed relaunch, a deterministic restore-to-app simulator fixture, and timestamped launch signposts now cover the frozen routing contract. The full Debug suite passed 528 tests. `PERF-RISK-01` remains open for large real-store profiling; that risk is not a routing coverage gap. See [`docs/audits/PAGE-ROOT-01.md`](audits/PAGE-ROOT-01.md).
- `PAGE-ROOT-05` is `Verified`: nine focused page regressions, a disposable-device replay, and the full 562-test iOS suite cover its eight-step state, palette handoff, recovery, notification consent, accessibility, persistence, and structured polling contract. See [`docs/audits/PAGE-ROOT-05.md`](audits/PAGE-ROOT-05.md).
- `PAGE-ROOT-06` is `Coverage gap`: seven focused regressions and a six-root simulator replay cover the repaired shell policies, pending-task precedence, and static reduced-motion branch; the full suite passed 569 tests. Unlocked deep-stack switch/reselect, nested workspace-switch, and actual Reduce Motion environment replay remain required before `Verified`. See [`docs/audits/PAGE-ROOT-06.md`](audits/PAGE-ROOT-06.md).
- `PAGE-ROOT-07` is `Coverage gap`: ADR 0012 resolves Catalyst as maintained internal/deferred scope; seven focused regressions and the 576-test full suite cover repaired route, presentation, workspace, accessibility-policy, and utility-scope boundaries, and the Catalyst target builds. Unlocked narrow/wide, keyboard/pointer, modal, workspace, and performance replay remains required. See [`docs/audits/PAGE-ROOT-07.md`](audits/PAGE-ROOT-07.md).
- `PAGE-MAIN-01` is `Coverage gap`: six focused regressions and simulator state injection cover repaired archive filtering, clock policy, global presentation ownership, reduced-motion work, and bounded unread-badge layout. The 582-test suite, TypeScript checks, and both builds are green. Unlocked tap-through, VoiceOver, actual Reduce Motion, and a real foreground transition across midnight or time-zone change remain required. See [`docs/audits/PAGE-MAIN-01.md`](audits/PAGE-MAIN-01.md).
- `PAGE-MAIN-02` is `Coverage gap`: eight focused regressions and simulator state injection cover repaired clock rebasing, truthful work/post timing, duplicate-safe indexing, reduced motion, one-pass List projection, and accessibility Week/List/Calendar layouts. The 589-test suite, TypeScript checks, and both builds are green. Unlocked tap-through, VoiceOver, actual Reduce Motion, lifecycle/external-route replay, bottom-navigation clearance, and the deeper explicit task-row clause remain required. See [`docs/audits/PAGE-MAIN-02.md`](audits/PAGE-MAIN-02.md).
- `PAGE-MAIN-03` is `Coverage gap`: eight focused regressions plus three neighboring domain regressions and simulator state injection cover repaired task-date separation, off-week post/history reachability, half-open Monday windows, output-only archive linkage, clock rebasing, reduced motion, one-pass projection, canonical routing, and accessibility semantics. The 597-test suite, TypeScript checks, and both builds are green. Unlocked tap-through, creation/completion, VoiceOver, actual Reduce Motion, lifecycle, and bottom-navigation clearance remain required. See [`docs/audits/PAGE-MAIN-03.md`](audits/PAGE-MAIN-03.md).
- `PAGE-MAIN-04` is `Coverage gap`: seven focused regressions and simulator state injection cover repaired malformed hierarchy reachability, duplicate-safe one-pass usage, the half-open Monday window, clock rebasing, truthful capacity, atomic selected-palette creation, and accessibility layouts including full weekday rows in place of chips. The 604-test suite, TypeScript checks, and both builds are green. Unlocked tap-through, creation/persistence, VoiceOver, actual Reduce Motion, real week rollover, and bottom-navigation clearance remain required. See [`docs/audits/PAGE-MAIN-04.md`](audits/PAGE-MAIN-04.md).
- `PAGE-MAIN-05` is `Coverage gap`: seven focused regressions and simulator state injection cover repaired workspace scoping, stale-filter capture safety, archived-pillar search, selection/platform reconciliation, missing-route consumption, Reduce Motion policy, and accessibility presentation. The 611-test suite, TypeScript checks, and both builds are green. Unlocked search/filter/deletion, workspace-switch, exit routing, keyboard/bottom clearance, VoiceOver, actual Reduce Motion, and Release-device large-library profiling remain required. See [`docs/audits/PAGE-MAIN-05.md`](audits/PAGE-MAIN-05.md).
- `PAGE-MAIN-06` is `Coverage gap`: the workspace-switch stale-thread defect and the accessibility-size rail truncation were reproduced on a disposable driven simulator, repaired through the full gate with creator authorization (seven focused regressions, 619 iOS tests, runtime-verified replay), and shipped to the creator's iPhone as signed Debug build 211. Streaming/cancel/live-error, proposal-review fixtures, relaunch (blocked by the account gate), VoiceOver, actual Reduce Motion, Catalyst overlay replay, and `PERF-RISK-02`/`07` Release profiling remain required. See [`docs/audits/PAGE-MAIN-06.md`](audits/PAGE-MAIN-06.md).
- `PAGE-MAIN-07` is `Coverage gap`: the invisible cross-platform live-post save was reproduced with a driven replay and repaired under the creator's "IG only" decision — the Feed add-live sheet is scoped to Instagram with honest rejection copy while Agenda and the Creation Hub keep all platforms. Three focused regressions and 622 iOS tests pass; the repair is runtime-verified. Workspace-switch replay, thumbnail hydration outcomes, accessibility/dark captures, Catalyst presentation, and `PERF-RISK-03`/`05` measurements remain required. See [`docs/audits/PAGE-MAIN-07.md`](audits/PAGE-MAIN-07.md).
- `PAGE-MAIN-08` is `Coverage gap`: populated, search/no-match, and delete cancel/confirm states were replayed on the disposable driven simulator with no reproduced defects at close; `DEFECT-MAIN-08-01` (saved-post open relocated the app to Idea Bank behind the shell-owned review — most visible on Catalyst) was creator-reported after close and resolved same-day through the full gate (red regression, one-line fix, 626 tests, desktop reinstalled) — deletion confirmation copy, strict unowned-record scoping, and honest empty/no-match copy all held. Analysis-state rows, duplicate import, hydration outcomes, workspace switch, accessibility, Catalyst, and `PERF-RISK-13` measurements (uncapped hydration batch, per-keystroke pillar scans, un-downsampled decodes) remain required. See [`docs/audits/PAGE-MAIN-08.md`](audits/PAGE-MAIN-08.md).
- `PAGE-MAIN-09` is `Coverage gap`: unread badge, needs-attention/earlier sections, All/Unread filters, filtered mark-all-read, and row routing replayed green on the disposable driven simulator with no reproduced defects. Per-record menu actions, stale-target routing, content-filter mix, accessibility, Catalyst, and workspace switch remain required. See [`docs/audits/PAGE-MAIN-09.md`](audits/PAGE-MAIN-09.md).
- `PAGE-MAIN-10` is `Coverage gap`: history listing with the Current marker, transcript continue/return, and confirmed deletion with active-thread preservation replayed green on the disposable driven simulator with no reproduced defects. Deleting the current thread, delete errors, accessibility, workspace-switch-while-open, and Catalyst remain required. See [`docs/audits/PAGE-MAIN-10.md`](audits/PAGE-MAIN-10.md).
- **Release build defect resolved 2026-08-18**: the Release configuration failed to compile — Swift 6 region-based checking under whole-module optimization rejected `RecurringPostSchedule.findOrCreateSeries` capturing the `brief` @Model inside the series-lookup closure (`sending 'brief' risks causing data races`), blocking every Release/TestFlight build from this tree. Smallest fix: the closure captures the plain `workspaceID` value instead of the model. Release now builds and codesigns; the full 622-test Debug suite stays green. Discovered while preparing the first Release-device profiling pass.

## Prioritized programs

| Priority | ID | Program | Why first | Completion gate |
| --- | --- | --- | --- | --- |
| P0 | `AUD-01` | Product truth and navigation | Every page review depends on knowing which platforms and information architecture are intentional. | `DRIFT-01` through `DRIFT-06` are resolved or explicitly classified; one canonical route inventory exists. |
| P0 | `AUD-02` | Root, identity, restoration, workspace isolation | Errors can lock out a creator, duplicate a profile, or expose records across workspaces. | Cold launch, credential delay, restore, workspace switch, delayed records, and relaunch pass with focused tests and runtime proof. |
| P0 | `AUD-03` | Capture-to-post lifecycle | This is the product promise and the highest concentration of state, AI, persistence, and view-reconstruction risk. | All capture paths reach a complete editable brief; proposal and lifecycle transitions survive relaunch and output removal. |
| P1 | `AUD-04` | External entry and inspiration | Extensions, widgets, notifications, shortcuts, and deep links enter the app outside normal navigation. | Every supported host/route opens exactly one canonical destination, preserves scope, and fails safely. |
| P1 | `AUD-05` | Planning, tasks, calendar, reminders, widgets | One record is projected across multiple pages and system services; dates have distinct meanings. | Placement/task independence, rescheduling, completion, time-zone changes, calendar projection, widget actions, and relaunch pass. |
| P1 | `AUD-06` | MCP, server, access, subscription, privacy | These boundaries gate external mutations, AI output, account access, quotas, export, and erase. | Invalid/unauthorized operations fail safely; proposals remain pending; destructive scopes and privacy boundaries are proven. |
| P2 | `AUD-07` | Page UI, accessibility, performance, and Catalyst parity | Visual, interaction, and smoothness defects are meaningful only after behavior and platform scope are settled. | Each in-scope surface passes layout, keyboard, VoiceOver, Dynamic Type, Reduce Motion, empty/error/offline, performance, and window-size checks. |

## `AUD-01`: Product truth and navigation

### Decisions to resolve

- Is Catalyst a current product, internal development surface, or future scope?
- Is the canonical iPhone IA five tabs or the implemented six-tab Home/Plan/Tasks/Pillars/Idea Bank/Cy model?
- Are Feed, Brand Cabinet, Creator Session, and Series current, experimental/hidden, or deferred?
- Which Paper file is canonical?

### Static trace

- Root destination resolution and platform shell selection.
- `AppTab`, `DesktopNavigationDestination`, persistent navigation stacks, sheets, and requested settings pages.
- Deep-link, notification, widget, and phone-intent destination handling.
- Current Paper page/artboard inventory and PRD/Paper-guide claims.

### Acceptance

- One approved route inventory names every in-scope surface and feature status.
- All source documents use the same product boundary and tab names.
- Route tests cover every enum case and unknown/malformed external route.

## `AUD-02`: Root, identity, restoration, and workspace isolation

### Runtime matrix

- New install with unresolved invitation status.
- Valid, invalid, expired, and already-used installation invitation.
- Existing profile with stored credential.
- Linked account while the private profile has not arrived yet.
- Offline launch and later reconnection.
- Workspace switch while detail routes, sheets, widgets, reminders, and MCP snapshots reference the previous workspace.
- Delayed legacy/nil-workspace CloudKit records.

### Function trace

Trace RootView resolution, credential refresh, account redemption/linking, active-workspace selection, WorkspaceScope filtering, bootstrap backfills, route-stack reset, widget snapshot refresh, reminder refresh, calendar refresh, and bridge snapshot generation.

### Acceptance

- No onboarding flash before credential/account resolution.
- No duplicate creator profile during restoration.
- No cross-workspace record appears in any screen, widget, reminder, shortcut, or MCP snapshot.
- A focused regression covers every confirmed root cause before a patch.

## `AUD-03`: Capture-to-post lifecycle

### Runtime matrix

- Quick Idea, Quick Post, Voice Spark, Shared Link, and Find three ideas.
- I'll drive, Collaborate, and Lead me assistance modes.
- Compose immediately, continue dialogue, cancel, retry, dismiss proposal, edit proposal, accept proposal.
- SwiftUI view reconstruction during live preview/editor changes.
- Complete structured proposal hydration, including script, beats, captions, CTA, notes, series/collaboration fields, and proposed tasks.
- Add/remove outputs, schedule/unschedule, mark/unmark Posted, archive, relaunch, and edit while expired.

### Function trace

Trace capture-mode initialization, local draft storage, voice-recording store, inspiration import/shaping, Cy reference policy, API/MCP operation selection, structured proposal decoding, proposal persistence, `LifecycleService`, output-specific status, task generation, and editor reconstruction.

### Acceptance

- Every input creates at most one intended record.
- Unselected Cy directions do not persist.
- No generated mutation persists before acceptance.
- A Ready brief retains all accepted structured fields across relaunch.
- Output and task operations follow the lifecycle invariants in the behavior map.

## `AUD-04`: External entry and inspiration

### Runtime matrix

- Share from Instagram, TikTok, YouTube/Shorts, Safari, and Notes using the actual provider representations.
- Unsupported Photos movie share, malformed/non-HTTPS input, duplicate share, extension termination, low storage, app restart, and offline import.
- Widget/Control destinations, task completion, every deep-link case, notification routes, and Voice Spark phone intent.
- Route request received before account/profile resolution and after a workspace change.

### Function trace

Trace share-item extraction/canonicalization, atomic envelope write, queue drain/commit/removal, deduplication, inspiration content analysis, snapshot generation, intent queue/take semantics, URL parsing, route-state reset, and object lookup.

### Acceptance

- The extension performs no network request and imports only one bounded source.
- Duplicate imports create no extra source or Spark.
- External routes clear stale destination state and open exactly one valid target.
- Unsupported or unavailable destinations fail silently and safely without orphaned state.

## `AUD-05`: Planning, tasks, calendar, reminders, and widgets

### Runtime matrix

- Place, move, pause, archive, schedule, unschedule, mark Posted, and remove final Posted state.
- Standalone, linked, parent, subtask, recurring, completed, deleted, and restored task states.
- Day/week navigation, weekly focus edits, time-zone change, missed target, and week rollover.
- Calendar enable/disable, permission denial, calendar deletion, event update/remove, and external calendar edit.
- Widget refresh, completion undo, stale snapshot, and app relaunch.

### Function trace

Trace agenda queries, task scoping/filtering, scheduling/reschedule policies, recurrence reconciliation, reminder planning, EventKit mapping, widget snapshot generation, pending completion application, and lifecycle recalculation.

### Acceptance

- Task dates never place content on Agenda.
- Task completion never advances the content lifecycle.
- Calendar edits never silently mutate SwiftData.
- Reminder/widget/calendar projections converge after relaunch, time-zone change, and workspace switch.

## `AUD-06`: MCP, server, access, subscription, and privacy

### Runtime matrix

- Native AI and local MCP paths; connected, disconnected, stale heartbeat, malformed snapshot, duplicate request, approval, edit, dismiss, and retry.
- Valid, invalid, cancelled, timed-out, quota-limited, schema-invalid, and provider-failed AI operations.
- Free journey, trial, promotional, Pro, expired, restored purchase, and offline entitlement states.
- Export, workspace reset, content reset, privacy erase, installation-linked metadata deletion, cancellation, failure, and relaunch.

### Function trace

Trace bridge snapshot/queue/review, contract parsing, operation IDs, SSE state machine, server authentication/access/quota checks, validated result emission, subscription projection, export, reset, erasure, and widget/reminder/calendar cleanup.

### Acceptance

- The bridge exposes no destructive or raw-database operation.
- The proxy stores no durable creator content and never emits an unvalidated result.
- Expired access preserves allowed editing/completion/export/erase while blocking new work.
- Reset and erase affect only the confirmed scope and remain correct after relaunch.

## `AUD-07`: UI, accessibility, performance, and platform parity

Start only after `AUD-01` classifies the platform and feature scope.

### Per-surface checks

- Purpose, primary action, entry/exit, empty, loading, error, offline, expired, permission-denied, and destructive-confirmation states.
- Dynamic Type through Accessibility Extra Extra Extra Large.
- VoiceOver order, labels, traits, rotor behavior, and focus restoration.
- Reduce Motion, keyboard appearance/dismissal, safe areas, sheet dismissal, and view reconstruction.
- iPhone widths, Catalyst narrow/wide breakpoints, utility-rail behavior, and pointer/keyboard navigation.
- Design-token ownership, Cy-only terracotta usage, danger treatment, contrast, 44-point controls, and no opacity-only hierarchy.
- First presentation and navigation latency, scrolling/frame hitches, repeated query/sort/filter work, body invalidation, animation cost, synchronous media/file/network work, memory growth, cancellation, and cleanup.

### Acceptance

- Every supported state is reachable and has one clear recovery path.
- No surface invents product intent to fix a visual inconsistency.
- Accessibility and UI regressions have focused tests or a documented manual replay when automation is unavailable.
- Performance concerns are measured and attached to one page ID; code size or complexity alone remains a risk signal rather than a confirmed defect.

## Recording an audit result

Use this exact shape for each audited slice:

```markdown
### YYYY-MM-DD · CONTRACT-ID · Surface or journey

- Platform/build:
- Starting data/state:
- Expected contract:
- Reproduction steps:
- Actual result:
- Evidence: test name, log, screenshot, or video
- Performance evidence: launch/navigation timing, hitch trace, query/body update count, memory trace, or no issue observed
- Classification: verified | drift | coverage gap | confirmed defect
- Next safe action:
```

Do not create a GitHub issue for `drift` or `coverage gap`. A confirmed defect may be filed only after reproduction steps and the external behavior contract are complete.
