# Findings: cohesion and flows (lane L3, batch B3)

Every finding below was produced this pass from `ios/AgentCy` on branch `refinement/pre-beta`, or
reproduced on a booted **iPhone 17e** simulator (`02BD778D-4257-412B-96D5-196A7F9A512A`) with the Debug
build at
`…/scratchpad/DerivedData/Build/Products/Debug-iphonesimulator/agent.cy.app`.
Nothing is seeded from `docs/archive/`.

Simulator evidence lives in `docs/refinement/evidence/flows/`. The `L3-A*` and `L3-B*` artefacts come
from a throwaway XCUITest driver written under the session scratchpad (`scratchpad/L3Driver`, not in the
repo) that drives the installed app by bundle id; both probes pass on current code, which is what makes
them evidence.

Counts: **4 blockers, 12 major, 6 minor.**

---

## Blockers

### L3-01 The Ask Cy sheet has no close control on iPhone, and the MCP poller opens it unprompted
- Where: `cy` presented as `ask-cy-sheet`, phone, both appearances. `ios/AgentCy/Views/Cy/AskCyView.swift:1274-1295`; presented at `ios/AgentCy/Views/Shell/AppShellView.swift:183`; raised automatically by `ios/AgentCy/ViewModels/AppModel.swift:364-367` from `ios/AgentCy/Views/Shell/AppShellView.swift:411-445`.
- Evidence: the close control is inside `#if targetEnvironment(macCatalyst)` —
  ```
  1274:            #if targetEnvironment(macCatalyst)
  1275:            if showsCloseButton {
  1276:                Button(action: dismiss.callAsFunction) {
  ```
  so the `showsCloseButton` parameter (`AskCyView.swift:585-588`) is inert on iOS, and `AppShellView.swift:183` (`case .askCy: AskCyView()`) does not pass it anyway. Reproduced on the simulator: launching with `-agentCyPreviewData -agentCyPreviewTab cy -agentCyPreviewSheet askCy` yields a full-height Cy sheet whose accessibility tree contains **no element labelled "Close" anywhere** — `docs/refinement/evidence/flows/L3-B1-tree-askcy-sheet.txt` (a case-insensitive grep for "close" returns nothing), screenshot `docs/refinement/evidence/flows/L3-B1-askcy-sheet-over-askcy-tab.png`. Probe `L3FlowProbes.testAskCySheetHasNoCloseControlOnPhone` passes.
- Severity: blocker
- Fix: move the close control out of the `#if targetEnvironment(macCatalyst)` block so `showsCloseButton` works on both form factors, and pass `showsCloseButton: true` at `AppShellView.swift:183`. Use `AgentToolbarIconButton(title: "Close", icon: .close)` so it joins close-control family CC-A rather than adding an eleventh. Sites touched: `AskCyView.swift:1274-1303`, `AppShellView.swift:183`, `DesktopAppShellView.swift:75`.
- Batch: B3
- Status: open

### L3-02 On iPhone a pending MCP request replaces the entire Cy conversation; the fix shipped to Catalyst only
- Where: `cy` (tab and sheet), phone. `ios/AgentCy/Views/Cy/AskCyView.swift:649-659` and `:2153-2161`.
- Evidence:
  ```
  651:             } else {
  652:                 // Desktop keeps the conversation. A queue used to replace the
  653:                 // whole feed, so Cy was unusable until every item was cleared.
  654:                 // Reviews are opened deliberately from the banner instead.
  655:                 #if targetEnvironment(macCatalyst)
  656:                 conversationContent
  657:                 #else
  658:                 pendingReviewContent
  659:                 #endif
  ```
  and the composer goes with it: `showsConversation` returns `pendingReviews.isEmpty && !showReviewCompletion` on non-Catalyst (`AskCyView.swift:2153-2161`), gating `if showsConversation { composer }` at `:669`. The comment records that this exact defect was already found and fixed — for the internal form factor only. Composed with L3-01, the shipping behaviour is: a 4-second poller raises a modal over the creator's work, that modal shows a review queue instead of Cy, and it has no visible way out.
- Severity: blocker
- Fix: apply the same treatment on phone — keep `conversationContent`, and surface the queue as a banner above the composer that opens the review deliberately. The desktop banner (`desktopReviewBanner`, `AskCyView.swift:2165+`) is the component; make it unconditional and drop both `#if` branches at `:655-659` and `:2154-2160`.
- Batch: B3
- Status: open

### L3-03 No flow survives being backgrounded: there is no `.background` scene-phase handler in the app
- Where: whole app, both form factors. `ios/AgentCy/App/AgentCyApp.swift:124-131`, `ios/AgentCy/Views/Shell/AppShellView.swift:264-267`, `ios/AgentCy/Views/Home/HomeDashboardView.swift:68`, `ios/AgentCy/Views/Tasks/TasksView.swift:638`, `ios/AgentCy/Views/Plan/PlanView.swift:103`, `ios/AgentCy/Views/Pillars/PillarsView.swift:279`.
- Evidence: `grep -rn "scenePhase" ios/AgentCy` returns six observers and every one begins `guard phase == .active else { return }` — e.g. `AgentCyApp.swift:124-125`:
  ```
  124:                .onChange(of: scenePhase) { _, phase in
  125:                    guard phase == .active else { return }
  ```
  Unsaved state is written only in `onDisappear`, which does not run on backgrounding or termination: `QuickCaptureView.swift:447-453` (`updateSavedIdeaFromForm` → `finalizeQuickPostDraft` → `preserveUnfinishedDrafts`), `ResumablePostEditorView.swift:409-417` (`persistChanges`), `DailyFocusDetailView` (`WeeklyFocusView.swift:532`, `flushPendingDetailsSave`). `PostProposalReviewView` has no exit persistence at all (see L3-06). So an idea typed in `quick-capture`, a title typed in `resumable-post-editor`, a focus note in `daily-focus-detail` and every edit in `post-proposal-review` are lost if iOS terminates the app in the background — which it routinely does.
- Severity: blocker (data is at risk; this is the contract's "the five core flows … survive relaunch")
- Fix: shared change. Add a single `.onChange(of: scenePhase)` at `AgentCyApp.swift:124` that also handles `.background` / `.inactive` by broadcasting one notification (e.g. `.agentCyShouldFlushDrafts`), and have each draft-owning view flush on it with the same closure it already runs in `onDisappear`. Sites touched: `AgentCyApp.swift:118-132`, `QuickCaptureView.swift:447-453`, `ResumablePostEditorView.swift:409-417`, `PostProposalReviewView.swift` (new), `WeeklyFocusView.swift:532`, `VoiceSparkView.swift:386-390`, `DevelopBriefView.swift` (composer text).
- Batch: B3
- Status: open

### L3-04 A link shared into the app from another app is never acknowledged on iPhone
- Where: share-extension import, phone. `ios/AgentCy/Views/Shell/AppShellView.swift:224-231` and `:239-245` against `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:142` and `:147`; behaviour at `ios/AgentCy/ViewModels/AppModel.swift:1112-1120`.
- Evidence: the phone shell passes `presentsImportedSource: false` at both call sites —
  ```
  226:            appModel.importPendingInspiration(
  227:                context: modelContext,
  228:                presentsImportedSource: false
  229:            )
  ```
  while the desktop shell uses the default `true` (`DesktopAppShellView.swift:142`, `:147`), which selects the Idea Bank tab and opens `inspiration-review` (`AppModel.swift:1118-1119`). The import itself succeeds either way, so the record exists — the creator is simply never told. It compounds on desktop, where the Idea Bank's inspiration list is compiled out (`IdeaBankView.swift:253-255`: `#if !targetEnvironment(macCatalyst)`), so the auto-opened review is the *only* place a desktop creator ever sees it. The two shells are exact mirror-image mistakes.
- Severity: blocker (this is one of the PRD's three ideation paths, `PRD.md:54`, and on the shipping platform it produces no visible result)
- Fix: on phone, either present `inspiration-review` on import (match desktop) or, if the review must not interrupt, post an `activity-center` entry plus a badge and land the creator in `idea-bank`. On desktop, remove the `#if !targetEnvironment(macCatalyst)` at `IdeaBankView.swift:253-255` so the list exists on both. Sites touched: `AppShellView.swift:224-231`, `:239-245`, `IdeaBankView.swift:253-255`, and `NotificationActivityCenterView` if the badge route is chosen.
- Batch: B3
- Status: open

---

## Major

### L3-05 Quick Add opens Quick Capture as a nested sheet on phone, with a close control that lies about where it goes
- Where: `creation-hub` → `quick-capture`, phone, both appearances. `ios/AgentCy/Views/Capture/CreationHubView.swift:34-52` against `:19-33`; label logic at `ios/AgentCy/Views/Capture/QuickCaptureView.swift:373-380`.
- Evidence: the desktop branch swaps the hub's content in place —
  ```
  23:             } else if showQuickCapture {
  24:                 QuickCaptureView(onExit: returnToCreationHub)
  ```
  — while the phone branch stacks a second sheet on the first:
  ```
  38:             .sheet(isPresented: $showQuickCapture) {
  39:                 QuickCaptureView()
  ```
  With `onExit == nil`, `QuickCaptureView.swift:375-379` picks the **"Close" / X** branch instead of **"Back to Quick Add" / chevron**, so the control says "close the app's capture" and actually returns to the Quick Add menu. Reproduced: `docs/refinement/evidence/flows/L3-A2-tree-quick-capture-nested.txt` shows two live `Close` buttons in one window — `{{37.8, 76.1}, {40.8, 40.8}}` (the hub, still behind) and `{{20.0, 73.0}, {44.0, 44.0}}` (Quick Capture) — with a `Sheet Grabber` between them; `L3-A2-quick-capture-nested.png` and `L3-A4-back-in-quick-add-after-close.png` show the entry and the landing. Probe `L3FlowProbes.testQuickAddNestedSheetDeadEnd` passes, asserting `Back to Quick Add` is absent. Leaving takes two dismissals.
- Severity: major
- Fix: make the phone match the desktop — replace the hub's content in place rather than stacking, i.e. use the same `Group { if showLivePost … else if showQuickCapture … }` shape for both, passing `onExit: returnToCreationHub` so the label is correct. Sites touched: `CreationHubView.swift:18-52` (both branches collapse to one), and the three nested sheets at `:38`, `:42`, `:48`.
- Batch: B3
- Status: open

### L3-06 Closing the Cy post review with the X silently throws away every edit, while "Discard post" asks first
- Where: `post-proposal-review`, both form factors. `ios/AgentCy/Views/Brief/PostProposalReviewView.swift:167-169` against `:157-159` and `:172-190`.
- Evidence: every field on the page binds to `@State private var proposal: BriefProposal` (`:9`, seeded at `:20-30`). The destructive-looking action confirms:
  ```
  157:                    Button(revisionProposal == nil ? "Discard post" : "Keep current post", role: …) {
  158:                        confirmDiscard = true
  ```
  The toolbar X does not:
  ```
  167:                ToolbarItem(placement: .cancellationAction) {
  168:                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
  ```
  There is no `onDisappear` persistence in the file. The stored `PendingBriefProposal` still holds the pre-edit payload (`AppModel.swift:2584-2598`), so reopening Build with Cy re-presents the original text and the creator's rewrite is gone. The safe-looking control destroys more than the one labelled destructive.
- Severity: major
- Fix: give the X the same contract as "Discard post" — either persist the edited proposal back over `PendingBriefProposal` on dismiss, or route the X through `confirmDiscard` when the proposal differs from the one it was seeded with. Preferred: persist, so the review is resumable like every other draft in the app.
- Batch: B3
- Status: open

### L3-07 Cy's "Create this post" chip can create the same post twice, because its done-state is not persisted
- Where: `cy`, both form factors. `ios/AgentCy/Views/Cy/AskCyView.swift:570`, `:2338-2343`, `:1655-1676`.
- Evidence: the guard is in-memory —
  ```
   570:    @State private var sentToPostMessageIDs: Set<UUID> = []
  2338:    private func canSendResponseToPost(_ message: ConversationMessage) -> Bool {
  2339:        CyPostCreationPolicy.canCreate(
  2340:            actionKind: message.proposedActionKind,
  2341:            referencedBriefID: message.referencedBriefID,
  2342:            alreadyCreated: sentToPostMessageIDs.contains(message.id)
  ```
  and the chip's label is driven by the same set (`:1659`, `:1673`). The sibling **task** chip on the same message solves this correctly with a persistent query:
  ```
  2352:    private func taskWasAdded(from message: ConversationMessage) -> Bool {
  2353:        tasks.contains { $0.sourceConversationMessageID == message.id }
  ```
  After a relaunch, a workspace switch, or anything that re-creates the view, the post chip resets to "Create this post" while the task chip stays "Task added" — so the creator gets a duplicate brief and output from one Cy answer. Two chips on the same message with two different idempotence models.
- Severity: major
- Fix: replace `sentToPostMessageIDs` with the same persistent test the task chip uses — record the originating message on the created brief (a `sourceConversationMessageID` on `CreativeBrief`, mirroring `CreatorTask`) and derive `alreadyCreated` from `briefs.contains { … }`. Sites touched: `AskCyView.swift:570, 1659, 1673, 2338-2343, 2391-2430`, `AppModel.createPostDraftFromCyResponse` (`:1547-1577`), plus the model.
- Batch: B3
- Status: open

### L3-08 A failed or cancelled Ask Cy turn strands the creator's message with no retry and does not give back what they typed
- Where: `cy`, both form factors. `ios/AgentCy/Views/Cy/AskCyView.swift:2269-2331`, against `ios/AgentCy/Views/Brief/DevelopBriefView.swift:483-502`.
- Evidence: `send()` clears the composer and commits the turn before the request starts —
  ```
  2280:        prompt = ""
  …
  2287:        thread.turnCount += 1
  2288:        thread.updatedAt = Date()
  2289:        try? context.save()
  ```
  and on failure `askCy` returns `nil` (`AppModel.swift:3877-3882`) with nothing inserted and nothing restored. `stopSending()` (`:2324-2331`) cancels the task and clears the flags, and a reply that lands after cancellation is dropped by `guard !Task.isCancelled else { return }` at `:2302`. `grep -n "Try again\|Retry\|retry\|resend" AskCyView.swift` returns nothing. The turn is spent, the message sits unanswered, and the only recovery is retyping. `DevelopBriefView` gets this right on the same kind of failure:
  ```
  494:            if !succeeded, self.answer.isEmpty {
  495:                self.answer = answer
  496:            }
  ```
- Severity: major
- Fix: mark the creator message as unanswered when the turn fails or is cancelled and render a "Try again" affordance on it that re-sends without spending a second turn; restore `prompt` on failure, matching `DevelopBriefView.swift:494-496`. Do not increment `thread.turnCount` until a reply is committed.
- Batch: B3
- Status: open

### L3-09 The app's only error channel has no presenter inside a sheet, and most errors are raised from inside sheets
- Where: whole app, both form factors. `ios/AgentCy/Views/Shell/AppShellView.swift:208-214` and `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:100-106` are the only two presenters.
- Evidence: `grep -rn "notice != nil" ios/AgentCy` returns exactly those two lines; `grep -rn "notice = \." ios/AgentCy | wc -l` returns **204** write sites. Many are inside sheet-presented surfaces where the shell's `.alert` is covered: `VoiceSparkView.swift:924` ("The post was created, but the recording could not be attached."), `ResumablePostEditorView.swift:2475-2478` ("Name the post before saving it." / "That post could not be saved."), `AppModel.schedule` failures surfaced from `post-reschedule` (`AgendaView.swift:4086-4098`), `AppModel.acceptProposal`'s five validation notices (`AppModel.swift:2503-2521`) raised from `post-proposal-review`. The one flow that does this correctly renders its errors inline in its own surface with a rollback — `EpisodeSlotActionsView.perform` (`AgendaView.swift:2779-2800`).
- Severity: major
- Fix: shared change. Give the notice channel a presenter that follows the topmost presentation — either an `.agentNotice()` view modifier applied inside every sheet root, or a scene-level overlay window. Adopt `EpisodeSlotActionsView`'s inline-message pattern for the surfaces whose errors are about the form in front of the creator. Sites touched: `AppShellView.swift:208-214`, `DesktopAppShellView.swift:100-106`, and every sheet root that raises a notice (`QuickCaptureView`, `VoiceSparkView`, `ResumablePostEditorView`, `PostProposalReviewView`, `PostRescheduleSheet`, `MCPBridgeRequestReviewView`, `InspirationReviewView`).
- Batch: B3
- Status: open

### L3-10 Three of the four capture paths end in the Quick Add menu, with no confirmation and no route to what was made
- Where: `creation-hub` → `quick-capture`, both form factors. `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1742-1748`, `:1750-1781`, `:1731-1736`.
- Evidence: `saveIdea()` ends with `finishCapture()`, which is
  ```
  1742:    private func finishCapture() {
  1743:        if let onExit {
  1744:            onExit()
  1745:        } else {
  1746:            dismiss()
  1747:        }
  1748:    }
  ```
  — a dismissal and nothing else. No `notice`, no navigation, no selection change. The same is true of the post path and the "Find three ideas" path. The saved idea lands in `idea-bank`, which the creator must go and find. The one capture path that resolves properly is Voice Spark, which routes to the post it just created: `VoiceSparkView.swift:955-962` sets `selectedTab`, `widgetBriefID` and `widgetBriefOpensEditor` before dismissing. See `flow-map.md` §1.
- Severity: major
- Fix: give `finishCapture()` a destination and use the Voice Spark pattern — on save, dismiss the whole capture stack (not just the inner sheet, see L3-05) and either land on the created object or show a one-line confirmation naming where it went. Sites touched: `QuickCaptureView.swift:1731-1781`, `CreationHubView.swift:294-297` (`returnToCreationHub`).
- Batch: B3
- Status: open

### L3-11 The whole Creator Session family is unreachable in any shipping build
- Where: `creator-session`, `creator-session-timer-fullscreen`, `creator-session-overlay-desktop`, `creator-session-floating-timer`. `ios/AgentCyShared/CreatorSessionActivity.swift:10-12`.
- Evidence:
  ```
  10: enum CreatorSessionFeatureAvailability {
  11:     static let isEnabled = false
  12: }
  ```
  Every entry is gated on it: `AppShellView.swift:98, 174`, `DesktopAppShellView.swift:121, 134`, `AppModel.presentCreatorSession` (`:370`), `ScheduledPostDetailView.swift:228`. `RootView.swift:176-181` actively retires any live activity at launch, and the deep link `case .creatorSession: break` (`RootView.swift:294-295`) routes nowhere. `AgentCyTests/WidgetTests.swift:82` asserts the flag is false, so this is intentional — but four surfaces, a floating overlay, a Live Activity controller and a deep-link case ship for a feature with zero entry points, and they distort every census taken across the app (they are, for instance, four of the five users of the 48pt `AgentCircularGlassIconButton` close control in the L1 inventory).
- Severity: major
- Fix: Chey's decision — remove the family, or set a date and keep it. If it stays, exclude it from the design-consistency and dead-code passes explicitly so it does not skew their counts. Sites touched if removed: `CreatorSessionView.swift`, `ActiveCreatorSessionFloatingTimer.swift`, `CreatorSessionActivity.swift`, `AppShellView.swift:96-109, 173-182`, `DesktopAppShellView.swift:118-138`, `AppModel.swift:368-381`, `ScheduledPostDetailView.swift:228`, `RootView.swift:176-181, 294-295`.
- Batch: B3
- Status: open

### L3-12 `TodayView` is a complete, unreferenced page duplicating Home and Daily Focus
- Where: `ios/AgentCy/Views/Today/TodayView.swift:4`, phone and desktop.
- Evidence: `grep -rn "TodayView" ios/AgentCy ios/AgentCyTests ios/AgentCyUITests ios/AgentCyWidgets ios/AgentCyShared` returns exactly one line — its own declaration:
  ```
  AgentCy/Views/Today/TodayView.swift:4:struct TodayView: View {
  ```
  It carries its own header (`PlanHeader`), a focus section pushing `DailyFocusDetailView` (`:175`), task collections, and two `presentedSheet = .quickCapture` actions (`:421`, `:428`) — a fourth "daily page" behind `home`, `day-agenda` and `daily-focus-detail`. `ios/AgentCy/Views/Spark/` is an empty directory in the same state.
- Severity: major (the largest single piece of dead UI found this pass, and a direct answer to Chey's "is there dead code?")
- Fix: delete `ios/AgentCy/Views/Today/TodayView.swift` and the empty `ios/AgentCy/Views/Spark/` group, and regenerate the project with `xcodegen`. Hand to the dead-code lane for execution; recorded here because it is also a page-purpose answer.
- Batch: B3
- Status: open

### L3-13 "Deny" on an MCP change request is a one-tap irreversible rejection with no confirmation
- Where: `ask-cy-review-request`, both form factors. `ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift:1113-1116`, `:1447-1454`.
- Evidence:
  ```
  1114:                Button("Deny") { perform { try decline(approvalRequest, nil) } }
  1115:                    .buttonStyle(AgentQuietDestructiveButtonStyle())
  ```
  `perform` runs the action and dismisses (`:1447-1454`). No `confirmationDialog`, no `alert`, no undo — while the app confirms deleting a task (`TasksView.swift:2120`), deleting an idea (`IdeaBankView.swift:279`), archiving a series (`ResumablePostEditorView.swift:3375`), archiving one Cy conversation (`DevelopBriefView.swift:155-163`) and even *skipping an empty episode slot* (`AgendaView.swift:2691-2702`). The sibling revision path for episodes is correctly gated behind `settings-mcp-revision-note` (`:1110-1112`).
- Severity: major
- Fix: put "Deny" behind a `confirmationDialog` matching the app's other destructive actions, or replace it with the episode path's "send back with a note" so the rejection is recoverable from the bridge side.
- Batch: B3
- Status: open

### L3-14 A Cy-created post draft is persisted the moment the chip is tapped and never cleaned up if abandoned
- Where: `cy` → `resumable-post-editor` sheet, both form factors. `ios/AgentCy/ViewModels/AppModel.swift:1547-1577`, `ios/AgentCy/Views/Cy/AskCyView.swift:766-793`.
- Evidence: `createPostDraftFromCyResponse` inserts the `CreativeBrief` and `PlatformOutput` and saves immediately (`:1561-1577`). The editor is then shown in a sheet whose Close simply nils the route:
  ```
  777:                        AgentToolbarIconButton(title: "Close", icon: .close) {
  778:                            postDraftToOpen = nil
  ```
  There is no equivalent of `QuickCaptureView.finalizeQuickPostDraft()` (`QuickCaptureView.swift:1867-1906`), which deletes an empty brief and output when the creator backs out of the quick-add post path. So the two "create a post from nothing" flows in the app have opposite cleanup contracts, and tapping the Cy chip and changing your mind leaves an orphan draft in Idea Bank and in Home's "Continue working on…".
- Severity: major
- Fix: extract `finalizeQuickPostDraft`'s emptiness test into a shared `PostDraftCleanupPolicy` and run it on dismissal of the Cy editor sheet as well. Sites touched: `QuickCaptureView.swift:1867-1906`, `AskCyView.swift:766-793`, and `MCPBridgeRequestReviewView`'s scratch-model path (`MCPBridgeSettingsView.swift:761-766`), whose comment already documents the same concern.
- Batch: B3
- Status: open

### L3-15 Widget and notification deep links push onto whatever stack the destination tab already had
- Where: `plan-week`, both form factors. `ios/AgentCy/App/RootView.swift:259-296` and `:307-336`, against `ios/AgentCy/ViewModels/AppModel.swift:343-348`.
- Evidence: the in-app route resets the stack —
  ```
  343:    func routeToWeeklyAgenda() {
  344:        dismissGlobalPresentation()
  345:        requestedPlanNavigationReset &+= 1
  ```
  (and `PlanView` is keyed on it, `AppShellView.swift:67`) — but neither deep-link handler bumps it. `openWidgetDestination` clears `widgetAgendaDay`/`widgetBriefID` and sets `selectedTab` (`RootView.swift:261-296`); `handlePendingNotificationRoute` does the same (`:307-336`). Tapping the Agenda widget while `plan-week` is already three pushes deep therefore pushes `day-agenda` on top of the stale stack, and Back walks the creator back through screens they did not choose. `openRequestedTaskIfNeeded` (`AppShellView.swift:404-409`) gets this right for tasks — it does `tasksPath = NavigationPath()` first.
- Severity: major
- Fix: bump `appModel.requestedPlanNavigationReset` (or call `routeToWeeklyAgenda()`) at the top of both handlers, matching `openRequestedTaskIfNeeded`. Sites touched: `RootView.swift:259-263`, `:307-310`.
- Batch: B3
- Status: open

### L3-16 A widget/notification brief deep link is silently dropped, and leaves stale routing state behind
- Where: `plan-week`, both form factors. `ios/AgentCy/Views/Agenda/AgendaView.swift:400-407`.
- Evidence:
  ```
  400:        .onChange(of: appModel.widgetBriefID, initial: true) { _, id in
  401:            guard let id, let brief = activeBriefs.first(where: { $0.id == id }) else { return }
  ```
  When the brief is not in `activeBriefs` — archived, in another workspace, or not yet materialised by the `@Query` at the moment the deep link lands — the guard returns **without clearing `appModel.widgetBriefID`**. Because `onChange` only fires on a change, the value then never fires again, so the deep link is lost and the stale id sits in the model until a different id arrives. The creator taps a widget and lands on `plan-week` with no explanation. Compare `IdeaBankView.openRequestedIdeaIfNeeded` (`IdeaBankView.swift:323-338`), which distinguishes `.missing` and tells the creator: "This idea is no longer available in this workspace."
- Severity: major
- Fix: mirror the Idea Bank pattern — clear `widgetBriefID`/`widgetBriefOpensEditor` on the miss and post a notice naming why. Sites touched: `AgendaView.swift:400-407`.
- Batch: B3
- Status: open

---

## Minor

### L3-17 The PRD's "Today" ships as Home, the PRD's "Agenda" ships as Plan, and the Plan tab's enum case is `.today`
- Where: `home`, `plan-week`, both form factors. `ios/AgentCy/Models/DomainTypes.swift:1350-1366`, `docs/PRD.md:76-77`.
- Evidence:
  ```
  1351:    case home
  1352:    case today
  …
  1361:        case .home: "Home"
  1362:        case .today: "Plan"
  ```
  while `PRD.md:76` describes "Today is the warm daily launch view" (which ships as Home) and `:77` describes Agenda (which ships as Plan). Three vocabularies for two pages, and the enum name is the opposite of the tab title, which makes every routing call site (`selectedTab = .today` meaning "go to Plan", used at `AppModel.swift:347, 355, 362`, `VoiceSparkView.swift:958`, `RootView.swift:270, 283, 313, 318, 328`) read backwards.
- Severity: minor (internal, plus a document fix)
- Fix: pick one vocabulary. Rename `AppTab.today` → `.plan`, then correct `docs/PRD.md:76-77` to the shipped names. Sites touched: `DomainTypes.swift:1350-1377` and every `selectedTab = .today` / `case .today` site above.
- Batch: B3
- Status: open

### L3-18 `PlanNavigationRoute.dailyFocusDetail` is a dead route sitting beside a live one
- Where: `plan-week`, both form factors. `ios/AgentCy/Views/Plan/PlanView.swift:9-12`, `:58-65`; only append at `ios/AgentCy/Views/Shell/AppShellView.swift:230-236`.
- Evidence: `grep -rn "dailyFocusDetail" ios/AgentCy ios/AgentCyTests` shows one append, inside `#if DEBUG`:
  ```
  232:            if PlanRuntimeFixture.requestsDailyFocusDetail(arguments: launchArguments), planPath.isEmpty {
  233:                appModel.selectedTab = .today
  234:                planPath.append(PlanNavigationRoute.dailyFocusDetail)
  ```
  The production path to the same page is `plan-week` → week row → `day-agenda` → the Focus showcase control (`AgendaView.swift:3268-3271`), present on both form factors. Captured: `docs/refinement/evidence/flows/L3-03-daily-focus-detail.png` (launched with `-agentCyPreviewDailyFocusDetail`), which also shows the "Edit" control that resolves the page inventory's `daily-focus-editor` uncertainty — see `page-purpose.md` §6.
- Severity: minor (internal)
- Fix: delete the `dailyFocusDetail` case and its `navigationDestination` arm, and point the fixture at the live route so the debug path exercises production code. Sites touched: `PlanView.swift:9-12, 58-65`, `AppShellView.swift:230-236`, `AgentCyTests/SocialGridTests.swift:7-8` (asserts `allCases`).
- Batch: B3
- Status: open

### L3-19 The feed grid bypasses the post-destination router, so the same post can open a different page depending on the list you tapped
- Where: `feed-grid`, both form factors. `ios/AgentCy/Views/Feed/SocialGridView.swift:928` against `ios/AgentCy/Views/Brief/ScheduledPostDetailView.swift:7-23`.
- Evidence: fourteen sites route through `PostOutputDetailView`, which chooses between `idea-post-draft` and `scheduled-post-detail` via `PostOutputDetailPolicy.destination(briefStatus:outputStatus:targetDate:)` (`ScheduledPostDetailView.swift:32-47`, whose first test is `PostDraftResumePolicy.shouldResume(briefStatus:outputStatus:)`). The grid tile pushes the finalized page directly:
  ```
  928:                ScheduledPostDetailView(brief: item.brief, output: item.output)
  ```
  Grid membership only tests the *output* status (`SocialGridProjectionPolicy.includes`, `SocialGridView.swift:45-55`), so a scheduled output whose brief is still `.developing` gets the finalized page from the grid and the draft editor from every other list.
- Severity: minor
- Fix: push `PostOutputDetailView(brief:output:)` from `SocialGridView.swift:928`.
- Batch: B3
- Status: open

### L3-20 The Tasks tab's two "add" actions use two different presentation owners
- Where: `tasks`, both form factors. `ios/AgentCy/Views/Tasks/TasksView.swift:1204-1210` and `:623-627`.
- Evidence:
  ```
  1204:    private func openTaskComposer(for collection: TaskCollection) {
  1205:        guard collection == .myTasks else {
  1206:            isAddingPostTask = true
  1207:            return
  1208:        }
  …
  1210:        appModel.presentedSheet = .quickCapture
  ```
  One add button raises a **shell-owned** sheet whose dismissal goes through `AppModel.presentedSheet`; the sibling raises a **view-owned** `.sheet(isPresented: $isAddingPostTask)` (`:623-627`). The two therefore behave differently under `dismissGlobalPresentation()`, workspace switches (`prepareShellForWorkspaceSwitch`, `AppModel.swift:310-318`, clears only the shell sheet) and deep links.
- Severity: minor
- Fix: give both the same owner. `post-task-creation-flow` is already reachable from `quick-capture` (`QuickCaptureView.swift:475-489`), so routing "add post task" through the shell's `.quickCapture` with `quickCaptureStartsWithTask` is the smaller change.
- Batch: B3
- Status: open

### L3-21 Two more one-off close controls, beyond the ten in the page inventory (cross-lane to L1)
- Where: `post-editor-spark-development` and `post-reschedule`, both form factors. `ios/AgentCy/Views/Brief/DevelopBriefView.swift:128-135`; `ios/AgentCy/Views/Agenda/AgendaView.swift:3962-3966` and `:3979-3985`.
- Evidence: `DevelopBriefView`'s close is a hand-rolled **opaque** 44pt circle, not glass and not the shared component:
  ```
  130:                AgentIconView(.close, size: 16)
  131:                    .frame(width: 44, height: 44)
  132:                    .background(Color.agentSurface, in: .circle)
  ```
  This is an eleventh implementation, distinct from the ten catalogued in `01-page-inventory.md` §Close-control variants (neither #4's glass hand-roll nor #5's 40pt opaque circle). Separately, `post-reschedule` uses a text **"Close"** on phone (`AgendaView.swift:3964`) but an X icon whose accessibility label is **"Cancel"** on desktop (`AgendaView.swift:3985`) — one sheet, two words, and the inventory records it as family CC-E ("Cancel" text), which matches neither.
- Severity: minor (cosmetic; owned by the design-consistency lane)
- Fix: replace both with `AgentToolbarIconButton(title: "Close", icon: .close)`. Handed to L1 for batch B1; recorded here because it surfaced while tracing flows 1f and 2b.
- Batch: B3
- Status: open

### L3-22 The Creator Session deep link routes nowhere and says nothing
- Where: `ios/AgentCy/App/RootView.swift:294-295`.
- Evidence:
  ```
  294:        case .creatorSession:
  295:            break
  ```
  `AgentCyDeepLink` still parses a `creatorSession` destination, so a URL or Live Activity tap that reaches it is swallowed. Consistent with L3-11, but silent about it.
- Severity: minor (internal)
- Fix: remove the case from `AgentCyDeepLink` along with the rest of the family (L3-11), or route it to `home` with a notice while the feature is off.
- Batch: B3
- Status: open

---

## Not reproduced, and exactly what is missing

Per the brief, the reproductions above use fixture flags and a scratchpad XCUITest driver. Three findings
could not be reproduced on the simulator, and these are the gaps:

1. **L3-03 (relaunch persistence).** `-agentCyPreviewData` builds an **in-memory** container
   (`AgentCyApp.swift:15-22`, `isStoredInMemoryOnly: true`), so no fixture launch can demonstrate
   survival across relaunch, and a launch without fixtures stops at `account-access-gate`
   (`RootView.swift:234`). **Missing: an invitation code from Chey, or a fixture flag that seeds the
   on-disk container** (e.g. `-agentCyPreviewPersistentData`). The finding rests on the absence of any
   `.background` handler, which is verifiable by grep.
2. **L3-01/L3-02 in their real trigger (MCP review).** Both are proven for the surface itself
   (probe B, and the `#if` blocks), but the automatic presentation needs
   `MCPBridgePreferences.isConnected` and a queued request in a bridge folder.
   **Missing: a fixture that seeds a pending `MCPBridgeChangeRequest`** — e.g.
   `-agentCyPreviewMCPQueue <type>` writing one envelope into a temporary bridge folder. Worth adding;
   flow 5 is currently untestable end to end.
3. **L3-07 (duplicate post from one Cy answer).** Needs a Cy conversation containing a message with a
   `proposedActionKind` that permits post creation. `PreviewData` seeds no `ConversationThread` with a
   proposed action. **Missing: `-agentCyPreviewCyThread proposedPost`** (or equivalent) in
   `ios/AgentCy/Preview/PreviewData.swift`.

## Corrections to `01-page-inventory.md` found while tracing

Not findings; fixes the inventory's owner should fold in.

- `daily-focus-editor` is **not** fixture-only. Production entry: `daily-focus-detail`'s "Edit"
  (`WeeklyFocusView.swift:520-521` phone, `:633-634` desktop → `.sheet` at `:525-526`). What *is*
  fixture-only is the `PlanNavigationRoute.dailyFocusDetail` route (L3-18). Screenshot:
  `evidence/flows/L3-03-daily-focus-detail.png`.
- `tasks`, `pillars` and `idea-bank` tab roots (listed "uncertain") all use the shared **`AgentPageRail`**,
  same as `home`: `TasksView.swift:685-691`, `PillarsView.swift:469-475`, `IdeaBankView.swift:369-375`.
  So header variant #3 has four users, not one.
- `post-editor-spark-discard-confirm` (row at `DevelopBriefView.swift:155`) is actually the
  **"Archive this conversation?"** dialog (`DevelopBriefView.swift:155-163`), not a discard of unsaved
  Cy output.
- `post-reschedule`'s close is `Button("Close")` on phone (`AgendaView.swift:3964`), not CC-E "Cancel";
  desktop uses an X labelled "Cancel" (`AgendaView.swift:3985`). See L3-21.
- Two surfaces have no row: `ScheduledPostDetailView` (`ScheduledPostDetailView.swift:130`, 3 entries) and
  its router `PostOutputDetailView` (`:7`, 14 call sites). Proposed slugs `scheduled-post-detail` and
  `post-output-detail`.
- One page is missing entirely because it is unreachable: `TodayView` (`Views/Today/TodayView.swift:4`).
  See L3-12.
