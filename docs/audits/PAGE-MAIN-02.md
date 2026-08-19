# PAGE-MAIN-02 Audit: Plan

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Scope owner: [`PlanView`](../../ios/AgentCy/Views/Plan/PlanView.swift), embedded planning surface in [`AgendaView`](../../ios/AgentCy/Views/Agenda/AgendaView.swift), and shared creator identity in [`CreatorAvatar`](../../ios/AgentCy/Views/Shared/CreatorAvatar.swift)
- Parent programs: [`AUD-05`](../APP_AUDIT_QUEUE.md#aud-05-planning-tasks-calendar-reminders-widgets) and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

Plan is the active workspace's date-based content-planning root. It owns the selected week, search, Feed shortcut, Settings entrance, and Week/Calendar/List display modes. It may place a work occurrence from a brief's explicit work date and a post occurrence from an output's explicit target date. A creator task date must never place content on Plan or be presented as a publishing time. Post cards show the output target time only. Work cards show a time only when the brief explicitly says its work date includes one. The selected weekday remains stable when the retained page crosses a week boundary.

| Event or state | Expected behavior |
| --- | --- |
| Current or offset week | Derive the Monday-based week from one injected reference instant and preserve the selected weekday when the week rebases. |
| Midnight, time-zone, or calendar change | Refresh the retained Plan clock on foreground and significant-time notification. |
| No dated content | Show an honest empty day/week/list state without promoting an undated draft or task date. |
| Work occurrence | Use only the brief work date and its explicit includes-time flag. |
| Post occurrence | Use only the output target date/time; never substitute a linked or unrelated task date. |
| Duplicate synced metadata | Build duplicate-safe indexes without `Dictionary(uniqueKeysWithValues:)` traps. |
| Week, Calendar, and List | Use one render snapshot per body pass and route their visible records to the canonical day, post, episode, reschedule, or capture destination. |
| Accessibility | At accessibility text sizes, remove the cramped seven-chip weekday strip, show a simple week-range navigator, stack completed-day rows and List filters, keep fixed calendar/avatar controls bounded, and retain full accessibility labels. |
| Reduce Motion | Change week, month, and selection state without animated transitions. |

## Function and exit trace

| Plan area | Source data | Canonical exit |
| --- | --- | --- |
| Header | active profile/workspace and the retained reference clock | search, Feed, or Settings |
| Week navigator | selected week offset and selected day | previous/next week or Today |
| Week mode | work/post occurrences for seven dates | day view, post detail/editor, episode action, reschedule, or quick capture |
| Calendar mode | month grid and occurrence summary | previous/next month or selected day |
| List mode | one snapshot projected through pillar/status filters | post detail/editor, episode action, or reschedule |
| External requests | requested week/day, late work, and widget day/brief state | requested date or canonical brief/output destination |

## Repair verification

| Confirmed cause | Repair and evidence |
| --- | --- |
| Week calculations and greeting read the wall clock from multiple places, so a retained Plan root could stay on yesterday or the prior week. | `PlanClockPolicy` now owns deterministic Monday week starts, relative offsets, greetings, and selected-weekday rebasing. `PlanView` owns one `planNow` and refreshes it on appearance, active scene entry, and significant time changes. |
| Agenda day, month, overdue, and list partitioning used scattered `Date()` calls. | `PlanView` passes its reference instant into `AgendaView` and `DayAgendaView`; their date-based projections now derive from that source. |
| Post cards could use a task date as the visible time, coupling production work to publishing placement. | `AgendaCardTimePolicy` permits post time only from the output target and work time only from an explicitly timed brief work date. The root task query and task-by-day grouping used for card-time fallback were removed. |
| List mode repeatedly rebuilt the full render snapshot and used a trap-prone unique-key dictionary for briefs. | The body creates one snapshot and one `AgendaListProjection`; `AgendaBriefIndexPolicy` now uses the shared first-value duplicate-safe index. |
| Calendar/week state changes animated even with Reduce Motion enabled. | `AgendaMotionPolicy` disables week, month, selection, and filter animations when the environment requests reduced motion. |
| The seven weekday chips, completed-day rows, List filters, and creator avatar became cramped or truncated at accessibility sizes. | Accessibility sizes now use a week-range navigator instead of weekday chips, stack completed-day rows and List filters, and cap only the visual type inside fixed calendar/avatar controls. Full semantic labels remain available. |

The user explicitly approved removing weekday chips for accessibility. The normal-size Week surface keeps them; accessibility categories use the range navigator.

## Automated evidence

- **8 PAGE-MAIN-02 regressions passed**: week rollover, relative week offsets, selected-weekday rebasing, truthful post time, truthful work time, duplicate-safe indexing, reduced-motion animation policy, and compact-control/accessibility layout policies.
- The full shared iOS suite passed **589 tests with 0 failures** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data.
- The `AgentCy Desktop` Catalyst target compiled successfully with the shared Plan and Agenda changes.
- `pnpm typecheck`, all **140 TypeScript tests**, and `pnpm build` passed in the same working tree.
- `git diff --check` passed for the PAGE-MAIN-02 source, test, contract, queue, and audit files.

## Runtime evidence

One disposable iPhone 17 Pro / iOS 26.5 simulator used in-memory preview data and explicit Week/Calendar/List fixtures. The audit visually inspected:

1. Normal light Week, Calendar, and List modes, including one scheduled post with its output-target time.
2. Normal dark Week mode for surface and text contrast.
3. Week at Accessibility Extra Extra Extra Large before and after repair; the repaired state removed weekday chips, bounded the avatar, and kept completed rows readable.
4. List at Accessibility Extra Extra Extra Large before and after repair; the repaired Pillar and Status filters stack at full width without truncating “Open posts.”
5. Calendar at Accessibility Extra Extra Extra Large; the fixed month grid remains bounded while the surrounding header scales and scrolls.

The initial Calendar relaunch used the wrong tab raw value and opened Home. Relaunching with the canonical `today` raw value opened Plan; this was fixture setup error, not production behavior.

## Remaining runtime coverage gap

The Mac remained locked after the user stepped away, so the audit did not bypass the session to drive live taps or VoiceOver. Before reclassifying this page as `Verified`, record one unlocked pass that:

1. Taps Week/Calendar/List, previous/next/Today, a day, a post, search, Feed, Settings, both List filters, reschedule, and return navigation.
2. Replays VoiceOver order and labels plus actual Reduce Motion across all three display modes.
3. Foregrounds the retained page across a real midnight, time-zone change, and week rollover.
4. Delivers weekly-agenda, open-post, late-work, widget-day, and widget-brief requests while another presentation is active.
5. Scrolls Calendar and List at Accessibility Extra Extra Extra Large to prove all content can clear the persistent bottom navigation.

## Open deeper contract clause

Production tasks are intentionally no longer used as hidden time fallbacks. Whether Plan should also render those tasks as explicit, visually separate task rows is not yet frozen at this wrapper level. That clause is deferred to `PAGE-PLAN-01`; until it is resolved, this audit does not claim that the Week surface is a complete task planner.

The Fable second opinion independently favored this separation: post cards should show only publishing time, while any task rows belong to the deeper planning-page contract. Fable was advisory and made no edits.

## Performance and smoothness

Classification: **two resolved deterministic work risks plus one open profiling risk**.

- List mode previously called the full render-snapshot builder repeatedly through separate computed properties. It now computes one snapshot and one list projection per body pass.
- The root Agenda owner previously queried and grouped all tasks solely to derive a fallback time for post cards. Removing that incorrect coupling also removes a whole-table query and grouping pass.
- `AgendaView.swift` is 3,756 lines and its root still owns 12 whole-table `@Query` collections. Static inspection found remaining linear lookups and derived filtering across week, month, and list projections. This is a risk signal, not proof of a hitch.
- `PERF-RISK-10` requires Release-device profiling with production-sized workspaces before splitting owners or adding more indexes. Measure body invalidations, SwiftData fetches, snapshot/projection time, scrolling, retained-tab background work, and memory in all three modes.

## Resolved defects and remaining coverage

1. `DEFECT-MAIN-02-01` — **Resolved**: retained Plan date/week state now refreshes deterministically.
2. `DEFECT-MAIN-02-02` — **Resolved**: task dates no longer masquerade as post times or place content.
3. `DEFECT-MAIN-02-03` — **Resolved**: duplicate brief IDs no longer risk a unique-key dictionary trap.
4. `DEFECT-MAIN-02-04` — **Resolved**: List mode no longer rebuilds its full snapshot multiple times per body pass.
5. `DEFECT-MAIN-02-05` — **Resolved**: Plan transitions honor Reduce Motion.
6. `DEFECT-MAIN-02-06` — **Resolved**: accessibility Week/List controls no longer truncate or overflow; weekday chips are removed at accessibility sizes.
7. `PERF-RISK-10` — **Open**: root query ownership and remaining derived scans need Release-device profiling.
8. `GAP-MAIN-02-01` — **Open**: unlocked tap, VoiceOver, actual Reduce Motion, lifecycle, external-route, and bottom-clearance replay remains required.
9. `GAP-PLAN-01-01` — **Open**: explicit production task-row behavior must be resolved under the deeper planning-page contract.

## Classification and next gate

PAGE-MAIN-02 is closed as `Coverage gap`. All confirmed source-level defects are repaired, Week/Calendar/List and their accessibility states were visually replayed, 589 iOS tests and 140 TypeScript tests pass, and both platform targets build. Reclassify it only after the unlocked five-part runtime pass and the explicit task-row clause are recorded.
