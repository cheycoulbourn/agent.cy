# PAGE-MAIN-01 Audit: Home

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Scope owner: [`HomeDashboardView`](../../ios/AgentCy/Views/Home/HomeDashboardView.swift), shared presentation state in [`AppModel`](../../ios/AgentCy/ViewModels/AppModel.swift), and global sheet hosts in [`AppShellView`](../../ios/AgentCy/Views/Shell/AppShellView.swift) and [`DesktopAppShellView`](../../ios/AgentCy/Views/Shell/DesktopAppShellView.swift)
- Parent programs: [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation), [`AUD-05`](../APP_AUDIT_QUEUE.md#aud-05-planning-tasks-calendar-reminders-widgets), and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

Home is the truthful daily launch surface for the active workspace. It summarizes today's focus, posts, top-level open tasks, late work, recent work, brand work, and activity without turning archived briefs back into active work. Its displayed calendar day and greeting refresh when the app becomes active and when iOS reports a significant time change. Weekly Focus and Activity are global shell presentations, so they cannot compete with task routes, Settings, inspiration review, or MCP review. Every card either shows a truthful empty state or exits to the canonical detail, tab, settings page, or sheet.

| Event or state | Expected behavior |
| --- | --- |
| Empty day | Show honest empty copy without inventing a scheduled post, task, or activity record. |
| Busy day | Show only active-workspace records; today's task card includes open, unskipped top-level work and may reveal its subtasks. |
| Scheduled today | “Up next” includes only scheduled or posted outputs targeted to the current calendar day. |
| Late or missed | “Needs a new date,” Cy Noticed, and unread activity agree on unresolved past-due work. |
| Archived linked work | Exclude linked tasks and posted outputs when their brief is archived. |
| Clock change | Recompute the day and greeting after foregrounding or a significant time, time-zone, or calendar change. |
| Activity and Weekly Focus | Present through `AppModel.presentedSheet`; one global owner wins and external routing can dismiss it safely. |
| Accessibility | Keep the full unread count in the accessibility label, bound the visual badge inside its 44-point control, make content scroll at accessibility sizes, and stop visually static timelines under Reduce Motion. |

## Function and exit trace

| Home area | Source data | Canonical exit |
| --- | --- | --- |
| Header | profile/workspace identity, current clock, visible activity | Settings, Activity, or Cy tab |
| Up next | scoped outputs plus owning brief | day view or post detail |
| Continue working / drafts / recent ideas / recently posted | scoped briefs and outputs | work or output detail, Idea Bank |
| Today’s tasks | scoped tasks plus archived-brief set | task completion/detail or Tasks tab |
| Needs a new date / Cy Noticed | past-due outputs and reconciliation policy | missed-work detail or reschedule flow |
| This week / next week / week at a glance / consistency | dated scoped outputs plus brief state | Plan or post detail |
| Pillar usage / Brand cabinet | scoped pillars, briefs, outputs, and partners | Pillars or brand detail |
| Weekly focus | focus templates and overrides | globally owned Weekly Focus sheet |

## Repair verification

| Confirmed cause | Repair and evidence |
| --- | --- |
| Today's task filter did not consult the owning brief, so a task linked to an archived brief could remain active on Home. | `HomeTodayTaskPolicy` now requires open, unskipped, top-level work on the reference day and rejects archived linked briefs. Home computes the scoped archived-ID set once for the task projection. |
| Recently Posted accepted any posted output even when its owning brief was archived. | `HomeRecentlyPostedPolicy` excludes archived briefs before accepting either posted state. |
| `today` and the greeting called `Date()` from computed properties, but the retained Home root had no midnight or time-zone invalidation. | Home now owns one `dashboardNow` state, refreshes it on appearance, active scene entry, and `UIApplication.significantTimeChangeNotification`, and derives both day and greeting through a tested clock policy. |
| Home owned separate local Weekly Focus and Activity sheets outside the shell's mutual-exclusion state. A global route or MCP review could compete with them. | Both entrances now set explicit global `AppSheet` cases. Phone and Catalyst sheet hosts render those cases; Home no longer owns local sheet booleans. |
| `CyAnimatedLogo` kept a 30-fps timeline alive under Reduce Motion even though every rendered frame was identical. | The reduced-motion branch is now a static mark. Normal motion is unchanged. |
| The unread badge's scaled font overflowed the 44-point bell control at accessibility XXL and covered adjacent header controls. | The badge's visual type size is bounded to Large, while its accessibility label continues to announce the full unread count. A second accessibility-XXL screenshot confirmed the badge stays inside the bell. |

## Automated evidence

- **6 PAGE-MAIN-01 regressions passed**: archived today-task filtering, archived recently-posted filtering, reference-clock day/greeting behavior, global sheet ownership, reduced-motion timeline suppression, and bounded/capped unread-badge presentation.
- The full shared iOS suite passed **582 tests with 0 failures** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data.
- The `AgentCy Desktop` Catalyst target compiled successfully with the new shared sheet cases and Home changes.
- `pnpm typecheck`, all **140 TypeScript tests**, and `pnpm build` passed in the same working tree.
- `git diff --check` passed for the audited patch set.

## Runtime evidence

One disposable iPhone 17 Pro / iOS 26.5 simulator used in-memory preview data and isolated Home-card fixtures. The audit visually inspected:

1. An empty Up Next card and a busy Today’s Tasks card with one parent and two subtasks.
2. A scheduled-today post card, plus a missed Aug 17 post with matching Cy Noticed and unread badge state.
3. An explicit unread activity badge, the empty Activity sheet, and globally injected Weekly Focus and Activity presentations.
4. The scheduled-today card in dark appearance.
5. Home at accessibility XXL before and after the unread-badge repair; the repaired badge remained bounded and the vertically growing content remained scrollable.

The simulator initially needed one preview-data relaunch before a freshly migrated task appeared in an isolated card; the full Home view and every subsequent isolated relaunch projected the task correctly. This was confined to the DEBUG in-memory preview/bootstrap sequence and was not treated as production evidence.

## Remaining runtime coverage gap

The Mac remained locked after the user stepped away, so the audit did not bypass the session to drive live taps or VoiceOver. Before reclassifying this page as `Verified`, record one unlocked pass that:

1. Taps every Home exit once, returns, and confirms card scroll position and shell stack behavior remain coherent.
2. Opens Activity and Weekly Focus from Home, then delivers a task route and an MCP request to confirm one visible presentation throughout.
3. Marks an activity record read and confirms the badge decrements without changing unrelated reminders.
4. Foregrounds the retained Home tab across a real midnight and a time-zone change and confirms its date, greeting, focus, posts, and tasks all move together.
5. Replays VoiceOver and actual Reduce Motion at accessibility XXL, including the header order, badge announcement, card labels, Customize controls, and static Cy mark.

## Performance and smoothness

Classification: **one resolved measured work defect plus an open performance risk**.

- The resolved defect was deterministic: under Reduce Motion, `CyAnimatedLogo` scheduled a 30-fps `TimelineView` while drawing the same static frame. The static branch removes that work.
- Home is now 2,503 lines and owns 12 whole-table root `@Query` collections. Static inspection found 20 output-filter or output-to-brief lookup sites across its daily, weekly, eight-week, and optional-card projections. Several projections repeatedly scan outputs and use a linear `briefs.first` lookup.
- A normal-motion DEBUG simulator process with all six retained shell roots mounted used about **228 MB resident memory** and roughly **4.5% host CPU** while idle. This is not a Release-device result and cannot be attributed to Home alone, so it is recorded only as a risk trigger.
- `PERF-RISK-09` requires Release profiling with production-sized workspaces before splitting card/query owners or replacing repeated lookup with a duplicate-safe per-pass brief index. A large owner alone is not evidence that a broad refactor will improve smoothness.

## Resolved defects and remaining coverage

1. `DEFECT-MAIN-01-01` — **Resolved**: archived linked tasks no longer appear in Today’s Tasks.
2. `DEFECT-MAIN-01-02` — **Resolved**: archived briefs no longer project into Recently Posted.
3. `DEFECT-MAIN-01-03` — **Resolved**: the retained Home clock refreshes on foreground and significant time changes.
4. `DEFECT-MAIN-01-04` — **Resolved**: Home no longer owns presentation state outside the shell.
5. `DEFECT-MAIN-01-05` — **Resolved**: Reduce Motion no longer keeps the static Cy mark on a 30-fps timeline.
6. `DEFECT-MAIN-01-06` — **Resolved**: accessibility-scaled unread badges stay within the header control.
7. `PERF-RISK-09` — **Open**: root query ownership and repeated derived scans need Release-device profiling.
8. `GAP-MAIN-01-01` — **Open**: unlocked tap, VoiceOver, real Reduce Motion, read transition, route competition, and midnight/time-zone lifecycle replay remains required.

## Classification and next gate

PAGE-MAIN-01 is closed as `Coverage gap`. All known source-level defects are repaired, its principal visual states were replayed, its focused and full automated checks are green, and both platform targets build. Reclassify it only after the five unlocked lifecycle and input checks above are recorded.
