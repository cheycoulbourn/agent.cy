# ADR 0012: Catalyst is a maintained internal pre-release surface

- Status: accepted
- Date: 2026-08-18

## Context

The v1 PRD defines agent.cy as an iPhone-only product and defers Mac. The repository also contains a substantial Mac Catalyst target, a dedicated desktop shell, desktop navigation and layout tests, Catalyst-specific capabilities, and canonical desktop designs. Leaving that implementation without an explicit product boundary blocks its page contracts and allows state, privacy, and workspace-isolation behavior to drift without review. Promoting it into v1 would silently expand the shipping promise beyond the PRD.

## Decision

Treat Mac Catalyst as an actively maintained internal pre-release surface. It is not part of the agent.cy v1 customer shipping promise and does not add Catalyst parity to the iPhone release gate.

The Catalyst target must continue to build and must preserve data ownership, workspace isolation, explicit AI proposal review, safe presentation behavior, accessibility, and the desktop interaction rules in `design.md`. Desktop-only pages may be audited and repaired against their recorded contracts. New customer-facing Catalyst launch commitments, distribution work, or parity requirements require a later product decision that updates the PRD.

## Consequences

- The PRD remains accurate: v1 ships on iPhone and Mac remains deferred.
- `PAGE-ROOT-07` and desktop-only surfaces can move from `Contract blocked` into bounded review.
- Clear correctness, privacy, workspace, accessibility, and maintenance defects may be fixed without treating every desktop gap as an iPhone release blocker.
- The Catalyst target and its tests remain maintained; it is not hidden or abandoned.
- A future Catalyst release requires a new ADR or amendment, explicit product scope, distribution criteria, and a full platform release matrix.
