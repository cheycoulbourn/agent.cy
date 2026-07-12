# ADR 0003: One master brief with platform differences

- Status: accepted
- Date: 2026-07-11

## Context

Creators may publish the same idea to Reels, TikTok, and Shorts. Maintaining three complete scripts would introduce drift, repeated edits, and unclear lifecycle state.

## Decision

Store one master CreativeBrief and one PlatformOutput per selected destination. Platform outputs contain only meaningful differences such as caption, opening adjustment, title, CTA, edit changes, target date, and posting state.

## Consequences

- Master edits remain the canonical creative truth.
- Distribution progress can aggregate as `x of y posted` without duplicating content.
- A master becomes Posted after the first selected output posts, while each output retains its own state.
- Unposting the final posted output deterministically rolls the master back to Scheduled or Ready.

