# PAGE-CAP-02 · Quick Capture · Audit record

Audited 2026-08-19 (evening pass) on the disposable simulator against the
post-commit tree (649 iOS tests, 0 failures). Companion feature record:
[`PAGE-CAP-02-FEATURE-2026-08-19.md`](PAGE-CAP-02-FEATURE-2026-08-19.md)
(platform/format idea tags, added earlier today with 4 focused regressions).
The Cy-directions failure seam was continued from the Claude handoff on
2026-08-21 and verified with the focused CAP-02 and neighboring service tests.

## Contract under test

Create exactly one idea, post, task, or Cy direction with explicit context.
Exits to development, setup, saved work, access, or dismiss.
Required states: every mode, invalid, saving, failure, upgrade, relaunch.
Performance concerns: 2,000-line view, typing redraw, AI cancellation.

## Runtime replay (phone)

| Check | Result |
| --- | --- |
| Idea mode: empty-title save is inert (dimmed check, no write) | Pass |
| Idea mode: titled save creates exactly one idea, lands first in the Idea Bank, sheet returns to the hub | Pass ("CAP-02 audit idea · Unfiled · now") |
| Post mode: editor opens on a fresh draft; platform/format/status/dates present | Pass |
| Post mode: titled draft survives dismissal into Home → "Continue working on…" (Draft · Instagram) | Pass |
| Post mode: empty draft is discarded on dismissal (no leak) | Pass (verified during PAGE-CAP-01) |
| Task mode: type chooser (Post task / Focus task) gates detail entry | Pass |
| Cy directions: loading and failure states render; failure offers Generate again / Close | Pass (failure exercised via missing sim credential and, in the field, the desktop timeout) |
| Cy directions: an eligibility guard explains how to restore access | Pass (presentation-policy regression pins the authored offline/access and incomplete-profile guidance) |
| Idea platform/format tags scope and persist | Pass (runtime + 4 unit regressions, earlier today) |
| Creator direction: spark and trash removed from quick-action posts and ideas | Pass — idea toolbar shows only the save check; the post embedding passes `showsEditorChrome: false`, covering the phone toolbar and the desktop rail |

## Findings

1. `DEF-CAP-02-01` — **Confirmed fixed**: the Find-three-ideas UI replaced the
   authored offline/access and incomplete-profile recovery instructions with
   the generic "couldn’t finish" message. `CyIdeaFailureMessagePolicy` now
   passes only those known recovery messages (plus actionable credit/quota
   responses) through verbatim and continues to hide unrecognized technical
   errors. CAP-02 and the two neighboring idea-outcome service tests pass.
2. Creator ruling recorded: the floating "Schedule post" bar overlapping the
   media button scrolls clear by design — not a defect.
3. `GAP-CAP-02-01` — **Open**: upgrade/access-gated capture state (no
   fixture), true relaunch draft restoration (the preview store is
   in-memory), VoiceOver/accessibility sizes, driven Catalyst replay, and
   Release-device typing-redraw profiling remain.

## Classification and next gate

PAGE-CAP-02 closes as `Confirmed defect (fixed)` + `Coverage gap` — every
replayable contract state passed, one-idea/one-post semantics held, and the
guard-message regression is pinned. Reclassify when `GAP-CAP-02-01` replays
are recorded. The sequential audit has already passed PAGE-CAP-03 and
PAGE-CAP-04; next page: PAGE-CAP-05 (Recording detail).
