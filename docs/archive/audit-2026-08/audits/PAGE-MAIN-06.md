# PAGE-MAIN-06 Audit: Cy

- Audit date: 2026-08-18
- Status: `Coverage gap` — both reproduced defects repaired and runtime-verified with creator authorization; recorded state/coverage gaps remain
- Scope owner: [`AskCyView`](../../ios/AgentCy/Views/Cy/AskCyView.swift) (2,650 lines), hosted by the retained phone shell in [`AppShellView`](../../ios/AgentCy/Views/Shell/AppShellView.swift) and by the Catalyst shell in [`DesktopAppShellView`](../../ios/AgentCy/Views/Shell/DesktopAppShellView.swift)
- Parent programs: [`AUD-07`](../APP_AUDIT_QUEUE.md), `PERF-RISK-02`, `PERF-RISK-07`
- Evidence: [`docs/audits/evidence/PAGE-MAIN-06/`](evidence/PAGE-MAIN-06/) — screenshots from the disposable simulator replay described below

## Frozen contract

Cy holds a contextual conversation scoped to the active workspace. Every mutation stays an explicit proposal: nothing is created, scheduled, or changed until the creator taps an explicit accept control (Add task, Send to post, proposal approval). Conversations stay with their account — the history sheet's own copy states "Your conversations stay with this account until you erase them." Exits go to conversation history, post/task work surfaces, MCP proposal review, access settings, and the canonical tabs.

| State | Expected behavior |
| --- | --- |
| Empty | Greeting, quick prompts, honest availability status. |
| Offline/unavailable | "CY IS OFFLINE" card with a settings exit; status dot and label truthful. |
| Streaming/sending | Typing indicator, stop control replaces send. |
| Cancel | Stop ends the turn without a phantom reply. |
| Provider error | Honest error surface; no silent loss of the creator's message. |
| Pending/revised/dismissed proposal | Review surface owns the page while requests exist. |
| Workspace switch | The transcript, composer target, and history must all re-scope to the new workspace. |
| Restored conversation | Relaunch reloads the workspace's most recent open thread. |
| Accessibility sizes / Reduce Motion | Readable layouts without collisions; motion gated. |

## Function and exit trace

| Area | Source | Exit |
| --- | --- | --- |
| Top rail | availability poll state, `ProfileSettingsButton`, ••• menu | Settings sheet; New conversation; Conversation history; Move to history |
| Availability | `resolveCyAvailability()`: local bridge check → access policy → keychain identity | unavailable card exits to Settings |
| Transcript | `messages` = `allMessages` filtered by `thread.id` (view-local `@State var thread`) | message actions: Add task, Send to post (`ResumablePostEditorView` sheet) |
| Composer | `send()` inserts `ConversationMessage(threadID: thread.id, …)` synchronously, then `appModel.askCy` with creator context from the *currently active* workspace | reply appended to `thread.id` on success; alert on failure |
| Cancel | `stopSending()` cancels the send task and clears sending state | — |
| Pending reviews | 4-second poll of `MCPBridgeService.refreshPendingRequests()` | request/series review sheets; batch approve/deny |
| History | `conversationThreads` = workspace-scoped threads with `briefID == nil`, `contextKind == .none` | open/delete thread; transcript subview |
| Thread lifecycle | `loadThread()` (runs once, in `.task` at first appearance), `startNewThread()`, `archiveThread()`, `openThreadFromHistory()` | — |

The explicit-proposal boundary is intact in the traced paths: `addProposedTask` and `sendResponseToPost` run only from explicit taps, and MCP approval goes through `MCPBridgeService.approve`. No pre-acceptance mutation was found, confirming the first static pass.

## Reproduced defects

### DEFECT-MAIN-06-01 — Confirmed, open: the Cy thread ignores workspace switches entirely

`thread` is view-local `@State` chosen once by `loadThread()` in the root `.task`. The phone shell keeps all six root NavigationStacks installed (`opacity(0)` when hidden), so that `.task` runs exactly once per process, and `switchWorkspace(to:)` resets only navigation paths — nothing re-scopes the Cy thread. Every later send writes to whatever thread the state still holds, while `askCy` builds the creator context from the *new* workspace.

Reproduced on a disposable `AgentCy-Audit-PM06` simulator (iPhone 17 Pro, iOS 26.5, Debug build of the current working tree, in-memory store via `-agentCyPreviewData -agentCyPreviewTab cy`, driven by a throwaway XCUITest runner outside the repo):

1. Launch → Cy creates its thread in the bootstrap default workspace W0 (the only workspace at first appearance).
2. Add accounts `@alpha` and `@beta` in Settings (each creates and activates a workspace), switch to `@alpha`, return to Cy, send "Alpha workspace question".
3. Switch to `@beta`, return to Cy: **the transcript still shows the prior thread** (`15-cy-after-switch-to-beta.png`; the driver's element query recorded `staleVisibleAfterSwitch=true`).
4. Send "Beta workspace question": **it appends to the same stale thread** — two creator bubbles in one transcript while `@beta` is active (`21-beta-transcript-two-messages.png`).
5. Open Conversation history while `@beta` is active: **"No conversations yet."** (`22-history-in-beta.png`) — the workspace-scoped history and the unscoped transcript disagree on the same screen.
6. Switch back to `@alpha` and open history: **also "No conversations yet."** (`24-history-in-alpha.png`). Both sends actually landed in W0's thread — neither `@alpha` nor `@beta` can ever see, continue, or erase those messages from history.
7. "New conversation" while `@beta` is active binds a fresh thread to `@beta`; after switching to `@alpha`, Cy displays that beta-scoped empty conversation (`23-transcript-back-in-alpha.png`) — the leak works in every direction, not just A→B.

Consequences beyond display: a send after a switch transmits the old thread's transcript together with the new workspace's creator context to the provider, persists replies into the wrong workspace, and the stale messages become unreachable from every workspace's history (privacy/erase controls miss them). Secondary hazard (traced, not yet replayed): Add task / Send to post on a stale message would materialize proposals into the newly active workspace.

### DEFECT-MAIN-06-02 — Resolved (narrowed after driven probe): AX5 top-rail truncation

Initial capture (`30-cy-ax5-text.png`, dark `31-cy-ax5-dark.png`) suggested a content/composer collision. A driven AX5 probe (`60`/`61`, measurements `62-ax5-probe.txt`) showed the empty-state content scrolls fully clear of the composer and the last quick prompt is visible and hittable — the initial overlap is standard scroll-under-translucent-chrome. The confirmed defect narrowed to the top rail truncating to "AGE… | Unav…", hiding the availability status from exactly the large-text readers it serves (VoiceOver was unaffected — the combined accessibility label carries the full status).

**Repair (authorized 2026-08-18, "approve all"):** `CyTopRailPresentationPolicy.stacksAvailability(for:)` stacks the kicker and status at accessibility sizes; the status extracts to one shared `availabilityStatus` view with a two-line budget when stacked; the rail's fixed 44pt height relaxes to `minHeight` so the stacked variant is not clipped. RED first (`cannot find 'CyTopRailPresentationPolicy'`), then GREEN: **619 tests, 0 failures**. Runtime verified at AX5: `63-ax5-rail-fixed.png` shows "AGENT (CY)" with a fully readable "· Unavailable" beneath it.

### Observed, needs product decision

- A send while Cy is unavailable persists the creator message into the thread, bumps `turnCount`, retitles the thread, then shows the "Cy is not connected yet" alert (`16-after-send-in-beta.png`). The message is kept with no reply and no retry affordance. Decide whether keep-with-alert is the contract or the composer should hold the draft.
- `resolveCyAvailability()` reports `hosted` from an unexpired keychain identity alone — no reachability check, confirming the static risk. "Available" can be shown while offline.
- Thread persistence uses silent `try? context.save()` throughout send/archive/restore paths.

## Repair verification (DEFECT-MAIN-06-01, authorized 2026-08-18)

| Confirmed cause | Repair |
| --- | --- |
| `thread` was view-local `@State` resolved once per process; the retained shell never re-ran `.task`, and `switchWorkspace` reset only navigation paths, so the transcript and send target stayed bound to a stale workspace. | `CyConversationScopePolicy.resolvedThread` (AskCyView.swift) qualifies a thread as non-archived, brief-free, context-free, and workspace-scope-included. `loadThread()` now resolves through the policy; `.onChange(of: appModel.activeWorkspaceID)` re-resolves on every switch; `send()` re-resolves before writing so a send can never enter another workspace's conversation. |

- RED: `PageMain06Tests` failed first (`cannot find 'CyConversationScopePolicy' in scope` across all six regressions) before any production code was written.
- GREEN: **6 PAGE-MAIN-06 regressions passed** — stale-thread drop, new-thread requirement, in-scope retention, legacy nil-workspace default-only scoping, archived/brief/context exclusion, archived-current exclusion.
- Full iOS suite: **618 tests, 0 failures** on the disposable iPhone 17 Pro / iOS 26.5 simulator (612 baseline + 6 new).
- Runtime verified: the patched build replayed the original reproduction on the disposable simulator via the assertion-bearing driver (`CyWorkspaceScopeVerification`, 91s, passed). Evidence `40`–`45`: alpha transcript absent after switching to beta (`41`), beta send lands in beta's own thread (`42`), beta history lists it (`43`), alpha restored with its message only (`44`), alpha history agrees and marks it CURRENT (`45`).
- Scoped `git diff --check` clean; pbxproj change is the XcodeGen-generated addition of `PageMain06Tests.swift` only (verified by normalized diff against a pre-regeneration snapshot).
- Neighboring behavior: New conversation, Move to history, history open/delete paths run through the same policy-resolved thread; covered by the passing full suite plus the driver's history open/agreement checks.

## Regression tests added with the repair (formerly "required before any patch")

No `PageMain06Tests.swift` exists. Neighboring coverage to extend (not duplicate): `DomainTests` (`ConversationTitleFormatter`, `CyChatActionPolicy`, `CyBriefReferencePolicy`, `CyPostCreationPolicy`, `CyPostSchedulingPolicy`, `CyMarkdownParser`) and `ServiceTests.testAskCyReceivesIncompletePostsAndCurrentTaskContext`.

1. Thread re-scope policy: given a thread bound to workspace A and an active switch to B, the resolved conversation thread must be a B-scoped thread (fails today — this is the focused failing regression for DEFECT-MAIN-06-01).
2. Send-target guard: a send must refuse or re-resolve when the bound thread's workspace is not included in the active scope.
3. History/transcript agreement: the thread shown in the transcript must be a member of the workspace-scoped history projection.
4. AX5 presentation policy test for the empty-state clearance, mirroring the accessibility-presentation tests of PAGE-MAIN-01…05.

## Runtime replay record

Disposable simulator `AgentCy-Audit-PM06` (created for this audit; left shut down, not deleted). In-memory container; no real device or persistent data touched. States captured: empty (`10`), offline/unavailable card (`10`), populated transcript (`14`, `21`), provider-error alert (`16`), workspace switch (`15`, `21`–`24`), history empty (`22`, `24`), accessibility AX5 light/dark (`30`, `31`). The driver project lives outside the repository (session scratchpad) and made no changes to the working tree.

## Remaining runtime coverage gap

- Streaming/typing indicator, cancel mid-flight, and live provider errors: `PreviewCreativeService` replies instantly and the fixture has no connected provider, so these need a slow/live provider or a delayed preview fixture.
- Pending/revised/dismissed proposal review states need an MCP bridge inbox fixture.
- Restored conversation across relaunch needs a persistent (file-backed) disposable store. Attempted 2026-08-18: a plain Debug launch on the disposable simulator reaches the account gate ("Continue with Apple" / "I have an invitation code") before any store exists, and the `-agentCyRootFixture` path is in-memory only — so this capture needs either a creator-supplied invitation code for the disposable simulator or an authorized file-backed preview fixture.
- VoiceOver order, actual Reduce Motion, keyboard/scroll interaction at AX sizes, and the Catalyst overlay variant of Cy (close button, split review layout) remain unreplayed — same locked-Mac limitation recorded by PAGE-MAIN-01…05.
- Cross-workspace Add task / Send to post materialization needs a driven replay once the thread defect is repaired.

## Performance and smoothness (Cy-specific)

Static mechanisms confirmed against current source; none is yet a measured Release finding:

1. **Hidden-tab polling is real and starts at launch.** `appTabLayer` hides tabs with `opacity(0)`, so all six roots are installed from launch and AskCyView's `.task` 4-second loop (bridge-connected check → pending-review refresh → availability resolve with keychain read and local-bridge probe) runs continuously even if Cy is never opened — concurrently with the shell's own 4-second `presentMCPApprovalsIfNeeded` loop. The poll already avoids `@State` writes on unchanged results, so the recurring cost is the off-main work plus timer wakeups, not body invalidation.
2. **Broad invalidation surface.** AskCyView owns nine whole-table `@Query` collections; `messages`, `scoped()`, `conversationThreads`, and per-row `taskWasAdded` scans re-filter full tables during body passes; transcript rows re-run markdown parsing.
3. `PERF-RISK-07` (retained six-stack shell) and the root-wide `NavigationRequestObserver` warning stay open as recorded.

Prioritized Release profiling plan for the broader slow-app report (unchanged in intent from the handoff, ordered by expected yield):

1. Release build on Chey's iPhone: Time Profiler + SwiftUI body-update instrument during launch, tab switches, Cy open, transcript scroll, and send; hangs instrument for main-actor stalls.
2. Idle-cost pass: energy log + Time Profiler over 5 idle minutes on Home with Cy never opened, to price the two 4-second loops and hidden-root observation (`PERF-RISK-07`).
3. SwiftData fetch/invalidation counts per tab switch and per Cy body pass at small/medium/production workspace sizes.
4. Same passes on the Release Catalyst build during window resize and Control Center visibility (`PERF-RISK-08`).
5. Media decode/thumbnail paths (`PERF-RISK-04/05`) after the above, since they are journey-specific.

Debug-simulator observations from this replay are deliberately excluded as evidence.

## Defects and classification

1. `DEFECT-MAIN-06-01` — **Resolved (Runtime verified)**: the thread re-resolves to the active workspace on switch and at send time; transcript, send target, and workspace-scoped history agree in the driven replay.
2. `DEFECT-MAIN-06-02` — **Resolved (Runtime verified)**: narrowed to top-rail truncation after the scroll probe; rail stacks at accessibility sizes and the status stays readable.
3. `DRIFT-MAIN-06-01` — **Resolved as current-behavior contract (2026-08-18)**: the creator's blanket approval retained today's behavior — an offline send keeps the message with an alert; revisit only on explicit request to hold the draft instead.
4. `RISK-MAIN-06-01` — **Static risk**: hosted availability without reachability; silent `try?` saves.
5. `GAP-MAIN-06-01` — **Open**: streaming/cancel/live-error, proposal review states, relaunch restoration, VoiceOver/Reduce Motion, Catalyst variant, cross-workspace proposal materialization.
6. `PERF-RISK-02` / `PERF-RISK-07` — **Open**: mechanisms confirmed statically; Release measurements outstanding.

## Classification and next gate

PAGE-MAIN-06 closes as `Coverage gap` (2026-08-18, creator "approve all"). Both reproduced defects completed the full gate: contract resolved → reproduced → focused failing regression watched red → smallest patch → **619 tests, 0 failures** → runtime verified on the disposable simulator. Signed Debug **build 211** (both fixes) was codesign-verified and upgrade-installed on Chey's iPhone, preserving bundle identity and local data; the working tree remains uncommitted by instruction. `GAP-MAIN-06-01` items and Release-device profiling (`PERF-RISK-02`/`07`) stay open and reclassify the page only when recorded. PAGE-MAIN-07 (Feed) is next `In review`, unblocked by resolved `DRIFT-02`/ADR 0012.
