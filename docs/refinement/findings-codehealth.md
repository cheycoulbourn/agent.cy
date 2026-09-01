# L4 · Code health findings

Lane L4, code health: duplicated implementations, compiler warnings, oversized files, and the script/CI gates.
Produced 2026-09-01 on branch `refinement/pre-beta`. Dead symbols and assets are in
`docs/refinement/findings-deadcode.md`. Chey's words for this lane: *"Is there any dead code? Is anything making it
feel heavy?"* — the measured heaviness belongs to L2; what follows is structural weight.

Findings that are design components are batched **B1**; the rest **B4**.

## Method

- **Duplicate clusters.** For each cluster the brief names — close controls, headers, section rules, empty states,
  chips, date formatting, relative-date strings — I located every shared component, counted its adopters, then
  searched for hand-rolled reimplementations and compared their concrete values (size, colour, opacity, font,
  spacing) against the canonical one. The inventory's ten-variant close-control census and eight-variant header
  census were re-verified from source, not taken on trust; one inventory claim is corrected in L4-19.
- **Warnings.** Three clean builds under scratchpad derived data (`<scratch>/L4/DD`, `<scratch>/L4/DDMac` —
  deliberately separate from the path named in `_common.md` so no other lane collided): iOS simulator `build`,
  `build-for-testing`, and Mac Catalyst `build`. All three succeeded. `docs/refinement/evidence/baseline/` holds
  only the last 400 lines of a test log with no warnings captured, so this is a fresh census.
  Full output: `docs/refinement/evidence/L4/build-warnings.md`.
- **Scripts.** `scripts/verify.sh` and `scripts/check_inter_typography.sh` were executed on this Mac and
  `.github/workflows/ci.yml` read line by line. Reproduction:
  `docs/refinement/evidence/L4/script-gates.md`.

---

### L4-11 `scripts/check_inter_typography.sh` prints "passed" and exits 0 when `rg` is missing, and it is currently masking eight real typography violations

- Where: `scripts/check_inter_typography.sh:14-21`
- Evidence: `rg` is not installed on this Mac. The check still passes.
  ```
  $ export PATH=/opt/homebrew/bin:$PATH
  $ bash scripts/check_inter_typography.sh; echo "EXIT=$?"
  scripts/check_inter_typography.sh: line 14: rg: command not found
  Inter typography check passed.
  EXIT=0
  ```
  The cause is line 14 putting `rg` in an `if` condition, which suppresses `set -euo pipefail` for that command.
  `rg` exits 127 (not found), the condition is false, the failure branch is skipped, and the script announces
  success having grepped nothing:
  ```bash
  if rg -n 'agentMono|paperMono|…|\.font\(\.system|\.font\(\.caption|UIFont\.systemFont' "${SEARCH_PATHS[@]}" …; then
    echo "Non-Inter typography reference found." >&2
    exit 1
  fi
  ```
  Running the same pattern through `grep` shows eight live violations of the "Inter only, no SF" rule the script
  exists to enforce:
  ```
  ios/AgentCy/App/RootView.swift:439:                      .font(.agentBody.monospaced())
  ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:269:  .font(.caption.weight(.semibold))
  ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:274:  .font(.caption.monospacedDigit())
  ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:357:  .font(.caption)
  ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:473:  .font(.caption)
  ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:478:  .font(.caption)
  ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:645:  .font(.caption2.weight(.semibold))
  ios/AgentCy/Views/Shell/DesktopAppShellView.swift:340:      .font(.system(size: 15, weight: .medium))
  ```
  `DesktopAppShellView.swift:340` renders San Francisco, not Inter, in the desktop shell; the six
  `MCPDesktopReviewView` sites use system text styles instead of the `agent*` tokens; `RootView.swift:439` forces a
  monospaced variant of Inter that the check explicitly bans. All eight are in files the working tree has modified,
  so the gate was silently absent exactly while the code that needed it was being written.
- Severity: blocker
- Fix: two parts, both small.
  1. Make the script fail loudly when its tool is missing and stop depending on `rg`. Add a
     `command -v rg >/dev/null || { echo "ripgrep is required" >&2; exit 1; }` preflight, or better, switch the
     search to `grep -rnE … --include='*.swift' --include='*.yml'`, which is present on every Mac and every CI
     image and produced the eight hits above. A gate that cannot run must exit non-zero, never print "passed".
  2. Fix the eight sites: `DesktopAppShellView.swift:340` to a semantic `Font.agent…` token, the six
     `MCPDesktopReviewView` sites to `.agentMetadata` / `.agentSubtext` (keeping `.monospacedDigit()` where the
     numbers need alignment — the script does not ban digit spacing, only monospaced *families*), and
     `RootView.swift:439` to plain `.agentBody`.
  This is a shared change: it touches `scripts/check_inter_typography.sh`, `RootView.swift`,
  `MCPDesktopReviewView.swift`, and `DesktopAppShellView.swift`, and it should land together with L4-12 so the
  repaired gate actually runs in CI.
- Batch: B4 (the script), B1 (the eight typography sites)
- Status: open

### L4-12 `scripts/verify.sh` cannot run on this Mac, and CI never runs the typography gate or `pnpm build`

- Where: `scripts/verify.sh:11-16`, `.github/workflows/ci.yml`
- Evidence:
  ```
  $ command -v pnpm corepack
  pnpm not found
  corepack not found
  $ grep packageManager package.json
    "packageManager": "pnpm@11.7.0",
  ```
  `verify.sh:13` is `pnpm install --frozen-lockfile` under `set -euo pipefail`, so the run aborts there. Lines
  18-49 — `xcodegen generate`, `xcodebuild build`, `xcodebuild test` — are unreachable locally. Because line 11
  runs the typography check *before* the pnpm step, the only part of `verify.sh` that does execute on this Mac is
  the check from L4-11 that always passes. So `verify.sh` on this machine is a no-op that reports success for
  eleven lines and then dies.

  CI does not compensate. `.github/workflows/ci.yml` invokes neither `scripts/verify.sh` nor
  `scripts/check_inter_typography.sh` anywhere in its 52 lines. The `workspace` job runs
  `pnpm install` / `pnpm --filter @agent-cy/contracts build` / `pnpm typecheck` / `pnpm test`, omitting the
  workspace-wide `pnpm build` that `verify.sh:16` runs. The `apps` job runs `xcodebuild test` and the Catalyst
  build. Neither job fails on compiler warnings. A third fragility sits at `ci.yml:42`:
  ```bash
  DEVICE=$(xcrun simctl list devices available | sed -n 's/^[[:space:]]*\(iPhone [^(]*\) (.*$/\1/p' | head -1 | xargs)
  ```
  This takes whichever iPhone the runner image happens to list first and pins nothing. The project targets
  `IPHONEOS_DEPLOYMENT_TARGET: 26.0` (`ios/project.yml:9`), so an image whose first available iPhone runs an older
  OS fails the job for a reason unrelated to the change under test — the same class of silent-environment
  dependency as L4-11, just failing loudly instead of quietly.
- Severity: major
- Fix:
  1. Add a `corepack enable && corepack prepare pnpm@11.7.0 --activate` preflight to `verify.sh` (or a
     `command -v pnpm || { echo "run: corepack enable" >&2; exit 1; }` guard) so the script says what is missing
     instead of dying on a bare "command not found". Node 24 ships corepack, so `corepack enable` is the whole
     local setup.
  2. Add `- run: ./scripts/check_inter_typography.sh` as the first step of the CI `apps` job, so the repaired gate
     from L4-11 runs on every PR.
  3. Add `- run: pnpm build` to the `workspace` job to match `verify.sh:16`.
  4. Replace the `sed`-scraped simulator with a pinned one — `-destination 'platform=iOS Simulator,name=iPhone 17
     Pro'` matching the `IOS_DESTINATION` default in `verify.sh:6` — so local and CI agree on the device.
  Together these make `verify.sh` and `ci.yml` the same gate, which is the point of having both.
- Batch: B4
- Status: open

### L4-13 158 call sites set font sizes by hand through two byte-identical helpers declared inside a page file, bypassing the sixteen semantic font tokens

- Where: `ios/AgentCy/Views/Pillars/PillarsView.swift:2339-2346`, used across 16 files
- Evidence: the two helpers are the same function twice, with different names and no doc comment explaining the
  distinction, living in a non-private `extension Font` at the bottom of a 2,370-line page file:
  ```swift
  // ios/AgentCy/Views/Pillars/PillarsView.swift:2339
  extension Font {
      static func paperInter(size: CGFloat, weight: Font.Weight, relativeTo style: TextStyle) -> Font {
          .custom("InterVariable", size: size, relativeTo: style).weight(weight)
      }
      static func paperMetadata(size: CGFloat, weight: Font.Weight, relativeTo style: TextStyle) -> Font {
          .custom("InterVariable", size: size, relativeTo: style).weight(weight)
      }
  }
  ```
  Identical bodies. Counts:
  ```
  paperInter sites:     136
  paperMetadata sites:   22
  files using them:      16
  agent font token sites: 921   (.font(.agent…))
  ```
  So roughly one text style in seven is set by a raw point size rather than a token. The heaviest adopters are
  `OnboardingView.swift` (~60 sites), `PillarsView.swift` (~28), `QuickCaptureView.swift` (~18), plus
  `MCPBridgeSettingsView`, `TasksView`, `AppShellView`, `ResumablePostEditorView`, `AgendaPostIdeaPickerView`,
  `IdeaBankView`, `OnboardingView`, `SavedPostsLibraryView`, `ScheduledPostDetailView`, `IdeaPostDraftView`,
  `AskCyView`, `HomeDashboardView`, `BrandCabinetView`, `AgentPostCard`. The sizes drift as you would expect from
  hand-set values: `28/.bold`, `28/.semibold`, `28/.medium` and `32/.bold`, `32/.medium` all appear for what read
  as the same display-title role, and `.paperMetadata` is called at 9, 10, 11 and 13pt.

  This is the contract's "tokens only" non-negotiable failing at 158 sites, and it is a code-health defect too:
  a design-token API is declared inside a view file, so `PillarsView.swift` is a compile-time dependency of the
  typography used by fifteen other pages.
- Severity: major
- Fix: a shared change. Move both functions into `ios/AgentCy/Design/DesignTokens.swift` beside the `agent*`
  tokens, collapse them to one (`paperMetadata` has no behaviour of its own), then map each of the 158 call sites
  onto the nearest existing semantic token — `agentDisplayLead`, `agentDisplay`, `agentTitle`, `agentHeadline`,
  `agentBody`, `agentSubtext`, `agentMetadata` and the six `agentDesktop*` tokens already cover the range in use.
  Where no token fits, add one rather than keeping a raw size. Sites to touch, all 16 files:
  `Views/Onboarding/OnboardingView.swift`, `Views/Pillars/PillarsView.swift`, `Views/Capture/QuickCaptureView.swift`,
  `Views/Settings/MCPBridgeSettingsView.swift`, `Views/Tasks/TasksView.swift`, `Views/Shell/AppShellView.swift`,
  `Views/Brief/ResumablePostEditorView.swift`, `Views/Agenda/AgendaPostIdeaPickerView.swift`,
  `Views/Ideas/IdeaBankView.swift`, `Views/Ideas/SavedPostsLibraryView.swift`,
  `Views/Brief/ScheduledPostDetailView.swift`, `Views/Brief/IdeaPostDraftView.swift`, `Views/Cy/AskCyView.swift`,
  `Views/Home/HomeDashboardView.swift`, `Views/Brands/BrandCabinetView.swift`, `Views/Shared/AgentPostCard.swift`.
  Once the raw sizes are gone, `check_inter_typography.sh` (repaired per L4-11) can add
  `Font\.custom\(|paperInter|paperMetadata` to its banned pattern so this cannot come back. Add the rule to
  `design.md` in the same pass.
- Batch: B1
- Status: open

### L4-14 The close/back control exists as two shared glass components with five divergent values plus two hand-rolled copies, one of which is not glass at all

- Where: `ios/AgentCy/Design/DesignTokens.swift:286-322` and `:917-942`;
  `ios/AgentCy/Views/Capture/CreationHubView.swift:213-247`;
  `ios/AgentCy/Views/Feed/SocialGridView.swift:1038-1052`
- Evidence: the two shared components do the same job — a translucent circular icon button — and disagree on every
  value:

  | | `AgentToolbarIconLabel` (`:305`) | `AgentCircularGlassIconButton` (`:917`) |
  |---|---|---|
  | frame | 44 × 44 | 48 × 48 |
  | icon size | 17 | 16 |
  | stroke | `agentPureWhite.opacity(0.22)` | `agentPureWhite.opacity(0.16)` |
  | button style | `.plain` (no press feedback) | `AgentPressButtonStyle()` |
  | disabled opacity | 0.42 (via `AgentToolbarIconButton`) | 0.34 |

  Its own doc comment calls the first one canonical — *"Canonical 44-point phone header control"* — yet the second
  exists with none of those five values matching. Adoption: `AgentToolbarIconButton` 43 references,
  `AgentToolbarIconLabel` 15, `AgentCircularGlassIconButton` 7, `AgentDesktopDetailRail` 10,
  `AgentDesktopDetailBackButton` 2.

  Two hand-rolled copies then drift further. `CreationHubView.swift:217-247` rebuilds the 44pt geometry inline —
  same `.glassEffect(.clear.interactive(), in: .circle)`, same `0.22` stroke — rather than calling the component,
  because it needs a walkthrough highlight state:
  ```swift
  AgentIconView(.close, size: 17)
      .frame(width: 44, height: 44)
      … .glassEffect(.clear.interactive(), in: .circle)
      .overlay { Circle().stroke(Color.agentPureWhite.opacity(0.22), lineWidth: 0.5) }
      .shadow(color: Color.agentPureBlack.opacity(0.08), radius: 12, y: 4)   // <- shadow the component lacks
  ```
  And `SocialGridView.swift:1043-1051` is the one close control in the app that is not glass at all — a 40pt
  opaque disc:
  ```swift
  AgentIconView(.close, size: 16)
      .frame(width: 40, height: 40)
      .background(Color.agentSurface, in: .circle)
      .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
  ```
  A third drift lives at the call sites: `PlanView.swift:137` and `:143` pass `iconSize: 16` to
  `AgentToolbarIconLabel`, overriding its 17pt default, so the "canonical" control renders at two sizes.

  This answers Chey's question directly — no, the close control is not the same X on every page, and it is not the
  same circle either: 40pt, 44pt and 48pt all ship.
- Severity: major
- Fix: a shared change with one owner. Make `AgentToolbarIconLabel` the single glass icon control and give it the
  two knobs the variants actually needed: an optional `highlight` state (for the walkthrough pulse
  `CreationHubView` hand-rolled) and an optional `shadow`. Then (a) delete `AgentCircularGlassIconButton` and
  migrate its five surfaces — `VoiceSparkView.swift:397`, `VoiceSparkView.swift:1312`,
  `VoiceRecordingDetailPage.swift:305` and `:313`, `CreatorSessionView.swift:326`/`:346` — accepting the 44pt
  geometry and the 0.22 stroke; (b) replace the inline block in `CreationHubView.swift:217-247` with the component
  plus its new `highlight` argument; (c) replace `SocialGridView.swift:1043-1051` with the component so
  `day-agenda-add-live-post` stops being the one opaque close button; (d) drop the `iconSize: 16` overrides at
  `PlanView.swift:137` and `:143`. Give `AgentToolbarIconLabel` `AgentPressButtonStyle()` while consolidating, so
  every close control gets the same press feedback. Record the rule in `design.md`: one glass circle, 44pt, 17pt
  glyph, 0.22 stroke, and `AgentDesktopDetailRail` as its only desktop substitute. If `CreatorSessionView` is
  removed under L4-01, two of the five migrations disappear.
- Batch: B1
- Status: open

### L4-15 Five independent "Today / Tomorrow" implementations produce five different fallback formats, and one hardcodes `en_US`

- Where: `ios/AgentCy/Views/Tasks/TasksView.swift:320-366` (two of them),
  `ios/AgentCy/Views/Capture/VoiceSparkView.swift:1386-1391`,
  `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:1486-1490`,
  `ios/AgentCy/Views/Home/HomeDashboardView.swift:2620-2629`
- Evidence: the same three-line shape repeated with a different tail each time.

  | site | "today" | "tomorrow" | fallback format |
  |---|---|---|---|
  | `TasksView.title(for:)` :326 | ✓ | ✓ | `EEEE, MMM d` via `DateFormatter`, plus a `Past due · ` prefix |
  | `TasksView.rowDateText(for:)` :343 | ✓ | ✓ | `MMM d` via `DateFormatter` |
  | `VoiceSparkView.dateLabel(for:)` :1388 | ✓ | ✓ | `.dateTime.weekday(.wide).month(.abbreviated).day()` |
  | `DesktopAppShellView.utilityPostDate(_:)` :1487 | ✓ | ✓ | `.dateTime.weekday(.abbreviated).month(.abbreviated).day()` |
  | `HomeDashboardView.activityTime(_:)` :2621 | time only | — (`Yesterday` instead) | `.dateTime.month(.abbreviated).day()` |

  Two of them also use different day-boundary logic — `calendar.isDate(date, inSameDayAs: now)` plus a manual
  `date(byAdding: .day, value: 1)` in `TasksView`, versus `calendar.isDateInToday` / `isDateInTomorrow` elsewhere —
  which behave differently when `now` is not the current instant. And `TasksView` pins the locale:
  ```swift
  // TasksView.swift:360-366
  private static func formatter(calendar: Calendar, dateFormat: String) -> DateFormatter {
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.locale = Locale(identifier: "en_US")     // <- ignores the user's locale
      formatter.dateFormat = dateFormat
      return formatter
  }
  ```
  Every other site uses `.formatted(.dateTime…)`, which is locale-aware. So the Tasks page shows a different date
  order from the rest of the app for any non-US creator, and the same due date reads as `Thu, Mar 6` on the task
  detail and `Mar 6` on the row.
- Severity: major
- Fix: a shared change. Add one `AgentRelativeDate` helper next to the other presentation policies in
  `ios/AgentCy/Services/`, with the two shapes the app actually needs — `dayLabel(for:relativeTo:)` (Today /
  Tomorrow / Yesterday, else an abbreviated weekday + month + day) and `shortDayLabel(for:relativeTo:)` — both
  built on `.formatted(.dateTime…)` so they follow the user's locale, and both taking an injectable `now` for
  tests. Then replace all five sites and delete `TasksView`'s private `formatter`, `formattedDay` and
  `formattedShortDay` (`:352-366`). `TasksView`'s `Past due · ` prefix stays at the call site, since that is task
  semantics, not date formatting.
- Batch: B1 (visible copy) with the helper landing as shared code
- Status: open

### L4-16 Three bespoke empty states sit beside a shared `AgentEmptyState`, each with a different title font, body font, icon size and spacing

- Where: canonical `ios/AgentCy/Design/DesignTokens.swift:1527-1554`; divergent copies at
  `ios/AgentCy/Views/Home/HomeDashboardView.swift:2466-2480`,
  `ios/AgentCy/Views/Feed/SocialGridView.swift:587-605`,
  `ios/AgentCy/Views/Agenda/AgendaView.swift:805-830`
- Evidence: `AgentEmptyState(title:message:icon:)` is real and adopted at 13 sites — `RootView.swift:362/387/407`,
  `SettingsView.swift:275/286`, `TasksView.swift:32`, `PlanView.swift:458`, `PillarsView.swift:460`,
  `SavedPostsLibraryView.swift:251`, `IdeaPostDraftView.swift:370/387/395`,
  `InspirationCaptureViews.swift:192`. It specifies icon 22pt, `.agentHeadline` title, `.agentBody` message,
  `AgentSpacing.x3` outer / `x1` inner spacing, `.padding(.vertical, AgentSpacing.x8)`, centred, and
  `.accessibilityElement(children: .combine)`.

  Three pages ignore it and disagree with it and with each other:

  | | icon | title font | body font | spacing | a11y combine |
  |---|---|---|---|---|---|
  | `AgentEmptyState` (canonical) | 22 | `.agentHeadline` | `.agentBody` | x3 / x1 | yes |
  | `HomeDashboardView:2466` | `.bell` 22 | `.agentTitle` | `.agentSubtext` | x3 | no |
  | `SocialGridView:587` | `.instagramCamera` 26 in a 48pt disc | `.agentHeadline` | `.agentSubtext` | x4 / x2 | no |
  | `AgendaView:805` | none | `.agentTitle` | `.agentBody` | x5 / x2, left-aligned in `AgentInsetSurface` | no |

  So an empty Home reads at a different type size from an empty Tasks list, and none of the three is announced as
  one element by VoiceOver.
- Severity: major
- Fix: a shared change on one component. Extend `AgentEmptyState` with the two things the copies genuinely need —
  an optional trailing `actions` `@ViewBuilder` (both `SocialGridView` and `AgendaView` put buttons under the copy)
  and an optional `alignment` (`AgendaView`'s inset-surface variant is left-aligned by design) — then replace all
  three bespoke blocks with it. `HomeDashboardView:2466` needs no new capability at all and is a straight swap.
  That leaves one empty-state component at 16 sites, all keeping the accessibility grouping the copies dropped.
- Batch: B1
- Status: open

### L4-17 Four competing treatments for the same 1pt rule, one of which hardcodes an opacity instead of using the hairline token

- Where: `ios/AgentCy/Design/DesignTokens.swift:1449-1469` and `:1088-1096`;
  `ios/AgentCy/Views/Pillars/PillarsView.swift:2158-2162`; plus inline rules across the view layer
- Evidence: four implementations of "a one-point horizontal line", using three different colours:
  ```swift
  // DesignTokens.swift:1466 — inside SectionRuleHeader, 66 adopters
  Rectangle().fill(Color.agentBorder).frame(height: 1)

  // DesignTokens.swift:1088 — AgentDesktopMenuDivider, Catalyst only
  Rectangle().fill(Color.agentHairline).frame(height: 1)

  // PillarsView.swift:2158 — PaperHairline, private, 9 adopters inside PillarsView
  Rectangle().fill(Color.agentText.opacity(0.12)).frame(height: 1)
  ```
  plus 129 inline `Color.agentHairline` rule sites written out longhand at the point of use, and 56 bare system
  `Divider()` calls, whose colour comes from UIKit rather than from `DesignTokens`. `PaperHairline` is the worst of
  them: `Color.agentText.opacity(0.12)` is a hand-mixed colour where `Color.agentHairline` already exists as the
  token (`DesignTokens.swift:472`, `adaptive(light: hairlineLight, dark: hairlineDark)`), so the nine rules inside
  the Pillars page resolve to a different value from every other rule in the app in at least one appearance.
- Severity: minor
- Fix: a shared change. Add one `AgentRule` view to `DesignTokens.swift` (`Rectangle().fill(Color.agentHairline)
  .frame(height: 1)`), point `SectionRuleHeader`'s underline and `AgentDesktopMenuDivider` at it, delete
  `PaperHairline` and replace its nine uses in `PillarsView.swift` (`:584`, `:585`, `:597`, `:1088`, `:1500`,
  `:1736`, `:1761`, `:1762`, `:1922`), and sweep the 56 bare `Divider()` calls onto it so rule colour comes from
  one token everywhere. `SectionRuleHeader` currently draws `agentBorder` while everything else draws
  `agentHairline` — the design lane should pick which one is the rule colour and record it in `design.md`; this
  finding only asks that there be one.
- Batch: B1
- Status: open

### L4-18 Twelve private copies of the same trim-a-string-to-nil helper, under four different names

- Where: as listed
- Evidence:
  ```
  ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift:1426:  private func nonempty(_ value: String?) -> String?
  ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift:1805:  private func nonempty(_ value: String?) -> String?
  ios/AgentCy/Views/Feed/SocialGridView.swift:323:              static func nonempty(_ value: String) -> String?
  ios/AgentCy/Views/Cy/AskCyView.swift:2000:                    private func nonempty(_ value: String?) -> String?
  ios/AgentCy/Services/CreativeService.swift:673:               private static func nonempty(_ value: String) -> String?
  ios/AgentCy/Services/CreativeService.swift:1186:              private func nonempty(_ value: String) -> String?
  ios/AgentCy/Services/InspirationContentAnalysisService.swift:137:  private func firstNonempty(_ values: String?...) -> String?
  ios/AgentCy/Services/InspirationContentAnalysisService.swift:197:  private func firstNonempty(_ values: String?...) -> String?
  ios/AgentCyInspirationShare/ShareViewController.swift:503:         private func firstNonempty(_ values: String?...) -> String?
  ios/AgentCy/Views/Home/HomeDashboardView.swift:2633:            var nilIfBlank: String?
  ios/AgentCy/Services/InspirationContentAnalysisService.swift:464:  var nilIfEmpty: String?
  ios/AgentCy/Views/Capture/CreatorSessionView.swift:1770:        var nonEmpty: String? { isEmpty ? nil : self }
  ```
  Two of them are declared twice in the same file (`MCPBridgeSettingsView`, `CreativeService`,
  `InspirationContentAnalysisService`). They are not all equivalent, which is the actual risk:
  `nilIfEmpty` / `nonEmpty` test `isEmpty` without trimming, while `nonempty` / `nilIfBlank` trim whitespace first.
  So `"   "` is a value in some code paths and nil in others.
- Severity: minor
- Fix: one `extension String { var trimmedOrNil: String? }` and one
  `func firstTrimmedOrNil(_ values: String?...) -> String?` in `ios/AgentCyShared/` (shared so
  `AgentCyInspirationShare`, which has its own copy at `ShareViewController.swift:503`, can use it — that target
  compiles only three `AgentCyShared` files today, so add the new one to `ios/project.yml:243-246`). Delete all
  twelve copies. Where a call site genuinely wanted untrimmed `isEmpty` semantics, make that explicit rather than
  relying on which helper happened to be in scope.
- Batch: B4
- Status: open

### L4-19 One tab root hand-builds the page rail that six other surfaces get from `AgentPageRail` — and the inventory's header census is wrong about this

- Where: canonical `ios/AgentCy/Views/Shared/CreatorAvatar.swift:114`; divergent
  `ios/AgentCy/Views/Plan/PlanView.swift:127-158`
- Evidence: `docs/refinement/01-page-inventory.md` says `AgentPageRail` is *"used only by home
  (HomeDashboardView.swift:800). One-off pattern not reused anywhere else"* and marks the tasks, pillars and
  idea-bank headers "uncertain". Checked directly, that is not the case — it has six adopters:
  ```
  $ grep -rn "AgentPageRail(" ios/AgentCy --include='*.swift'
  ios/AgentCy/Views/Home/HomeDashboardView.swift:797
  ios/AgentCy/Views/Feed/SocialGridView.swift:484
  ios/AgentCy/Views/Ideas/SavedPostsLibraryView.swift:234
  ios/AgentCy/Views/Tasks/TasksView.swift:686
  ios/AgentCy/Views/Pillars/PillarsView.swift:470
  ios/AgentCy/Views/Ideas/IdeaBankView.swift:370
  ```
  Four of the five tab roots use it. The exception is `plan-week`, which hand-builds the same three-part rail —
  breadcrumb `MetaLabel`, trailing icon buttons, `ProfileSettingsButton` — in a bespoke `HStack`:
  ```swift
  // PlanView.swift:128-157
  HStack(alignment: .center, spacing: AgentSpacing.x1) {
      MetaLabel("Weekly agenda").frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: AgentSpacing.x1) {
          Button { isSearchingPosts = true } label: { AgentToolbarIconLabel(icon: .search, iconSize: 16) }
          if showsFeedShortcut { NavigationLink(value: …) { AgentToolbarIconLabel(icon: .instagramCamera, iconSize: 16) } }
      }
      .frame(height: 44)
      ProfileSettingsButton(identity: activeIdentity, action: { appModel.presentedSheet = .settings })
  }
  ```
  Structurally identical to `AgentPageRail`, hand-spaced, and it is also where the `iconSize: 16` override from
  L4-14 lives. So the header story is much better than the inventory suggests — two shared components
  (`AgentPageRail` for tab roots at six sites, `EditorialHeader` at 19, plus `SettingsPageShell` wrapping
  `EditorialHeader` for all ~18 pushed settings pages at 21 sites) and one hold-out.
- Severity: minor
- Fix: give `AgentPageRail`'s existing `Actions` generic slot the two buttons `plan-week` needs and adopt it in
  `PlanView.swift:127-158`, deleting the bespoke `HStack`. One file changes and the tab-root header pattern becomes
  universal. Correct the `AgentPageRail` entry and the tasks/pillars/idea-bank "Uncertain" entries in
  `docs/refinement/01-page-inventory.md` so later lanes are not planning against the wrong census.
- Batch: B1
- Status: open

### L4-20 Fourteen compiler warnings across the three schemes, from three distinct causes

- Where: `ios/AgentCy/Services/InspirationContentAnalysisService.swift:362`,
  `ios/AgentCyInspirationShare/InspirationShareMediaAnalyzer.swift:147`,
  `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:714`, `ios/AgentCyTests/ServiceTests.swift:961`
- Evidence: three clean builds, full output in `docs/refinement/evidence/L4/build-warnings.md`. All three succeeded.

  | kind | count | sites |
  |---|---|---|
  | `'copyCGImage(at:actualTime:)' was deprecated in iOS 18.0 / Mac Catalyst 18.0` | 11 iOS + 10 Catalyst, **2 distinct sites** | `InspirationContentAnalysisService.swift:362:43`, `InspirationShareMediaAnalyzer.swift:147:43` |
  | `result of call to 'withTransaction' is unused` | 1, **Catalyst only** | `DesktopAppShellView.swift:714:9` |
  | `'init(frame:)' was deprecated in iOS 26.0: Use init(windowScene:)` | 1, test target | `ServiceTests.swift:961:22` |
  | `Metadata extraction skipped. No AppIntents.framework dependency found.` | 1 | tool notice against `AgentCyInspirationShare`, which declares no intents — benign, see `findings-deadcode.md` |

  The repeat counts are one site emitting once per compilation unit, not many sites. Two observations worth more
  than the counts:
  - `copyCGImage(at:actualTime:)` is a **synchronous, blocking** frame grab, deprecated in favour of
    `generateCGImageAsynchronously(for:completionHandler:)`. Both sites are video-thumbnail extraction on the
    inspiration-capture path — the app target's copy and a near-identical copy in the share extension. That is a
    duplicate implementation as well as a deprecation, and a plausible hang source for L2 to measure: a blocking
    frame decode on whatever thread calls it.
  - `result of call to 'withTransaction' is unused` at `DesktopAppShellView.swift:714` is inside
    `completeUtilityTask`, whose whole purpose is to suppress the completion animation:
    ```swift
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { appModel.toggleTask(task, context: modelContext) }
    ```
    The warning is cosmetic — the transaction does apply — but it fires only on Catalyst, which means the Catalyst
    scheme is not being built warning-clean as often as the iOS one.
- Severity: minor
- Fix: (a) migrate both `copyCGImage` sites to `generateCGImageAsynchronously(for:completionHandler:)` and, while
  there, extract the shared thumbnail logic into `ios/AgentCyShared/` so the app and the share extension stop
  carrying two copies — hand the before/after timing to L2, since this is on a capture path Chey uses.
  (b) At `DesktopAppShellView.swift:714`, discard the result explicitly (`_ = withTransaction(…)`) or mark
  `AppModel.toggleTask` `@discardableResult`. (c) Update `ServiceTests.swift:961` to `init(windowScene:)`.
  (d) Once at zero, add `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for the Debug configuration in `ios/project.yml`, or
  at minimum have CI fail on new warnings — with L4-12 fixed, CI is the place that would catch a regression.
- Batch: B4
- Status: open

### L4-21 Fifteen files exceed 2,000 lines, three of them over 4,000

- Where: as listed
- Evidence: `find ios -name '*.swift' -not -path '*/build*' | xargs wc -l | sort -rn`. Repo total is 104,755 lines
  of Swift, so these fifteen files hold roughly 42% of it.

  | lines | file |
  |---|---|
  | 5,412 | `ios/AgentCy/Views/Brief/ResumablePostEditorView.swift` |
  | 5,273 | `ios/AgentCyTests/DomainTests.swift` |
  | 4,990 | `ios/AgentCy/ViewModels/AppModel.swift` |
  | 4,104 | `ios/AgentCy/Views/Agenda/AgendaView.swift` |
  | 2,826 | `ios/AgentCy/Views/Cy/AskCyView.swift` |
  | 2,637 | `ios/AgentCy/Views/Home/HomeDashboardView.swift` |
  | 2,623 | `ios/AgentCy/Views/Tasks/TasksView.swift` |
  | 2,452 | `ios/AgentCy/Views/Settings/SettingsSubpages.swift` |
  | 2,374 | `ios/AgentCy/Views/Capture/QuickCaptureView.swift` |
  | 2,370 | `ios/AgentCy/Views/Pillars/PillarsView.swift` |
  | 2,248 | `ios/AgentCy/Services/MCPBridgeService.swift` |
  | 2,152 | `ios/AgentCy/Design/DesignTokens.swift` |
  | 2,113 | `ios/AgentCyTests/ServiceTests.swift` |
  | 2,112 | `ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift` |
  | 2,064 | `ios/AgentCy/Views/Onboarding/OnboardingView.swift` |

  A split proposal for each, by responsibility rather than by line number:

  **`ResumablePostEditorView.swift` (5,412)** — one file holds the post editor plus at least seven of its own
  sub-sheets (series detail, series-details editor, add-future-episodes, task composer, task due date,
  actual-posted date, pillar calendar). Split into `PostEditorView.swift` (the root editor, its state machine and
  the save/resume path), `PostEditorSeriesSheets.swift` (series detail, series details editor, future episodes,
  episode-slot selection), `PostEditorSchedulingSheets.swift` (dates sheet, task due date, actual posted date,
  `PillarCalendarDatePicker`), and `PostEditorTaskComposer.swift`. Boundary: the root owns the draft; each sheet
  file owns one sheet and reaches the draft through a binding.

  **`AppModel.swift` (4,990)** — a single `@Observable` doing navigation state, quick-capture state, task
  mutations, brief/post mutations, pillar mutations, week planning, inspiration import and notice/toast state.
  Split by domain into extensions in their own files — `AppModel+Navigation.swift`, `AppModel+Tasks.swift`,
  `AppModel+Posts.swift`, `AppModel+Pillars.swift`, `AppModel+Planning.swift`, `AppModel+Inspiration.swift` —
  keeping the stored properties in `AppModel.swift`. This is mechanical, needs no API change, and makes the nine
  dead methods in `findings-deadcode.md` L4-03 visible for what they are.

  **`AgendaView.swift` (4,104)** — the week agenda, the day agenda, the list mode, the episode-slot flows and the
  pillar-overwrite confirmations. Split into `AgendaWeekView.swift`, `AgendaDayView.swift`,
  `AgendaListView.swift`, and `AgendaEpisodeSlots.swift`, with the projections (`AgendaOutputState`,
  `AgendaPostSearchProjection`) moving to `ios/AgentCy/Services/` where the other pure policies live — they are
  testable logic sitting inside a view file.

  **`DomainTests.swift` (5,273) and `ServiceTests.swift` (2,113)** — grab-bag test files. Split per subject
  (`PillarDomainTests`, `PostDomainTests`, `TaskDomainTests`, `SchedulingServiceTests`, …) to match the naming the
  rest of the suite already uses (`WeeklyFocusTests`, `InspirationLifecycleTests`, `PageMain02Tests`).

  **`AskCyView.swift` (2,826)** — the chat transcript, the composer, the proposed-action review sheets and the
  conversation-history browser. Split into `AskCyTranscriptView.swift`, `AskCyComposer.swift`,
  `AskCyReviewSheets.swift`, `AskCyHistoryView.swift`.

  **`HomeDashboardView.swift` (2,637)** — dashboard shell plus a dozen card types. Split into
  `HomeDashboardView.swift` (shell, rail, layout) and `HomeDashboardCards.swift`, or one file per card group.

  **`TasksView.swift` (2,623)** — list root, filter sheet, task detail, due-date editor, post-task creation flow,
  plus `TaskDueDatePresentation` and `TaskCollectionPolicy`. Split into `TasksListView.swift`,
  `TaskDetailView.swift`, `TaskComposerViews.swift`, with the policies moving to `ios/AgentCy/Services/`.

  **`SettingsSubpages.swift` (2,452)** — roughly eighteen pushed settings pages in one file. Split by section:
  `SettingsAccountPages.swift`, `SettingsContentPages.swift`, `SettingsIntegrationPages.swift`,
  `SettingsPrivacyPages.swift`, keeping `SettingsPageShell` in a shared `SettingsChrome.swift`.

  **`QuickCaptureView.swift` (2,374)** — idea capture, task capture, post capture and the subtask composer in one
  view with a mode enum. Split one file per mode plus `QuickCaptureShell.swift` for the chrome they share.

  **`PillarsView.swift` (2,370)** — list root, guide, detail, new-pillar, colour chooser, weekday chooser, plus the
  `Font.paperInter` extension from L4-13 and `PaperHairline` from L4-17. Split into `PillarsListView.swift`,
  `PillarDetailView.swift`, `PillarGuideView.swift`, `PillarEditorViews.swift`; the two design helpers leave for
  `DesignTokens.swift` as part of B1.

  **`MCPBridgeService.swift` (2,248)** — transport, request/response models, structured-field migration and
  polling. Split into `MCPBridgeService.swift` (transport and polling), `MCPBridgeModels.swift`, and
  `MCPBridgeMigration.swift`.

  **`DesignTokens.swift` (2,152)** — the only one where size is defensible, since it is the single source of truth.
  Still worth splitting by kind for navigability: `DesignTokens+Color.swift`, `+Typography.swift`, `+Spacing.swift`,
  `+Controls.swift` (the button styles and icon buttons), `+Chrome.swift` (`EditorialHeader`,
  `AgentDesktopDetailRail`, `SectionRuleHeader`, `AgentEmptyState`). The B1 consolidations in L4-13, L4-14, L4-16
  and L4-17 all land in `+Typography` and `+Controls`, so doing this split first makes those diffs readable.

  **`MCPBridgeSettingsView.swift` (2,112)** — settings page plus the review sheets. Split into
  `MCPBridgeSettingsView.swift` and `MCPBridgeReviewSheets.swift`.

  **`OnboardingView.swift` (2,064)** — the paged first-run flow. Split one file per step group —
  `OnboardingIdentitySteps.swift`, `OnboardingPillarSteps.swift`, `OnboardingPreferenceSteps.swift` — with
  `OnboardingView.swift` keeping the pager, the draft and the completion path. This file is also the single
  heaviest user of the raw font sizes in L4-13 (~60 sites), so the two changes should be sequenced: split first,
  then tokenize.
- Severity: minor
- Fix: as proposed per file above. None of these is required for beta and none should be attempted in the same
  commit as a behaviour change — the value is that B1's shared-component work in `DesignTokens.swift`,
  `PillarsView.swift` and `PlanView.swift` becomes reviewable. Sequence: split `DesignTokens.swift` first, then
  land B1, then the view splits. `AppModel.swift`'s extension split is the cheapest and highest-value single move.
- Batch: B4
- Status: open

### L4-22 `ExportService` allocates a fresh `ISO8601DateFormatter` 41 times per export

- Where: `ios/AgentCy/Services/ExportService.swift`
- Evidence:
  ```
  $ grep -c "ISO8601DateFormatter()" ios/AgentCy/Services/ExportService.swift
  41
  ```
  Each one is constructed inline inside a `map` closure over a model collection, for example:
  ```swift
  // ExportService.swift:216-226
  "skippedAt":  task.skippedAt.map  { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
  "targetDate": task.targetDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
  "dailyFocusDate": task.dailyFocusDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
  "completedAt": task.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
  ```
  So the count is 41 *sites*, but the allocations are per row: a workspace with a few hundred tasks, posts and
  outputs constructs tens of thousands of formatters in one export. `ISO8601DateFormatter` is one of the more
  expensive Foundation objects to initialize. Six more inline allocations exist elsewhere —
  `AgentCyApplicationDelegate.swift:55`, `PersistenceModels.swift:612` and `:625`,
  `MCPBridgeService.swift:2187`/`:2190`, `NotificationPlanning.swift:699`, `ReminderService.swift:288`/`:629`.
- Severity: minor
- Fix: add one `static let iso8601 = ISO8601DateFormatter()` (formatters are thread-safe for formatting once
  configured) in `ios/AgentCyShared/` and use it at all 49 sites. Mechanical, no behaviour change. Worth handing to
  L2 as a candidate before/after measurement if export ever appears in a hang trace — it is the clearest
  allocation-in-a-loop in the codebase.
- Batch: B4
- Status: open

### L4-23 26 GB of build output lives inside the iCloud-synced repo folder

- Where: `ios/build/` (26 GB), `ios/build-device/` (285 MB)
- Evidence:
  ```
  $ du -sh ios/build ios/build-device
   26G    ios/build
  285M    ios/build-device
  $ git ls-files ios/build ios/build-device | wc -l
  0
  ```
  Both are untracked and correctly ignored (`.gitignore:18-19`), so this is not a repo-weight problem. It is a
  tooling problem: the repo is under `~/Documents`, which is iCloud-synced, and `docs/refinement/briefs/_common.md`
  already warns that derived data inside the repo "is iCloud-synced and breaks signing" — the reason every lane is
  told to build under scratchpad. Yet 26 GB of derived data is sitting there being synced, which both burns iCloud
  storage and is the exact configuration the brief warns against.
- Severity: minor
- Fix: delete both directories (`rm -rf ios/build ios/build-device`) and mark them excluded from iCloud by
  appending `.nosync` or setting the directory's `com.apple.fileprovider.ignore#P` xattr, so a future in-repo
  build does not resync. Better: point the default Xcode derived-data location for this project at
  `~/Library/Developer/Xcode/DerivedData` (the Xcode default) rather than a repo-relative path, and add a note to
  `README.md` that in-repo builds break signing. Confirm with Chey before deleting, since a device build lives in
  `ios/build-device` and she may have it installed on her phone. This is housekeeping, not a shipping defect.
- Batch: B4
- Status: open
