# PAGE-CAP-07 · Share extension · Audit record

Audited 2026-08-21 after PAGE-CAP-06 against the current working tree. The
host-provided URL/text intake, staged media lifecycle, queue boundary, and
main-app import deduplication were traced as separate boundaries.

## Contract under test

Accept one public HTTPS URL, either directly or inside host-provided text, and
atomically queue one bounded envelope. Unsupported input and a missing app
group stay recoverable and explain what failed. Replaying one capture is
idempotent; re-sharing one canonical post updates/reopens the workspace's
existing saved post. Closing the extension must stop unfinished work and leave
no unqueued staged media behind.

## Evidence

| Check | Result |
| --- | --- |
| Direct URL wins over host-supplied caption text and platform tracking is removed | Pass (focused regression) |
| URL-bearing text resolves exactly one unique public HTTPS URL and keeps the caption without links | Pass (focused regressions) |
| HTTP, credentials, localhost, local-network names, and IP literals are rejected | Pass (focused regression) |
| Queue write is bounded, atomic, oldest-first, replay-idempotent, and collision-safe | Pass (focused regressions + static file trace) |
| Same canonical post deduplicates inside one workspace while remaining private across workspaces | Pass (seven import regressions) |
| App and extension use the same `group.com.agentcy.app` entitlement; missing-container error remains visible | Pass (configuration/state trace; broken-entitlement runtime fixture remains) |
| Closing cancels provider loading, extraction, download, analysis, and link saving; a late staged file is removed | Pass (new focused regression + lifecycle trace) |
| Share transport and import suites | Pass (18 tests, 0 failures, iOS 26.5 simulator) |
| App scheme, embedded share extension, and diff whitespace check | Pass |

## Findings

1. `DEF-CAP-07-01` — **Confirmed fixed**: every share action was launched in an
   unowned task. Closing the extension completed the request but did not cancel
   provider loading, link extraction, downloads, media analysis, or link save.
   A provider callback could therefore stage a video or image after cleanup and
   orphan it in the app group. The controller/model now own and cancel their
   tasks, media analysis checks cancellation between expensive phases, and the
   shared asset store deletes files that finish staging after cancellation.
2. `DEF-CAP-07-02` — **Confirmed fixed**: unsupported-input and app-group
   failures used the same state as a transient alert. Dismissing the alert
   cleared the reason from the unavailable page and replaced it with generic
   guidance. Unavailable-state copy is now persistent; save/analyze failures
   remain alerts.
3. `PERF-CAP-07-01` — **Partially fixed risk**: the uncancelled work above could
   keep network, Vision, and Speech processing alive after dismissal. Explicit
   cancellation now stops at provider/network/analysis boundaries. Some Apple
   framework calls remain cooperative rather than instant, so device timing is
   still required.
4. `PERF-CAP-07-02` — **Open risk**: Analyze may download and stage a video up
   to 250 MB, generate five frames at up to 1280 px, run accurate OCR,
   classification, and face detection on each, then transcribe audio inside the
   extension process. This is the page's strongest remaining explanation for
   slow or memory-pressured sharing. The synchronous frame-copy API is also
   deprecated in iOS 18; migration to asynchronous frame generation should be
   measured on a Release device before changing the analysis pipeline.
5. `PERF-CAP-07-03` — **Open risk**: reaching Ready automatically starts remote
   extraction and optional thumbnail download even before the user chooses
   Analyze or Save link. The UI stays usable and the requests have 25/20-second
   timeouts, but this adds avoidable work to short share sessions and needs a
   product decision against preview quality.
6. `GAP-CAP-07-01` — **Open**: a host-app share-sheet fixture is missing.
   Direct URL, URL-bearing text, unsupported content, broken app-group signing,
   close-during-provider-callback, VoiceOver/Dynamic Type, and Release-device
   memory/time replays remain.

## Classification and next gate

PAGE-CAP-07 closes as `Confirmed defect (fixed)` + `Coverage gap`. Intake,
atomic queueing, replay/collision behavior, cross-workspace duplicate policy,
and late-file cancellation are pinned. The named host-share-sheet,
accessibility, signing-failure, and Release performance evidence remain. Next
page: PAGE-CAP-08 (Inspiration review).
