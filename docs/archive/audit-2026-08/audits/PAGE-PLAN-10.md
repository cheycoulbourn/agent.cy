# PAGE-PLAN-10 · Add live post · Audit record

Audited 2026-08-21 against the current working tree. Blank, invalid,
cross-platform, account-scoped, past/future date, duplicate, metadata,
persistence-failure, dismissal, Agenda/Create/Feed entry, and query-work paths
were traced separately.

## Contract under test

Add live post records one already-published post; it never claims to publish to
a network. The link determines platform, destination, and format. The active
workspace's primary matching account is associated when available. Posted date
must not be future. Equivalent links cannot create two records in one workspace,
and a failed save cannot leave partial brief/output/media data. Optional link
metadata must not block the save.

## Evidence

| Check | Result |
| --- | --- |
| Canonically equivalent links are duplicates only inside the active workspace | Pass (new focused regression) |
| Saved post uses the scoped primary account and canonical posted/non-recurring fields | Pass (new focused regression) |
| Duplicate recheck at persistence boundary creates no second brief/output | Pass (new focused regression) |
| Future suggested day clamps to now while a past suggested day stays on that day | Pass (new focused regression) |
| Explicit Add-live replay requires its own debug launch argument | Pass (new focused regression) |
| PAGE-MAIN-02/07, PAGE-PLAN-02 through PAGE-PLAN-10, weekly-focus, social-grid, and related episode/live-post regressions | 89 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Phone sheet | Pass: platform guidance, blank link, published date/time, save, and close affordances render in [`add-live-post.png`](evidence/PAGE-PLAN-10/add-live-post.png) |

## Findings

1. `DUPLICATE-PLAN-10-01` — **Fixed**: duplicate detection compared stored and
   submitted strings literally, so `http` upgrades, fragments, and tracking
   parameters could create a second record. Both sides now use the shared link
   canonicalizer before workspace-scoped comparison.
2. `RACE-PLAN-10-01` — **Fixed locally**: duplicate checking occurred before a
   potentially long metadata request. Another local save during that wait could
   make the first check stale. The shared persistence boundary now fetches and
   checks immediately before insertion.
3. `ATOMIC-PLAN-10-01` — **Fixed**: brief, output, optional generated thumbnail,
   scoped account selection, and save now live in one persistence service.
   Save failure rolls back inserted page data and the sheet remains with a
   truthful retry message.
4. `ACCOUNT-PLAN-10-01` — **Pinned**: the platform link determines destination
   and format; account association prefers the first non-archived primary
   account in stable sort order, then the first non-archived matching account,
   and never borrows another workspace's account.
5. `DATE-PLAN-10-01` — **Pinned**: a live post cannot be dated in the future.
   Agenda entry preserves a past suggested day using the current time, while a
   future suggested day clamps to now. The same timestamp owns brief agenda,
   output target, and posted-at fields.
6. `SCOPE-PLAN-10-01` — **Preserved**: Feed continues to accept Instagram only
   because that grid can only display Instagram. Agenda and Create continue to
   accept Instagram, TikTok, and YouTube, so the page does not save invisible
   work from the Feed entry.
7. `PERF-PLAN-10-01` — **Fixed structurally**: the sheet previously observed
   every workspace, output, and social account while idle and waited for
   optional remote metadata before saving. It now has zero root collection
   observers, fetches persistence inputs only on Save, commits and dismisses
   without network work, then hydrates an available thumbnail asynchronously.
8. `DECISION-PLAN-10-01` — **Open product decision**: creators with multiple
   accounts cannot choose a non-primary account from this sheet. The current
   behavior is deterministic and matches existing default-account policy, but
   exposing an account picker would be a product change rather than an audit
   repair.
9. `GAP-PLAN-10-01` — **Open**: driven URL entry/save/duplicate/error taps,
   injected store failure, background thumbnail success/failure, simultaneous
   cross-device duplicate writes, VoiceOver, accessibility text sizes, Catalyst
   runtime interaction, and production-sized Release traces remain.

## Performance and smoothness

Opening and editing this sheet no longer subscribes to app-wide model changes.
The synchronous Save path now consists of bounded validation, three on-demand
collection fetches (workspace, output, account), insertion, and one persistence
commit. Optional metadata and thumbnail networking runs after dismissal. Release
profiling should still measure those fetches with large stores, SwiftData save
invalidation, widget snapshot refresh, calendar scrolling, keyboard transitions,
and background thumbnail memory.

## Classification and next gate

PAGE-PLAN-10 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-TASK-01 (Task detail), beginning with contract validation while
preserving the one-page-at-a-time audit boundary.
