# PAGE-WORK-02 · Resumable post editor · Audit record

Audited 2026-08-24 against the current working tree. Draft, Ready, Scheduled,
and Posted lifecycles; one and many outputs; Idea Bank handoff; explicit and
implicit exits; invalid and failed saves; work/scheduled dates; tasks, media,
series, brand partners, export, and typing invalidation were traced separately.

## Contract under test

The Resumable Post Editor edits one post and its selected platform output without
silently changing another output's lifecycle or schedule. Title and long-form
fields remain local while typing. Save and Back commit valid changes once;
persistence failure keeps the creator in the editor and restores the last saved
version. Scheduling, marking Posted, opening Spark, duplication, copy/export,
media, series, and partner actions only continue after their required save
succeeds. The brief's agenda date is the earliest scheduled child output, and an
explicit Idea Draft handoff remains a post rather than returning to Idea Bank.

## Evidence

| Check | Result |
| --- | --- |
| Editing one output preserves its Scheduled lifecycle, a Ready sibling, and the earliest parent agenda date | Pass (new focused regression) |
| Failed and invalid main saves restore the committed brief, output, work date, target date, and linked task values | Pass (new focused regressions) |
| Explicit Save suppresses a second `onDisappear` persistence pass | Pass (new focused regression) |
| Title and reusable text fields keep keystrokes local until an explicit commit boundary | Pass (new focused regression) |
| Resume policy never downgrades Draft, Ready, Scheduled, or Posted output as a save side effect | Pass (new focused regression) |
| Idea Draft handoff uses Post placement atomically and restores its previous placement on failure | Pass (updated domain regression) |
| Failed recurring schedule reports failure and does not queue false calendar success | Pass through neighboring domain/service coverage and source trace |
| PAGE-WORK-01, PAGE-WORK-02, domain, output-detail, service, and root-routing regressions | 305 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Phone editor fixture | Render pass: explicit Back/Save, title, pillar, platform, format, Scheduled status, dates, duration, and media sections in [`post-editor.png`](evidence/PAGE-WORK-02/post-editor.png) |

## Findings

1. `SAVE-WORK-02-01` — **Fixed**: `persistChanges` discarded SwiftData save
   errors, so Save could close and Spark, schedule, Posted, duplicate, copy, or
   export could continue after a failed prerequisite. It now returns a truthful
   result, blocks downstream actions and dismissal, and restores an explicit
   last-committed snapshot because `ModelContext.rollback()` alone did not
   restore already-materialized property values in the reproduced test.
2. `LIFECYCLE-WORK-02-01` — **Fixed**: saving a developing brief recalculated
   its output status and could downgrade Ready or Scheduled work to Draft.
   Resuming and saving now preserve every child output's current lifecycle.
3. `CHILD-WORK-02-01` — **Fixed**: saving one output assigned the brief's
   agenda date from that output even when a sibling had an earlier target. The
   parent projection now uses the earliest scheduled child without rewriting
   sibling status or dates.
4. `EXIT-WORK-02-01` — **Fixed**: explicit Save was followed by a second save
   from `onDisappear`, and iPhone relied on an unowned native Back gesture that
   could not stop dismissal after failure. The editor now owns phone/desktop
   Back, and a successful explicit exit suppresses duplicate persistence.
5. `ROUTE-WORK-02-01` — **Fixed**: Idea Draft created an output without moving
   the brief to Post placement. PAGE-WORK-02's legacy `onAppear` repair could
   then move that intentional post back to Idea Bank and remove dates/tasks.
   The handoff is now atomic; the destructive entry repair is removed.
6. `SCHEDULE-WORK-02-01` — **Fixed**: recurring schedule failure returned
   success when the in-memory output already said Scheduled and queued calendar
   sync despite a failed store write. It now rolls back and returns failure.
7. `CHILD-SAVE-WORK-02-01` — **Fixed**: mood-board, collaboration-file,
   attachment, voice-title, brand-partner, series assignment/detail/status,
   future-slot removal, and archive paths contained swallowed or incomplete
   failure handling. They now report failure, roll back, restore materialized
   values where necessary, and avoid successful dismissal after failure.
8. `PERF-WORK-02-01` — **Bounded, not closed**: the editor is still a 5,300-line
   file whose root owns eleven live queries and many sheets. The highest-frequency
   typing path no longer writes SwiftData every 250 ms; title/text keystrokes are
   local until commit. Brief outputs, tasks, attachments, pillars, social
   accounts, series, and partners are predicate-scoped, and the series detail
   sheet now scopes its slot/brief/output observations. Catalog/profile/workspace
   observers and the large view owner remain for Release profiling.
9. `GAP-WORK-02-01` — **Open**: driven edits through every field, Back/Save,
   lifecycle, media, partner, series, task, and export action; real failing-store
   replay; process relaunch; multi-output phone fixtures; VoiceOver; larger
   accessibility sizes; dark appearance; Reduce Motion; Catalyst pointer and
   keyboard interaction; and Release-device Instruments evidence with a
   production-sized workspace remain.

## Performance and smoothness

The prior typing implementation scheduled a model write for every text change,
so the editor's eleven queries and large derived tree could invalidate while the
creator typed. The repaired path buffers text and performs one model commit at a
save/focus/exit boundary. The largest record families are fetched with brief or
workspace predicates, including nested series views. The simulator fixture
rendered and scrolled without a visible stall, but Debug simulator behavior is
not shipping proof. `PERF-RISK-02` remains open for Release-device body-update,
SwiftData fetch, frame-hitch, sheet-latency, media decode, memory, and keyboard
profiling against small, medium, and production-sized workspaces.

## Classification and next gate

PAGE-WORK-02 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-WORK-03 (Scheduled post detail), beginning with contract validation
while preserving the one-page-at-a-time audit boundary.
