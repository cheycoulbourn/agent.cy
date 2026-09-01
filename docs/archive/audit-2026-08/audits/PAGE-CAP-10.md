# PAGE-CAP-10 · Develop brief · Audit record

Audited 2026-08-21 after PAGE-CAP-09 against the current working tree. The
thread opener, prompt submission, eight-turn boundary, compose transition,
access denial, provider failure, cancellation, dismissal, archiving, pending
proposal persistence, relaunch, accessibility semantics, and page-owned query
cost were traced separately.

## Contract under test

Develop one post through one active conversation. A successful first dialogue
or composition moves a Spark to Developing, but generated post content remains
an editable pending proposal until the creator accepts it. Cancellation,
failure, or denied access does not append a turn, stage a proposal, consume the
Spark lifecycle, or manufacture an error. Closing cancels page-owned work.
Archiving keeps the old conversation in history and starts one fresh thread.

## Evidence

| Check | Result |
| --- | --- |
| Assistance mode creates the intended opener and only one active thread | Pass (focused regressions) |
| A successful dialogue appends one creator/Cy pair and enters Developing | Pass (new focused regression) |
| Rapid repeated submission cannot create duplicate turns | Pass (new focused regression) |
| Cancellation appends no messages, stages no proposal, preserves Spark, and shows no error | Pass (two new focused regressions) |
| Provider failure preserves the Spark and returns a retryable failure outcome | Pass (new focused regression + view trace) |
| Composition stages one relaunch-safe proposal without applying generated fields, outputs, or tasks | Pass (focused regressions) |
| Acceptance applies the proposal; discard removes the pending proposal | Pass (focused regressions) |
| Archive starts a fresh thread and preserves the old thread | Pass (focused regression) |
| Close and interactive dismissal cancel page-owned AI work | Pass structurally; driven mid-flight replay remains |
| Typing state has a combined accessibility label and primary controls meet 44-point targets | Pass structurally; VoiceOver/Dynamic Type replay remains |
| App scheme, embedded extensions, and diff whitespace check | Pass |

## Findings

1. `DEF-CAP-10-01` — **Confirmed fixed**: dialogue and composition ran in
   unowned `Task` blocks. Closing the page did not own or cancel that work, and
   cancellation was reported as “couldn’t be completed” with “Your work is
   saved.” The page now drives one identifiable SwiftUI task, dismissal cancels
   it, the model checks cancellation before persistence, and both Swift and URL
   cancellation return without a notice.
2. `DEF-CAP-10-02` — **Confirmed fixed**: the public model boundary accepted a
   second dialogue/composition request while the first was suspended. That
   could duplicate conversation turns and race the shared loading flag. Both
   operations now reject re-entry before and after the asynchronous access
   gate; the UI also disables every competing action while its request is
   pending.
3. `DEF-CAP-10-03` — **Confirmed fixed**: conversation archiving stayed active
   during generation. An in-flight response could write into the newly archived
   thread while the page displayed a fresh one. The menu and archive boundary
   are now unavailable while this page owns work.
4. `DEF-CAP-10-04` — **Confirmed fixed**: the composer cleared the creator's
   prompt before the provider outcome and discarded it on failure or denied
   access. Dialogue now returns an explicit success result; the page restores
   the prompt when no turn was committed.
5. `SPEC-CAP-10-01` — **Clarified**: “no pre-acceptance mutation” conflicted
   with the PRD's explicit Spark-to-Developing rule. The page contract now says
   generated *content* is not applied before acceptance, while successful
   dialogue/composition enters Developing. Cancelled and failed attempts remain
   Spark.
6. `PERF-CAP-10-01` — **Confirmed fixed risk**: the page observed every
   `ConversationMessage` in the store and filtered the active thread during
   every body evaluation. It now fetches only the active thread's maximum
   eight-turn history and refreshes that bounded state after page-owned writes.
7. `PERF-CAP-10-02` — **Open risk**: every dialogue and composition builds
   creator context synchronously on the main actor by fetching/filtering whole
   workspace, pillar, output, task, and brief tables before the network call.
   This is a credible source of delayed taps and stutter as the library grows.
   It needs Release-device signposts plus a scoped or cached context snapshot;
   this page audit did not guess at a cross-feature data architecture.
8. `GAP-CAP-10-01` — **Open**: no seeded Develop Brief runtime fixture exists.
   Mid-flight close/swipe, denied access, provider error, pending-proposal
   relaunch, VoiceOver, accessibility text sizes, Reduce Motion, Catalyst, and
   Release-device latency remain driven coverage gaps.

## Classification and next gate

PAGE-CAP-10 closes as `Confirmed defect (fixed)` + `Coverage gap`. Cancellation,
duplicate submission, prompt recovery, archive safety, lifecycle intent,
proposal staging, and thread-scoped message loading are pinned. The named
driven, accessibility, Catalyst, and Release-performance evidence remains.
Next page: PAGE-CAP-11 (Proposal review).
