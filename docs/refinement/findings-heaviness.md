# L2 · Heaviness findings (batch B2)

Lane L2. Every number below was measured this pass on the simulator **"iPhone 17"
(iOS 26.5, UDID `1F605047-4304-48C2-8DA0-1D5C72D585BC`)** — "iPhone 17 Pro" was in use by
lane L1. Build: the prebuilt Debug `agent.cy.app`. Raw data:
`docs/refinement/evidence/L2/`.

The archived one-second Home hang was **not** carried forward as a fact. It was
re-measured; what the measurements show is below.

---

## Census

### Whole-table `@Query`

**Every `@Query` in the app is unfiltered.** 245 declarations across 27 view files (251
including `App/RootView.swift`); `grep -rn '@Query(filter' ios/AgentCy` returns **0**. Scoping to the active workspace happens in Swift after the
whole table is fetched, through a `scoped(_:)` helper duplicated in nine files
(`HomeDashboardView.swift:1601`, `HomeDashboardView.swift:2004`, `PillarsView.swift:180`,
`PillarsView.swift:1363`, `TodayView.swift:29`, `WeeklyFocusView.swift:480`,
`AgendaView.swift:239`, `AgendaView.swift:2867`, `AskCyView.swift:579`).

Per root view and per sheet:

| View | Declaration site | Whole-table `@Query` |
|---|---|---|
| `AgendaView` | `Views/Agenda/AgendaView.swift:208`, `:2584`, `:2820` | 25 |
| `BrandCabinetView` | `Views/Brands/BrandCabinetView.swift:7` and five nested views | 18 |
| `TasksView` | `Views/Tasks/TasksView.swift:13`, `:96`, `:126`, `:461`, `:1306`, `:1941` | 17 |
| `SettingsSubpages` | `Views/Settings/SettingsSubpages.swift:171` and eight others | 17 |
| `HomeDashboardView` | `Views/Home/HomeDashboardView.swift:16-27`, `:2192` | 14 |
| `ResumablePostEditorView` | `Views/Brief/ResumablePostEditorView.swift:84-94`, `:3117` | 14 |
| `MCPBridgeSettingsView` | `Views/Settings/MCPBridgeSettingsView.swift:744` | 12 |
| `PillarsView` | `Views/Pillars/PillarsView.swift:162`, `:1345`, `:1955` | 12 |
| `TodayView` (**unreferenced**) | `Views/Today/TodayView.swift:9` | 10 |
| `AskCyView` | `Views/Cy/AskCyView.swift:536-545` | 10 |
| `WeeklyFocusView` | `Views/Agenda/WeeklyFocusView.swift:13`, `:462`, `:845` | 10 |
| `DesktopAppShellView` | `Views/Shell/DesktopAppShellView.swift:10-18` | 9 |
| `ScheduledPostDetailView` | `Views/Brief/ScheduledPostDetailView.swift:137-145` | 9 |
| `SettingsView` | `Views/Settings/SettingsView.swift:8-14`, `:454` | 8 |
| `PlanView` | `Views/Plan/PlanView.swift:73`, `:417` | 8 |
| `SocialGridView` | `Views/Feed/SocialGridView.swift:365-372` | 8 |
| `VoiceSparkView` | `Views/Capture/VoiceSparkView.swift:295-301` | 7 |
| `AgendaPostIdeaPickerView` | `Views/Agenda/AgendaPostIdeaPickerView.swift:73`, `:283` | 7 |
| `SavedPostsLibraryView` | `Views/Ideas/SavedPostsLibraryView.swift:204`, `:422` | 6 |
| `QuickCaptureView` | `Views/Capture/QuickCaptureView.swift:227-232` | 6 |
| `IdeaBankView` | `Views/Ideas/IdeaBankView.swift:203-207` | 5 |
| others (6 files) | — | 13 |

### Collections derived inside `body`

| Root view | Array-typed computed properties | `filter`/`sorted`/`map`/`compactMap`/`reduce`/`first(where:)` calls |
|---|---|---|
| `HomeDashboardView` | 29 | 71 |
| `PillarsView` | 24 | 41 |
| `AgendaView` | 22 | 101 |
| `AskCyView` | 15 | 52 |
| `DesktopAppShellView` | 12 | 40 |
| `TasksView` | 6 | 34 |
| `IdeaBankView` | 0 | 28 |
| `PlanView` | 0 | 9 |

### Lifecycle work on tab roots

| Root | `.onAppear` | `.task` | `.onChange` | `.onReceive` |
|---|---|---|---|---|
| `HomeDashboardView` | 1 | 13 | 2 | 1 |
| `TasksView` | 2 | 20 | 3 | 1 |
| `AskCyView` | 1 | 3 | 6 | 1 |
| `IdeaBankView` | 1 | 3 | 4 | 0 |
| `PillarsView` | 1 | 2 | 1 | 1 |
| `PlanView` | 1 | 0 | 2 | 1 |

Four-second polling loops: `AppShellView.swift:247`, `DesktopAppShellView.swift:150`,
`AskCyView.swift:711`, `MCPBridgeSettingsView.swift:103`. One-second loops:
`ActiveCreatorSessionFloatingTimer.swift:86`, `CreatorSessionView.swift:1747`.

### Observation scope

`AppModel` (`ViewModels/AppModel.swift:232`, 4,990 lines) is `@Observable` with 77 stored
properties. `@Observable` tracks per-property, so the 32 views that hold
`@Environment(AppModel.self)` are **not** all invalidated by every mutation. This is not a
finding; it is recorded so the shared-model size is not mistaken for the cause.

---

### L2H-01 The phone shell builds all six tab roots on every launch, and keeps all six mounted forever
- Where: `ios/AgentCy/Views/Shell/AppShellView.swift:61-83` and `:733-741`; all six tab-root slugs
- Evidence: six `NavigationStack`s sit in one `ZStack`; unselected tabs are only made invisible:
  ```swift
  func appTabLayer(_ tab: AppTab, selection: AppTab) -> some View {
      opacity(selection == tab ? 1 : 0)
          .allowsHitTesting(selection == tab)
          .accessibilityHidden(selection != tab)
  ```
  `docs/refinement/evidence/L2/launch-milestones.txt`: launching with Home selected and with Plan selected costs the same first-screen time (mean **553.5 ms** vs **532.5 ms**, warm) although `HomeDashboardView` declares 12 whole-table queries and 29 derived array properties and `PlanView` declares 8 and 0. Building only the selected tab would separate those numbers; they do not separate. In the same file, launching straight into `ResumablePostEditorView` **without** the shell (`RootView.swift:154-155`) costs **234–275 ms** of build against the shell's **363–400 ms**.
  On the cold path — first launches after install, freshly booted simulator — the gap between `app_model_ready` and `destination_app` was **1592 ms / 2474 ms / 1595 ms** over three runs, with total time to first screen **2213 / 3649 / 2305 ms**.
- Severity: blocker
- Fix: build the selected tab and keep at most the previously selected one alive. Wrap each layer so its content is `EmptyView()` until first selection, and drop it after a grace period; or move to a `TabView` and let SwiftUI manage the lifetimes. This is the precondition for L2H-02 mattering less: a tab that is not built runs no queries. Proof: re-run `launchtime.sh`; the Home-selected and Plan-selected build times must diverge, and warm first-screen must fall below 400 ms.
- Batch: B2
- Status: open

### L2H-02 Every `@Query` in the app fetches a whole table, then filters in Swift
- Where: 245 declarations across 27 view files (table above); the heaviest are `AgendaView.swift:208-218`, `TasksView.swift:461-466`, `HomeDashboardView.swift:16-27`, `ResumablePostEditorView.swift:84-94`
- Evidence: `grep -rn '@Query(filter' ios/AgentCy` returns **0 matches**; `grep -rn '@Query' ios/AgentCy/Views` returns 245. Workspace scoping is done afterwards in Swift, e.g. `HomeDashboardView.swift:36-42`:
  ```swift
  private var briefs: [CreativeBrief] { scoped(allBriefs) }
  private var outputs: [PlatformOutput] { scoped(allOutputs) }
  ```
  with `scoped` (`:1601`) delegating to `HomeWorkspaceScopePolicy.scoped`. So every SwiftData change notification re-materialises the full table for each of the twelve queries, on the main thread, and — because of L2H-01 — for all six tabs at once. `QuickCaptureView` repeats the pattern inline at `:288-298`.
- Severity: blocker
- Fix: give every `@Query` a `#Predicate` on `workspaceID` (the models already conform to `WorkspaceScopedRecord`) and a `fetchLimit` where the view shows a bounded list. `Home`'s "Up next" and "Today's tasks" cards do not need every brief and every task ever written. Shared change: one `@Query` initialiser helper next to `WorkspaceScope`, then the 245 sites. Proof: with a synthetic store of ~2,000 briefs/outputs/tasks, warm first-screen must not grow with row count; today it will.
- Batch: B2
- Status: open

### L2H-03 A sheet cannot begin to present until its body is built, and the post editor's body costs a quarter of a second
- Where: `ios/AgentCy/Views/Brief/ResumablePostEditorView.swift` (5,412 lines, 14 whole-table queries at `:84-94` and `:3117-3119`); presented from ten call sites — `HomeDashboardView.swift:684` and `:1273`, `QuickCaptureView.swift:325`, `ScheduledPostDetailView.swift:524`, `IdeaPostDraftView.swift:211`, `AgendaPostIdeaPickerView.swift:316`, `AskCyView.swift:768`, `MCPBridgeSettingsView.swift:839` and `:866`, `MCPDesktopReviewView.swift:133`; page slug `resumable-post-editor`
- Evidence: `docs/refinement/evidence/L2/launch-milestones.txt`, `editoronly` rows — `PreviewPostEditorRoot` (`RootView.swift:397-415`) builds nothing but a `NavigationStack` and `ResumablePostEditorView`, and takes **234, 251 and 275 ms** between `app_model_ready` and the first frame. On a phone that work runs on the main thread *before* iOS starts the sheet animation, so the creator sees the tap, then a pause, then the sheet. This — not a curve — is what Chey means by sheets feeling slow; the phone uses only native presentation (79 `.sheet(` call sites, 38 `presentationDetents`, 3 `fullScreenCover`, zero custom sheet drivers).
- Severity: major
- Fix: split the editor so its first frame needs only the record being edited: predicate the fourteen queries (L2H-02), move the series/episode-slot block (`:3117-3119`) behind the section that shows it, and render the media manager lazily. Proof: the same `editoronly` measurement must fall under 120 ms.
- Batch: B2
- Status: open

### L2H-04 Home and Cy render continuously while the creator does nothing
- Where: `ios/AgentCy/Views/Home/HomeDashboardView.swift:811`, `ios/AgentCy/Views/Cy/AskCyView.swift:918, 1211, 1387` → `ios/AgentCy/Design/DesignTokens.swift:1644-1680`
- Evidence: `docs/refinement/evidence/L2/idle-frames-by-tab.txt`. Ten seconds with no input at all: `home` 300 frames, `cy` 599 frames, `today` 1, `tasks` 1, `pillars` 1, `ideaBank` 1. Confirmed over a 12 s window in a second session: `home` 716 frames, `plan-week` 1. The four idle tabs contain no `CyAnimatedLogo`; Home and Cy do. `docs/refinement/evidence/L2/tab-switch-bursts.txt` also shows the app never returning to idle for the remaining 27 s of a session once Home or Cy has been visited, including while a sheet covers Home.
- Severity: blocker
- Fix: see `findings-motion.md` L2M-01 — the fix is a motion fix, but the cost is heaviness. Every frame Home renders competes with whatever the creator is scrolling, and on a phone it is battery spent on a decorative asterisk. Proof: the idle recording must return 1 frame per 10 s on all six tabs.
- Batch: B2
- Status: open

### L2H-05 A tab switch costs about half a second of continuous rendering
- Where: `ios/AgentCy/Views/Shell/AppShellView.swift:849`; all six tab roots, phone
- Evidence: `docs/refinement/evidence/L2/tab-switch-bursts.txt` — the three tab taps that landed on tabs which do settle produced continuous render bursts of **508 ms, 518 ms and 503 ms**. The tab pill is animated with `.snappy(duration: 0.32)`; the content layer is explicitly not animated. So roughly 320 ms is the declared animation and the remainder is the newly revealed tab's body work landing on the main thread.
- Severity: major
- Fix: L2M-03 (0.22 s `easeInOut` instead of a 0.32 s spring) plus L2H-01/L2H-02. Proof: the per-tap burst must fall under 260 ms.
- Batch: B2
- Status: open

### L2H-06 `refreshReminderSchedule` runs three times on every cold launch
- Where: `ios/AgentCy/App/RootView.swift:197`, `ios/AgentCy/Views/Shell/AppShellView.swift:225`, `ios/AgentCy/Views/Home/HomeDashboardView.swift:78`; plus `AgentCyApp.swift:131` on every foreground
- Evidence: twelve call sites of `refreshReminderSchedule(context:)` outside its own definition. Three of them are `.task` bodies that all run during a single cold launch: `RootView`'s root task, `AppShellView`'s task, and `HomeDashboardView`'s task. Each awaits `reminderService.authorizationStatus()` and then a full `reminderService.reconcile(context:now:)` over the store (`AppModel.swift:1010-1017`). `AgentCyApp.swift:131` adds a fourth on every `scenePhase == .active`, alongside `FocusTaskRecurrenceService.reconcile`, `WidgetSnapshotService.refresh` and `MCPBridgeService.sync` in the same block.
- Severity: major
- Fix: one owner. `RootView.task` already runs the full startup reconciliation (`RootView.swift:170-206`); delete the calls in `AppShellView.swift:225` and `HomeDashboardView.swift:78`, and debounce the `scenePhase` block so a quick app switch does not re-reconcile the whole store. Proof: instrument-free — the count of `reconcile` entries in one cold launch must drop from 3 to 1.
- Batch: B2
- Status: open

### L2H-07 `QuickCaptureView` re-evaluates a 2,374-line body, six whole-table queries and two workspace filters on every keystroke
- Where: `ios/AgentCy/Views/Capture/QuickCaptureView.swift:227-232` (queries), `:233-278` (46 `@State` properties in one view), `:286-298` (derived `pillars` and `socialAccounts`), `:303-315` (`body`); page slug `quick-capture`
- Evidence: the title, notes and task fields all bind to `@State` on the same view that owns `allPillars`, `profiles`, `destinations`, `formats`, `allSocialAccounts` and `workspaces`, and that computes:
  ```swift
  private var pillars: [Pillar] {
      allPillars.filter { WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces) }
  }
  ```
  SwiftUI re-runs `body` and both filters for every character. A per-keystroke cost could **not** be isolated on the simulator: the recording is dominated by the text caret's ~1 Hz blink and, in Quick Capture's case, by L2H-04 continuing to render Home behind the sheet (`evidence/L2/` raw `typing.mov`, `typing2.mov`). This finding therefore rests on the code, not on a timing.
- Severity: major
- Fix: move each capture kind's draft into its own small `@Observable` model or child view so a keystroke invalidates only the field's own subtree, and hoist `pillars`/`socialAccounts` out of `body` (compute once in `.task`/`.onChange(of: activeWorkspaceID)`). Proof needs a device: type ten characters with Instruments' SwiftUI template attached and compare `View Body` counts before and after — see gate G-device.
- Batch: B2
- Status: open

### L2H-08 `Views/Today/TodayView.swift` is unreferenced and carries ten whole-table queries
- Where: `ios/AgentCy/Views/Today/TodayView.swift:4-18`
- Evidence: `grep -rn 'TodayView' ios/AgentCy --include='*.swift'` returns exactly one line — its own declaration at `TodayView.swift:4`. Nothing constructs it. It duplicates `HomeDashboardView`'s query set and its own copy of `scoped(_:)` (`:29`).
- Severity: minor
- Fix: delete the file. It costs nothing at runtime, but it is a second copy of the pattern L2H-02 has to fix, and it will drift. Hand to the dead-code lane rather than fixing inside B2.
- Batch: B2
- Status: open

---

## What could not be measured, and why

- **Instruments.** `xcrun xctrace record --template 'Time Profiler' --device <sim udid>
  --attach <pid> --time-limit 30s` was run twice. Both attempts created the `.trace`
  directory, wrote 52 KB, and hung; each was killed after five minutes without producing a
  trace. There is therefore **no top-app-frames table** in this pass. Every number above
  comes from the app's own `RootLaunchDiagnostics` os_log milestones
  (`App/RootView.swift:43-86`) and from variable-frame-rate `simctl io … recordVideo`
  captures, where one frame equals one composited screen update.
- **Per-keystroke body cost** (L2H-07) and **Agenda week scrolling.** Both are drowned by the
  text caret's ~1 Hz blink in the frame-timing method, and by L2H-04 where Home is behind
  the sheet. They need `Self._printChanges()` or the Instruments SwiftUI template.
- **Scale.** `-agentCyPreviewData` seeds 34 records (`Preview/PreviewData.swift`, 485 lines):
  one idea, no saved posts. Every figure here is a floor. The cost of L2H-02 is proportional
  to the creator's own data and cannot be sized from this fixture; sizing it needs either a
  synthetic large store or Chey's device.

## Needs Chey's iPhone to settle (gate G-device)

- **Whether any of this crosses Instruments' hang threshold.** The contract's success
  criterion is "no hang above Instruments' hang threshold on Chey's iPhone in the core
  journeys". A 2.2–3.6 s cold launch and a 500 ms tab switch on an M-series simulator are
  not a device measurement. The archived one-second Home hang was re-measured here and is
  **not** reproduced as a hang; what reproduces is a Home screen that never stops rendering
  (L2H-04) and a 1.6–2.5 s cold-launch shell build (L2H-01).
- **L2H-07 per-keystroke cost** — needs the SwiftUI Instruments template on device.
- **L2H-02 at real data volume** — needs her store, or her sign-off on a synthetic one.
- **Battery and thermals from L2H-04** — only observable on device over a real session.
