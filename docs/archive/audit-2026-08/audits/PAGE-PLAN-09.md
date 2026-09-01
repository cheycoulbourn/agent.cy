# PAGE-PLAN-09 · Episode slot actions · Audit record

Audited 2026-08-21 against the current working tree. Open, converted, skipped,
stale-link, saved-idea, duplicate-previous, missing-series, error, and query-work
paths were traced separately.

## Contract under test

Only an open series slot can create, reuse, duplicate, or skip an episode. A
converted or skipped slot cannot mutate again. Reusing an Idea Bank idea must
turn it into one non-recurring episode, and a stale conversion link must stop
instead of manufacturing duplicate work. Failure leaves the plan unchanged.

## Evidence

| Check | Result |
| --- | --- |
| Reusing an Idea Bank output clears its prior recurrence and scheduling links | Pass (new focused regression) |
| Stale converted-brief link cannot create a second episode | Pass (new focused regression) |
| Converted slot cannot be skipped or lose its episode link | Pass (new focused regression) |
| Skipped slot cannot convert into hidden episode work | Pass (new focused regression) |
| Idea with multiple outputs is rejected instead of choosing one arbitrarily | Pass (new focused regression) |
| Explicit episode-actions replay requires its own debug launch argument | Pass (new focused regression) |
| Existing new/reuse/duplicate episode domain behavior | Pass (3 focused regressions) |
| PAGE-MAIN-02 through PAGE-PLAN-09, weekly-focus suite, and existing episode regressions | 70 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Phone action sheet | Pass: title, series, date, create/reuse/duplicate exits, skip action, and close affordance render in [`episode-slot-actions.png`](evidence/PAGE-PLAN-09/episode-slot-actions.png) |

## Findings

1. `RECURRENCE-PLAN-09-01` — **Fixed**: converting a saved idea reused its
   existing output without clearing recurrence, recurrence-root, target,
   posted, or publication state. The reused output is now reset to one draft,
   non-recurring episode while creator-authored content remains intact.
2. `DUPLICATE-PLAN-09-01` — **Fixed**: an open slot carrying a stale
   `convertedBriefID` was treated as unconverted and could create a second
   brief/output. Linked conversions now use targeted lookups and stale,
   missing, or ambiguous links stop with a truthful unchanged-plan error.
3. `STATE-PLAN-09-01` — **Fixed**: planner entry points previously trusted the
   caller to filter slot status. Converted slots could be skipped and skipped
   slots could be converted. Every conversion and skip path now enforces the
   same open-slot state gate.
4. `AMBIGUITY-PLAN-09-01` — **Fixed**: Idea Bank conversion could select an
   arbitrary output when data contained multiple outputs for one idea. It now
   fetches at most two matching outputs and refuses ambiguous or mismatched
   ownership without mutating the idea or slot.
5. `FAIL-PLAN-09-01` — **Fixed at the page boundary**: conversion and skip
   errors now roll back the model context and explain that the plan is
   unchanged. Stale conversion links receive specific recovery copy instead of
   opening or duplicating uncertain work.
6. `SKIP-PLAN-09-01` — **Fixed**: skip was an immediate destructive action.
   It now requires confirmation and states that only this empty date is skipped
   while the series stays active.
7. `MISSING-PLAN-09-01` — **Pinned**: if the owning series is missing or out of
   workspace scope, the sheet stays readable and offers no mutation actions.
8. `PERF-PLAN-09-01` — **Improved, profiling still open**: sheet-level
   whole-table observers fell from four to two by removing outputs entirely and
   loading Idea Bank briefs only after the user requests them. Existing-link
   and reusable-output validation use bounded targeted fetches. Duplicate,
   episode-number, and task-template paths still perform collection fetches.
9. `DECISION-PLAN-09-01` — **Open product decision**: a linked episode with
   more than one platform output is treated as an incomplete conversion because
   this page has no canonical output-selection rule. Supporting multi-output
   series episodes requires a deliberate navigation contract, not fetch-order
   selection.
10. `GAP-PLAN-09-01` — **Open**: driven taps through every successful exit,
    confirmation-dialog interaction, injected save failure, missing-series
    runtime replay, VoiceOver, accessibility text sizes, Catalyst runtime
    interaction, and production-sized Release traces remain.

## Performance and smoothness

The idle sheet now observes only series and workspace changes. It does not
subscribe to output changes, and it defers the brief fetch until Idea Bank is
opened. Release-device profiling should still measure initial series lookup,
large Idea Bank load and scrolling, duplicate-previous conversion, save
invalidation, dismissal-to-editor latency, and memory with small, medium, and
large workspaces.

## Classification and next gate

PAGE-PLAN-09 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-10 (Add live post), beginning with contract validation before
implementation because its current ledger status is contract-blocked.
