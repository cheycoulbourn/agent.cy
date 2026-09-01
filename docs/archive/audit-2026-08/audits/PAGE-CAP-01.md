# PAGE-CAP-01 · Creation Hub · Audit record

Audited 2026-08-19 (evening pass) on the disposable simulator (`AgentCy-Audit-PM06`,
iPhone 17 Pro, iOS 26.5) against HEAD `2e8f9f6`, with the day's committed quick-add
work included. Evidence: session scratchpad `evidence-cap01/00–05`.

## Contract under test

Offer capture modes without writing data before selection. Exits to capture
(Idea / Post / Task), Live Post, Voice Spark, Cy ideas, or dismiss.
Required states: allowed, expired, phone/desktop, repeated.
Performance concerns: sheet stacking and presentation animation.

## Runtime replay (phone)

| Check | Result |
| --- | --- |
| Hub presents from the tab-bar plus | Pass — all sections render: Create (Idea, Post, Task, Live post), Create on iPhone (Voice Spark), With Cy (Find three ideas) (`00`) |
| Idea exit → New idea composer; close returns to hub | Pass (`01`) |
| Post exit → New post editor | Pass (`02`) — see neighbor defect below |
| Task exit → task-type chooser (Post task / Focus task) | Pass (`03`) |
| Live post exit → Add live post (link + published calendar) | Pass (`04`) |
| Voice Spark exit → recorder page with empty library state | Pass (`05`) |
| Cy ideas exit → suggestions flow | Pass — exercised extensively earlier today, including the failure state |
| Dismiss (X) returns Home | Pass |
| No data written before selection | Pass — after opening every mode and closing without saving, Home shows "No drafts or posts in progress"; the auto-created empty post draft is discarded on exit |
| Repeated rapid open/close ×3 | Pass — no sheet stacking, no ghost state, full render each cycle |

## Desktop

Not simulator-drivable. Field-observed today at length by the creator on
builds 220–227: menu stage (600×560), stage growth into capture, embedded
post editor without the duplicate rail, and the Cy-ideas failure state. The
`creationHubMetrics(stage:)` policy carries a focused regression
(`DesktopNavigationTests`).

## Findings

1. Floating "Schedule post" bar overlapping the media button on the phone
   quick-add Post form: **not a defect** — creator-confirmed intentional
   floating action; scrolling lifts the content clear.
2. Creator direction (2026-08-19 evening): the spark and trash controls are
   removed from quick-action posts AND ideas on every platform — applied via
   `showsEditorChrome: false` on the quick-add post embedding and by deleting
   the idea composer's spark toolbar button. "Find three ideas" remains
   reachable from the hub's With Cy card.
3. `GAP-CAP-01-01` — **Open**: expired/access-gated hub state (no fixture),
   VoiceOver order, accessibility sizes, and driven Catalyst replay remain.

## Classification and next gate

PAGE-CAP-01 closes as `Coverage gap` — the contract held at every replayed
state with no hub-owned defects; reclassify when `GAP-CAP-01-01` replays are
recorded. Next page: PAGE-CAP-02 (Quick Capture).
