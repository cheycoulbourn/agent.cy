# ADR 0001: Local-first client with a thin AI proxy

- Status: accepted
- Date: 2026-07-11

## Context

agent.cy needs private creator context, offline editing, Apple-native planning, abuse controls, and a protected Anthropic credential. A hosted product database or agent.cy account would expand identity and privacy scope before the wedge is validated.

## Decision

Store creator content in SwiftData with optional private CloudKit mirroring. Keep the app useful offline. Send only operation-scoped summaries to a Fastify proxy. The proxy authenticates a pseudonymous installation, enforces access and quotas, owns prompts, validates structured model output, and returns buffered results over SSE. It does not persist prompt or response bodies.

## Consequences

- Capture, editing, lifecycle, tasks, planning, export, and erase work without the network.
- Cy features require connectivity and explicit retry.
- Cross-device content sync is controlled by the creator's private iCloud account.
- The proxy still needs durable non-content access records and a deletion endpoint.
- There is no server-side collaborative editing or web client in v1.

