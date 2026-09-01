# PAGE-TASK-02 · Post task creation · Audit record

Audited 2026-08-21 against the current working tree. Scheduled-post
eligibility, current-week and search projections, workspace changes, selected
post context, title/notes, priority, due date, recurrence, subtasks, save
failure, dismissal, and post-lifecycle isolation were traced separately.

## Contract under test

Post Task Creation lets a creator choose one real scheduled post in the active
workspace and add one independent task, optionally with subtasks. The default
chooser shows the current Monday week; search can find another scheduled post.
Saving is atomic, honors an explicit task due date or no due date, and never
changes the post's placement, scheduled date, or lifecycle.

## Evidence

| Check | Result |
| --- | --- |
| Chooser is workspace-scoped, excludes archived/missing-date records, defaults to this week, and searches beyond it | Pass (new focused regression) |
| Parent plus normalized/completed subtasks save as one transaction | Pass (new focused regression) |
| Explicit task “No due date” remains nil without changing the post date | Pass (new focused regression) |
| A stale selection from another workspace is rejected without a partial task | Pass (new focused regression) |
| Explicit chooser and selected-composer simulator routes are isolated | Pass (focused fixture regression) |
| PAGE-TASK-02, PAGE-TASK-01, PAGE-MAIN-03, PAGE-ROOT-06, and domain regressions | 225 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass; two pre-existing warnings remain outside this page |
| Phone scheduled-post chooser | Pass: heading, guidance, search, count, post title, pillar, platform, date, close, and route render in [`post-task-chooser.png`](evidence/PAGE-TASK-02/post-task-chooser.png) |
| Phone selected composer | Pass: title, post context, priority, due date, repeat, notes, subtasks, and save state render in [`post-task-composer.png`](evidence/PAGE-TASK-02/post-task-composer.png) |

## Findings

1. `ATOMIC-TASK-02-01` — **Fixed**: the parent task was saved and calendar
   sync was queued before subtasks were created. Each subtask then saved
   independently while failures were skipped, so an error could leave a parent
   or partial checklist. One linked-task operation now validates first, stages
   the parent and all nonblank subtasks, saves once, rolls back on failure, and
   queues calendar sync only after success.
2. `DATE-TASK-02-01` — **Fixed**: choosing “No due date” passed nil through the
   general task creator, whose linked-post policy silently inherited the post
   date. The dedicated operation now treats the composer value as authoritative:
   nil stays nil, while the scheduled post date remains unchanged.
3. `SCOPE-TASK-02-01` — **Fixed**: a workspace switch could leave the sheet
   holding its prior selection, then save a task into the new workspace with
   old-workspace brief/output IDs. Save now fetches and revalidates the exact
   records against the active workspace immediately before inserting anything.
4. `ELIGIBILITY-TASK-02-01` — **Fixed**: search could expose a malformed
   scheduled output with no scheduled date. Eligibility now requires an active,
   nonarchived linked brief, scheduled output, real target date, and matching
   active-workspace scope. Empty search remains current-week only; nonempty
   search reaches other dates.
5. `PERF-TASK-02-01` — **Improved structurally, profiling still open**: the
   chooser previously repeated full brief/output/pillar scans and workspace
   resolution through several computed properties and row lookups. One
   projection now resolves scope once, builds duplicate-safe indexes, filters
   and sorts once per body pass, and feeds stable candidate rows. The sheet
   still owns four whole-table observers, so production-sized Release profiling
   remains under `PERF-RISK-11`.
6. `LIFECYCLE-TASK-02-01` — **Preserved**: creating a task does not mutate the
   linked brief, output status, or output target date. Stale, archived, moved,
   unscheduled, or malformed selections fail closed with creator-facing notice.
7. `GAP-TASK-02-01` — **Open**: driven typing/search/selection/save, injected
   persistence failure, a live workspace switch while the composer is open,
   expired access, keyboard traversal, VoiceOver, confirmed accessibility text
   sizes, actual Reduce Motion, Catalyst runtime interaction, and Release-device
   measurement with production-sized workspaces remain.

## Performance and smoothness

Debug phone replay showed no visible stall while presenting either chooser or
composer, and this page performs no synchronous file, media, or network work.
The material static risk was repeated collection work: several full scans and
linear lookups were triggered from one render. That work is now one indexed
projection, but all four backing tables are still broadly observed. A Release
device should measure presentation, search typing, row invalidations, scrolling,
selection push, save/dismiss latency, SwiftData fetches, calendar-sync follow-up,
and memory with small, medium, and production-sized stores before query owners
are split further.

## Classification and next gate

PAGE-TASK-02 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-TASK-03 (Due-date editors), beginning with contract validation
while preserving the one-page-at-a-time boundary.
