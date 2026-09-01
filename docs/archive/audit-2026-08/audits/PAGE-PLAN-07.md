# PAGE-PLAN-07 · Daily focus detail · Audit record

Audited 2026-08-21 against the current working tree. Rest/focus resolution,
empty and assigned task states, completion counts, conflicting task dates,
duplicate day records, note/reminder persistence, task creation routing, query
work, and phone/desktop compilation were traced separately.

## Contract under test

Daily focus detail shows the focus that canonically owns the selected date and
counts only top-level, non-skipped Focus tasks whose own effective date is that
day. Post tasks and work owned by another day must not leak into its completion
count. Notes and reminders save automatically without writing once per
keystroke, claiming success after failure, or refreshing unrelated widgets.

## Evidence

| Check | Result |
| --- | --- |
| A task with conflicting target/focus dates appears on one canonical day | Pass (new focused regression) |
| Post tasks, skipped tasks, and subtasks are excluded from the top-level Focus count | Pass (new focused regression) |
| Newest same-day focus override wins in either fetch order | Pass (new focused regression) |
| Newest saved detail/note record wins in either fetch order | Pass (new focused regression) |
| Explicit detail preview route requires its own argument | Pass (new focused regression) |
| PAGE-PLAN-06/07 plus the complete weekly-focus suite | 27 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| PAGE-MAIN-02 through PAGE-PLAN-07 plus the weekly-focus suite | 57 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the focused test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Rest/empty phone state | Pass in [`daily-focus-detail-rest.png`](evidence/PAGE-PLAN-07/daily-focus-detail-rest.png) |
| Configured/part-complete phone state | Pass: focus, directive, duration, start time, saved note, and `1 of 2` render in [`daily-focus-detail-configured.png`](evidence/PAGE-PLAN-07/daily-focus-detail-configured.png) |

## Findings

1. `DATE-PLAN-07-01` — **Fixed**: a task belonged to the detail page when
   either `targetDate` or `dailyFocusDate` matched. When those fields diverged,
   the same task appeared in two days and polluted both completion stories.
   The page now uses the app's canonical task-owned precedence: target date,
   then focus date.
2. `COUNT-PLAN-07-01` — **Pinned**: the displayed projection now explicitly
   includes only top-level, non-skipped Focus tasks. Post-linked tasks,
   post-output tasks, and subtasks cannot enter the top-level `n of n` count.
3. `DUPLICATE-PLAN-07-01` — **Fixed deterministically**: focus resolution and
   saved note/reminder loading used fetch-order `first` selection for duplicate
   same-day records. Both now prefer the newest update, then creation date,
   then a stable UUID tie. A newer Rest override therefore cannot be revived by
   an older focus record.
4. `SAVE-PLAN-07-01` — **Fixed**: every Notes character immediately performed
   a SwiftData save plus widget refresh; reminder-wheel changes could do the
   same. Detail changes now use a cancellable 350 ms autosave, flush on exit,
   skip unchanged snapshots, and no longer refresh widgets that do not consume
   day-detail records.
5. `FAIL-PLAN-07-01` — **Fixed**: detail persistence discarded save errors with
   `try?`, then proceeded as if the write succeeded and could schedule a
   reminder from unsaved state. Save failure now rolls back, reports the error,
   preserves the editable draft, and blocks reminder scheduling.
6. `PERF-PLAN-07-01` — **Improved deterministically, profiling still open**:
   the page observed entire brief and output tables only to derive linkage that
   its Focus-only list discarded. Those two queries and repeated linkage scans
   are removed, reducing root whole-table observers from seven to five. The
   remaining whole-task query supports nested `TaskRow` subtasks and remains a
   Release profiling target.
7. `GAP-PLAN-07-01` — **Open**: driven note/reminder edits, injected persistence
   and notification-permission failures, checkbox/task-detail/add-task exits,
   VoiceOver, accessibility text sizes, Catalyst runtime interaction, and
   production-sized Release traces remain.

## Performance and smoothness

The two irrelevant whole-table observers, their workspace filters, and their
per-render linkage scans are gone. Notes, toggles, and time-wheel changes now
collapse into one short autosave burst, and unchanged appearance/disappearance
cycles perform no write. Release-device profiling should still measure detail
open latency, five remaining query invalidations, task checkbox refresh,
subtask lookup cost, text-field responsiveness, autosave duration, reminder
scheduling, scrolling beneath the persistent phone navigation, and memory with
small, medium, and large workspaces.

## Classification and next gate

PAGE-PLAN-07 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-08 (Daily focus editor).
