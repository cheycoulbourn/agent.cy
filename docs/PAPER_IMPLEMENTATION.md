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
- Inline add actions use the shared `AgentAddActionRow` treatment and 15-point medium Inter. The plus mark, spacing, and type do not change by screen. Full-width primary creation or save buttons remain a separate control class.
- Resting content is flat or separated by a solid hairline. Shadows are reserved for floating controls.
- The native liquid-glass tab bar, sheets, and menus are preserved. Non-Cy tabs use thin, unfilled monochrome symbols; the Cy asterisk and separate `+` chip retain their branded forms.

## Information architecture

The six phone tabs are Home, Plan, Tasks, Pillars, Idea Bank, and Cy. The separate `+` chip opens a creation hub for ideas, posts, tasks, three-angle ideation, and Idea Bank. Cy owns persistent global conversation and contextual recommendations. Feed and Saved Posts remain separate Catalyst destinations rather than phone tabs.

Today is the warm daily home. Agenda owns weekly planning. Briefs lead with title, duration, hook, script, and ending; secondary production and strategy fields remain collapsed until requested.

Tasks are never inferred from posts. `Pillar tasks` and `Production` are separate lanes; tasks have explicit status, date, and priority and can progress independently of a post.

Publishing uses destination + format rather than a fixed platform enum. Built-ins are Instagram, TikTok, and YouTube; creators may add custom destinations and formats. Creator Profile also holds manually managed profile links, including multiple owned accounts for the same destination. One account may be the default while every post version can select a different account. Video formats own their duration choices. A post version can be added, edited, scheduled, posted, or deleted independently.

There is exactly one active anchor pillar. Supporting pillars retain their own color and preferred weekdays. Pillar controls stay inline: circle-only color choices, a custom color picker, and one-letter days.

The Settings page and its Paper subpage artboards are canonical for account, assistance mode, appearance, publishing destinations, voice examples, access, export, and destructive erase. Notifications is a first-class Settings destination; Daily focus and Weekly reset live together in its Reminders section.

## Onboarding

Onboarding uses eight focused steps: Welcome, About you, Your vibe, Your content, Where you post, Your AI, Notifications, and Ready. The Welcome screen explicitly introduces Claude and Codex as optional ways to power the creator workflow.

Your AI offers two equal, explicit choices:

- **Agent Cy AI** works natively in the iPhone app without a computer or API key.
- **Claude or Codex** uses the creator's own CLI subscription through the local MCP bridge on a Mac or Windows computer.

The Claude/Codex walkthrough uses numbered plain-language steps and copyable mono code blocks. It shows Not connected, Folder connected, Bridge found, or Connected based on the shared-folder bookmark and the bridge heartbeat. The screen never implies that the iPhone directly authenticates a Claude or Codex account. Setup can be finished later under Settings > AI > Claude & Codex.

## Cy proposal review

- Keep the Cy review intro and count fixed above a vertically scrolling list of proposal cards.
- Proposal cards reuse the calendar post card, including pillar color, post title, platform, date, and the `TO REVIEW` status.
- Opening a proposal shows one polished post review with the complete post, posting details, linked tasks, and an Edit action in the top-right position.
- The creator has exactly one approval decision. A dated new post uses `Approve & schedule`; an undated post uses `Approve draft`. Deny remains secondary.
- A dated new post is created and scheduled atomically. Never show a second scheduling review for the same proposal.
- Direct work completed inside agent.cy does not require Cy review. The review gate applies only to Claude, Codex, and other MCP proposals.
