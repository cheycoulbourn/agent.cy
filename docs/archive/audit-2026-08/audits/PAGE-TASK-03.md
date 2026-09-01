# PAGE-TASK-03 · Due-date editors · Audit record

Audited 2026-08-24 against the current working tree. Creation-time and
persisted-task entry, cancel, set, change, clear, date-only, timed, recurring,
focus-template, linked-post, save-failure, calendar-sync, and layout paths were
traced separately.

## Contract under test

The due-date editors change only one task's date/time meaning. Date-only values
normalize to the selected calendar day; timed values retain the selected time.
Clearing a one-time task removes both its date and hidden time state. Repeating
tasks retain a usable date so their next occurrence can still materialize.
Focus-template occurrences stay on their assigned focus day and become
customized when their time changes. A task date never reschedules linked
content, and a failed save leaves the prior task value intact.

## Evidence

| Check | Result |
| --- | --- |
| Repeating task cannot lose the date required for its next occurrence | Pass (new focused regression) |
| Date-only and timed values normalize without changing recurrence | Pass (new focused regression) |
| Focus time change is locked to the focus day, marks customization, and restores on failure | Pass (new focused regression) |
| Removing a creation-time date also clears the hidden time flag | Pass (new focused regression) |
| Linked task date changes leave post date/status and brief lifecycle unchanged | Pass (new focused regression) |
| Both due-date editors require isolated runtime arguments | Pass (focused fixture regression) |
| PAGE-TASK-03, PAGE-TASK-02, PAGE-TASK-01, PAGE-MAIN-03, PAGE-ROOT-06, PAGE-CAP-02, Weekly Focus, and domain regressions | 256 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass; one pre-existing unused-result warning remains outside this page |
| Persisted-task date editor | Pass: date toggle, responsive calendar, time control, Cancel, and Set date render in [`due-date-editor.png`](evidence/PAGE-TASK-03/due-date-editor.png) |
| Creation-time date editor | Pass after calendar repair: guidance, responsive calendar, time control, removal, Cancel, and Set date render in [`capture-due-date-editor.png`](evidence/PAGE-TASK-03/capture-due-date-editor.png) |

## Findings

1. `RECURRENCE-TASK-03-01` — **Fixed**: the persisted editor allowed a
   repeating task's only due date to be cleared while leaving recurrence active.
   Completion then produced no next occurrence because recurrence materializing
   requires a target date. Repeating editors now initialize with a repairable
   date state, keep the date toggle on, explain the requirement, and reject an
   invalid clear again at the mutation boundary.
2. `STATE-TASK-03-01` — **Fixed**: “Remove due date” in the shared creation
   sheet cleared only `hasDueDate`; `includesTime` stayed true and silently
   returned the next time a date was added. Removal now clears both values as
   one state transition. The removal action is hidden for repeating drafts.
3. `SAVE-TASK-03-01` — **Fixed**: the persisted editor mutated the live task
   before `ModelContext.save()`, but save failure left those new values in
   memory. A later save elsewhere could persist a change the page had reported
   as failed. The date policy now snapshots date, time meaning, and focus
   customization, restores them on any persistence error, and queues calendar
   sync only after success.
4. `FOCUS-TASK-03-01` — **Fixed**: a focus-template occurrence could save a
   time change before `TaskDetailView` later marked it customized on exit. A
   recurrence reconciliation in that window could overwrite the creator's
   change. Date/time change and customization now persist atomically, while the
   focus calendar day remains locked.
5. `LAYOUT-TASK-03-01` — **Fixed**: the system graphical `DatePicker` in the
   creation sheet compressed and overlapped weekday labels in phone runtime at
   the simulator's current text size. It now uses the app's existing responsive
   `PillarCalendarDatePicker`, matching the persisted-task editor and rendering
   stable month navigation, weekday columns, and touch targets.
6. `LIFECYCLE-TASK-03-01` — **Preserved**: the mutation boundary accepts only a
   task. Linked output dates/statuses and brief lifecycle remain unchanged when
   the task date is set or cleared.
7. `PERF-TASK-03-01` — **No issue observed**: neither sheet owns SwiftData
   queries, media, files, networking, animation loops, or derived full-table
   scans. The calendar has a bounded month grid and local draft state. Debug
   phone presentation and scrolling showed no visible stall.
8. `GAP-TASK-03-01` — **Open**: driven taps through set/change/clear/time and
   repeating help text, an actual failing SwiftData store rather than the
   injected persistence closure, DST/time-zone transitions, VoiceOver,
   additional accessibility text sizes, pointer/keyboard Catalyst interaction,
   and Release-device latency measurement remain.

## Performance and smoothness

Both sheets keep date selection local until confirmation and perform one
bounded normalization plus one save. Replacing the compressed system graphical
picker also removes the observed layout instability without adding query or
media work. Release measurement should still sample presentation, month
navigation, time-toggle redraw, save/dismiss latency, calendar-sync follow-up,
and memory, but static tracing and Debug replay found no current heavy path.

## Classification and next gate

PAGE-TASK-03 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-WORK-01 (Idea draft), beginning with contract validation while
preserving the one-page-at-a-time boundary.
