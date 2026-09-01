# Agent.cy pre-beta refinement: the contract

Approved by Chey on 2026-09-01. Every job in `docs/refinement/` reads this file first. No job may redefine the objective, reorder the priorities, or narrow the scope. Only Chey can.

## Objective

Agent.cy feels polished, light, consistent, and coherent, so the first beta testers have a pleasant experience. Four repeatable processes (code review, security audit, design review, Apple readiness) keep that quality as the app changes.

## Terminal deliverable

1. Four processes committed to the repo as documents plus repo-local Claude skills.
2. A first refinement pass shipped as commits: consistency, motion, heaviness, cohesion and flow fixes, and dead code removed.
3. A beta-readiness report naming what remains and who owns each item.

## Success means

- Every screen and sheet passes one design-consistency checklist: one close control, one header pattern, tokens only, light and dark, phone and desktop.
- One motion vocabulary in `design.md` and code. No ad hoc curves or durations remain. Reduce Motion honored everywhere.
- No hang above Instruments' hang threshold on Chey's iPhone in the core journeys. Heaviness causes are measured before and after, not guessed.
- Each page has a one-sentence job it visibly serves. The five core flows complete and survive relaunch.
- No unreferenced code or assets. Security findings fixed or explicitly accepted by Chey. Apple readiness blockers listed with owners.

## Optimize for

Felt quality on Chey's iPhone. Not document completeness. Not speed.

## Priorities (in order)

1. Design consistency
2. Motion and heaviness
3. Cohesion and flows
4. Security
5. Apple readiness

## Non-negotiables

- Brick red stays and appears only as marks, tints, glyphs, and text. No solid accent fills.
- Buttons are quiet ink tints with 10 pt corners. Never solid fills, never pills.
- Every change lands on phone and desktop (Catalyst) in the same pass.
- Reduce Motion honored on every animation.
- No SF Symbols in shipped UI; icons go through `AgentIcon`.
- `design.md` is canonical; where code and document disagree, code wins and the document is fixed.

## Rectify, don't note

A finding that can be fixed inside its batch is fixed there. A finding may be deferred only with a reason Chey can read. Every deferral appears in the beta-readiness report. A document-only outcome is not done.

## Scope

- iPhone ships. Mac Catalyst stays internal per ADR 0012 but is refined alongside.
- Security covers the iOS app, the Fastify server, the MCP bridge, and the deployed Railway proxy.

## Non-goals

Mac App Store, iPad, new features, palette changes, removing or hiding a page without Chey's decision.

## Authoritative context

- `design.md`, `ios/AgentCy/Design/DesignTokens.swift`, and the code itself.
- `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/adr/0012-catalyst-maintained-internal-scope.md`.
- Untrusted until re-verified: everything under `docs/archive/audit-2026-08/`. Those records may seed a finding but never supply its evidence.

## Decisions that stay Chey's

Which pages consolidate (the graph recommends; nothing is removed or hidden without her yes). Anything that changes the PRD. Profiling on her iPhone. Probing the production proxy (needs ownership confirmation and a request budget). Accepting any security risk. Dependency upgrades with breaking changes. The beta go.

## Chey's named concerns

- The app feels heavy.
- Design details are inconsistent. Her example: is every close button the same Liquid Glass X, and is it perfectly round on every page?
- Do all the flows make sense? Flows that don't finish or lose state.
- Is there dead code?
- Would certain pages make sense, or could they be consolidated?
- Transitions and sheets feel slow or springy.

## Finding format

Every lane writes findings in this shape so the skeptic, merger, and reviewers can read across lanes:

```
### <LANE>-<NN> <one-sentence defect>
- Where: <file:line>, or page name plus form factor and appearance
- Evidence: <file:line excerpt, measurement, or screenshot path under docs/refinement/evidence/>
- Severity: blocker | major | minor
- Fix: <concrete change>
- Batch: B1..B6
- Status: open
```

A finding without evidence from this pass is not a finding.
