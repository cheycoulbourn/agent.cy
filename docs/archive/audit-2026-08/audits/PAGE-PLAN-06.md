# PAGE-PLAN-06 · Weekly focus setup · Audit record

Audited 2026-08-21 against the current working tree. Empty/rest setup,
configured focus tasks, midweek edits, duplicate weekday records, save failure
boundaries, recurrence materialization, query work, and phone/desktop compilation
were traced separately.

## Contract under test

Weekly focus setup saves one canonical focus/rest choice for every weekday and
materializes recurring My Tasks only from the current day forward. A save must
not create already-overdue work, let an older duplicate override a newer
choice, or commit focus templates when task reconciliation fails. The sheet
dismisses only after the complete save succeeds.

## Evidence

| Check | Result |
| --- | --- |
| Midweek save never backfills generated tasks into earlier days | Pass (new focused regression plus corrected legacy regression) |
| Duplicate weekday records resolve newest-first in either input order | Pass (new focused regression) |
| A newer Rest record overrides an older active duplicate | Pass (new focused regression) |
| Every weekday, including Rest, persists through the combined save | Pass (existing regression) |
| Configured focus templates materialize recurring My Tasks | Pass (existing regression) |
| PAGE-PLAN-06 plus the complete weekly-focus suite | 22 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| PAGE-MAIN-02 through PAGE-PLAN-06 plus the weekly-focus suite | 52 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the focused test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Empty/rest phone state | Pass: all seven days, neutral day-letter circles, navigation, copy, and close affordance render cleanly in [`weekly-focus-setup.png`](evidence/PAGE-PLAN-06/weekly-focus-setup.png) |

## Findings

1. `OVERDUE-PLAN-06-01` — **Fixed**: recurrence reconciliation rewound every
   save to Monday of the current week. Editing on Thursday could immediately
   create Monday through Wednesday tasks as overdue work. The rolling horizon
   now begins on the requested day while retaining a week-aligned end date.
2. `ATOMIC-PLAN-06-01` — **Fixed**: `saveWeeklyFocus` persisted seven template
   mutations before recurring-task reconciliation. A reconciliation failure
   could therefore leave the saved focus changed while the sheet stayed open
   and reported failure. Templates and generated tasks now share one save
   boundary; failure rolls the context back and dismissal remains success-only.
3. `DUPLICATE-PLAN-06-01` — **Fixed deterministically**: setup loading, saving,
   recurrence, and downstream focus resolution all used unsorted `first`
   selection for duplicate weekday records. They now share one canonical index
   that prefers the newest update, then creation date, then a stable UUID tie.
   A newer inactive Rest choice therefore cannot be revived by an older active
   record. Duplicate physical records are preserved rather than destructively
   merged during this page repair.
4. `PERF-PLAN-06-01` — **Improved deterministically, profiling still open**:
   recurrence formerly fetched the entire task table and repeatedly scanned
   templates for every day in its horizon. It now predicate-fetches only
   top-level focus-generated tasks and indexes the seven weekday templates once.
5. `COLOR-PLAN-06-01` — **Confirmed**: setup uses neutral day-letter circles
   and no colored weekday chips. This page does not reintroduce calendar date
   colors.
6. `GAP-PLAN-06-01` — **Open**: injected persistence failure, driven focus/task
   editing, configured and edited runtime screenshots, VoiceOver, accessibility
   text sizes, Catalyst runtime interaction, and production-sized Release save
   traces remain.

## Performance and smoothness

The seven-day form itself is bounded, but it still observes whole template and
workspace collections and save currently fetches workspace/template data in
both the model and recurrence service. The high-risk full-task-table read and
per-day template scans are removed. Release-device profiling should measure
sheet-open invalidations, weekday navigation, task-field typing, save latency,
SwiftData invalidations after the combined commit, widget refresh, and calendar
sync with small, medium, and large workspaces before considering broader query
or ownership refactors.

## Classification and next gate

PAGE-PLAN-06 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-07 (Daily focus detail).
