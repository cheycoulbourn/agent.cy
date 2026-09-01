# PAGE-CAP-06 · Voice link picker · Audit record

Audited 2026-08-21 after PAGE-CAP-05 against the build-229 working tree. The
picker projection, its Voice Spark owner, and the attachment/store mutation
were traced as separate boundaries.

## Contract under test

Attach the explicitly selected recording to one eligible open post exactly
once. Empty and no-match states stay truthful; search covers useful post
context; a failed attachment stays recoverable; success exits to the connected
post. Performance watch: large-list filtering and whole-audio attachment I/O.

The prior ledger said "idea/post." The actual product language and reachable
picker policy consistently say open post: "Connect to a post," "Choose an open
post," and `ContinueWorkingPostPolicy`. The contract is corrected here rather
than treating dead idea-handling code as reachable picker behavior.

## Evidence

| Check | Result |
| --- | --- |
| Empty list says no open posts; a no-match query says no matching open posts | Pass (static trace) |
| Search matches title, premise, platform, and pillar context | Pass (focused regression) |
| Only eligible draft/open posts appear, ordered upcoming → past → undated | Pass (existing focused regressions) |
| Same-day work/post dates use the scheduled post date | Pass (existing focused regression) |
| Selecting one recording attaches only that recording, even when other session recordings exist | Pass (new focused regression) |
| Repeated attachment uses the recording filename to update one reference attachment instead of inserting a duplicate | Pass (static mutation trace) |
| Missing/stale selected recording reports a recoverable library error | Pass (guarded code path; runtime fixture remains) |
| Full Voice Spark regression class | Pass (16 tests, 0 failures, iOS 26.5 simulator) |
| Simulator build and diff whitespace check | Pass |

## Findings

1. `DEF-CAP-06-01` — **Confirmed fixed**: the record-specific Connect action
   reused the session-wide action set. Tapping one recording could therefore
   attach every recording made in that session. The link picker now resolves
   and attaches only the selected recording; multi-record Create Post/save
   behavior is unchanged.
2. `PERF-CAP-06-01` — **Partially fixed risk**: search previously filtered the
   entire post list twice during one redraw. The filtered list and date groups
   are now each computed once per redraw, with search behavior regression
   pinned. Large-list typing still needs Release-device measurement.
3. `PERF-CAP-06-02` — **Open risk**: attachment reads the full M4A and writes
   its cloud-backed `Data` synchronously on the main actor. A long recording
   may pause the picker. Moving this across an actor boundary also requires an
   explicit two-store rollback design, so it is deferred for instrumented,
   transaction-safe remediation instead of patched speculatively.
4. `GAP-CAP-06-01` — **Open**: a workspace-scoped picker fixture is missing.
   Driven empty/search/select/failure replays, repeated-tap behavior, real
   attachment rollback failure, VoiceOver/Dynamic Type, Catalyst, and
   Release-device large-list/audio profiling remain.

## Classification and next gate

PAGE-CAP-06 closes as `Confirmed defect (fixed)` + `Coverage gap`. The
selection scope and search projection are pinned; `PERF-CAP-06-02` and the
named runtime/accessibility evidence remain. Next page: PAGE-CAP-07 (Share
extension).
