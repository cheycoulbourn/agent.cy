# PAGE-CAP-09 · Filming schedule · Audit record

Audited 2026-08-21 after PAGE-CAP-08 against the current working tree. The
sheet presentation, date and time form, source/brief ownership boundary,
filming-task idempotency, failure path, completion path, and post-save sync
work were traced separately.

## Contract under test

Schedule filming as creator-owned work derived from one linked brief. The
saved inspiration remains a reference. Only a source and brief from the same
workspace can schedule one filming task. Repeated saves update that task;
stale links do not rewrite unrelated work. A failed save keeps the sheet open,
and a successful save dismisses it after updating the brief and task.

## Evidence

| Check | Result |
| --- | --- |
| The sheet opens with a concrete source/brief pair and cannot render an empty modal | Pass (item-bound SwiftUI presentation + static trace) |
| A foreign or missing linked brief cannot open or mutate the filming schedule | Pass (view scope + new coordinator regression) |
| The date always has a chosen value; a saved date is reused and a new schedule defaults to tomorrow | Pass (state initialization + static trace) |
| The optional time changes both the brief and filming task timing flag | Pass (focused regression) |
| Repeated scheduling updates exactly one filming task | Pass (focused regression) |
| A stale filming-task link leaves unrelated work unchanged and creates the correct task | Pass (new focused regression) |
| Save failure keeps the sheet presented; success dismisses and reports completion | Pass structurally; driven failure replay remains |
| Inspiration shaping suite | Pass (13 tests, 0 failures, iOS 26.5 simulator) |
| App scheme, embedded extensions, and diff whitespace check | Pass |

## Findings

1. `DEF-CAP-09-01` — **Confirmed fixed**: the scheduler verified the mutual
   source/brief IDs but not their workspaces. A malformed cross-workspace link
   could create or update work under the wrong creator workspace. The view now
   refuses to resolve that brief, and the persistence boundary independently
   rejects it before mutation.
2. `DEF-CAP-09-02` — **Confirmed fixed**: `source.filmingTaskID` was trusted
   without confirming the task belonged to the linked brief or was a filming
   task. A stale ID could therefore rewrite an unrelated task's title, date,
   kind, and lane. Eligible reuse is now restricted to filming tasks for this
   brief and workspace; the stale task remains untouched.
3. `STATE-CAP-09-01` — **Confirmed fixed**: boolean sheet presentation used
   conditional content, so a live-data change could leave an empty modal. The
   sheet is now driven by one concrete, identifiable source/brief selection.
4. `PERF-CAP-09-01` — **Partially fixed risk**: scheduling previously fetched
   the entire task table to find one filming task. The fetch is now restricted
   to the selected brief before the workspace/kind check.
5. `PERF-CAP-09-02` — **Open risk**: the Add to schedule action still performs
   several synchronous main-actor rebuilds after persistence. Widget snapshot
   refresh reads many whole tables, EventKit reconciliation reads briefs,
   outputs, and tasks and can rewrite events, and a connected desktop bridge
   builds and writes a full workspace snapshot. This is a credible contributor
   to save stalls as the library grows, but needs Release-device signposts and
   a cross-service incremental/background design before refactoring.
6. `GAP-CAP-09-01` — **Open**: a seeded schedule-sheet fixture and driven save
   failure are missing. VoiceOver, Dynamic Type, keyboard/focus behavior,
   Catalyst, EventKit-connected, bridge-connected, and Release-device latency
   replays remain.

## Classification and next gate

PAGE-CAP-09 closes as `Confirmed defect (fixed)` + `Coverage gap`. Workspace
ownership, task identity, retry idempotency, date/time persistence, and modal
presentation are pinned. The named driven, accessibility, integration, and
Release-performance evidence remains. Next page: PAGE-CAP-10 (Develop brief).
