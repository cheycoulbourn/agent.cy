# ADR 0002: AI output is always a proposal

- Status: accepted
- Date: 2026-07-11

## Context

The product offers three assistance modes, including a proactive Lead me mode. Proactivity can save effort, but silently changing a creator's brief, voice model, schedule, pillars, or tasks would erode trust and make local history hard to reason about.

## Decision

All Cy-generated mutations are approval-gated proposals. A composed brief proposal is staged in the creator's local private store so it survives an app exit, but it does not modify the master brief, platform outputs, or tasks until the creator accepts it. Accepting or discarding clears the staged copy. Assistance mode changes initiative and question strategy only, not write authority.

## Consequences

- Proposal UI must remain visually distinct from accepted local data.
- Every mutation flow needs accept, edit, and dismiss paths.
- Retries and duplicate SSE delivery cannot silently duplicate stored records.
- Lead me may prepare more, but cannot bypass creator ownership.
