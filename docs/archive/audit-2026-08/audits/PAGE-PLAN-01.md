# PAGE-PLAN-01 · Agenda engine · Audit record

Audited 2026-08-21 against the current working tree. Week, Calendar, and List
projections; post/task date ownership; archived-work visibility; task exits;
month color placement; query ownership; render-time grouping; and preview
fixtures were traced separately.

## Contract under test

Agenda projects publishing placements and production work without collapsing
their meanings. A post is placed only by its output target date. A production
task is placed only by its own target or daily-focus date, is shown separately
from posts, and opens the canonical task route. Month dates remain visually
clean; weekday headers alone carry repeating pillar color.

## Evidence

| Check | Result |
| --- | --- |
| Top-level task projection uses only task-owned dates | Pass (new focused regression) |
| Undated task does not inherit a linked post target | Pass (new focused regression) |
| Task linked only to archived work is hidden | Pass (new focused regression) |
| Existing occurrence, clock, duplicate-index, accessibility, motion, and month-color policies | Pass |
| PAGE-MAIN-02 / PAGE-PLAN-01 focused suite | 12 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass |
| `AgentCy Desktop` Mac Catalyst build | Pass; existing frame-extraction deprecation warning is outside this page |
| Week preview | Pass: selected day exposes a separate `Production tasks` section with one task |
| Calendar preview | Pass: colored weekday circles, clean month dates, and `0 posts · 1 task` selected-day summary |

## Findings

1. `DEFECT-PLAN-01-01` — **Fixed**: the root Agenda had no production-task
   projection or task exit even though the product contract requires posts and
   production tasks to be planned separately. Week and selected-day Calendar
   surfaces now render top-level, non-skipped, dated tasks in a separate section
   using the canonical `TaskRow` route.
2. `TRUTH-PLAN-01-01` — **Pass**: task placement uses
   `TaskRootDatePolicy.taskOwnedDate`. It never falls back to an output target,
   and post placement continues to use output-owned dates only.
3. `VIS-PLAN-01-01` — **Pass**: standalone tasks remain visible; tasks whose
   only linked brief is archived do not leak into Agenda. Past days with a task
   no longer collapse into a completed summary that hides the task exit.
4. `COLOR-PLAN-01-01` — **Pass**: Calendar keeps pillar color only in weekday
   header circles. Month dates show post counts without pillar color, while
   task counts remain in the day accessibility label and selected-day summary.
5. `PERF-PLAN-01-01` — **Improved, profiling still open**: root query ownership
   fell from 12 whole-table queries to 11 despite adding the truthful task
   query, because unused profile and social-account queries were removed.
   Workspace scoping, indexes, episode grouping, and task grouping now occur
   once in the render snapshot instead of being repeated for each of seven week
   rows or post cards.
6. `GAP-PLAN-01-01` — **Open**: List is intentionally post-only because its
   filters describe post status and pillar. Release-device profiling with a
   production-sized workspace, interactive task/post/day/reschedule taps,
   VoiceOver, accessibility text sizes, Reduce Motion, and Catalyst runtime
   replay remain before this page can be called fully verified.

## Performance and smoothness

Static review found a real source of unnecessary work: the 3,960-line shared
file repeatedly rescoped full collections and linearly searched pillar,
destination, format, series, focus, and episode data while constructing rows.
The root now builds duplicate-safe indexes and day groups once per render pass.
That reduces deterministic CPU work but does not prove the phone hitch is gone.
The root still observes 11 whole-table SwiftData queries, so the next performance
gate is a Release-device trace measuring fetches, body invalidations, snapshot
time, scroll frame cadence, retained-tab work, memory, and save-driven refreshes.

## Classification and next gate

PAGE-PLAN-01 closes as `Confirmed defect (fixed)` + `Coverage gap`. The missing
production-task behavior is repaired and regression-pinned; the calendar color
contract remains clean. Next page: PAGE-PLAN-02 (Day agenda).
