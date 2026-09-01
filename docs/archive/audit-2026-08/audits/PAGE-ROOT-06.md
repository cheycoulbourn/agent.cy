# PAGE-ROOT-06 Audit: Phone shell

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Scope owner: [`AppShellView`](../../ios/AgentCy/Views/Shell/AppShellView.swift), shared shell state in [`AppModel`](../../ios/AgentCy/ViewModels/AppModel.swift), and external-route handoff in [`RootView`](../../ios/AgentCy/App/RootView.swift)
- Parent programs: [`AUD-01`](../APP_AUDIT_QUEUE.md#aud-01-product-truth-and-navigation), [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation), and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

The iPhone shell owns six persistent root stacks: Home, Plan, Tasks, Pillars, Idea Bank, and Cy. Switching tabs preserves the destination stack of both the source and destination tabs. Reselecting the active tab pops only that tab to its root. The shell may show only one global presentation at a time. A requested record route dismisses an existing global presentation and becomes the visible destination. A workspace change clears every record-scoped stack, route, and presentation before records from the new workspace appear; Settings may remain open because it owns workspace selection. Reduce Motion removes continuous decorative animation.

| Event | Expected behavior |
| --- | --- |
| First entry | Show the persisted selected tab with one selected-state affordance and no stale route or presentation. |
| Switch tab | Preserve every tab's current `NavigationPath`; reveal the destination at its prior depth. |
| Reselect active tab | Reset only the active tab's path to its root. |
| Global presentation | Present exactly one App sheet or inspiration-review sheet. A new global presentation replaces the old state. |
| Pending task route | Dismiss the current presentation, select Tasks, reset the Tasks path, and open the requested task once. |
| Workspace switch | Clear six paths plus record-scoped capture, widget, task, and inspiration state. Dismiss content sheets; Settings may remain. |
| Walkthrough | Move through the six canonical tabs without leaving another global presentation underneath it. |
| MCP review | Present only newly observed pending requests, never interrupt another presentation, and do not reopen the same unresolved request on scene re-entry. |
| Reduce Motion | Use a static Cy planning cue instead of a continuously ticking timeline. |

## Repair verification

| Confirmed cause | Repair and evidence |
| --- | --- |
| Every tab selection reset the destination path. | `selectTab` now resets only when `current == tapped`. A 36-combination policy regression covers all six source and destination tabs. |
| App sheets and inspiration review used independent presentation state. | The two state properties now evict one another, and all route helpers share `dismissGlobalPresentation()`. |
| A pending task could be pushed while another sheet remained visible. | The task request is consumed once through one helper that dismisses global presentation state before selecting Tasks and appending the destination. A DEBUG launch fixture replayed Quick Capture plus a requested task; after the native dismissal transition, only the task remained visible. |
| Workspace change retained stale record-scoped shell state. | `prepareShellForWorkspaceSwitch()` clears record routes and presentations before the workspace revision resets all six paths; Settings is intentionally retained. |
| Reduce Motion still instantiated a 30-fps `TimelineView`. | The reduced-motion branch is now a static circle. The timeline exists only in the motion-enabled branch. |
| MCP polling forgot prior requests on every active-scene entry and ignored inspiration review as a presentation. | Presented request IDs survive scene activation. Presentation requires at least one new request and no global presentation. |
| Product sources disagreed about five versus six phone tabs. | The behavior map and Paper implementation guide now name the implemented six-tab phone information architecture. |

## Automated evidence

- **7 PAGE-ROOT-06 regressions passed**: all tab switch/reselect combinations, mutually exclusive presentations, one-shot task-route consumption, workspace cleanup with Settings retention, reduced-motion policy, MCP non-repeat/non-interruption, and the runtime task fixture.
- The relevant routing, weekly-planning cue, inspiration import, and PAGE-ROOT-06 batch passed **27 tests with 0 failures**.
- The full iOS suite passed **569 tests with 0 failures** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data.
- `pnpm typecheck`, `pnpm test` (**140 tests**), and `pnpm build` passed. The `AgentCy Desktop` Catalyst build also passed.
- Existing warnings remain: synchronous `AVAssetImageGenerator.copyCGImage` deprecations and deprecated `UIWindow(frame:)` test setup. Neither was introduced by this page repair.

## Disposable-simulator replay

A disposable iPhone 17 Pro / iOS 26.5 simulator with in-memory preview data was used only for PAGE-ROOT-06.

| Scenario | Observed result |
| --- | --- |
| Six roots | Home, Plan, Tasks, Pillars, Idea Bank, and Cy each cold-launched, rendered their own root, and showed the correct selected tab. No root was clipped by the floating navigation. |
| Pending route over Quick Capture | The first capture recorded the native sheet dismissal in progress with the requested task already behind it. A stable follow-up capture showed Quick Capture gone and `Edit the 45-second cut` as the sole visible destination. |
| Offline Cy | Preview-mode Cy rendered its expected unavailable/offline state without blocking navigation. |
| Relaunch | Each fixture launch resolved directly into the requested shell tab with the in-memory creator data intact for that launch. |

The Mac locked after the user stepped away, so the audit could not use desktop-driven taps to replay a deep navigation stack through switch → return → reselect, a nested workspace change, or the Accessibility Reduce Motion toggle. Unit policy coverage and per-tab runtime fixtures are not substitutes for those view-lifecycle interactions. This is the sole reason the page is classified `Coverage gap` rather than `Verified`.

## Performance and smoothness

Classification: **Performance risk; no measured shipping regression**.

- The shell keeps all six `NavigationStack` roots mounted and hides five with layer state. The six root files contain 74 static `@Query`, `.task`, `.onReceive`, or `TimelineView` signal lines: Home 15, Plan 8, Tasks 19, Pillars 13, Idea Bank 6, and Cy 13. Hidden roots may continue query observation and task work.
- One DEBUG simulator snapshot with preview data reported approximately 341 MB resident memory. Simulator/debug memory is not representative of a Release build, so this is only a profiling trigger and is not a product-performance claim.
- The reduced-motion Cy cue no longer owns a continuously ticking timeline. The normal cue still updates at 30 fps only while its small planning indicator is visible.
- MCP review polling remains a four-second shell task. It now avoids repeated presentation and respects other global presentations, but Release-device energy and inactive-tab work still need Instruments evidence.
- Required follow-up under `PERF-RISK-07`: compare a one-root prototype or lazy-root strategy against the current retained-stack behavior using Release-device body-update counts, SwiftData fetch activity, memory, tab latency, scroll hitches, and path restoration correctness.

## Resolved defects and remaining coverage

1. `DEFECT-ROOT-06-01` — **Resolved**: switching tabs preserves paths; reselecting resets only the active path.
2. `DEFECT-ROOT-06-02` — **Resolved**: global presentation state is mutually exclusive.
3. `DEFECT-ROOT-06-03` — **Resolved**: a task route dismisses presentation state and is consumed only once.
4. `DEFECT-ROOT-06-04` — **Resolved**: workspace change clears record-scoped shell state before path invalidation.
5. `DEFECT-ROOT-06-05` — **Resolved**: Reduce Motion does not instantiate the 30-fps planning timeline.
6. `DEFECT-ROOT-06-06` — **Resolved**: MCP review does not repeatedly reclaim the screen or interrupt another global presentation.
7. `DRIFT-02` — **Resolved**: the canonical phone navigation is six tabs.
8. `GAP-ROOT-06-01` — **Open**: unlocked runtime replay must prove deep switch/return preservation, active-tab reselect pop, nested workspace invalidation, and the actual Reduce Motion environment branch.

## Classification and next gate

PAGE-ROOT-06 is closed as `Coverage gap`. Its known defects are repaired and the complete automated baseline is green. Reclassify it to `Verified` only after the four unlocked lifecycle checks in `GAP-ROOT-06-01` pass without stale content or extra presentations.
