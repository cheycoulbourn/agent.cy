# PAGE-CAP-11 · Proposal review · Audit record

Audited 2026-08-21 after PAGE-CAP-10 against the current working tree. The
composition and revision variants, local editing state, validation, stale
proposal handling, acceptance, discard, close, persistence failure boundary,
existing output/task reconciliation, accessibility semantics, and form cost
were traced separately.

## Contract under test

Review one persisted pending composition or revision as local editable state.
Close leaves the stored proposal unchanged. Confirmed discard removes only the
pending proposal. Accept validates and commits the reviewed brief, eligible
output copy, tasks, canonical payload, and pending-proposal deletion as one
transaction. A stale, invalid, or failed operation keeps the review presented
and preserves the pending proposal and accepted work.

## Evidence

| Check | Result |
| --- | --- |
| Composition remains pending and does not apply generated fields before acceptance | Pass (focused regression) |
| A pending proposal rehydrates after relaunch and confirmed discard removes it | Pass (focused regression) |
| A stale composition proposal cannot overwrite current work | Pass (new focused regression) |
| Invalid or multiple recording milestones cannot create invalid tasks | Pass (new focused regression) |
| Accepted composition updates the existing Draft/Ready platform output without duplicating it | Pass (new focused regression) |
| Accepted regeneration preserves Scheduled/Posted output state and completed task history | Pass (focused regression) |
| Revision stages without mutation, rejects stale work, preserves lifecycle/history, and discards without refunding usage | Pass (four focused regressions) |
| Accept/Discard dismiss only after the model reports a successful save; failures roll back | Pass structurally; injected save-failure replay remains |
| Optional task minutes stay visually blank instead of displaying an unsaved invented value | Pass (binding trace + app build) |
| Changing a milestone task away from Filming clears the invalid milestone flag | Pass (binding trace + model validation) |
| Composition/revision review gate | Pass (10 tests, 0 failures, iOS 26.5 simulator) |
| App scheme, embedded extensions, and diff whitespace check | Pass |

## Findings

1. `DEF-CAP-11-01` — **Confirmed fixed**: composition and revision Accept and
   Discard always dismissed the review, even when fetch/encoding/save failed.
   Accept also mutated managed records before entering its `do/catch` and did
   not roll them back. All four operations now return a success result, roll
   back on failure, retain the in-memory pending proposal until commit, and let
   the view dismiss only after success.
2. `DEF-CAP-11-02` — **Confirmed fixed**: composition acceptance checked only
   the brief ID. A stale or substituted proposal could overwrite the post and
   delete the actual pending proposal. Acceptance now requires the exact staged
   proposal identity and rejects blank required names, duplicate platforms,
   and invalid recording milestones before mutation.
3. `DEF-CAP-11-03` — **Confirmed fixed**: accepting reviewed platform copy
   skipped an already-existing Draft output, so the page showed a caption and
   opening that were never applied. Reviewed variants now update Draft/Ready
   outputs in place and preserve Scheduled/Posted outputs and their history.
4. `DEF-CAP-11-04` — **Confirmed fixed**: a task with no estimate displayed
   `15` minutes even though acceptance persisted `nil`. The optional field now
   stays blank until the creator supplies a value. Changing a task from Filming
   also clears its recording-milestone flag instead of leaving a disabled,
   invalid toggle selected.
5. `COPY-CAP-11-01` — **Confirmed fixed**: revision discard used the alert title
   “Discard this post?”, which implied the accepted post would be removed. The
   revision path now asks “Keep your current post?” The header no longer claims
   every proposal structure is editable when tasks/platforms cannot be removed
   on this surface.
6. `PERF-CAP-11-01` — **No static issue observed**: the 208-line page owns no
   live table query and edits one bounded value proposal. Acceptance performs
   scoped brief output/task/pending fetches and one synchronous save. Large AI
   strings and many expanded task/platform fields can still invalidate the
   whole form per keystroke; Release-device typing and save latency have not
   been measured.
7. `GAP-CAP-11-01` — **Open**: no seeded proposal-review runtime fixture or
   injected persistent-store failure exists. Unchanged/edited/partial layouts,
   mid-save failure, close after edits, keyboard focus, VoiceOver, accessibility
   text sizes, Reduce Motion, Catalyst, and Release-device latency remain driven
   coverage gaps.

## Classification and next gate

PAGE-CAP-11 closes as `Confirmed defect (fixed)` + `Coverage gap`. Atomic
dismissal, rollback, proposal identity, required invariants, composition and
revision preservation, and Draft/Ready output application are pinned. The
named driven, accessibility, Catalyst, persistence-fault, and Release latency
evidence remains. Next page: PAGE-CAP-12 (Creator Session), currently Hidden.
