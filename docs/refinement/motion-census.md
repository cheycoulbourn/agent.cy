# L2 · Motion census

Every animation site in `ios/AgentCy`, located this pass by grepping for `withAnimation`,
`.animation(`, `.transition(`, `.snappy`, `.spring`, `.easeOut`, `.easeIn`, `.easeInOut`,
`.smooth`, `.bouncy`, `.linear(duration`, `repeatForever`, `matchedGeometryEffect`,
`symbolEffect`, `phaseAnimator`, `keyframeAnimator`, `TimelineView`, `.contentTransition`,
`.scrollTransition`. 111 raw hits across 23 files; collapsed below into 60 rows
(the thirteen identical `AgentButtonPressFeedback` call sites are one row).

Yardstick: `.agents/skills/review-animations/STANDARDS.md` (frequency table, ease-out for
enter/exit, ease-in-out for on-screen movement, UI under 300 ms, never scale from ~0,
springs only for gestures) and `.agents/skills/apple-design/SKILL.md`.

Frequency classes: **constant** (runs with no user action at all) · **high** (tens of times
a day) · **medium** (a few times a day) · **low** (occasional — modals, toasts, sheets) ·
**rare** (first run, onboarding, error paths).

Verdict values map to the vocabulary proposed in `draft-motion-section.md`:
`press` · `reveal` · `move` · `settle` · `gesture` · `none`.

---

## A. Shared tokens (Design/DesignTokens.swift)

| # | Site | Trigger | Freq | Curve / duration | Purpose | RM gated | Verdict |
|---|---|---|---|---|---|---|---|
| A1 | `DesignTokens.swift:757` `AgentButtonPressFeedback.animation` | any button press | high | `.easeOut(0.12)`, nil on Catalyst | feedback | yes | **keep** → `AgentMotion.press` (0.12 easeOut). Already correct. |
| A2 | `DesignTokens.swift:804, 830, 857, 884, 910, 1246, 1281, 1320` + `AppShellView.swift:696`, `PostMediaViews.swift:377`, `OnboardingView.swift:1980, 2004, 2037` (13 call sites) | button press | high | A1 | feedback | yes | **keep** → `press`. Only shared timing in the app today. |
| A3 | `DesignTokens.swift:497` `AgentModalResize.animation` | desktop modal changes stage | low | `.smooth(0.34)` | prevent jarring resize | at call sites | **retune** → `settle` (`.easeOut(0.26)`). 340 ms breaks the 300 ms UI ceiling. |
| A4 | `DesignTokens.swift:1208` `AgentTaskCheckbox` | task checked | high | `.easeOut(0.15)` + `scaleEffect(isCompleted ? 1 : 0.6)` | state | yes | **retune** → `reveal` (0.18) and raise the rest scale 0.6 → 0.94. |
| A5 | `DesignTokens.swift:1627` `CyPendingReviewLogo` | mounted whenever an MCP proposal waits; lives in the phone tab bar | constant | `.linear(1.8).repeatForever` rotation | decoration / state | yes | **retune** → `none` for the loop. Keep the mark, drop the spin; use a static tinted dot for "waiting". |
| A6 | `DesignTokens.swift:1655` `CyAnimatedLogo` | mounted on Home and on four Cy surfaces | constant | `TimelineView(.animation(minimumInterval: 1/30))`, 2.8 s cycle, rotation + scale + **animated shadow radius** | decoration | yes (static fallback) | **remove** the perpetual loop → `none`. See L2M-01: this is why Home never idles. |
| A7 | `DesignTokens.swift:1689` `CyThinkingMark` | Cy is generating | low | `TimelineView(.animation)` — **no `minimumInterval`**, so it ticks at display rate (120 Hz on ProMotion); 1.1 s cycle | state (thinking) | **partial** — still runs a TimelineView under Reduce Motion, pulsing scale 0.94→1.06 and opacity 0.68→1 | **retune**: add `minimumInterval: 1/30`; render a truly static mark under Reduce Motion. |

## B. Phone shell (Views/Shell/AppShellView.swift)

| # | Site | Trigger | Freq | Curve / duration | Purpose | RM gated | Verdict |
|---|---|---|---|---|---|---|---|
| B1 | `AppShellView.swift:733-741` `appTabLayer` | tab switch | high | explicitly `transaction.animation = nil` | — | n/a | **keep** → `none`. Correct: content swaps instantly. |
| B2 | `AppShellView.swift:849` `PaperBottomNavigation` | tab switch | high | `.snappy(0.32)` (a spring) driving `matchedGeometryEffect` on the glass pill | spatial | yes | **retune** → `move` (`.easeInOut(0.18)`). A 320 ms spring on the app's most-used control; measured 503–518 ms of continuous redraw per switch (`evidence/L2/tab-switch-bursts.txt`). Standards: tens-of-times/day → "remove or drastically reduce"; springs are for gestures. |
| B3 | `AppShellView.swift:94` bottom nav `.transition(.opacity + .move(.bottom))` | keyboard shows/hides | high | driven by B4 | prevent jarring | **no** | **retune** → `reveal`, opacity-only under Reduce Motion. |
| B4 | `AppShellView.swift:218, 221` keyboard notifications | every text field focus | high | `withAnimation(.easeOut(0.16))` | prevent jarring | **no** | **retune** → `reveal` (0.18) **and gate on Reduce Motion**. Same defect duplicated at `ResumablePostEditorView.swift:434, 437`. |
| B5 | `AppShellView.swift:115` undo toast transition + `:159` `.animation(.easeOut(0.24), value: taskCompletionUndo)` | task completed | medium | `.easeOut(0.24)`, asymmetric move-in / fade-out | prevent jarring | **no** | **retune** → `settle` (0.26) via a shared toast modifier; gate on Reduce Motion. Desktop twin (D3) has the transition but no animation at all. |
| B6 | `AppShellView.swift:124` walkthrough backdrop `.transition(.opacity)` | walkthrough | rare | ambient | prevent jarring | n/a (opacity) | **keep** → `reveal`. |
| B7 | `AppShellView.swift:145` walkthrough card transition | walkthrough step change | rare | asymmetric move+opacity in / offset(-12)+opacity out | spatial | yes | **retune** → `settle`; the asymmetric offset removal is a fourth unnamed curve. |
| B8 | `AppShellView.swift:319, 343` `setWalkthroughStep` / `completeWalkthrough` | walkthrough | rare | `.snappy(0.28)` and `.snappy(0.26)` — two values for one job | spatial | yes | **retune** → `settle` (one value). |
| B9 | `AppShellView.swift:644` walkthrough card content reveal | walkthrough card appears | rare | `.spring(duration: 0.3, bounce: 0)` | delight | yes | **retune** → `settle`. A zero-bounce spring is an ease; name it. |
| B10 | `AppShellView.swift:654-671` `WalkthroughAnimatedGlyph` | walkthrough card appears | rare | `scaleEffect(isVisible ? 1 : 0.25)` + opacity + blur | delight | via B9 | **retune**: start at 0.94, not 0.25. Standards: never appear from ~nothing. |
| B11 | `AppShellView.swift:724` `WalkthroughControlCue` | walkthrough active | rare→constant while active | `.easeInOut(1.15).repeatForever(autoreverses:)` on scale + shadow radius | attention | yes | **retune**: cap at 3 pulses, or `none`. Animated shadow radius re-rasterizes every frame. |
| B12 | `AppShellView.swift:903` `CyWeeklyPlanningPulse` | Mondays until Cy is opened | constant (all Monday) | `TimelineView(.animation(minimumInterval: 1/30))`, 1.8 s sine on opacity + scale + **shadow radius** | attention | yes (static fallback) | **retune** → `none` for the loop; a static tinted ring says the same thing. |

## C. Tab roots

| # | Site | Trigger | Freq | Curve / duration | Purpose | RM gated | Verdict |
|---|---|---|---|---|---|---|---|
| C1 | `HomeDashboardView.swift:811` `CyAnimatedLogo()` | none — mounted with Home | **constant** | A6 | decoration | yes | **remove** the loop → `none`. **Measured: Home emits 300 frames in 9.9 s (30 fps) and 716 frames in 11.9 s (60 fps) while completely untouched; the Plan tab under the same conditions emits 1 frame in 12 s.** |
| C2 | `HomeDashboardView.swift:185` `.transition(.opacity)` on a dashboard card | card shown/hidden while arranging | low | ambient | prevent jarring | n/a | **keep** → `reveal`. |
| C3 | `HomeDashboardView.swift:1660, 1687` begin/finish arranging | tap "Customize" | low | `.easeInOut(0.16)` | move | yes | **retune** → `move` (0.22) or `reveal`; 0.16 easeInOut is a one-off value. |
| C4 | `PlanView.swift:219` week change | swipe/tap a week | medium | `.snappy(0.28)` | spatial | yes | **retune** → `move` (0.22). |
| C5 | `TasksView.swift:612` collection change | tap a task collection | high | `.snappy(0.24)` **stacked on top of** a paging `TabView` (`:672`) that runs its own system paging animation | spatial | yes | **retune** → `none` on phone (the TabView already animates; the extra `.animation` double-drives it); keep `reveal` for the Catalyst `.transition(.opacity)` branch. |
| C6 | `TasksView.swift:2322` scroll subtask composer into view | add a subtask | low | `.easeOut(0.22)` after an explicit 180 ms sleep | prevent jarring | **no** | **retune** → `reveal`; gate on Reduce Motion (scroll position changes are exactly what Reduce Motion is for). |
| C7 | `PillarsView.swift:1705` content tab select | tap a pillar sub-tab | medium | `.snappy(0.2)` | spatial | **no** | **retune** → `move`; gate. |
| C8 | `PillarsView.swift:1831, 1838, 1848` begin/cancel/save editing | edit a pillar | low | `.snappy(0.2)` ×3 | move | **no** | **retune** → `move`; gate. |
| C9 | `IdeaBankView.swift:774` selection mode | enter/exit multi-select | medium | `.snappy(0.2)` | move | yes (`IdeaBankRootAccessibilityPolicy`) | **retune** → `move`. |
| C10 | `IdeaBankView.swift:810` delete selected | delete ideas | low | `.snappy(0.24)` | prevent jarring | yes | **retune** → `settle`. |
| C11 | `AgendaView.swift:520` | day/post change | medium | `.snappy(0.24)` | move | yes (`AgendaMotionPolicy`) | **retune** → `move`. |
| C12 | `AgendaView.swift:734` | agenda edit | medium | `.snappy(0.22)` | move | yes | **retune** → `move`. |
| C13 | `AgendaView.swift:1588` | agenda edit | medium | `.snappy` (**no duration** — SwiftUI default, a fifth value) | move | yes | **retune** → `move`. |
| C14 | `AgendaView.swift:1954` month change | tap month arrows | medium | `.snappy(0.2)` | spatial | yes | **retune** → `move`. |
| C15 | `AgendaView.swift:1966` month change (second path) | tap month arrows | medium | `.snappy(0.24)` | spatial | yes | **retune** → `move`. Two different durations for the same gesture in the same file. |
| C16 | `AskCyView.swift:1018` refresh-inbox spin | 4-second poll flips `isRefreshingReviews` | constant while Cy review inbox is open | `.linear(0.9).repeatForever` | progress | **no** | **retune**: gate on Reduce Motion; the in-code comment already flags this as a render-loop problem. |
| C17 | `AskCyView.swift:2194, 2204, 2214` scroll reveals | new message / thinking / end | medium | `.easeOut(0.30)`, `.easeOut(0.25)`, `.easeOut(0.28)` — three values, one job | prevent jarring | yes | **retune** → one `reveal`. Twin at `DevelopBriefView.swift:448 (0.30)`, `:462 (0.25)`. |

## D. Desktop shell (Views/Shell/DesktopAppShellView.swift)

| # | Site | Trigger | Freq | Curve / duration | Purpose | RM gated | Verdict |
|---|---|---|---|---|---|---|---|
| D1 | `DesktopAppShellView.swift:52, 61` utility rail | window resize crosses a breakpoint | low | `.snappy(0.24)` + move/opacity transition | spatial | yes (`DesktopShellMotionPolicy`) | **retune** → `move`. |
| D2 | `DesktopAppShellView.swift:235` creation-hub stage | hub changes stage | low | `AgentModalResize.animation` = `.smooth(0.34)` | prevent jarring | yes | **retune** → `settle` (0.26). Twin at `AskCyView.swift:685`. |
| D3 | `DesktopAppShellView.swift:112` undo toast | task completed | medium | `.transition(.move(.top) + .opacity)` with **no `.animation` and no `withAnimation`** at the mutation site | prevent jarring | **no** | **fix**: same shared toast modifier as B5. Today the phone fades over 240 ms and the desktop pops. |

## E. Capture, Creator Session, and sheets

| # | Site | Trigger | Freq | Curve / duration | Purpose | RM gated | Verdict |
|---|---|---|---|---|---|---|---|
| E1 | `CreationHubView.swift:271` `closeIsPulsing` | walkthrough "quick add" step | rare→constant while shown | `.easeInOut(1.05).repeatForever(autoreverses:)` on scale + **shadow radius** | attention | yes | **retune** → `none` or 3 pulses. Sixth distinct repeat duration in the app. |
| E2 | `QuickCaptureView.swift:88` Cy Pro mark | Cy Pro upsell shown | constant while shown | `.linear(7).repeatForever` rotation | decoration | yes | **remove** → `none`. |
| E3 | `QuickCaptureView.swift:996` dismiss Cy suggestion card | tap × on the suggestion | low | `.easeOut(0.18)` | prevent jarring | **no** | **retune** → `reveal`; gate. |
| E4 | `VoiceSparkView.swift:474` `TimelineView(.periodic(by: 1))` | recording in progress | low | 1 Hz clock | state | n/a | **keep** → `none` (it is a clock, not an animation). Correct use. |
| E5 | `ActiveCreatorSessionFloatingTimer.swift:39` `.contentTransition(.numericText(countsDown:))` | every second while a session runs | constant while running | system | state | **no** | **keep**, but gate: under Reduce Motion use `.identity`. |
| E6 | `ActiveCreatorSessionFloatingTimer.swift:65` appear/disappear | session starts/ends | low | `.move(.bottom) + .opacity`, opacity-only under Reduce Motion | prevent jarring | yes | **keep** → `settle`. Good model for B5/D3. |
| E7 | `ActiveCreatorSessionFloatingTimer.swift:89` | session identity changes | low | `.easeOut(0.20)` | prevent jarring | yes | **retune** → `reveal` (0.18). |
| E8 | `CreatorSessionView.swift:929` theme dots | theme preview changes | low | `.easeOut(0.18)` | move | yes | **keep** → `reveal`. |
| E9 | `CreatorSessionView.swift:1021, 1022` | session phase / pause | low | `.easeOut(0.15)` ×2 | state | yes | **retune** → `reveal` (0.18). |
| E10 | `CreatorSessionView.swift:1296` timer digits `.contentTransition(.numericText)` | every second | constant while running | system | state | **no** | **keep**, gate under Reduce Motion. |
| E11 | `CreatorSessionView.swift:1392, 1400` page change | open/choose timer theme | low | `.easeOut(0.18)` ×2 | spatial | yes | **retune** → `move`. |

## F. Ideas, brief, account, settings

| # | Site | Trigger | Freq | Curve / duration | Purpose | RM gated | Verdict |
|---|---|---|---|---|---|---|---|
| F1 | `InspirationCaptureViews.swift:30` analysis glyph swap | inspiration analysis starts/ends | low | `.spring(0.3, bounce: 0)` crossfading `scaleEffect(0.25 ↔ 1)` + blur, **both directions** | state | yes | **retune** → `reveal`; raise 0.25 → 0.94. Two `scale(0.25)` entrances (`:21`, `:27`). |
| F2 | `InspirationCaptureViews.swift:223` shaped payload arrives | Cy finishes shaping | low | `.easeOut(0.22)` | prevent jarring | yes | **retune** → `reveal`. |
| F3 | `InspirationCaptureViews.swift:405, 417` `.contentTransition(.opacity)` | text swaps | low | system | prevent jarring | n/a | **keep** → `reveal`. |
| F4 | `AgentSwipeDeleteRow.swift:121, 132` | swipe-to-delete release / close | high | `.easeOut(0.16)`; `value.predictedEndTranslation` is used to pick the target but its **velocity is discarded** | gesture | yes | **retune** → `gesture` (`.spring(0.28, bounce: 0)`), so a flick carries and a reversal is interruptible. Standards: springs maintain velocity when interrupted; keyframes/eases restart. |
| F5 | `DevelopBriefView.swift:448, 462` scroll reveals | new message / end | medium | `.easeOut(0.30)`, `.easeOut(0.25)` | prevent jarring | yes | **retune** → one `reveal`. Duplicate of C17. |
| F6 | `AppleAccountAccessView.swift:531` restore mark | account restore in flight | constant while restoring | `.linear(1.6).repeatForever` rotation | progress | yes (`shouldAnimate`) | **keep** → `none` in the vocabulary (a progress spinner is exempt), but move to one shared spinner speed. |
| F7 | `SettingsSubpages.swift:2118` Cy Pro mark | Cy Pro card visible | constant while shown | `.linear(8).repeatForever` rotation | decoration | yes | **remove** → `none`. Seventh distinct repeat duration. |
| F8 | `OnboardingView.swift:158` + `:1225` `stepTransition` | onboarding step change | rare | pure `.move` asymmetric, **no opacity**, no Reduce Motion branch | spatial | **no** | **retune** → `move` + opacity; opacity-only under Reduce Motion. |
| F9 | `OnboardingView.swift:1367` `setStep` | onboarding step change | rare | `.easeInOut(0.24)` | spatial | yes | **retune** → `move` (0.22). |
| F10 | `OnboardingView.swift:824` | onboarding pillar edit | rare | `.snappy(0.24)` | move | yes | **retune** → `move`. |

## G. Sheet and modal presentation

The phone uses only native presentation — 79 `.sheet(` call sites, 38 `presentationDetents`,
3 `fullScreenCover`, 32 drag-indicator modifiers, and **zero** custom sheet drivers. So there is no ad hoc
sheet curve to fix: what Chey reads as "sheets feel slow or springy" is (a) the 340 ms
`AgentModalResize` on desktop and (b) sheet **content** that has to be built before iOS can
present it — see `findings-heaviness.md`. The only custom modal motion in the app is D2/A3.

---

## Duration inventory

Distinct durations in use for UI motion today, and how many sites use each:

| Duration | Sites | Curve(s) | Where |
|---|---|---|---|
| 0.12 s | 1 token, 13 call sites | easeOut | `AgentButtonPressFeedback` |
| 0.15 s | 3 | easeOut | `DesignTokens:1208`, `CreatorSessionView:1021, 1022` |
| 0.16 s | 8 | easeOut, easeInOut | `AppShellView:218, 221`, `HomeDashboardView:1660, 1687`, `AgentSwipeDeleteRow:121, 132`, `ResumablePostEditorView:434, 437` |
| 0.18 s | 4 | easeOut | `CreatorSessionView:929, 1392, 1400`, `QuickCaptureView:996` |
| 0.20 s | 7 | easeOut, snappy | `PillarsView:1705, 1831, 1838, 1848`, `IdeaBankView:774`, `AgendaView:1954`, `ActiveCreatorSessionFloatingTimer:89` |
| 0.22 s | 3 | easeOut, snappy | `AgendaView:734`, `TasksView:2322`, `InspirationCaptureViews:223` |
| 0.24 s | 8 | easeOut, snappy, easeInOut | `AppShellView:159`, `TasksView:612`, `AgendaView:520, 1966`, `IdeaBankView:810`, `DesktopAppShellView:63`, `OnboardingView:824, 1367` |
| 0.25 s | 2 | easeOut | `AskCyView:2204`, `DevelopBriefView:462` |
| 0.26 s | 1 | snappy | `AppShellView:343` |
| 0.28 s | 3 | easeOut, snappy | `AppShellView:319`, `PlanView:219`, `AskCyView:2214` |
| 0.30 s | 4 | easeOut, spring | `AskCyView:2194`, `DevelopBriefView:448`, `AppShellView:644`, `InspirationCaptureViews:31` |
| 0.32 s | 1 | snappy | `AppShellView:849` |
| 0.34 s | 1 token, 2 call sites | smooth | `AgentModalResize` |
| (unspecified `.snappy`) | 1 | snappy | `AgendaView:1588` |
| repeatForever | 0.9, 1.05, 1.15, 1.6, 1.8, 7, 8 s | linear, easeInOut |
| TimelineView | 1.1 s, 1.8 s, 2.8 s, 1 s periodic | — |

Fourteen UI durations and four curve families for what is really five jobs.

## Reduce Motion gaps

Sites that animate with no Reduce Motion branch at all:

| Site | What moves |
|---|---|
| `AppShellView.swift:159` (+ transition at `:115`) | undo toast slides up from the bottom |
| `AppShellView.swift:218, 221` (+ transition at `:94`) | whole bottom nav slides down on every keyboard show |
| `ResumablePostEditorView.swift:434, 437` | same, inside the editor |
| `PillarsView.swift:1705, 1831, 1838, 1848` | pillar sub-tab and edit-mode layout changes |
| `QuickCaptureView.swift:996` | Cy suggestion card collapse |
| `TasksView.swift:2322` | animated scroll to the subtask composer |
| `AskCyView.swift:1018` | perpetual rotation on the refresh control |
| `DesktopAppShellView.swift:112` | undo toast slides down from the top |
| `OnboardingView.swift:158`/`:1225` | onboarding step slides sideways |
| `ActiveCreatorSessionFloatingTimer.swift:39`, `CreatorSessionView.swift:1296` | numeric-text roll every second |
| `DesignTokens.swift:1689` `CyThinkingMark` | **partial** — still runs a TimelineView and pulses under Reduce Motion |

## Continuous ("constant") motion

Nine sites animate with no user action. Three of them animate a **shadow radius**, which
cannot be cached and re-rasterizes every frame.

| Site | Runs when | Shadow animated |
|---|---|---|
| `HomeDashboardView.swift:811` → `DesignTokens.swift:1655` | Home is on screen — i.e. app launch onward | **yes** |
| `AskCyView.swift:918, 1211, 1387` → same | any Cy surface | **yes** |
| `DesignTokens.swift:1689` `CyThinkingMark` | Cy is generating | no |
| `DesignTokens.swift:1627` `CyPendingReviewLogo` | an MCP proposal waits (phone tab bar) | no |
| `AppShellView.swift:903` `CyWeeklyPlanningPulse` | every Monday until Cy is opened | **yes** |
| `AppShellView.swift:724` `WalkthroughControlCue` | walkthrough active | **yes** |
| `CreationHubView.swift:271` | walkthrough "quick add" step | **yes** |
| `QuickCaptureView.swift:88` | Cy Pro upsell visible | no |
| `SettingsSubpages.swift:2118` | Cy Pro card visible | no |
| `AskCyView.swift:1018` | Cy review inbox open (4 s poll) | no |
| `AppleAccountAccessView.swift:531` | account restore in flight (legitimate progress) | no |

## Measurements taken this pass

Device: simulator **"iPhone 17" (iOS 26.5, UDID 1F605047-4304-48C2-8DA0-1D5C72D585BC)** —
"iPhone 17 Pro" was in use by lane L1. Build: the prebuilt Debug `agent.cy.app`.
Launch: `-agentCyPreviewData -agentCyPreviewTab <tab>`.

Method: `xcrun simctl io <udid> recordVideo` writes a **variable-frame-rate** H.264 file —
one frame per composited screen update — so `ffprobe -show_entries frame=pts_time` is a
direct read-out of when the app rendered and for how long. Raw data in
`docs/refinement/evidence/L2/`.

`xcrun xctrace record --attach` against the simulator hung twice without producing a
`.trace` (30 s time limit, killed after 5 min at 52 KB); the frame-timing method above
replaced it and is what every number here rests on.

- Idle frame output per tab — `evidence/L2/idle-frames-by-tab.txt`
- Tab-switch burst durations — `evidence/L2/tab-switch-bursts.txt`
- Cold launch milestones — `evidence/L2/launch-milestones.txt`
