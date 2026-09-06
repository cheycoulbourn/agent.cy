# Agent.cy Design System

> **Status: Canonical.** This is the repository-wide source of truth for
> agent.cy visual design and interaction decisions across iPhone, Mac Catalyst,
> SwiftUI implementation, and Paper explorations.

The rulebook for designing new pages and components. Read this before designing
anything — in Paper, in SwiftUI, or anywhere else. The goal is that a new screen
looks like it was always part of the app.

## Sources of truth

| What | Where |
|---|---|
| Colors (OKLCH) | `ios/AgentCyShared/AgentOKLCH.swift` (`AgentColorPalette`) |
| Spacing, radii, type, components | `ios/AgentCy/Design/DesignTokens.swift` |
| Paper design tokens | Paper file **"agent.cy design system"** (mirrors the Swift values 1:1) |
| Paper file layout | Four pages (reorganized 2026-08-14): **Design System** (sheet + Control Center master), **Control Center** (widget directory + canon), **Desktop App** (all 1280-pt boards, 3-col grid: core screens → drill-downs → Quick Add forms), **Mobile App** (all 375-pt boards in matching rows). New boards go on the form-factor pages — never new per-feature pages. |
| Icons | Licensed Nucleo UI outline set, via `AgentIcon` / `AgentIconView` — never raw SF Symbols in new designs |

If this document and the code ever disagree, the code wins — then fix this document.

## Personality

Warm paper, quiet ink, one decisive accent. Agent.cy should feel like a calm
editorial planner, not a dashboard. Three adjectives: **grounded, editorial, unhurried.**

Design inspiration (approved 2026-08): **Todoist** for list structure and accent
discipline; **Atoms** for the pillar distribution-bar mechanic only (not its colors);
**Retro** for the week-grouped social grid. We borrow structure from these apps,
never their palettes.

## Color

Everything is OKLCH. Light and dark are both first-class — never design a screen
in only one mode.

| Role | Swift | Paper token | Light | Dark |
|---|---|---|---|---|
| Canvas (page ground) | `Color.agentCanvas` | `--color-canvas` | `oklch(97.16% 0.0041 121.56)` | `oklch(21.78% 0 0)` |
| Surface (cards, sheets) | `Color.agentSurface` | `--color-surface` | `oklch(99.35% 0.0026 106.45)` | `oklch(19.13% 0 0)` |
| Ink (primary text) | `Color.agentText` | `--color-ink` | `oklch(19.13% 0 0)` | `oklch(97.16% 0.0041 121.56)` |
| Secondary text | `Color.agentSecondary` | `--color-secondary` | `oklch(42.21% 0.0111 78.21)` | `oklch(84.31% 0.0118 84.58)` |
| Border (controls) | `Color.agentBorder` | `--color-border` | `oklch(88% 0.0068 115.72)` | `oklch(34.07% 0 0)` |
| Hairline (row dividers) | `Color.agentHairline` | `--color-hairline` | `oklch(92.58% 0.0068 115.71)` | `oklch(29.72% 0 0)` |
| Selection/hover fill | `Color.agentSelectionFill` | `--color-selection` | ink @ 5.5% | ink @ 5.5% |
| **Cy accent** | `Color.cyAccent` | `--color-cy` | `oklch(48.23% 0.1323 29.75)` | same (use `--color-cy-text-dark` for text: `oklch(62.2% 0.1447 29.73)`) |
| Cy as text/label | — | `--color-cy-text` | = Cy accent | `--color-cy-text-dark` |
| On-accent text | `Color.onCyAccent` | `--color-on-cy` | near-white | near-white |
| Success | `Color.agentSuccess` | `--color-success` | `oklch(50% 0.09 150)` moss † | `oklch(72% 0.1 150)` † |
| Destructive | `Color.agentDestructive` | `--color-destructive` | = Cy accent | `oklch(60.36% 0.1447 29.73)` |
| Priority high | `Color.agentPriorityHigh` | `--color-priority-high` | `oklch(66% 0.145 70)` ochre † | `oklch(76% 0.13 75)` † |
| Priority as text | — | `--color-priority-text` | `oklch(56% 0.145 70)` † | use dark fill value |
| Scheduled / info | — (new) | `--color-scheduled` | `oklch(50% 0.09 300)` dusk † | `oklch(72% 0.09 300)` † |

† **Botanical refresh, approved 2026-08:** the semantic set moved to muted garden
hues (moss / ochre / dusk violet) and gained a dedicated scheduled/info color.
The Paper tokens carry the new values; the Swift constants in `AgentColorPalette`
still hold the old forest/marigold values until the app is updated. When
implementing, also use the darker `priority-text` value for colored metadata
text — the ochre fill tone is too light for 11-pt text on paper.

**Accent colorway note (2026-08-14):** a bright-cobalt rebrand was explored on
the "Brand · Accent colorway explorations" board in Paper and **rejected** —
the brand stays brick red. Do not re-propose blue/cool accents. The accent now
appears only as tints, marks, glyphs, and text (see Accent discipline), never
as a solid fill, which was the actual complaint behind the exploration.
| Cy panel (dark callout) | `AgentColorPalette.cyPanel` | `--color-cy-panel` | — | `oklch(23.23% 0.0149 32.68)` |

### Accent discipline (the Todoist rule)

The Cy accent is the **one** decisive color moment per screen. It may appear on:

1. The selected state of exactly one control (e.g. selected date, nav indicator)
2. The Cy brand asterisk and accent-colored text links
3. Destructive actions (tint + text — the alarm reading is intentional)

It does **not** appear on buttons otherwise: because the accent doubles as the
destructive color, red on any non-destructive button reads as an error state
(decided 2026-08-14). Primary actions are a neutral ink tint instead — see
Buttons.

It may **not** appear on secondary buttons, decorative elements, multiple
competing controls, or as a background wash. If a screen has two accent-colored
elements that aren't the same action, remove one.

**No solid accent fills, anywhere** (decided 2026-08-14, enforced by
`scripts/check_design_review.sh`): the accent shows up as tints (~10% opacity
washes), thin marks (selection bars, dots), colored glyphs, and colored text —
never as a filled color block. This includes the floating Cy button. Solid
fills read as jarring against the paper canvas; boldness comes from the hue,
not from area of coverage. The one accent-worthy action per Cy surface is the
quiet accent action (`cy @ 12%` tint, brick label — see Buttons), never a fill.
The lint's `accent_control_fill` and `accent_shape_fill` rules stand at zero; a
genuine brand *mark* (an unread dot, a count badge, a 7-pt timeline dot, the
walkthrough coach mark) opts out in the source with
`// design-review-allow: accent-mark -- <reason>`, which is the complete list of
places a solid brand fill is allowed to exist. `accent_control_fill` reads the
whole `background(` argument list whatever the shape, `accent_shape_fill` covers
**ink as well as brick** and sees the multi-line `.fill(` form, and neither
matches an `.opacity(...)` tint.

**Cy's identity disc is chrome plus a glyph, never a brick disc.** Every round
Cy avatar — the Pro upsell's 86-pt hero, the Access and AI-connection 48-pt
avatars, the MCP bridge's 42-pt Local Cy and 48-pt connection discs — is
`AgentCyDisc`: a `Color.agentSurface` circle with the same 0.75-pt `agentBorder`
hairline `agentSurfaceChrome` draws, carrying the brick glyph (`CyAsterisk`, or
a Nucleo glyph in `cyAccent`). A large brick disc is a fill however
identity-shaped its intent; the disc is the chrome and the brick is the mark
inside it. Where a disc carries state (the MCP bridge), the **glyph** changes
colour — brick when live, `agentSecondary` when not — and the disc does not.
Gradients are not a way around this: a `LinearGradient` of the accent is still a
fill, and design.md bans gradients as decoration regardless.

**Creator Session selections (decided 2026-08-16):** mode choices use a quiet
neutral selection fill, a darker structural border, and one Nucleo check. The
duration control uses native draggable hour and minute wheels, with no red
selected state. Start Session is the single primary action and uses neutral
ink; active timer progress uses ink as well. The circular close control sits
inside a 72-point header with 12 points of extra top placement so it never
crowds the screen edge.

### Pillar colors

Pillar colors come from the app's existing **`CreatorVibePalette`** sets
(`ios/AgentCy/Models/DomainTypes.swift`) — nine named palettes (Stone, Soft Girl
Era, Aesthetica, Vivrant Thing, (not) Vivrant Thing, Midnight, Soho, Too Cool,
Scraper). Onboarding offers Soft Girl Era, Aesthetica, Soho, and Too Cool; the
full library lives in Settings, and users can still pick any custom hex. These
palettes are settled — do not redesign them. All nine are documented on the
design-system artboard in Paper.

Pillar colors are data, not chrome. They appear only as small marks:
`PillarColorMark` dots, checkbox tint, chips, and segments of the pillar
distribution bar. Always run them through `PillarVisualContrast` /
`AgentChipContrast` so they stay legible in both modes. Fallback hex: `5D6B58`.

**Dividers on tinted surfaces are dynamic** (decided 2026-08-14): inside a
pillar- or semantic-tinted card (details cards on post/task/idea/pillar
views), never use the neutral `--color-hairline` — it vanishes against the
tint. Derive the divider from the card's own accent at ~40% opacity (the
same hue the tint and border already use, via `PillarVisualContrast` in
code). Rule of thumb: tint fill ~8–10%, border ~40–45%, divider ~40%.

### Row metadata color

Inside a list row, color appears only in the metadata line (due dates,
schedule state) and in the pillar mark — never on the row title. Row titles
are always ink.

## Typography

Inter everywhere (`InterVariable` in the app, "Inter" in Paper). No second
typeface. Seven levels — every text element must map to exactly one:

| Level | Swift | Size / weight | Paper tokens | Use |
|---|---|---|---|---|
| Display | `.agentDisplay` | 32 bold, tracking −0.64px | `--text-display` | Page mastheads (`EditorialHeader`) |
| Brief title | `.agentBriefTitle` | 28 semibold | `--text-brief-title` | Post/brief titles |
| Title | `.agentTitle` | 22 bold | `--text-title` | Section titles, sheet titles |
| Headline | `.agentHeadline` | 18 semibold | `--text-headline` | Card headings, button labels |
| Body | `.agentBody` | 15 regular | `--text-body` | Everything readable |
| Subtext | `.agentSubtext` | 13 regular | `--text-subtext` | Secondary rows, compact labels |
| Metadata | `.agentMetadata` | 11 medium, UPPERCASE, tracking +1.4px | `--text-metadata` | `MetaLabel` eyebrows, statuses, dates |

Rules:
- Hierarchy comes from **weight and the three text colors** (ink / secondary /
  secondary-at-reduced-emphasis), not from inventing new sizes.
- Uppercase tracked metadata (`MetaLabel`) is the signature move for section
  eyebrows — use it instead of bold sub-headers.
- Numbers that align in columns (counts, dates, durations) use `.monospacedDigit()`.
- Date-group headers (Agenda, Tasks) are the Todoist pattern: `MetaLabel`-style
  eyebrow or subtext-semibold line, e.g. "THU · AUG 13 · TODAY", sitting on a
  hairline rule (`SectionRuleHeader`).

## Spacing & layout

4-pt non-linear scale — never use in-between values:
`x1 4 · x2 8 · x3 12 · x4 16 · x5 20 · x6 24 · x8 32 · x12 48 · x16 64`

| Constant | Value | Meaning |
|---|---|---|
| `AgentLayout.pageMargin` | 24 | Page/header inset |
| `AgentLayout.dashboardGutter` | 12 | Outer gutter around dashboard surfaces |
| `AgentLayout.pageHeaderToContentSpacing` | 32 | Header → first surface |
| `AgentLayout.sectionHeadingSpacing` | 8 | Section eyebrow → content |
| `AgentLayout.bottomNavigationClearance` | 120 | Clearance above floating nav (phone) |
| `AgentQuickAddLayout.desktopContentWidth` | 620 | Quick Add drill-downs |
| `AgentQuickAddLayout.desktopEditorWidth` | 680 | Desktop editors |
| `DesktopLayoutPolicy.workspaceModalMetrics` | 900 × 860 | Every desktop Quick Action modal and Settings |

Layout rules:
- **Lists are flat** (the Todoist rule): rows sit directly on the surface with
  hairline dividers. Do not wrap each row in its own card. Cards are reserved
  for genuinely elevated things: dashboard surfaces, Cy callouts, sheets,
  floating controls.
- Group with proximity, not boxes. Section gap 32–48, intra-group gap 8–16.
- Every screen uses `agentScreen()` (canvas ground) and, if it's a dashboard
  surface, `AgentDashboardSurface` with `AgentRadius.dashboard`.
- Touch targets ≥ 44×44 pt, always; dense desktop (Catalyst) controls may go
  down to 40 pt but never below. Checkbox rows use the horizontal-only hit
  expansion (`AgentTaskCheckbox`) so adjacent 44-pt rows don't collide, and
  hit areas of neighboring controls must never overlap.

## Radius & elevation

| Token | Value | Use |
|---|---|---|
| `AgentRadius.control` / `--radius-control` | 8 | Inputs, hover fills, block add buttons |
| `AgentRadius.button` / `--radius-button` | 10 | **All standalone buttons** (primary, secondary) |
| `AgentRadius.card` / `--radius-card` | 12 | Cards |
| `AgentRadius.panel` / `--radius-panel` | 16 | Inset surfaces, sheets |
| `AgentRadius.dashboard` / `--radius-dashboard` | 20 | Dashboard surfaces, Cy callouts |
| `AgentRadius.floating` / `--radius-floating` | 28 | Floating chrome |
| capsule / `--radius-full` | ∞ | Chips, badges, count pills, avatars — **never buttons** (decided 2026-08-14) |

Elevation comes from `agentSurfaceChrome(role:)` — one 0.75-pt neutral hairline
plus layered ambient shadows. Four roles only: `structural` (no shadow),
`card` (0 4 12 @ 4.5%), `floating` (two layers), `walkthrough` (two layers,
strongest). Never invent a new shadow.

## Materials — Liquid Glass

The app uses iOS 26 Liquid Glass for interactive chrome, and it stays. Four
canonical shapes, all documented on the Paper design-system artboard:

| Shape | Swift | Where |
|---|---|---|
| Circular toolbar icon (44 pt, 17 pt glyph) | `AgentToolbarIconButton` / `AgentToolbarIconLabel` / `AgentToolbarIconContainer` | Every icon control that leaves or acts on a screen: close, back, save, add, refresh, spark |
| Floating bar (radius 28 = `AgentRadius.floating`) | `.glassEffect(.clear, in: .rect(cornerRadius: AgentRadius.floating))` | Ask Cy input bar, DevelopBrief bar |
| Bottom-nav pill cluster | `GlassEffectContainer` + per-segment `.glassEffect` | `AppShellView` navigation |
| Segmented selector rail | Native `Picker` + `.pickerStyle(.segmented)` | Agenda view rail, Tasks `Focus Tasks / Post Tasks` rail, and every peer-view selector rail |

Sheet/overlay backgrounds use `.ultraThinMaterial` (`presentationBackground`,
media-overlay circles).

Rules:
- Glass is reserved for **floating chrome above content** — never for content
  surfaces (cards, lists, sheets' bodies). Content stays on opaque paper.
- **One circular icon control.** There is exactly one glass circle: 44 pt,
  17 pt glyph, `pureWhite@0.22` hairline, built by `AgentToolbarIconContainer`
  in `DesignTokens.swift`. Close, back, save, add, refresh, and spark are all
  that control; it never gets a per-screen shadow, a second diameter, or a
  second glyph size. `AgentDesktopDetailBackButton` is its only desktop
  substitute. Every circular `glassEffect` in the app goes through
  `.agentGlassCircle()`, and `scripts/check_design_review.sh` fails the build
  if another file writes one (rule `glass_circle`, baseline 0).
- **Hard design rule — selector rails:** every compact horizontal rail that
  switches between peer views, modes, or collections **must** use the native
  iOS 26 segmented `Picker`, so the system renders it as Liquid Glass. The
  Agenda rail is the canonical reference; the Tasks `Focus Tasks / Post Tasks`
  rail must remain identical in construction. Never replace this pattern with
  `.ultraThinMaterial`, an opaque capsule, a custom `HStack`, or hand-built
  `.glassEffect` segments. An exception requires an explicit new design
  decision before implementation. In Paper, label these rails as native Liquid
  Glass rather than treating the translucent mock fill as the implementation.
- Each glass element keeps the standard chrome: 0.5 pt white highlight stroke
  at ~22–40% and an ambient shadow (`agentSurfaceChrome` conventions).
- **In Paper mocks**, Liquid Glass is approximated with a CSS stand-in —
  `background: oklch(100% 0 0 / 0.16–0.18)` + 0.5px white border at ~40% +
  inset top highlight + ambient shadow (`backdrop-filter` is written for intent
  but Paper's renderer ignores the blur). Treat any element with that recipe as
  "this is `.glassEffect()` in code" — never translate it literally to a flat
  translucent white fill in SwiftUI.

## Media & images

**Post media is a spotlight, not a file list** (decided 2026-08). On post
detail, attached media renders as a swipeable viewport at the post format's
true aspect ratio (9:16 for Reels, 4:5 for feed) — a preview of what the post
will actually look like. Never show file names, dimensions, or upload-style
rows on the detail view; that metadata belongs in the edit flow only.
- Desktop: the viewport sits top-right beside the title block ("star of the
  show"), ~200 pt wide, `--radius-card`, 1-px pure-black 10% outline, with a
  count pill ("1 / 3", black-58% capsule, top-right), swipe dots
  (bottom-center, white/white-45%), and quiet text actions beneath:
  "Edit | Add" — words only, separated by a 1-px hairline divider, no
  icons (decided 2026-08-14).
- Phone: the same viewport runs full-width directly under the title and
  swipes horizontally.
- No media → no placeholder; the title block takes the full width and the
  page looks exactly like a text-only post. Add/edit lives in the editor.
- **Cover + full-res in/out:** one media item is the designated cover
  (thumbnail) — uploadable separately from the content, marked with a small
  "COVER" pill (top-left, black-58% capsule) on its spotlight page, and it is
  what the Feed grid tile shows. Uploads always keep the original file
  untouched. Download is an icon-only overlay (28-pt black-58% capsule,
  bottom-right corner of the viewport, mirrored in the ⋯ post menu) that
  hands back the full-resolution original — the publish-time path for
  getting the asset onto the device. Only "Edit | Add" sit as text
  actions beneath the viewport. Compressed derivatives are for previews
  only, never the stored source.
- **Mismatched aspect ratios:** the viewport ratio always follows the post
  format, never the file. Media that doesn't match is center-cropped to fill —
  exactly what the platform will do — with a small "Cropped" pill beside the
  count so the loss is visible, not silent. The full uncropped asset and
  framing controls live in Edit media. Carousel pages all share one frame
  (mixed-shape sources never reshape the viewport mid-swipe), and the ratio
  re-derives live if the post's platform/format changes.

**Saved-post reference thumbnails** (decided 2026-08-14): a saved post is a
reference, not the creator's own post — its media never gets spotlight
placement. The thumbnail lives INSIDE the Reference details card, side by
side with the detail rows, at the top of the page. It is ALWAYS the IG
thumbnail format — 3:4 portrait (`SocialGridLayoutPolicy.tileWidthToHeightRatio`
= 0.75), the same ratio as the social grid tiles: height matches the card,
width derives from the locked ratio, and mismatched sources center-crop. It carries only an icon-only external-link overlay (28-pt
black-58% capsule, bottom-right) that opens the original. No format pill on
the image — format is a card row ("Instagram · Carousel"). Remove lives only
in the ⋯ menu, never as a visible text action.

Every photo/video thumbnail (grid tiles, post previews, attachments) gets a
1-pt inside outline so image edges never bleed into the canvas:
`agentPureBlack.opacity(0.10)` in light, `agentPureWhite.opacity(0.10)` in
dark — always the pure neutrals, never a tinted gray (tint reads as dirt on
the image edge). The social grid already does this
(`SocialGridView` tile overlay); copy that treatment, don't invent a new one.
In Paper mocks: `outline: 1px solid oklch(0% 0 0 / 0.1)` (light).

## Components — use these, don't reinvent

- Buttons — the **quiet system** (decided 2026-08-14; supersedes the capsule
  styles). All buttons are rounded rectangles at `--radius-button` (10), never
  capsules, never solid color fills. Four tiers:
  1. **Primary** — neutral ink tint: ink @ 9% background, ink label
     13 **semibold**, min height 40; one per screen (e.g. "Schedule post").
     Hierarchy over Secondary comes from the slightly deeper fill and the
     heavier label, not from color or darkness. **Never a red/accent fill or
     tint** (red on a button reads as an error state) and **never a solid ink
     block** (too dark and bold) — both decided 2026-08-14.
  2. **Secondary** — ink @ 5.5% fill (`--color-selection`), ink label
     13 medium, min height 40 (e.g. "Save draft", "Save task").
     *On dark surfaces* (Cy callout panel, dark mode): the neutral tint flips —
     primary = white @ 12% with a near-white semibold label (e.g. the
     CyCallout "Show me" action); same 10px corners, still no color fill.
  3. **Block add** — `AgentBlockAddActionButton`, unchanged (see below);
     deliberately the lightest tier.
  4. **Text/icon** — bare label or icon in a 44/40-pt hit area
     (`AgentPressButtonStyle`).
  Destructive actions are the ONLY buttons that may carry red: brick at a
  ~10% tint with `--color-destructive` text — never a filled red button.
  Because destructive shares the brand hue, any red-tinted button
  automatically reads as dangerous; that is intended and reserved.
  The Swift styles (`AgentPrimaryButtonStyle`, `AgentSecondaryButtonStyle`,
  `AgentCyPrimaryButtonStyle`, `AgentQuietDestructiveButtonStyle`) all read
  `AgentActionButtonTheme.radius` and render this rounded-rect family; the
  capsule versions they used to be are gone.
- **Quiet accent action** (`AgentQuietAccentButtonStyle`, decided 2026-09-02,
  closes L1-05) — the one exception to "no red on buttons", and the *only*
  sanctioned brick-hued action: `cy @ 12%` fill, a 0.75-pt `cy @ 40%` border,
  a brick semibold label (`cyAccentText`, so it still clears 4.5:1 in dark
  mode), 10-px corners, and the shared press feedback (0.96 scale + easeOut
  0.12 s, dropped under Reduce Motion). Two label sizes, each matching an
  existing member of the family so an accent action never adds a third button
  height to a screen: `.page` (18-pt semibold, min height 52 — the ink
  primary's footprint) and `.compact` (13-pt semibold, min height 44 — the
  CyCallout action's). `AgentQuietAccentIconLabel` is the circular sibling for
  the icon-only form (Cy's composer send, Cy's inline "add this"); it falls
  back to a neutral surface and border when the action is unavailable, so the
  accent never marks a control the user cannot press.
  **Use it for exactly one action per Cy surface** — the accent-worthy one
  (Start 14-day trial, Upgrade to Pro, Three ideas, Create this post, the
  walkthrough's final step). Every other action on that surface stays ink.
  This is the same treatment as the light CyCallout action, lifted out of the
  callout so screens stop hand-rolling a solid brick capsule each time; on a
  non-Cy surface red still means destructive and stays banned from buttons.
- **Floating Cy button** — a 56-pt **white** (`--color-surface`) circle with a
  1-px pure-black 10% border, ambient floating shadow, and the Cy asterisk
  glyph drawn in the accent. Never a solid accent circle. The circle shape is
  reserved for Cy alone.
- **Spark lives in Cy chat only** (decided 2026-08-14): never place a Spark
  button on page or editor chrome. When the user opens Cy while a post is open,
  Cy offers it contextually — a suggestion chip referencing the open post
  ("Expand on this post"). Page rails carry at most Back / title / primary +
  overflow.
- Press feedback is one system: every custom tappable control uses the
  0.96-scale + easeOut 0.12 s treatment (via a shared button style), not bare
  `.buttonStyle(.plain)` — plain gives only the system dim and feels
  inconsistent next to the scaled controls.
- Icon weight matches text weight: the Nucleo outline set is one stroke weight —
  never mix in icons from another set on the same surface, and pair icons with
  regular/medium text rather than bold labels where possible.
- Add actions: `AgentAddActionRow` (dashed-box + label) inline;
  **`AgentBlockAddActionButton`** for block-level — a first-class system
  component, not a variant. Spec: full-width, visible height 38 pt inside a
  44 pt hit target, `--radius-control` (8), 1 px `agentBorder` stroke,
  `agentCanvas` fill (reads as a quiet cutout on surface cards),
  centered 12 pt `add` icon + UPPERCASE label in `agentSubtext` medium (13),
  both in `agentSecondary`. Same tokens in dark mode. It is deliberately the
  *lightest* action in the hierarchy — quieter than Secondary — so empty and
  end-of-list add affordances never compete with content or the primary
  action. Use it for every "add another X" slot (Add task, Schedule post,
  Add live post, Add pillar, Add partner); never restyle these as filled or
  outlined-bold buttons.
- Headers: `EditorialHeader` (kicker/title/subtitle), `MetaLabel`,
  `SectionRuleHeader`, `AgentInputHeader`.
- Checkboxes: `AgentTaskCheckbox` (+ pillar-tinted border).
- Cy: `CyAsterisk`, `CyAnimatedLogo`, `CyThinkingMark`, `CyCallout`. Cy speaks
  through `CyVoiceHeading` labels.
  **The logo mark is the 8-point asterisk** — four rounded strokes at
  0°/45°/90°/135° (matching `CyAsterisk` in Swift, and the ✳ glyph). Never
  draw a 6-point or other variant. In Paper, give SVG strokes the explicit
  accent color (`currentColor` doesn't resolve in Paper's renderer).
  **CyCallout chrome (decided 2026-08-14)** — the callout **surface-matches**:
  light variant in light mode, dark variant in dark mode (this supersedes the
  old "always the dark panel" rule). No glow — standard ambient shadows only
  (a glow was tried and rejected 2026-08-14; enforced everywhere, not just on
  the callout, by `scripts/check_design_review.sh`'s `accent_glow` rule, which
  stands at zero and has no opt-out). Two variants, both sampled on
  the design-system sheet:
  - *Dark* (`cyPanel` ground): 0.75-pt red border, ambient shadow, full-width
    action in `cy @ 28%` with near-white semibold label.
  - *Light* (`surface` or `cy @ 6%` ground): 0.75-pt `cy @ 40%` border, brick
    eyebrow and asterisk, ink body, full-width action in `cy @ 12%` with
    brick semibold label.
  Both actions: 10px corners, min height 40. The red-hued button, border, and
  tint are **Cy-exclusive chrome** — they mark it as Cy's voice. This is the
  ONE sanctioned red-hued button; on any non-Cy surface red still means
  destructive and stays banned from buttons.
- Empty states: `AgentEmptyState` — every list screen needs one that says why
  it's empty and what goes here.
- Desktop (Catalyst): hover states via `agentHoverRow()` / selection fill only —
  hover feedback is limited to sidebar nav, quick add, and post cards. Use the
  `AgentDesktopDetail*` rail components for drill-downs.
- **Hard design rule — no shadows behind top controls:** desktop drill-downs
  never use the native Catalyst navigation toolbar, because its automatic
  material adds large shadows behind Back, Edit, Save, and overflow controls.
  Use the flat `AgentDesktopDetailRail` family instead. Top controls may show a
  subtle hover fill, but never an ambient shadow, glow, floating white halo, or
  shadowed capsule. Back always uses the Nucleo `AgentIcon.back` asset on the
  same 44/48-pt control geometry as Close and Ellipsis; its shared optical
  scaling must not be bypassed with a raw system icon.
- **Hard design rule — one Back indicator:** every phone Back control, whether
  it comes from a native `NavigationStack` or a custom toolbar, uses the Nucleo
  `AgentIcon.back` asset at the shared 12.8-pt rendered glyph size. Never fall
  back to the SF Symbols chevron or resize Back independently from this token.
- **Hard design rule — one desktop modal footprint:** every modal launched by
  Quick Add and the Settings modal uses the spacious 900 × 860 Cy development
  footprint through `DesktopLayoutPolicy.workspaceModalMetrics` /
  `agentDesktopWorkspaceModal()`. Do not introduce smaller per-flow modal
  sizes; internal scrolling handles content length.
- **Hard design rule — lower phone quick-action controls:** Close, Save, and
  companion controls in phone Quick Action sheets sit in the canonical
  `AgentQuickAddLayout` header: a 72-point control row placed 12 points below
  the safe area. Never pin these controls directly to the safe-area edge or
  use a one-off negative/top offset. Use `agentQuickAddHeaderSurface()` or the
  same shared metrics when a flow needs a custom header.
- **Hard design rule — Creator Session Full Screen is desktop-only:** desktop
  timers may enter a purpose-built, responsive Full Screen workspace that
  preserves the selected theme, interval, pause state, linked post, and modes.
  Its Nucleo Back control exits Full Screen without ending the session. Never
  offer Full Screen on iPhone; the phone timer stays in its standard sheet.
- **Creator Session appearance flow:** keep timer-theme previews off the session
  editor. First-time Start opens a separate swipeable gallery of the three
  timer screenshots. After a default exists, Start uses it immediately. A
  bottom settings icon reopens the same gallery on both phone and desktop.
- **Active Creator Session persistence:** after the Creator Session sheet or
  desktop timer closes, show a compact liquid-glass countdown pill centered
  above the phone navigation rail and a matching centered desktop pill. Tapping
  it returns to the same running session; dismissing the timer never ends it.
- **Creator Session Live Activity brand:** the Lock Screen and every Dynamic
  Island presentation use the circular Cy asterisk instead of a mode glyph.
  The Lock Screen countdown is visually primary and the Nucleo Stop action is
  always contained in a clear circle.
  Motion must respect Reduce Motion and Always-On display behavior. Because
  WidgetKit caps Live Activity animations at two seconds, the mark may make a
  slow partial turn on state updates but must not fake a continuous spin.
- **Control Center (desktop utility column)** — one canonical spec (refactored
  2026-08-14; master sampled on the Design System page in Paper):
  344-pt surface column, 1-px hairline left border, 24/16 padding, 16-pt gap
  between cards. Header row: "CONTROL CENTER" metadata + "Edit". Quick add is
  a white radius-16 card (32-pt tinted + circle, ⌘N). Every widget shares ONE
  anatomy: canvas radius-16 card, 16-pt padding, 12-pt internal gap; header =
  eyebrow (metadata uppercase) left + count (13 medium secondary) right —
  never a second headline line; content rows at 44-pt min height; footer =
  hairline + "View all →" 40-pt row. Contextual widgets (e.g. POST TASKS,
  SCHEDULE on post detail) use the same anatomy with contextual content.
  The full widget catalog lives on the **"Control Center" page in Paper**:
  a directory board (every widget with its tier — DEFAULT ships out of the
  box, CONTEXTUAL swaps in per page, OPTIONAL lives in the Edit picker) and
  a canon board rendering each one. Optional widgets: Pillar usage, Needs a
  new date, Cy noticed, Week at a glance, Consistency, Recently posted,
  Drafts in progress, Brand cabinet, Weekly focus. The column always holds
  Quick add + three widgets; the Edit picker chooses which three.

## Approved surface patterns

- **Agenda / Tasks** — Todoist structure: flat date-grouped list, date-group
  header on a hairline rule, overdue section pinned on top, a single primary
  action (tinted, per the quiet button system).
- **Pillars** — Atoms mechanic with our colors: a proportional segmented bar
  showing each pillar's share of the planned week (pillar colors as segments,
  `--radius-full` ends, min segment width 4 pt), with dot-labeled rows beneath
  (`PillarColorMark` + name + percentage in `.monospacedDigit()`).
  **Pillar hierarchy (decided 2026-08-14):** one pillar is the **anchor
  pillar** — it targets **40–50%** of the planned week — and every other
  pillar is a **secondary pillar** filling the remainder. The UI always
  expresses this hierarchy with exactly these names: the Pillars list groups
  rows under "ANCHOR PILLAR" (with the "Targets 40–50% of the week"
  reference) and "SECONDARY PILLARS" section headers, the pillar detail
  eyebrow names the role ("ANCHOR PILLAR · …"), and the percentages are
  always labeled **"Pillar usage"** — the metric name for a pillar's share
  of the planned week (the root card eyebrow is "THIS WEEK'S PILLAR USAGE";
  the detail stat is "PILLAR USAGE"). They stay visible everywhere as the
  reference number. The anchor is first in the distribution bar. Compact Pillar
  Usage widgets name the anchor pillar and show each used supporting pillar as
  a distinct color + percentage; unused 0% pillars are omitted. The segmented
  bar subtracts every inter-segment gap from its available width, stays clipped
  to its track, and must end at the same inset as the header and footer. Every
  Pillar Usage surface uses the same Monday-through-Sunday set of unique posts
  with scheduled or posted outputs in that week. Saved posts, ideas, draft or
  ready outputs, work dates, and assigned weekdays never affect the percentage.
- **Social grid** — a truthful, read-only preview of the profile: 3-column
  full-bleed tiles (3-pt hairline gaps, 3:4 ratio, 1-pt image outlines), white
  status pills on a black-58% capsule with the day badge. **No manual
  reordering** (decided 2026-08): tile position must always equal real posting
  order — live posts are fixed by publish time, and planned posts move only by
  rescheduling (tap the tile → post detail → Reschedule). Never add a cosmetic
  arrange mode that lets the preview diverge from reality.
- **Desktop voice-recording rows** — use the stable warm off-white
  `Color.agentWarmWhite` surface with a darker 22%-black border and structural
  chrome. They never cast a shadow. This contrast treatment is desktop-only;
  the phone recording experience keeps its existing adaptive surfaces.
- **Day agenda header (desktop)** — the day focus and its pillar live in ONE
  surface card, never two (decided 2026-08-14): left zone = date eyebrow +
  day-focus title + subtitle; 1-px hairline vertical divider; right zone
  (fixed ~180 pt, vertically centered) = "PILLAR" eyebrow, `PillarColorMark` +
  name, assignment line. Detail headers across post/task/pillar/idea views
  share the same rhythm: 32 pt below the rail, 8-pt gaps inside the
  eyebrow/title/subtitle group, then a full 40 pt before the next group
  (details card, media, sections) — the title zone must clearly read as its
  own block.
- **Settings** — desktop is a two-pane modal (240-pt canvas nav rail with
  MetaLabel section groups and one selected row — selection fill + accent
  bar; the "Reset & erase" row and its selection use destructive styling);
  phone uses the back-chevron subpage pattern. Toggles are ink track / white
  thumb (border track when off) — never a color. Destructive pages: warning
  card in destructive tint + border, actions as destructive-tinted buttons
  ("Reset…", "Erase…"), never filled red. **Weekly focus assigns each day
  named focuses** — a focus day is never just an on/off toggle. Expanding
  a day row reveals two sections: (1) a "Focus · choose up to 2" chip
  picker (8px-radius chips: selected = ink@9% fill + semibold ink,
  unselected = border + secondary medium) — up to **two** focuses per day,
  and the same focus may repeat across days to split it up; a two-focus day
  reads "Scripting · Filming" in its collapsed row. **Scripting and
  Filming are separate focuses** (default vocabulary: Planning, Scripting,
  Filming, Editing, Community & engagement, Rest — chips may shorten
  "Community & engagement" to "Community" to keep one line), and the chip
  row always ends with a dashed **"+ Add"** chip (dashed border, secondary
  text, plus glyph) for creating a custom focus. (2) a "Repeats every [day]" sub-list of that day's
  recurring tasks (checkbox rows with times) plus a bordered block "Add
  recurring task" affordance — tasks can be pre-filled by the focus or
  added by the user, and repeat on that day every week; Cy drops them onto
  the day's agenda automatically (this is where the Day agenda's
  pre-filled production tasks come from). **Changing a day's focus clears
  its recurring tasks entirely** — state this rule inline as a metadata
  footnote near the picker. **Form-factor split:** desktop expands the day
  inline inside the list (it has the width); the phone never nests the
  picker between list rows — the Weekly focus screen stays a calm 7-row
  drill-in list (day name left, focus values in secondary 13-pt right,
  chevron-right) and tapping a day opens a dedicated day page ("Phone ·
  Day focus" board): back-chevron header with the day name, hint line,
  then two eyebrow-labeled section cards — FOCUS (chip picker) and
  REPEATS EVERY [DAY] (task rows + a quiet "+ Add recurring task" row
  inside the card).
- **Phone detail views** (Task / Pillar / Idea / Saved post boards) — shared
  anatomy: back-chevron header (centered title, "Save" or ⋯ trailing),
  then eyebrow → title (22 bold) → subtitle with 10/8-pt gaps, 28 pt to
  the tinted details card, 32 pt between sections. Sections use hairline-
  underlined eyebrows with a trailing count; list rows 50–58 pt; block-add
  affordances stay inside their section. Desktop's side-by-side note pairs
  (Plan/Repeat, Hook/Structure) stack vertically. The saved-post reference
  thumbnail keeps its 3:4 ratio inside the details card (≈96×128) with the
  icon-only external-link overlay. Screen-level primary actions ("Create
  post", "Shape into idea") become a full-width quiet-primary button at
  the bottom, 36 pt below the last section.
- **Cy chat** — keeps its identity: dark `cyPanel` chrome, `CyVoiceHeading`
  eyebrows, animated asterisk. Don't lighten it to match the paper canvas.
  When a post is open, Cy leads with a contextual suggestion chip for it
  (Spark / "Expand on this post") — that is the only place Spark appears.
- **"On your plate" digest card** (approved 2026-08-14, sampled on the mobile
  Ask Cy board) — Cy's greeting-state summary: light CyCallout chrome
  (`cy @ 6%` ground, 0.75-pt `cy @ 40%` border, no glow), "ON YOUR PLATE"
  eyebrow in brick, then a compact count list (count in brick metadata,
  hairline-separated rows: "1 · Post needs a new date"), closing with one
  contextual question from Cy ("The date for X has passed. Want to choose a
  new one together?") with a chevron. It's a digest, not a dashboard — counts
  and one question, never widgets. Use it in both Ask Cy surfaces (phone and
  desktop sheet).

## Every new screen must have

0. **Both form factors in the same pass** (decided 2026-08-14): a surface or
   change is not done until the phone version is refined and finalized
   alongside the desktop version. Never ship a desktop-only board.

1. Light **and** dark mode, checked at both.
2. All interactive states: default, pressed (0.96 scale + easeOut 0.12s),
   disabled (42% opacity), and on desktop, hover where the hover policy allows.
3. An empty state (`AgentEmptyState`).
4. Reduce Motion honored — every animation gated on `accessibilityReduceMotion`.
5. Accessibility labels on icon-only controls; decorative icons hidden.
6. Text contrast ≥ 4.5:1 for anything below 18 pt (use `AgentChipContrast`
   where color is dynamic).

## Don'ts

- No new colors, sizes, radii, or shadows outside the tokens.
- No per-row cards in lists; no boxes around things proximity can group.
- No second accent competing with Cy on the same screen.
- No solid accent fills and no capsule-shaped buttons — accent is tint, mark,
  glyph, or text; buttons are 10-px rounded rectangles. The one brick-hued
  action is `AgentQuietAccentButtonStyle`, and it is a 12% tint, not a fill.
- No accent glow, anywhere — `shadow(color: …cyAccent…)` is banned outright and
  linted at zero.
- No Spark (or other Cy actions) on page chrome — Cy offers them in chat.
- No pure black / pure white text or backgrounds outside `pureBlack`/`pureWhite`
  utility uses (shadows, overlays).
- No SF Symbols in shipped UI — map through `AgentIcon`.
- No gradients as decoration; no borrowed palettes from inspiration apps.

## Paper workflow

When designing new pages in Paper (file: "agent.cy design system"):
- Use the tokens via CSS variables (`var(--color-canvas)` etc.) — they mirror
  the Swift values exactly. `-dark` variants exist for dark-mode artboards.
- Design phone screens at 375 wide, desktop at 1280.
- When handing a design back to code, translate token names Paper → Swift using
  the tables above; never eyeball values off screenshots.
