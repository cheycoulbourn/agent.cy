# PAGE-CAP-08 · Inspiration review · Audit record

Audited 2026-08-21 after PAGE-CAP-07 against the current working tree. The
sheet-owned view state, AppModel analysis lifecycle, content/media services,
creator-authored draft persistence, generated proposal staging, duplicate
import, deletion, and exits were traced as separate boundaries.

## Contract under test

Show one workspace-scoped saved reference and its safe metadata/analysis.
Pending and failed references can start or retry one analysis; the result stays
an editable proposal until the creator explicitly creates a post. Creator-
authored writing remains available if Cy finishes while it exists. Closing
cancels page-owned analysis without changing the saved post into a failure.
Duplicate imports reopen/update the existing workspace record. Deletion keeps
any created post. Exits go to the original link, created post, filming schedule,
delete, or dismiss.

## Evidence

| Check | Result |
| --- | --- |
| Source lookup is active-workspace scoped; a missing/foreign record stays unavailable | Pass (policy + route regressions) |
| Pending, processing, retry, ready, and converted action states are distinct | Pass (focused regressions + static state trace) |
| Analysis stages an editable result without creating a post | Pass (focused persistence regression) |
| Creating from a staged result is explicit and retry-idempotent | Pass (focused persistence regressions) |
| Manual creation works without Cy and incomplete manual drafts round-trip | Pass (focused persistence regressions) |
| Manual writing remains counted/visible after generated analysis and keeps its own pillar | Pass (three new focused regressions + view trace) |
| Dismissal cancellation restores the prior status/error and emits no failure notice | Pass (new AppModel boundary regression) |
| Failure copy distinguishes missing source content from a retryable shaping failure | Pass (focused presentation regression) |
| Canonical duplicates deduplicate per workspace but remain private across workspaces | Pass (import regressions) |
| Delete removes the reference, clears provenance, and preserves the created post | Pass (lifecycle regressions) |
| Review/lifecycle/shaping/import suites | Pass (33 tests, 0 failures, iOS 26.5 simulator) |
| App scheme, embedded extensions, and diff whitespace check | Pass |

## Findings

1. `DEF-CAP-08-01` — **Confirmed fixed**: the Analyze button launched an
   unowned `Task`. Dismissing the sheet did not bind analysis to the page
   lifecycle, and `CancellationError` was classified as a shaping failure. A
   cancelled request could therefore leave the saved post in Failed and show a
   misleading error. Analysis now runs through `.task(id:)`; model/service
   boundaries check cancellation; cancellation restores the previous status
   and error without presenting a notice.
2. `DEF-CAP-08-02` — **Confirmed fixed**: the manual idea form stayed editable
   during analysis, but a completed result replaced that screen. Once a result
   existed, the unsaved-work guard considered only the generated draft, so the
   creator's writing could disappear without a Close warning. Manual changes
   are now persisted before analysis, the form is disabled while processing,
   a populated manual draft remains visible beside the generated proposal, and
   both draft families participate in save/close protection.
3. `DEF-CAP-08-03` — **Confirmed fixed**: persisting a manual draft after a Cy
   result reused the source's single presentation pillar and silently replaced
   the analyzed suggestion's pillar. The manual payload now keeps its own
   pillar while the source retains the generated suggestion until the creator
   explicitly creates one of the posts.
4. `A11Y-CAP-08-01` — **Confirmed fixed**: processing used
   `allowsHitTesting(false)`, which blocked touch but did not expose disabled
   control semantics to assistive technology. It now uses `disabled`; manual
   text fields also announce their visible field names rather than only their
   placeholder copy, and deletion is unavailable during mutation.
5. `PERF-CAP-08-01` — **Partially fixed risk**: closing now stops at async
   metadata, shaping, frame, and Vision boundaries instead of continuing the
   complete pipeline. Individual synchronous frame extraction/Vision calls and
   speech recognition remain cooperative rather than instantly cancellable.
6. `PERF-CAP-08-02` — **Open risk**: explicit analysis loads five video frames
   up to 1280 px, runs accurate OCR/classification/face detection, and may run
   speech recognition. The deprecated synchronous frame-copy API remains the
   page's strongest measured-code candidate for analysis stalls and should be
   replaced only with Release-device timing evidence.
7. `PERF-CAP-08-03` — **Open risk**: the sheet observes whole source, brief, and
   pillar tables to resolve one source, one linked brief, and one workspace's
   pillars. It also reconstructs `UIImage` from stored thumbnail data during
   body evaluation. Large libraries and large thumbnails need Instruments and
   scrolling/re-render measurements before query/downsampling refactors.
8. `GAP-CAP-08-01` — **Open**: a seeded review-sheet fixture is missing.
   Driven pending/analyzing/ready/failure/cancel/delete replays, VoiceOver,
   Dynamic Type, Reduce Motion, Catalyst, background/foreground interruption,
   and Release-device media/memory profiling remain.

## Classification and next gate

PAGE-CAP-08 closes as `Confirmed defect (fixed)` + `Coverage gap`. Proposal
ownership, duplicate policy, creator-draft preservation, cancellation recovery,
deletion, and the major state labels are pinned. The named driven,
accessibility, lifecycle-interruption, and Release-performance evidence remain.
Next page: PAGE-CAP-09 (Filming schedule).
