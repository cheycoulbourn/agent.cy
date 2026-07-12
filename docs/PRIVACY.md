# Privacy and Data Handling

## Local creator data

Voice examples, voice profile, sparks, conversations, briefs, scripts, platform variants, tasks, pillars, schedules, reminders, and settings live in SwiftData and the creator's private iCloud database when available.

The app remains usable locally without iCloud.

## Voice capture

- Audio is transcribed on-device.
- Only transcript text may be sent to the AI proxy.
- Temporary audio is deleted after transcript acceptance unless the creator explicitly keeps it.
- Raw audio is never uploaded in v1.

## AI requests

The client sends only the context required for the current operation. The proxy must not log request bodies, response bodies, voice examples, scripts, captions, pillar names, URLs, authorization headers, or query strings containing user content.

Public-post links remain local references in v1. The proxy does not fetch links. Screenshot text is recognized on-device, shown to the creator for editing and confirmation, and sent only as confirmed text. Raw screenshots, page HTML, cookies, and source URLs are never included in AI requests.

Public wording:

> Sent securely to our AI provider to generate your result; agent.cy does not store this content on its servers.

Do not claim zero retention until the Anthropic organization has a confirmed contractual configuration that supports it.

## Operational records

Content-free request metadata and consented product events are retained for 30 days, then aggregated or deleted. Invite redemption, free-journey consumption, and subscription entitlement records are durable because they enforce access and prevent abuse.

## Export and erasure

Export produces a ZIP with canonical JSON and readable Markdown briefs. The JSON includes staged compositions, scoped revisions, and Teach Cy proposals so an unaccepted creator-visible proposal is not omitted from export.

When a live installation credential exists, Erase All Data first sends the authenticated `/v1/privacy/delete` request. The app deletes the device-only Keychain credential only after that request succeeds. If the service cannot be reached in a live build, local data and the credential remain intact so the creator can retry. Debug and fixture builds may continue with a clearly labeled local-only erase when no live identity or service is available.

Erase All Data removes:

- Local SwiftData.
- Private CloudKit records.
- Temporary audio and export files.
- Keychain installation credentials.
- Local entitlement cache.
- Persisted composition, revision, and voice-profile proposals.
- Installation-linked proxy metadata.

A redeemed invitation remains a detached non-content tombstone so the same code cannot be reused.
