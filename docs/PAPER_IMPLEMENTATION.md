# Paper implementation guide

Source of truth: [agent.cy Paper design](https://app.paper.design/file/01KP9N9DAM2N8GHSM3P8MF2BS3/7-0)

Paper defines agent.cy's product structure, visual language, interaction priorities, and voice. Native SwiftUI behavior remains authoritative for safe areas, keyboard handling, Dynamic Type, VoiceOver, Reduce Motion, navigation, menus, sheets, and the liquid-glass tab bar.

## Product boundary

The redesign covers creation, ideation, planning, and execution. Connected accounts, analytics, automatic publishing, trend claims, external inspiration, and a repurpose inbox remain deferred. Platform destinations and posting progress are manual.

## Brand and voice

- Personality: a creative strategist friend who is confident, smart, energizing, and creator-native.
- Default line: "Your brand, on autopilot."
- Campaign line: "From scroll to schedule."
- Copy is short, active, and specific. Controls use a verb plus an object.
- Never shame, grade, rush, gamify, or manufacture urgency.
- Cy proposals remain visibly pending until the creator confirms them.

## Color tokens

| Role | Light | Dark | Use |
|---|---:|---:|---|
| Canvas | `#F5F6F3` | `#1A1A1A` | Screen background |
| Surface | `#FDFDFB` | `#141414` | Cards, editors, and elevated content |
| Primary text | `#141414` | `#F5F6F3` | Headlines and body copy |
| Secondary text | `#5C554B` | `#C8BEAA` | Supporting copy with solid accessible color |
| Border | `#6B6151` | `#786F62` | Hairlines and control boundaries |
| Action | `#141414` | `#F5F6F3` | Creator-led primary actions |
| Cy | `#9B3A2E` | `#9B3A2E` | Cy and active AI guidance only |

Terracotta is not a general accent. A creator may intentionally choose it as a pillar color. Text hierarchy never relies on opacity.

## Typography

- Inter Variable: display, title, headline, body, and subtext.
- IBM Plex Mono: metadata, dates, statuses, section markers, and duration labels.
- SF Pro appears only through native system chrome and SF Symbols.
- Display: 32 points, bold, tight tracking.
- Title: 22 points, bold.
- Headline: 18 points, semibold.
- Body: 15 points, regular.
- Subtext: 13 points, regular.
- Mono: 11 points, medium, tracked uppercase when used as a section marker.

All roles scale relative to an iOS text style. Inter Tight is not used.

## Layout and controls

- Spacing follows `4`, `8`, `12`, `16`, `24`, `32`, `48`, and `64` points.
- Radii use 8 points for controls, 16 for panels, 28 for floating surfaces, and capsules where appropriate.
- Interactive targets remain at least 44 by 44 points.
- Resting content is flat or separated by a solid hairline. Shadows are reserved for floating controls.
- The native liquid-glass tab bar, sheets, menus, and floating Cy control are preserved.

## Information architecture

The five tabs are Today, Agenda, Tasks, Pillars, and Spark. Cy remains a separate floating control. Spark contains creation entry points and a searchable Your work section that replaces the former Library tab.

Today is the warm daily home. Agenda owns weekly planning. Briefs lead with title, duration, hook, script, and ending; secondary production and strategy fields remain collapsed until requested.
