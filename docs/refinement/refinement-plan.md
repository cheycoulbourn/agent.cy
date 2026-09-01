# Agent.cy pre-beta refinement plan

Written by job M (merger) from the six discovery lanes and `skeptic-report.md`. This is the
implementation plan for the subagent-driven-development loop. It is not approved until Chey
signs off at gate H1; the decisions she owns are in `decision-packet.md`.

## Objective

Agent.cy feels polished, light, consistent, and coherent, so the first beta testers have a
pleasant experience. Every task below exists because a lane produced evidence in this pass that
a beta tester or App Review would meet the defect.

## Global constraints (copied from `00-contract.md`, non-negotiable)

- Brick red stays and appears only as marks, tints, glyphs, and text. No solid accent fills.
- Buttons are quiet ink tints with 10 pt corners. Never solid fills, never pills.
- Every change lands on phone and desktop (Catalyst) in the same pass.
- Reduce Motion honored on every animation.
- No SF Symbols in shipped UI; icons go through `AgentIcon`.
- `design.md` is canonical; where code and document disagree, code wins and the document is fixed.

And the contract's working rule: **rectify, don't note.** A finding that can be fixed inside its
batch is fixed there. A document-only outcome is not done.

## Finding format and status

Findings keep the ids the lanes gave them (`L1-`, `L2M-`, `L2H-`, `L3-`, `L4-`, `L5-`, `APPLE-`)
plus the skeptic's ten gaps (`G-1` … `G-10`). A task names every finding it closes. When a task
lands, the implementer sets `Status: closed by Task N` on each finding in its lane file.

## Census as merged

The skeptic's per-lane verdicts — the ones carrying re-derived evidence — sum to **125 findings
standing, 6 weakened, 1 reclassified (APPLE-18), 1 rejected (L2H-08)**, against a headline of
"124 stand, 8 weakened". I have planned from the per-lane verdicts. Four of the standing findings
are duplicates the skeptic collapsed (L1-06→L4-13, L1-14→L4-19, L3-11→L4-01, L3-12→L4-02), so
**121 distinct defects** plus the skeptic's ten gaps enter the batches below.

## Batches

| Batch | Subject | Tasks | What it makes true |
|---|---|---|---|
| B1 | Design consistency | 1–27 | One close control, one header pattern, one button family, tokens only, on both form factors and both appearances. |
| B2 | Motion and heaviness | 28–42 | One motion vocabulary, Reduce Motion honored everywhere, and the app idles when the creator is not touching it. |
| B3 | Cohesion and flows | 43–59 | Every core flow finishes, tells the creator what happened, and survives being backgrounded. |
| B4 | Dead code | 60–75 | No unreferenced code or assets; the gates that would have caught the drift actually run. |
| B5 | Security | 76–97 | Blockers fixed, published privacy statements true, the server's abuse controls real. |
| B6 | Apple readiness | 98–113 | The archive uploads, the review-blocking items are closed or owned, and the first screen behaves. |

Ordering rule inside a batch: shared components and gates land before the sites that adopt them.

---

## B1 · Design consistency

### Task 1: Repair the typography gate and stand up the design-review lint

- **Closes:** L4-11 (script half, blocker), G-2 (major).
- **Files and sites:** `scripts/check_inter_typography.sh:6-21` — replace the `rg` call in the
  `if` condition with `grep -rnE … --include='*.swift' --include='*.yml'`, add a
  `command -v` preflight that exits non-zero when a required tool is missing, and add
  `"$ROOT/ios/AgentCyInspirationShare"` to `SEARCH_PATHS` (currently absent, which is why four raw
  `.font(.system(size:))` calls in `ShareViewController.swift:841/864/889/905` pass today). New
  `scripts/check_design_review.sh` grepping for the five bans the later batches need checked:
  `Image(systemName:` / `systemImage:`, animation curves outside `AgentMotion`,
  `Font.custom(|paperInter|paperMetadata|\.font\(\.system`, `cornerRadius: (3|5|6|9|13|14|18|22)`,
  and `background(Color.cyAccent|actionAccent` with `in: .capsule` or `in: .circle`.
- **Shared thing introduced:** the lint script, wired into `scripts/verify.sh` before the pnpm step.
- **Tests:** a shell fixture per rule — a file that must fail and a file that must pass — run from
  the script's own `--self-test` flag. Assert exit 1 when the tool is missing.
- **Acceptance:** `bash scripts/check_inter_typography.sh; echo $?` prints the eight current
  violations and exits 1. `bash scripts/check_design_review.sh` exits 1 today and its output is
  attached to the review. No screenshots — not a visible change.

### Task 2: Fix the eight off-token font sites the repaired gate exposes

- **Closes:** L4-11 (sites half, blocker), APPLE-20 (minor — same site).
- **Files and sites:** `ios/AgentCy/App/RootView.swift:439` (`.agentBody.monospaced()` → `.agentBody`);
  `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:269, 274, 357, 473, 478, 645`
  (`.caption*` → `.agentMetadata` / `.agentSubtext`, keeping `.monospacedDigit()` where the numbers
  align); `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:340`
  (`.font(.system(size: 15, weight: .medium))` → `.agentInter(size: 15, weight: .medium, relativeTo: .subheadline)`).
- **Shared thing reused:** the semantic `agent*` font tokens in `DesignTokens.swift:599-680`.
- **Tests:** Task 1's gate now passes; add that assertion to `scripts/verify.sh`'s output.
- **Acceptance:** gate exits 0. Catalyst screenshots of the desktop shell appearance control and the
  MCP review pane, light and dark; the text must read in Inter, and the appearance glyph must grow
  at an accessibility text size.

### Task 3: Buttons render at 10 pt corners

- **Closes:** L1-08 (major).
- **Files and sites:** `ios/AgentCy/Design/DesignTokens.swift:769` —
  `static let radius = AgentRadius.control` becomes `AgentRadius.button`. One line; ~95 button call
  sites correct at once, since all five shared styles read `AgentActionButtonTheme.radius`.
- **Shared thing reused:** `AgentRadius.button = 10` (`DesignTokens.swift:69`), which currently has
  zero users in the button family.
- **Tests:** a unit assertion that `AgentActionButtonTheme.radius == AgentRadius.button`.
- **Acceptance:** phone and desktop screenshots, light and dark, of one screen per button role
  (Access page primary, a quiet secondary, a quiet destructive). Corners visibly 10 pt, and the
  contract's number and the code's number now agree.

### Task 4: One glass icon control

- **Closes:** L1-01 (major), L1-02 (major), L1-03 (major), L4-14 (major), L3-21 first half (minor).
- **Files and sites:** make `AgentToolbarIconLabel` / `AgentToolbarIconButton`
  (`ios/AgentCy/Design/DesignTokens.swift:286-322`) the single glass circle — 44 pt, 17 pt glyph,
  `pureWhite@0.22` stroke — and give it the two knobs the variants needed: an optional `highlight`
  state and an optional shadow. Then: delete `AgentCircularGlassIconButton`
  (`DesignTokens.swift:917-942`) and migrate its 6 call sites — `VoiceSparkView.swift:397, 405, 1312`,
  `CreatorSessionView.swift:346`, `VoiceRecordingDetailPage.swift:305, 313`. Replace the hand-rolled
  copies at `CreationHubView.swift:216-247` (drop the stray
  `shadow(agentPureBlack@0.08, radius: 12, y: 4)` at `:244`), `SocialGridView.swift:452-470`,
  `ResumablePostEditorView.swift:576-586`, `AskCyView.swift:1278-1292` (drop the same stray shadow at
  `:1290`), and `CreationHubView.swift:489-497` (the 40 pt `agentBorder` copy). Replace the two
  non-glass copies: `SocialGridView.swift:1041-1051` (opaque 40 pt, under the phone floor) and
  `DevelopBriefView.swift:128-135` (opaque 44 pt, no stroke). Move `AgentPressButtonStyle` onto the
  canonical control at `DesignTokens.swift:296`, which currently uses bare `.buttonStyle(.plain)`.
- **Shared thing introduced:** one glass icon control; `AgentDesktopDetailBackButton`
  (`DesignTokens.swift:390-418`) stays as its only desktop substitute.
- **Tests:** a snapshot or geometry unit test asserting the control's frame is 44×44 and its glyph
  17; a grep test in the design lint asserting `glassEffect(.clear.interactive(), in: .circle)`
  appears only inside `DesignTokens.swift`.
- **Acceptance:** re-run `docs/refinement/evidence/consistency/measure-close-controls.py` against
  fresh captures of `weekly-focus-setup`, `voice-spark`, `day-agenda-add-live-post` and
  `post-editor-spark-development` on phone light and dark plus desktop light and dark. Every measured
  diameter must be 44 pt ±0.7 and every interior fill identical. Attach the before (44.00 / 48.00 /
  40) and after numbers.

### Task 5: One Save control

- **Closes:** L1-04 (blocker), L1-18 (the 24 pt checkmark half, major).
- **Files and sites:** introduce `AgentToolbarSaveButton` on Task 4's geometry (glass circle,
  `AgentIcon.check`, ink glyph) in `DesignTokens.swift`, and use it at
  `AgendaView.swift:2980-2990`, `WeeklyFocusView.swift:99-109` and `:955-965`,
  `TasksView.swift:1577-1587`, `ResumablePostEditorView.swift:5311-5321`,
  `AskCyView.swift:2695-2705` (the `.tint(Color.agentSurface)` variant), and
  `InspirationCaptureViews.swift:208-212` (the bare 24 pt checkmark). All six of the first group are
  `.buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(Color.agentPureWhite)` — the
  contract's "never solid fills" broken byte-for-byte six times.
- **Shared thing introduced:** `AgentToolbarSaveButton`; it also collapses the check glyph's six
  sizes (11/12/13/14/15/16 across 33 sites) to one.
- **Tests:** design lint rule banning `.buttonStyle(.borderedProminent)` anywhere in `ios/AgentCy`;
  it currently returns exactly six sites.
- **Acceptance:** phone and desktop, light and dark, of `day-agenda`, `weekly-focus-setup` and
  `inspiration-review`. In dark mode the solid white puck was the brightest object on the screen —
  the after shot must show the same glass treatment as the Close beside it, and the
  `inspiration-review` Save must measure 44 pt.

### Task 6: One quiet accent action, and no accent fill or glow anywhere

- **Closes:** L1-05 (blocker), G-5 (blocker, folded into L1-05).
- **Files and sites:** introduce one "quiet accent action" style — `cy @ 12%` fill, 0.75 pt
  `cy @ 40%` border, brick semibold label, 10 pt corners — in `DesignTokens.swift`, and adopt it at
  the **nine** solid accent fills (not eight): `QuickCaptureView.swift:135, 1037, 1452`,
  `AskCyView.swift:1471`, `CreationHubView.swift:410`, `AppShellView.swift:686`
  (`WalkthroughPrimaryButtonStyle`), `SettingsSubpages.swift:2141`, plus the two the census missed —
  `CreationHubView.swift:222-233` (the walkthrough Quick Add close, `Circle().fill(Color.cyAccent)`)
  and `DevelopBriefView.swift:348` (`.background(canSend ? Color.cyAccent : …, in: .circle)`).
  Delete the **eleven** accent glows: `QuickCaptureView.swift:78, 136, 1038`,
  `SettingsSubpages.swift:2115`, `AskCyView.swift:1444, 1472, 1670`,
  `InspirationCaptureViews.swift:486`, `AppShellView.swift:687`, `DevelopBriefView.swift:353`, and
  `CreationHubView.swift:227`. Leave the Home activity count badge
  (`HomeDashboardView.swift:2105`) — it is a mark, not a button.
- **Shared thing introduced:** the quiet accent action style; design.md's
  "No solid accent fills, anywhere (decided 2026-08-14)" and "No glow (rejected 2026-08-14)" become
  enforceable by Task 1's lint.
- **Tests:** lint rule: zero matches for `fill(Color.cyAccent)` / `background(Color.cyAccent` and
  zero for `shadow(color: Color.cyAccent`.
- **Acceptance:** phone light and dark of `cy-pro-upsell`, `walkthrough-overlay`, `quick-capture`,
  `ask-cy-sheet`, `settings-access`, `inspiration-review` and `develop-brief`; desktop light and dark
  of the same where they exist. Brick red must appear only as glyph, text, border and 12% tint.

### Task 7: Retire the onboarding and walkthrough capsule button styles

- **Closes:** L1-10 (blocker).
- **Files and sites:** delete `PaperOnboardingPrimaryButtonStyle` /
  `PaperOnboardingOutlineButtonStyle` (`OnboardingView.swift:1959-1985`, `:2018`) and
  `WalkthroughPrimaryButtonStyle` (`AppShellView.swift:676-701`); use `AgentPrimaryButtonStyle` /
  `AgentSecondaryButtonStyle` at all six sites. Convert `OnboardingView.swift:1746`
  (platform-format chips) and `TasksView.swift:2194` to 8 pt-radius chips — `ink@9%` selected, border
  unselected — per design.md's weekly-focus chip spec. `QuickCaptureView.swift:687` moves to the
  shared family too.
- **Shared thing reused:** `AgentActionButtonTheme` and the five shared styles, now at 10 pt (Task 3).
- **Tests:** lint rule banning `in: .capsule` on any `Button` label background inside `Views/`.
- **Acceptance:** phone light and dark of `onboarding-flow` (all steps) and `walkthrough-overlay`.
  These are the first two screens a beta tester sees; the after shots must be visually continuous
  with `home` in the same appearance.

### Task 8: Move the raw typography helpers into the token file and map the 158 call sites

- **Closes:** L4-13 (major); L1-06 is the same defect and is cross-referenced, not double-counted.
- **Files and sites:** delete `Font.paperInter` / `Font.paperMetadata`
  (`PillarsView.swift:2339-2346` — byte-identical bodies) and map all 158 calls onto the seven levels:
  32→`.agentDisplay`, 28→`.agentBriefTitle`, 22→`.agentTitle`, 17–20→`.agentHeadline`,
  14–16→`.agentBody`, 12–13→`.agentSubtext`, 9–11→`.agentMetadata`, taking the weight from the level.
  Sixteen files: `OnboardingView.swift` (~60), `PillarsView.swift` (~28), `QuickCaptureView.swift`
  (~18), `MCPBridgeSettingsView.swift`, `TasksView.swift`, `AppShellView.swift`,
  `ResumablePostEditorView.swift`, `AgendaPostIdeaPickerView.swift`, `IdeaBankView.swift`,
  `SavedPostsLibraryView.swift`, `ScheduledPostDetailView.swift`, `IdeaPostDraftView.swift`,
  `AskCyView.swift`, `HomeDashboardView.swift`, `BrandCabinetView.swift`, `AgentPostCard.swift`.
  The 36 pt onboarding masthead (`OnboardingView.swift:317`) waits on DEC-04 — leave it at 36 with a
  `// DEC-04` comment and close it in Task 26's follow-up if she adds an eighth level.
- **Shared thing removed:** a design-token API declared inside a view file, which made
  `PillarsView.swift` a compile-time dependency of fifteen other pages.
- **Tests:** extend Task 1's gate with `Font\.custom\(|paperInter|paperMetadata` so this cannot
  come back. It must exit 1 before the change and 0 after.
- **Acceptance:** phone light and dark of `onboarding-flow`, `pillars`, `quick-capture`; desktop
  light and dark of `pillars`. Nothing may change size by more than one level; where it does, the
  reviewer checks the mapping table above. Run at the largest accessibility text size on `pillars`
  and confirm text still scales (the helpers passed `relativeTo:`, so this is a regression guard).

### Task 9: Bring the Share Extension and the widgets onto the type tokens

- **Closes:** G-1 (major), G-3 (major).
- **Files and sites:** `ios/AgentCyInspirationShare/InspirationShareDesign.swift:68-73` — the six
  `share*` fonts are `Font.custom("InterVariable", size:)` with **no `relativeTo:`** at 26/20/16/16/
  12/14, mapping to none of the seven levels. `ios/AgentCyInspirationShare/ShareViewController.swift:841,
  864, 889, 905` — four raw `.font(.system(size: 28/36/22/16))`.
  `ios/AgentCyWidgets/WidgetViews.swift` — `Font.widgetInter(size:weight:)` at 50 sites, a third raw
  escape hatch, also without `relativeTo:`.
- **Shared thing introduced:** move the seven semantic levels into `ios/AgentCyShared/` so all three
  targets read one definition; the widget family keeps its own sizes only where a widget family size
  class genuinely requires it, and gains `relativeTo:` in every case.
- **Tests:** Task 1's gate now searches `ios/AgentCyInspirationShare` (added in Task 1) and must exit
  0. Add `ios/AgentCyWidgets` `Font.custom` without `relativeTo:` to the banned pattern.
- **Acceptance:** share a link into the app on phone, light and dark, at default and at the largest
  accessibility text size; the 946-line share sheet must scale. Widget gallery screenshots at both
  sizes, light and dark. `ShareViewController.swift` is full-screen iPhone UI on the PRD's shared-link
  ideation path and is the one surface the app does not control the exit from.

### Task 10: One empty state, extended, at every list screen

- **Closes:** L4-16 (major), L1-17 (major).
- **Files and sites:** extend `AgentEmptyState` (`DesignTokens.swift:1527-1555`) with an optional
  trailing `actions` `@ViewBuilder` and an optional `alignment`, then replace the three bespoke
  copies — `HomeDashboardView.swift:2466-2480` (straight swap), `SocialGridView.swift:587-605`,
  `AgendaView.swift:805-830` — and the ~20 bare-`Text` empty states:
  `HomeDashboardView.swift:676, 743, 865, 900, 1088, 1161, 1243`,
  `DesktopAppShellView.swift:664, 753, 911, 1105, 1153`, `IdeaBankView.swift:885-895`,
  `VoiceSparkView.swift:574`, `MCPBridgeSettingsView.swift:390, 1039`,
  `MCPDesktopReviewView.swift:459`, and `AppShellView.swift:458` (a `ContentUnavailableView`, which
  is also one of the SF Symbol sites in Task 16). Every one gets a second sentence naming the action.
- **Shared thing extended:** `AgentEmptyState`, from 13 adopters to ~36, all keeping the
  `.accessibilityElement(children: .combine)` the bespoke copies dropped.
- **Tests:** a unit test that `AgentEmptyState` requires a non-empty `message`; a lint rule flagging a
  bare `Text` returned as the whole body of a `…EmptyView`/`empty…` computed property.
- **Acceptance:** phone light and dark of empty `idea-bank`, `feed-grid`, `day-agenda`, `voice-spark`;
  desktop light and dark of the Control Center's five empty panes. VoiceOver must announce each as one
  element.

### Task 11: One hairline rule

- **Closes:** L4-17 (minor — shares its sites with Tasks 8 and 15, so it lands here, not in the sweep).
- **Files and sites:** add one `AgentRule` view to `DesignTokens.swift`
  (`Rectangle().fill(Color.agentHairline).frame(height: 1)`); point `SectionRuleHeader`'s underline
  (`DesignTokens.swift:1466`, 66 adopters, currently `agentBorder`) and `AgentDesktopMenuDivider`
  (`:1088-1096`) at it; delete `PaperHairline` (`PillarsView.swift:2158-2162`, a hand-mixed
  `agentText.opacity(0.12)`) and replace its nine uses at `PillarsView.swift:584, 585, 597, 1088,
  1500, 1736, 1761, 1762, 1922`; sweep the 56 bare `Divider()` calls onto it.
- **Shared thing introduced:** `AgentRule`. Which token is the rule colour — `agentBorder` or
  `agentHairline` — is decided here and written into design.md; the finding only asks that there be one.
- **Tests:** lint rule: zero `Divider()` and zero `Rectangle().fill(` … `frame(height: 1)` outside
  `DesignTokens.swift`.
- **Acceptance:** phone and desktop, light and dark, of `pillars` (nine rules) beside `tasks` (which
  uses `SectionRuleHeader`). The rules must be the same colour in both appearances.

### Task 12: One relative-date helper

- **Closes:** L4-15 (major).
- **Files and sites:** add `AgentRelativeDate` to `ios/AgentCy/Services/` beside the other
  presentation policies, with `dayLabel(for:relativeTo:)` and `shortDayLabel(for:relativeTo:)`, both
  built on `.formatted(.dateTime…)` and both taking an injectable `now`. Replace the five
  implementations: `TasksView.swift:320-366` (two of them — and delete its private `formatter`,
  `formattedDay`, `formattedShortDay` at `:352-366`, which pin `Locale(identifier: "en_US")`),
  `VoiceSparkView.swift:1386-1391`, `DesktopAppShellView.swift:1486-1490`,
  `HomeDashboardView.swift:2620-2629`. `TasksView`'s `Past due · ` prefix stays at the call site.
- **Shared thing introduced:** `AgentRelativeDate`; it also settles the day-boundary disagreement
  (`isDate(_:inSameDayAs:)` + manual `+1 day` versus `isDateInToday`/`isDateInTomorrow`).
- **Tests:** unit tests with an injected `now` across a midnight boundary, in `en_US`, `en_GB` and
  `de_DE`, asserting Today / Tomorrow / Yesterday and the fallback order.
- **Acceptance:** phone light of `tasks` and `task-detail` for the same due date — they read
  `Thu, Mar 6` and `Mar 6` today and must agree after. Repeat with the device region set to United
  Kingdom; the date order must follow the locale.

### Task 13: `plan-week` uses the shared page rail

- **Closes:** L4-19 (minor); L1-14 is the same defect, cross-referenced.
- **Files and sites:** `ios/AgentCy/Views/Plan/PlanView.swift:127-158` — delete the bespoke
  `HStack(alignment: .center, spacing: AgentSpacing.x1)` and call `AgentPageRail`
  (`ios/AgentCy/Views/Shared/CreatorAvatar.swift:114-141`), passing the search and feed-shortcut
  buttons through its existing `Actions` generic slot. Drop the `iconSize: 16` overrides at `:137`
  and `:144` (Task 17 owns the token set; here they simply take the 17 pt default).
- **Shared thing reused:** `AgentPageRail`, already at six sites — `HomeDashboardView.swift:797`,
  `TasksView.swift:686`, `SocialGridView.swift:484`, `PillarsView.swift:470`,
  `IdeaBankView.swift:370`, `SavedPostsLibraryView.swift:234`. `plan-week` is the sole hold-out; the
  page inventory's claim that the rail is "used only by home … not reused anywhere else" is wrong and
  is corrected in Task 23.
- **Tests:** an assertion in the design lint that every tab-root file contains `AgentPageRail(`.
- **Acceptance:** phone light and dark of `plan-week` beside `tasks`; the rail height, spacing and
  the three circles must match. Desktop light and dark of the same.

### Task 14: The last hand-built selector rail becomes a segmented `Picker`

- **Closes:** L1-13 (major).
- **Files and sites:** `ios/AgentCy/Views/Pillars/PillarsView.swift:1700-1723` — an `HStack` of
  `Button`s with `.background(… in: .capsule)` inside another capsule. Replace with
  `Picker(...).pickerStyle(.segmented)` matching `AgendaView.swift:424-434`. Per-tab counts move into
  the segment labels or drop.
- **Shared thing reused:** the native iOS 26 segmented `Picker`, which eight other rails already use
  (`AgendaView.swift:434`, `TasksView.swift:663`, `SocialGridView.swift:546`,
  `QuickCaptureView.swift:533`, `WeeklyFocusView.swift:893`, `ResumablePostEditorView.swift:1718`,
  `SettingsSubpages.swift:1499`, `DesignTokens.swift:1426`).
- **Tests:** lint rule: no `in: .capsule` inside a horizontal selector `HStack`.
- **Acceptance:** phone light and dark of `pillar-guide` beside `plan-week`'s rail
  (`tab-today-light.png` is the correct pattern, `tab-pillars-light.png` the incorrect one). Desktop
  light and dark of the same.

### Task 15: Rebuild the desktop MCP review pane on shared chrome

- **Closes:** L1-19 (major).
- **Files and sites:** `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift` (894 lines, desktop
  only) — the least conformant surface in the app. Rebuild its header on `AgentDesktopDetailRail` +
  `AgentDesktopDetailBackButton` + `EditorialHeader`; the two Back controls at `:104-120` and
  `:146-162` become `AgentDesktopDetailBackButton`; `:477` becomes `AgentIconView(.forward, size: 13)`;
  `:459`'s empty state becomes `AgentEmptyState` (Task 10); map its 20 non-token fonts (done in
  Task 2), its six off-scale paddings (`:128`, `:170` 14; `:284` 6; `:363` 10; `:415` 40; `:481` 14)
  and radius 14 at `:323` onto the scale; its five bare `.buttonStyle(.plain)` take
  `AgentPressButtonStyle` (Task 18).
- **Shared thing reused:** `AgentDesktopDetailRail` (10 refs), `AgentDesktopDetailBackButton`,
  `EditorialHeader` (19 refs).
- **Tests:** the design lint must return zero hits for this file afterwards.
- **Acceptance:** desktop light and dark of `ask-cy-review-desktop-workspace` beside another desktop
  drill-down (`settings-mcp-bridge`). Back control, rail and type must be indistinguishable. One file,
  35 matrix cells closed.

### Task 16: Every icon goes through `AgentIcon`

- **Closes:** L1-07 (major), APPLE-19 (minor), G-6 (minor, folded into L1-07).
- **Files and sites:** the complete union is **16 live sites, 12 of them on iPhone surfaces** — not
  L1's six and not APPLE-19's twelve. `MCPDesktopReviewView.swift:110, 152, 477` (done in Task 15);
  `PillarsView.swift:2264` (colour picker eyedropper); `DesktopAppShellView.swift:339` (appearance
  toggle); `AppShellView.swift:458` (`ContentUnavailableView`, done in Task 10);
  `ShareViewController.swift:840, 863, 888, 904` and `:633` (`Label(…, systemImage: "sparkles")`) and
  `:754` (`"arrow.down.circle.fill"`); `WidgetViews.swift:186, 204, 217`;
  `PhoneControls.swift:11` (`Label("Voice Spark", systemImage: "mic.fill")`, Control Center — in
  scope by `ios/project.yml:200-202`'s own rule). `CreatorSessionActivity.swift:31`'s
  `var systemImage: String` dies with DEC-05 and is not counted here.
- **Shared thing extended:** add the missing Nucleo cases to `AgentIcon`
  (`DesignTokens.swift:79-215`): chevron-left, chevron-right, eyedropper, appearance, link,
  link-badge-plus, mic, waveform. Ship the assets to all three catalog-consuming targets.
- **Tests:** Task 1's lint rule for `Image(systemName:` and `systemImage:` must return zero across
  `ios/AgentCy ios/AgentCyWidgets ios/AgentCyInspirationShare ios/AgentCyShared`.
- **Acceptance:** phone light and dark of the share sheet, the widget gallery and the Control Center
  control; desktop light and dark of the appearance toggle and the pillar colour picker. Every glyph
  must be Nucleo at the same optical weight as its neighbours.

### Task 17: An icon-size token set

- **Closes:** L1-15 (minor — shares its sites with Task 4, so it lands here).
- **Files and sites:** remove the `iconSize` parameter from `AgentToolbarIconLabel`
  (`DesignTokens.swift:308`, default 17, overridden at 8 of 14 call sites) so every 44 pt circle
  renders one glyph size. Add `AgentIconSize` (mark 12 / inline 15 / control 17 / feature 24) and
  have `AgentIconView` take it instead of a raw `CGFloat`. Today `AgentIconView(size:)` is called
  with **18 distinct values** (8,9,10,11,12,13,14,15,16,17,18,19,20,22,23,24,26,30) at 222 sites.
  Override sites to correct: `PlanView.swift:137, 144`, `TasksView.swift:721`,
  `IdeaBankView.swift:409, 423, 438`, `PillarsView.swift:510`, `ResumablePostEditorView.swift:571`.
- **Shared thing introduced:** `AgentIconSize`.
- **Tests:** lint rule: `AgentIconView(` never takes a numeric literal for `size:`.
- **Acceptance:** phone light of `plan-week` and `idea-bank` — the header circles currently carry 16,
  17 and 18 pt glyphs in identical 44 pt discs. Measure the glyph bounding box off the screenshots
  with `png_measure_lib.py`; all three must match.

### Task 18: One press feedback

- **Closes:** L1-11 (major).
- **Files and sites:** 234 bare `.buttonStyle(.plain)` across 30 view files against 97 correct
  `AgentPressButtonStyle()` uses. Worst: `HomeDashboardView.swift` 24, `QuickCaptureView.swift` 24,
  `AgendaView.swift` 24, `ResumablePostEditorView.swift` 19, `PillarsView.swift` 16,
  `OnboardingView.swift` 16; the full site list is `findings-consistency.md` §2's `R9-press` index.
  `DesignTokens.swift:296` is done in Task 4 and alone fixes all 56 canonical toolbar controls.
  Keep `.plain` only where the label is a full row already handled by `agentHoverRow()`; record that
  exception in design.md.
- **Shared thing reused:** `AgentPressButtonStyle` (0.96 scale, `easeOut` 0.12 s). On Catalyst it
  returns `nil` per the Motion section (Task 28) — a pointer has hover.
- **Tests:** lint rule counting bare `.buttonStyle(.plain)`; assert it is under the recorded
  `agentHoverRow` allowance and that the allowance is enumerated in a checked-in list.
- **Acceptance:** a short screen recording on phone (light) pressing five controls across three
  pages — every one must dip identically. Desktop: confirm no dip and correct hover.

### Task 19: One word for leaving a screen

- **Closes:** L1-16 (major), L3-21 second half (the `post-reschedule` label split).
- **Files and sites:** add the rule to design.md — a surface that can discard unsaved edits says
  "Cancel"; a read-only surface uses the icon-only glass X; "Done" is never a dismissal. Then apply
  it. Current census: **49 × "Cancel", 47 × "Close" (not 46), 8 × "Done" of which 2 are dismissals**.
  Same-file collisions: `BrandCabinetView.swift:787` vs `:1064` and `:1111` (all three in
  `.cancellationAction`); `TasksView.swift:1396` (icon X) vs `:858` ("Done") vs `:2571` ("Cancel");
  `QuickCaptureView.swift:376` vs `:2148`. `TasksView.swift:858` (task-filter) and
  `PostMediaViews.swift:897` (post-editor-media-manager) currently have no way to discard at all and
  need one. `AgendaView.swift:3964` is text "Close" on phone while `:3985` is an X labelled "Cancel"
  on desktop — one sheet, two words. `IdeaBankView.swift:406-418` swaps *form* at runtime: the same
  action is a 44 pt glass X at normal Dynamic Type and a text "Cancel" at large sizes — pick one.
  `RootView.swift:495-503` (`installation-invite-gate`) is a text "Close" and is the surface App
  Review reaches — it takes the rule too. `AppShellView.swift:583`'s `Button("Skip tour")` is a skip,
  not a dismissal, and is left as is with a comment saying so.
- **Shared thing introduced:** the design.md rule; ~100 sites, a pure string and toolbar-item change.
- **Tests:** lint rule: `Button("Done")` may not appear in `.cancellationAction`.
- **Acceptance:** phone light of `brand-cabinet` (three sheets), `tasks` (three), `quick-capture`
  (two), `post-reschedule`, `installation-invite-gate`; desktop light of `post-reschedule`. Then
  repeat `idea-bank` at the largest accessibility text size — the control must not change form.

### Task 20: Creation Hub obeys the quick-add header rule

- **Closes:** G-7 (major).
- **Files and sites:** `ios/AgentCy/Views/Capture/CreationHubView.swift:213-247` — `mobileHeader`
  hand-builds its own `VStack`/`ZStack` and references neither `AgentQuickAddLayout` nor
  `agentQuickAddHeaderSurface()`. design.md:389-394 states this as a **hard** rule: a 72-point control
  row placed 12 points below the safe area, never a one-off offset. Creation Hub is the entry point
  to every Quick Action sheet in the app, so its control row currently sits at a different height
  from every sheet it opens — `VoiceSparkView.swift:420`, `QuickCaptureView.swift:509`,
  `SocialGridView.swift:1057`, `SavedPostsLibraryView.swift:449` all call the modifier;
  `CreatorSessionView.swift:320-321, 387-388` uses the metrics directly.
- **Shared thing reused:** `AgentQuickAddLayout` / `agentQuickAddHeaderSurface()`. Lands after Task 4,
  which supplies the `highlight` knob the hand-roll existed for.
- **Tests:** lint rule: any file presenting a phone Quick Action sheet must call
  `agentQuickAddHeaderSurface()`.
- **Acceptance:** phone light and dark — capture `creation-hub`, then open `quick-capture` and
  `voice-spark` from it. Overlay the three captures; the close control's centre must land on the same
  y in all three (it does not today).

### Task 21: Every tap target clears the minimum

- **Closes:** L1-18 (the two remaining sites, major).
- **Files and sites:** `SocialGridView.swift:1235-1253` (32 pt − / + steppers on
  `day-agenda-add-live-post`) and `DesktopAppShellView.swift:340-346` (36 pt appearance button;
  the desktop floor is 40). Both take an outer `.frame(width: 44, height: 44).contentShape(.circle)`
  (44 on phone, 40 on desktop). `SocialGridView.swift:1044` (40 pt close) and
  `InspirationCaptureViews.swift:211` (24 pt Save) are closed by Tasks 4 and 5.
- **Shared thing reused:** the geometry from Task 4.
- **Tests:** none automatable at this scope; the design-review checklist's HT row owns it going
  forward.
- **Acceptance:** phone light of `day-agenda-add-live-post` and desktop light of the shell,
  with the frames measured off the captures.

### Task 22: A design-consistency pass over the two shipping extensions

- **Closes:** G-4 (major, a scope item rather than a single defect).
- **Files and sites:** `ios/AgentCyInspirationShare/ShareViewController.swift` (946 lines) and
  `ios/AgentCyWidgets/WidgetViews.swift` (1,101 lines) — 2,047 lines of iPhone UI a beta tester sees,
  audited by nobody in this pass. L1's 164-surface matrix is drawn entirely from `ios/AgentCy`.
  Typography is closed by Task 9 and icons by Task 16; this task covers what is left: close controls,
  empty states, radii, hit targets, press feedback, and both appearances, including
  `ios/AgentCyInspirationShare/InspirationShareDesign.swift`'s own colour and spacing decisions.
- **Shared thing reused:** whatever of `AgentCyShared` the extensions can link;
  `ios/project.yml:243-246` currently compiles only three shared files into the share extension, so
  expect to add the token file there.
- **Tests:** run Task 1's design lint over both targets (Task 1 added the missing search path).
- **Acceptance:** phone light and dark, at default and largest accessibility text size: the full
  share flow from another app, and both widget sizes in the gallery. The contract's "every screen and
  sheet passes one design-consistency checklist" is currently untrue of these two targets; this task
  is what makes the claim honest.

### Task 23: Correct `design.md` and the page inventory where the code wins

- **Closes:** the six `design.md` corrections that are records rather than decisions
  (`findings-consistency.md` §6 items 1, 3, 5, 6, 7, 8), plus the inventory corrections from L4-19,
  L1-18 and APPLE-18.
- **Files and sites:** `design.md` — delete the sentence at 314-315 saying the capsule styles are
  "pending a code update" (that update shipped as commit `8d5767b`); document the 1 pt `agentBorder`
  stroke `AgentActionButtonTheme` adds to every tier (`DesignTokens.swift:820-823`); resolve
  `AgentRadius.structural` (8) sitting beside `.control` (8) — document one or delete one; add rows
  for `Color.agentFocusControl` (`DesignTokens.swift:475`) and `Color.agentWarmWhite` (`:466`), or
  fold `agentFocusControl` into `actionAccent` (it tints one toggle at `WeeklyFocusView.swift:919`
  where every other toggle uses `actionAccent`); resolve footnote † — either ship the moss / ochre /
  dusk values into `AgentColorPalette` or mark the botanical refresh not-for-beta; add `AgentPageRail`
  to the Components list beside `EditorialHeader`. `docs/refinement/01-page-inventory.md` — correct
  the `AgentPageRail` entry (six adopters, not one), resolve the tasks/pillars/idea-bank "uncertain"
  header rows, replace the ten-variant close census with the corrected eleven-implementation /
  four-geometry table, and delete family #10 ("no visible control at all") — `installation-invite-gate`
  has a text "Close" at `RootView.swift:495-503`.
- **Tests:** none; this is a document task, and it is explicitly *not* a substitute for a fix.
- **Acceptance:** a reviewer reads design.md against `DesignTokens.swift` and finds no statement the
  code contradicts, except the three the decision packet holds (DEC-01, DEC-02, DEC-03).

### Task 24: Minor sweep — radii, paddings, stray shadows

- **Closes:** L1-12 (minor), L1-22 (minor), L1-20 (minor, the nine neutral one-offs; the accent
  glows are closed by Task 6).
- **Files and sites:** map the eight off-scale radii at ~60 sites — 3/5/6→`AgentRadius.control`,
  9/13/14→`.card` (12), 18→`.panel` (16), 22→`.dashboard` (20); heaviest files
  `CreatorSessionView.swift` (14 sites) and `OnboardingView.swift` (17). Round the 29 off-scale
  paddings (14, 10, 18, 28, 40) to the nearest 4-pt step; leave the 1–7 pt optical nudges on marks and
  badges but document them in design.md as sanctioned nudges rather than violations. Route the nine
  neutral shadows through `agentSurfaceChrome(role:)` — `CreationHubView.swift:229, 244`,
  `AskCyView.swift:1290, 1742, 1767`, `AppShellView.swift:373, 717, 923`, `VoiceSparkView.swift:466`
  — and delete the app's only raw `Color(white:)` constructor at `AskCyView.swift:1742`. Full site
  lists are in `findings-consistency.md` §2's `R5-radii`, `R4-space` and `R12-shadow` indexes.
- **Shared thing reused:** `AgentRadius`, `AgentSpacing`, `agentSurfaceChrome`.
- **Tests:** the design lint's radius rule (Task 1) must return zero.
- **Acceptance:** phone and desktop, light and dark, of `onboarding-flow` and `creation-hub` — the
  two heaviest files. Nothing may shift by more than 4 pt; anything that does is called out.

### Task 25: (after H1: DEC-01) Settle Liquid Glass on the paper canvas

- **Closes:** L1-21 (major), APPLE-13 (major). These are one token-level decision, not two.
- **Files and sites:** all 13 `glassEffect` sites are `.clear`; zero are `.regular`. The tab bar
  (`AppShellView.swift:809-811`), `AgentToolbarIconLabel` (`DesignTokens.swift:314`),
  `AgentPhonePostActionButton` (`DesignTokens.swift:975`), and — if it still exists after Task 4 —
  `AgentCircularGlassIconButton` (`:928`). Plus `ProfileSettingsButton` (`CreatorAvatar.swift`),
  which measures 45.33 pt with an `agentSurface` `(253,253,251)` fill 30 pt from two 44.00 pt circles
  filled `(255,255,255)` on a `(245,246,243)` canvas.
- **Blocked on:** DEC-01. Do not start this task before H1.
- **Tests:** re-run `measure-close-controls.py`; all circles in one rail must report one diameter and
  one interior fill.
- **Acceptance:** phone light and dark of `home` (the tab bar smear at
  `evidence/apple/tabbar-glass-legibility.png` is the before), and of `plan-week`'s three-circle rail.
  Attach the measured diameters and RGB fills before and after.

### Task 26: (after H1: DEC-02) Settle the button metric

- **Closes:** L1-09 (major), and the second `design.md` correction.
- **Files and sites:** add `minHeight` and `labelFont` constants to `AgentActionButtonTheme`
  (`DesignTokens.swift:760-771`) and have all five shared styles read them, replacing the six current
  minimum heights and two label sizes: `:817`, `:844`, `:871` (52 pt / `.agentHeadline` 18), `:790`
  (44 pt / `.agentSubtext` 13), `PostMediaViews.swift:363` (44/13),
  `AskCyView.swift:2445` `ReviewBatchButtonStyle` (36 pt, radius 12 — delete it, 3 sites move to
  `AgentQuietSecondaryButtonStyle`), `OnboardingView.swift:1966` (56 pt) and `:2018` (54 pt), both
  deleted in Task 7. design.md says 40 / 13; the code says 52 / 18; nothing in the code is 40.
- **Blocked on:** DEC-02. Do not start before H1.
- **Tests:** unit assertion that every shared style's resolved height equals
  `AgentActionButtonTheme.minHeight`.
- **Acceptance:** phone and desktop, light and dark, of one screen per role. Then update design.md to
  the chosen number in the same commit.

### Task 27: (after H1: DEC-03) Settle the desktop modal footprints

- **Closes:** G-8. design.md:384-388 states a **hard** rule: one desktop modal footprint, 900 × 860,
  and "do not introduce smaller per-flow modal sizes". `DesktopNavigation.swift:137`
  (`creationHubMenuMetrics = 600 × 560`) breaks it; `:126` (`cyReviewModalMetrics = 1180 × 860`) is a
  second footprint even though it is larger. L1 filed both as documentation corrections on the
  grounds that "both carry explanatory code comments, so both look deliberate" — a code comment is
  not Chey's approval, and the contract's "code wins" clause settles disagreements, not a rule the
  document states as hard.
- **Blocked on:** DEC-03. Do not start before H1.
- **Files and sites:** either `DesktopNavigation.swift:110, 126, 137` change, or design.md's hard rule
  gains both as named exceptions — whichever DEC-03 says.
- **Tests:** a unit assertion over `DesktopLayoutPolicy`'s metrics matching the approved set.
- **Acceptance:** desktop light and dark of the Quick Add choice card and the Cy review workspace.

### Deferred (B1)

- **Hit-target verification across the remaining 156 surfaces.** L1 §8 is explicit that its `?` cells
  mean *not checked*, not *passing*, and only 8 of 164 surfaces were measured. Tasks 5, 21 and 4 close
  every target a lane actually measured under the minimum. A full sweep is a measurement pass, not a
  fix pass, and it belongs to the design-review process (`processes/design-review.md`, checklist row
  HT), which runs on every changed surface from here on. **Reason: no evidence of a further defect
  exists; inventing one would be guessing, and the process catches new ones at the point of change.**
- **Contrast ratios.** Measured by nobody this pass, in either appearance. Same owner and same reason:
  `processes/design-review.md` adds a contrast row that runs per changed surface. **Reason: a
  repo-wide contrast sweep is a discovery lane's job, not a batch's, and none of the eight lanes
  produced evidence of a failing pair.**

---

## B2 · Motion and heaviness

### Task 28: The Motion section for `design.md` and the `AgentMotion` tokens

- **Closes:** nothing on its own; it is the precondition for every other B2 motion task, and the
  contract's "one motion vocabulary in `design.md` and code" lives or dies here.
- **Files and sites:** paste `docs/refinement/draft-motion-section.md` into `design.md` as the Motion
  section, and add `enum AgentMotion` to `ios/AgentCy/Design/DesignTokens.swift`: `press` `easeOut`
  0.12, `reveal` `easeOut` 0.18, `move` `easeInOut` 0.22, `settle` `easeOut` 0.26, `gesture`
  `spring(duration: 0.28, bounce: 0)`, plus `resolved(_:reduceMotion:)`,
  `transition(_:reduceMotion:)`, `run(_:reduceMotion:_:)` and `entranceScale = 0.94`.
  `AgentButtonPressFeedback` keeps its shape and returns `AgentMotion.press`, so the thirteen button
  styles are untouched. On Catalyst `press` returns `nil`. Fold the six existing per-file policies —
  `AgendaMotionPolicy`, `TaskRootMotionPolicy`, `DesktopShellMotionPolicy`,
  `IdeaBankRootAccessibilityPolicy`, `AppShellMotionPolicy`, `CyAnimatedLogoMotionPolicy` — into
  `AgentMotion.resolved` so there is one answer, not six; keep their existing unit tests, repointed.
- **Shared thing introduced:** `AgentMotion`. Every later B2 task adopts it; nothing else may declare
  a curve or a duration.
- **Tests:** the folded policies' existing tests, repointed at `AgentMotion.resolved`; a new test
  asserting `resolved` returns `nil` and `transition` returns `.opacity` under Reduce Motion.
- **Acceptance:** the design lint (Task 1) gains a rule banning `.snappy`, `.smooth`, `.bouncy` and
  any literal `duration:` outside `DesignTokens.swift`; it must exit 1 today. No screenshots.

### Task 29: Stop the perpetual Cy mark

- **Closes:** L2M-01 (blocker), L2H-04 (blocker).
- **Files and sites:** `ios/AgentCy/Design/DesignTokens.swift:1644-1680` (`CyAnimatedLogo`) — delete
  the perpetual `TimelineView(.animation(minimumInterval: 1/30))` and render the static `CyAsterisk`
  branch it already has for Reduce Motion, for everyone. The animated `shadow(color: … radius: 5 +
  pulse*4)` at `:1673-1679` cannot be cached and re-rasterizes every frame. Call sites:
  `HomeDashboardView.swift:811`, `AskCyView.swift:918, 1211, 1387`. If a "Cy is alive" cue is wanted,
  run one 2.8 s cycle on appear and stop, animating `opacity` only.
- **Shared thing reused:** `AgentMotion` (Task 28); `CyAnimatedLogoMotionPolicy` is folded in there.
- **Tests:** a unit test that `CyAnimatedLogo` renders its static branch when Reduce Motion is off.
- **Acceptance and before/after measurement:** re-run
  `docs/refinement/evidence/L2/idle-frames-by-tab.txt`'s method — launch into a tab, touch nothing
  for 10 s, `xcrun simctl io … recordVideo`, count frames with `ffprobe`. **Before: home 300 frames /
  9.98 s (30.1 fps), cy 599 / 9.98 s (60.0 fps); plan-week, pillars, idea-bank, tasks 1 frame each.
  After: all six tabs must return 1 frame per 10 s.** Attach both tables. Phone light and dark
  screenshots of `home` and `cy` confirming the mark still reads.

### Task 30: No `repeatForever` in shipped decoration

- **Closes:** L2M-02 (major), APPLE-17 (minor — same defect class; closed here rather than in B6 so
  B6 does not re-touch files this batch rewrote).
- **Files and sites:** seven `repeatForever` durations — `AskCyView.swift:1020` (0.9 s),
  `CreationHubView.swift:271` (1.05), `AppShellView.swift:724` (1.15),
  `AppleAccountAccessView.swift:533` (1.6), `DesignTokens.swift:1628` (1.8),
  `QuickCaptureView.swift:89` (7), `SettingsSubpages.swift:2119` (8) — plus three `TimelineView`
  cycles at 1.1, 1.8 and 2.8 s. Shadow radius is an animation target at `DesignTokens.swift:1676-1679`,
  `AppShellView.swift:717-720`, `AppShellView.swift:923-926`, `CreationHubView.swift:229-232`.
  `CyPendingReviewLogo` (`DesignTokens.swift:1627`) lives in the **phone tab bar**, so a spinning
  glyph there means the shell can never idle on any screen — it becomes a static tinted mark.
  Genuine progress indicators are exempt and share one spinner speed:
  `AppleAccountAccessView.swift:531` (during restore) and `AskCyView.swift:1018` (during a refresh).
  APPLE-17's two sites — `AppShellView.swift:722-726` and `CreationHubView.swift:269-273` — evaluate
  `guard !reduceMotion` once in `.onAppear`, so turning Reduce Motion on mid-session never cancels the
  loop; drive them from `.onChange(of: reduceMotion, initial: true)` instead, the pattern
  `AppleAccountAccessView.swift:466-468` already uses.
- **Shared thing reused:** `AgentMotion`; the design.md rule from Task 28 (nothing in decoration
  repeats, no animation targets a shadow).
- **Tests:** lint rule: `repeatForever` appears only at the two exempt progress sites, enumerated in
  a checked-in allowance.
- **Acceptance and before/after measurement:** re-run the idle recording on `settings-access`,
  `quick-capture` and `account-access-gate` (the three remaining looping surfaces). Each must fall to
  1 frame per 10 s with no network call in flight. Then toggle Reduce Motion on while the walkthrough
  and Creation Hub are open — the pulse must stop within one frame; capture a short recording.

### Task 31: Every animation goes through `AgentMotion`, so Reduce Motion is honored

- **Closes:** L2M-04 (blocker).
- **Files and sites:** sixteen file:line groups have no Reduce Motion branch, of which one
  (`AskCyView.swift:1018`) is exempt as a genuine progress indicator per L2M-02 — the finding's title
  says eleven, the Where line lists sixteen. `AppShellView.swift:159` (+`:115`),
  `AppShellView.swift:218, 221` (+`:94`), `ResumablePostEditorView.swift:434, 437`,
  `PillarsView.swift:1705, 1831, 1838, 1848`, `QuickCaptureView.swift:996`, `TasksView.swift:2322`,
  `DesktopAppShellView.swift:112`, `OnboardingView.swift:158` / `:1225`,
  `ActiveCreatorSessionFloatingTimer.swift:39`, `CreatorSessionView.swift:1296`,
  `DesignTokens.swift:1689`. `CyThinkingMark` (`DesignTokens.swift:1689-1707`) is the worst: under
  Reduce Motion it still enters `TimelineView` and drives `scaleEffect(0.94 + pulse*0.12)` and
  `opacity(0.68 + pulse*0.32)` — a direct breach of a named non-negotiable. It also has no
  `minimumInterval`, so it ticks at display rate; give it a static Reduce Motion branch and throttle
  the live branch to 1/30.
- **Shared thing reused:** `AgentMotion.resolved` / `.transition` / `.run` (Task 28) — the only door.
- **Tests:** lint rule: no `.animation(` and no `withAnimation(` outside `AgentMotion.run` /
  `AgentMotion.resolved`. A unit test per folded policy.
- **Acceptance:** with Reduce Motion on, record the phone shell through: completing a task (undo
  toast), focusing a text field (bottom nav), an onboarding step change, a Pillars tab change, and a
  Cy turn. Nothing may travel; every change may fade. Repeat on desktop for
  `DesktopAppShellView.swift:112`.

### Task 32: The tab bar moves instead of springing

- **Closes:** L2M-03 (major), L2H-05 (major).
- **Files and sites:** `ios/AgentCy/Views/Shell/AppShellView.swift:849` —
  `.animation(reduceMotion ? nil : .snappy(duration: 0.32), value: selection)` driving the
  `matchedGeometryEffect` glass pill at `:794` becomes `AgentMotion.move` (`easeInOut` 0.22). The
  content layer is already correct: `appTabLayer` (`:733-741`) sets `transaction.animation = nil`.
- **Shared thing reused:** `AgentMotion.move`.
- **Tests:** none beyond the lint.
- **Acceptance and before/after measurement:** re-run
  `docs/refinement/evidence/L2/tab-switch-bursts.txt`'s method — six consecutive tab taps, variable
  frame-rate recording, burst detection. **Before: 503 ms, 508 ms, 518 ms of continuous render per
  tap. After: under 260 ms per tap.** Note that the remainder above the declared animation is the
  newly revealed tab's body work, which Tasks 36 and 37 own; report both numbers so the split is
  visible.

### Task 33: Five durations and two curves, everywhere

- **Closes:** L2M-05 (major), L2M-06 (major).
- **Files and sites:** fourteen durations (0.12, 0.15, 0.16, 0.18, 0.20, 0.22, 0.24, 0.25, 0.26,
  0.28, 0.30, 0.32, 0.34) plus one bare `.snappy` with no duration (`AgendaView.swift:1588`), across
  `.easeOut`, `.easeInOut`, `.snappy`, `.smooth` and two zero-bounce springs. Delete
  `AgentModalResize` (`DesignTokens.swift:497`, `.smooth(duration: 0.34)` — a spring, and the longest
  UI animation in the app, over the 300 ms ceiling); its two call sites
  (`DesktopAppShellView.swift:235`, `AskCyView.swift:685`) take `AgentMotion.settle`, keeping the
  existing two-frame trick commented at `AskCyView.swift:676-684`, which is correct. Same-file
  duplicates to collapse: `AgendaView.swift:1954` / `:1966`; `AskCyView.swift:2194, 2204, 2214`;
  `AppShellView.swift:319` / `:343`; `DevelopBriefView.swift:448, 462`. The vocabulary-to-census
  mapping is `draft-motion-section.md` § "Mapping from the census"; the full touched-file list is its
  § "Sites the shared change touches" (23 files).
- **Shared thing reused:** `AgentMotion`.
- **Tests:** lint (Task 28) returns zero literal durations outside `DesignTokens.swift`.
- **Acceptance:** the numbers in `draft-motion-section.md` § "What this changes in numbers" become
  true — fourteen durations to five, four curve families to two eases and one spring, longest UI
  animation 0.34 s to 0.28 s. A reviewer greps and attaches the counts. Desktop recording of the Cy
  review modal resize, before and after; Chey's words for this were "sheets feel slow and springy".

### Task 34: One undo toast on both shells

- **Closes:** L2M-08 (major).
- **Files and sites:** phone `AppShellView.swift:110-119`, `:159`, `:349`; desktop
  `DesktopAppShellView.swift:108-115`, `:1647`. The phone declares both a transition and
  `.animation(.easeOut(duration: 0.24), value:)`; the desktop declares
  `.transition(.move(edge: .top).combined(with: .opacity))` and **nothing drives it** —
  `grep taskCompletionUndo DesktopAppShellView.swift` returns only 109, 110, 1647, so it pops.
  Introduce one `AgentUndoToast` modifier carrying the transition, `AgentMotion.settle` and the
  Reduce Motion collapse; both shells call it.
- **Shared thing introduced:** `AgentUndoToast`.
- **Tests:** a unit test that the modifier's transition collapses to `.opacity` under Reduce Motion.
- **Acceptance:** complete a task on phone and on desktop, light and dark, and record both. The toast
  must arrive and leave identically on the two form factors. Repeat with Reduce Motion on.

### Task 35: Swipe-to-delete keeps the finger's velocity

- **Closes:** L2M-09 (minor — it shares its site with no other fix, but it is the one place a spring
  is correct and it introduces `AgentMotion.gesture`, so it is not sweep material).
- **Files and sites:** `ios/AgentCy/Views/Shared/AgentSwipeDeleteRow.swift:110-125` and `:130-136` —
  the gesture reads `value.predictedEndTranslation.width` to choose the resting state, then animates
  with a fixed `easeOut` 0.16 s that starts from zero velocity and restarts from zero if the creator
  swipes back mid-flight. Both call sites take `AgentMotion.gesture` (`spring(duration: 0.28,
  bounce: 0)`).
- **Shared thing reused:** `AgentMotion.gesture`.
- **Tests:** none; this is a feel change.
- **Acceptance:** phone recording of a fast swipe, a slow swipe, and a swipe reversed mid-flight, on
  `tasks`. The reversal must not restart from zero. **This one needs Chey's device to judge** — the
  motion standards are explicit that swipe gestures are judged on real hardware; flag it in the
  review for the AUTH-01 session.

### Task 36: Build only the selected tab

- **Closes:** L2H-01 (blocker).
- **Files and sites:** `ios/AgentCy/Views/Shell/AppShellView.swift:61-83` — six `NavigationStack`s in
  one `ZStack` — and `:733-741`, where `appTabLayer` sets only `opacity`, `allowsHitTesting`,
  `accessibilityHidden` and `zIndex`. `.opacity(0)` prevents neither layout nor body evaluation, so
  the code is the proof. Wrap each layer so its content is `EmptyView()` until first selection and
  drop it after a grace period, keeping at most the previously selected tab alive; or move to a
  `TabView` and let SwiftUI own the lifetimes.
- **Shared thing introduced:** one tab-lifetime policy, unit-testable, beside the other shell policies.
- **Tests:** a unit test over the lifetime policy (first selection builds, previous stays, older
  drops); plus an instrumented first-body counter per tab root, asserted in a debug-only test.
- **Acceptance and before/after measurement:** the finding's own proof — re-run `launchtime.sh` and
  compare Home-selected against Plan-selected. **Before: 553.5 ms vs 532.5 ms warm (they do not
  separate, although Home declares 12 whole-table queries and 29 derived arrays against Plan's 8 and
  0); cold `app_model_ready`→`destination_app` 1592 / 2474 / 1595 ms; total to first screen 2213 /
  3649 / 2305 ms. After: warm first-screen under 400 ms.** Note the skeptic's caution — divergence
  between Home and Plan is a weak test, because Home may not be much heavier than Plan on the 34-record
  fixture. **Use the first-body counter as the primary proof**, and the timing as corroboration; run
  the timing again against the synthetic store from Task 37.

### Task 37: Every `@Query` fetches only what the view shows

- **Closes:** L2H-02 (blocker).
- **Files and sites:** 245 `@Query` declarations across 27 view files (251 repo-wide, 6 in
  `App/RootView.swift`); `grep -rn '@Query(filter' ios/AgentCy` returns **0**. Scoping happens in
  Swift afterwards through a `scoped(_:)` helper duplicated in nine files
  (`HomeDashboardView.swift:1601` and `:2004`, `PillarsView.swift:180` and `:1363`,
  `TodayView.swift:29`, `WeeklyFocusView.swift:480`, `AgendaView.swift:239` and `:2867`,
  `AskCyView.swift:579`). Give every query a `#Predicate` on `workspaceID` — the models already
  conform to `WorkspaceScopedRecord` — and a `fetchLimit` where the view shows a bounded list.
  Heaviest: `AgendaView.swift:208-218` (25), `BrandCabinetView` (18), `TasksView.swift:461-466` (17),
  `SettingsSubpages` (17), `HomeDashboardView.swift:16-27` (14),
  `ResumablePostEditorView.swift:84-94` (14). `QuickCaptureView.swift:288-298` repeats the pattern
  inline. `TodayView`'s ten queries disappear with Task 61 rather than being fixed here.
- **Shared thing introduced:** one `@Query` initialiser helper beside `WorkspaceScope`, so the
  predicate is written once. **Split this task if the reviewer cannot hold it in one sitting: land the
  helper plus the six heaviest files first, then the remaining twenty-one.**
- **Tests:** a unit test per model that the helper's predicate matches `WorkspaceScope.includes`; a
  regression test that `grep -rn '@Query(' ios/AgentCy/Views | grep -v 'filter'` returns zero.
- **Acceptance and before/after measurement:** build a synthetic store of ~2,000 briefs, outputs and
  tasks (the `-agentCyPreviewData` fixture seeds 34 records, so every existing number is a floor).
  **Warm first-screen must not grow with row count; today it will.** Attach the two curves.

### Task 38: The post editor's first frame costs only the record being edited

- **Closes:** L2H-03 (major).
- **Files and sites:** `ios/AgentCy/Views/Brief/ResumablePostEditorView.swift` (5,412 lines,
  14 whole-table queries at `:84-94` and `:3117-3119`), presented from ten call sites —
  `HomeDashboardView.swift:684` and `:1273`, `QuickCaptureView.swift:325`,
  `ScheduledPostDetailView.swift:524`, `IdeaPostDraftView.swift:211`,
  `AgendaPostIdeaPickerView.swift:316`, `AskCyView.swift:768`, `MCPBridgeSettingsView.swift:839` and
  `:866`, `MCPDesktopReviewView.swift:133`. Predicate the fourteen queries (Task 37), move the
  series/episode-slot block behind the section that shows it, and render the media manager lazily.
- **Shared thing reused:** Task 37's query helper.
- **Tests:** the `editoronly` launch path (`RootView.swift:397-415`, `PreviewPostEditorRoot`) becomes
  a checked-in performance test with a ceiling.
- **Acceptance and before/after measurement:** `docs/refinement/evidence/L2/launch-milestones.txt`,
  `editoronly` rows. **Before: 234, 251, 275 ms between `app_model_ready` and the first frame.
  After: under 120 ms.** On a phone that work runs on the main thread *before* iOS starts the sheet
  animation, which is the other half of what Chey means by sheets feeling slow.

### Task 39: One owner for the reminder reconciliation

- **Closes:** L2H-06 (major).
- **Files and sites:** `refreshReminderSchedule(context:)` has twelve call sites outside its
  definition; three of them run during a single cold launch — `RootView.swift:197`,
  `AppShellView.swift:225`, `HomeDashboardView.swift:78`. Each awaits
  `reminderService.authorizationStatus()` and then a full `reminderService.reconcile(context:now:)`
  over the store (`AppModel.swift:1010-1017`). `AgentCyApp.swift:124-131` adds a fourth on every
  `scenePhase == .active`, alongside `FocusTaskRecurrenceService.reconcile`,
  `WidgetSnapshotService.refresh` and `MCPBridgeService.sync` in one `guard phase == .active` block.
  Delete the calls at `AppShellView.swift:225` and `HomeDashboardView.swift:78`, leaving
  `RootView.task` (`:170-206`) as the single startup owner, and debounce the `scenePhase` block so a
  quick app switch does not re-reconcile the whole store.
- **Shared thing introduced:** the debounce, beside the other lifecycle policies.
- **Tests:** a unit test over the debounce window; an os_log-counting assertion in the launch test.
- **Acceptance and before/after measurement:** count `reconcile` entries in one cold launch.
  **Before: 3. After: 1.** No instrument needed.

### Task 40: Hoist Quick Capture's workspace filters out of `body`

- **Closes:** L2H-07, at the skeptic's weakened severity (**minor**, not major — the lane says
  outright that a per-keystroke cost could not be isolated on the simulator, and the contract requires
  heaviness causes to be measured, not guessed).
- **Files and sites:** `ios/AgentCy/Views/Capture/QuickCaptureView.swift:286-298` — `pillars` and
  `socialAccounts` are computed inside `body` from `allPillars` / `allSocialAccounts` through
  `WorkspaceScope.includes`. Compute them once in `.task` and `.onChange(of: activeWorkspaceID)`.
  This half is a pure code change with no measurement dependency and ships now.
- **Shared thing reused:** Task 37's predicated queries make the six whole-table queries at
  `:227-232` cheap in the same pass.
- **Tests:** a unit test that the hoisted values recompute on a workspace switch.
- **Acceptance:** typing ten characters in Quick Capture must produce the same field state as before
  (a behaviour-preservation check), and `Self._printChanges()` in a debug build must no longer report
  the two filters re-running per keystroke. **The `@State` split half is deferred — see below.**

### Task 41: Minor sweep (B2)

- **Closes:** L2M-07 (minor), L2M-10 (minor), L2M-11 (minor).
- **Files and sites:** entrances that scale up from near-nothing —
  `AppShellView.swift:669` (`scaleEffect(isVisible ? 1 : 0.25)`), `InspirationCaptureViews.swift:21`
  and `:27` (`0.25` and its mirror), `DesignTokens.swift:1204` (`0.6` on every task checkbox) — all
  take `AgentMotion.entranceScale` (0.94) with `opacity` doing the rest; the `.blur(radius: 4)`
  crossfade at `InspirationCaptureViews.swift:22, 28` stays, capped where it is. Tasks
  double-animates its collection change: `TasksView.swift:612-617` is a `TabView` with
  `.tabViewStyle(.page)` running the system paging animation on `$collection` while `:668-680` also
  declares `.animation(… value: collection)` — drop the outer `.animation` on the phone branch and
  keep `AgentMotion.reveal` on the Catalyst `.transition(.opacity)`. Onboarding's step transition
  (`OnboardingView.swift:158`, `:1225-1229`) is a pure `.move` with no `.combined(with: .opacity)` and
  no Reduce Motion branch, while its mutation at `:1363-1369` **is** gated — the two halves disagree;
  route it through `AgentMotion.transition` driven by `AgentMotion.move`.
- **Shared thing reused:** `AgentMotion`.
- **Tests:** covered by Task 31's lint.
- **Acceptance:** phone recordings of the walkthrough card appearing, an inspiration processing
  crossfade, a task checkbox, a Tasks collection change, and an onboarding step — light and dark,
  Reduce Motion off and on.

### Task 42: (after H1: AUTH-01) Profile the core journeys on Chey's iPhone, before and after

- **Closes:** the contract's success criterion "no hang above Instruments' hang threshold on Chey's
  iPhone in the core journeys", which is **currently unmeasurable** — `xctrace record` was run twice on
  this machine, created the `.trace` directory, wrote 52 KB and hung both times. There is no
  top-app-frames table in this pass.
- **Blocked on:** AUTH-01. Do not start before H1.
- **What it settles:** L2H-01 … L2H-06 at real data volume; **L2H-07 re-escalates to major on this
  gate** and the deferred `@State` split below becomes a task; L2M-01 / L2M-02 in battery and thermal
  terms; L2M-03's and L2M-09's feel; and `CyThinkingMark` at 120 Hz, whose `TimelineView(.animation)`
  has no `minimumInterval` so its ProMotion cost is unmeasured (Task 31 throttles it blind).
- **Method:** Instruments Time Profiler and the SwiftUI template on device, over the five core
  journeys, once before B2 lands and once after. Record `View Body` counts for Quick Capture typing.
- **Acceptance:** both traces attached, with the hang-threshold verdict stated per journey.

### Deferred (B2)

- **L2H-07's second half — splitting `QuickCaptureView`'s 46 `@State` properties into per-kind
  `@Observable` models or child views.** Task 40 ships the cheap, certain half. The split is a large
  structural change to a 2,374-line view whose only justification today is a code shape; the lane
  itself says "this finding rests on the code, not on a timing", and the contract's criterion is
  "heaviness causes are measured before and after, not guessed". **Reason: it needs the device
  measurement from Task 42 to size it and to prove it worked. It re-enters as a task the moment
  AUTH-01's before-trace shows a per-keystroke cost.**

---

## B3 · Cohesion and flows

Two B3-batched findings are duplicates the skeptic collapsed and are closed elsewhere: **L3-11**
(Creator Session) by Task 74, and **L3-12** (`TodayView`) by Task 61. Their page-purpose value is
carried into the decision packet, not lost.

### Task 43: Three fixtures, so the flow findings can be verified

- **Closes:** nothing directly; it is the precondition for the acceptance checks of Tasks 44–46 and
  50. Three of L3's findings could not be reproduced end to end this pass, and the lane named exactly
  what was missing.
- **Files and sites:** `ios/AgentCy/Preview/PreviewData.swift` and `ios/AgentCy/App/AgentCyApp.swift:13-24`
  — add `-agentCyPreviewPersistentData`, which seeds the same fixture into an **on-disk** container.
  Today `-agentCyPreviewData` builds an in-memory container (`AgentCyApp.swift:15-22`), so no fixture
  launch can demonstrate relaunch survival at all. Add `-agentCyPreviewMCPQueue <type>`, seeding one
  pending `MCPBridgeChangeRequest` so flow 5 is testable. Add `-agentCyPreviewCyThread proposedPost`,
  seeding a Cy thread whose message carries a proposed post action. All three go inside the existing
  `#if DEBUG` guard and follow the shape Task 69 makes uniform.
- **Shared thing introduced:** the persistent fixture container. (Chey's alternative — handing over a
  live invitation code — is in the decision packet; the fixture is the cheaper path and does not spend
  an invite.)
- **Tests:** an XCUITest that launches with `-agentCyPreviewPersistentData`, writes a draft,
  terminates, relaunches and finds it — the driver L3 wrote lived in a session scratchpad and is not
  re-runnable; this one lands in `ios/AgentCyUITests`.
- **Acceptance:** each flag launches the app into the stated state on the simulator, captured.

### Task 44: The Ask Cy sheet has a close control on iPhone

- **Closes:** L3-01 (blocker).
- **Files and sites:** `ios/AgentCy/Views/Cy/AskCyView.swift:1274-1303` — the entire
  `showsCloseButton` block sits inside `#if targetEnvironment(macCatalyst)`, so the parameter
  (`:585-588`) is inert on iOS, and `AppShellView.swift:183` (`case .askCy: AskCyView()`) does not
  pass it anyway. Move the control out of the `#if`; pass `showsCloseButton: true` at
  `AppShellView.swift:183`; keep `DesktopAppShellView.swift:75` working. Use
  `AgentToolbarIconButton(title: "Close", icon: .close)` so it joins the family Task 4 unified rather
  than adding a twelfth.
- **Shared thing reused:** the glass icon control from Task 4.
- **Tests:** an XCUITest asserting an element labelled "Close" exists in the sheet's accessibility
  tree on phone — today a case-insensitive grep for "close" over
  `evidence/flows/L3-B1-tree-askcy-sheet.txt` returns nothing.
- **Acceptance:** phone light and dark of `ask-cy-sheet`, with the accessibility tree attached.
  Compose with Task 45: today a 4-second poller raises this modal over the creator's work, it shows a
  review queue instead of Cy, and it has no visible way out.

### Task 45: A pending MCP request no longer replaces the Cy conversation on iPhone

- **Closes:** L3-02 (blocker).
- **Files and sites:** `ios/AgentCy/Views/Cy/AskCyView.swift:649-659` — drop the `#if
  targetEnvironment(macCatalyst)` so `conversationContent` renders on both, and
  `:2153-2161`, where `showsConversation` returns `pendingReviews.isEmpty && !showReviewCompletion`
  on non-Catalyst and thereby gates the composer at `:669`. Make `desktopReviewBanner` (`:2165+`)
  unconditional and rename it; the queue is surfaced as a banner above the composer that opens the
  review deliberately. The code comment at `:652-654` records that this exact defect was already
  found and fixed — for the internal form factor only.
- **Shared thing reused:** the existing banner component.
- **Tests:** a unit test over `showsConversation` asserting it is true with a non-empty queue; an
  XCUITest with `-agentCyPreviewMCPQueue` (Task 43) asserting the composer is present.
- **Acceptance:** phone light and dark with a pending request queued: the conversation and composer
  must both be visible, with the banner above them. Desktop light and dark unchanged.

### Task 46: Every draft survives being backgrounded

- **Closes:** L3-03 (blocker — data is at risk, and this is the contract's "the five core flows
  complete and survive relaunch").
- **Files and sites:** `grep -rn "scenePhase" ios/AgentCy` returns **seven** reaction sites (five
  `.onChange`, two `.task(id:)`), not six, and every `.onChange` body begins
  `guard phase == .active else { return }`. **There is no `.background` handler anywhere in the app.**
  Unsaved state is written only in `onDisappear`, which backgrounding and termination do not call:
  `QuickCaptureView.swift:447-453` (`updateSavedIdeaFromForm` → `finalizeQuickPostDraft` →
  `preserveUnfinishedDrafts`), `ResumablePostEditorView.swift:409-417` (`persistChanges`),
  `WeeklyFocusView.swift:532` (`flushPendingDetailsSave`), and `PostProposalReviewView` has no exit
  persistence at all (Task 49). Add one `.onChange(of: scenePhase)` at `AgentCyApp.swift:118-132`
  that also handles `.background` / `.inactive` by broadcasting `.agentCyShouldFlushDrafts`, and have
  each draft-owning view flush on it with the closure it already runs in `onDisappear`:
  `QuickCaptureView`, `ResumablePostEditorView`, `PostProposalReviewView`, `WeeklyFocusView`,
  `VoiceSparkView.swift:386-390`, `DevelopBriefView` (composer text).
- **Shared thing introduced:** the flush notification and one `agentFlushesDraftsOnBackground(_:)`
  view modifier, so a new draft surface opts in with one line.
- **Tests:** a unit test per surface that the flush closure persists; an XCUITest with
  `-agentCyPreviewPersistentData` (Task 43) that types, backgrounds, terminates, relaunches, and
  finds the text.
- **Acceptance:** phone — for each of the five draft surfaces, type, background the app, kill it from
  the app switcher, relaunch, and screenshot the recovered draft. Repeat on desktop for the two that
  exist there.

### Task 47: A shared link is acknowledged on iPhone, and visible on desktop

- **Closes:** L3-04 (blocker — one of the PRD's three ideation paths, `PRD.md:54`, producing no
  visible result on the shipping platform).
- **Files and sites:** the phone shell passes `presentsImportedSource: false` at both call sites
  (`AppShellView.swift:224-231`, `:239-245`) while the desktop takes the default `true`
  (`DesktopAppShellView.swift:142`, `:147`), which is what `AppModel.swift:1112-1119` gates — it
  selects the Idea Bank tab and opens `inspiration-review`. The import succeeds either way; the
  creator is simply never told. It compounds on desktop, where `IdeaBankView.swift:253-255`
  (`#if !targetEnvironment(macCatalyst)`) compiles the inspiration list out, so the auto-opened
  review is the only place a desktop creator ever sees it. Two exact mirror-image mistakes. On phone,
  either present `inspiration-review` on import or post an `activity-center` entry plus a badge and
  land the creator in `idea-bank`; on desktop, delete the `#if` so the list exists on both.
- **Shared thing reused:** `NotificationActivityCenterView` if the badge route is chosen.
- **Tests:** a unit test over `importPendingInspiration` asserting a visible outcome is produced on
  both form factors.
- **Acceptance:** phone light and dark — share an Instagram link from Safari, return to the app, and
  screenshot what the creator sees. Desktop light and dark — the same, plus the Idea Bank's
  inspiration list now present.

### Task 48: Quick Add swaps in place instead of stacking a second sheet

- **Closes:** L3-05 (major).
- **Files and sites:** `ios/AgentCy/Views/Capture/CreationHubView.swift:18-52` — the desktop branch
  (`:23-24`) swaps content in place; the phone branch (`:38`) stacks `QuickCaptureView()` as a second
  sheet on the first. With `onExit == nil`, `QuickCaptureView.swift:373-380` picks the "Close" / X
  branch instead of "Back to Quick Add" / chevron, so the control says "close the app's capture" and
  actually returns to the Quick Add menu, and leaving takes two dismissals. Collapse both branches to
  one `Group { if showLivePost … else if showQuickCapture … }` passing `onExit: returnToCreationHub`;
  the three nested sheets at `:38`, `:42`, `:48` go with it.
- **Shared thing reused:** `returnToCreationHub` (`:294-297`).
- **Tests:** the existing probe shape — assert `Back to Quick Add` is **present** on phone (it
  asserts absent today) and that only one `Close` element exists in the window; the tree at
  `evidence/flows/L3-A2-tree-quick-capture-nested.txt` currently shows two live `Close` buttons with
  a `Sheet Grabber` between them.
- **Acceptance:** phone light and dark of `creation-hub` → `quick-capture`, with the accessibility
  tree attached; one dismissal must leave.

### Task 49: Closing the post review keeps the creator's edits

- **Closes:** L3-06 (major).
- **Files and sites:** `ios/AgentCy/Views/Brief/PostProposalReviewView.swift:167-169` — the toolbar X
  calls `dismiss()` with no persistence, while `:157-159`'s "Discard post" opens a confirmation. Every
  field binds to `@State private var proposal` (`:9`, seeded `:20-30`), and the stored
  `PendingBriefProposal` still holds the pre-edit payload (`AppModel.swift:2584-2598`), so reopening
  Build with Cy re-presents the original text. The safe-looking control destroys more than the one
  labelled destructive. Preferred fix: persist the edited proposal back over `PendingBriefProposal` on
  dismiss, so the review is resumable like every other draft; failing that, route the X through
  `confirmDiscard` when the proposal differs from its seed.
- **Shared thing reused:** Task 46's flush modifier, which this surface also needs (it has no exit
  persistence at all today).
- **Tests:** a unit test asserting the stored proposal equals the edited one after dismiss.
- **Acceptance:** phone and desktop, light and dark — edit, close with the X, reopen; the edit must
  be there.

### Task 50: The "Create this post" chip cannot fire twice

- **Closes:** L3-07 (major).
- **Files and sites:** `ios/AgentCy/Views/Cy/AskCyView.swift:570`
  (`@State private var sentToPostMessageIDs: Set<UUID>`), `:1659`, `:1673`, `:2338-2343`, `:2391-2430`,
  and `AppModel.createPostDraftFromCyResponse` (`:1547-1577`), plus the model. The guard is
  in-memory, so after a relaunch or a workspace switch the chip resets to "Create this post" and the
  creator gets a duplicate brief and output from one Cy answer. The sibling **task** chip on the same
  message already does this correctly with a persistent query (`:2352-2353`,
  `tasks.contains { $0.sourceConversationMessageID == message.id }`). Record the originating message
  on `CreativeBrief` — a `sourceConversationMessageID`, mirroring `CreatorTask` — and derive
  `alreadyCreated` from `briefs.contains { … }`.
- **Shared thing reused:** `CyPostCreationPolicy`, repointed at the persistent test.
- **Tests:** a unit test over `CyPostCreationPolicy.canCreate` with a persisted brief; an XCUITest
  with `-agentCyPreviewCyThread proposedPost` (Task 43) that taps, relaunches, and asserts the chip
  still reads "Post created".
- **Acceptance:** phone and desktop — tap the chip, relaunch, screenshot the chip's label.

### Task 51: A failed Cy turn can be retried, and gives back what was typed

- **Closes:** L3-08 (major).
- **Files and sites:** `ios/AgentCy/Views/Cy/AskCyView.swift:2269-2331` — `send()` clears the composer
  (`:2280`) and commits the turn (`:2287-2289`, incrementing `thread.turnCount` and saving) before the
  request starts; on failure `askCy` returns `nil` (`AppModel.swift:3877-3882`) with nothing inserted
  and nothing restored, and `stopSending()` (`:2324-2331`) drops a late reply at `:2302`.
  `grep -n "Try again\|Retry\|retry\|resend" AskCyView.swift` returns nothing. Mark the creator
  message unanswered on failure or cancellation, render a "Try again" affordance on it that re-sends
  without spending a second turn, restore `prompt` on failure — the pattern
  `DevelopBriefView.swift:494-496` already uses — and do not increment `thread.turnCount` until a
  reply is committed.
- **Shared thing introduced:** one unanswered-turn state on `ConversationMessage`, usable by
  `DevelopBriefView` too.
- **Tests:** a unit test that a failed turn leaves `turnCount` unchanged and `prompt` restored.
- **Acceptance:** phone and desktop, light and dark — put the device in airplane mode, send, and
  screenshot; the typed text must be back in the composer and the message must offer a retry.

### Task 52: Errors are visible from inside sheets

- **Closes:** L3-09 (major).
- **Files and sites:** `grep -rn "notice != nil"` returns exactly two presenters —
  `AppShellView.swift:208-214` and `DesktopAppShellView.swift:100-106` — against **204** `notice = .`
  write sites, many inside sheet-presented surfaces where the shell's `.alert` is covered:
  `VoiceSparkView.swift:924`, `ResumablePostEditorView.swift:2475-2478`,
  `AgendaView.swift:4086-4098` (`post-reschedule`), `AppModel.swift:2503-2521` (five validation
  notices raised from `post-proposal-review`). Add an `.agentNotice()` modifier applied at every sheet
  root, or a scene-level overlay window that follows the topmost presentation. For errors that are
  about the form in front of the creator, adopt the inline pattern `EpisodeSlotActionsView.perform`
  (`AgendaView.swift:2779-2800`) already gets right, including its rollback. Sheet roots to cover:
  `QuickCaptureView`, `VoiceSparkView`, `ResumablePostEditorView`, `PostProposalReviewView`,
  `PostRescheduleSheet`, `MCPBridgeRequestReviewView`, `InspirationReviewView`.
- **Shared thing introduced:** `agentNotice()`.
- **Tests:** a unit test that the presenter resolves to the topmost presentation; a lint rule that any
  file writing `notice = .` also applies `agentNotice()` or renders inline.
- **Acceptance:** phone and desktop, light and dark — force one error per sheet root (five sheets) and
  screenshot each; the message must be readable without dismissing the sheet.

### Task 53: Capture paths land somewhere

- **Closes:** L3-10 (major).
- **Files and sites:** `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1731-1781` — `saveIdea()`,
  the post path and the "Find three ideas" path all end in `finishCapture()` (`:1742-1748`), which is
  a dismissal and nothing else: no notice, no navigation, no selection change. Three of the four
  capture paths therefore end in the Quick Add menu with no confirmation and no route to what was
  made. Voice Spark is the one that resolves properly — `VoiceSparkView.swift:955-962` sets
  `selectedTab`, `widgetBriefID` and `widgetBriefOpensEditor` before dismissing. Give
  `finishCapture()` a destination on the same pattern: dismiss the whole capture stack (not just the
  inner sheet — Task 48), then either land on the created object or show a one-line confirmation
  naming where it went. `CreationHubView.swift:294-297` (`returnToCreationHub`) changes with it.
- **Shared thing introduced:** one capture-completion policy, so all four paths resolve the same way.
- **Tests:** a unit test per path asserting a destination or a notice is produced.
- **Acceptance:** phone light and dark — save an idea, a task, a post and run "Find three ideas";
  screenshot where each lands. Desktop light and dark for the two that exist there.

### Task 54: "Deny" on an MCP change request asks first

- **Closes:** L3-13 (major).
- **Files and sites:** `ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift:1113-1116` — a bare
  `Button("Deny") { perform { try decline(approvalRequest, nil) } }`, where `perform` (`:1447-1454`)
  runs and dismisses. No confirmation, no undo — while the app confirms deleting a task
  (`TasksView.swift:2120`), deleting an idea (`IdeaBankView.swift:279`), archiving a series
  (`ResumablePostEditorView.swift:3375`), archiving a Cy conversation
  (`DevelopBriefView.swift:155-163`) and even skipping an empty episode slot
  (`AgendaView.swift:2691-2702`). The sibling revision path is correctly gated behind
  `settings-mcp-revision-note` (`:1110-1112`). Put Deny behind a `confirmationDialog` matching the
  app's other destructive actions, or replace it with the episode path's "send back with a note" so
  the rejection is recoverable from the bridge side.
- **Shared thing reused:** the app's existing destructive-confirmation shape.
- **Tests:** a unit test that `decline` is not reachable without confirmation.
- **Acceptance:** phone and desktop, light and dark, of `ask-cy-review-request` with the dialog open.

### Task 55: One cleanup contract for abandoned post drafts

- **Closes:** L3-14 (major).
- **Files and sites:** `AppModel.createPostDraftFromCyResponse` (`:1547-1577`) inserts the
  `CreativeBrief` and `PlatformOutput` and saves immediately; the editor is then shown in a sheet
  whose Close simply nils the route (`AskCyView.swift:766-793`, `:777-778`). There is no equivalent of
  `QuickCaptureView.finalizeQuickPostDraft()` (`:1867-1906`), which deletes an empty brief and output
  when the creator backs out — so the two "create a post from nothing" flows have opposite cleanup
  contracts, and changing your mind after the Cy chip leaves an orphan draft in Idea Bank and in
  Home's "Continue working on…". Extract the emptiness test into a shared `PostDraftCleanupPolicy` and
  run it on dismissal of the Cy editor sheet and on `MCPBridgeRequestReviewView`'s scratch-model path
  (`MCPBridgeSettingsView.swift:761-766`, whose comment already documents the same concern).
- **Shared thing introduced:** `PostDraftCleanupPolicy`.
- **Tests:** unit tests over the policy for empty, partially-filled and complete drafts.
- **Acceptance:** phone and desktop — tap the Cy chip, close without editing, and screenshot Idea Bank
  and Home; no orphan may appear.

### Task 56: Deep links reset the stack and report a miss

- **Closes:** L3-15 (major), L3-16 (major).
- **Files and sites:** `ios/AgentCy/App/RootView.swift:259-296` (`openWidgetDestination`) and
  `:307-336` (`handlePendingNotificationRoute`) clear `widgetAgendaDay` / `widgetBriefID` and set
  `selectedTab`, but neither bumps `requestedPlanNavigationReset`, which is what `routeToWeeklyAgenda`
  (`AppModel.swift:343-348`) does and what `PlanView` is keyed on (`AppShellView.swift:67`). Tapping
  the Agenda widget while `plan-week` is three pushes deep therefore pushes `day-agenda` onto the
  stale stack. `openRequestedTaskIfNeeded` (`AppShellView.swift:404-409`) gets it right by resetting
  `tasksPath` first. Bump the reset at the top of both handlers. Separately,
  `AgendaView.swift:400-407`'s `onChange(of: appModel.widgetBriefID, initial: true)` guards on
  `activeBriefs.first(where:)` and returns **without clearing** `widgetBriefID` — and because
  `onChange` only fires on a change, the deep link is then lost forever and the stale id sits in the
  model. Mirror `IdeaBankView.openRequestedIdeaIfNeeded` (`:323-338`), which distinguishes `.missing`
  and says "This idea is no longer available in this workspace."
- **Shared thing reused:** `routeToWeeklyAgenda`; the Idea Bank miss pattern.
- **Tests:** unit tests over both handlers asserting the reset is bumped and that a missing brief id
  is cleared and produces a notice.
- **Acceptance:** phone — push three deep into Plan, tap the Agenda widget, screenshot the back
  stack; then tap a widget for an archived brief and screenshot the notice. Desktop for the same two.

### Task 57: One vocabulary in the code — `AppTab.today` becomes `.plan`

- **Closes:** L3-17's code half (minor). **The `docs/PRD.md:76-77` edit is not in this task** — the
  contract reserves anything that changes the PRD for Chey; it is DEC-11 and Task 59.
- **Files and sites:** `ios/AgentCy/Models/DomainTypes.swift:1350-1377` — `case today` renders the
  title "Plan" (`:1362`), so every routing call site reads backwards: `AppModel.swift:347, 355, 362`,
  `VoiceSparkView.swift:958`, `RootView.swift:270, 283, 313, 318, 328`, plus every `case .today` in
  the shells. Rename to `.plan` and update all of them.
- **Shared thing reused:** none; a pure rename.
- **Tests:** the existing `AppTab.allCases` assertions (`AgentCyTests/SocialGridTests.swift:7-8`)
  updated.
- **Acceptance:** the app builds on both schemes, all tests pass, and a reviewer greps for
  `selectedTab = .today` and finds nothing. No visible change; no screenshots.

### Task 58: Minor sweep (B3)

- **Closes:** L3-18 (minor), L3-19 (minor), L3-20 (minor), L3-22 (minor).
- **Files and sites:** delete `PlanNavigationRoute.dailyFocusDetail` and its `navigationDestination`
  arm (`PlanView.swift:9-12`, `:58-65`) — its only append is inside `#if DEBUG` at
  `AppShellView.swift:230-236`, beside a live production path (`plan-week` → week row → `day-agenda`
  → Focus, `AgendaView.swift:3268-3271`); point the fixture at the live route so the debug path
  exercises production code, and update `AgentCyTests/SocialGridTests.swift:7-8`. Push
  `PostOutputDetailView(brief:output:)` from `SocialGridView.swift:928` instead of
  `ScheduledPostDetailView` directly, so the grid stops being the one list of fourteen that bypasses
  `PostOutputDetailPolicy` and shows a different page for the same post. Give the Tasks tab's two add
  actions one presentation owner — `TasksView.swift:1204-1210` raises a shell-owned sheet while
  `:623-627` raises a view-owned one, so they behave differently under `dismissGlobalPresentation()`,
  workspace switches (`AppModel.swift:310-318`) and deep links; route "add post task" through the
  shell's `.quickCapture` with `quickCaptureStartsWithTask`, which `QuickCaptureView.swift:475-489`
  already supports. Remove the `case .creatorSession: break` at `RootView.swift:294-295` and the
  `creatorSession` destination from `AgentCyDeepLink` **if DEC-05 removes the family** (Task 74);
  otherwise route it to `home` with a notice so a Live Activity tap is not swallowed silently.
- **Tests:** the updated `allCases` assertion; a unit test that a scheduled output with a
  `.developing` brief opens the same page from the grid as from every other list.
- **Acceptance:** phone light of `feed-grid` → a developing post (must open the draft editor, as it
  does from every other list) and of both Tasks add buttons. Desktop light of the same.

### Task 59: (after H1: DEC-11) Correct the PRD's vocabulary

- **Closes:** L3-17's document half, and the two other PRD-facing recommendations —
  APPLE-14's tab count and `page-purpose.md` §5's brand-cabinet deferral.
- **Blocked on:** DEC-11. Do not start before H1.
- **Files and sites:** `docs/PRD.md:76-77` ("Today is the warm daily launch view" ships as Home;
  "Agenda" ships as Plan), plus the navigation list's *Platforms* entry, which has no tab and
  correctly ships as a section inside `resumable-post-editor`.
- **Acceptance:** a reviewer reads `PRD.md`'s navigation section against `AppTab.allCases` and the
  shipped tab titles and finds one vocabulary.

### Deferred (B3)

None. Every standing B3 finding is in a task above, in Task 61 or Task 74 (the two duplicates), or in
Task 59 behind DEC-11.

---

## B4 · Dead code

L4's method is deliberately conservative: occurrences in comments and string literals count as
references, so the census under-reports rather than over-reports. Every deletion below is
"verify by build after removal", and the batch removes roughly 3,500 lines — which is why Task 60
comes first.

### Task 60: (after H1: AUTH-03) Run Periphery over the three targets before deleting anything

- **Closes:** nothing; it is the safety gate for Tasks 61–68.
- **Blocked on:** AUTH-03 (`brew install peripheryapp/periphery/periphery`). Do not start before H1.
- **Files and sites:** run Periphery against the iOS, Catalyst and widget schemes; diff its result
  against `docs/refinement/evidence/L4/unreferenced-symbols.md` (742 zero-reference declarations, 73
  outside the test target). Anything Periphery calls live that L4 called dead is a false positive
  removed from the deletion list, and the reverse is recorded as a follow-up.
- **Acceptance:** the reconciled deletion list is checked in beside the evidence, and each of Tasks
  61–68 names the symbols it deletes from that list.

### Task 61: Delete `TodayView` and `PlanHeader`

- **Closes:** L4-02 (major); L3-12 and L2H-08 are the same fact filed twice more — L2H-08 is
  **rejected as a heaviness finding** (an unreferenced file that never runs costs nothing at runtime)
  and L3-12's value is the page-purpose answer, which is carried into DEC-06's context.
- **Files and sites:** first move `TodayOutputSection` and `TodayOutputPresentation`
  (`TodayView.swift:445`, `:451`, ~20 lines) into `ios/AgentCy/Services/` beside the other
  presentation policies — `AgendaView.swift:1387` calls `TodayOutputPresentation.section`, so deleting
  the file naively breaks the build. Then delete `ios/AgentCy/Views/Today/TodayView.swift` (443 lines,
  ten whole-table `@Query`s at `:4-18`, its own copy of `scoped(_:)` at `:29`, a focus section, three
  post sections, two task collections, a quick-capture sheet and a confirmation dialog — presented
  from nowhere) and `PlanHeader` with its `where Actions == EmptyView` extension
  (`PlanView.swift:550-620`), whose only caller is the dead view. Delete the empty
  `ios/AgentCy/Views/Spark/` group. Re-run `xcodegen generate`.
- **Tests:** the full suite on all three schemes.
- **Acceptance:** ~510 lines removed; all three schemes build clean; `grep -rn "TodayView\|PlanHeader"
  ios --include='*.swift'` returns nothing.

### Task 62: Delete nine never-called `AppModel` methods

- **Closes:** L4-03 (major).
- **Files and sites:** `ios/AgentCy/ViewModels/AppModel.swift` — `voiceExampleDrafts(context:)`
  (`:659-672`), `isVoiceProfileStale(_:context:)` (`:838-843`),
  `noteManualDevelopment(of:context:)` (`:2912-2916`), `createRepurposedSpark(from:context:)`
  (`:3846-3848`), `proposedPillars(context:)` (`:3885-3898`), `acceptPillar(_:context:)`
  (`:3900-3914`), `ensureCurrentWeek(context:)` (`:3936-3938`), `saveWeekToTemplate(_:context:)`
  (`:3940-3953`), `addPublishingOutput(...)` (`:4320-4351`) — 106 lines, each with exactly one
  repo-wide occurrence, its own `func` line. `AppModel` is a concrete `@Observable` class and no
  protocol it adopts declares them.
- **Tests:** the full suite; the compile is the cheapest proof nothing reaches them through a key path.
- **Acceptance:** all three schemes build; the nine names return zero hits.

### Task 63: Delete nine unreferenced model and service symbols

- **Closes:** L4-05 (minor — it shares its verification with Tasks 61–62, so it lands here).
- **Files and sites:** `RecurringPostSchedule.swift:939` (`enum RecurringPostMaterializer`, a whole
  second unwired materializer inside the live recurrence engine) and `:940`
  (`createFutureOccurrences`), `:815` (`PostSeriesDeletionPolicy.isPartOfSeries`);
  `VoiceSparkRecordingStore.swift:154` (`updateTranscript`); `LocalCyService.swift:152`
  (`LocalCyAIClient.isRemoteAvailable`) and `:322` (`removeRequest(requestID:)`, `private`, so
  conclusively unreachable); `CreatorFacingErrorMapper.swift:10` (`postNotFound`);
  `DomainTypes.swift:1341` (`SubscriptionAccess.canEditExisting`, a `Bool { true }` nothing reads);
  `PersistenceModels.swift:1250` (`Pillar.isBranch`, computed, not schema — so not a migration).
  **Before deleting `LocalCyAIClient.removeRequest`, confirm against Task 82** that queued local-AI
  requests are cleaned up some other way; if they are not, this is a leak whose fix is already
  written and should be called rather than deleted.
- **Tests:** the full suite.
- **Acceptance:** all three schemes build; the nine names return zero hits; the `removeRequest`
  question is answered in writing in the review.

### Task 64: Delete ten unreferenced members inside view files

- **Closes:** L4-06 (minor).
- **Files and sites:** `QuickCaptureView.swift:988` (`cyIdeaPrompt`), `:1539` (`lockedTaskValue`),
  `:1691` (`headerTitle`), `:1700` (`headerSubtitle`); `CreatorSessionView.swift:1340`
  (`fullScreenTimerContentWidth` — disappears with Task 74 if that file goes);
  `PillarsView.swift:2298` (`PillarMetrics`) and `:2313` (`postedCount`, which go together — the
  struct has no reachable members left); `AgendaView.swift:2254`
  (`AgendaOutputState.needsRescheduling`); `MCPDesktopReviewView.swift:666`
  (`editingPayloadBinding`); `DesktopAppShellView.swift:1559` (`openCy()`, a dead navigation action).
  Every one is `private` or a `private struct`, so "no other occurrence of the name" is conclusive.
- **Tests:** the full suite.
- **Acceptance:** all three schemes build.

### Task 65: Delete three unreferenced design-token symbols

- **Closes:** L4-04 (minor).
- **Files and sites:** `DesignTokens.swift:1255` (`AgentDesktopPrimaryActionButtonStyle`, a whole
  unused button style and the only "primary action" style in the token file), `:33`
  (`AgentLayout.sectionHeadingSpacing`), `:632` (`Font.agentBriefTitle`, the only one of the sixteen
  semantic font tokens with zero call sites — the other fifteen carry 921 `.font(.agent…)` sites).
  **Decision taken here rather than deferred:** delete all three. Task 8 mapped 28 pt onto
  `.agentBriefTitle`, so if that mapping is in the tree, keep the token and delete only the other two
  — the reviewer checks Task 8's diff first. Desktop primary actions use `AgentPrimaryButtonStyle`;
  there is no desktop-only primary role in the design.
- **Tests:** the full suite; Task 1's lint.
- **Acceptance:** all three schemes build; the token file is one style and two constants shorter.

### Task 66: Delete seven unreferenced imagesets and five dead `AgentIcon` cases

- **Closes:** L4-07 (minor).
- **Files and sites:** `agent-icon-feed`, `agent-icon-move-vertical`, `agent-icon-messages`,
  `agent-icon-send`, `agent-icon-camera`, `agent-icon-music`, `agent-icon-radio-selected` in
  `ios/AgentCy/Resources/Assets.xcassets`, and the cases `messages`, `send`, `camera`, `music`,
  `radioSelected` in `AgentIcon` (`DesignTokens.swift:79-215`). **`radioSelected` is the exception:**
  `radioEmpty` is used but its selected partner is not, so some radio control draws its selected state
  another way — check that control against Task 4's work first, and adopt `radioSelected` there rather
  than deleting it if it is the right glyph. `Assets.xcassets` is a build input of `AgentCy`,
  `AgentCyMac` and `AgentCyWidgets` (`ios/project.yml:204-206`), so re-run `xcodegen generate` and
  build all three.
- **Tests:** all three schemes build; a test that every `AgentIcon` raw value resolves to an imageset.
- **Acceptance:** the widget extension shrinks too; the radio-control question is answered in writing.

### Task 67: Delete all ten colorsets

- **Closes:** L4-08 (minor).
- **Files and sites:** `AccentColor`, `ActionAccent`, `AgentBorder`, `AgentCanvas`,
  `AgentDestructive`, `AgentSecondary`, `AgentSuccess`, `AgentSurface`, `AgentText`, `CyAccent` in
  `ios/AgentCy/Resources/Assets.xcassets`. The project sets
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: NO` (`ios/project.yml:17-19`), so a
  colorset is reachable only through a string lookup and there is exactly one string asset lookup in
  the whole app — `Image("agent-icon-stop")`. `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` is set
  nowhere, so not even `AccentColor` is picked up by convention. Keep `AppIcon.appiconset`, which
  **is** referenced through `ASSETCATALOG_COMPILER_APPICON_NAME`. Re-run `xcodegen generate`.
- **Tests:** all three schemes build; light and dark launch screenshots to confirm nothing lost a
  colour.
- **Acceptance:** beyond the bytes, the catalog stops showing a colour system that no longer matches
  `DesignTokens.swift`.

### Task 68: Delete the four dead `OnboardingDraft` voice fields

- **Closes:** L4-09(a) (minor).
- **Files and sites:** `ios/AgentCy/Models/DomainTypes.swift:1669-1672` — `voiceSummary`,
  `voiceTraits`, `voiceAvoid`, `voiceProfilePayloadJSON`, each with one repo-wide hit. The comment at
  `:1664-1665` justifies them by saying saved drafts must "continue to decode", but `OnboardingDraft`
  is `struct OnboardingDraft: Equatable, Sendable` (`:1653`) — not `@Model`, not `Codable` — so
  nothing persists it and that reason no longer holds. They pair with `voiceExampleDrafts` and
  `isVoiceProfileStale` from Task 62: one removed onboarding step, cut in two places.
- **Tests:** the full suite.
- **Acceptance:** all three schemes build. **(b) and (c) of L4-09 are deferred — see below.**

### Task 69: Preview fixtures stop shipping in Release

- **Closes:** L4-10 (minor).
- **Files and sites:** wrap `ios/AgentCy/Preview/PreviewData.swift` (485 lines, opening at line 6 with
  a bare `enum PreviewData {` and containing no `#if DEBUG` anywhere) in one file-level
  `#if DEBUG` / `#endif`. `ios/project.yml:28-31` adds the whole `AgentCy` directory to the `AgentCy`
  and `AgentCyMac` targets excluding only the entitlements file, so all 485 lines of seeded creator
  profiles, pillars, briefs and tasks compile into Release on both form factors. Move the three
  unguarded `PlanRuntimeFixture` bodies (`PlanView.swift:14-52`: `requestsDailyFocusDetail`,
  `requestsPostSearch`, `postSearchQuery`) into the `#if DEBUG … #else false #endif` shape their three
  siblings already use, so the guard is uniform inside the enum and the `#if DEBUG` at the three call
  sites (`AppShellView.swift:230-236`, `PlanView.swift:82-87`, `:425-430`) can go away. **No release
  behaviour changes today** — the defect is that the next caller added in release code silently gets a
  live fixture hook. Leave `PreviewCredentialStore` (`APIClient.swift:114`) where it is —
  `AgentCyTests` links the app target in Debug and needs it — and flag it to the security process so a
  fake credential store is never mistaken for the real one. Task 43's three new flags follow the same
  shape.
- **Tests:** the full suite; confirm the Release configuration of both schemes still compiles.
- **Acceptance:** a Release build of both schemes, plus `strings` over the archive confirming the
  fixture strings are gone.

### Task 70: One trim-a-string-to-nil helper

- **Closes:** L4-18 (minor).
- **Files and sites:** twelve private copies under four names, three files declaring one twice —
  `MCPBridgeSettingsView.swift:1426` and `:1805`, `SocialGridView.swift:323`, `AskCyView.swift:2000`,
  `CreativeService.swift:673` and `:1186`, `InspirationContentAnalysisService.swift:137`, `:197` and
  `:464`, `ShareViewController.swift:503`, `HomeDashboardView.swift:2633`,
  `CreatorSessionView.swift:1770`. **They are not equivalent, which is the actual risk:** `nilIfEmpty`
  / `nonEmpty` test `isEmpty` without trimming, while `nonempty` / `nilIfBlank` trim first, so `"   "`
  is a value in some code paths and nil in others. Add one
  `extension String { var trimmedOrNil: String? }` and one `firstTrimmedOrNil(_:)` in
  `ios/AgentCyShared/` — shared so the share extension can use it; that target compiles only three
  `AgentCyShared` files today, so add the new one to `ios/project.yml:243-246`. Delete all twelve.
  Where a call site genuinely wanted untrimmed semantics, make that explicit.
- **Tests:** unit tests over `""`, `"   "`, `"\n"`, `nil` and a real value.
- **Acceptance:** all three schemes build; the twelve declarations return zero hits.

### Task 71: One shared ISO8601 formatter

- **Closes:** L4-22 (minor).
- **Files and sites:** `ios/AgentCy/Services/ExportService.swift` constructs
  `ISO8601DateFormatter()` at **41 sites**, each inline inside a `map` closure over a model
  collection — so the allocations are per row, and a workspace with a few hundred tasks, posts and
  outputs constructs tens of thousands of formatters in one export. Six more inline allocations:
  `AgentCyApplicationDelegate.swift:55`, `PersistenceModels.swift:612` and `:625`,
  `MCPBridgeService.swift:2187` and `:2190`, `NotificationPlanning.swift:699`,
  `ReminderService.swift:288` and `:629`. Add one `static let iso8601 = ISO8601DateFormatter()` in
  `ios/AgentCyShared/` (formatters are thread-safe for formatting once configured) and use it at all
  49 sites.
- **Tests:** the existing export tests must produce byte-identical output.
- **Acceptance and before/after measurement:** export a workspace seeded with 500 tasks and 500 posts
  and time it before and after; this is the clearest allocation-in-a-loop in the codebase and belongs
  in Task 42's trace if export appears there.

### Task 72: Zero compiler warnings, then keep it that way

- **Closes:** L4-20 (minor).
- **Files and sites:** fourteen warnings across three schemes from three causes. Migrate both
  `copyCGImage(at:actualTime:)` sites — `InspirationContentAnalysisService.swift:362:43` and
  `InspirationShareMediaAnalyzer.swift:147:43` — to
  `generateCGImageAsynchronously(for:completionHandler:)`, and while there extract the shared
  thumbnail logic into `ios/AgentCyShared/` so the app and the share extension stop carrying two
  copies. **This is the more interesting half:** `copyCGImage` is a synchronous blocking frame decode
  on the inspiration-capture path, which is a plausible hang source — hand the before/after timing to
  Task 42. At `DesktopAppShellView.swift:714:9`, discard the `withTransaction` result explicitly or
  mark `AppModel.toggleTask` `@discardableResult` (the transaction does apply; the warning is
  cosmetic, but it fires only on Catalyst, which means that scheme is not built warning-clean as
  often). Update `ServiceTests.swift:961:22` to `init(windowScene:)`. Then add
  `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for Debug in `ios/project.yml`, or at minimum have CI fail on
  new warnings.
- **Tests:** three clean builds with zero warnings.
- **Acceptance:** the build logs, attached, beside `evidence/L4/build-warnings.md`.

### Task 73: `verify.sh` runs, and CI runs the same gate

- **Closes:** L4-12 (major). **Depends on AUTH-04** for the local half; the CI half lands regardless.
- **Files and sites:** `scripts/verify.sh:11-16` — line 13 is `pnpm install --frozen-lockfile` under
  `set -euo pipefail`, and neither `pnpm` nor `corepack` exists on this Mac, so lines 18-49
  (`xcodegen generate`, `xcodebuild build`, `xcodebuild test`) are unreachable locally; because line
  11 runs the typography check first, the only part that executed was the gate that always passed.
  Add a `corepack enable && corepack prepare pnpm@11.7.0 --activate` preflight, or a
  `command -v pnpm || { echo "run: corepack enable" >&2; exit 1; }` guard, so the script says what is
  missing instead of dying on "command not found". In `.github/workflows/ci.yml` (52 lines, invoking
  neither `verify.sh` nor `check_inter_typography.sh`): add
  `- run: ./scripts/check_inter_typography.sh` and `- run: ./scripts/check_design_review.sh` as the
  first steps of the `apps` job; add `- run: pnpm build` to the `workspace` job to match
  `verify.sh:16`; and replace the `sed`-scraped simulator at `ci.yml:42` — which takes whichever
  iPhone the runner image lists first and pins nothing, against an
  `IPHONEOS_DEPLOYMENT_TARGET: 26.0` — with `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  matching `verify.sh:6`.
- **Shared thing:** `verify.sh` and `ci.yml` become the same gate, which is the point of having both.
- **Tests:** a CI run on a branch that deliberately violates one lint rule must fail.
- **Acceptance:** `bash scripts/verify.sh` completes on this Mac; a red CI run is attached.

### Task 74: (after H1: DEC-05) Creator Session — remove it, or register and date it

- **Closes:** L4-01 (major), L3-11 (major, the same defect), L3-22 (minor, if the family goes).
- **Blocked on:** DEC-05. Do not start before H1.
- **Files and sites:** `ios/AgentCyShared/CreatorSessionActivity.swift:10-12`
  (`static let isEnabled = false`), and 2,520 lines behind it —
  `CreatorSessionView.swift` (1,782), `ActiveCreatorSessionFloatingTimer.swift` (104),
  `CreatorSessionActivity.swift` (451), `CreatorSessionLiveActivity.swift` (183). Seven statically
  false gates: `RootView.swift:176`, `AppModel.swift:370`, `AppShellView.swift:98` and `:174`,
  `DesktopAppShellView.swift:121` and `:134`, `ScheduledPostDetailView.swift:228`.
  `WidgetTests.swift:82` pins the off state. **And the flag could not simply be flipped:**
  `CreatorSessionActivityWidget` (`CreatorSessionLiveActivity.swift:85`) is absent from
  `AgentCyWidgetBundle.body` (`AgentCyWidgets.swift:233-249`, which lists twelve other widgets), while
  `CreatorSessionView.swift:173` calls `Activity.request(...)` — so the Live Activity would have no
  registered configuration to render. If DEC-05 removes it: delete the four files, the seven gates,
  `WidgetTests.swift:82`, `RootView.swift:176-181` and `:294-295`, `AppModel.swift:368-381`, and the
  `NSSupportsLiveActivities` plus `UIBackgroundModes: audio` entries in `ios/project.yml:87-90, 104`
  (keeping `remote-notification`, which CloudKit mirroring needs) — which also closes half of Task 101.
  If DEC-05 keeps it: register `CreatorSessionActivityWidget()` in the bundle now, and exclude the
  family explicitly from the design-consistency and dead-code censuses so it stops skewing them (it
  supplies four of the six `AgentCircularGlassIconButton` sites Task 4 migrates).
- **Tests:** all three schemes build; the widget bundle test updated either way.
- **Acceptance:** whichever branch DEC-05 chooses, executed completely — no half state.

### Task 75: (after H1: DEC-15) Get 26 GB of build output out of the iCloud-synced repo

- **Closes:** L4-23 (minor).
- **Blocked on:** DEC-15 — a device build lives in `ios/build-device` (285 MB) and may be installed on
  her phone.
- **Files and sites:** `ios/build/` (26 GB) and `ios/build-device/` (285 MB), both untracked and
  correctly ignored (`.gitignore:18-19`), so this is a tooling problem, not a repo-weight one: the
  repo is under `~/Documents`, which is iCloud-synced, and `briefs/_common.md` already warns that
  derived data inside the repo "is iCloud-synced and breaks signing". Delete both, mark the paths
  excluded from iCloud (`.nosync`, or the `com.apple.fileprovider.ignore#P` xattr), point the
  project's default derived-data location at `~/Library/Developer/Xcode/DerivedData`, and add a
  `README.md` note that in-repo builds break signing.
- **Acceptance:** `du -sh ios/build ios/build-device` returns nothing, and a fresh Xcode build lands
  outside the repo.

### Deferred (B4)

- **L4-21 — fifteen files over 2,000 lines, three over 4,000** (`ResumablePostEditorView.swift` 5,412;
  `DomainTests.swift` 5,273; `AppModel.swift` 4,990; `AgendaView.swift` 4,104; and eleven more,
  holding ~42% of the repo's 104,755 Swift lines). **Reason: minor, and none of it is required for
  beta. The lane's own recommendation is that no split share a commit with a behaviour change; B1–B3
  have already rewritten large parts of `DesignTokens.swift`, `PillarsView.swift`, `PlanView.swift`,
  `AppShellView.swift` and `AskCyView.swift`, so every split would now be a rebase conflict against
  work that is either in flight or freshly reviewed.** The per-file split proposals in
  `findings-codehealth.md` L4-21 are good and should be executed after the beta go, cheapest first
  (`AppModel.swift`'s extension split). Carried to the beta-readiness report.
- **L4-09(b) — `PendingWeekProposal.appliedAt`** (`PersistenceModels.swift:1466`), a stored SwiftData
  column never written and never read. **Reason: dropping a stored property from a CloudKit-mirrored
  `@Model` is a schema change, and `AgentCySchemaV1` is still at `Schema.Version(1, 0, 0)`
  (`:1834`) — not worth a migration before beta.** It is RISK-05 in the decision packet: either wire
  it into the proposal-apply path or drop it in a deliberate V2.
- **L4-09(c) — twelve decoded-but-unread wire fields** (`IdeaDirectionWire.whyItFits`,
  `SparkTurnResultWire.readyToCompose` / `.missingFields`,
  `SparkRecommendedNextStepWire.answerQuestion` / `.reviewWorkingState`,
  `ChatProposedActionKindWire.planWeek`, three `AIQuotaScopeWire` cases, three
  `MCPBridgeExternalPlanContext` fields). **Reason: the decoder needs the non-optional ones and the
  enum cases are values the server can legitimately send; deleting them would break decoding.** One is
  worth acting on rather than accepting — `whyItFits` is a "why this fits you" explanation the server
  computes for every idea direction and the app throws away; that is DEC-16.

---

## B5 · Security

L5 sent **no request to the deployed service** — verified: `probe-plan.md:3` states so, a grep for
`railway|agentcy.up|https://api.` across `evidence/security/` returns nothing, and every artefact is
locally produced. The production probe is AUTH-02 / Task 94. Fix ownership is marked **client**,
**server**, **bridge** or **docs**.

### Task 76: The app refuses to POST creator content to an arbitrary URL

- **Closes:** L5-01 (blocker). **client**
- **Files and sites:** `ios/AgentCy/Services/LocalCyService.swift:267-278` — `connectionConfig()`
  decodes `baseURL` from `cy-connection.json` in the creator-selected bridge folder and validates only
  `schemaVersion == 1` and `token.count >= 32`. `performDirect` (`:207`, `:245`) then POSTs
  `encoder.encode(envelope)` — the complete request-scoped creator context — to that URL with
  `Authorization: Bearer <token>`. No scheme, host, loopback or private-range check anywhere. The
  folder is normally `iCloud Drive/agent.cy MCP`, writable by anything on the creator's Mac and by any
  app granted that folder in Files. Require `http` only for `127.0.0.1`, `::1`, `localhost`, an
  RFC1918 / `fe80::` literal or a single-label `*.local` host; require `https` for anything else;
  reject a URL carrying a user, password, query or fragment. Mirror the check in
  `contracts/src/local-cy.ts:80` so the runtime and the schema agree. Refuse a `baseURL` whose host
  changed since the last successful handshake without an explicit re-confirmation in Settings > AI.
- **Tests:** a unit test table over accepted and rejected URLs, including
  `http://evil.example.com`, `http://127.0.0.1:49321`, `https://mac.local`, and a URL with embedded
  credentials.
- **Acceptance:** hand-edit `cy-connection.json` to a public `http://` host; the app must refuse and
  say so in Settings > AI, screenshotted on both form factors.

### Task 77: The published privacy statements become true

- **Closes:** L5-02 (blocker), L5-03 (blocker), and the doc half of L5-04. **docs**
- **Files and sites:** `docs/PRIVACY.md:11` says the Share Extension "makes no network request"; it
  makes two — `InspirationShareAPI.swift:112` POSTs to `/v1/inspiration/extract` and `:155` to
  `/v1/ai/inspiration/shape`, both authenticated with the installation credential from keychain access
  group `2S27MSM8G8.com.agentcy.shared`, and `InspirationShareMediaAnalyzer.swift:23` downloads video
  and thumbnail bytes from Instagram CDN hosts. `docs/ARCHITECTURE.md:35` says the extension "does not
  link SwiftData, AI, EventKit, notification, or CloudKit services" — also false.
  `docs/PRIVACY.md:23` says "The proxy does not fetch links"; `inspiration-extractor.ts:46-50` is
  `Promise.allSettled([fetchHtml(canonicalUrl), fetchHtml(embedUrl), fetchOEmbed(oEmbedUrl)])` — three
  fetches per shared post, from the proxy's IP, with a spoofed mobile Safari user agent. Rewrite both
  to describe what happens, naming the host allow-list (`instagram.com`, `www.instagram.com`,
  `m.instagram.com`; `*.cdninstagram.com`, `*.fbcdn.net`), stating that page HTML is discarded after
  extraction and the URL is not stored, and adding the retention sentence for the extract route.
  `ARCHITECTURE.md:33` and `MCP_BRIDGE.md`'s privacy boundary get the same treatment for Task 78.
  **The extractor's own host allow-listing is sound and stays.**
- **Shared thing:** the corrected text is the input to owner step O-5 (App Store Connect privacy
  answers) and to Task 99's manifest.
- **Tests:** a documentation test asserting the allow-list in `PRIVACY.md` matches
  `inspiration-extractor.ts`'s constant — the same shape as Task 91's tool-list test.
- **Acceptance:** a reviewer reads `PRIVACY.md` and `ARCHITECTURE.md` against the four cited code
  paths and finds no false statement. **DEC-12 may change the code instead of the document** — if the
  intent was genuinely a no-network capture, the alternative is to move both calls back into the main
  app's drain path. This task ships the honest document either way; Task 95 ships the code change if
  she picks it.

### Task 78: The bridge capability leaves `snapshot.json`, and becomes revocable

- **Closes:** L5-04 (blocker). **client + server + docs**
- **Files and sites:** `ios/AgentCy/Services/MCPBridgeService.swift:697` writes the whole snapshot —
  including `McpBridgeSnapshotSchema.notification`, a `McpBridgePushCapability` with a 32–512
  character bearer `token` (`contracts/src/mcp.ts:22`, `:232`) — to `snapshot.json` in the chosen
  folder. On macOS that lands unencrypted in
  `~/Library/Mobile Documents/com~apple~CloudDocs/agent.cy MCP/`, syncs through iCloud, and is
  readable by every process running as the creator. `MCP_BRIDGE.md` contradicts itself inside one
  document: the privacy boundary says credentials are not copied into the snapshot; "Review delivery"
  says the capability is written into it. Move the capability into its own `push-capability.json`
  written with `0600` semantics; correct `ARCHITECTURE.md:33` and the `MCP_BRIDGE.md` boundary to say
  the bridge folder holds one revocable, notification-only capability; add server-side revocation so
  `/v1/bridge/notifications/register` invalidates the prior `bridgeNotificationCapabilityHash`, and
  have the app re-register on every erase, sign-out and bridge disconnect. Pairs with Task 83 so a
  leaked capability cannot be abused at volume.
- **Tests:** a server test that registering invalidates the previous hash; a client test that erase
  and disconnect both re-register.
- **Acceptance:** the bridge folder after a connect contains no bearer token in `snapshot.json`, shown
  by `cat`; a previously captured capability returns 401 after a re-register.

### Task 79: The Share Extension declares the API it uses

- **Closes:** L5-15 (major) and **APPLE-05 (blocker)** — the same defect, filed by two lanes.
  **client**
- **Files and sites:** `ios/AgentCyInspirationShare/PrivacyInfo.xcprivacy` is
  `<key>NSPrivacyAccessedAPITypes</key><array/>`, while `ShareViewController.swift:275` and `:338`
  construct `UserDefaults(suiteName: InspirationSharedContainer.appGroupIdentifier)` and
  `InspirationShareTransport.swift:615-627` reads and writes the same suite. The main app and the
  widget extension both correctly declare `NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1` /
  `1C8F.1`; the share extension was missed. Add the category with reason `CA92.1`. This is an
  **ITMS-91053 upload validation**, so it stops the build before review — it and Task 98 gate
  everything else in B6.
- **Tests:** a build-phase or CI check that every target's `PrivacyInfo.xcprivacy` declares a category
  for every required-reason API its sources call.
- **Acceptance:** an archive validates in App Store Connect without ITMS-91053 for this target.
  Re-derive all three manifests against the final binaries in the same pass — `SETUP.md` already lists
  that as an open release gate, and Task 77 changes what the extension is documented to do.

### Task 80: Rate limits key on an address the caller cannot choose

- **Closes:** L5-05 (major). **server**
- **Files and sites:** `server/src/app.ts:148-155` — `trustProxy: true` trusts the entire chain, so
  the left-most forwarded address wins and the caller controls the rate-limit key consumed at `:275`
  and `:365` via `enforceInviteRedemptionRateLimit` (`:1178`). Proven locally:
  `evidence/security/trustproxy-xff-spoof.txt` shows `request.ip` returning the attacker-supplied
  `203.0.113.9` and then `198.51.100.1`. Change to `trustProxy: 1`. Invitation redemption and Apple
  sign-in are the only two routes that limiter protects; production invite codes are already ≥20
  characters across ≥3 classes (`server/src/config.ts:226-243`), so this is a throughput and abuse
  control, not an immediate credential-guessing exposure.
- **Caveat carried:** `trustProxy: 1` yields the right-most untrusted address **only if Railway's edge
  adds exactly one `X-Forwarded-For` entry**. If it adds two, every request collapses into one
  rate-limit bucket — worse than today. **Read the real hop count first** (added to P1 in Task 94), or
  accept RISK-04.
- **Tests:** a regression test asserting a request with `x-forwarded-for: 1.2.3.4, 5.6.7.8` resolves
  to `5.6.7.8`, not `1.2.3.4`.
- **Acceptance:** the test, plus the hop count from P1 recorded in the review.

### Task 81: Erase All Data clears the push identifiers

- **Closes:** L5-06 (major). **server**
- **Files and sites:** `server/src/store.ts:751` (`eraseInstallation`) nulls `tokenHash`, sets
  `deletedAt`, and clears quota events, cost events, telemetry, reservations and operations — but
  never clears `pushDeviceToken`, `pushPlatform`, `bridgeNotificationCapabilityHash`, `accountId` or
  `allowanceCounts` (`server/src/store.ts:32-45`). `PRIVACY.md:57` lists "installation-linked proxy
  metadata" among the things erase removes and names only three retained items; an APNs device token
  is a durable per-device identifier and is none of them. Set `pushDeviceToken = null`,
  `pushPlatform = null`, `pushShowTitles = true`, `bridgeNotificationCapabilityHash = null` and
  `accountId = null`. Keep `allowanceCounts` — it is the content-free free-journey integrity record —
  and add it to the `retained` list returned by `/v1/privacy/delete` (`server/src/app.ts:451`) so the
  response and `PRIVACY.md` agree.
- **Tests:** extend the existing erase test to assert every push field is null afterwards.
- **Acceptance:** the test, plus `PRIVACY.md`'s retained list matching the route's response byte for
  byte.

### Task 82: Erase All Data clears the bridge folder

- **Closes:** L5-07 (major). **client**
- **Files and sites:** `ios/AgentCy/Services/PrivacyEraseCoordinator.swift:252` removes only
  `snapshot.json`, then calls `MCPBridgePreferences.disconnect()`, which just clears the bookmark from
  `UserDefaults`. `mcp/src/workspace.ts:79-99` creates and populates `requests/`, `responses/`,
  `episode-revisions/`, `cy-requests/`, `cy-responses/`, `cy-processing/`, `cy-connection.json`,
  `cy-runtime.json`, `bridge-status.json` and `push-status.json` in the same folder.
  `cy-requests/*.json` holds complete AI request payloads (`LocalCyService.swift:280`) and
  `cy-connection.json` holds the Local Cy bearer token — all of it survives an erase, in iCloud Drive.
  Replace the single-file removal with a best-effort sweep of every path the bridge owns; keep it
  best-effort (the folder may be offline) but report a paused erase if the folder is reachable and
  removal fails, matching the existing `cleanupFailed` path. Document in `MCP_BRIDGE.md` that erase
  clears the bridge folder's agent.cy contents. **Answer Task 63's `removeRequest` question here.**
- **Tests:** a unit test over a temp folder populated with all eleven paths.
- **Acceptance:** `ls -la` of a populated bridge folder before and after an erase, attached.

### Task 83: The bridge notification route is rate-limited and its text is bounded

- **Closes:** L5-08 (major). **server**
- **Files and sites:** `server/src/app.ts:239-270` authenticates on the bridge capability alone, then
  `bridgePushSender.send` builds the body at `:1227` with `request.subject` verbatim —
  `"${request.subject}" ${change} and needs your review.` — whenever `pushShowTitles` is true.
  `McpBridgeNotificationRequestSchema` (`contracts/src/mcp.ts:35-42`) allows a 1–500 character subject
  and `pendingCount` up to 10,000. No reservation, no quota, no short-window limit, no per-installation
  cap. Combined with L5-04, anyone who reads the iCloud-synced capability can push unlimited alerts
  with attacker-chosen text under the agent.cy name. Apply a per-installation window limit (reuse the
  `enforceInviteRedemptionRateLimit` shape keyed on `installation.id`, e.g. 20 per 10 minutes)
  returning 429 with `retry-after`; cap the rendered subject at ~60 characters, strip control
  characters and newlines, and prefix it with a fixed agent.cy sentence so a spoofed subject cannot
  impersonate a system message.
- **Tests:** a server test for the 21st request in the window, and one asserting a newline-bearing
  subject renders sanitised.
- **Acceptance:** the tests; the sanitised alert screenshotted on device or simulator.

### Task 84: Telemetry ingestion is batched and capped

- **Closes:** L5-09 (major). **server**
- **Files and sites:** `server/src/app.ts:401-429` loops
  `for (const event of parsed.data.events) await repository.appendTelemetry(...)`; each
  `appendTelemetry` (`store.ts:735`) is its own `transact` (`:245`), and each `transact`
  `structuredClone`s the entire state and does a full `writeFile` + `rename` of
  `agent-cy-state.json` (`:196`). The schema permits 100 events per request
  (`contracts/src/supporting.ts:192`) inside the 128 KB body limit, with no rate limit, no
  per-installation cap and no cap on `state.telemetry.length` — only a 30-day age purge. `SETUP.md`
  specifies one replica on one `/data` volume, so this is the whole store. Batch the loop into one
  `repository.appendTelemetryBatch(events, cutoff)` transaction; add a per-installation window limit;
  add a hard drop-oldest cap on `state.telemetry` (~200,000 rows) beside the age purge.
- **Tests:** a server test that 100 events perform one write; a test that the cap evicts oldest-first.
- **Acceptance and before/after measurement:** time 100 events before and after locally; report both.

### Task 85: A failed generation stops refunding the abuse controls

- **Closes:** L5-10 (major). **server**
- **Files and sites:** `server/src/app.ts:794-820` settles any non-success outcome with
  `failureCostMicros = 0`, and `settleOperation` (`store.ts:700-707`) splices the matching entry out
  of `state.quotaEvents`. So a request that reached Anthropic, consumed input and output tokens, and
  then failed schema validation (`:730`), the integrity check (`:737`) or the model-identity check
  (`:717`) consumes no short-window count, no daily operation count, no free allowance and nothing
  against `dailyCostLimitMicros` — an authenticated installation can drive unbounded real provider
  spend serially, limited only by the one-concurrent-operation guard. Keep the **allowance** refund
  (that promise is creator-facing and correct); record the real `providerResult` token cost in
  `costEvents` whenever the provider actually returned tokens, even on a failed outcome; leave the
  `quotaEvent` in place for every outcome except `cancelled` before the provider call started.
- **Tests:** a test asserting ten consecutive `generation_invalid` outcomes consume ten short-window
  slots and their true cost.
- **Acceptance:** the test, plus the daily-spend counter moving in a local run.

### Task 86: The extract route is subject to the same limits as everything else

- **Closes:** L5-11 (major). **server**
- **Files and sites:** `server/src/app.ts:190-204` calls `authenticate` (`:869`) and nothing else —
  no `reserveOperation`, no rate limit, no access check; and `authenticate` only matches a token hash
  and requires `deletedAt === null`, never inspecting `installation.access`, so an `expired`
  installation passes. Each accepted call makes the proxy issue three outbound Instagram requests, each
  with a 10 s timeout and up to 2 MB of body (`inspiration-extractor.ts:12`, `:14`). Put the route
  behind the per-installation short-window limiter (e.g. 15 per 10 minutes), reject `expired`, and add
  a single-flight guard keyed on `installationId + canonicalUrl` so a retry storm from the share sheet
  cannot multiply outbound fetches. The URL canonicalisation and host allow-listing need no change.
- **Tests:** server tests for the limit, the expired rejection and the single-flight guard.
- **Acceptance:** the tests; confirmed again against production in Task 94's P7.

### Task 87: Local Cy stops broadcasting the creator's content in the clear

- **Closes:** L5-12 (major). **bridge + docs**, and it interacts with Task 76.
- **Files and sites:** `mcp/scripts/install-local-cy.mjs:63-70` writes
  `baseURL: http://<LocalHostName>.local:49321` and a 32-byte token into `cy-connection.json`;
  `mcp/src/local-cy-http-server.ts:38` binds `0.0.0.0`; the iPhone reaches it through the ATS local
  networking exception in `ios/project.yml`. Every request body is the complete request-scoped creator
  context and every request carries `Authorization: Bearer <token>` in clear, so on a café or hotel
  network any device on the same L2 segment can read the content and capture the token, and mDNS
  resolution for `<host>.local` is spoofable. The code comment at `local-cy-http-server.ts:34-37`
  acknowledges this; `PRIVACY.md` does not mention it at all. Bind to the Mac's current private LAN
  address rather than `0.0.0.0`; reject a request whose remote address is not RFC1918 or link-local;
  add a per-request HMAC over the body using the shared token so a passive listener cannot replay; and
  add a plain sentence to `PRIVACY.md` and the Settings > AI screen — Local Cy sends your content over
  your local network in the clear, so use it on networks you trust.
- **Tests:** bridge tests for the bind address, the remote-address rejection and HMAC verification.
- **Acceptance:** `lsof -i :49321` shows a private address, not `*`; the Settings > AI disclosure
  screenshotted on both form factors. **The TLS half is deferred — see below.**

### Task 88: `.dockerignore` excludes nested `.env` files

- **Closes:** L5-13 (major). **server**
- **Files and sites:** `.dockerignore` lines 4–5 use root-anchored `.env` and `.env.*`, which under
  Docker's pattern matching cover `./.env` only, while `Dockerfile:18` is `COPY server ./server` — so a
  local `docker build` bakes in `server/.env`, which `SETUP.md` instructs developers to create. The
  same file already uses `**/node_modules` and `**/dist`, so the nested form was known and simply not
  applied to secrets. Change both lines to `**/.env` and `**/.env.*`; add `.claude`, `.agents` and
  `mcp` to the ignore list. Railway builds from git where `.env` is not tracked, so the live image is
  not currently affected.
- **Tests:** a CI step that builds the image and greps the layers for `.env`.
- **Acceptance:** `docker build` with a `server/.env` present, then `docker run … ls server/.env`
  returning not-found.

### Task 89: The production container stops running as root

- **Closes:** L5-14 (major). **server**
- **Files and sites:** `Dockerfile:1-26` has no `USER` directive, so
  `CMD ["node", "server/dist/index.js"]` runs as uid 0 and the attached `/data` volume — every
  installation record, hashed credential, entitlement and telemetry row — is created and written by
  root. `store.ts:201`'s mode `0600` is the only file-level control today. Add
  `RUN mkdir -p /data && chown -R node:node /data /app` and `USER node` before `CMD`. Verify on Railway
  that the mounted volume's ownership survives; if the mount lands root-owned, add a tiny entrypoint
  that `chown`s once and drops privileges rather than reverting to root.
- **Tests:** a CI step asserting `id -u` in the image is not 0.
- **Acceptance:** the check, plus a successful Railway deploy with the volume writable.

### Task 90: Patch the two reachable advisories

- **Closes:** L5-16 (major), except the acceptance and the major-upgrade question. **server**
- **Files and sites:** `server/package.json` (`fastify: ^5.6.2`). The two reachable advisories are
  both **patch bumps** reached through `fastify`: `fast-uri` ≥ 4.1.2 (GHSA-v2hh-gcrm-f6hx,
  GHSA-7p8r-x3mc-p8w7 — host confusion via a backslash authority delimiter) and `find-my-way` ≥ 9.6.1
  (GHSA-c96f-x56v-gq3h — HTTP/2 DDoS). **Do not run `pnpm update fastify --latest`** as the finding
  originally wrote: `--latest` can cross a major, and the contract reserves dependency upgrades with
  breaking changes for Chey (that is DEC-14). Pin the patch bumps, re-run `pnpm audit`, re-run
  `server`'s vitest suite. Neither advisory is currently exploitable here — the app validates with Zod
  rather than JSON Schema `format: uri`, and Fastify is not configured for HTTP/2
  (`server/src/app.ts:148`) — but they are high severity in a production tree.
  The three MCP-side advisories (`hono`, `@hono/node-server`, `ip-address`) are unreachable because
  the bridge runs stdio-only (`mcp/src/index.ts`) and are **RISK-01**, not a fix.
- **Tests:** `pnpm audit` in `server/` returns zero high-severity reachable advisories; the server
  suite passes.
- **Acceptance:** the audit output before and after, attached.

### Task 91: The MCP tool document matches the bridge

- **Closes:** L5-17 (major). **docs**
- **Files and sites:** `docs/MCP_BRIDGE.md` lists 8 read and 7 write tools; `mcp/src/server.ts:32-778`
  registers **32**, including `scheduling_preflight`, `list_social_accounts`, `list_series`,
  `list_episode_slots`, `list_episode_revisions`, `get_episode_revision`, `list_brand_partners`,
  `set_post_work_date`, `reschedule_post`, `mark_posted`, `create_series`, `create_series_episode`,
  `resubmit_series_episode`, `add_post_task`, `create_brand_partner`, `update_brand_partner` and
  `make_anchor_pillar`. **The boundary itself holds** — every write tool routes through
  `queuedResult` → `workspace.queueRequest` (`server.ts:812`, `workspace.ts:111`), no tool deletes,
  archives, publishes, erases, reads attachment bytes or touches the database, and every id parameter
  is `z.string().uuid()` so the `join()` calls cannot traverse — it is simply undocumented, so nobody
  can review it. Regenerate the list from source and note explicitly that `mark_posted` records a
  status the creator already published elsewhere and does not publish anything, since "publish" is
  named in the not-exposed list.
- **Tests:** a test asserting the documented set equals the registered set, so it cannot drift again.
- **Acceptance:** the test passes and the document lists 32.

### Task 92: Server and bridge minors

- **Closes:** L5-18 (minor), L5-21 (minor), L5-22 (minor), L5-23 (minor). **server + bridge**
- **Files and sites:** `server/src/app.ts:167-171` — the `onSend` hook sets only
  `x-content-type-options: nosniff` and `referrer-policy: no-referrer`, and `/v1/installations/redeem`
  (`:318`) and `/v1/accounts/apple/sign-in` (`:382`) return the raw installation credential in the JSON
  body with no `cache-control`; add `strict-transport-security: max-age=31536000; includeSubDomains`,
  `x-frame-options: DENY`, `content-security-policy: default-src 'none'` and `cache-control: no-store`
  on every response, and leave CORS unregistered with a comment saying that is deliberate.
  `server/src/config.ts:290` — throw at startup when `NODE_ENV=production` and
  `REVENUECAT_WEBHOOK_SECRET` is unset or under 32 characters, and require it to differ from the four
  hash secrets, matching `:155-179` (the webhook already fails closed, so this is about a silent
  failure, not a bypass). `server/src/config.ts:284-288` — invert `PILOT_COMPED_ACCESS`'s default to
  `false` so removing the variable revokes rather than grants, and make
  `promoteActiveFreeJourneysToComped` (`app.ts:135-143`, `store.ts:433`) idempotent by skipping any
  installation that already has a `promotionalEntitlementEndsAt`, so a redeploy does not silently
  re-extend the 28-day window for the whole cohort. `mcp/src/installer.ts:98`, `:104-112`, `:118`,
  `:161-166` — drop `shell: process.platform === "win32"` and resolve `claude.cmd` / `codex.cmd`
  explicitly so a `--workspace` value containing `&` or `"` is not re-parsed by `cmd.exe`.
- **Tests:** header assertions on one JSON route and one SSE route; a config test for the missing
  secret; a store test for the idempotent promotion.
- **Acceptance:** `curl -I` output before and after, attached.

### Task 93: Client minors

- **Closes:** L5-19 (minor), L5-20 (minor), L5-24 (minor), L5-25 (minor). **client**
- **Files and sites:** `ExportService.swift:410-413` — write the archive with
  `[.atomic, .completeFileProtection]` and remove it when the share sheet is dismissed rather than
  waiting for an erase; keep `LocalExportArchiveCleaner`
  (`PrivacyEraseCoordinator.swift:43`) as the backstop. `InspirationShareTransport.swift:313-318`,
  `:352`, `:500` — cap the `IncomingInspiration/` queue at ~40 envelopes and 1 GB of assets, evicting
  oldest-first on enqueue, and stream `InspirationShareMediaAnalyzer.swift:29`'s video download with a
  running byte counter that aborts past `maximumBytes` instead of relying on `expectedContentLength`,
  which returns 0 when the CDN omits `Content-Length` (`:66-69`) so an oversized body is fully written
  before `stageFile` rejects it. `AppModel.swift:2366-2368` and `ModelContainerFactory.swift:41` — map
  the error to a stable enumerated diagnostic identifier (the shape
  `server/src/provider.ts:135`'s `safeDiagnosticIdentifier` already uses) and log that as public,
  keeping the raw description at `privacy: .private`; no reachable error type carries creator text
  today, so this is a guard against the next one. `MCPBridgeService.swift:746-750` — treat a nil
  `workspaceId` as belonging to the **default** workspace only, matching `WorkspaceScope.includes`,
  and have the bridge refuse to queue a write when no snapshot exists
  (`mcp/src/workspace.ts:151` sets `workspaceId: snapshot?.workspaceId ?? undefined`), so the id is
  always present. `ARCHITECTURE.md:31` already states the intended rule.
- **Tests:** unit tests for the queue cap, the streaming abort, the diagnostic mapping and the nil
  workspace rule.
- **Acceptance:** export, share, dismiss, and confirm the temp file is gone; queue 45 shares and
  confirm eviction.

### Task 94: (after H1: AUTH-02) Run the production probe

- **Closes:** the live confirmation of L5-05, L5-06, L5-08, L5-09, L5-11 and the header work in
  Task 92 — none of which was tested against the deployed service, correctly.
- **Blocked on:** AUTH-02. Do not start before H1.
- **Files and sites:** `docs/refinement/probe-plan.md`, P1–P12, **58 requests total**, none of which
  reaches Anthropic, so incremental provider spend is zero. **Add one item to P1: read Railway's
  actual `X-Forwarded-For` hop count**, so Task 80's `trustProxy: 1` is verified rather than assumed.
  Observe the plan's own hard stops, especially P8's ("do not send more than these four requests").
- **Acceptance:** the plan's per-phase expected-versus-observed table filled in, the P6 invite removed
  from `INVITE_CODES` afterwards, and P12's erase confirmed — or, if P12 cannot run, the installation
  id recorded so it can be erased later.

### Task 95: (after H1: DEC-12) Settle what the Share Extension is allowed to do

- **Closes:** the code half of L5-02, if DEC-12 says the behaviour changes rather than the document.
- **Blocked on:** DEC-12. Do not start before H1.
- **Files and sites:** if the answer is "the document was right" — move
  `InspirationShareAPI.swift:112` and `:155` back into the main app's drain path so the extension
  makes no network request, and keep `InspirationShareMediaDownloader` local. If the answer is "the
  code is right", Task 77 has already shipped and nothing further is needed here.

### Task 96: (after H1: DEC-13) Settle Local Cy for the beta

- **Closes:** the residual of L5-12, either by shipping TLS or by accepting RISK-02.
- **Blocked on:** DEC-13. Do not start before H1.
- **Files and sites:** if TLS: generate a self-signed certificate at install time
  (`mcp/scripts/install-local-cy.mjs`) and pin its SPKI in `cy-connection.json`, moving the transport
  to `https` — which also lets Task 76's validator drop the `http` allowance entirely and closes the
  ATS question in Task 102. If not: the disclosure from Task 87 stands and RISK-02 is accepted.

### Task 97: (after H1: DEC-14) Fastify major upgrade

- **Closes:** the remainder of L5-16 if she takes the major.
- **Blocked on:** DEC-14. Do not start before H1. Task 90 has already closed both reachable
  advisories with patch bumps, so this is hygiene, not a fix.

### Deferred (B5)

- **L5-09's architectural half — moving telemetry out of the single JSON document.** Task 84 ships the
  batching, the window limit and the row cap, which is what makes the route safe before beta.
  **Reason: replacing `JsonFileStateBackend` is a storage-engine change on a live service with one
  replica and one volume; it is not a pre-beta change, and the batching removes the amplification that
  made the shape dangerous.** Carried to the beta-readiness report.
- **L5-12's TLS half — a self-signed certificate generated at install time with its SPKI pinned in
  `cy-connection.json`.** Task 87 ships the bind-address restriction, the remote-address rejection,
  the per-request HMAC and the plain-language disclosure. **Reason: certificate generation, trust and
  rotation across the installer, the bridge and the iOS client is a multi-day change with its own
  failure modes, and the mitigations shipped in Task 87 remove the passive-capture and replay paths
  that make the cleartext channel dangerous.** It re-enters as Task 96 if DEC-13 asks for it; otherwise
  it is RISK-02.

---

## B6 · Apple readiness

Four B6-batched findings are closed in earlier batches, deliberately, so B6 does not re-touch files
those batches rewrote: **APPLE-05** by Task 79, **APPLE-13** by Task 25, **APPLE-17** by Task 30,
**APPLE-19** by Task 16, **APPLE-20** by Task 2. **APPLE-18 is not a finding** — the skeptic
reclassified it as an inventory correction (its body is "L1 owns this, and Apple imposes no
constraint" plus the `installation-invite-gate` correction), and the correction lands in Task 23.

Tasks 98 and 79 are ITMS upload validations: **nothing else in B6 can be tested until they land.**

### Task 98: Declare the System Boot Time required-reason API

- **Closes:** APPLE-04 (blocker).
- **Files and sites:** `ios/AgentCy/Support/PrivacyInfo.xcprivacy` declares exactly one category
  (`NSPrivacyAccessedAPICategoryUserDefaults`, reasons `CA92.1` / `1C8F.1`), but the app calls
  `ProcessInfo.processInfo.systemUptime` at six live sites — `RootView.swift:56` and `:63`,
  `AppModel.swift:106`, `:118`, `:145`, `:164` — whose `RootLaunch` milestones appear in the captured
  launch log. Add `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1` ("measure the
  amount of time that has elapsed between events that occurred within the app"), which is exactly what
  `RootLaunchDiagnostics` does. **ITMS-91053 stops the upload, before review** — a dozen lines of XML
  with the highest ratio of consequence to effort in the pass.
- **Tests:** Task 79's manifest-versus-sources check now covers this target too.
- **Acceptance:** an archive validates in App Store Connect with no ITMS-91053.

### Task 99: Declare what the app collects

- **Closes:** APPLE-09 (major). Pairs with owner step **O-5**.
- **Files and sites:** `ios/AgentCy/Support/PrivacyInfo.xcprivacy` has no `NSPrivacyCollectedDataTypes`
  key at all — not even an empty array — while the Share Extension declares
  `<key>NSPrivacyCollectedDataTypes</key><array/>`, so the app is the odd one out, and
  `docs/TESTFLIGHT.md:6` requires the manifests to match the archived binary. `PRIVACY.md` documents
  real collection: a keyed hash of the Apple subject identifier, a device-only installation credential,
  content-free request metadata and consented product events retained for 30 days, invite redemption
  records, and entitlement history. Add at minimum
  `NSPrivacyCollectedDataTypeOtherUserContent` (linked, not tracking, purpose
  `NSPrivacyCollectedDataTypePurposeAppFunctionality`) for the material sent to Cy, and
  `NSPrivacyCollectedDataTypeOtherDiagnosticData` for the content-free request metadata. **Derive the
  list from Task 77's corrected `PRIVACY.md`, not from the current one.**
- **Tests:** a check that every collected type in the manifest has a matching sentence in `PRIVACY.md`.
- **Acceptance:** the manifest and the App Store Connect answers (O-5) agree, item for item.

### Task 100: One signing and APNs story

- **Closes:** APPLE-02 (blocker), APPLE-11 (minor). Pairs with owner step **O-4**.
- **Files and sites:** `ios/project.yml:57-60` — the `AgentCy` Release config carries
  `APS_ENVIRONMENT: development`, `CODE_SIGN_STYLE: Manual` and
  `PROVISIONING_PROFILE_SPECIFIER: AgentCy Development 2026`, which flow into
  `aps-environment: "$(APS_ENVIRONMENT)"` (`:108`, `AgentCy.entitlements`). The Catalyst target gets
  it right in the same file (`:141-142`), which is what makes the iPhone value read as an oversight.
  `scripts/archive_testflight.sh:27-32` overrides `CODE_SIGN_STYLE=Automatic` but **not**
  `APS_ENVIRONMENT`, so the archive carries `development` — and then
  `AgentCyApplicationDelegate.swift:141-175` registers tokens production APNs will reject, so every
  "Claude or Codex sent a proposal" notification silently fails for every tester. Set
  `APS_ENVIRONMENT: production` and drop `PROVISIONING_PROFILE_SPECIFIER` / `CODE_SIGN_STYLE: Manual`
  from that config so the archive resolves an App Store profile; make the same edit for
  `AgentCyWidgets` Release (`:222-224`); keep Debug on `development`. Removing the specifier also stops
  Xcode fighting automatic signing when Chey archives from the UI, which is what
  `docs/TESTFLIGHT.md:33` tells her to do.
- **Tests:** a CI or script assertion that the Release entitlements resolve to `production`.
- **Acceptance:** `codesign -d --entitlements :- ` on a Release archive shows
  `aps-environment: production`; a bridge push reaches a device on a TestFlight build.

### Task 101: Drop the background mode nothing uses

- **Closes:** APPLE-06 (major — blocker if review asks and there is no answer).
- **Files and sites:** `ios/project.yml:85-87` declares `UIBackgroundModes: [audio,
  remote-notification]`, but every audio session in the app is foreground-scoped:
  `VoiceSparkView.swift:47-52` sets `.record` and `:165` deactivates; the playback sites
  (`VoiceSparkView.swift:230-236`, `VoiceRecordingDetailPage.swift:141-149`,
  `PostMediaViews.swift:91-99`) each set `.playback` then deactivate.
  `grep -rn "beginBackgroundTask" ios/AgentCy` returns nothing, there is no interruption or
  route-change handling, and the whole recorder is compiled out on Catalyst
  (`VoiceSparkView.swift:1`), where the target correctly declares only `remote-notification`
  (`:170-171`). Remove `audio`, keeping `remote-notification`, which private CloudKit mirroring needs.
  **If DEC-05 removes the Creator Session family, Task 74 removes `NSSupportsLiveActivities` in the
  same edit; sequence them.** **DEC-17** is the alternative: if Voice Spark should keep recording when
  the creator leaves the app, that is a feature decision and needs interruption handling before the
  mode can be justified.
- **Tests:** an assertion over the generated Info.plist.
- **Acceptance:** the plist, and a Voice Spark recording confirmed still working end to end on device.

### Task 102: Drop the ATS exception and the purpose strings for capabilities the app does not use

- **Closes:** APPLE-07 (major).
- **Files and sites:** `ios/project.yml:88-90` declares `NSAppTransportSecurity:
  NSAllowsLocalNetworking: true` and `NSLocalNetworkUsageDescription`, but no code performs local
  network discovery: `grep -rn "NWConnection\|NWBrowser\|NWListener\|NetService" ios/` returns
  nothing, there is no `NSBonjourServices` key, and the only non-HTTPS URL is
  `URL(string: "http://127.0.0.1:3000")` at `APIClient.swift:137`, inside `#if DEBUG` and loopback
  (loopback needs no local-network permission). Local Cy exchanges files through an iCloud Drive
  folder, as the app's own copy says (`MCPBridgeSettingsView.swift:157`). Delete lines 88-90, the
  Catalyst equivalents at `:172-174`, and `NSSpeechRecognitionUsageDescription` from the Catalyst
  target at `:176` — speech recognition runs only in the iOS-only Voice Spark and share extension.
  **Sequence after Task 96:** if DEC-13 keeps Local Cy on HTTP over the LAN, the ATS exception may
  become genuinely required, in which case it stays and the purpose string is rewritten to describe
  Local Cy honestly rather than deleted.
- **Tests:** an assertion over both targets' generated Info.plists.
- **Acceptance:** a clean install prompts for no local-network permission.

### Task 103: The control that deletes the account says so

- **Closes:** APPLE-08 (major).
- **Files and sites:** the control literally labelled **"Delete account"**
  (`SettingsSubpages.swift:430-438`) deletes one content workspace, lives in an overflow menu, and only
  exists when `activeWorkspaces.count > 1`; its confirmation (`:487`) names posts, pillars, ideas,
  tasks, weekly focus and Cy conversations — content only. The control that actually deletes the
  account is `EraseDataSettingsView`, kicker "Your data", title **"Erase all data"** (`:2266-2270`),
  the only path to `appModel.eraseAll(context:)` → `PrivacyEraseCoordinator` →
  `POST /v1/privacy/delete` (`PrivacyDeletionService.swift:210`). Guideline 5.1.1(v) expects account
  deletion to be easy to find and unambiguously labelled; two differently-scoped destructive actions,
  one of them mislabelled, is the pattern that draws a rejection. Rename the workspace control to
  "Delete workspace" and its dialog to match; add an explicit "Delete account" row in Settings routing
  to `EraseDataSettingsView`, whose title becomes "Delete account and erase data". Sites:
  `SettingsSubpages.swift:438`, `:478-487`, `:2266-2270`, `:2312-2318`, and the index entry in
  `SettingsView.swift`.
- **Tests:** a copy test asserting no two destructive controls share a label.
- **Acceptance:** phone and desktop, light and dark, of the Settings index, the workspace menu and the
  delete-account page.

### Task 104: The calendar purpose string describes the access it asks for

- **Closes:** APPLE-10 (minor — major if review asks and the answer is "for the picker").
- **Files and sites:** `CalendarSyncService.swift:181` calls `requestFullAccessToEvents()`, and the
  only declared string (`ios/project.yml:91`) is "Allow agent.cy to add scheduled posts and tasks to
  your chosen calendar" — a purpose string that describes writing. Full access is genuinely needed:
  `availableCalendars()` calls `eventStore.calendars(for: .event)`, which write-only access does not
  permit. Keep the access; make the string honest about the scope — that it lists calendars so the
  creator can choose one, adds and updates the posts and tasks they schedule, and never reads their
  other events, which is what `PRIVACY.md` already promises. Edit `ios/project.yml:91` and `:175`
  together.
- **Tests:** an assertion over both generated Info.plists.
- **Acceptance:** the permission prompt screenshotted on device.

### Task 105: The Sign in with Apple button stays visible when the appearance changes

- **Closes:** APPLE-12 (major — it is the only control on the first screen).
- **Files and sites:** `AppleAccountAccessView.swift:614` —
  `.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)`. `SignInWithAppleButton` is a
  `UIViewRepresentable` whose style is fixed when the view is made and is not re-applied on a
  `colorScheme` change, so launching light and then switching to dark leaves a black button on the
  near-black `agentSurface` card, visible only by its edge — a tester on the system's automatic
  Light/Dark schedule hits this without doing anything. Add `.id(colorScheme)` to force the
  representable to rebuild.
- **Tests:** none automatable; this is a representable lifecycle bug.
- **Acceptance:** the three captures the lane took, re-taken —
  `evidence/apple/first-launch-gate-light.png`, `-dark.png` (launched light then switched) and
  `-dark-coldstart.png`. The runtime-switched capture must now match the cold-start one.

### Task 106: The tab bar is one VoiceOver container

- **Closes:** APPLE-14's accessibility half (minor). **The tab count is DEC-10 / Task 113.**
- **Files and sites:** `AppShellView.swift:762-810` — per-tab VoiceOver is already handled well
  (`.accessibilityLabel(tab.title)`, `.accessibilityHint(...)`,
  `.accessibilityAddTraits(.isSelected)` at `:801-805`), but the enclosing `HStack` has no
  `.accessibilityElement(children: .contain)` and no tab-bar trait, so VoiceOver reads six loose
  buttons in scroll order instead of a tab group with position. Wrap the `HStack`.
- **Tests:** an accessibility audit assertion in the UI test target.
- **Acceptance:** a VoiceOver pass over the tab bar, recorded, announcing position ("2 of 6").

### Task 107: The first screen is written for someone who has never been here

- **Closes:** APPLE-15 (minor — but it is the first screen five invited creators and App Review all
  meet).
- **Files and sites:** `AppleAccountAccessView.swift:19-59` — on a clean install the gate leads with
  "Pick up where you left off." and "Sign in to connect this device to your existing workspace", while
  the invitation path, the only one a beta tester can use, is a secondary button explained by fine
  print at the bottom. Branch on `appModel.hasInstallationCredential`: lead with the invitation for a
  device that has never held a credential, and swap the emphasis back once `hasLinkedAccount` has ever
  been true. Copy change plus one branch in `AccountAccessGate`. Task 19's Cancel/Close/Done rule also
  touches this surface's `installation-invite-gate` (`RootView.swift:495-503`).
- **Tests:** a unit test over the gate's copy selection for both credential states.
- **Acceptance:** phone light and dark, clean install, against
  `evidence/apple/first-launch-gate-light.png` as the before. This is also owner step **O-11**'s
  screen, so attach the after shot to the review notes.

### Task 108: A Keychain read failure is not a red error on a first launch

- **Closes:** APPLE-16 (minor).
- **Files and sites:** `AppModel.swift:503-530` — the `catch` sets `hasInstallationCredential = false`
  and `hasLinkedAccount = false` and then calls `presentCreatorError(error, action: "The connection")`,
  which renders through `CreatorFacingErrorMapper.swift:116-121` as "The connection couldn't be
  completed. Your work is saved. Try again." in `agentDestructive` under the sign-in card
  (`AppleAccountAccessView.swift:81-92`). **Scope note carried from the lane:** the trigger observed
  was the entitlement-free baseline simulator build, which is a build artifact, not proof a signed
  build shows this today. The defect is the code shape: `load()` already maps `errSecItemNotFound` to
  `nil` (`APIClient.swift:59`), so anything reaching that `catch` is an unexpected Keychain or decode
  failure — and the app's response is to greet a first-time creator with a red error about a
  connection they have not attempted. A restored device whose stored blob no longer decodes, a
  provisioning change, or a read during a locked state all produce the same first impression. On the
  launch path, treat a failed read as "no credential": set the flags, log content-free, leave `notice`
  alone, and surface a Keychain error only after the creator taps Continue with Apple or Connect Cy.
  Separately, `AccountAccessGate` should show only account-scoped notices rather than whatever
  `appModel.notice` happens to hold.
- **Tests:** a unit test injecting a Keychain failure on the launch path and asserting `notice` is nil.
- **Acceptance:** phone light and dark, clean install on a **signed** build — no red line.

### Task 109: Minor sweep (B6)

- **Closes:** the residual documentation items — `docs/TESTFLIGHT.md:22` still shows
  `BUILD_NUMBER=136` as its example against a current `CURRENT_PROJECT_VERSION` of 229
  (`ios/project.yml:14`, `MARKETING_VERSION 0.1.0`, history 139 → 158 → 170 → 227 → 229, monotonic and
  fine); update the example. Record owner step **O-9**'s substantiation in `TESTFLIGHT.md` so nobody
  re-derives it: `ITSAppUsesNonExemptEncryption: false` is correct — the app uses only HTTPS,
  `CryptoKit.SHA256` (`AppleAccountAccessView.swift:672`), `SecRandomCopyBytes` and the Keychain, and
  `grep -rn "AES\|ChaChaPoly\|SealedBox\|CCCrypt\|SymmetricKey" ios/AgentCy ios/AgentCyShared` returns
  nothing.
- **Acceptance:** a reviewer follows `TESTFLIGHT.md` end to end and finds nothing stale.

### Task 110: (after H1: O-3) Revoke the Sign in with Apple token on account deletion

- **Closes:** APPLE-01 (blocker).
- **Blocked on:** owner step **O-3** — the Sign in with Apple key. This finding **cannot be fixed in
  code without it**; the code can be written and unit-tested against a stub, but it cannot be verified.
- **Files and sites:** `server/src/app.ts:431` (`/v1/privacy/delete`) runs `eraseInstallation`, clears
  the idempotency cache and returns a retention receipt. Nothing in `server/src/` calls
  `https://appleid.apple.com/auth/revoke` — `grep -rni "revoke" server/src/` returns **nothing**, and
  `grep -rn "client_secret\|auth/token" server/src/` returns nothing. The client collects
  `credential.authorizationCode` (`AppleAccountAccessView.swift:585-597`) and ships it to the proxy,
  where the only mention is the type declaration `readonly authorizationCode: string;` — never
  exchanged, never stored. Persist the authorization code (or its refresh token) at redemption time in
  `apple-identity.ts`; on delete, exchange it at `https://appleid.apple.com/auth/token` and
  `POST /auth/revoke` with the Sign in with Apple client secret before erasing. Add `APPLE_TEAM_ID`,
  `APPLE_KEY_ID` and the `.p8` to Railway. **Revoke failure must not block local erasure** — log it
  content-free and retry. Guideline 5.1.1(v) is a standing, commonly enforced rejection reason.
- **Tests:** a server test with a stubbed Apple endpoint covering success, failure and retry.
- **Acceptance:** delete a test account and confirm in the Apple ID's app list that agent.cy is gone.

### Task 111: (after H1: O-6 / DEC — see packet) Subscription, or a safe promotional path

- **Closes:** APPLE-03 (blocker for an App Store submission; major for the promotional TestFlight
  cohort).
- **Blocked on:** owner step **O-6**.
- **Files and sites:** `SubscriptionService.swift:33-73` — `UnavailableLiveSubscriptionService`
  advertises `monthlyPrice: "$8.99", trialDays: 14`, sets `supportsPurchases = false`, and both
  `startTrial` and `restore` throw; `SubscriptionServiceFactory.runtime` returns it for **every**
  non-DEBUG build. `SubscriptionAccess.canCreate` and `.canUseCy` are both `self != .expired`
  (`DomainTypes.swift:1339-1340`), so an expired creator loses creation and Cy entirely, and the
  Access page prints "Paid plans arrive in an upcoming release. Your invite covers access until then."
  (`SettingsSubpages.swift:2159-2163`). The server side is already built —
  `server/src/app.ts:470` handles the RevenueCat webhook. Guidelines 3.1.1 and 2.1 both apply.
  **The promotional-cohort half is not blocked and should ship with B6 regardless:**
  `refresh` must never downgrade a server-granted state it cannot verify — return early instead of
  writing `.expired`, and let `LifecycleService` own expiry from the server-supplied `trialEnd`.
  Note that `.comped` **is** already preserved
  (`isVerifiedLocally = state.trialEnd.map { $0 > now } ?? true`); only `.trial` and `.paid` downgrade.
  The full RevenueCat client integration (offerings, purchase, restore, `supportsPurchases = true`)
  waits on O-6 and is not required for a promotional-only external cohort.
- **Tests:** a unit test that a `.comped` and a server-granted `.paid` state survive a refresh the
  client cannot verify.
- **Acceptance:** a TestFlight tester on the promotional cohort never reaches `.expired`.

### Task 112: (after H1: artwork from Chey) App icon dark and tinted variants

- **Closes:** APPLE-21 (minor) — a code change waiting on an owner input.
- **Files and sites:** `ios/AgentCy/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` holds
  a single universal 1024×1024 entry. The file itself is submission-valid (verified: sRGB,
  `hasAlpha: no`, PNG colour type 2, so no alpha channel to trip the store's icon check); what is
  missing is the `appearances` entries, so a Home Screen set to dark or tinted shows the light icon
  unchanged. Add `"appearances": [{"appearance": "luminosity", "value": "dark"}]` and the tinted
  entry with matching artwork, or supply an Icon Composer `.icon` asset.
- **Acceptance:** Home Screen screenshots in light, dark and tinted.

### Task 113: (after H1: DEC-10) The tab count

- **Closes:** APPLE-14's structural half.
- **Blocked on:** DEC-10. Do not start before H1.
- **Context:** `AppTab.allCases` is six — `home, today(→plan), tasks, pillars, ideaBank, cy` — plus a
  separate Create accessory, none rendering its `title` (`AppShellView.swift:885`). Apple's iPhone
  guidance is three to five, and UIKit's own tab bar collapses past five into More, which a custom bar
  does not do. `page-purpose.md` §4's verdict is that **the set is right and matches the PRD
  one-for-one**, with two vocabulary problems and no structural ones — so the recommendation is to
  keep six. The desktop shell carries **eight** sidebar destinations
  (`DesktopAppShellView.swift:1601-1636`), and the two extras (`feed-grid`, `saved-posts-library`) are
  the two DEC-08 and DEC-07 propose to demote, which would make one IA instead of two.
- **Acceptance:** whichever DEC-10 chooses, with the desktop sidebar brought to the same number.

### Deferred (B6)

None. Every standing B6 finding is in a task above, in an earlier batch's task (APPLE-05, 13, 17, 19,
20), or behind a named owner step (Tasks 110–113). APPLE-18 is not a finding.

---

## Owner steps

`findings-apple.md` §2 carries O-1 … O-14 in dependency order and they are reproduced in
`decision-packet.md` §5. Two are hard blockers on code — **O-3** (APPLE-01 / Task 110) and **O-6**
(APPLE-03 / Task 111) — and **O-8** (a published privacy policy URL and a support address) has no repo
artefact at all yet.

## Where I differ from the skeptic

The brief asks me to say so, and to decide. Five places, none of them substantive reversals:

1. **The census arithmetic.** The report's headline is "124 findings stand, 8 are weakened"; its own
   per-lane verdicts sum to 125 standing, 6 weakened, 1 reclassified, 1 rejected. I planned from the
   per-lane verdicts, which are the ones carrying re-derived evidence. This is exactly the class of
   error the report's own G-10 catalogues.
2. **G-8 covers both desktop modal metrics, not one.** The report accepts
   `cyReviewModalMetrics = 1180 × 860` because it is *larger* and so does not violate the "smaller"
   clause. The rule design.md states is "**one** desktop modal footprint"; 1180 × 860 is a second
   footprint whether or not it is smaller. DEC-03 puts both in front of Chey.
3. **L2H-07 splits in two.** The report weakens it to minor and says "keep the code fix in B2 if it is
   cheap; do not let it displace a measured item." I have split it: the filter hoist (Task 40) is
   cheap, certain and needs no measurement, so it ships now; the 46-`@State` split is deferred until
   Task 42's device trace sizes it. Half a fix now beats a whole fix that cannot be proved.
4. **APPLE-17 moves from B6 to B2** (Task 30). It is the same defect class as L2M-04 and lives in two
   files B2 rewrites; fixing it in B6 would mean touching them twice.
5. **G-3 goes to B1, not "B1 or B6"** (Task 9). The Share Extension's Dynamic Type failure and G-1's
   fourth typography family are the same edit in the same file, so they are one task.

Two of the report's own asides I have taken up rather than left: the `Button("Skip tour")` label
one-off is recorded in Task 19 (as a skip, not a dismissal), and the fixture requests it routed to
Chey are built in Task 43 instead, because building them is cheaper than spending an invite code.
