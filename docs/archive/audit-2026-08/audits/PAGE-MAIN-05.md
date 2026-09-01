# PAGE-MAIN-05 Audit: Idea Bank

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Scope owner: [`IdeaBankView`](../../ios/AgentCy/Views/Ideas/IdeaBankView.swift), shared root Saved Post rows in [`SavedPostsLibraryView`](../../ios/AgentCy/Views/Ideas/SavedPostsLibraryView.swift), and Idea Bank fixtures in [`PreviewData`](../../ios/AgentCy/Preview/PreviewData.swift)
- Parent programs: [`AUD-03`](../APP_AUDIT_QUEUE.md#aud-03-capture-to-post-lifecycle), [`AUD-04`](../APP_AUDIT_QUEUE.md#aud-04-external-entry-and-inspiration), and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

Idea Bank is the active workspace's searchable root for explicit ideas and the phone's five-item Saved Posts preview. Search applies to both visible sections. Filters show all ideas, truly unfiled ideas, archived work, or an active pillar. Selection and deletion may act only on items currently visible on this platform. A workspace change invalidates record-scoped filter, selection, detail, and deletion state. Missing requested ideas are consumed once with an honest unavailable notice. Save idea may carry only a currently active pillar into Quick Capture.

| State | Expected behavior |
| --- | --- |
| Empty | Show zero ideas, honest copy, and Save idea. |
| Populated | Show scoped Saved Posts preview and explicit Idea Bank items with truthful counts/metadata. |
| Search | Filter both sections from one trimmed query and explain zero results. |
| All / Unfiled / Pillar / Archived | Normalize invalid pillar filters to All; keep attached pillar context searchable. |
| Selection | Count/delete only currently visible ideas and phone-visible Saved Posts; hidden Catalyst references are never selectable. |
| Workspace switch | Reset query, filter, selection, detail/library navigation, pending deletion, and thumbnail-attempt state. |
| Requested idea | Open one scoped match or consume the request with an unavailable notice; never leave a deferred surprise route. |
| Accessibility | Stack selection actions, bound the rail cancel control, allow idea/Saved Post labels to wrap, expose status metadata, and honor Reduce Motion. |

## Function and exit trace

| Area | Source | Exit |
| --- | --- | --- |
| Header | active identity and normalized filter/selection state | selection, filter, or Settings |
| Search | one root projection across scoped briefs, Saved Posts, and pillars | in-place results |
| Saved Posts preview | resolved workspace, filtered sources, five-item policy | review, original URL, delete, or Saved Posts library |
| Idea list | explicit/legacy placement plus normalized filter | Idea/Post draft detail |
| Selection | current visible IDs only | clear, select all, delete, or cancel |
| Save idea | normalized active pillar ID | Quick Capture |
| Requested route | scoped brief index | detail or honest unavailable notice |

The complete Saved Posts library/review remains `PAGE-MAIN-08`; Idea/Post editing remains a deeper work contract. This pass covers only their root exits and shared row accessibility.

## Repair verification

| Confirmed cause | Repair |
| --- | --- |
| Ideas resolved a fallback workspace while Saved Posts used the raw, possibly archived workspace ID. | `IdeaBankRootProjectionPolicy` resolves one workspace once and scopes/de-duplicates briefs, sources, and pillars consistently. |
| Repeated computed lists rescanned titles, full notes, sources, and pillars several times per render/keystroke. | One projection builds normalized filter, pillar index, ideas, Saved Posts, and preview once for the body pass. |
| A retained pillar filter could cross a workspace boundary and hand Quick Capture another workspace's pillar ID. | Workspace changes reset record-scoped state; invalid/archived pillar filters normalize to All; capture accepts only an active projected pillar. |
| Missing requested IDs remained pending indefinitely. | Route policy consumes every non-nil request and presents a scoped unavailable notice on misses. |
| Saved Post selection was not pruned when search changed, so counts and deletion targets diverged. | One visible-ID reconciliation intersects both idea and Saved Post selections before count/delete work. |
| Catalyst hid Saved Posts visually but Select all and Delete still included the phone preview. | Platform-visible Saved Post IDs are now the only selectable/deletable Saved Post IDs; Catalyst resolves that set to empty. |
| Selection transitions ignored Reduce Motion and maximum text collided in the page rail or truncated row context. | Motion is gated; selection controls stack; accessibility sizes use a bounded close control and larger title/metadata line budgets; VoiceOver receives row metadata. |

## Evidence

- **7 PAGE-MAIN-05 regressions passed**: resolved-workspace projection, stale-filter capture safety, archived pillar search, selection reconciliation/platform visibility, missing-route consumption, Reduce Motion, and accessibility presentation.
- Full iOS suite: **611 tests, 0 failures** on iPhone 17 Pro / iOS 26.5.
- `AgentCy Desktop` Catalyst build passed.
- `pnpm typecheck`, **140 TypeScript tests**, and `pnpm build` passed.
- Scoped `git diff --check` passed.

## Runtime replay

The disposable iPhone 17 Pro / iOS 26.5 simulator used an in-memory container and inspected populated light/dark, empty, archived, no-match query, missing route, accessibility selection, and accessibility filter states. It confirmed:

1. Scoped counts, Saved Posts preview, idea metadata, search copy, archived view, and missing-route notice render truthfully.
2. Maximum-text selection uses a bounded cancel control without colliding with the breadcrumb; selection actions and row labels receive expanded layouts.
3. The maximum-text filter exposes All, Unfiled, Archived, and all active pillars without clipping the popover.

## Remaining runtime coverage gap

The locked Mac session prevented driven taps, keyboard input, VoiceOver, and actual Reduce Motion. Before `Verified`, record one unlocked pass that:

1. Searches titles, notes, Saved Post titles, and pillar names; clears search; exercises every filter and empty result.
2. Selects ideas and Saved Posts, changes the query while selected, verifies the count shrinks, then cancels and deletes exact visible targets; repeat on Catalyst to prove hidden Saved Posts cannot be selected.
3. Switches workspaces while a pillar filter, selection, detail, library, and deletion dialog are active; then saves an idea and verifies no stale pillar crosses scope.
4. Opens every root exit, triggers missing/deleted/cross-workspace requested IDs, and confirms no route fires later.
5. Replays keyboard dismissal, full bottom-navigation clearance, VoiceOver order/metadata, and actual Reduce Motion at normal and maximum text sizes.

## Deferred decisions and deeper clauses

- Product decision: Archived currently means all archived work, including archived explicit post drafts; blank-title records remain hidden. Confirm before changing either behavior.
- Product decision: Select all intentionally covers the five visible phone preview items, not the full Saved Posts library.
- `PAGE-MAIN-08`: bulk Saved Post failure/partial-deletion behavior, hydration retries, full search/sort, thumbnail/media memory, and review routing.
- Deeper work page: Idea/Post resume, deletion persistence, and Quick Capture save failure/relaunch behavior.

## Performance and smoothness

- Resolved: repeated root projections and linear per-row pillar lookups are replaced by one pass plus an ID index.
- Open `PERF-RISK-13`: the 991-line root still owns five whole-table queries and searches full notes synchronously per keystroke; thumbnail hydration changes its task key after successful saves. Release-device profiling with large libraries must measure typing latency, projection time, query/body invalidations, scroll hitches, thumbnail network/decode work, memory, and retained-tab background activity.
- Open `PERF-RISK-07`: retained six-stack shell behavior and the root-wide navigation warning still need Release-device measurement.

## Defects and classification

1. `DEFECT-MAIN-05-01` — **Resolved**: both sections now use one resolved workspace.
2. `DEFECT-MAIN-05-02` — **Resolved**: stale pillar state cannot cross workspace/capture boundaries.
3. `DEFECT-MAIN-05-03` — **Resolved**: missing routes are consumed with honest feedback.
4. `DEFECT-MAIN-05-04` — **Resolved**: hidden/stale Saved Post IDs cannot inflate counts or be deleted.
5. `DEFECT-MAIN-05-05` — **Resolved**: repeated root search/filter/pillar work is projected once.
6. `DEFECT-MAIN-05-06` — **Resolved**: Reduce Motion, VoiceOver metadata, and maximum-text selection/filter presentation are covered.
7. `PERF-RISK-13` — **Open**: production-size search, thumbnail, memory, and scroll profiling remains.
8. `GAP-MAIN-05-01` — **Open**: unlocked tap/keyboard/deletion/workspace/VoiceOver/Reduce Motion/bottom-clearance proof remains.

## Second opinion

Fable independently found the same destructive Catalyst selection, stale Saved Post count, cross-workspace filter/capture, raw workspace asymmetry, missing-route, repeated-search, Reduce Motion, and VoiceOver risks. Fable was advisory and made no edits.

## Classification and next gate

PAGE-MAIN-05 is closed as `Coverage gap`. All confirmed root source defects are repaired, representative required states were visually replayed, 611 iOS tests and 140 TypeScript tests pass, and both platform targets build. Reclassify only after the unlocked five-part pass is recorded.

## Creator feature record · 2026-08-19 · Section quick actions + in-app Save a post

Creator request: put "Add idea" and "Save a post" above their sections for easy access, phone and desktop.

- Idea Bank page: "Add idea" now sits directly under the Idea Bank section header (replacing the bottom "Save idea" button); phone's Saved Posts section always renders with "Save a post" under its header. Both hidden during multi-select. Desktop gets "Add idea" via the shared view and "Save a post" at the top of the Saved Posts library destination.
- New in-app save flow: `SavedPostLinkCapturePolicy` + `SavedPostLinkCaptureView` (SavedPostsLibraryView.swift). A pasted link goes through `InspirationLinkCanonicalizer` exactly like a share-extension capture (http upgraded, tracking junk stripped); a link already saved to the account reopens the existing reference instead of duplicating; the source lands as `.pending` and the existing thumbnail hydrator and review/analyze flow take over.
- Tests: `PageMain08Tests` +1 (canonicalize / per-account dedup / reject); full suite 638/0.
- Runtime replay: saved an Instagram link end-to-end on the simulator — "Post saved." notice, row appeared as "Saved Instagram post · Instagram · Waiting to analyze", section count incremented.
