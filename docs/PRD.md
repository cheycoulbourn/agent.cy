# agent.cy v1 Product Requirements

## Product definition

agent.cy is an iPhone-only creative copilot for adult, English-speaking solo creators who already publish but struggle to turn rough ideas into ready work.

The promise is **From spark to ready**.

The three product jobs are:

1. Ideation: capture a text or voice spark, or ask Cy for three directions grounded in the creator's own context.
2. Creation: develop one direction into a personalized video brief.
3. Execution: schedule, produce, track, and manually publish the work without shame-based mechanics.

## Audience

- Adults 18 and older.
- Emerging solo creators, not teams.
- English-only in v1.
- Three genuine captions, scripts, posts, or transcripts are required before Cy extracts a voice profile, but they are not required to begin creating.
- Short-form destinations are Instagram Reels, TikTok, and YouTube Shorts. Long-form YouTube is also supported.

## Onboarding

Initial flow:

1. Age confirmation, privacy explanation, and optional content-free telemetry consent.
2. Name, primary creator goal, and selected platforms.
3. Assistance mode, defaulting to Collaborate.
4. Add three real voice examples or choose **Add these later**.
5. When three examples are ready, review and edit the voice profile extracted by Cy. When deferred, skip this step.
6. Optional daily-focus and weekly-reset reminder setup.
7. Bring a spark or Find a spark, then complete the first brief.

Pillars and production rhythm are deferred. Cy proposes three to five pillars after three developed briefs.

Examples can be added during onboarding or later in Settings through pasted text, on-device dictation, an Instagram post link kept as local provenance, or editable text recognized from a screenshot on-device. A link alone is not treated as voice evidence. The creator must paste or confirm the corresponding text. Raw screenshots and source URLs are never sent to the AI proxy.

Each confirmed example is limited to 20,000 UTF-16 units, and the confirmed text sent in one creator context is limited to 40,000 UTF-8 bytes in total. The app enforces both limits before saving onboarding evidence and again before any remote request, with a specific amount to trim.

## Assistance modes

All generated changes require explicit acceptance in every mode.

- **I'll drive:** Cy responds only to explicit requests and shows no unsolicited Today guidance.
- **Collaborate:** Cy asks one high-value question, offers one next step, and shows one concise Today recommendation.
- **Lead me:** Cy minimizes questions and prepares complete proposals with visible assumptions.

The global default can be overridden per brief, week, or task flow.

## Ideation and brief creation

Two equal paths create the same Spark-backed brief:

- Bring a spark through text or on-device voice transcription.
- Find a spark by asking Cy for three distinct directions based only on local creator summaries.

Unselected directions disappear unless explicitly saved. Dialogue is capped at eight turns and always offers Compose now.

Creators may also make a lightweight Post from Spark by choosing a title, optional pillar, platform, posting target, notes, and optional first task. The Post remains a Spark until developed; its draft posting target is visible in Agenda without advancing the master lifecycle.

The ready brief contains:

- Premise, audience, goal, takeaway, and assumptions.
- A format-aware duration target. Short-form offers 15, 30, 45, 60, or 90 seconds and defaults to 45. Long-form YouTube offers 3, 5, 8, 10, or 15 minutes and defaults to 8.
- Spoken hook and first-frame text.
- Flexible script with modular beats.
- Close and CTA intent.
- Light setup, shot, B-roll, delivery, edit, audio, and on-screen-text guidance.
- Proposed creator-work tasks.
- Voice confidence.
- Variants only for selected platforms.

Creators edit inline or invoke scoped Ask Cy revisions. Teach Cy proposes visible voice-profile changes for approval.

## Navigation

- Today is the warm daily launch view with a greeting, one focus, content going live today, today's tasks, and quick capture.
- Agenda can move backward or forward one week at a time. Every day separates planned Posts from production Tasks, and pillar colors appear only when assigned.
- Tasks contains all brief-linked and standalone creator-work tasks. Each row shows status, date, and priority, supports left-swipe deletion, and uses full-row separators. Parent tasks may contain independently completable subtasks, which remain out of top-level lists.
- Content placement and task scheduling are separate. A task date never places its linked post on Agenda.
- Pillars contains manual, guided, or inferred themes. Each anchor page edits its color through unlabeled swatches and its assigned weekdays through one-letter controls; branches inherit both. Pillar descriptions are not part of the interface. Unfiled briefs remain valid.
- Pillar detail groups branches, ideas, scheduled work, and posted work, with a manual new-spark action for posted content.
- Spark has one Create entry for ideas, posts, tasks, and on-device voice capture, plus a separate Find three ideas entry. Your work remains searchable and filterable, including archived content.
- Ask Cy opens global context-aware conversation.
- `+` captures an Idea, Post, or creator-work Task without opening chat.

## Lifecycle

`Spark -> Developing -> Ready -> Scheduled -> Posted -> Archived`

- First dialogue or substantive development enters Developing.
- Creator approval enters Ready.
- A target date on a selected platform output enters Scheduled.
- The first posted platform output enters Posted and displays `x of y posted`.
- Removing the final posted state returns to Scheduled when a target remains, otherwise Ready.
- Archive is manual.

Completing the designated filming task emits a content-free `recording_completed` milestone without adding a visible status.
Tasks may be completed while linked content is still a Spark or Developing; task progress never silently advances the content lifecycle.

## Planning and reminders

- Dates are flexible targets, not punitive deadlines.
- Production-rhythm templates are not exposed in the current Agenda experience.
- Week changes remain local unless explicitly saved to the template.
- Missed targets offer move, simplify, pause, or archive.
- Two opt-in local reminders are supported: daily focus and weekly reset.
- A Posted brief offers Create a new spark from this. There is no Repurpose Inbox.

## Access and pricing

The first complete brief is free. Its allowance includes voice-profile extraction, three ideation requests, one eight-turn dialogue, one composition, three scoped revisions, and one Teach Cy update. The included dialogue is scoped to developing the free first Spark; global Ask Cy requires trial, paid, or promotional access.

Public paid pilot:

- 14-day App Store trial after the first brief.
- $8.99 per month, monthly only.

Expired creators may finish and edit existing work, complete existing tasks, update posting status, export, and erase. They cannot create new sparks, briefs, tasks, schedules, or Cy requests.

## Explicitly deferred

- Platform OAuth, analytics, and publishing.
- Live trends and external inspiration ingestion.
- Teams and brand-deal management.
- iPad, Mac, Android, web, and localization.
- General personal task management.
