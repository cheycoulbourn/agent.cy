# L3 · Cohesion and flows lane

Read `docs/refinement/briefs/_common.md` first. Outputs: `docs/refinement/page-purpose.md`, `docs/refinement/flow-map.md`, `docs/refinement/findings-flows.md`.

Chey's words, as the agency project manager: "Would certain pages make sense, or could they be consolidated? Do all of the flows make sense?" and "flows that don't finish or lose state". You recommend; she decides. Nothing is removed or hidden without her yes.

## Page purpose

Read `docs/PRD.md` (three jobs: ideation, creation, execution; navigation section) and `docs/ARCHITECTURE.md`. For every surface in the inventory write: the one-sentence job in the user's words; which PRD job it serves; the one thing only this surface does; which other surfaces overlap it and how; entry points (how many ways a user reaches it); and a recommendation: keep as is / keep but trim (name what is fluff) / merge into <slug> / hide behind a setting, with the rationale, the tradeoff, and what evidence would flip the recommendation. Include a short section on the six-tab phone IA versus the PRD's description and whether Feed, Saved Posts, Brand Cabinet, Creator Session, and Series each earn a top-level or secondary place.

## Flow map

Trace these five journeys step by step through the code (routes, sheets, state, persistence), naming each surface slug and the exit at each step, and what happens on cancel, background, and relaunch mid-flow:
1. Capture to post: Quick Capture idea and post, Voice Spark, shared link via the share extension, "find three ideas" via Cy, through Develop brief and Proposal review into the post editor.
2. Schedule: from the editor and from Plan/Agenda, reschedule, series episode slots, calendar projection.
3. Tasks: create (standalone and post-linked), subtasks, complete, undo, due-date edits, recurring focus.
4. Cy proposal: ask, stream, cancel, error, accept, and the "Expand on this post" chip.
5. MCP review: request arrives, review, approve, reject, and the desktop review view.

## Flow defects

For each place a flow dead-ends, duplicates work, drops state, shows the wrong destination, or leaves the user without a next step, write a finding with reproduction steps. Reproduce each blocker or major on the simulator using the fixture flags where the fixtures allow, or with a focused unit test you write under the scratchpad (not in the repo) that fails on the current code. Cite the evidence. If a defect cannot be reproduced with available fixtures, say exactly which fixture or account state is missing.

## Deliverables

- `page-purpose.md` with the matrix and the consolidation shortlist (each candidate: keep/merge/hide, rationale, tradeoff, flip evidence).
- `flow-map.md`.
- `findings-flows.md` (batch B3).
