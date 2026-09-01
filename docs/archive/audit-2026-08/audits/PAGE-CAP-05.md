# PAGE-CAP-05 · Recording detail · Audit record

Audited 2026-08-21 from the Claude handoff against the build-229 working tree.
The page was traced through both owners: the local Voice Spark library and a
post's cloud-backed voice attachments.

## Contract under test

Play and inspect one recording without accidental linked-work edits. Exits to
the owning library/post, download/share, explicit connection, or deletion.
Required states: playable audio, missing audio, playback completion or
interruption, transcript/empty transcript, title save/failure, download,
delete, and back. Performance watch: audio loading, long-transcript redraw,
and player/session cleanup.

## Evidence

| Check | Result |
| --- | --- |
| Back dismisses detail without deleting the recording | Pass (navigation policy regression) |
| Delete is owned by the parent and causes exactly one navigation pop | Pass (navigation policy regression) |
| Title save enables only for a normalized change | Pass |
| Transcript and empty-transcript presentation | Pass (static trace; transcript normalization regression) |
| Local and post-backed audio both reach the detail page | Pass (both call sites compile and pass the full Voice Spark regression class) |
| Playback is available from the detail page and stops/releases its player and audio session on exit | Pass (implemented; build and lifecycle trace) |
| Missing local audio is detected before actions render | Pass (store regression) |
| Full Voice Spark regression class | Pass (14 tests, 0 failures, iOS 26.5 simulator) |
| Simulator build | Pass |

## Findings

1. `DEF-CAP-05-01` — **Confirmed fixed**: the detail page had no playback
   control even though playback is part of its approved contract. It now owns
   a URL-or-data player, exposes Play/Stop with an accessible state label, and
   releases the player and audio session on disappearance or completion.
2. `DEF-CAP-05-02` — **Confirmed fixed**: the local recording store returned a
   plausible URL even after the original file was missing. The page could
   therefore render enabled playback/download actions that failed only after
   a tap. `audioURL` now verifies file existence, and the detail page presents
   an explicit unavailable-audio explanation.
3. `PERF-CAP-05-01` — **Fixed risk**: title typing previously retrimmed the
   entire transcript on each page redraw. The immutable transcript is now
   normalized once during page initialization. The playback monitor runs only
   while audio is active and cancels on stop/disappearance; no idle polling or
   retained player remains.
4. `GAP-CAP-05-01` — **Open**: a stable workspace-scoped recording-detail
   runtime fixture is still missing. Real playback interruption, deletion and
   title-failure UI, VoiceOver/Dynamic Type, Catalyst, and Release-device
   latency/memory profiling remain.

## Classification and next gate

PAGE-CAP-05 closes as `Confirmed defect (fixed)` + `Coverage gap`. The approved
page behavior is represented in code and focused regressions, but the named
runtime/accessibility/performance evidence in `GAP-CAP-05-01` remains. Next
page: PAGE-CAP-06 (Voice link picker).
