# PAGE-MAIN-04 Audit: Pillars

- Audit date: 2026-08-18
- Status: `Coverage gap`
- Repair verified: 2026-08-18
- Scope owner: [`PillarsView`](../../ios/AgentCy/Views/Pillars/PillarsView.swift), the root hierarchy/usage/accessibility policies in the same file, and Pillars preview fixtures in [`PreviewData`](../../ios/AgentCy/Preview/PreviewData.swift)
- Parent programs: [`AUD-05`](../APP_AUDIT_QUEUE.md#aud-05-planning-tasks-calendar-reminders-widgets) and [`AUD-07`](../APP_AUDIT_QUEUE.md#aud-07-page-ui-accessibility-performance-and-catalyst-parity)

## Frozen contract

Pillars is the active workspace's top-level content-theme index. It presents exactly one active anchor and every other active pillar as a reachable secondary pillar, even when legacy data has an invalid parent or role. Archived pillars do not appear in the active hierarchy. The page shows the current Monday-through-Sunday planned/posted mix, keeps the six-pillar total limit truthful, and carries the creator's selected palette into first-pillar creation.

| Event or state | Expected behavior |
| --- | --- |
| No active pillars | Explain the anchor concept and offer one Create your anchor action. |
| Anchor and branches | Resolve one deterministic anchor and keep every other active pillar reachable exactly once. |
| Legacy orphan or extra root | Recover it into the visible secondary list instead of presenting a false empty state or silently hiding it. |
| Archived pillar | Exclude it from the active hierarchy and capacity count without hiding the remaining active pillars. |
| Six-pillar limit | Show five of five secondary pillars and explain that every secondary spot is in use; do not offer an invalid add action. |
| Weekly usage | Count each qualifying brief once in a half-open Monday-through-next-Monday interval, then derive all root metrics from one projection. |
| First pillar color | Use the active workspace's selected onboarding palette, with a safe legacy profile/fallback path. |
| Retained clock | Refresh weekly usage on appearance, active foreground, and significant-time changes. |
| Accessibility | Preserve complete semantic labels, stack root metadata and metrics at accessibility sizes, make education scrollable, and replace compact weekday chips with full weekday checkbox rows. |
| Reduce Motion | Do not depend on a delayed animated task to open the guide. |

## Function and exit trace

| Pillars area | Source data | Canonical exit |
| --- | --- | --- |
| Header | active creator/workspace identity | About pillars popover or Settings |
| Usage strip | one root projection across active pillars, briefs, and outputs | informational only |
| Anchor hero | deterministic active hierarchy plus root metric | anchor Pillar detail |
| Secondary list | every other unique active pillar plus root metrics | selected Pillar detail |
| Capacity state | active hierarchy count and six-pillar policy | New pillar when below limit; explanatory limit state at five branches |
| Empty state | no active hierarchy | New anchor sheet |
| About popover | shared education copy | Pillar guide |
| New pillar sheet | exact parent request plus active workspace palette | save or cancel |
| Persistent shell | shell-owned tab state | Home, Plan, Tasks, Idea Bank, Cy, or Quick Add |

Pillar detail, Pillar guide, and the full New pillar editor remain separate deeper contracts under `PAGE-WORK-11`, `PAGE-WORK-12`, and `PAGE-WORK-13`. This root pass covers their entry request, exact parent/palette handoff, and accessible weekday selector presentation, not their complete internal lifecycle.

## Repair verification

| Confirmed cause | Repair and evidence |
| --- | --- |
| Root selection assumed one valid nil-parent hierarchy, so multiple roots and orphaned supporting pillars could disappear or produce a false empty state. | `PillarRootHierarchyPolicy` de-duplicates, excludes archived records, resolves one deterministic anchor, and exposes every other active pillar as a branch. |
| Weekly usage repeatedly scanned briefs and outputs for the anchor, strip, and each branch and admitted the exact next-Monday boundary through `DateInterval.contains`. | `PillarRootProjectionPolicy` creates one brief/output/idea projection; schedule inclusion is explicitly `targetDate >= start && targetDate < end`. |
| Retained Pillars state captured the current week only during recomputation initiated by unrelated data changes. | One `pillarsNow` reference refreshes on appearance, active foreground, and significant-time notifications. |
| New-pillar presentation carried its parent through separate mutable state and could briefly show the fallback sage before an async palette update. | Identifiable `NewPillarRequest` carries the exact parent and initial palette color into the sheet's initializer. The first active pillar receives the first selected palette color immediately. |
| The limit UI did not explain its branch capacity precisely. | The root presents `5 of 5` and “All five secondary pillar spots are in use,” while creation remains unavailable at six total pillars. |
| Root metrics and branch fragments compressed or truncated at accessibility text sizes; all color swatches announced the same label; education used a fixed non-scrolling popover. | Stats, branch metadata, and anchor metadata stack; rows expose complete labels; swatches announce position, hex, and selection; the education popover scrolls at accessibility sizes. |
| The New pillar form retained seven compact weekday circles at accessibility text sizes. | Normal sizes retain the compact chooser; accessibility sizes use full Monday-through-Sunday checkbox rows with selected/not-selected values. |
| Guide presentation used an unstructured delayed task. | The transition is view-scoped, cancellation-aware, yields once, and guards the selected tab before navigation. |

## Automated evidence

- **7 PAGE-MAIN-04 regressions passed**: duplicate-safe hierarchy and orphan recovery, one-pass unique metrics, exact next-Monday exclusion, workspace palette handoff, accessibility presentation policy, and six-pillar capacity copy.
- The full shared iOS suite passed **604 tests with 0 failures** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data.
- The `AgentCy Desktop` Catalyst target compiled successfully.
- `pnpm typecheck`, all **140 TypeScript tests**, and `pnpm build` passed in the same working tree.
- Scoped `git diff --check` passed for the Pillars source, preview/test additions, generated project, and audit files.

## Runtime evidence

One disposable iPhone 17 Pro / iOS 26.5 simulator used an in-memory model container and explicit Pillars fixtures. The audit visually inspected:

1. Normal anchor plus two branches in light and dark appearance.
2. Empty, archived, five-branch limit, and malformed orphan/root recovery states.
3. Accessibility Extra Extra Extra Large root layout after stacking anchor metadata, branch details, and stats.
4. The accessibility education popover with scrollable long-form content.
5. First-anchor creation with the `Too Cool` workspace palette; the first swatch was selected immediately from palette color `440607` rather than the fallback earth palette.
6. First-anchor creation at Accessibility Extra Extra Extra Large; weekday chips were replaced by full weekday checkbox rows and the Form remained vertically scrollable.

The persistent floating navigation intentionally overlays the scrolling surface. The root supplies 140 points of trailing scroll content, but the locked session prevented a driven swipe-to-bottom proof, so bottom-clearance remains in the runtime gap rather than being declared verified from a still image.

## Remaining runtime coverage gap

The Mac remained locked after the user stepped away, so the audit did not bypass the session to drive live taps or VoiceOver. Before reclassifying this page as `Verified`, record one unlocked pass that:

1. Opens About, follows the guide, returns, opens the anchor and every branch, returns, opens Settings, switches every tab, and verifies missing/deleted destinations use the honest fallback.
2. Creates an anchor and a secondary pillar, verifies the exact requested parent, confirms the saved first-pillar color matches the onboarding palette, reaches the five-branch limit, and cancels a second creation attempt without an orphan.
3. Scrolls empty, normal, limit, orphan-recovery, and maximum-text layouts fully above the persistent navigation and checks keyboard dismissal plus focus restoration.
4. Replays actual VoiceOver order, labels, traits, checkbox values, selected color announcements, and actual Reduce Motion.
5. Foregrounds the retained page across a real Monday boundary or time-zone change and confirms weekly counts and percentages rebase together.

## Deferred deeper-page clauses

- `PAGE-WORK-11`: settle Scheduled tab versus weekly-usage inclusion, posted `targetDate` versus `postedAt` semantics, anchor deletion scope, legacy root recovery, skipped-task cleanup, and partially posted output overlap.
- `PAGE-WORK-12`: verify the guide's large-text range rows, animations, navigation, and education copy as its own page.
- `PAGE-WORK-13`: verify full New pillar validation, editing, weekday persistence, custom color input, keyboard behavior, save failures, and relaunch persistence.
- Product decision: whether archived pillars need a visible archive/restore index rather than remaining excluded from the active root.

## Performance and smoothness

Classification: **one resolved deterministic work risk plus two open profiling risks**.

- The root now builds schedule counts, idea counts, percentages, and row metrics once per projection instead of repeatedly scanning all briefs and outputs for each visible pillar.
- Sheet requests now carry immutable parent/color context and the guide transition uses structured view lifetime, reducing stale presentation work.
- `PillarsView.swift` is 2,370 lines. The root owns five whole-table `@Query` collections; the deeper detail owner owns another five and performs its own derived work. This is a risk signal, not proof of a hitch.
- `PERF-RISK-12` requires Release-device profiling with production-sized small, medium, and large workspaces. Measure root/deeper body invalidations, SwiftData fetches, projection time, scrolling/frame hitches, retained-tab background work, sheet latency, detail-tab switching, and memory before splitting query owners or adding more indexes.
- `PERF-RISK-07` still requires Release-device measurement of the retained six-stack phone shell and its root-wide `NavigationRequestObserver` warning.

## Resolved defects and remaining coverage

1. `DEFECT-MAIN-04-01` — **Resolved**: malformed roots/orphans and duplicate IDs no longer hide active pillars or invent a false empty state.
2. `DEFECT-MAIN-04-02` — **Resolved**: weekly usage excludes next Monday and is projected in one pass.
3. `DEFECT-MAIN-04-03` — **Resolved**: retained week state refreshes on lifecycle/time changes.
4. `DEFECT-MAIN-04-04` — **Resolved**: new-pillar parent and selected palette color arrive atomically; the first pillar uses the chosen palette.
5. `DEFECT-MAIN-04-05` — **Resolved**: the six-pillar limit and five-branch capacity use one truthful rule and message.
6. `DEFECT-MAIN-04-06` — **Resolved**: root metadata, metrics, education, color labels, and weekday selection adapt at accessibility sizes.
7. `DEFECT-MAIN-04-07` — **Resolved**: guide navigation no longer relies on an unstructured delay.
8. `PERF-RISK-12` — **Open**: the large root/deeper owner and remaining derived work need Release-device profiling.
9. `PERF-RISK-07` — **Open**: retained root-shell work and warning impact need Release-device measurement.
10. `GAP-MAIN-04-01` — **Open**: unlocked tap, creation/persistence, VoiceOver, actual Reduce Motion, real week rollover, and bottom-clearance replay remain required.

## Second opinion

Fable independently highlighted malformed hierarchy reachability, repeated usage aggregation, the next-Monday boundary, retained-clock drift, sheet state coupling, unstructured guide presentation, and the accessibility/presentation risks. Local inspection confirmed onboarding already writes the selected palette to both the profile and workspace; the repair therefore preserves that current source and adds only a safe legacy fallback. Fable was advisory and made no edits.

## Classification and next gate

PAGE-MAIN-04 is closed as `Coverage gap`. All confirmed root source defects are repaired, representative light/dark/accessibility/empty/archived/limit/orphan/palette states were visually replayed, 604 iOS tests and 140 TypeScript tests pass, and both platform targets build. Reclassify it only after the unlocked five-part runtime pass is recorded.
