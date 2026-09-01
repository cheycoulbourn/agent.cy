# Flow map (lane L3)

Five journeys traced through `ios/AgentCy` this pass: routes, sheets, state, persistence. Surface names
are the slugs from `docs/refinement/01-page-inventory.md`; two surfaces the inventory does not name
(`scheduled-post-detail`, `post-output-detail`) are introduced in `page-purpose.md` §2.

Every step lists its **exit** — where the creator lands when the step ends — and every flow ends with
what happens on **cancel**, **background**, and **relaunch mid-flow**.

## Facts that apply to all five flows

- **There is no `.background` scene-phase handler anywhere in the app.** The only `scenePhase` observers
  are `AgentCyApp.swift:124`, `AppShellView.swift:264`, `HomeDashboardView.swift:68`,
  `TasksView.swift:638`, `PlanView.swift:103`, `PillarsView.swift:279`, and every one of them
  `guard phase == .active else { return }`. Unsaved capture and editor state is written only in
  `onDisappear`, which does not run when the app is backgrounded or killed. This is the answer to
  "background" for every flow below, so it is stated once here. Filed as L3-03.
- **`appModel.notice` is the app's only error channel and it is presented in exactly two places** —
  `AppShellView.swift:208` and `DesktopAppShellView.swift:100`, both at shell root. 204 sites write to
  it (`grep -rn "notice = \." AgentCy | wc -l`). Errors raised from inside a sheet have no presenter
  inside that sheet. Filed as L3-09.
- **Fixture data is in-memory.** `-agentCyPreviewData` builds the container with
  `isStoredInMemoryOnly: true` (`AgentCyApp.swift:15-22`), so nothing survives relaunch under fixtures,
  and a launch without fixtures stops at `account-access-gate`. Relaunch persistence therefore cannot be
  observed on the simulator without an invite code. Where a "relaunch" answer below is derived from code
  rather than observed, it says so.

---

## Flow 1 — Capture to post

### 1a. Quick Capture, idea

| # | Surface | What happens | Exit |
|---|---|---|---|
| 1 | `home` (any tab) | `+` in `PaperBottomNavigation` → `openCreationHub()` sets `presentedSheet = .creationHub` (`AppShellView.swift:305-308`) | `creation-hub` sheet |
| 2 | `creation-hub` | "Idea" row → `openCapture(.idea)` → `appModel.setQuickCaptureMode(.idea)`, `showQuickCapture = true` (`CreationHubView.swift:275-292`) | **phone:** a *nested* `.sheet` at `CreationHubView.swift:38-41` presenting `QuickCaptureView()` with `onExit == nil`. **desktop:** the hub's content is replaced in place by `QuickCaptureView(onExit: returnToCreationHub)` (`CreationHubView.swift:23-25`) |
| 3 | `quick-capture` | Title + notes + optional pillar/platform. Save (check icon) → `saveIdea()` → `appModel.createSpark(...)` → `finishCapture()` (`QuickCaptureView.swift:1750-1781`) | **phone:** `dismiss()` on the nested sheet — the creator lands back in `creation-hub`, not in the app. **desktop:** `onExit()` returns the hub to its menu |
| 4 | — | No confirmation, no toast, no navigation to the saved idea. It appears in `idea-bank`, which the creator has to find | — |

The step-3 close control on phone is labelled **"Close"** with an X, even though it returns to Quick Add;
the desktop path is correctly labelled "Back to Quick Add"
(`QuickCaptureView.swift:373-379`, `onExit == nil` selects the wrong branch on phone).
Reproduced: `docs/refinement/evidence/flows/L3-A2-quick-capture-nested.png` and
`L3-A2-tree-quick-capture-nested.txt` — two live `Close` buttons in one window, one at `{37.8, 76.1}`
(the hub, still behind) and one at `{20, 73}` (Quick Capture), with the sheet grabber between them.
`L3-A4-back-in-quick-add-after-close.png` shows where Close lands. Filed as L3-05.

- **Cancel:** `closeCapture()` runs `updateSavedIdeaFromForm()` then `preserveUnfinishedDrafts()`
  (`QuickCaptureView.swift:1730-1740`), so a typed-but-unsaved title is silently saved as a spark. That is
  a deliberate, good behaviour — but it is invisible: the creator who backs out of a half-typed idea gets
  a new Idea Bank row with no notice.
- **Background:** `preserveUnfinishedDrafts()` is only reached through `closeCapture()` or
  `.onDisappear` (`QuickCaptureView.swift:447-453`). Killing the app from the switcher loses the text.
- **Relaunch:** a saved spark is a `CreativeBrief` and survives. An unsaved one does not.

### 1b. Quick Capture, post

`creation-hub` → "Post" → `quick-capture` with `kind == .post` → `beginQuickPostDraft()` inserts a real
`CreativeBrief` + `PlatformOutput` immediately (`QuickCaptureView.swift:1848-1865`) and embeds
`ResumablePostEditorView(showsEditorChrome: false)` inside the capture sheet
(`QuickCaptureView.swift:325-332`). On exit, `finalizeQuickPostDraft()`
(`QuickCaptureView.swift:1867-1906`) deletes the brief and output again if no text and no linked task
survived. Exit: back to `creation-hub` (phone) or the hub menu (desktop).

This is the only capture path in the app that cleans up its own empty draft. Compare 1e.

### 1c. Voice Spark

| # | Surface | What happens | Exit |
|---|---|---|---|
| 1 | `creation-hub` | "Voice Spark" row (phone section only) → `showVoiceSpark = true` | nested `.sheet` at `CreationHubView.swift:48-51` |
| 2 | `voice-spark` | Record → transcribe → edit transcript. `.interactiveDismissDisabled` while recording/transcribing (`VoiceSparkView.swift:357`) | — |
| 3 | `voice-spark` | Save (check) → `createPost(from:)` → `createSpark(placement: .post)` + `ensurePostDraft` + attach audio (`VoiceSparkView.swift:893-927`) | `openPost(brief)` |
| 4 | `openPost` | Sets `widgetBriefOpensEditor = true`, `requestedPlanMode = .week`, `selectedTab = .today`, `presentedSheet = nil`, `widgetBriefID = brief.id`, then `dismiss()` (`VoiceSparkView.swift:955-962`) | `plan-week` → `resumable-post-editor` pushed via `AgendaView.swift:400-407` |

This is the **only** capture path that takes the creator to the thing they just made. It is the model the
other three should follow.

- Alternative branch: "Connect to an existing post" opens `voice-spark-link-picker`; if the target is an
  idea rather than a post, the flow stays put and posts a notice
  (`VoiceSparkView.swift:929-953`) — correct.
- **Cancel:** the X resets the recorder, stops playback and dismisses. In-progress audio is discarded.
- **Background:** `.onDisappear` resets the recorder; backgrounding mid-record does not, so the recorder
  keeps running. Not traced further; flagged for the audio owner, not this lane.
- **Desktop:** the whole surface is `EmptyView` on Catalyst (`AppShellView.swift:168-172`) and the hub
  does not offer the row, so there is no dead end.

### 1d. Shared link via the Share Extension

| # | Step | What happens |
|---|---|---|
| 1 | Another app | Share → `AgentCyInspirationShare` writes a bounded envelope to `group.com.agentcy.app` (`ARCHITECTURE.md:35`) |
| 2 | App launch / scene active | `AppShellView.swift:224-231` and `:239-245` call `appModel.importPendingInspiration(context:presentsImportedSource: **false**)` |
| 3 | Import | The `InspirationSource` is created and the queue file removed |
| 4 | **Nothing happens.** | On iPhone the creator is never told. There is no notice, no badge, no route |

The desktop shell calls the same method with the default `presentsImportedSource: true`
(`DesktopAppShellView.swift:142, 147`), which switches to `idea-bank` and opens `inspiration-review`
(`AppModel.swift:1112-1120`). So the shipping platform is silent and the internal one is not — and the
desktop `idea-bank` then has no inspiration list to find the item in again, because
`inspirationList(...)` is compiled out for Catalyst (`IdeaBankView.swift:253-255`). Filed as L3-04.

- **Exit on phone:** the item is discoverable only by opening `idea-bank` and scrolling to the
  inspiration section, or `saved-posts-library`.
- **Cancel/Background/Relaunch:** the import is transactional (queue file removed only after commit), so
  the data survives. Only the *notification* of it is missing.

### 1e. "Find three ideas" via Cy

`creation-hub` → "Find three ideas" → `openCapture(.cyIdeas)` → `setQuickCaptureMode(.cyIdeas)` →
`quick-capture` opens in `showingCySuggestions` mode and calls `loadIdeas()`
(`QuickCaptureView.swift:427-430`). Saving a direction calls `saveGeneratedIdea`
(`QuickCaptureView.swift:1783-1795`) per idea. Closing runs the `showingCySuggestions` branch of
`closeCapture()` (`QuickCaptureView.swift:1731-1736`), which skips draft preservation — correct, since
unselected directions must disappear per `PRD.md:56`.

Exit: back to `creation-hub` on phone, hub menu on desktop. Same missing-destination problem as 1a.

### 1f. Develop brief → Proposal review → post editor

| # | Surface | What happens | Exit |
|---|---|---|---|
| 1 | `resumable-post-editor` / `idea-post-draft` | "Build with Cy" → `showSparkDevelopment` | `post-editor-spark-development` sheet |
| 2 | `post-editor-spark-development` (`DevelopBriefView`) | `onAppear` sets `postProposal = appModel.proposal(for:)` — an existing proposal re-opens the review sheet immediately (`DevelopBriefView.swift:105-110`) | `post-proposal-review` if one was pending |
| 3 | dialogue / compose | `perform(_:)` at `DevelopBriefView.swift:483-502`. On a failed dialogue turn it **restores the typed answer** (`:494-496`) | — |
| 4 | compose success | `postProposal = appModel.proposal(for:)` | `post-proposal-review` sheet |
| 5 | `post-proposal-review` | Every field is bound to `@State proposal` (`PostProposalReviewView.swift:9`, initialised at `:20-30`). "Use this post" → `acceptProposal` → `dismiss()` | back to `post-editor-spark-development`, **still open**, chat and all |
| 6 | — | The creator must close Develop as well to reach the post they just accepted. Nothing routes to it | — |

- **Cancel:** two different cancels with two different contracts. "Discard post" opens a confirmation
  alert (`PostProposalReviewView.swift:157-159`, alert at `:172-190`). The toolbar **Close (X) at
  `PostProposalReviewView.swift:167-169` calls `dismiss()` with no confirmation and no save**, so every
  edit made in the review is thrown away while the stored `PendingBriefProposal` keeps the original.
  Reopening shows the pre-edit text. Filed as L3-06.
- **Background:** same as step 5 — `@State` only, nothing written.
- **Relaunch:** the *proposal* survives (`PendingBriefProposal`, read back at `AppModel.swift:2584-2598`);
  the *edits* do not. Derived from code; not observed, see "Facts" above.

---

## Flow 2 — Schedule

### 2a. From the editor

`resumable-post-editor` → the dates row → `post-editor-dates-sheet` (`PostDatesPicker`,
`ResumablePostEditorView.swift:309, 4453`). Dates are held in editor `@State` (`hasTargetDate`,
`targetDate`, `hasWorkDate`, `workDate`) and written by `persistChanges()`
(`ResumablePostEditorView.swift:2435-2487`), which also calls `appModel.rescheduleLinkedTasks(...)` and
`appModel.queueCalendarSync(context:)`.

Exit paths out of the editor:
- Back / close → `requestCloseEditor()` (`:2428-2432`) → `guard persistChanges() else { return }`. **If
  the title is empty, `persistChanges` returns `false` and the close is silently refused**, with only
  `appModel.notice = .info("Name the post before saving it.")` (`:2475-2477`) — which has no presenter
  when the editor is inside a sheet (see "Facts"). The Back button appears dead.
- Disappearing without that call → `.onDisappear` at `:409-417` persists unless the draft is being
  deleted or moved to the Idea Bank.

### 2b. From Plan / Agenda

- Overdue or unscheduled row → `reschedulingOutput` → `post-reschedule` sheet
  (`AgendaView.swift:326, 3891`). `saveAndDismiss()` normalises the date through
  `RecurringPostSchedule.normalizedTargetDate` and calls `appModel.schedule(output:...)`; on failure it
  `return`s and leaves the sheet open (`AgendaView.swift:4086-4098`). The failure notice, again, has no
  presenter above the sheet.
- The picker is bounded by `minimumDate = now` (`AgendaView.swift:3903`), so an overdue post silently
  opens on today rather than its original date. Acceptable, but undocumented in the copy.
- Unscheduled post with no date → `schedulingPost` → `day-agenda-scheduling-post`
  (`AgendaPostIdeaPickerView`, `AgendaView.swift:338`).
- Close controls differ by form factor: `Button("Close")` on phone (`AgendaView.swift:3962-3966`), an X
  icon whose accessibility label is **"Cancel"** on desktop (`AgendaView.swift:3979-3985`).

### 2c. Series episode slots

`day-agenda` → open slot → `episode-slot-actions` sheet (`AgendaView.swift:328-333, 2578`).
Three actions (`Create New Episode`, `Use an Idea Bank Idea`, `Duplicate Previous Episode`) all run
through `perform(_:)` at `AgendaView.swift:2779-2800`, which on **every** failure calls
`context.rollback()` and writes an inline, specific message ("Your plan is unchanged"). On success it
calls `onConverted(result)` **then** `dismiss()`, and the parent sets `deepLinkedBriefOpensEditor = true;
deepLinkedBrief = result.brief` (`AgendaView.swift:329-332`) so the creator lands in the editor for the
episode they just planned.

**This is the best-behaved flow in the app** — inline errors, rollback, explicit destination — and it is
the pattern the rest should copy.

### 2d. Calendar projection

`appModel.queueCalendarSync(context:)` (`AppModel.swift:1072-1083`) refreshes the widget snapshot,
`refreshCalendarSync`, and the reminder schedule. It is called from `persistChanges`, `toggleTask`,
`undoLastTaskCompletion`, `finalizeQuickPostDraft` and others. One-way, per `ARCHITECTURE.md:31`.

- **Cancel:** each sheet's cancel leaves the stored date untouched.
- **Background:** dates typed into `post-editor-dates-sheet` but not committed are `@State`.
- **Relaunch:** committed dates are SwiftData and survive; `deepLinkedBrief` / `widgetBriefID` routing
  state is in-memory and does not.

### 2e. Deep links into scheduling

`RootView.openWidgetDestination` (`:259-296`) and `handlePendingNotificationRoute` (`:307-336`) both set
`selectedTab` and `widgetAgendaDay` / `widgetBriefID` — but neither bumps
`appModel.requestedPlanNavigationReset`, so the destination is **pushed on top of whatever the Plan tab's
stack already held**. The in-app equivalent, `AppModel.routeToWeeklyAgenda()` (`:343-348`), does reset it.
Tapping an Agenda widget while Plan is three pushes deep therefore leaves stale screens under Back.
Filed as L3-16.

`case .creatorSession: break` (`RootView.swift:294-295`) — the Creator Session deep link routes nowhere,
consistent with the feature being disabled but silent about it.

---

## Flow 3 — Tasks

### 3a. Create

| Entry | Surface | Owner of the presentation |
|---|---|---|
| `creation-hub` → "Task" | `quick-capture` (`kind == .task`) | nested sheet on the hub (phone) |
| `tasks` → add, My tasks | `quick-capture` | **shell** sheet (`TasksView.swift:1204-1210` sets `appModel.presentedSheet = .quickCapture`) |
| `tasks` → add, Post tasks | `post-task-creation-flow` | **local** sheet (`TasksView.swift:623-627`) |
| `day-agenda`, `daily-focus-detail`, `pillars`, `idea-bank`, `weekly-focus-*` | `quick-capture` | shell sheet (`AgendaView.swift:1951, 3730`, `WeeklyFocusView.swift:826`, `PillarsView.swift:1772`, `IdeaBankView.swift:745`) |
| `resumable-post-editor` / `scheduled-post-detail` | `post-editor-task-composer` | local sheet |

Two "add a task" buttons on the same page use two different presentation owners and two different
surfaces. Filed as L3-17 (minor).

Inside `quick-capture`, the task branch first shows `taskTypeChooser` and only reaches `taskComposer`
once `quickTaskType == .focus`; choosing "post task" opens `post-task-creation-flow` as a *third* stacked
sheet with an `onDismiss` that either finishes the whole capture or resets the chooser
(`QuickCaptureView.swift:475-489`).

### 3b. Subtasks

`draftSubtasks` in `quick-capture` (`QuickCaptureView.swift:265`) and `quick-capture-subtask-composer`
(`DraftSubtaskComposer`, `:1973`). Subtasks are stored as `CreatorTask` with `parentTaskID` and are
deleted with their parent (`ARCHITECTURE.md:76`, `AppModel.swift:3443-3445`).

### 3c. Complete and undo

`AppModel.toggleTask(_:context:)` (`:3380-3424`):
1. refuses if the linked brief is archived or missing, with a notice;
2. emits the recording milestone at most once;
3. materialises the next occurrence of a recurring task;
4. `context.save()`, `queueCalendarSync`;
5. on a fresh completion, `presentTaskCompletionUndo(for:generatedTaskID:)`.

`taskCompletionUndo` lives for 5 s (`AppModel.swift:3465-3471`) and renders as a shell-level toast
(`AppShellView.swift:110-120`, `DesktopAppShellView.swift:1645-…`). `undoLastTaskCompletion`
(`:3426-3453`) un-completes the task **and deletes the generated next occurrence and its subtasks** —
correct and non-obvious.

Because the toast is drawn in the shell's `ZStack`, completing a task from inside a sheet leaves the undo
invisible for its whole 5-second life. The undo state is also in-memory: `taskCompletionUndo` does not
survive relaunch, so an accidental completion noticed after a relaunch is unrecoverable.

- **Cancel:** re-tapping the checkbox toggles back and clears the undo (`:3414-3416`).
- **Background:** the 5 s timer is a detached `Task` and keeps running; the toast is gone on return.
- **Relaunch:** completion persists; undo does not.

### 3d. Due dates

Four separate due-date surfaces for one job: `quick-capture-task-due-date-sheet`
(`QuickCaptureView.swift:2060`), `task-due-date-editor` (`TasksView.swift:2512`),
`post-editor-task-due-date` (`ResumablePostEditorView.swift:5372`), `post-task-due-date-picker`
(`TasksView.swift:1593`). All four are `.sheet`s with a "Cancel" and their own date state.

### 3e. Recurring focus

`FocusTaskRecurrenceService.reconcile(context:)` runs at `RootView.swift:184` and again on every
`scenePhase == .active` (`AgentCyApp.swift:126`). `RecurringTaskMaterializer.createNextOccurrence`
generates the follow-on task inside `toggleTask`. `weekly-focus-task-templates`
(`WeeklyFocusView.swift:317`) edits the templates. Nothing dead-ends here.

---

## Flow 4 — Cy proposal

| # | Step | Code | Exit |
|---|---|---|---|
| 1 | Ask | `send()` (`AskCyView.swift:2269-2322`): inserts the creator's `ConversationMessage`, clears `prompt`, bumps `thread.turnCount`, saves, sets `isSending`, starts `sendTask` | transcript grows |
| 2 | Stream | `appModel.askCy(...)` (`AppModel.swift:3850-3883`) — the proxy buffers and emits one validated result (`ARCHITECTURE.md:58-62`); the client shows `typingIndicator`, not a token stream | — |
| 3 | Reply | assistant message inserted with `suggestions` and `proposedAction` | chips render |
| 4 | Cancel | `stopSending()` (`AskCyView.swift:2324-2331`) cancels the task and clears the flags | **the creator's message stays in the transcript with no reply, no marker, and no retry** |
| 5 | Error | `askCy` catches, calls `presentCreatorError` → `notice` → shell alert | same as 4: stranded turn, and `prompt` was already cleared at step 1 and is never restored |
| 6 | Accept a task | `addProposedTask` (`AskCyView.swift:2358-2389`); idempotence is a **persistent** query, `taskWasAdded(from:)` → `tasks.contains { $0.sourceConversationMessageID == message.id }` (`:2352-2355`) | notice "Task added." |
| 7 | Accept a post | `sendResponseToPost` (`AskCyView.swift:2391-2430`) creates and **persists** the brief + output immediately, then opens `postDraftToOpen` | `resumable-post-editor` in a sheet (`AskCyView.swift:766-793`) |

`DevelopBriefView` handles the same failure at step 5 correctly — it puts the answer back in the composer
(`DevelopBriefView.swift:494-496`). `AskCyView` does not. Filed as L3-08.

**The "Create this post" chip** (`AskCyView.swift:1655-1676`; there is no chip literally named "Expand on
this post" in the tree — `grep -rn "Expand on this" AgentCy` returns nothing, the label is
"Create this post" / "Post created", driven by `message.proposedActionKind` through
`CyPostCreationPolicy`):
- Its "already created" state is `@State private var sentToPostMessageIDs: Set<UUID>`
  (`AskCyView.swift:570`), which is not persisted. After a relaunch, a workspace switch that re-creates
  the view, or any state reset, the chip reads "Create this post" again and a second identical post is
  created from the same message. Its sibling task chip is immune because it queries SwiftData. Filed as
  L3-07.
- The draft it creates is inserted and saved at once (`AppModel.swift:1547-1577`). If the creator closes
  the editor sheet with the toolbar Close (`AskCyView.swift:776-782`, which just nils `postDraftToOpen`),
  the untitled draft stays. `quick-capture` has `finalizeQuickPostDraft()` for exactly this and the Cy
  path has no equivalent. Filed as L3-15.

- **Cancel:** see step 4. `thread.turnCount` was already incremented and any quota already spent.
- **Background:** `sendTask` is an unstructured `Task`; the view staying alive means the reply can still
  land. Nothing marks the pending turn if it does not.
- **Relaunch:** the thread and both messages persist. `isSending`, `sendTask`, `sentToPostMessageIDs` and
  `postDraftToOpen` do not — so a relaunch mid-request loses the request with no trace beyond an
  unanswered message.

---

## Flow 5 — MCP review

| # | Step | Code |
|---|---|---|
| 1 | Arrives | `AppShellView.presentMCPApprovalsIfNeeded()` polls every 4 s (`:239-249, 411-445`); `AskCyView` polls independently every 4 s (`:704-716`) and also listens for `.agentCyMCPInboxChanged` (`:722-724`) |
| 2 | Badge | `hasPendingMCPReview` drives the Cy tab dot |
| 3 | Present | `AppShellMCPReviewPolicy.shouldPresent` suppresses while any global presentation is up; otherwise `appModel.presentMCPReview()` sets `presentedSheet = .askCy` (`AppModel.swift:364-367`) |
| 4 | The sheet | `AppShellView.swift:183` presents `AskCyView()` — with `showsCloseButton` at its default `false`, and the control is compiled out for non-Catalyst anyway (`AskCyView.swift:1274-1295` is inside `#if targetEnvironment(macCatalyst)`) |
| 5 | Review | On phone, `pendingReviews` being non-empty makes `pendingReviewContent` **replace the whole conversation** and hides the composer (`AskCyView.swift:649-659`, `showsConversation` at `:2153-2161`) |
| 6 | One request | tap → `.sheet(item: $reviewingRequest)` → `ask-cy-review-request` (`AskCyView.swift:729-746`, `MCPBridgeSettingsView.swift:739`) |
| 7 | Approve | `reviewActions` (`MCPBridgeSettingsView.swift:1097-1118`) → `perform { try approve(...) }` → `MCPBridgeService.approve` → `dismiss()` |
| 8 | Reject | "Deny" → `perform { try decline(request, nil) }` — **no confirmation, no undo** |
| 9 | Revision | episodes only: "Send back for revision" → `settings-mcp-revision-note` → `decline(request, note)` |

Two defects here, both phone-only:

- **Step 4 — the sheet has no close control on iPhone.** Verified on the simulator: launching with
  `-agentCyPreviewSheet askCy` produces a full-height Cy sheet whose accessibility tree contains no
  element labelled "Close" at all (`docs/refinement/evidence/flows/L3-B1-tree-askcy-sheet.txt`,
  `L3-B1-askcy-sheet-over-askcy-tab.png`). Only the swipe-down gesture dismisses it. Filed as L3-01.
- **Step 5 — Cy is unusable while anything is queued.** The comment at `AskCyView.swift:652-654` records
  that this exact behaviour was already fixed once ("A queue used to replace the whole feed, so Cy was
  unusable until every item was cleared. Reviews are opened deliberately from the banner instead") — but
  the fix is inside `#if targetEnvironment(macCatalyst)` and the `#else` branch still does the old thing.
  Filed as L3-02.

Because steps 4 and 5 compose, the shipping behaviour is: the poller raises a modal over whatever the
creator was doing, that modal shows a review queue instead of Cy, and it has no visible way out.

- **Desktop:** `desktopReviewBanner` keeps the conversation and offers `ask-cy-review-desktop-workspace`
  (`MCPDesktopReviewView`), which is deliberately rendered *inside* Cy's surface rather than as a second
  sheet — the comment at `AskCyView.swift:641-643` explains why. Right call; the phone should do the same.
- **Cancel:** `MCPBridgeRequestReviewView`'s Close leaves the request queued.
- **Background:** both pollers are `while !Task.isCancelled` loops in `.task`, so they suspend and resume.
- **Relaunch:** the queue lives in the bridge folder, so it survives; `presentedMCPRequestIDs`
  (`AppShellView.swift:44`) does not, so **every relaunch re-presents every still-pending request**.

---

## Cross-flow summary: where a flow does not finish

| Flow | Finishes at | Problem |
|---|---|---|
| 1a idea | `creation-hub` | Lands back in the menu it came from, with no confirmation and no route to the idea |
| 1b post | `creation-hub` | Same |
| 1c voice | `resumable-post-editor` | **Finishes correctly** |
| 1d shared link | nowhere | Never acknowledged on iPhone |
| 1e three ideas | `creation-hub` | Same as 1a |
| 1f develop | `post-editor-spark-development` | Two closes to reach the accepted post; X discards edits |
| 2a schedule from editor | the editor | Back is silently refused on an empty title |
| 2b reschedule | `plan-week` | **Finishes correctly** |
| 2c episode slot | the episode's editor | **Finishes correctly** |
| 3 task complete | the list | **Finishes correctly**, undo invisible from inside a sheet |
| 4 Cy accept post | the post editor sheet | **Finishes correctly**; abandoned drafts are not cleaned up |
| 4 Cy cancel/error | the transcript | Stranded turn, no retry |
| 5 MCP review | the queue | No close control on iPhone; Cy unusable meanwhile |
