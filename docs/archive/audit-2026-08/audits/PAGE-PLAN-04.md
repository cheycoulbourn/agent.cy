# PAGE-PLAN-04 · Schedule existing work · Audit record

Audited 2026-08-21 against the current working tree. Eligibility, workspace
scope, archived relationships, search, ordering, day-only scheduling, duplicate
draft prevention, missing records, save recovery, editor routing, and picker
work per redraw were traced separately.

## Contract under test

Schedule existing work offers a new post or an eligible saved Idea Bank item
for one selected day. It never exposes archived, foreign, or already-converted
post work; it does not duplicate an existing output; and a day-level suggestion
must not claim that the creator selected a time. Missing records and failed
draft creation remain recoverable.

## Evidence

| Check | Result |
| --- | --- |
| Saved and legacy ideas remain; post drafts, archived ideas, and foreign work are removed | Pass (new focused regression) |
| Search covers creator text and active pillar | Pass (new focused regression) |
| Selected day is normalized safely to noon without presenting noon as a chosen time | Pass (two new focused regressions plus phone replay) |
| Explicit preview picker/editor routes require their own arguments | Pass (new focused regression) |
| PAGE-MAIN-02 / PAGE-PLAN-02 / PAGE-PLAN-03 / PAGE-PLAN-04 focused suite | 26 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through focused test build |
| `AgentCy Desktop` Mac Catalyst build | Pass; existing frame-extraction deprecation warning is outside this page |
| Picker, new-post editor, and saved-idea editor phone states | Pass |
| Existing-output reuse and creation failure recovery | Pass structurally: `IdeaPostDraftView` resumes one output and exposes retry |
| Missing routed record | Pass structurally: explicit unavailable state preserves back navigation |

## Findings

1. `SCOPE-PLAN-04-01` — **Fixed**: the picker treated every Spark as a saved
   idea and every Developing item as ineligible. That could expose a Spark
   already converted to a post while hiding a creator's saved Developing idea.
   Eligibility now uses the canonical Idea Bank placement policy, including
   legacy saved ideas while excluding post-placement and archived work.
2. `RELATION-PLAN-04-01` — **Fixed**: an otherwise valid idea disappeared when
   its linked pillar was archived. The idea now remains available as unfiled;
   archived pillar metadata and color do not leak into the row.
3. `SEARCH-PLAN-04-01` — **Fixed**: the page contract required a search state,
   but the picker had no search control. Search now covers title, premise,
   notes, hook, script beats, CTA, and active pillar, with distinct empty-store
   and no-match recovery copy.
4. `TRUTH-PLAN-04-01` — **Fixed**: opening a saved idea for a selected day
   created an output whose legacy default said it included a time. The editor
   therefore rendered the internal noon normalization as `12:00 PM`, although
   the creator chose only a day. Newly ensured idea drafts now explicitly begin
   without a scheduled time; the replay renders `Fri, Aug 21` only.
5. `PERF-PLAN-04-01` — **Improved deterministically, profiling still open**:
   the former body repeatedly rebuilt workspace subsets, active-pillar sets,
   and per-row linear pillar lookups. One projection now resolves scope once,
   builds a duplicate-safe active-pillar index once, filters once, and provides
   stable ordering to the body.
6. `DUP-PLAN-04-01` — **Pass**: choosing a saved idea resumes its eligible
   output before creating one, while the explicit New post action creates one
   atomic brief/output pair. Failed creation stays on a retryable state.
7. `GAP-PLAN-04-01` — **Open**: interactive search clearing, row taps, injected
   persistence failure, VoiceOver, accessibility text sizes, Reduce Motion,
   Catalyst interaction replay, and production-sized Release traces remain.

## Performance and smoothness

The picker still observes four whole-table SwiftData queries. Its destination
adds three more only after navigation. The indexed projection removes repeated
workspace and pillar scans within a redraw, but live search still joins and
rescans eligible idea text on each keystroke. A production-sized Release trace
should measure picker-open latency, query invalidations, keystroke-to-result
latency, allocations from joined search text, row scroll cadence, and editor
transition time before considering predicate-backed fetches or cached search
text.

## Classification and next gate

PAGE-PLAN-04 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-05 (Post reschedule).
