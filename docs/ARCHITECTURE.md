# Architecture

## Redesign migration rule

The Paper redesign uses additive SwiftData evolution only. `StoreBootstrapService` seeds and deduplicates the publishing catalog and backfills legacy outputs, profile destinations, task lanes/priorities, and pillar roles on every launch. It never deletes creator content. The v1 AI routes remain live while v2 destination-aware compose and revise routes are deployed server-first.

## System boundary

```text
iPhone app
  SwiftUI + SwiftData + private CloudKit mirroring
  on-device speech transcription
  local creator content and conversations
        |
        | request-scoped HTTPS/SSE, transcript text only
        v
Fastify proxy on Railway
  authentication, entitlements, quotas, schemas, prompts
  no durable creator-content storage
        |
        v
Anthropic Messages API, pinned claude-sonnet-5
```

There is no agent.cy account and no Supabase dependency.

Social profiles are manual local references, not connected identities. Multiple creator-owned accounts can point at the same publishing destination, and `PlatformOutput.socialAccountID` records which account a specific post version targets. No social-platform OAuth token, platform cookie, profile scraping, or automatic publishing is introduced.

Calendar integration uses EventKit on the creator's iPhone. The creator grants full Calendar access only when enabling the feature and chooses a writable calendar already configured on the device, including Google calendars connected through iOS. Calendar selection, sync toggles, and EventKit identifiers are device-local preferences rather than CloudKit records. agent.cy is the one-way source of truth: scheduled or posted platform outputs and dated top-level production tasks create or update calendar events, while calendar edits never silently mutate SwiftData.

## Client modules

- Domain: SwiftData entities, lifecycle rules, task and planning logic.
- Features: onboarding, ideation, briefs, Today, Agenda, Tasks, anchor/branch Pillars, Spark/Your work, Cy, settings.
- Services: AI transport, speech, notifications, EventKit calendar sync, entitlements, telemetry, export, erasure, and installation identity.
- DesignSystem: colors, typography, spacing, motion, components, and accessibility behavior.

SwiftData models use stable UUIDs, application-level deduplication, optional relationships where CloudKit requires them, explicit inverses, and migration-safe defaults. Private CloudKit mirroring is configured from the first shipping schema.

## Server modules

- Contracts: canonical Zod schemas and JSON Schema output formats.
- AI: versioned prompts, Anthropic adapter, streaming result validation, and error normalization.
- Identity: one-use invitation redemption and hashed installation credentials.
- Access: durable free-journey counters and RevenueCat entitlement projection.
- Quotas: one concurrent operation, short-window limits, daily limits, and global budget controls.
- Telemetry: consented content-free events and 30-day operational metadata.
- Privacy: installation-linked metadata deletion.

## AI contract

Every operation contains a schema version, prompt version, operation ID, app build, assistance mode, and minimal relevant context. The proxy buffers Anthropic output until it validates against the canonical schema, then emits one result over SSE.

Stream sequence:

`meta -> phase -> result | error -> done`

The client never persists a generated mutation until the creator accepts it.

## Offline contract

Capture, editing, lifecycle, tasks, planning, reminders, export, and deletion work offline. Cy operations do not queue automatically. A failed request remains retryable only by explicit creator action.

## Lifecycle invariants

- Platform outputs own platform status and optional URL.
- The master is Posted when at least one selected output is Posted.
- Tasks are stored once and queried into Brief, Today, and Tasks.
- CreativeBrief owns its Agenda placement. CreatorTask target dates never infer or duplicate content placement.
- Top-level tasks may own independently completable subtasks. Subtasks stay out of top-level lists and are deleted with their parent.
- Pillar branches inherit color and assigned weekdays from their active anchor. Missing or archived parents safely fall back to the branch's stored values.
- Rhythm templates and week instances are distinct records.
- Recorded validation is a milestone emitted by the filming task, not a visible status.
