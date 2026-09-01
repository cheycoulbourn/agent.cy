# Draft: the Motion section for `design.md`

Proposed by lane L2. `design.md` has no motion section today; `AgentModalResize` and
`AgentButtonPressFeedback` in `DesignTokens.swift` are the only shared timings in the app.
Every row of `motion-census.md` maps to exactly one entry below, or to **none**.

---

## Motion

Agent.cy is a working tool. Motion here has one job: to keep a change legible. It never
performs, never bounces, and never asks to be watched. If a change is already obvious,
it does not animate.

### The five animations

There are five, and there are only five. Nothing in the app invents a curve or a duration.

| Name | Curve and duration | Use it for | Never for |
|---|---|---|---|
| **Press** | `easeOut` 0.12 s | The scale and opacity dip under a finger on any pressable thing. | Anything that is not a press. |
| **Reveal** | `easeOut` 0.18 s | Something small appears or disappears in place: a chip, a checkbox fill, an inline card, a status line, the bottom nav yielding to the keyboard, an animated scroll to a new row. | Something moving across the screen. |
| **Move** | `easeInOut` 0.22 s | Something already on screen changes place or size: the tab pill, a segmented selection, a week or month change, an onboarding step, a list reordering, edit mode opening a form. | Entering or leaving. |
| **Settle** | `easeOut` 0.26 s | A whole surface arrives or leaves: a toast, a walkthrough card, the floating session timer, the desktop utility rail, a desktop modal changing stage. | Anything you meet more than a few times an hour. |
| **Gesture** | `spring(duration: 0.28, bounce: 0)` | The release of a drag, and only the release of a drag: swipe-to-delete, drag-to-dismiss. A spring is used here because it keeps the finger's velocity and can be reversed mid-flight; an ease cannot. | Anything a finger is not already holding. |

Nothing in the app uses `.snappy`, `.smooth`, or `.bouncy`. Those are springs with
overshoot, and overshoot on a tool reads as slack.

### What is never animated

- **Tab content.** Switching tabs swaps the screen with animation explicitly suppressed. The
  tab bar's pill uses **Move**; the content behind it does not animate at all.
- **Anything that repeats.** No `repeatForever`. A mark that spins forever is a mark that
  costs a frame forever. The one exception is a genuine progress indicator while a network
  call is actually in flight, and it stops the moment the call returns.
- **Shadows.** A shadow radius or opacity is never a target of an animation; it cannot be
  cached and re-rasterizes every frame. Animate `opacity` and `scale`, never `shadow`.
- **Anything that appears from nothing.** An entrance starts at `scale 0.94` and `opacity 0`,
  never at `scale 0` or anything below `0.9`.
- **Keyboard-repeatable actions.** Anything a creator does tens of times an hour — checking a
  task, moving between task collections, typing — gets **Press** or nothing.

### Reduce Motion

Reduce Motion is not "no motion". It is "no travel".

1. Every animation is created through `AgentMotion`, which returns `nil` for anything that
   moves or scales when Reduce Motion is on.
2. Every `.transition` that includes `.move`, `.offset`, `.scale`, or `.slide` collapses to
   `.opacity` at the same duration. Comprehension is preserved; travel is removed.
3. Continuous motion **stops**. It is not slowed. A `TimelineView` is not entered at all —
   the static branch renders instead.
4. `.contentTransition(.numericText)` becomes `.identity`.

There is one helper and it is the only way motion enters a view:

```swift
enum AgentMotion {
    static let press  = Animation.easeOut(duration: 0.12)
    static let reveal = Animation.easeOut(duration: 0.18)
    static let move   = Animation.easeInOut(duration: 0.22)
    static let settle = Animation.easeOut(duration: 0.26)
    static let gesture = Animation.spring(duration: 0.28, bounce: 0)

    /// The only way an animation reaches a view. Returns nil under Reduce Motion.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Collapses any travelling transition to a fade under Reduce Motion.
    static func transition(_ base: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : base
    }

    /// Wraps a mutation. Use instead of a bare `withAnimation`.
    @MainActor
    static func run(_ animation: Animation, reduceMotion: Bool, _ changes: () -> Void) {
        if let resolved = resolved(animation, reduceMotion: reduceMotion) {
            withAnimation(resolved, changes)
        } else {
            changes()
        }
    }

    /// The one permitted entrance geometry.
    static let entranceScale: CGFloat = 0.94
}
```

`AgentButtonPressFeedback` keeps its existing shape and simply returns `AgentMotion.press`,
so the thirteen button styles do not change. `AgentModalResize` is deleted; its two call
sites take `AgentMotion.settle`.

On Mac Catalyst, `AgentMotion.press` returns `nil` (a pointer has hover; it does not need a
press dip). Every other entry behaves the same on both form factors.

---

## Mapping from the census

| Vocabulary entry | Census rows |
|---|---|
| **Press** | A1, A2 |
| **Reveal** | A4, B3, B4, C2, C6, C17, E3, E7, E8, E9, F2, F3, F5, and the phone keyboard pair in `ResumablePostEditorView` |
| **Move** | B2, C3, C4, C7, C8, C9, C11, C12, C13, C14, C15, D1, E11, F8, F9, F10 |
| **Settle** | A3, B5, B7, B8, B9, C10, D2, D3, E6 |
| **Gesture** | F4 |
| **none** (animation removed) | A5, A6, B1, B11, B12, C1, C5 (phone branch), C16, E1, E2, E5, E10, F1's blur, F7 |
| **exempt** (real progress, real clock) | E4, F6, and `CyThinkingMark` (A7) once it is throttled and given a static Reduce Motion branch |

## What this changes in numbers

- Fourteen UI durations → **five**.
- Four curve families (`easeOut`, `easeInOut`, `snappy`, `smooth`, plus two zero-bounce
  springs) → **two eases and one spring**.
- Seven `repeatForever` durations → **zero** in shipped decoration.
- Eleven sites with no Reduce Motion branch → **zero**, because the helper is the only door.
- Longest UI animation: 0.34 s → **0.28 s**, under the 300 ms ceiling.

## Sites the shared change touches

`AgentMotion` is a new type in `Design/DesignTokens.swift`. Adopting it touches every file
in the census: `Design/DesignTokens.swift`, `Views/Shell/AppShellView.swift`,
`Views/Shell/DesktopAppShellView.swift`, `Views/Home/HomeDashboardView.swift`,
`Views/Plan/PlanView.swift`, `Views/Tasks/TasksView.swift`, `Views/Pillars/PillarsView.swift`,
`Views/Ideas/IdeaBankView.swift`, `Views/Ideas/InspirationCaptureViews.swift`,
`Views/Agenda/AgendaView.swift`, `Views/Cy/AskCyView.swift`, `Views/Brief/DevelopBriefView.swift`,
`Views/Brief/ResumablePostEditorView.swift`, `Views/Brief/PostMediaViews.swift`,
`Views/Capture/CreationHubView.swift`, `Views/Capture/QuickCaptureView.swift`,
`Views/Capture/CreatorSessionView.swift`, `Views/Capture/ActiveCreatorSessionFloatingTimer.swift`,
`Views/Capture/VoiceSparkView.swift`, `Views/Settings/SettingsSubpages.swift`,
`Views/Account/AppleAccountAccessView.swift`, `Views/Onboarding/OnboardingView.swift`,
`Views/Shared/AgentSwipeDeleteRow.swift`.

The existing motion-policy enums (`AgendaMotionPolicy`, `TaskRootMotionPolicy`,
`DesktopShellMotionPolicy`, `IdeaBankRootAccessibilityPolicy`, `AppShellMotionPolicy`,
`CyAnimatedLogoMotionPolicy`) are already unit-tested indirection for the same question and
should be folded into `AgentMotion.resolved` so there is one answer, not six.
