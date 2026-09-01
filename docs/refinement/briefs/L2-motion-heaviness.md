# L2 · Motion and heaviness lane

Read `docs/refinement/briefs/_common.md` first. Outputs: `docs/refinement/motion-census.md`, `docs/refinement/findings-motion.md`, `docs/refinement/findings-heaviness.md`, `docs/refinement/draft-motion-section.md`.

Chey's words: the app "feels heavy"; "transitions and sheets feel slow or springy". Two questions: what motion is wrong, and what is actually slow.

## Standards

Use `.agents/skills/review-animations/STANDARDS.md` and `.agents/skills/apple-design/SKILL.md` in the repo as the yardstick (frequency table, ease-out for enter/exit, under 300 ms for UI, no spring on frequent actions, never scale from 0, Reduce Motion). `design.md` has no motion section; `AgentModalResize` and `AgentButtonPressFeedback` in DesignTokens are the only shared timings today.

## Motion method

1. Census every animation site in `ios/AgentCy`: `withAnimation`, `.animation(`, `.transition(`, `.snappy`, `.spring`, `.easeOut`, `.easeIn`, `.easeInOut`, `.smooth`, `.bouncy`, `repeatForever`, `matchedGeometryEffect`, `symbolEffect`, `phaseAnimator`, `keyframeAnimator`, `TimelineView`, `.contentTransition`, `.scrollTransition`, plus custom sheet or modal presentation helpers. One row per site: file:line, what triggers it, how often a user meets it per day (frequency class), curve, duration, purpose (spatial, state, feedback, prevent jarring, decoration), Reduce Motion gated (yes/no/partial), verdict (keep / retune to X / remove) with the exact replacement value.
2. Look specifically at: tab switching in both shells, sheet and modal presentation (native vs custom, and the desktop workspace modal resize), the floating Cy button, the pulsing close control (`closeIsPulsing`), keyboard show/hide, list insert/delete, undo toasts, onboarding, Creator Session timer, Cy thinking mark.
3. Draft the Motion section for `design.md` (in `draft-motion-section.md`): a named vocabulary of at most five animations with curve and duration, when each is used, the Reduce Motion rule, and what is never animated. Propose the Swift token set (`AgentMotion.*`) that implements it. Every census row's verdict must map to one vocabulary entry or "none".

## Heaviness method

1. Census whole-table `@Query` declarations per root view and per sheet, computed collections derived inside `body`, `onAppear`/`task` work on tab roots, and observation scope (what observes `AppModel`, which is about 5,000 lines). Cite file:line and counts.
2. Measure on the simulator, not by inference. Use the fixture launch flags and either `Self._printChanges()` instrumentation notes or `xcrun xctrace record --template 'Time Profiler' --device <simulator udid> --attach <pid>` (works on simulators) during: cold open to Home, switching all six tabs twice, opening and closing the post editor, typing ten characters in Quick Capture and in the Idea Bank search, scrolling Agenda a week forward and back. Record what you measured and the top app frames. If you cannot attach, record body-update counts by another method and say which.
3. Rank causes by measured cost. Do not carry the archived one-second Home hang as a fact; re-measure it and report what you see.
4. Findings each propose a fix with the measurement that will prove it (before and after).

## Deliverables

- Census file, two findings files (batch B2), and the draft Motion section with the token set.
- Note anything that needs Chey's iPhone to settle (that is gate G-device; list it, do not ask her).
