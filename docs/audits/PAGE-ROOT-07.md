# PAGE-ROOT-07 Audit: Catalyst shell

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Product boundary: maintained internal pre-release surface under [ADR 0012](../adr/0012-catalyst-maintained-internal-scope.md); excluded from the iPhone-only v1 shipping promise
- Scope owner: [`DesktopAppShellView`](../../ios/AgentCy/Views/Shell/DesktopAppShellView.swift), [`DesktopNavigation`](../../ios/AgentCy/Models/DesktopNavigation.swift), and shared shell state in [`AppModel`](../../ios/AgentCy/ViewModels/AppModel.swift)
- Parent programs: [`AUD-01`](../APP_AUDIT_QUEUE.md#aud-01-product-truth-and-navigation), [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation), and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

Catalyst is actively maintained so it does not accumulate unsafe state or data behavior, but it is not a v1 customer platform. The shell owns eight desktop destinations: Home, Agenda, Feed, Tasks, Pillars, Idea Bank, Saved Posts, and Cy. It preserves each destination's path while switching, resets all paths on workspace change, and honors repeated shared-tab route requests even while Feed or Saved Posts is selected. At most one global or desktop-local presentation may own the screen. Pending MCP review may signal but never interrupt work in progress. Quick Add and its Command-N shortcut remain reachable at both narrow and wide window sizes. Motion, keyboard, pointer, and accessibility behavior follow `design.md`.

| Event | Expected behavior |
| --- | --- |
| First entry | Open Agenda, the desktop planning-first default, with one selected sidebar destination. |
| Sidebar switch | Preserve each destination path; Feed and Saved Posts do not prevent later shared-tab routes from winning. |
| External route | A repeated assignment to the same shared `AppTab` still selects its desktop destination. Task routes dismiss presentations and open once. |
| Presentation | App sheets, inspiration review, Weekly Focus, and custom desktop overlays do not compete or replace work unexpectedly. Escape closes custom overlays. |
| MCP review | Present only a new request for the active workspace, never over another presentation, and never again merely because the app reactivated. |
| Workspace switch | Reset eight paths, route/presentation state, local Weekly Focus state, MCP badge state, and in-flight results from the former workspace. |
| Narrow window | Hide the utility rail, retain Quick Add in the leading sidebar, and keep Command-N working. |
| Wide window | Show the 344-point Control Center, Quick Add, configured widgets, and the center workspace without clipping. |
| Reduce Motion | Remove the utility-rail move/fade transition and resize animation. |

## Repair verification

| Confirmed cause | Repair and evidence |
| --- | --- |
| Product sources disagreed about whether Catalyst was a current product. | ADR 0012 classifies it as maintained internal/deferred scope without changing the iPhone-only v1 PRD. `DRIFT-01` is resolved. |
| Feed and Saved Posts left `selectedTab` stale, so assigning the same tab could drop an external route. | `AppModel.selectedTabRevision` increments on every assignment, including same-value assignment. The desktop shell observes that request revision and resolves the current shared tab every time. |
| Desktop task routing consumed the request under Settings or another sheet. | The shell now uses the shared one-shot `consumeRequestedTaskRoute()`, closes Weekly Focus, dismisses global presentation state, selects Tasks, and appends the task. |
| Scene activation erased MCP presentation memory. | Presented request IDs now survive ordinary inactive/active cycles and clear only when requests disappear, the bridge disconnects, or the workspace changes. |
| MCP checked only `presentedSheet`, so it could replace inspiration review or consume a request behind Weekly Focus. | The desktop policy requires a new request, no shared global presentation, and no local Weekly Focus presentation before auto-presenting. |
| An in-flight MCP read could finish after a workspace switch. | Each read carries its starting workspace ID; a result is discarded if the active workspace changed before completion. |
| Workspace change left desktop-local presentation and MCP badge memory. | Workspace revision now resets all eight paths, Weekly Focus, presented MCP IDs, and the badge in addition to AppModel's shared route cleanup. |
| Archived or cross-workspace outputs entered some Control Center widgets. | One output policy now requires a non-archived brief and both the output and brief to resolve into the active workspace. All `utilityBrief(for:)` consumers use it. |
| Quick Add existed only inside the wide utility rail. | The same Quick Add control moves to the leading sidebar below the 1,280-point breakpoint, so one Command-N owner remains mounted in either layout. |
| Utility-rail motion ignored Reduce Motion. | Both its transition and resize animation are disabled by the reduced-motion policy. |
| Desktop visual/accessibility chrome drifted. | Sidebar selection now exposes `.isSelected`; Settings uses the Nucleo-mapped sliders icon; custom overlays support Escape; and the floating Cy control uses a neutral surface, accent glyph, neutral border, and ambient shadow instead of a solid accent fill and glow. |

## Automated evidence

- **7 PAGE-ROOT-07 regressions passed**: repeated same-tab routing, global/local MCP blocking and non-repeat, stale-workspace MCP rejection, narrow/wide Quick Add placement, reduced-motion policy, utility-output scope, and one-shot task-route consumption.
- The full shared iOS suite passed **576 tests with 0 failures** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data. This validates the shared AppModel revision behavior as well as existing phone behavior.
- The `AgentCy Desktop` Catalyst target compiled successfully after every Catalyst-only view repair.
- The same working-tree TypeScript baseline remained green at **140 tests**, with typecheck and production builds passing earlier in this audit cycle; no TypeScript file changed during PAGE-ROOT-07.
- Existing synchronous thumbnail and test-window deprecation warnings remain outside this page.

## Runtime coverage gap

The Mac locked after the user stepped away. The current turn could compile the Catalyst target but could not drive or inspect its live windows without bypassing the locked session. The following dated runtime replay remains required:

1. Resize across 1,280 points in light, dark, and Reduce Motion; verify sidebar/Control Center fit and Command-N in both layouts.
2. Select Feed while the shared tab is already Agenda, trigger the same Agenda route, and verify the requested list becomes visible. Repeat with Idea Bank.
3. Open Settings and Weekly Focus separately, then deliver a task route and an MCP request; task routing must win visibly while MCP must wait.
4. Cmd-Tab away and back with the same pending MCP request; it must not reopen. Switch workspaces during an MCP refresh and confirm no stale badge or review.
5. Verify VoiceOver selected-state announcement, pointer hover, keyboard focus order, and Escape dismissal for both custom overlays.

These are view-lifecycle and input-system checks. Pure policy tests and a successful build cannot replace them, so PAGE-ROOT-07 is not marked `Verified`.

## Performance and smoothness

Classification: **Performance risk; no measured Catalyst regression**.

- The 1,698-line shell owns nine whole-table `@Query` collections and 36 utility-derived properties/functions at the root window level. Even when the narrow layout omits the Control Center, record changes still invalidate the shell owner and its query-backed state.
- Several widgets scan `allOutputs` repeatedly, and `utilityBrief(for:)` performs a linear `allBriefs.first` lookup for each candidate. Week at a Glance and Consistency multiply this across seven days or eight weeks. That creates output-count × brief-count work in body-derived state.
- The repair deliberately did not perform a broad performance refactor without Release evidence. `PERF-RISK-08` requires Instruments measurements with production-sized data before moving queries into a conditional child owner or replacing repeated scans with one duplicate-safe brief index.
- The four-second MCP read remains detached from the main actor and now discards stale-workspace results. Energy and file-coordination cost still require Release measurement.
- Resize animation is now absent under Reduce Motion, removing one known source of avoidable layout churn.

## Resolved defects and remaining coverage

1. `DRIFT-01` — **Resolved**: Catalyst is maintained internal/deferred scope under ADR 0012.
2. `DEFECT-ROOT-07-01` — **Resolved**: same-value shared-tab routes are not dropped from Feed or Saved Posts.
3. `DEFECT-ROOT-07-02` — **Resolved**: task routes dismiss presentation state and are consumed once.
4. `DEFECT-ROOT-07-03` — **Resolved**: MCP review does not interrupt another presentation or repeat on reactivation.
5. `DEFECT-ROOT-07-04` — **Resolved**: former-workspace MCP results and desktop-local state are invalidated.
6. `DEFECT-ROOT-07-05` — **Resolved**: utility output projections exclude archived and cross-workspace records consistently.
7. `DEFECT-ROOT-07-06` — **Resolved**: Quick Add and Command-N remain available in the narrow layout.
8. `DEFECT-ROOT-07-07` — **Resolved**: reduced-motion, selected-state, Nucleo icon, Escape, and floating-Cy chrome match the recorded desktop contract.
9. `PERF-RISK-08` — **Open**: whole-table root queries and repeated output-to-brief scans need Release Mac profiling.
10. `GAP-ROOT-07-01` — **Open**: the five unlocked Catalyst lifecycle/input replays above remain required.

## Classification and next gate

PAGE-ROOT-07 is closed as `Coverage gap`. Its product boundary and known source-level defects are resolved, all automated checks are green, and the Catalyst target builds. Reclassify it only after the unlocked narrow/wide, routing, modal, workspace, keyboard, pointer, accessibility, and performance replay is recorded.
