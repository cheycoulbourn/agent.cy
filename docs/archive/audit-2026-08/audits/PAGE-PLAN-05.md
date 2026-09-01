# PAGE-PLAN-05 · Post reschedule · Audit record

Audited 2026-08-21 against the current working tree. Existing and missed dates,
date-only/time semantics, multi-output parent placement, linked tasks, clearing,
missing records, persistence failure, dismissal, query work, and phone/desktop
compilation were traced separately.

## Contract under test

Post reschedule changes only the selected output's scheduled target, keeps its
open linked tasks aligned, and recalculates the parent from all remaining
outputs. Saving or clearing dismisses only after persistence succeeds. A
date-only choice remains date-only; clearing removes only this output's target
and recurrence while preserving other scheduled outputs.

## Evidence

| Check | Result |
| --- | --- |
| Moving one of several outputs recalculates the parent's earliest target | Pass (new focused regression) |
| Date-only save normalizes safely and aligns the open linked task | Pass (new focused regression) |
| Missing post rejects the write without applying the requested time | Pass (new focused regression) |
| Clearing one output preserves the other output and parent schedule | Pass (new focused regression) |
| Explicit reschedule preview route requires its own argument | Pass (new focused regression) |
| PAGE-MAIN-02 through PAGE-PLAN-05 plus related lifecycle suite | 35 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through focused test build |
| `AgentCy Desktop` Mac Catalyst build | Pass; existing frame-extraction deprecation warning is outside this page |
| Reschedule sheet phone state | Pass: copy, calendar, time toggle, save, close, and scrollable clear action render |

## Findings

1. `PARENT-PLAN-05-01` — **Fixed**: when the selected output owned the parent
   brief's earliest target, moving it later assigned that later date directly
   to the parent. Another output could still be scheduled earlier, leaving the
   parent and agenda wrong. The parent target is now recomputed from every
   linked output after the selected output changes.
2. `FAIL-PLAN-05-01` — **Fixed**: the sheet changed the output's time flag,
   called a write path that swallowed save errors, and dismissed regardless of
   permission, missing records, lifecycle rejection, or persistence failure.
   Reschedule now returns a real success result, rolls back and reports failure,
   queues calendar sync only after save, and the sheet remains open unless the
   operation succeeds.
3. `CLEAR-PLAN-05-01` — **Fixed**: the required clear state existed in the
   model but the reschedule sheet offered no clear action. Phone and desktop now
   expose `Clear scheduled date`; it dismisses only after the selected output is
   cleared successfully.
4. `TRUTH-PLAN-05-01` — **Fixed**: the subtitle claimed moving a post would not
   affect the rest of the week, although open linked tasks intentionally move
   with it. The sheet now states that behavior directly and labels the field as
   a scheduled date rather than a task due date.
5. `TIME-PLAN-05-01` — **Pinned**: the sheet normalizes a date-only selection to
   the app's safe internal day anchor and persists `includesTargetTime = false`.
   Explicit times remain unchanged. Existing non-sheet callers retain their
   exact date semantics.
6. `PERF-PLAN-05-01` — **Improved deterministically, profiling still open**:
   reschedule formerly fetched every task in the store and fetched the same
   output collection twice during one save. It now predicate-fetches only tasks
   linked to the selected output/brief and reuses one linked-output fetch for
   lifecycle synchronization and parent-date calculation.
7. `GAP-PLAN-05-01` — **Open**: interactive date/time edits, driven Save/Clear,
   injected persistence failure, VoiceOver, accessibility text sizes, Catalyst
   runtime interaction, and production-sized Release save traces remain.

## Performance and smoothness

The sheet itself owns no SwiftData query and its calendar is bounded to one
visible month. The write path now avoids whole-task-table work and duplicate
linked-output fetches. A Release-device trace should still measure sheet-open
latency, calendar month navigation, date selection redraws, linked-task fetch
and update duration, context-save latency, agenda invalidations after dismissal,
and calendar-sync scheduling with production-sized stores.

## Classification and next gate

PAGE-PLAN-05 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-06 (Weekly focus setup).
