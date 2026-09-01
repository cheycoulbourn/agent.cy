# PAGE-TASK-01 · Task detail · Audit record

Audited 2026-08-21 against the current working tree. Standalone, linked,
top-level/subtask, recurring, completed, overdue-action, missing-route,
duplicate, delete, save/back, workspace, and query-work paths were traced
separately.

## Contract under test

Task Detail edits one reachable top-level task and its independent subtasks.
Buffered title and notes, setup fields, completion, overdue actions, and direct
subtask edits persist once. A linked post remains reachable. Duplication stays
inside the task's workspace without cloning completion or recurrence. Deleting
a parent also deletes its subtasks, dismisses only after a successful save, and
never writes the deleted object again while the page disappears.

## Evidence

| Check | Result |
| --- | --- |
| Duplicate preserves workspace, partner, links, editable fields, and non-recurring safety | Pass (new focused regression) |
| Explicit save/delete exits bypass disappearance autosave | Pass (new focused regression) |
| Pillar choices exclude archived and other-workspace pillars | Pass (new focused regression) |
| Parent deletion reports success and removes its subtasks | Pass (new focused regression) |
| Explicit Task Detail replay requires its own launch argument and selects a top-level task | Pass (two new focused regressions) |
| PAGE-TASK-01, PAGE-MAIN-03, PAGE-ROOT-06, linked-post, and task domain regressions | 237 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Phone Task Detail | Pass: top-level title, setup fields, notes, linked-post section, subtask section, save, back, and options render in [`task-detail-parent.png`](evidence/PAGE-TASK-01/task-detail-parent.png) |

## Findings

1. `SCOPE-TASK-01-01` — **Fixed**: Duplicate created an unowned task because it
   never copied `workspaceID`. In a non-default workspace the copy could vanish
   from the current task list or appear in the default workspace. Duplication
   now preserves workspace, partner, post/pillar links, estimate, date, and
   authored text while deliberately creating an open, non-recurring top-level
   copy.
2. `SCOPE-TASK-01-02` — **Fixed**: the Pillar menu filtered only archived state,
   so it could offer and assign another workspace's pillar. Choices now use the
   same legacy-aware workspace rule as the task route.
3. `SAVE-TASK-01-01` — **Fixed**: Save committed and synced, dismissed, then
   `onDisappear` committed, saved, and queued calendar sync again. Successful
   explicit exits now carry a terminal state, so only an implicit Back exit
   performs disappearance persistence.
4. `DELETE-TASK-01-01` — **Fixed**: deletion swallowed persistence failure and
   dismissed regardless; disappearance then accessed and saved the deleted
   task again. Deletion now returns success/failure, rolls back and stays open
   on failure, and marks a successful delete so disappearance is inert.
5. `ACTION-TASK-01-01` — **Fixed at the page boundary**: overdue Complete, Move
   today, and Skip previously dismissed even if their save failed and then ran
   the second disappearance save. These actions now return persistence success,
   roll back where needed, and dismiss only after the single successful commit.
6. `PERF-TASK-01-01` — **Improved structurally, profiling still open**: route
   resolution no longer observes every task; subtasks use a parent predicate;
   exact/legacy linked outputs and the linked brief use bounded child queries.
   The detail page therefore no longer linearly scans the complete task, output,
   and brief tables on unrelated changes. Pillar and workspace menus remain two
   whole-table observers, and the Tasks root remains under `PERF-RISK-11`.
7. `LINK-TASK-01-01` — **Preserved**: exact output linkage still wins. Legacy
   brief-only tasks still choose the existing canonical finalized/draft output
   policy, and missing linked records leave the rest of Task Detail usable.
8. `FIXTURE-TASK-01-01` — **Fixed**: the explicit runtime route selected the
   first stored task, which could be a subtask and did not cover this page's
   parent contract. It now deterministically selects the first top-level task.
9. `DECISION-TASK-01-01` — **Open product decision**: Duplicate currently does
   not clone subtasks. Copying an entire checklist versus creating one clean
   parent task needs a creator-facing product decision rather than audit
   inference.
10. `GAP-TASK-01-01` — **Open**: driven editing through every control, injected
    save/delete failure, wrong-workspace and stale-route runtime states,
    recurrence generation after completion, VoiceOver, confirmed accessibility
    text-size environment, actual Reduce Motion, Catalyst runtime interaction,
    and production-sized Release traces remain.

## Performance and smoothness

The phone Debug replay showed no visible stall while presenting the top-level
detail. Static work is materially smaller: one routed task, only that parent's
subtasks, a bounded linked-output query, and one linked brief are observed.
There is no synchronous file, media, or network work on this page. Persistence
still queues calendar synchronization after a successful edit, and two menu
collections remain broad, so Release-device profiling must measure first
presentation, typing, menu opening, save/dismiss latency, toggle invalidation,
long-subtask scrolling, calendar-sync follow-up, and memory at realistic sizes.

## Classification and next gate

PAGE-TASK-01 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-TASK-02 (Post task creation), beginning with contract validation
while preserving the one-page-at-a-time boundary.
