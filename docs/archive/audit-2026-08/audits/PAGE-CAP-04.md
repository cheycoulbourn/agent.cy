# PAGE-CAP-04 · Voice Spark · Audit record

Audited 2026-08-19 (late pass) on the disposable simulator, TCC-reset
between permission scenarios. Evidence: crash report
`agent.cy-2026-08-19-230822.ips` plus session screenshots.

## Contract under test

Record/transcribe locally; explicitly create or connect work. Exits to
recording, picker, work, or dismiss. Required states: permission, record,
interrupt, failure, saved, linked. Performance concerns: audio buffers,
transcription task, waveform/list redraw, cleanup.

## Confirmed defect — fixed and regression-verified

`DEFECT-CAP-04-01` — **Fixed**: first-ever Speech Recognition grant crashed
the app (`EXC_BREAKPOINT`, `dispatch_assert_queue_fail`). The TCC callback in
`VoiceSparkRecorder.speechAuthorization()` inherited the class's MainActor
isolation but arrives on a system queue; Swift 6's dynamic isolation check
trapped. Every fresh install would crash on its first voice save — existing
authorized devices never see it, which is why it survived until now.
Smallest patch: `nonisolated` on `speechAuthorization()` (and the identical
site in `InspirationContentAnalysisService`, hardened preemptively). The
exact crash sequence was replayed after a TCC reset: no crash; the flow
completes into the saved-without-transcript state. A unit regression is not
practical (requires a live TCC prompt); the recorded replay is the
regression evidence.

## Runtime replay (phone)

| Check | Result |
| --- | --- |
| Mic granted: recording starts immediately, live timer, stop control | Pass |
| Speech prompt appears at point of need (on stop), with the app's purpose string | Pass |
| First-grant continuation | Pass after fix (previously crashed) |
| Transcription failure is honest: "saved, but could not be transcribed", audio kept | Pass |
| Saved recording listed with duration, play, save-to-file, swipe-to-delete | Pass |
| Recorder resets to "Record another thought" | Pass |
| Mic denied: inline "Microphone access is required…", no crash, typing path remains | Pass |
| Dismiss returns to hub | Pass |

## Findings

1. `DEFECT-CAP-04-01` — fixed above.
2. `GAP-CAP-04-01` — **Open**: interruption mid-record (call/backgrounding),
   real-audio transcription accuracy path, connect-to-post picker replay
   (PAGE-CAP-06), typed-thought save replay, VoiceOver, and device-audio
   buffers/waveform profiling remain.

## Classification and next gate

PAGE-CAP-04 closes as `Confirmed defect (fixed)` + `Coverage gap`. The
first-run crash is repaired and replay-verified; reclassify when
`GAP-CAP-04-01` replays are recorded. Next page: PAGE-CAP-05
(Recording detail).
