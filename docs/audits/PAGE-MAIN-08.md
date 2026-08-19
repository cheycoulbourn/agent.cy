# PAGE-MAIN-08 Audit: Saved Posts library

- Audit date: 2026-08-18
- Status: `Coverage gap` — no reproduced defects; recorded state and measurement gaps remain
- Scope owner: [`SavedPostsLibraryView`](../../ios/AgentCy/Views/Ideas/SavedPostsLibraryView.swift) (372 lines) plus the shared `SavedPostRow`/`SavedPostPresentation`; reached from Idea Bank's "View all saved posts" and as a Catalyst destination
- Evidence: [`docs/audits/evidence/PAGE-MAIN-08/`](evidence/PAGE-MAIN-08/)

## Frozen contract

The library lists the active workspace's saved inspiration references, newest first, with truthful counts, search over titles and pillar names, safe review, external original-post exit, and confirmed deletion that never touches ideas already created from a reference ("Any idea you already created from it will stay in your Idea Bank."). Unowned records stay hidden (`SavedPostsScopePolicy`: nil workspace or nil active scope → excluded).

| State | Expected behavior |
| --- | --- |
| Empty | "No saved posts yet" with honest keep-here copy. |
| Populated | Rows with thumbnail or link placeholder, title, platform · analysis-state metadata, pillar mark. |
| Search / no match | Filter by title or pillar name; "No matching saved posts" with recovery copy. |
| Analysis states | pending "Waiting to analyze", shaping "Analyzing", ready "Idea ready", failed "Analysis needs attention", converted "Idea created", original-only "Original saved". |
| Delete | Explicit confirmation; cancel keeps the row; confirm removes it and surfaces errors through the real error path (no silent `try?`). |
| Missing thumbnails | Link placeholder; hydration task refetches per workspace-scoped missing set. |

## Function and exit trace

| Area | Source | Exit |
| --- | --- | --- |
| List | `sources` = strict scope filter + search over presentation title and pillar name | row → `appModel.openInspiration` (review) |
| Row menu | "Saved post actions" | Open original post (external URL), Delete saved post (confirmation) |
| Delete | `InspirationDeletionCoordinator.delete` with `presentCreatorError` on failure | notice "Saved post deleted." |
| Thumbnails | `.task(id:)` keyed on workspace + missing-thumbnail IDs; attempted-set dedupe | network fetch via `SavedPostThumbnailHydrator` |

## Runtime replay record

Disposable `AgentCy-Audit-PM06` simulator, in-memory `-agentCyPreviewData -agentCyPreviewIdeaBankState` fixtures, driven replay (2026-08-18): populated list with count and pillar mark (`90`), no-match search copy (`91`), row menu (`92`), delete confirmation with contract copy and cancel-keeps-row (`93`), confirmed delete removing the row and restoring the empty copy (`94-after-delete`). All assertions passed.

Two observations recorded, neither a defect:

1. **Reachability**: with zero saved posts, Idea Bank renders no Saved Posts section and no library link (`94-ideabank-empty-no-link.png`, `emptyStateLibraryReachable=false`) — the empty library page is unreachable on the phone. Acceptable (nothing to show), noted as a product-awareness fact.
2. **Harness note**: the row context menu and anchored confirmation dialog render outside the app's XCUITest accessibility tree on iOS 26 — driven via coordinates. These are system-provided surfaces (VoiceOver handles them natively), so this is a test-harness limitation, not an app accessibility defect.

## Remaining runtime coverage gap

- Analysis-state rows: the fixture seeds only `.ready`; pending/shaping/failed/converted/original-only rows and the failed-analysis recovery journey are unreplayed.
- Duplicate-import behavior, hydration success/failure with reachable media, workspace-switch replay, accessibility sizes/VoiceOver/Reduce Motion, and Catalyst presentation.
- Open-original external exit (would leave the app; not driven).

## Performance and smoothness

Static mechanisms recorded under `PERF-RISK-13` (Release measurement outstanding):

1. `hydrateMissingThumbnails` has **no batch cap** (Feed caps at 8) — a large library with many missing thumbnails fires an unbounded sequential network pass from the view task.
2. The `sources` filter runs a linear pillar scan per source per body pass (O(sources × pillars) per keystroke) — the same pattern PAGE-MAIN-05 already replaced with an index on the Idea Bank root.
3. Row thumbnails decode full `UIImage(data:)` per render without downsampling.

## Defects and classification

1. `DEFECT-MAIN-08-01` — **Resolved (2026-08-19, creator-reported)**: opening a saved post relocated the app to the Idea Bank behind the review sheet — on Catalyst the visible page swapped underneath, and closing the review stranded the user there. Cause: `AppModel.openInspiration` carried a vestigial `selectedTab = .ideaBank` from before the review sheet became shell-owned. Gate: the creator reproduced it on the desktop build; `PageMain08Tests.testOpeningASavedPostPresentsReviewWithoutSwitchingTabs` failed red with the exact symptom (`"ideaBank" != "home"`); the smallest patch removed the tab switch (the share-import auto-present path intentionally keeps its Idea Bank landing); **626 tests, 0 failures**; the rebuilt desktop app was reinstalled for creator runtime verification. A second regression pins the out-of-scope no-op path.
2. `GAP-MAIN-08-01` — **Open**: analysis-state rows, duplicate import, hydration outcomes, workspace switch, accessibility, Catalyst.
3. `PERF-RISK-13` — **Open**: uncapped hydration batch, per-keystroke pillar scans, and un-downsampled row decodes need Release-device measurement before any refactor.

## Classification and next gate

PAGE-MAIN-08 closes as `Coverage gap` (2026-08-18): the frozen contract held in every driven state with no source changes required. Reclassify after the `GAP-MAIN-08-01` replays and `PERF-RISK-13` measurements are recorded. Next page selection returns to the queue.
