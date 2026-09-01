# Page purpose (lane L3)

Built this pass from `ios/AgentCy`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, and the slugs in
`docs/refinement/01-page-inventory.md`. Nothing here is seeded from `docs/archive/`.

"Entry points" is the number of places in `ios/AgentCy` that construct the view (measured with
`grep -rn '\bViewName(' AgentCy`, excluding the declaration). It is a proxy for how many ways a
creator can arrive, not a count of taps.

Chey decides every keep/merge/hide. This document only recommends.

---

## 1. The three PRD jobs, and where they live

| PRD job | Surfaces that carry it |
|---|---|
| **Ideation** — capture a spark, share a post, ask Cy for three directions | `creation-hub`, `quick-capture`, `voice-spark`, `inspiration-review`, `idea-bank`, `saved-posts-library`, `idea-post-draft`, `cy` |
| **Creation** — develop one direction into a brief | `post-editor-spark-development` (Build with Cy), `post-proposal-review`, `resumable-post-editor` |
| **Execution** — schedule, produce, track, publish manually | `plan-week`, `day-agenda`, `daily-focus-detail`, `tasks`, `task-detail`, `post-reschedule`, `scheduled-post-detail`, `feed-grid`, `day-agenda-add-live-post`, `pillars` |
| **No PRD job** | `home` (a mirror of the other five tabs), `brand-cabinet` family (PRD defers brand-deal management), `creator-session` family (hard-disabled), the series family (`post-editor-series-*`, `episode-slot-actions`) which the PRD navigation never mentions |

---

## 2. Purpose matrix

Format per row: **job in the creator's words** · PRD job · the one thing only it does · what overlaps
it · entry points · recommendation.

### Tab roots

**`home`** — "Show me what today looks like without making me go anywhere."
PRD: none of the three directly; it is a launcher.
Only it does: nothing. Every one of its fifteen cards is a projection of another tab
(`HomeDashboardView.swift:1769-1785`): `scheduledToday`/`weekAhead`/`nextWeek`/`weekAtAGlance`/`pastDuePosts`
are `plan-week`; `tasks` is `tasks`; `recentIdeas`/`draftsInProgress`/`continueWorking` are `idea-bank`;
`pillarUsage` is `pillars`; `recentlyPosted` is `feed-grid`; `brandCabinet` is `brand-cabinet`;
`weeklyFocus` is `weekly-focus-setup`; `consistency` is `consistency-goal-editor`; `cyNoticed` is `cy`.
Overlaps: all five other tabs.
Entry points: 2 (phone shell, desktop sidebar).
**Recommendation: keep, but trim.** Fluff is the second copy of the week (`weekAhead` + `nextWeek` +
`weekAtAGlance` are three renderings of the same seven days that `plan-week` already owns) and
`recentlyPosted`, which is `feed-grid` in miniature. A launcher earns its place only if it is shorter
than the thing it launches.
Tradeoff: card reordering is a shipped affordance; cutting cards removes choices a creator may already
have arranged.
Flips it: if beta testers reorder cards and end up with a Home that is *not* the union of the other
tabs, the redundancy is a feature and Home should keep all fifteen.

**`plan-week`** — "Where does the week's work sit?"
PRD: Execution, and it is the PRD's *Agenda*.
Only it does: move a week at a time and separate planned posts from production tasks per day.
Overlaps: `home`'s week cards; the calendar and list modes inside `AgendaView` overlap `tasks`' list.
Entry points: 2.
**Recommendation: keep as is.** The PRD's Agenda maps onto it cleanly.
Note: the tab is `AppTab.today` in code but titled "Plan" (`DomainTypes.swift:1352, 1362`), while the
PRD's "Today" is what ships as `home`. See L3-14.

**`tasks`** — "What is the next concrete step, across everything?"
PRD: Execution.
Only it does: show brief-linked and standalone tasks together with lane/priority/date filters.
Overlaps: `home`'s `tasks` card, `day-agenda`'s task rows, `daily-focus-detail`'s task collection.
Entry points: 2.
**Recommendation: keep as is.**

**`pillars`** — "Is my mix balanced?"
PRD: Execution (pillars section).
Only it does: anchor/branch structure, colour, and assigned weekdays.
Overlaps: `home`'s `pillarUsage` card only.
Entry points: 2.
**Recommendation: keep as is.** The cleanest single-job tab in the app.

**`idea-bank`** — "Where do ideas live before they are posts?"
PRD: Ideation.
Only it does: hold unscheduled sparks, and (phone only) list shared-in inspiration.
Overlaps: `home`'s `recentIdeas`/`draftsInProgress`; `saved-posts-library`, which is a filtered view of
the same `InspirationSource` records.
Entry points: 2.
**Recommendation: keep as is on phone.** On desktop it is currently *not* the same page — the
inspiration list is compiled out (`IdeaBankView.swift:253-255`), so the desktop Idea Bank cannot show a
shared link at all. Fix that before judging the merge (L3-04).

**`cy`** — "Talk to Cy about my own work."
PRD: Ideation, plus the assistance modes.
Only it does: free-form conversation with context, and the MCP review queue.
Overlaps: `post-editor-spark-development` is a second, brief-scoped Cy conversation with its own
transcript, composer, archive action and 8-turn cap.
Entry points: 4 (phone tab, desktop sidebar, `ask-cy-sheet` from either shell).
**Recommendation: keep as is, but stop presenting it modally over itself.** See L3-01/L3-02: on iPhone
the modal instance has no close control and the review queue replaces the transcript.

### Secondary surfaces the brief asks about

**`feed-grid`** — "What will my profile look like?"
PRD: not named in the navigation section. Nearest is Execution/tracking.
Only it does: render planned + live posts in an Instagram 3-up grid.
Overlaps: `home`'s `recentlyPosted`; `day-agenda-add-live-post` is reachable from both.
Entry points: 2 constructions, but different kinds per form factor — a **top-level sidebar tab on
desktop** and a **push behind an icon in the `plan-week` header on phone** (`PlanView.swift:143`).
**Recommendation: keep, secondary on both.** It does not earn a top-level place: it is read-only,
Instagram-only, and only meaningful once posts are live. Demote the desktop sidebar entry to a push
from `plan-week` so both shells agree.
Tradeoff: the desktop sidebar has room; demoting costs a click for the person most likely to use it
(desktop planning).
Flips it: if the grid becomes the place live URLs are entered in bulk, it earns the tab.

**`saved-posts-library`** — "Show me every external post I saved."
PRD: Ideation ("share one HTTPS post link… Saved Posts").
Only it does: the full, filterable list of `InspirationSource` records. `idea-bank` shows a preview of
the same records.
Entry points: 2 — desktop sidebar tab, phone push from `idea-bank` (`IdeaBankView.swift:270`).
**Recommendation: merge into `idea-bank` as a filter, on both form factors.** It is a filtered view of
data the Idea Bank already lists; the phone already treats it that way (preview + "see all"), and the
desktop promotes the child above the parent while hiding the parent's own copy of the list.
Tradeoff: the library has multi-select delete and link capture that would have to move into Idea Bank's
existing multi-select mode.
Flips it: if analysis state (shaping / ready / failed) needs its own review queue with per-item retry,
that is a real second job and it stays.

**`brand-cabinet`** (with `brand-partner-detail`, `brand-partner-editor`, `brand-contact-editor`,
`brand-activity-editor`, `brand-post-link-picker`, `brand-import-review`, `settings-brand-partnerships`)
— "Track partner relationships and collab posts."
PRD: **explicitly deferred** (`PRD.md:126`, "Teams and brand-deal management").
Only it does: partners, contacts, activity log.
Entry points: 2 — a `home` card gated on `showsBrandDealsInPostEditor` and a settings subpage
(`BrandCabinetView.swift:1212`). It has no tab and no sidebar destination.
**Recommendation: hide behind the existing setting, default off, and leave it out of beta.** Seven
surfaces and a settings page for a feature the PRD defers is the largest single block of scope in the
app that no beta tester was promised.
Tradeoff: it already works and is already opt-in; hiding it is nearly free but wastes shipped work.
Flips it: Chey wanting brand deals in the beta story. That is a PRD change and hers alone.

**`creator-session`** (with `creator-session-timer-fullscreen`, `creator-session-floating-timer`,
`ActiveCreatorSessionFloatingTimer`, `CreatorSessionActivity`) — "Focus timer for heads-down creating."
PRD: not mentioned.
**It is unreachable.** `CreatorSessionFeatureAvailability.isEnabled` is a `static let … = false`
(`AgentCyShared/CreatorSessionActivity.swift:10-12`), and every call site is gated on it
(`AppShellView.swift:98,174`, `DesktopAppShellView.swift:121,134`, `AppModel.swift:370`,
`ScheduledPostDetailView.swift:228`), with `RootView.swift:176-181` actively retiring any live activity
on launch.
Entry points: 0 in a shipping build.
**Recommendation: remove, or state a date.** It earns no place — top-level or secondary — because it
has no place at all today. This is a dead-code decision for Chey, not a design one.
Flips it: a decision to ship the timer in beta, which would need the flag flipped and the surface
re-reviewed (it is one of only two 48pt close-control users, per the L1 census).

**Series** (`post-editor-series-planner`, `post-editor-series-detail`, `post-editor-series-details-editor`,
`post-editor-add-future-episodes`, `episode-slot-actions`, `settings-mcp-episode-review`,
`ask-cy-review-series`) — "Run a recurring show."
PRD: not in the navigation section; the lifecycle section does not mention episodes.
Only it does: recurring slots and per-episode briefs.
Entry points: reached only from inside `resumable-post-editor` and from MCP review.
**Recommendation: keep, secondary, exactly where it is.** It is correctly buried inside the post editor
and never competes for a tab. Its `episode-slot-actions` flow is the best-behaved error surface in the
app (inline messages, `context.rollback()` on every failure — `AgendaView.swift:2779-2800`) and is worth
copying elsewhere.
Flips it: nothing found this pass.

### Surfaces the inventory did not list, found while tracing

**`today` (`Views/Today/TodayView.swift`)** — an entire second daily page with its own header, focus
section, task list and quick-capture actions. It is **referenced nowhere**: `grep -rn "TodayView" AgentCy
AgentCyTests AgentCyWidgets AgentCyShared` returns only its own declaration at line 4.
**Recommendation: delete** (see L3-12). It duplicates `home` + `daily-focus-detail`.

**`scheduled-post-detail` (`ScheduledPostDetailView`, `ScheduledPostDetailView.swift:130`)** — the
read-mostly page for a scheduled or posted output, with its own inline editor, media manager, reschedule
sheet and posted-date flow. The inventory names it in the close-control census but gives it no row.
Entry points: 3 (`RootView.swift:385` preview fixture, `SocialGridView.swift:928`, and the
`PostOutputDetailView` router at `ScheduledPostDetailView.swift:21`).

**`post-output-detail` (`PostOutputDetailView`, `ScheduledPostDetailView.swift:7`)** — not a page, a
router: it picks between `idea-post-draft` and `scheduled-post-detail`. 14 call sites.

---

## 3. The "one post" family — the biggest consolidation question

Four types answer "show me this post":

| Type | File:line | Role | Call sites |
|---|---|---|---|
| `PostOutputDetailView` | ScheduledPostDetailView.swift:7 | router only | 14 |
| `IdeaPostDraftView` | IdeaPostDraftView.swift:129 | idea / early draft | 13 |
| `ResumablePostEditorView` | ResumablePostEditorView.swift:77 | the editor | **15** |
| `ScheduledPostDetailView` | ScheduledPostDetailView.swift:130 | scheduled / posted | 3 |

`ResumablePostEditorView` is constructed at fifteen sites, each configuring its own chrome through
`contextLabel`, `showsEditorChrome`, `isReviewEditing`, `bottomActionClearance` and a bespoke toolbar —
so "the post editor" looks and closes differently depending on which of the fifteen doors you used.
`SocialGridView.swift:928` skips the router entirely and pushes `ScheduledPostDetailView` directly.

**Recommendation: keep all four types, but route through `PostOutputDetailView` from every site and
give the editor one chrome contract.** This is a shared change. Sites it touches: every construction of
`ResumablePostEditorView` (RootView.swift:405, QuickCaptureView.swift:325, HomeDashboardView.swift:684 and :1273,
MCPBridgeSettingsView.swift:839 and :866, MCPDesktopReviewView.swift:133, IdeaPostDraftView.swift:211,
ScheduledPostDetailView.swift:524, ResumablePostEditorView.swift:3344, AgendaView.swift:361, :1536
and :3054, AskCyView.swift:768, AgendaPostIdeaPickerView.swift:316) plus `SocialGridView.swift:928`.
Tradeoff: one chrome contract means one of the fifteen contexts loses a bespoke affordance.
Flips it: evidence that a specific context (MCP "edit before approval", say) genuinely needs a
different close semantic — it does, and that argues for two named modes rather than fifteen ad-hoc ones.

---

## 4. The six-tab phone IA against the PRD

The PRD's navigation section names, in order: **Today, Agenda, Tasks, Platforms, Pillars, Idea Bank,
Ask Cy, `+`.**

What ships on the phone (`AppShellView.swift:62-81`, `DomainTypes.swift:1350-1377`):

| Position | Code | Title | PRD name |
|---|---|---|---|
| 1 | `.home` | Home | **Today** |
| 2 | `.today` | Plan | **Agenda** |
| 3 | `.tasks` | Tasks | Tasks |
| 4 | `.pillars` | Pillars | Pillars |
| 5 | `.ideaBank` | Idea Bank | Idea Bank |
| 6 | `.cy` | (asterisk) | Ask Cy |
| — | `+` | Create | `+` |

Verdict on the six tabs: **the set is right and matches the PRD one-for-one.** Two vocabulary problems,
no structural ones:

1. The PRD's *Today* ships as *Home*, and the PRD's *Agenda* ships as *Plan* — while the enum case for
   Plan is literally `.today`. Three names for two pages. Pick one vocabulary and make the PRD, the tab
   titles and the enum agree (L3-14).
2. *Platforms* has no tab, correctly: the PRD says it "replaces Post versions", and it ships as a
   section inside `resumable-post-editor`. The PRD navigation entry is misleading; fix the document.

The five surfaces the brief asks about, judged against a top-level place:

| Surface | Top-level? | Secondary? | Why |
|---|---|---|---|
| `feed-grid` | No | **Yes** | Read-only, one platform, only meaningful post-publish. Desktop currently gives it a sidebar tab it has not earned. |
| `saved-posts-library` | No | **Yes, as an Idea Bank filter** | Same records the Idea Bank already lists. Desktop promotes it to a tab while hiding the parent's own list — exactly backwards. |
| `brand-cabinet` | No | **Only behind its setting** | PRD-deferred scope. |
| `creator-session` | No | **No** | Hard-disabled; not reachable at all. |
| Series | No | **Yes, inside the post editor** | Correctly buried; never competes for navigation. |

The desktop shell carries **eight** sidebar destinations (`DesktopAppShellView.swift:1601-1636`: home,
plan, feed, tasks, ideaBank, savedPosts, pillars, cy) against the phone's six. The two extras are the
two surfaces above that should be secondary. Bringing desktop to six would make one IA instead of two
and would remove the desktop-only mismatch where `saved-posts-library` is a tab but the Idea Bank's own
inspiration list is compiled out.

---

## 5. Consolidation shortlist

| Candidate | Recommendation | Rationale | Tradeoff | What would flip it |
|---|---|---|---|---|
| `today` (`TodayView`) | **Delete** | Unreferenced anywhere in the app; duplicates `home` + `daily-focus-detail`. | None found. | A plan to make it a real page. |
| `creator-session` family | **Remove or date it** | `isEnabled = false`; zero reachable entry points. | Loses shipped work. | Chey deciding the timer ships in beta. |
| `brand-cabinet` family (7 surfaces + settings page) | **Hide behind its setting, default off, out of beta** | PRD explicitly defers brand-deal management. | Working, opt-in feature goes unused. | Chey putting brand deals in the beta story (a PRD change). |
| `saved-posts-library` | **Merge into `idea-bank` as a filter** | Filtered view of the same records; phone already models it that way. | Multi-select delete + link capture must move. | A real per-item analysis review queue with retry. |
| `feed-grid` desktop sidebar tab | **Demote to a push from `plan-week`** | Matches the phone; the grid is read-only and single-platform. | Costs desktop planners one click. | The grid becoming the bulk live-URL entry point. |
| Home's `weekAhead` + `nextWeek` + `weekAtAGlance` | **Trim to one** | Three renderings of the seven days `plan-week` owns. | Removes cards a creator may have ordered. | Testers arranging a Home that is not a mirror. |
| Home's `recentlyPosted` | **Trim** | `feed-grid` in miniature. | Same. | Same. |
| `post-editor-spark-development` vs `cy` | **Keep both, share the transcript component** | Two conversation UIs with two composers, two archive actions, two close controls (one of them the app's 11th bespoke close, `DevelopBriefView.swift:127-135`). Shared change: one `CyTranscript` component used by `AskCyView` and `DevelopBriefView`. | A brief-scoped chat has different affordances (starters, post context card). | Nothing found; the duplication is real. |
| `PlanNavigationRoute.dailyFocusDetail` | **Delete the route** | Dead second entry appended only under `#if DEBUG`; the live path is `day-agenda` → Focus. | None. | A product decision to put Focus one tap from the Plan header. |

---

## 6. Resolving the inventory's `daily-focus-editor` question

The inventory flagged `daily-focus-editor` as reachable only through a DEBUG fixture. **That is not
correct, and the real answer is more interesting.**

- `DailyFocusEditorView` has a production entry: `daily-focus-detail` renders an "Edit" toolbar item on
  phone (`WeeklyFocusView.swift:520-521`) and an "Edit" button in the desktop rail
  (`WeeklyFocusView.swift:633-634`), both opening `.sheet(isPresented: $showFocusEditor)` at
  `WeeklyFocusView.swift:525-526`. Captured on the simulator:
  `docs/refinement/evidence/flows/L3-03-daily-focus-detail.png`.
- `daily-focus-detail` itself is reachable in production, but **not by the route the inventory names**.
  `PlanNavigationRoute.dailyFocusDetail` (`PlanView.swift:11, 62`) is appended at exactly one site —
  `AppShellView.swift:234`, inside `#if DEBUG`. The live path is `plan-week` → week row → `day-agenda` →
  the "Focus" showcase control (`AgendaView.swift:3268-3271`), present on both form factors.

So: both pages ship, and the fixture route is dead code beside a live one. Filed as L3-11.
