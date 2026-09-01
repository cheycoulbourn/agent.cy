# L1 · Design consistency findings

Lane L1 of the pre-beta refinement program. Scope, format and severity per
`docs/refinement/00-contract.md`. Surfaces are named with the slugs in
`docs/refinement/01-page-inventory.md`. Every finding below carries evidence
produced in this pass — a `file:line` excerpt I read, a pixel measurement I
took, or a screenshot I captured. Nothing was carried over from
`docs/archive/audit-2026-08/`.

**Evidence produced this pass** — `docs/refinement/evidence/consistency/`:
22 iPhone 17 Pro simulator screenshots (six tab roots light + dark, seven
sheet kinds) and 3 Mac Catalyst screenshots (the Catalyst app **did** build and
run under the scratchpad derived data — scheme "AgentCy Desktop", 1024×768
window), plus `measure-close-controls.py` / `png_measure_lib.py` /
`measurements.txt`, the script that measures rendered control geometry
straight out of the PNGs.

---

## 1. The close-control census verdict — the answer to Chey's question

**No. There is no single Liquid Glass X in this app, and the two most common
ones differ by 4 points in diameter — enough to see, not enough to look
deliberate.**

Every circular close control in Agent.cy *is* perfectly round; that part is
fine. What is not fine is that there are **nine distinct implementations of
"leave this screen"** and they disagree on size, material, stroke, icon size,
press feedback and wording. Measured off the screenshots I captured, in the
same appearance, on the same device:

| Surface | Screenshot | Measured diameter | Interior fill |
|---|---|---|---|
| weekly-focus-setup Close | `sheet-weeklyFocus-light.png` | **44.00 pt** | `(255,255,255)` |
| voice-spark Close | `sheet-voiceSpark-light.png` | **48.00 pt** | `(255,255,255)` |
| weekly-focus-setup Close (dark) | `sheet-weeklyFocus-dark.png` | 44.67 pt | `(46,46,46)` |

The canonical one is `AgentToolbarIconButton` / `AgentToolbarIconLabel`
(`Design/DesignTokens.swift:286-322`): 44 pt, 17 pt glyph, 0.5 pt white
stroke at **0.22**. That is what design.md's "Circular toolbar icon (44 pt)"
row describes, it is used at **56 call sites**, and it should win.

The eight others:

1. **`AgentCircularGlassIconButton`** (`DesignTokens.swift:917-942`) — a
   second shared component that is 48 pt, glyph 16 pt, stroke at **0.16**,
   and unlike the canonical one it *does* apply `AgentPressButtonStyle`.
   6 call sites: `VoiceSparkView.swift:397/405/1312`,
   `CreatorSessionView.swift:346`, `VoiceRecordingDetailPage.swift:305/313`.
   This is the 44-vs-48 pair Chey can see.
2. **Four hand-rolled copies of the canonical geometry**, each re-typing
   `.glassEffect(.clear.interactive(), in: .circle)` + a 0.22 white stroke
   instead of calling the component: `CreationHubView.swift:216-244`,
   `SocialGridView.swift:452-470`, `ResumablePostEditorView.swift:576-586`,
   `AskCyView.swift:1278-1292`. Two of them (`CreationHubView.swift:244`,
   `AskCyView.swift:1290`) have already drifted — they add
   `.shadow(color: agentPureBlack.opacity(0.08), radius: 12, y: 4)` that the
   shared component does not have.
3. **A fifth glass circle at 40 pt** with an `agentBorder` stroke instead of
   the white one — `CreationHubView.swift:489-497`.
4. **A non-glass 40 pt opaque circle** — `agentSurface` fill, 1 pt
   `agentBorder`, no `glassEffect` at all — `SocialGridView.swift:1041-1051`
   (day-agenda-add-live-post). The only close control in the app that is not
   translucent, **and** 4 pt under the 44 pt phone minimum.
5. **Plain text "Cancel"** — 49 occurrences.
6. **Plain text "Close"** — 46 occurrences.
7. **Plain text "Done"** with no cancel at all — `TasksView.swift:858`
   (task-filter), `PostMediaViews.swift:897` (post-editor-media-manager).
8. **`AgentDesktopDetailBackButton`** (`DesignTokens.swift:390-418`) — the
   Catalyst-only text-plus-chevron rail control.

`ResumablePostEditorView.swift` alone contains **seven** of these nine
families; `AgendaView.swift` contains five; `TasksView.swift` five;
`BrandCabinetView.swift` uses text "Cancel" at `:787` and text "Close" at
`:1064` and `:1111` — same file, same `.cancellationAction` placement, same
job, two different words.

---

## 2. Page × rule matrix

164 surfaces × 12 checkable rules. Cells are computed from the file that
declares the surface, which is the granularity the inventory itself uses;
where several surfaces share a file they share a row's verdict, and the
per-file line index in §3 says exactly where.

Legend — `·` pass · `✗n` fail (n distinct sites in the declaring file)
· `–` not applicable · `?` not individually verified this pass.

Columns — **CC** close control (one family per file) · **HD** header pattern
(one component per file) · **TY** the seven type levels · **SP** 4-pt spacing
scale · **RA** radii from `AgentRadius` · **BT** button family (no
`.borderedProminent`, no capsule buttons) · **AC** accent discipline (no
solid accent fill, no accent glow) · **IC** icon source (no SF Symbols) ·
**PF** press feedback (no bare `.buttonStyle(.plain)`) · **HT** hit targets
≥ 44 pt · **ES** `AgentEmptyState` · **SH** shadows only via
`agentSurfaceChrome`.

Column totals (surfaces failing): CC 145 · HD 122 · BT 111 · SP 99 · TY 92 ·
RA 90 · PF 149 · ES 61 · AC 49 · SH 44 · IC 14 · HT 8 verified.

| Slug | File | CC | HD | TY | SP | RA | BT | AC | IC | PF | HT | ES | SH |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| home | `Home/HomeDashboardView.swift` | · | ✗2 | ✗1 | ✗1 | ✗2 | ✗2 | ✗1 | · | ✗24 | ? | ✗ | · |
| plan-week | `Plan/PlanView.swift` | · | ✗2 | · | · | · | · | · | · | ✗4 | ? | · | · |
| tasks | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| pillars | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| idea-bank | `Ideas/IdeaBankView.swift` | ✗2 | · | ✗5 | · | · | · | · | · | ✗9 | ? | – | · |
| cy | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| feed-grid | `Feed/SocialGridView.swift` | ✗4 | ✗2 | · | · | · | ✗2 | · | · | ✗6 | ✗ | – | · |
| saved-posts-library | `Ideas/SavedPostsLibraryView.swift` | ✗2 | ✗3 | ✗2 | · | · | ✗1 | · | · | ✗3 | ? | · | · |
| creation-hub | `Capture/CreationHubView.swift` | ✗2 | · | · | · | · | ✗1 | ✗1 | · | ✗2 | ? | – | ✗2 |
| quick-capture | `Capture/QuickCaptureView.swift` | ✗3 | · | ✗20 | · | ✗2 | ✗4 | ✗7 | · | ✗24 | ? | ✗ | ✗4 |
| quick-capture-idea-notes | — | – | – | – | – | – | – | – | – | – | – | – | – |
| quick-capture-task-due-date-sheet | `Capture/QuickCaptureView.swift` | ✗3 | · | ✗20 | · | ✗2 | ✗4 | ✗7 | · | ✗24 | ? | ✗ | ✗4 |
| quick-capture-subtask-composer | `Capture/QuickCaptureView.swift` | ✗3 | · | ✗20 | · | ✗2 | ✗4 | ✗7 | · | ✗24 | ? | ✗ | ✗4 |
| cy-pro-upsell | `Capture/QuickCaptureView.swift` | ✗3 | · | ✗20 | · | ✗2 | ✗4 | ✗7 | · | ✗24 | ? | ✗ | ✗4 |
| voice-spark | `Capture/VoiceSparkView.swift` | ✗2 | · | · | · | · | · | · | · | · | ? | ✗ | ✗1 |
| voice-spark-link-picker | `Capture/VoiceSparkView.swift` | ✗2 | · | · | · | · | · | · | · | · | ? | ✗ | ✗1 |
| voice-recording-detail | `Shared/VoiceRecordingDetailPage.swift` | · | · | · | · | · | · | · | · | · | ? | – | · |
| creator-session | `Capture/CreatorSessionView.swift` | ✗2 | · | · | · | ✗14 | · | · | · | ✗1 | ? | – | · |
| creator-session-timer-fullscreen | `Capture/CreatorSessionView.swift` | ✗2 | · | · | · | ✗14 | · | · | · | ✗1 | ? | – | · |
| ask-cy-sheet | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| ask-cy-post-review | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| ask-cy-review-request | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| ask-cy-review-series | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| ask-cy-review-desktop-workspace | `Settings/MCPDesktopReviewView.swift` | · | · | ✗20 | ✗6 | ✗1 | · | · | ✗3 | ✗5 | ? | ✗ | · |
| ask-cy-conversation-history | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| ask-cy-transcript | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| ask-cy-batch-decision-alert | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| ask-cy-notice-alert | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| ask-cy-delete-conversation | `Cy/AskCyView.swift` | ✗4 | ✗2 | ✗1 | ✗3 | ✗4 | ✗3 | ✗4 | · | ✗13 | ? | ✗ | ✗6 |
| settings | `Settings/SettingsView.swift` | ✗3 | ✗2 | · | · | · | · | · | · | ✗5 | ? | · | · |
| settings-new-destination | `Settings/SettingsView.swift` | ✗3 | ✗2 | · | · | · | · | · | · | ✗5 | ? | · | · |
| settings-creator-profile | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-how-cy-helps | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-appearance | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-switch-account | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-add-account | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-new-post | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-platforms | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-new-format | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-brand-partnerships | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| settings-calendar | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-calendar-disconnect | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-notifications | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-ai-connection | `Settings/AIConnectionsSettingsView.swift` | · | · | · | · | · | · | · | · | · | ? | – | · |
| settings-quick-prompts | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-mcp-bridge | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| settings-mcp-guided-setup | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| settings-mcp-revision-note | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| settings-mcp-episode-review | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| settings-mcp-create-post-draft-review | `Settings/MCPBridgeSettingsView.swift` | ✗2 | ✗2 | ✗6 | · | ✗1 | · | · | · | ✗1 | ? | ✗ | · |
| settings-shortcuts-widgets | `Settings/CaptureIdeaShortcutSettingsView.swift` | · | · | · | · | · | · | · | · | · | ? | – | · |
| settings-onboarding-preview | `Onboarding/OnboardingView.swift` | ✗3 | · | ✗66 | ✗3 | ✗17 | ✗2 | ✗1 | · | ✗16 | ? | ✗ | · |
| settings-access | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-export-data | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-reset-posts-tasks | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-reset-confirm | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-erase-all-data | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-erase-confirm | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-remove-account-confirm | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-social-account-actions | `Settings/SettingsSubpages.swift` | ✗3 | ✗2 | · | ✗2 | ✗6 | ✗2 | ✗2 | · | ✗7 | ? | – | ✗1 |
| settings-review-test-alert | `Settings/SettingsView.swift` | ✗3 | ✗2 | · | · | · | · | · | · | ✗5 | ? | · | · |
| weekly-focus-setup | `Agenda/WeeklyFocusView.swift` | ✗3 | ✗3 | · | · | · | ✗2 | · | · | ✗4 | ? | – | · |
| weekly-focus-day-selection | `Agenda/WeeklyFocusView.swift` | ✗3 | ✗3 | · | · | · | ✗2 | · | · | ✗4 | ? | – | · |
| weekly-focus-task-templates | `Agenda/WeeklyFocusView.swift` | ✗3 | ✗3 | · | · | · | ✗2 | · | · | ✗4 | ? | – | · |
| daily-focus-detail | `Agenda/WeeklyFocusView.swift` | ✗3 | ✗3 | · | · | · | ✗2 | · | · | ✗4 | ? | – | · |
| daily-focus-editor | `Agenda/WeeklyFocusView.swift` | ✗3 | ✗3 | · | · | · | ✗2 | · | · | ✗4 | ? | – | · |
| consistency-goal-editor | `Shared/ConsistencyGoalCard.swift` | · | · | · | · | · | ✗1 | · | · | · | ? | – | · |
| activity-center | `Home/HomeDashboardView.swift` | · | ✗2 | ✗1 | ✗1 | ✗2 | ✗2 | ✗1 | · | ✗24 | ? | ✗ | · |
| activity-center-desktop-filter | `Home/HomeDashboardView.swift` | · | ✗2 | ✗1 | ✗1 | ✗2 | ✗2 | ✗1 | · | ✗24 | ? | ✗ | · |
| agenda-post-search | `Plan/PlanView.swift` | · | ✗2 | · | · | · | · | · | · | ✗4 | ? | · | · |
| day-agenda | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-inline-post-editor | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-pillar-picker | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-pillar-overwrite-confirm | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-pillar-picker-inline-confirm | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-add-live-post-picker | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-add-live-post | `Feed/SocialGridView.swift` | ✗4 | ✗2 | · | · | · | ✗2 | · | · | ✗6 | ✗ | – | · |
| day-agenda-episode-slot-picker | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| episode-slot-actions | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-focused-day-push | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-scheduling-post | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-deep-linked-brief | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| day-agenda-post-task-picker | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| post-reschedule | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| episode-slot-actions-secondary-push | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| post-task-output-sheet | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| agenda-month-calendar | `Agenda/AgendaView.swift` | ✗5 | ✗3 | · | ✗2 | ✗6 | ✗1 | · | · | ✗24 | ? | ✗ | · |
| resumable-post-editor | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-brand-partner-picker | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| post-editor-task-composer | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-task-due-date | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-voice-recorder | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-spark-development | `Brief/DevelopBriefView.swift` | ✗2 | · | · | ✗1 | · | · | · | · | ✗4 | ? | – | ✗1 |
| post-editor-spark-discard-confirm | `Brief/DevelopBriefView.swift` | ✗2 | · | · | ✗1 | · | · | · | · | ✗4 | ? | – | ✗1 |
| post-editor-series-planner | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-series-detail | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-series-details-editor | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-add-future-episodes | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-remove-future-slots-confirm | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-archive-series-confirm | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-episode-slot-selection | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-episode-brief | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-media-manager | `Brief/PostMediaViews.swift` | ✗2 | · | · | ✗1 | · | ✗2 | · | · | ✗1 | ? | – | · |
| post-editor-media-delete-confirm | `Brief/PostMediaViews.swift` | ✗2 | · | · | ✗1 | · | ✗2 | · | · | ✗1 | ? | – | · |
| post-editor-dates-sheet | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-actual-posted-date | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-actual-posted-date-confirm | `Brief/ScheduledPostDetailView.swift` | ✗3 | ✗2 | ✗1 | · | ✗4 | · | · | · | ✗4 | ? | ✗ | · |
| post-editor-pillar-calendar | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-delete-draft-confirm | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-move-to-idea-bank-confirm | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-delete-custom-status-confirm | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-episode-scheduled-confirm | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-editor-pending-proposal | `Brief/ResumablePostEditorView.swift` | ✗7 | ✗2 | ✗6 | ✗2 | ✗1 | ✗2 | · | · | ✗19 | ? | – | · |
| post-proposal-review | `Brief/PostProposalReviewView.swift` | ✗2 | ✗2 | · | · | · | · | · | · | · | ? | – | · |
| post-proposal-discard-confirm | `Brief/PostProposalReviewView.swift` | ✗2 | ✗2 | · | · | · | · | · | · | · | ? | – | · |
| idea-post-draft | `Ideas/IdeaBankView.swift` | ✗2 | · | ✗5 | · | · | · | · | · | ✗9 | ? | – | · |
| idea-post-draft-options-menu | `Brief/IdeaPostDraftView.swift` | ✗3 | ✗3 | ✗1 | · | · | · | · | · | · | ? | · | · |
| idea-post-draft-archive-confirm | `Brief/IdeaPostDraftView.swift` | ✗3 | ✗3 | ✗1 | · | · | · | · | · | · | ? | · | · |
| idea-bank-link-capture | `Ideas/SavedPostsLibraryView.swift` | ✗2 | ✗3 | ✗2 | · | · | ✗1 | · | · | ✗3 | ? | · | · |
| idea-bank-multi-select-toolbar | `Ideas/IdeaBankView.swift` | ✗2 | · | ✗5 | · | · | · | · | · | ✗9 | ? | – | · |
| idea-bank-delete-confirm | `Ideas/IdeaBankView.swift` | ✗2 | · | ✗5 | · | · | · | · | · | ✗9 | ? | – | · |
| idea-bank-content-filter-popover | `Ideas/IdeaBankView.swift` | ✗2 | · | ✗5 | · | · | · | · | · | ✗9 | ? | – | · |
| saved-posts-delete-confirm | `Ideas/SavedPostsLibraryView.swift` | ✗2 | ✗3 | ✗2 | · | · | ✗1 | · | · | ✗3 | ? | · | · |
| inspiration-review | `Ideas/InspirationCaptureViews.swift` | ✗3 | · | · | · | · | · | ✗1 | · | ✗4 | ✗ | · | ✗1 |
| inspiration-review-unsaved-close-confirm | `Ideas/InspirationCaptureViews.swift` | ✗3 | · | · | · | · | · | ✗1 | · | ✗4 | ✗ | · | ✗1 |
| inspiration-filming-schedule | `Ideas/InspirationCaptureViews.swift` | ✗3 | · | · | · | · | · | ✗1 | · | ✗4 | ✗ | · | ✗1 |
| inspiration-filming-schedule-dialog | `Ideas/InspirationCaptureViews.swift` | ✗3 | · | · | · | · | · | ✗1 | · | ✗4 | ✗ | · | ✗1 |
| brand-cabinet | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-partner-detail | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-partner-editor | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-contact-editor | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-activity-editor | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-activity-delete-confirm | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-post-link-picker | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brand-import-review | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| brief-details-linked-brief | `Brands/BrandCabinetView.swift` | ✗2 | ✗3 | ✗1 | · | · | · | · | · | ✗6 | ? | ✗ | · |
| pillar-guide | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| pillar-detail | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| pillar-info-popover | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| new-pillar | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| pillar-delete-confirm | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| pillar-make-anchor-confirm | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| pillar-picker-in-editor | `Pillars/PillarsView.swift` | ✗4 | ✗3 | ✗27 | ✗2 | · | ✗2 | · | ✗1 | ✗16 | ? | · | · |
| task-detail | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| task-options-dialog | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| task-delete-confirm | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| task-due-date-editor | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| task-filter | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| post-task-creation-flow | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| post-task-due-date-picker | `Tasks/TasksView.swift` | ✗5 | ✗4 | ✗6 | ✗3 | · | ✗3 | · | · | ✗9 | ? | · | · |
| onboarding-flow | `Onboarding/OnboardingView.swift` | ✗3 | · | ✗66 | ✗3 | ✗17 | ✗2 | ✗1 | · | ✗16 | ? | ✗ | · |
| onboarding-pillar-editor | `Onboarding/OnboardingView.swift` | ✗3 | · | ✗66 | ✗3 | ✗17 | ✗2 | ✗1 | · | ✗16 | ? | ✗ | · |
| onboarding-notice-alert | `Onboarding/OnboardingView.swift` | ✗3 | · | ✗66 | ✗3 | ✗17 | ✗2 | ✗1 | · | ✗16 | ? | ✗ | · |
| onboarding-completion-alert | `Onboarding/OnboardingView.swift` | ✗3 | · | ✗66 | ✗3 | ✗17 | ✗2 | ✗1 | · | ✗16 | ? | ✗ | · |
| account-access-gate | `Account/AppleAccountAccessView.swift` | · | · | · | · | · | · | · | · | · | ? | – | · |
| installation-invite-gate | `App/RootView.swift` | · | · | · | · | · | · | · | · | · | ? | · | · |
| account-restore | `Account/AppleAccountAccessView.swift` | · | · | · | · | · | · | · | · | · | ? | – | · |
| account-restore-sign-out-confirm | `Account/AppleAccountAccessView.swift` | · | · | · | · | · | · | · | · | · | ? | – | · |
| creation-hub-overlay-desktop | `Shell/DesktopAppShellView.swift` | ✗2 | · | ✗1 | ✗1 | ✗1 | · | · | ✗1 | ✗7 | ✗ | ✗ | · |
| creator-session-overlay-desktop | `Shell/DesktopAppShellView.swift` | ✗2 | · | ✗1 | ✗1 | ✗1 | · | · | ✗1 | ✗7 | ✗ | ✗ | · |
| walkthrough-overlay | `Shell/AppShellView.swift` | · | · | ✗8 | ✗2 | · | ✗2 | ✗2 | ✗1 | ✗4 | ? | – | ✗4 |
| mcp-review-global | `Shell/AppShellView.swift` | · | · | ✗8 | ✗2 | · | ✗2 | ✗2 | ✗1 | ✗4 | ? | – | ✗4 |
| task-completion-undo-toast | `Shell/AppShellView.swift` | · | · | ✗8 | ✗2 | · | ✗2 | ✗2 | ✗1 | ✗4 | ? | – | ✗4 |
| creator-session-floating-timer | `Capture/ActiveCreatorSessionFloatingTimer.swift` | · | · | · | · | · | ✗2 | · | · | · | ? | – | · |
| cy-weekly-planning-pulse / activity-bell | `Home/HomeDashboardView.swift` | · | ✗2 | ✗1 | ✗1 | ✗2 | ✗2 | ✗1 | · | ✗24 | ? | ✗ | · |
### Per-file violation index (the `file:line` behind every ✗)

- `AgentCy/Views/Agenda/AgendaView.swift` — R4-space @ 424,2107; R5-radii @ 548,550,556,761…; R6-btn @ 2986; R9-press @ 457,558,630,660…; empty state: 2 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Agenda/WeeklyFocusView.swift` — R6-btn @ 105,961; R9-press @ 75,303,426,1015
- `AgentCy/Views/Brands/BrandCabinetView.swift` — R3-type @ 1239; R9-press @ 108,254,295,363…; empty state: 3 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Brief/DevelopBriefView.swift` — R4-space @ 358; R9-press @ 136,355,379,386; R12-shadow @ 353
- `AgentCy/Views/Brief/IdeaPostDraftView.swift` — R3-type @ 249
- `AgentCy/Views/Brief/PostMediaViews.swift` — R4-space @ 1096; R6-btn @ 694,1098; R9-press @ 212
- `AgentCy/Views/Brief/ResumablePostEditorView.swift` — R3-type @ 4258,4301,4418,5072…; R4-space @ 4390,5135; R5-radii @ 4431; R6-btn @ 4391,5317; R9-press @ 561,1145,1228,1263…
- `AgentCy/Views/Brief/ScheduledPostDetailView.swift` — R3-type @ 598; R5-radii @ 589,592,772,774; R9-press @ 641,722,778,1327; empty state: 1 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Capture/ActiveCreatorSessionFloatingTimer.swift` — R6-btn @ 50,56
- `AgentCy/Views/Capture/CreationHubView.swift` — R6-btn @ 410; R7-accent @ 410; R9-press @ 237,412; R12-shadow @ 229,244
- `AgentCy/Views/Capture/CreatorSessionView.swift` — R5-radii @ 1127,1128,1281,1283…; R9-press @ 823
- `AgentCy/Views/Capture/QuickCaptureView.swift` — R3-type @ 97,102,126,132…; R5-radii @ 631,2323; R6-btn @ 135,687,1037,1452; R7-accent @ 78,135,136,687…; R9-press @ 137,143,601,688…; R12-shadow @ 78,136,1038,2298; empty state: 2 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Capture/VoiceSparkView.swift` — R12-shadow @ 466; empty state: 1 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Cy/AskCyView.swift` — R3-type @ 1154; R4-space @ 1437,1733,2783; R5-radii @ 1381,1382,1439,1441; R6-btn @ 1471,1668,2702; R7-accent @ 1444,1471,1472,1670; R9-press @ 965,982,1053,1107…; R12-shadow @ 1290,1444,1472,1670…; empty state: 2 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Feed/SocialGridView.swift` — R6-btn @ 975,1106; R9-press @ 470,610,933,1105…; hit targets @ 1038 (40pt close), 1235/1249 (32pt steppers)
- `AgentCy/Views/Home/HomeDashboardView.swift` — R3-type @ 1321; R4-space @ 2397; R5-radii @ 200,373; R6-btn @ 203,2105; R7-accent @ 2105; R9-press @ 117,177,202,235…; empty state: 7 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Ideas/IdeaBankView.swift` — R3-type @ 501,522,694,942…; R9-press @ 411,417,425,440…
- `AgentCy/Views/Ideas/InspirationCaptureViews.swift` — R7-accent @ 486; R9-press @ 428,604,623,900; R12-shadow @ 486; hit targets @ 211 (24pt Save)
- `AgentCy/Views/Ideas/SavedPostsLibraryView.swift` — R3-type @ 140,328; R6-btn @ 496; R9-press @ 95,105,495
- `AgentCy/Views/Onboarding/OnboardingView.swift` — R3-type @ 261,265,317,321…; R4-space @ 752,980,1567; R5-radii @ 504,506,535,537…; R6-btn @ 1746,1968; R7-accent @ 1968; R9-press @ 278,469,510,582…; empty state: 1 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Pillars/PillarsView.swift` — R3-type @ 372,565,692,695…; R4-space @ 1086,1600; R6-btn @ 1717,1723; R8-icon @ 2264; R9-press @ 420,512,576,615…
- `AgentCy/Views/Plan/PlanView.swift` — R9-press @ 139,146,168,507
- `AgentCy/Views/Settings/MCPBridgeSettingsView.swift` — R3-type @ 935,1553,1589,1634…; R5-radii @ 929; R9-press @ 1606; empty state: 2 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Settings/MCPDesktopReviewView.swift` — R3-type @ 111,113,153,155…; R4-space @ 128,170,284,363…; R5-radii @ 323; R8-icon @ 110,152,477; R9-press @ 118,160,328,370…; empty state: 1 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Settings/SettingsSubpages.swift` — R4-space @ 2414,2417; R5-radii @ 2063,2064,2104,2105…; R6-btn @ 2080,2141; R7-accent @ 2115,2141; R9-press @ 426,563,579,984…; R12-shadow @ 2115
- `AgentCy/Views/Settings/SettingsView.swift` — R9-press @ 86,100,175,196…
- `AgentCy/Views/Shared/ConsistencyGoalCard.swift` — R6-btn @ 128
- `AgentCy/Views/Shell/AppShellView.swift` — R3-type @ 353,576,584,593…; R4-space @ 714,808; R6-btn @ 372,686; R7-accent @ 372,686; R8-icon @ 458; R9-press @ 366,588,800,828; R12-shadow @ 373,687,717,923
- `AgentCy/Views/Shell/DesktopAppShellView.swift` — R3-type @ 340; R4-space @ 411; R5-radii @ 843; R8-icon @ 339; R9-press @ 218,267,504,580…; hit targets @ 340 (36pt appearance button); empty state: 5 bare-Text empty states, no AgentEmptyState
- `AgentCy/Views/Tasks/TasksView.swift` — R3-type @ 1513,1555,1888,1904…; R4-space @ 655,1717,1737; R6-btn @ 843,1583,2194; R9-press @ 735,847,887,1132…
---

## 3. Findings

### L1-01 Two shared glass close-control components exist, 44 pt and 48 pt, and neither is a subset of the other
- Where: `ios/AgentCy/Design/DesignTokens.swift:305-322` (`AgentToolbarIconLabel`, 44 pt / glyph 17 / stroke 0.22 / `.buttonStyle(.plain)`) vs `ios/AgentCy/Design/DesignTokens.swift:917-942` (`AgentCircularGlassIconButton`, 48 pt / glyph 16 / stroke 0.16 / `AgentPressButtonStyle`). Surfaces: weekly-focus-setup, quick-capture, settings, post-proposal-review (44 pt) vs voice-spark, voice-spark-link-picker, voice-recording-detail, creator-session (48 pt). Phone and desktop, both appearances.
- Evidence: measured off my own screenshots — `docs/refinement/evidence/consistency/measurements.txt`: weekly-focus Close = **44.00 pt**, voice-spark Close = **48.00 pt**, both interior fill `(255,255,255)` on ground `(245,246,243)`. Reproduce with `docs/refinement/evidence/consistency/measure-close-controls.py`.
- Severity: major
- Fix: delete `AgentCircularGlassIconButton` and re-point its 6 call sites (`VoiceSparkView.swift:397/405/1312`, `CreatorSessionView.swift:346`, `VoiceRecordingDetailPage.swift:305/313`) at `AgentToolbarIconButton`. Then move `AgentPressButtonStyle` onto `AgentToolbarIconButton` (`DesignTokens.swift:296` currently uses `.buttonStyle(.plain)`, so the canonical control is the one *without* press feedback), and settle the white stroke at one value — 0.22, the value the 56-site component already uses.
- Batch: B1
- Status: open

### L1-02 Four files hand-roll the canonical 44 pt glass circle instead of calling the component, and two have already drifted
- Where: `ios/AgentCy/Views/Capture/CreationHubView.swift:216-244` (creation-hub), `ios/AgentCy/Views/Feed/SocialGridView.swift:452-470` (feed-grid refresh), `ios/AgentCy/Views/Brief/ResumablePostEditorView.swift:576-586` (resumable-post-editor Spark), `ios/AgentCy/Views/Cy/AskCyView.swift:1278-1292` (ask-cy-sheet, Catalyst).
- Evidence: all four re-type `.glassEffect(.clear.interactive(), in: .circle)` plus `Circle().stroke(Color.agentPureWhite.opacity(0.22), lineWidth: 0.5)`. Two have already diverged by adding a shadow the shared component does not have — `CreationHubView.swift:244` and `AskCyView.swift:1290` both carry `.shadow(color: Color.agentPureBlack.opacity(0.08), radius: 12, y: 4)`, which is not one of the four `agentSurfaceChrome` roles.
- Severity: major
- Fix: replace all four with `AgentToolbarIconButton` / `AgentToolbarIconLabel` and drop the two stray shadows. `CreationHubView.swift:489-497` is a fifth copy at 40 pt with an `agentBorder` stroke — fold it in at 44 pt too.
- Batch: B1
- Status: open

### L1-03 day-agenda-add-live-post's close control is not glass and is under the 44 pt minimum
- Where: `ios/AgentCy/Views/Feed/SocialGridView.swift:1041-1051`, phone, both appearances.
- Evidence: `AgentIconView(.close, size: 16).frame(width: 40, height: 40).background(Color.agentSurface, in: .circle).overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }` — an opaque circle, no `glassEffect` anywhere in the expression, 40 pt on a phone sheet. design.md ("Spacing & layout") requires ≥ 44×44 pt on phone; 40 pt is the *desktop-only* floor.
- Severity: major
- Fix: `AgentToolbarIconButton(title: "Close", icon: .close)`.
- Batch: B1
- Status: open

### L1-04 Five Save controls are solid pure-white filled circles, which the contract bans outright
- Where: `ios/AgentCy/Views/Agenda/AgendaView.swift:2980-2990` (day-agenda), `ios/AgentCy/Views/Agenda/WeeklyFocusView.swift:99-109` (weekly-focus-setup) and `:955-965` (weekly-focus-day-selection), `ios/AgentCy/Views/Tasks/TasksView.swift:1577-1587` (post-task-creation-flow), `ios/AgentCy/Views/Brief/ResumablePostEditorView.swift:5311-5321` (post-editor-task-composer). Phone and desktop, both appearances.
- Evidence: all five are byte-for-byte the same block — `.buttonStyle(.borderedProminent).buttonBorderShape(.circle).controlSize(.large).tint(Color.agentPureWhite)` wrapping `AgentIconView(.check, size: 15).foregroundStyle(Color.agentPureBlack)`. Contract non-negotiable: "Buttons are quiet ink tints with 10 pt corners. Never solid fills, never pills." design.md Don'ts: "No pure black / pure white text or backgrounds outside `pureBlack`/`pureWhite` utility uses." On weekly-focus-setup this solid white puck sits in the *same toolbar* as the 44 pt glass Close (`WeeklyFocusView.swift:95`) — two unrelated circle treatments 300 pt apart, visible in `sheet-weeklyFocus-light.png`. A sixth site, `AskCyView.swift:2695-2705`, uses the same construction with `.tint(Color.agentSurface)`.
- Severity: blocker — it is a named non-negotiable, it is the item the inventory escalated, and it is on the two surfaces (day agenda, weekly focus) a beta tester touches first.
- Fix: introduce one shared `AgentToolbarSaveButton` built on the same 44 pt geometry as `AgentToolbarIconLabel` (glass circle, `AgentIcon.check`, ink glyph) and use it at all six sites. That also collapses the check glyph's six sizes (11/12/13/14/15/16 pt across 33 sites) to one.
- Batch: B1
- Status: open

### L1-05 The accent appears as a solid fill on eight buttons and a glow on ten surfaces, both explicitly banned
- Where: solid `cyAccent` capsule buttons — `ios/AgentCy/Views/Capture/QuickCaptureView.swift:135`, `:1037`, `:1452`; `ios/AgentCy/Views/Cy/AskCyView.swift:1471`; `ios/AgentCy/Views/Capture/CreationHubView.swift:410`; `ios/AgentCy/Views/Shell/AppShellView.swift:686` (`WalkthroughPrimaryButtonStyle`); solid `cyAccent` pill — `ios/AgentCy/Views/Settings/SettingsSubpages.swift:2141`. Accent glows — `QuickCaptureView.swift:78/136/1038`, `SettingsSubpages.swift:2115`, `AskCyView.swift:1444/1472/1670`, `InspirationCaptureViews.swift:486`, `AppShellView.swift:687`, `DevelopBriefView.swift:353`. Surfaces: cy-pro-upsell, quick-capture, creation-hub, ask-cy-sheet, settings-access, walkthrough-overlay, inspiration-review, develop-brief.
- Evidence: e.g. `QuickCaptureView.swift:135-136` — `.background(Color.cyAccent, in: .capsule)` immediately followed by `.shadow(color: Color.cyAccent.opacity(0.26), radius: 14, y: 6)`. design.md: "**No solid accent fills, anywhere** (decided 2026-08-14)"; "No glow — standard ambient shadows only (a glow was tried and rejected 2026-08-14)"; "no capsule-shaped buttons". Contract non-negotiable: "Brick red stays and appears only as marks, tints, glyphs, and text. No solid accent fills."
- Severity: blocker — three explicitly-dated design decisions are contradicted, on the paywall and the first-run tour, which is exactly where a beta tester starts.
- Fix: convert all eight to the sanctioned Cy chrome — `cy @ 12%` fill, 0.75 pt `cy @ 40%` border, brick semibold label, 10 pt corners, min height 40 — and delete every `shadow(color: Color.cyAccent…)`. The Home activity badge (`HomeDashboardView.swift:2105`) is a count badge, not a button, and may keep its solid accent as a "mark".
- Batch: B1
- Status: open

### L1-06 A second, undocumented typography API bypasses the seven type levels at 158 call sites
- Where: defined at `ios/AgentCy/Views/Pillars/PillarsView.swift:2339-2346` (`Font.paperInter` / `Font.paperMetadata`), used across 16 view files. Heaviest: onboarding-flow 66 sites, pillars 29, quick-capture 20, walkthrough-overlay 8, tasks 6, settings-mcp-bridge 6, resumable-post-editor 6.
- Evidence: `static func paperInter(size: CGFloat, weight: Font.Weight, relativeTo style: TextStyle) -> Font { .custom("InterVariable", size: size, relativeTo: style).weight(weight) }` — a raw size/weight escape hatch living at the bottom of a 2 400-line view file. The 158 calls span **39 distinct size/weight combinations** across sizes 9,10,11,12,13,14,15,16,17,18,19,20,22,24,28,32,36. design.md: "Seven levels — every text element must map to exactly one" and "Hierarchy comes from weight and the three text colors, not from inventing new sizes." `paperInter` also drops the `UIFont(name:)` availability guard that `Font.agentInter` (`DesignTokens.swift:600-609`) has, so it silently falls through to the system font if InterVariable fails to load.
- Severity: major
- Fix: delete both functions and map every call site to the nearest of the seven levels (32→`.agentDisplay`, 28→`.agentBriefTitle`, 22→`.agentTitle`, 17–20→`.agentHeadline`, 14–16→`.agentBody`, 12–13→`.agentSubtext`, 9–11→`.agentMetadata`), taking the weight from the level rather than the call. The 36 pt onboarding masthead (`OnboardingView.swift:317`) needs a decision from Chey: cap it at `.agentDisplay` (32) or add an eighth level.
- Batch: B1
- Status: open

### L1-07 Six SF Symbols ship in the UI, three of them as Back chevrons on a desktop drill-down
- Where: `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:110`, `:152`, `:477` (ask-cy-review-desktop-workspace); `ios/AgentCy/Views/Pillars/PillarsView.swift:2264` (new-pillar colour picker); `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:339` (desktop appearance toggle); `ios/AgentCy/Views/Shell/AppShellView.swift:458` (episode-slot-actions fallback).
- Evidence: `MCPDesktopReviewView.swift:110` — `Image(systemName: "chevron.left").font(.footnote.weight(.semibold))` paired with `Text("Back").font(.subheadline)`. Contract non-negotiable: "No SF Symbols in shipped UI; icons go through `AgentIcon`." design.md hard rule: "Back always uses the Nucleo `AgentIcon.back` asset on the same 44/48-pt control geometry as Close and Ellipsis; its shared optical scaling must not be bypassed with a raw system icon." This file bypasses it twice, and also bypasses `AgentDesktopDetailBackButton`, so the desktop MCP review pane is the only desktop drill-down in the app with a Back control that isn't the shared one.
- Severity: major
- Fix: `MCPDesktopReviewView.swift:104-120` and `:146-162` become `AgentDesktopDetailBackButton`; `:477` becomes `AgentIconView(.forward, size: 13)`; `PillarsView.swift:2264` and `DesktopAppShellView.swift:339` need Nucleo eyedropper and appearance glyphs added to `AgentIcon` (`DesignTokens.swift:79-215`); `AppShellView.swift:458`'s `ContentUnavailableView` becomes `AgentEmptyState`.
- Batch: B1
- Status: open

### L1-08 Buttons render at 8 pt corners, not the 10 pt the contract and design.md both specify
- Where: `ios/AgentCy/Design/DesignTokens.swift:769` — `AgentActionButtonTheme.radius = AgentRadius.control`, i.e. **8**. Every surface with an action button; phone and desktop.
- Evidence: `AgentRadius.control = 8` and `AgentRadius.button = 10` (`DesignTokens.swift:68-69`). The whole button family (`AgentPrimaryButtonStyle`, `AgentSecondaryButtonStyle`, `AgentCyPrimaryButtonStyle`, `AgentQuietSecondaryButtonStyle`, `AgentQuietDestructiveButtonStyle`) reads `AgentActionButtonTheme.radius`, so `AgentRadius.button` currently has **zero** users in the button family. Contract non-negotiable: "Buttons are quiet ink tints with **10 pt corners**." design.md: "`AgentRadius.button` / `--radius-button` | 10 | **All standalone buttons**".
- Severity: major — the contract states a number and the code uses a different one, so every button in the app is 2 pt off the spec Chey approved.
- Fix: `static let radius = AgentRadius.button` at `DesignTokens.swift:769`. One line, ~95 button call sites corrected at once.
- Batch: B1
- Status: open

### L1-09 The "one button family" has six different minimum heights and two label sizes
- Where: `ios/AgentCy/Design/DesignTokens.swift:817`, `:844`, `:871` (52 pt, `.agentHeadline`/18); `:790` `AgentQuietDestructiveButtonStyle` (44 pt, `.agentSubtext`/13); `ios/AgentCy/Views/Brief/PostMediaViews.swift:363` `AgentQuietSecondaryButtonStyle` (44 pt, `.agentSubtext`/13); `ios/AgentCy/Views/Cy/AskCyView.swift:2445` `ReviewBatchButtonStyle` (36 pt, radius 12); `ios/AgentCy/Views/Onboarding/OnboardingView.swift:1966` (56 pt, capsule) and `:2018` (54 pt, radius 16).
- Evidence: the doc comment above `AgentActionButtonTheme` (`DesignTokens.swift:760-766`) says "One visual family for every action button in the app… Roles differ only by fill and text color, never by shape" — but the five styles that read it disagree on height (44 vs 52) and label size (13 vs 18), and three more styles outside it (`ReviewBatchButtonStyle`, `PaperOnboardingPrimaryButtonStyle`, `PaperOnboardingOutlineButtonStyle`) don't read it at all. design.md specifies 40 pt min height and a 13 pt label for both Primary and Secondary; nothing in the code is 40.
- Severity: major
- Fix: settle on one height and one label size in `AgentActionButtonTheme` (add `minHeight` and `labelFont` constants), have all five styles read them, and delete `ReviewBatchButtonStyle` (3 sites, `AskCyView.swift`) in favour of `AgentQuietSecondaryButtonStyle`. Because design.md's 40/13 and the code's 52/18 disagree, this needs Chey to pick the number — see §6.
- Batch: B1
- Status: open

### L1-10 Onboarding and the walkthrough ship capsule buttons with solid ink or accent fills
- Where: `ios/AgentCy/Views/Onboarding/OnboardingView.swift:1959-1985` (`PaperOnboardingPrimaryButtonStyle`, 3 sites) and `:1746` (platform-format chips); `ios/AgentCy/Views/Shell/AppShellView.swift:676-701` (`WalkthroughPrimaryButtonStyle`, 1 site); `ios/AgentCy/Views/Capture/QuickCaptureView.swift:687`; `ios/AgentCy/Views/Tasks/TasksView.swift:2194`. Surfaces: onboarding-flow, walkthrough-overlay, quick-capture, task-detail.
- Evidence: `OnboardingView.swift:1968` — `.background(Color.actionAccent, in: .capsule)` with `.foregroundStyle(Color.onAccent)`, i.e. a solid ink capsule. `AppShellView.swift:686-691` — `.background(isFinalStep ? Color.cyAccent : Color.agentText, in: .capsule)` plus `.shadow(color: … cyAccent.opacity(0.24), radius: 12, y: 4)`: a solid accent capsule with a red glow. design.md: "buttons are 10-px rounded rectangles… never capsules, never solid color fills"; "never a solid ink block (too dark and bold)".
- Severity: blocker — onboarding and the first-run tour are literally the first two screens a beta tester sees, and they look like a different app from everything after them.
- Fix: delete `PaperOnboardingPrimaryButtonStyle` / `PaperOnboardingOutlineButtonStyle` / `WalkthroughPrimaryButtonStyle` and use `AgentPrimaryButtonStyle` / `AgentSecondaryButtonStyle` at all six sites; `OnboardingView.swift:1746` and `TasksView.swift:2194` become 8 pt-radius chips (`ink@9%` selected, border unselected) per design.md's Weekly-focus chip spec.
- Batch: B1
- Status: open

### L1-11 234 custom controls use bare `.buttonStyle(.plain)`, so press feedback is inconsistent across the app
- Where: 234 sites across 30 view files. Worst: `HomeDashboardView.swift` 24, `QuickCaptureView.swift` 24, `AgendaView.swift` 24, `ResumablePostEditorView.swift` 19, `PillarsView.swift` 16, `OnboardingView.swift` 16. Against 97 sites that correctly use `AgentPressButtonStyle`.
- Evidence: full site list in §2's per-file index. design.md, Components: "Press feedback is one system: every custom tappable control uses the 0.96-scale + easeOut 0.12 s treatment (via a shared button style), **not bare `.buttonStyle(.plain)`** — plain gives only the system dim and feels inconsistent next to the scaled controls." The canonical close control itself is one of the offenders (`DesignTokens.swift:296`), which is why the 44 pt X does not scale on press while the 48 pt X does.
- Severity: major
- Fix: mechanical swap of `.buttonStyle(.plain)` → `.buttonStyle(AgentPressButtonStyle())` on every control that draws its own background or icon. Keep `.plain` only where the label is a full row already handled by `agentHoverRow()`. Start with `DesignTokens.swift:296` — that one line fixes all 56 canonical toolbar controls.
- Batch: B1
- Status: open

### L1-12 Eight off-scale corner radii are in use, 3/5/6/9/13/14/18/22, at ~60 sites
- Where: radius 14 (28 sites, heaviest in `OnboardingView.swift` and `CreatorSessionView.swift`), 18 (9), 9 (8), 6 (6), 22 (3), 13 (3), 3 (3), 5 (1). Full list in §2's index under `R5-radii`.
- Evidence: `AgentRadius` offers 8/10/12/16/20/28 (`DesignTokens.swift:66-73`); none of 3/5/6/9/13/14/18/22 is a token. Examples: `OnboardingView.swift:504/579/597/627/1658/1725` all use `.rect(cornerRadius: 14)` for what are structurally `AgentRadius.card` (12) surfaces; `AgendaView.swift:761-770` uses 13 while `AgendaView.swift:548-556` twelve lines earlier uses 14 for the same kind of row. design.md Don'ts: "No new colors, sizes, radii, or shadows outside the tokens."
- Severity: minor
- Fix: map 3/5/6→`AgentRadius.control` where they are marks, 9/13/14→`AgentRadius.card` (12), 18→`AgentRadius.panel` (16), 22→`AgentRadius.dashboard` (20). Highest-value single file: `CreatorSessionView.swift` (14 sites).
- Batch: B1
- Status: open

### L1-13 pillar-guide's content selector is a hand-built capsule rail, which the segmented-Picker hard rule forbids
- Where: `ios/AgentCy/Views/Pillars/PillarsView.swift:1700-1723`, phone and desktop.
- Evidence: `HStack` of `Button`s with `.background(selectedTab == tab ? Color.agentSurface : Color.clear, in: .capsule)` inside `.background(Color.agentText.opacity(0.05), in: .capsule)`. design.md: "**Hard design rule — selector rails:** every compact horizontal rail that switches between peer views, modes, or collections **must** use the native iOS 26 segmented `Picker`… Never replace this pattern with `.ultraThinMaterial`, an opaque capsule, a custom `HStack`, or hand-built `.glassEffect` segments." Eight rails in the app do it correctly (`AgendaView.swift:434`, `TasksView.swift:663`, `SocialGridView.swift:546`, `QuickCaptureView.swift:533`, `WeeklyFocusView.swift:893`, `ResumablePostEditorView.swift:1718`, `SettingsSubpages.swift:1499`, `DesignTokens.swift:1426`); this is the one that doesn't. Compare `tab-today-light.png` (correct native rail) with `tab-pillars-light.png`.
- Severity: major
- Fix: replace with `Picker(...).pickerStyle(.segmented)` matching `AgendaView.swift:424-434`. The per-tab counts move into the segment labels or drop.
- Batch: B1
- Status: open

### L1-14 plan-week hand-rebuilds `AgentPageRail` instead of using it, and is the only tab root that doesn't
- Where: `ios/AgentCy/Views/Plan/PlanView.swift:129-155` vs `ios/AgentCy/Views/Shared/CreatorAvatar.swift:114-141`.
- Evidence: `PlanView`'s header is an `HStack(alignment: .center, spacing: AgentSpacing.x1)` of `MetaLabel` → actions → `ProfileSettingsButton` at `.frame(height: 44)` — structurally identical to `AgentPageRail`'s body, re-typed. The other five roots (home, tasks, pillars, idea-bank, feed-grid) plus saved-posts-library all call `AgentPageRail(` — which corrects the inventory's claim that it is a "one-off pattern not reused anywhere else, even though plan-week and idea-bank have a structurally similar need". Idea-bank already uses it (`IdeaBankView.swift:370`); only plan-week does not.
- Severity: minor
- Fix: `PlanView.swift:129-155` becomes `AgentPageRail(breadcrumb: "Weekly agenda", identity: activeIdentity, openSettings: …) { search + feed-shortcut buttons }`. Also resolves the inventory's "tasks / pillars / idea-bank tab-root headers — uncertain" item: all three use `AgentPageRail`.
- Batch: B1
- Status: open

### L1-15 The 44 pt toolbar control carries three different glyph sizes, so identical-looking circles have differently-sized icons
- Where: `ios/AgentCy/Views/Plan/PlanView.swift:137/144` (16), `ios/AgentCy/Views/Tasks/TasksView.swift:721` (16), `ios/AgentCy/Views/Ideas/IdeaBankView.swift:409` (16) vs `:423/438` (18), `ios/AgentCy/Views/Pillars/PillarsView.swift:510` (18), `ios/AgentCy/Views/Brief/ResumablePostEditorView.swift:571` (16), and 6 sites that take the 17 pt default.
- Evidence: `AgentToolbarIconLabel`'s `iconSize` defaults to 17 (`DesignTokens.swift:308`) and is overridden at 8 of its 14 call sites. The sharpest case is plan-week, whose two header circles pass 16 (`PlanView.swift:137/144`) while the settings and quick-capture circles a tap away take the 17 pt default — three visually identical 44 pt discs with three glyph sizes. `IdeaBankView.swift:409/423/438` uses 16 for one control and 18 for the two beside it. Across the whole app `AgentIconView(size:)` is called with **18 distinct values** (8,9,10,11,12,13,14,15,16,17,18,19,20,22,23,24,26,30) at 222 sites, none of them a token.
- Severity: minor
- Fix: remove the `iconSize` parameter from `AgentToolbarIconLabel` so all 14 sites render at 17, and add an `AgentIconSize` token set (mark 12 / inline 15 / control 17 / feature 24) that `AgentIconView` accepts instead of raw `CGFloat`.
- Batch: B1
- Status: open

### L1-16 Three words are used for the same "leave without acting" action, sometimes in the same file
- Where: 49 × "Cancel", 46 × "Close", 7 × "Done". Same-file collisions: `ios/AgentCy/Views/Brands/BrandCabinetView.swift:787` ("Cancel") vs `:1064` and `:1111` ("Close"), all three in `ToolbarItem(placement: .cancellationAction)`. `ios/AgentCy/Views/Tasks/TasksView.swift:1396` (icon X) vs `:858` ("Done") vs `:2571` ("Cancel"). `ios/AgentCy/Views/Capture/QuickCaptureView.swift:376` (icon X) vs `:2148` ("Cancel").
- Evidence: the greps above; each label read directly from the cited line. `ios/AgentCy/Views/Ideas/IdeaBankView.swift:406-418` goes further and swaps *form* at runtime: the same "Cancel selection" action renders as a 44 pt glass X at normal Dynamic Type and as a plain text "Cancel" at large sizes, so one control belongs to two close-control families depending on the reader's settings.
- Severity: major
- Fix: one rule, added to design.md — a surface that can discard unsaved edits says "Cancel"; a read-only surface uses the icon-only glass X; "Done" is never a dismissal (task-filter `TasksView.swift:858` and post-editor-media-manager `PostMediaViews.swift:897` currently have *no* way to discard, only to accept). Applying it touches ~100 sites but is a pure string/toolbar-item change.
- Batch: B1
- Status: open

### L1-17 About 20 empty states are bare `Text`, not `AgentEmptyState`, so half the app's empty screens say what's missing but not what goes there
- Where: `ios/AgentCy/Views/Home/HomeDashboardView.swift:676/743/865/900/1088/1161/1243`, `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:664/753/911/1105/1153`, `ios/AgentCy/Views/Ideas/IdeaBankView.swift:885-895`, `ios/AgentCy/Views/Capture/VoiceSparkView.swift:574`, `ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift:390/1039`, `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:459`. Surfaces: home, idea-bank, feed-grid, brand-cabinet, day-agenda, voice-spark, the whole desktop Control Center.
- Evidence: `IdeaBankView.swift:885` returns the string `"No ideas match this search."`, rendered as a plain `Text` — visible in `tab-ideaBank-light.png`, a single grey line where every other list screen shows the icon + title + message of `AgentEmptyState` (`DesignTokens.swift:1527-1555`). `AgentEmptyState` has 13 uses across 8 files; four files with list content (`IdeaBankView`, `SocialGridView`, `BrandCabinetView`, `AgendaView`) have zero.
- Severity: major
- Fix: convert each to `AgentEmptyState(title:message:icon:)` and give every one a second sentence naming the action, per design.md ("every list screen needs one that says why it's empty and what goes here").
- Batch: B1
- Status: open

### L1-18 Three tap targets are below the 44 pt minimum
- Where: `ios/AgentCy/Views/Feed/SocialGridView.swift:1235-1253` (32 pt − / + steppers, day-agenda-add-live-post), `ios/AgentCy/Views/Ideas/InspirationCaptureViews.swift:208-212` (24 pt Save checkmark, inspiration-review), `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:340-346` (36 pt appearance button — desktop floor is 40). Plus `SocialGridView.swift:1044` (40 pt close) from L1-03.
- Evidence: read directly; e.g. `InspirationCaptureViews.swift:211` — `AgentIconView(.check, size: 16).frame(width: 24, height: 24)` inside a `ToolbarItem(placement: .confirmationAction)` with no outer frame and no button style. This also resolves the inventory's "inspiration-review toolbar items — uncertain": `.cancellationAction` is text "Close" (`:203`) and `.confirmationAction` is a bare 24 pt checkmark — a *tenth* dismiss/confirm family.
- Severity: major — a 24 pt Save is a control a tester will miss.
- Fix: outer `.frame(width: 44, height: 44).contentShape(.circle)` on all three; the inspiration-review Save becomes the shared `AgentToolbarSaveButton` from L1-04.
- Batch: B1
- Status: open

### L1-19 `ask-cy-review-desktop-workspace` does not use any of the app's shared chrome
- Where: `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift`, desktop only.
- Evidence: in one 894-line file — 3 SF Symbols (`:110/:152/:477`), 20 non-token fonts (`.font(.subheadline)`, `.font(.footnote)`, `.font(.caption)`), 6 off-scale paddings (`:128/:170` 14, `:284` 6, `:363` 10, `:415` 40, `:481` 14), radius 14 (`:323`), 5 bare `.buttonStyle(.plain)`, a bespoke header, and no `AgentDesktopDetailRail`, no `AgentEmptyState`, no `AgentIcon` Back. It is the single least conformant surface in the app.
- Severity: major
- Fix: rebuild its chrome on `AgentDesktopDetailRail` + `AgentDesktopDetailBackButton` + `EditorialHeader` and map its type to the seven levels. One file, closes 35 cells.
- Batch: B1
- Status: open

### L1-20 Twelve shadows exist outside the four `agentSurfaceChrome` roles
- Where: accent glows (L1-05) plus neutral one-offs — `ios/AgentCy/Views/Capture/CreationHubView.swift:229` and `:244`, `ios/AgentCy/Views/Cy/AskCyView.swift:1290` / `:1742` / `:1767`, `ios/AgentCy/Views/Shell/AppShellView.swift:373` / `:717` / `:923`, `ios/AgentCy/Views/Capture/VoiceSparkView.swift:466`.
- Evidence: e.g. `AskCyView.swift:1742` — `.shadow(color: Color(white: 0).opacity(0.12), radius: 14, y: 4)`, which is also the app's only raw `Color(white:)` constructor (every other colour in `Views/` comes from the palette). design.md: "Elevation comes from `agentSurfaceChrome(role:)`… Four roles only… Never invent a new shadow."
- Severity: minor
- Fix: route all twelve through `agentSurfaceChrome(role: .floating)` / `.card`, and delete the accent-tinted ones outright per L1-05.
- Batch: B1
- Status: open

### L1-21 Liquid Glass renders as a flat pure-white puck on the light paper canvas
- Where: every 44/48 pt glass circle on a light-mode page: home, plan-week, tasks, pillars, idea-bank headers; weekly-focus-setup, voice-spark, quick-capture, settings closes. Phone; the same controls on desktop sit on `agentCanvas` too.
- Evidence: measured — on `tab-today-light.png` the plan-week search and feed-shortcut circles are exactly **44.00 pt** with an interior fill of **`(255,255,255)`** against a `(245,246,243)` canvas, while the `ProfileSettingsButton` avatar 30 pt to their right is **45.33 pt** with a `(253,253,251)` (`agentSurface`) fill. Three circles in one rail, two different whites and two different diameters, both visible in the screenshot. `(255,255,255)` is pure white, which design.md's Don'ts reserve for `pureWhite` utility uses.
- Severity: major — this is the visual root of "the close buttons don't match": the glass isn't doing anything on paper, so the control reads as a plain white disc that happens to be a different size and a different white on every screen.
- Fix: two options for Chey. (a) Keep glass but give the avatar the same treatment so the rail is internally consistent — `ProfileSettingsButton` (`CreatorAvatar.swift`) adopts `AgentToolbarIconLabel`'s geometry and material. (b) Accept that glass reads as opaque on paper and specify the light-mode fallback explicitly as `agentSurface` + the 0.5 pt stroke, so it is a chosen colour rather than a system artefact. Either way the diameter must be one number — see L1-01.
- Batch: B1
- Status: open

### L1-22 Twenty-nine paddings sit off the 4-pt scale
- Where: values 14 (6 sites), 10, 18, 28, 40, plus 1–7 pt optical nudges. Full list in §2's index under `R4-space`. Heaviest: `MCPDesktopReviewView.swift` (6), `OnboardingView.swift` (3), `TasksView.swift` (3), `AskCyView.swift` (3).
- Evidence: e.g. `AskCyView.swift:1437` and `:2783` both `.padding(.vertical, 14)`; `PillarsView.swift:1086` `.padding(.vertical, 18)`; `TasksView.swift:1737` `.padding(.leading, 28)`. design.md: "4-pt non-linear scale — never use in-between values."
- Severity: minor
- Fix: round each to the nearest scale step (14→12 or 16, 10→8 or 12, 18→16 or 20, 28→24 or 32, 40→32 or 48). The 1–7 pt values are optical nudges on marks and badges and can be left, but should be documented as such in design.md rather than reading as violations.
- Batch: B1
- Status: open

---

## 4. Shared components to introduce or unify — ordered by sites closed

| # | Change | Sites closed | Call sites it replaces |
|---|---|---|---|
| 1 | `.buttonStyle(.plain)` → `AgentPressButtonStyle()` on every control that draws its own background or glyph — starting with `DesignTokens.swift:296`, which alone fixes all 56 `AgentToolbarIcon*` controls | **234** | every site in §2's `R9-press` index |
| 2 | Delete `Font.paperInter` / `Font.paperMetadata` (`PillarsView.swift:2339-2346`); map calls onto the seven levels | **158** | 16 view files; see L1-06 for the per-file counts |
| 3 | `AgentActionButtonTheme.radius = AgentRadius.button` (one line, `DesignTokens.swift:769`) | **~95** | every button drawn by the five shared styles |
| 4 | One `AgentIconSize` token set replacing raw `AgentIconView(size:)` values | **222** | 18 distinct sizes across `Views/` |
| 5 | Collapse `AgentCircularGlassIconButton` into `AgentToolbarIconButton`; fold in the five hand-rolled glass circles and the one opaque circle | **12** | `VoiceSparkView.swift:397/405/1312`, `CreatorSessionView.swift:346`, `VoiceRecordingDetailPage.swift:305/313`, `CreationHubView.swift:216/489`, `SocialGridView.swift:463/1044`, `ResumablePostEditorView.swift:581`, `AskCyView.swift:1284` |
| 6 | New `AgentToolbarSaveButton` (44 pt glass circle + `AgentIcon.check`) replacing the `.borderedProminent` white pucks and the bare checkmarks | **9** | `AgendaView.swift:2986`, `WeeklyFocusView.swift:105/961`, `TasksView.swift:1583`, `ResumablePostEditorView.swift:5317`, `AskCyView.swift:2702`, `InspirationCaptureViews.swift:211`, `VoiceRecordingDetailPage.swift:313`, `VoiceSparkView.swift:405` |
| 7 | Convert bare-`Text` empty states to `AgentEmptyState` | **~20** | `HomeDashboardView.swift` ×7, `DesktopAppShellView.swift` ×5, `IdeaBankView.swift` ×3, `MCPBridgeSettingsView.swift` ×2, `VoiceSparkView.swift`, `MCPDesktopReviewView.swift`, `AppShellView.swift:458` |
| 8 | One shared "quiet accent action" (`cy@12%` fill, `cy@40%` border, brick semibold label) replacing solid accent capsules and their glows | **18** | `QuickCaptureView.swift:78/135/1037/1452`, `AskCyView.swift:1444/1471/1670`, `CreationHubView.swift:410`, `AppShellView.swift:686`, `SettingsSubpages.swift:2115/2141`, `InspirationCaptureViews.swift:486`, `DevelopBriefView.swift:353` |
| 9 | Delete `PaperOnboardingPrimaryButtonStyle` / `PaperOnboardingSecondaryButtonStyle` / `PaperOnboardingOutlineButtonStyle` / `WalkthroughPrimaryButtonStyle` / `ReviewBatchButtonStyle` in favour of the shared family | **9** | `OnboardingView.swift` ×7, `AppShellView.swift` ×1, `AskCyView.swift` ×3 |
| 10 | Radius token mapping for 3/5/6/9/13/14/18/22 | **~60** | see §2's `R5-radii` index; `CreatorSessionView.swift` (14) and `OnboardingView.swift` (17) are half of it |
| 11 | `AgentPageRail` at plan-week (`PlanView.swift:129-155`) | **1** | the last tab root that doesn't use it |
| 12 | `Picker(.segmented)` at pillar-guide (`PillarsView.swift:1700-1723`) | **1** | the last hand-built peer-view rail |

Items 1, 3 and 11 are each a handful of characters and close 330 cells between
them; they should land first.

---

## 5. Form factors and appearances

- **Phone:** all six tab roots and seven sheet kinds captured in light and
  dark (`tab-*-light.png` / `tab-*-dark.png`, `sheet-*-light.png`,
  `sheet-weeklyFocus-dark.png`, `sheet-creationHub-dark.png`). No appearance-
  specific breakage found beyond L1-04 (the solid white Save puck is far more
  jarring in dark mode, where it is the brightest object on the screen) and
  L1-21 (glass reads as pure white in light, `(46,46,46)` in dark).
- **Desktop (Mac Catalyst):** the "AgentCy Desktop" scheme **built and ran**
  under `…/scratchpad/DerivedDataMac` — `desktop-home-light.png`,
  `desktop-settings-light.png`, `desktop-creationHub-light.png`. The desktop
  shell is materially more consistent than the phone: `AgentDesktopDetailRail`
  and the Control Center widget anatomy hold up. Its two exceptions are the
  36 pt SF-Symbol appearance button (L1-07, L1-18) and
  `MCPDesktopReviewView` (L1-19). Every other L1 finding is shared code and
  lands on both form factors in the same change.

---

## 6. design.md corrections — where code and document disagree and code wins

Per the contract's "code wins and the document is fixed". These are *not*
findings; they are edits `design.md` needs so it stops describing an app that
no longer exists.

1. **Button styles are no longer capsules.** design.md line 314-315 says "The
   Swift capsule styles (`AgentPrimaryButtonStyle`, `AgentCyPrimaryButtonStyle`)
   are superseded and pending a code update to match." That update shipped
   (commit `8d5767b`, "Unify every action button into one bordered family");
   both styles are now bordered rounded rects reading `AgentActionButtonTheme`
   (`DesignTokens.swift:811-890`). Delete the sentence.
2. **Button metrics.** design.md says Primary is "13 **semibold**, min height
   40" and Secondary "13 medium, min height 40". The code is `.agentHeadline`
   (18 semibold) at min height 52 for both (`DesignTokens.swift:815-817`,
   `:868-871`), and 13/44 for the two quiet variants. **Chey needs to pick the
   number** before the document is rewritten — this is the one item in this
   list where "code wins" would settle a design question rather than record
   one. Flagged in L1-09.
3. **`AgentActionButtonTheme` uses a bordered fill.** design.md describes
   Primary as "ink @ 9% background" with no border; the code adds a 1 pt
   `agentBorder` stroke to every tier (`DesignTokens.swift:820-823`). Document
   the border.
4. **Two sanctioned exceptions to the "one desktop modal footprint" hard
   rule** exist in code and not in the document:
   `DesktopLayoutPolicy.creationHubMenuMetrics = 600 × 560`
   (`DesktopNavigation.swift:137`) for the Quick Add choice card, and
   `cyReviewModalMetrics = 1180 × 860` (`:126`) for the Cy review workspace.
   Both carry explanatory code comments, so both look deliberate. Add them to
   the hard rule as named exceptions.
5. **`AgentRadius.structural` (8) exists** alongside `.control` (8)
   (`DesignTokens.swift:67-68`) and is not in design.md's radius table. Either
   document it or delete it — two token names for one value invites drift.
6. **`Color.agentFocusControl`** (`DesignTokens.swift:475`) and
   `Color.agentWarmWhite` (`:466`) are shipping palette entries with no row in
   design.md's colour table. `agentFocusControl` tints a control at
   `WeeklyFocusView.swift:919` where every other toggle in the app uses
   `actionAccent`; document it or fold it into `actionAccent`.
7. **The botanical refresh never landed in Swift.** design.md's footnote † says
   the semantic set moved to moss / ochre / dusk and that "the Swift constants
   in `AgentColorPalette` still hold the old forest/marigold values until the
   app is updated." That is still true, and there is still no
   `--color-scheduled` equivalent in Swift. Either ship the values or mark the
   refresh as not-for-beta so the document stops describing colours the app
   does not have.
8. **`AgentPageRail` is reused.** design.md's Components list does not mention
   it at all, and the inventory calls it a one-off; it is in fact the shared
   tab-root header at six call sites. Add it to the Headers line beside
   `EditorialHeader`.

---

## 7. Inventory items this pass resolved

- **tasks / pillars / idea-bank tab-root headers** — all three use
  `AgentPageRail` (`TasksView.swift:686`, `PillarsView.swift:470`,
  `IdeaBankView.swift:370`). Not bespoke. plan-week is the only bespoke one
  (L1-14).
- **day-agenda's trailing "Save" button** — confirmed, and it is not one site
  but five identical ones plus a sixth variant (L1-04).
- **`WalkthroughPrimaryButtonStyle` / `PaperOnboardingPrimaryButtonStyle`** —
  confirmed solid fills, and capsules, and one carries an accent glow (L1-10).
- **inspiration-review toolbar items** — `.cancellationAction` is text
  "Close" (`InspirationCaptureViews.swift:203`); `.confirmationAction` is a
  bare 24 pt checkmark (`:211`), a family the census did not have (L1-18).

## 8. Not covered by this lane

Reduce Motion, animation curves and durations (L2). Dead or unreferenced views
— `Views/Today/TodayView.swift` renders list content and is not in the page
inventory; that belongs to the dead-code lane. Copy quality beyond the
Cancel/Close/Done collision (L1-16). Contrast ratios were not measured.
Hit targets were verified by reading only where a control's frame was visibly
under 44 pt; the `?` cells in §2 mean *not checked*, not *passing*.
