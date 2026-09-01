# L2 · Motion findings (batch B2)

Lane L2. Evidence produced this pass; see `motion-census.md` for the full site list and
`docs/refinement/evidence/L2/` for raw measurements. Simulator: **"iPhone 17" (iOS 26.5,
UDID `1F605047-4304-48C2-8DA0-1D5C72D585BC`)** — "iPhone 17 Pro" was in use by lane L1.

---

### L2M-01 The Home tab never stops rendering, because a decorative Cy mark runs a perpetual `TimelineView`
- Where: `ios/AgentCy/Views/Home/HomeDashboardView.swift:811` -> `ios/AgentCy/Design/DesignTokens.swift:1644-1680` (`CyAnimatedLogo`); same mark on `Views/Cy/AskCyView.swift:918, 1211, 1387`; page slugs `home`, `cy`
- Evidence: `docs/refinement/evidence/L2/idle-frames-by-tab.txt`. With the app launched into a tab and then **left completely untouched for 10 seconds**, `xcrun simctl io … recordVideo` (variable frame rate — one frame per composited update) records:

  | Tab | Frames | Window | Effective rate |
  |---|---|---|---|
  | `home` | 300 | 9.98 s | 30.1 fps |
  | `cy` | 599 | 9.98 s | 60.0 fps |
  | `plan-week` | 1 | 12.0 s | idle |
  | `pillars` | 1 | 10.0 s | idle |
  | `idea-bank` | 1 | 10.0 s | idle |

  The animated mark rotates, scales, **and animates its shadow radius** every frame
  (`DesignTokens.swift:1673-1679`):
  ```swift
  CyAsterisk(color: color, size: size, strokeWidth: strokeWidth)
      .rotationEffect(.degrees(progress * 45))
      .scaleEffect(0.97 + (pulse * 0.06))
      .shadow(color: color.opacity(0.12 + (pulse * 0.12)), radius: 5 + (pulse * 4))
  ```
  An animated shadow radius cannot be cached and re-rasterizes on every frame.
- Severity: blocker
- Fix: delete the perpetual timeline. `CyAnimatedLogo` renders the static `CyAsterisk` branch it already has for Reduce Motion, for everyone. If a "Cy is alive" cue is wanted, run one 2.8 s cycle on appear and stop, and animate `opacity` only, never `shadow`. Shared change: `CyAnimatedLogo` and `CyAnimatedLogoMotionPolicy` in `DesignTokens.swift`; call sites `HomeDashboardView.swift:811`, `AskCyView.swift:918, 1211, 1387`. Proof: re-run the idle recording; `home` and `cy` must fall to 1 frame per 10 s like every other tab.
- Batch: B2
- Status: open

### L2M-02 Nine decorative animations run forever with no user action, four of them animating a shadow radius
- Where: `DesignTokens.swift:1627` (`CyPendingReviewLogo`, lives in the **phone tab bar**), `DesignTokens.swift:1655`, `DesignTokens.swift:1689`, `Views/Shell/AppShellView.swift:724`, `Views/Shell/AppShellView.swift:903`, `Views/Capture/CreationHubView.swift:271`, `Views/Capture/QuickCaptureView.swift:88`, `Views/Settings/SettingsSubpages.swift:2118`, `Views/Cy/AskCyView.swift:1018`
- Evidence: seven distinct `repeatForever` durations — `0.9 s` (`AskCyView.swift:1020`), `1.05 s` (`CreationHubView.swift:271`), `1.15 s` (`AppShellView.swift:724`), `1.6 s` (`AppleAccountAccessView.swift:533`), `1.8 s` (`DesignTokens.swift:1628`), `7 s` (`QuickCaptureView.swift:89`), `8 s` (`SettingsSubpages.swift:2119`) — plus three `TimelineView` cycles at 1.1 s, 1.8 s and 2.8 s. Shadow radius is an animation target at `DesignTokens.swift:1676-1679`, `AppShellView.swift:717-720`, `AppShellView.swift:923-926`, `CreationHubView.swift:229-232`. The code already knows this is a problem: `AskCyView.swift:1015-1017` carries the comment that restarting a `repeatForever` "kept the render loop busy the whole time Cy was open".
- Severity: major
- Fix: a `design.md` rule — nothing in shipped decoration uses `repeatForever`, and no animation targets a shadow. Genuine progress indicators (`AppleAccountAccessView.swift:531` during restore, `AskCyView.swift:1018` during a refresh) are exempt but share one spinner speed. `CyPendingReviewLogo` becomes a static tinted mark: a spinning glyph in the persistent tab bar means the shell can never idle on any screen. Shared change; sites listed above.
- Batch: B2
- Status: open

### L2M-03 The tab bar runs a 320 ms spring on the app's most frequent action
- Where: `ios/AgentCy/Views/Shell/AppShellView.swift:849`; all six tab roots, phone
- Evidence: `.animation(reduceMotion ? nil : .snappy(duration: 0.32), value: selection)` driving a `matchedGeometryEffect` glass pill (`AppShellView.swift:794`). `docs/refinement/evidence/L2/tab-switch-bursts.txt`: six consecutive tab taps produced continuous render bursts of **503 ms, 508 ms and 518 ms**, separated by multi-second idle. `.agents/skills/review-animations/STANDARDS.md`: tens of times a day -> "Remove or drastically reduce"; springs are reserved for gestures; UI stays under 300 ms.
- Severity: major
- Fix: `.easeInOut(duration: 0.22)` (`AgentMotion.move`). The content layer is already right — `appTabLayer` (`AppShellView.swift:733-741`) explicitly sets `transaction.animation = nil`. Proof: the per-tap render burst should fall from ~510 ms to under 260 ms in the same recording.
- Batch: B2
- Status: open

### L2M-04 Eleven animation sites have no Reduce Motion branch, and `CyThinkingMark` honours it only partly
- Where: `AppShellView.swift:159` (+`:115`), `AppShellView.swift:218, 221` (+`:94`), `ResumablePostEditorView.swift:434, 437`, `PillarsView.swift:1705, 1831, 1838, 1848`, `QuickCaptureView.swift:996`, `TasksView.swift:2322`, `AskCyView.swift:1018`, `DesktopAppShellView.swift:112`, `OnboardingView.swift:158`/`:1225`, `ActiveCreatorSessionFloatingTimer.swift:39`, `CreatorSessionView.swift:1296`, `DesignTokens.swift:1689`
- Evidence: none of these sites consult `accessibilityReduceMotion`. `AppShellView.swift:159` — `.animation(.easeOut(duration: 0.24), value: appModel.taskCompletionUndo)` — slides the undo toast up the screen unconditionally. `AppShellView.swift:218` — `withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = true }` — slides the whole bottom navigation off screen on every text-field focus. `OnboardingView.swift:1226-1228` builds a pure `.move` transition with no opacity and no Reduce Motion branch. `CyThinkingMark` (`DesignTokens.swift:1689-1707`) still enters a `TimelineView` under Reduce Motion and pulses scale 0.94->1.06 and opacity 0.68->1. `docs/refinement/00-contract.md` lists "Reduce Motion honored on every animation" as a non-negotiable.
- Severity: blocker
- Fix: route every animation through one helper (`AgentMotion.resolved` / `AgentMotion.transition` / `AgentMotion.run`, proposed in `draft-motion-section.md`) that returns `nil` for travel and collapses travelling transitions to `.opacity`. Fold the six existing per-file motion policies (`AgendaMotionPolicy`, `TaskRootMotionPolicy`, `DesktopShellMotionPolicy`, `IdeaBankRootAccessibilityPolicy`, `AppShellMotionPolicy`, `CyAnimatedLogoMotionPolicy`) into it so there is one answer, not six. Shared change; sites listed above.
- Batch: B2
- Status: open

### L2M-05 Fourteen durations and four curve families do the work of five animations
- Where: whole app; inventory in `motion-census.md`, section "Duration inventory"
- Evidence: 0.12, 0.15, 0.16, 0.18, 0.20, 0.22, 0.24, 0.25, 0.26, 0.28, 0.30, 0.32, 0.34 s plus one bare `.snappy` with no duration (`AgendaView.swift:1588`), spread across `.easeOut`, `.easeInOut`, `.snappy`, `.smooth` and two zero-bounce `.spring`s. The duplication is inside single files: `AgendaView.swift:1954` uses `.snappy(0.2)` and `AgendaView.swift:1966` uses `.snappy(0.24)` for the same month change; `AskCyView.swift:2194, 2204, 2214` use `.easeOut(0.30)`, `.easeOut(0.25)` and `.easeOut(0.28)` for three scroll reveals in one view; `AppShellView.swift:319` and `:343` use `.snappy(0.28)` and `.snappy(0.26)` for the same walkthrough transition; `DevelopBriefView.swift:448, 462` repeat the AskCy pair.
- Severity: major
- Fix: adopt the five-token vocabulary in `draft-motion-section.md`. `AgentModalResize` is deleted and its two call sites take `AgentMotion.settle`; `AgentButtonPressFeedback` returns `AgentMotion.press`, so the thirteen button styles are untouched. Shared change; the full touched-file list is in `draft-motion-section.md`, section "Sites the shared change touches".
- Batch: B2
- Status: open

### L2M-06 The longest UI animation in the app is 340 ms, over the 300 ms ceiling, and it is a spring
- Where: `ios/AgentCy/Design/DesignTokens.swift:497` (`AgentModalResize.animation = .smooth(duration: 0.34)`); call sites `Views/Shell/DesktopAppShellView.swift:235` and `Views/Cy/AskCyView.swift:685`; page slugs `creation-hub-overlay-desktop`, `ask-cy-review-desktop-workspace`
- Evidence: `static let animation: Animation = .smooth(duration: 0.34)`. `.smooth` is a spring. `STANDARDS.md`: "Rule: UI animations stay under 300ms." This is the desktop modal resize that Chey describes as sheets feeling slow and springy.
- Severity: major
- Fix: `AgentMotion.settle` = `.easeOut(duration: 0.26)`. Keep the existing two-frame trick at both sites (lay the content out at its target size with animation suppressed, animate the cheap outer frame over it) — that part is correct and already commented at `AskCyView.swift:676-684`.
- Batch: B2
- Status: open

### L2M-07 Three entrances scale up from near-nothing
- Where: `ios/AgentCy/Views/Shell/AppShellView.swift:669` (`scaleEffect(isVisible ? 1 : 0.25)`), `ios/AgentCy/Views/Ideas/InspirationCaptureViews.swift:21` and `:27` (`scaleEffect(isProcessing ? 0.25 : 1)` and its mirror), `ios/AgentCy/Design/DesignTokens.swift:1204` (`scaleEffect(isCompleted ? 1 : 0.6)`); page slugs `walkthrough-overlay`, `inspiration-review`, plus every task checkbox
- Evidence: the three `scaleEffect` values above. `STANDARDS.md`: "Never `scale(0)`. Start from `scale(0.9–0.97)` + `opacity: 0`. Nothing in the real world appears from nothing."
- Severity: minor
- Fix: one `AgentMotion.entranceScale = 0.94` at all three sites, with `opacity` doing the rest. The `.blur(radius: 4)` crossfade at `InspirationCaptureViews.swift:22, 28` may stay — it is the documented way to mask an imperfect crossfade — capped where it is.
- Batch: B2
- Status: open

### L2M-08 The undo toast animates on the phone and pops on the desktop
- Where: phone `ios/AgentCy/Views/Shell/AppShellView.swift:110-119` and `:159`; desktop `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:108-115`; page slug `task-completion-undo-toast`, both form factors
- Evidence: the phone declares `.transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))` **and** `.animation(.easeOut(duration: 0.24), value: appModel.taskCompletionUndo)`. The desktop declares `.transition(.move(edge: .top).combined(with: .opacity))` and nothing drives it: `taskCompletionUndo` appears in `DesktopAppShellView.swift` only at lines 109, 110 and 1647, and there is no `.animation(…, value:)` for it and no `withAnimation` at the mutation site. Neither shell is Reduce Motion gated (see L2M-04).
- Severity: major
- Fix: one shared `AgentUndoToast` modifier carrying the transition, `AgentMotion.settle` and the Reduce Motion collapse; both shells call it. Sites: `AppShellView.swift:110-119, 159, 349`, `DesktopAppShellView.swift:108-115, 1647`.
- Batch: B2
- Status: open

### L2M-09 Swipe-to-delete throws away the finger's velocity on release
- Where: `ios/AgentCy/Views/Shared/AgentSwipeDeleteRow.swift:110-125` and `:130-136`
- Evidence: the gesture reads `value.predictedEndTranslation.width` to choose the resting state, then animates to it with `withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16))` — a fixed 160 ms ease that starts from zero velocity however fast the row was moving, and restarts from zero if the creator swipes back before it settles. `STANDARDS.md`: "Springs maintain velocity when interrupted (keyframes restart from zero), so they're ideal for gestures users may reverse mid-motion."
- Severity: minor
- Fix: `AgentMotion.gesture` = `.spring(duration: 0.28, bounce: 0)` at both call sites. This is the one place in the app where a spring is correct.
- Batch: B2
- Status: open

### L2M-10 Tasks double-animates its collection change
- Where: `ios/AgentCy/Views/Tasks/TasksView.swift:612-617` and `:668-680`; page slug `tasks`, phone
- Evidence: on phone, `taskCollectionContent` is a `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))`, which runs the system paging animation on `$collection`, while the parent also declares `.animation(TaskRootMotionPolicy.usesCollectionAnimation(…) ? .snappy(duration: 0.24) : nil, value: collection)`. Two animations drive the same state change. The Catalyst branch is a plain `.transition(.opacity)` and does not have this problem.
- Severity: minor
- Fix: drop the outer `.animation` on the phone branch (`none` in the vocabulary); keep `AgentMotion.reveal` on the Catalyst `.transition(.opacity)`.
- Batch: B2
- Status: open

### L2M-11 The onboarding step transition slides with no fade and disagrees with its own Reduce Motion branch
- Where: `ios/AgentCy/Views/Onboarding/OnboardingView.swift:158` and `:1225-1229`; page slug `onboarding-flow`
- Evidence:
  ```swift
  private var stepTransition: AnyTransition {
      let insertion = AnyTransition.move(edge: transitionEdge)
      let removal = AnyTransition.move(edge: transitionEdge == .trailing ? .leading : .trailing)
      return .asymmetric(insertion: insertion, removal: removal)
  }
  ```
  No `.combined(with: .opacity)` and no Reduce Motion branch. The mutation at `:1363-1369` **is** gated, so under Reduce Motion the step swaps with no animation while the transition still declares travel — the two halves disagree.
- Severity: minor
- Fix: `.move(...).combined(with: .opacity)` routed through `AgentMotion.transition(_:reduceMotion:)` and driven by `AgentMotion.move`. Onboarding is a rare surface, so animating it is right; only its correctness is at issue.
- Batch: B2
- Status: open

---

## Needs Chey's iPhone to settle (gate G-device)

- **L2M-01 / L2M-02 in battery terms.** The simulator proves the frames are produced; only her
  device shows what a continuously compositing Home costs in battery and thermals over a real
  session.
- **L2M-03 tab-switch feel.** 503–518 ms of render is measurable here; whether 0.22 s
  `easeInOut` reads as *right* rather than merely *faster* is a device judgement.
- **`CyThinkingMark` at 120 Hz.** `TimelineView(.animation)` with no `minimumInterval`
  (`DesignTokens.swift:1689`) ticks at display rate. The simulator composites at 60 Hz, so the
  ProMotion cost is unmeasured here.
- **L2M-09 swipe feel.** `STANDARDS.md` is explicit that drawers and swipe gestures must be
  judged on real hardware.
