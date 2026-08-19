# PAGE-MAIN-07 Audit: Feed

- Audit date: 2026-08-18
- Status: `Coverage gap` — the confirmed defect is repaired and runtime-verified under the creator's "IG only" decision; recorded coverage gaps remain
- Scope owner: [`SocialGridView`](../../ios/AgentCy/Views/Feed/SocialGridView.swift) (1,207 lines), reachable from the phone Plan rail ("Open social grid") and as a Catalyst destination; `AddLivePostView` lives in the same file but its full behavior is `PAGE-PLAN-10` — only its root exit and save/duplicate boundary are covered here
- Scope basis: resolved `DRIFT-02`/[ADR 0012](../adr/0012-catalyst-maintained-internal-scope.md) — Feed is a desktop-owned destination reachable from the phone; audited under that scope
- Evidence: [`docs/audits/evidence/PAGE-MAIN-07/`](evidence/PAGE-MAIN-07/)

## Frozen contract

Feed shows a manual planned/live Instagram-profile preview grid without implying any network publishing. Planned means a scheduled Instagram output with a target date; live means a posted output. Counts and tiles must be truthful for the active workspace. Exits: post detail, add live post, settings, back to Plan.

| State | Expected behavior |
| --- | --- |
| Empty | Honest empty card with an Add-live-post exit. |
| Populated | 3:4 tiles, newest first; media cover or pillar-colored placeholder with the post title. |
| Filters | All / Planned / Live segmented control filters by output status. |
| Missing media | Placeholder tile; posted Instagram links may hydrate a thumbnail (capped, deduplicated). |
| Workspace switch | All projections re-scope; thumbnail attempt state resets (`onChange(workspaceRevision)`). |
| Add live post | A saved live link lands visibly in the surface the sheet promises ("place it on the right day"). |

## Function and exit trace

| Area | Source | Exit |
| --- | --- | --- |
| Rail | phone: back / add-live / refresh / profile; desktop: `AgentPageRail` | Plan, add-live sheet, Settings |
| Projection | `scopedBriefs` → `scopedOutputs` (**Instagram Reels only**) → ordered records → attachment cover index → `allItems` | — |
| Tiles | `SocialGridTile` (3:4, cover image or pillar placeholder, status capsule) | `ScheduledPostDetailView` |
| Stats | planned/live/with-media counts over `allItems` | — |
| Refresh | manual `refreshFeed()`: save, 700ms sleep, three whole-table fetches, then thumbnail re-hydration | — |
| Thumbnails | `.task(id:)` keyed on workspace + posted-Instagram-link IDs; ≤8 fetches per pass, attempted-set dedupe, reset on workspace change | network fetch via `PublishedPostThumbnailHydrator` |
| Add live | `LivePostURLPolicy` accepts Instagram, TikTok, YouTube; duplicate URL guard is workspace-scoped; save creates posted brief+output (+thumbnail attachment when metadata resolves) | sheet dismiss |

Workspace scoping is consistent throughout (briefs, outputs, pillars, accounts, thumbnail state) — this page already has the discipline PAGE-MAIN-06 lacked. The no-network-publishing framing holds in copy and accessibility hints.

## Reproduced defect

### DEFECT-MAIN-07-01 — Confirmed, open: TikTok/YouTube live posts save invisibly

The add-live sheet invites "Paste an Instagram, TikTok, or YouTube link… agent.cy will place it on the right day," and `addPost` saves TikTok (`.tiktok`) and YouTube (`.youtubeVideo`) outputs — but the grid projection filters `platform == .instagramReels` only, and the page's stats count the same projection.

Runtime reproduction (disposable simulator, in-memory preview store, driven replay, 2026-08-18):

1. Save `https://www.tiktok.com/@creator/video/…` → sheet closes with no error; grid and Live count unchanged (`73-after-tiktok-save.png`; verdict `tiktokSavedButHidden=true`).
2. Save the same URL again → **"That live post is already saved."** (`74-tiktok-duplicate-error.png`) — proving the invisible record persisted.
3. Control: save `https://www.instagram.com/p/…` → a Live tile appears and counts update (`75-after-instagram-save.png`) — the grid pipeline itself is healthy.

The saved TikTok post does surface in Plan/Agenda via `agendaDate`, so data is not lost — but this page tells the user nothing happened while blocking a retry.

**Repair (creator decision "IG only", 2026-08-18):** `LivePostLinkScope` carries the page's platform scope — `.instagramOnly` for the Feed sheet, `.allPlatforms` (the default) for Agenda and the Creation Hub, so cross-platform live capture survives where the grid can show or place it. The Feed sheet's prompt, invalid-link copy, and a new scope guard reject TikTok/YouTube links in place with "This grid previews Instagram only. Add TikTok or YouTube posts from the Agenda or the create menu." — nothing is saved, so the duplicate guard can no longer trap a hidden record.

- RED first: `PageMain07Tests` failed (`cannot find 'LivePostLinkScope'`) before any production code — three regressions: instagram-only rejection, all-platforms preservation, and rejection-copy honesty.
- GREEN: full suite **622 tests, 0 failures**.
- Runtime verified (driven replay, `80`–`82`): Instagram-only prompt shown; TikTok rejected in place and **not** persisted (re-adding shows the scope message, not the duplicate guard); Instagram control still lands as a live tile.

## Runtime replay record

Disposable `AgentCy-Audit-PM06` simulator, in-memory `-agentCyPreviewData` store, driven via the scratchpad XCUITest runner. States captured: populated grid with media tile and placeholder tile (`70`, `75` — placeholder covers the missing-media state), Planned filter (`71`), Live filter before any live post (`72`), add-live save/duplicate/control flows (`73`–`75`). One probe assertion was a test bug, recorded honestly: the Instagram control tile was present but titled "Instagram" (fetched page title), not the probe's expected "Instagram post".

## Remaining runtime coverage gap

- Workspace-switch replay on this page (scoping is statically consistent; a driven two-workspace pass would close it).
- Thumbnail hydration success/failure with reachable Instagram media; missing-media recovery after refresh.
- Accessibility sizes, VoiceOver order, Reduce Motion, dark mode captures.
- Catalyst presentation (desktop rail, 660×720 sheet), and `PAGE-PLAN-10`'s full add-live matrix (posted-date boundaries, per-platform accounts, rollback path).

## Performance and smoothness

Static mechanisms recorded (Release measurement still owed under `PERF-RISK-03`/`05`):

1. `refreshFeed()` sleeps 700ms then runs three whole-table fetches on the main actor per tap, and busy-waits in 100ms steps while hydration runs.
2. Tiles decode full `UIImage(data:)` from `previewData ?? cloudData` per render with no downsampling cache — the classic grid-scroll decode risk (`PERF-RISK-05`).
3. Eight whole-table `@Query` collections; projection/index chains (`scopedBriefs` → `outputIndex` → `attachmentIndex` → `allItems`) recompute per body pass.
4. Thumbnail hydration performs network fetches from a view task (capped at 8, deduplicated, workspace-reset — well-bounded).

## Defects and classification

1. `DEFECT-MAIN-07-01` — **Resolved (Runtime verified)**: the Feed sheet is scoped to Instagram with honest guidance; cross-platform capture remains in Agenda and the Creation Hub.
2. `GAP-MAIN-07-01` — **Open**: workspace-switch replay, hydration success/failure, accessibility/dark captures, Catalyst presentation.
3. `PERF-RISK-03`/`05` — **Open**: refresh fetch pattern, per-tile decode, and projection recompute need Release-device measurement.

## Classification and next gate

PAGE-MAIN-07 closes as `Coverage gap` (2026-08-18). DEFECT-MAIN-07-01 completed the full gate under the creator's "IG only" decision: contract resolved → reproduced → focused failing regressions watched red → smallest patch → **622 tests, 0 failures** → runtime verified on the disposable simulator. The working tree remains uncommitted by instruction, and the Feed fix is **not yet installed on the creator's iPhone** (build 211 predates it). `GAP-MAIN-07-01` and the `PERF-RISK-03`/`05` measurements reclassify the page only when recorded.
