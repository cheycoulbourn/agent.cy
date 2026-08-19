# PAGE-MAIN-03 Audit: Tasks

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Scope owner: [`TasksView`](../../ios/AgentCy/Views/Tasks/TasksView.swift), shared task policies in [`DomainTypes`](../../ios/AgentCy/Models/DomainTypes.swift), and the canonical phone-shell task route in [`AppShellView`](../../ios/AgentCy/Views/Shell/AppShellView.swift)
- Parent programs: [`AUD-05`](../APP_AUDIT_QUEUE.md#aud-05-planning-tasks-calendar-reminders-widgets) and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

Tasks is the active workspace's complete top-level work index. Focus tasks are standalone creator work. Post tasks are work linked to a brief or output. Both lists keep completion independent from content lifecycle and remain filterable by status, task-owned date, pillar, priority, and focus. A linked post or brief date may provide context, but it must never become the task's due date, group, overdue state, or Date-filter value. Post tasks and completed or archived history remain reachable across weeks; only materialized recurring Focus tasks retain a bounded future horizon.

| Event or state | Expected behavior |
| --- | --- |
| Focus tasks / Post tasks | Classify by direct brief or output association, not a legacy lane value. |
| Open / Completed / Archived | Keep completed history and tasks from archived posts reachable without silently dropping off-week records. |
| Task date | Use `targetDate`, then `dailyFocusDate`; never substitute output target date or brief work/agenda date. |
| This Week | Use the same Monday-through-Sunday half-open interval as Plan, regardless of locale first-weekday settings. |
| Linked output only | Resolve the output's brief for archive and pillar context even when the task has no direct brief ID. |
| Completion | Toggle parent and subtask completion independently without advancing the linked post lifecycle. |
| Clock change | Refresh Today, past-due, grouping, sorting, and filters on appearance, active foreground, and significant-time changes. |
| Empty state | Explain the selected collection/status honestly and offer creation only where that status permits it. |
| Accessibility | Keep collection controls bounded, stack task metadata at accessibility sizes, preserve readable task titles, and expose accurate group count and collapse semantics. |
| Reduce Motion | Change collections without the page transition animation. |

## Function and exit trace

| Tasks area | Source data | Canonical exit |
| --- | --- | --- |
| Header | active creator/workspace and active filter count | filter sheet or Settings |
| Collection rail | task association policy | Focus tasks or Post tasks |
| Filter sheet | status, task date, pillar, priority, and focus policies | apply in place, clear, or Done |
| Open list | one filtered/sorted projection grouped by task-owned date | checkbox, group collapse, task detail, linked post, or add task |
| Completed/Archived list | preserved top-level history grouped by task-owned date | task detail, linked post, or status/filter change |
| Creation | selected collection | Quick Capture task or Post Task creation flow |
| Requested task route | shell-owned task path and workspace-scoped lookup | task detail or honest Task not found state |

## Repair verification

| Confirmed cause | Repair and evidence |
| --- | --- |
| Task visibility and presentation used a `visibilityDate` that could substitute output placement for task due date. | `TaskRootDatePolicy` now permits only task-owned `targetDate ?? dailyFocusDate` for root filtering, grouping, sorting, overdue state, and row metadata. |
| Post tasks and history disappeared outside the current week. | `TaskListVisibilityPolicy` and `TaskRootVisibilityPolicy` now keep all post tasks plus completed/archived history reachable; only future materialized recurring Focus tasks are bounded. Cy's task-attention expectation was aligned to the same rule. |
| Monday intervals used `DateInterval.contains`, which admitted the next Monday boundary. | `TaskCalendarPolicy.contains` makes the interval explicitly half-open: Monday inclusive, next Monday exclusive. |
| Output-only tasks did not inherit their linked brief's archive state. | A duplicate-safe output-to-brief index now resolves archive state for direct-brief and output-only tasks. |
| Root filtering rebuilt archive and output maps inside repeated work and the page derived the full filtered list twice. | Archive IDs and the duplicate-safe output index are built once per filter pass; `taskPage` derives one visible list and one group projection per call. |
| Relative labels could retain yesterday's wall clock. | `TasksView` owns one `tasksNow` reference and refreshes it on appearance, active scene entry, and significant-time notifications. |
| Collection changes always animated. | `TaskRootMotionPolicy` removes collection animation under Reduce Motion. |
| Group headers exposed misleading button traits and incomplete state; fixed controls and task metadata became cramped at large text sizes. | Non-collapsible headers are semantic text, collapsible headers announce count plus Expanded/Collapsed, fixed picker/badge visuals are bounded, task titles gain three lines, and metadata stacks at accessibility sizes. |
| A per-row lazy navigation destination produced an oversized automatic List disclosure accessory at maximum text size. | Rows now request the shell's single canonical task route and render a bounded visual forward icon. Missing IDs still resolve through the shared Task not found destination. |

## Automated evidence

- **8 PAGE-MAIN-03 regressions passed**: task-owned date separation, off-week post/history reachability, output-only archive linkage, Monday/next-Monday boundaries, clock rebasing, reduced motion, accessibility/group semantics, and canonical detail routing.
- **3 neighboring domain regressions passed** for Date filters, cross-week post visibility, and Cy task attention.
- The full shared iOS suite passed **597 tests with 0 failures** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data.
- The `AgentCy Desktop` Catalyst target compiled successfully with the shared task-policy changes.
- `pnpm typecheck`, all **140 TypeScript tests**, and `pnpm build` passed in the same working tree.

## Runtime evidence

One disposable iPhone 17 Pro / iOS 26.5 simulator used in-memory preview data and explicit Tasks fixtures. The audit visually inspected:

1. Empty Focus tasks and populated Post tasks in normal light appearance.
2. Populated Post tasks in normal dark appearance, including dated, undated, linked, parent, and subtask presentation.
3. Post tasks at Accessibility Extra Extra Extra Large after replacing the automatic List disclosure accessory; the task title receives three lines, metadata stacks, and the forward icon remains bounded.
4. The filter sheet at Accessibility Extra Extra Extra Large; its content scrolls, primary controls remain reachable, and fixed header controls do not grow with content text.
5. Repeated cold preview launches on both Tasks and Home. Both log the same SwiftUI `NavigationRequestObserver` invalid-configuration warning, isolating it to the retained root-shell navigation architecture rather than the Tasks row. This is recorded under `PERF-RISK-07`; no user-visible Tasks failure was reproduced after launch settled.

## Remaining runtime coverage gap

The Mac remained locked after the user stepped away, so the audit did not bypass the session to drive live taps or VoiceOver. Before reclassifying this page as `Verified`, record one unlocked pass that:

1. Switches both collections and all status/date/pillar/priority/focus filters, clears filters, collapses a Focus group, and reaches the bottom of each list under the persistent navigation.
2. Creates one Focus task and one Post task, opens each detail, follows the linked post, returns, and verifies a missing/deleted requested task uses the honest fallback.
3. Toggles a parent and subtask independently while Open, Completed, and Archived filters redraw, then verifies the linked post lifecycle does not advance.
4. Replays VoiceOver order, labels, traits, count/collapse announcements, focus restoration, and actual Reduce Motion at normal and maximum accessibility text sizes.
5. Foregrounds the retained page across a real midnight or time-zone change and confirms Today, past-due, This Week, grouping, and sorting rebase together.

## Performance and smoothness

Classification: **two resolved deterministic work risks plus two open profiling risks**.

- The root no longer runs the full filter/sort projection twice for one render and no longer rebuilds archive/output linkage inside each task check.
- Replacing per-row lazy navigation destinations removes one destination observer and automatic disclosure accessory per visible task.
- `TasksView.swift` is 2,367 lines. The root owns six whole-table `@Query` collections and still performs linear output/brief/pillar/title and subtask scans while producing rows. This is a risk signal, not proof of a hitch.
- `PERF-RISK-11` requires Release-device profiling with production-sized small, medium, and large workspaces. Measure root body invalidations, SwiftData fetches, filter/group time, row work, scrolling/frame hitches, task toggle redraw, collection-switch latency, retained-tab background work, and memory before splitting query owners or adding more indexes.
- `PERF-RISK-07` now also records the root-wide `NavigationRequestObserver` warning reproduced on both Home and Tasks in the DEBUG iOS 26.5 simulator. Confirm impact on a Release device before changing the six-stack shell architecture.

## Resolved defects and remaining coverage

1. `DEFECT-MAIN-03-01` — **Resolved**: linked post placement no longer masquerades as task due date.
2. `DEFECT-MAIN-03-02` — **Resolved**: post tasks and task history no longer disappear across week boundaries.
3. `DEFECT-MAIN-03-03` — **Resolved**: the Monday interval excludes the next Monday boundary.
4. `DEFECT-MAIN-03-04` — **Resolved**: output-only tasks inherit archived brief context.
5. `DEFECT-MAIN-03-05` — **Resolved**: retained date state now refreshes deterministically.
6. `DEFECT-MAIN-03-06` — **Resolved**: collection transitions honor Reduce Motion and task/group accessibility semantics are accurate.
7. `DEFECT-MAIN-03-07` — **Resolved**: each visible task no longer installs its own lazy destination or oversized automatic disclosure accessory.
8. `PERF-RISK-11` — **Open**: root query ownership and remaining derived scans need Release-device profiling.
9. `PERF-RISK-07` — **Open**: root-shell retained navigation needs Release-device measurement and warning isolation.
10. `GAP-MAIN-03-01` — **Open**: unlocked tap, creation, completion, VoiceOver, actual Reduce Motion, lifecycle, and bottom-clearance replay remains required.

## Second opinion

Fable independently agreed that task-owned dates must remain separate from post placement, off-week post work/history must remain reachable, duplicate linkage should be indexed once, and per-row lazy navigation destinations should be removed. Fable was advisory and made no edits.

## Classification and next gate

PAGE-MAIN-03 is closed as `Coverage gap`. All confirmed source-level defects are repaired, representative light/dark/accessibility/filter states were visually replayed, 597 iOS tests and 140 TypeScript tests pass, and both platform targets build. Reclassify it only after the unlocked five-part runtime pass is recorded.
