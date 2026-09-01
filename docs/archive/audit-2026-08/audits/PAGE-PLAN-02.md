# PAGE-PLAN-02 · Day agenda · Audit record

Audited 2026-08-21 against the current working tree. Day-owned post and task
placement, archived-work visibility, focus and pillar controls, empty states,
past-day actions, save failures, canonical exits, query ownership, and phone
rendering were traced separately.

## Contract under test

Day agenda shows what belongs to one date without borrowing dates between
posts and tasks. Scheduled and in-production posts remain separate. A task is
shown only on its own due or focus date, and archived work never leaks through
an output-only link. Past days are reviewable but cannot manufacture new tasks.
All writes either succeed visibly or leave the page open with an error.

## Evidence

| Check | Result |
| --- | --- |
| Linked task stays on its task-owned date | Pass (new focused regression) |
| Output-only link to archived work is hidden | Pass (new focused regression) |
| Output metadata falls back to platform | Pass (new focused regression) |
| Overlapping anchor/branch weekday resolves deterministically to anchor | Pass (new focused regression) |
| Past-day task-creation policy | Pass (existing focused regression, now wired to both Day controls) |
| Explicit Day preview route requires its own launch argument | Pass (new focused regression) |
| PAGE-MAIN-02 / PAGE-PLAN-02 focused suite | 18 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass |
| `AgentCy Desktop` Mac Catalyst build | Pass; existing frame-extraction deprecation warning is outside this page |
| Empty Day phone replay and full vertical scroll | Pass |
| Focus, pillar picker, and Schedule post exits | Pass on iPhone 17 Pro / iOS 26.5 simulator |

## Findings

1. `DEFECT-PLAN-02-01` — **Fixed**: a task linked to a post was repeated on
   every day where that post appeared, even when the task's own target date was
   different. Day now delegates to the same task-owned date projection as Week
   and Calendar and separates focus tasks from post tasks afterward.
2. `VIS-PLAN-02-01` — **Fixed**: an output-only task link did not resolve the
   owning brief before archived-work filtering. Those tasks could leak into
   Day. The projection now resolves the output first and applies the active
   brief gate once.
3. `TRUTH-PLAN-02-01` — **Fixed**: post cards with no configured destination,
   format, or account rendered no platform metadata. They now fall back to the
   output's platform label.
4. `DEFECT-PLAN-02-02` — **Fixed**: overlapping anchor and branch weekday data
   was resolved with an unordered `first`, so identical launches could display
   a different Friday pillar without a user change. Resolution now prefers the
   anchor and uses stable creation/identity ordering for malformed ties.
5. `ACTION-PLAN-02-01` — **Fixed**: the existing product policy prohibited task
   creation on past days, but Day still rendered both Add task buttons. Both
   controls now follow the pinned policy; existing tasks and See all tasks stay
   available.
6. `FAIL-PLAN-02-01` — **Fixed**: post-task creation swallowed persistence
   failure, queued calendar sync, and dismissed as if the task had saved. It now
   rolls back, remains open, and reports a retryable error; sync and dismissal
   occur only after a successful save.
7. `BUILD-PLAN-02-01` — **Fixed**: the Catalyst-only Day header referenced the
   render snapshot outside its scope, so the desktop target did not compile.
   The body now passes its already-built snapshot into the desktop header.
8. `GAP-PLAN-02-01` — **Open**: mixed, complete, late, and missing-linked-record
   states are policy-traced but not all driven visually. VoiceOver, accessibility
   text sizes, Reduce Motion, Catalyst interaction replay, and injected save
   failure remain.

## Performance and smoothness

The Day page observes 12 whole-table SwiftData queries inside a shared 3,999-line
Agenda file. Before this pass, the toolbar change check rebuilt and rescanned
day outputs, tasks, focus, and pillar state separately from the body snapshot on
every invalidation. The render snapshot now owns the assigned pillar and one
stable day signature, and save/dismiss paths reuse or deliberately rebuild that
snapshot once.

This removes deterministic duplicate main-thread work but does not prove the
reported phone hitch is gone. Several action-time helpers still rescope the same
collections, and every observed table can invalidate this large view. The next
performance gate remains a Release-device trace with production-sized data,
measuring fetch count, snapshot duration, body invalidations, scroll frame
cadence, retained-tab work, and save-driven refreshes.

## Classification and next gate

PAGE-PLAN-02 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-03 (Post search).
