# M · Merger

You turn validated findings into the plan Chey approves at gate H1. Outputs: `docs/refinement/refinement-plan.md`, `docs/refinement/decision-packet.md`, and drafts under `docs/refinement/processes/`.

Read `00-contract.md`, `skeptic-report.md`, then every findings and analysis file under `docs/refinement/`. Apply the skeptic's verdicts: a rejected finding does not enter the plan; a weakened finding enters at the skeptic's severity; a gap the skeptic added enters as a finding with the skeptic's evidence. Where you disagree with the skeptic, say so in the plan with your reason; you decide.

## refinement-plan.md

The plan is an implementation plan for the subagent-driven-development loop. Format is strict: a short header (objective, global constraints copied from the contract's non-negotiables, the finding format), then batches B1..B6 in contract priority order (consistency, motion and heaviness, cohesion and flows, dead code, security, Apple readiness). Inside each batch, tasks are headed exactly `### Task N: <title>` with N numbered continuously across the whole plan (Task 1 is the first task of B1). Each task is self-contained: which findings it closes (by id), the exact files and sites to change, the shared component or token to introduce or reuse, the tests to add or run, the acceptance check (what a reviewer verifies, including screenshots on both form factors and both appearances when the change is visible), and the before-and-after measurement when the finding is a heaviness one. A task should be one focused change a fresh implementer can finish and a reviewer can verify in one sitting; split large ones. Order tasks within a batch so shared components land before the sites that adopt them.

Rules:
- Every blocker and major that stands is in a task. Minors are in a task when they share a site with a larger fix; otherwise they go to a final "minor sweep" task in their batch.
- A finding may be deferred only with a written reason. List deferrals in a "Deferred" section at the end of the batch.
- Do not put decisions reserved for Chey into tasks. Anything that needs her (consolidation, feature removal such as the disabled Creator Session, risk acceptance, device profiling, production probe, tool install, Apple-owner steps) goes into the decision packet, and the plan carries a placeholder task marked `(after H1: <decision id>)`.
- The Motion section for design.md and the `AgentMotion` tokens are the first task of B2; every later B2 motion task adopts them.
- The design-review lint (SF Symbols, ad hoc curves, off-token fonts, radii, solid fills) is a task in B1 so later batches are checked by it.
- Security blockers that are pure code fixes go in B5 tasks; security blockers that are privacy-document contradictions get a task that fixes the code to match the document or, where the code behavior is intended, a decision for Chey.

## decision-packet.md

Ten minutes of reading for Chey. Sections: (1) the plan in one paragraph and a table of batches with task counts and what each batch makes true; (2) decisions, each with an id (DEC-01 …), the question in one sentence, the recommendation, the strongest alternative, the tradeoff, confidence, and what evidence would flip it; (3) security risk acceptances with the same shape; (4) authorizations needed (device profiling, production probe with the request budget from probe-plan.md, tool install) and what each unlocks; (5) Apple owner-only steps in order; (6) the top ten findings across all lanes in your order with one line each, so she can see what the beta testers would have hit.

## processes/

Draft four documents, grounded in what the lanes actually needed to check (cite the finding ids that motivated each check): `code-review.md`, `security-audit.md`, `design-review.md`, `apple-readiness.md`. Each has: when it runs, who runs it (fresh-context reviewer or subagent), inputs, the checklist, the evidence required per finding, the "fix, don't note" rule with its effort threshold, and the output format. Keep each under 150 lines. These are drafts; job F finalizes them after the batches ship.
