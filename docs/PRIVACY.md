# Privacy and Data Handling

## Local creator data

Voice examples, voice profile, sparks, conversations, briefs, scripts, platform variants, tasks, pillars, schedules, reminders, and settings live in SwiftData and the creator's private iCloud database when available.

Creator-owned social profile names and public profile links are stored as private manual references in the same local/private-iCloud store. They are not OAuth connections. agent.cy does not sign in to, fetch from, monitor, or publish to those profiles.

The app remains usable locally without iCloud.

Calendar integration is optional and device-local. When enabled, agent.cy uses Apple's EventKit framework to add and update the creator's scheduled posts and selected production tasks in a calendar already configured on the iPhone. Google credentials and OAuth tokens are never requested or stored by agent.cy. Calendar event identifiers stay in local preferences and are cleared when the calendar is disconnected or app data is erased. agent.cy does not import unrelated calendar events or send calendar data to its server or AI provider.

Creator-added reference files are copied into the private SwiftData store, capped at 25 MB per file, included in export and erase, and never attached to an AI request. SwiftData private CloudKit mirroring is store-wide; the app does not claim per-file selective sync.

## AI requests

The client sends only the context required for the current operation. The proxy must not log request bodies, response bodies, voice examples, scripts, captions, pillar names, URLs, authorization headers, or query strings containing user content.

Public-post and creator-profile links remain local references in v1. The proxy does not fetch links. Screenshot text is recognized on-device, shown to the creator for editing and confirmation, and sent only as confirmed text. Raw screenshots, page HTML, cookies, and source URLs are never included in AI requests.

Public wording:

> Sent securely to our AI provider to generate your result; agent.cy does not store this content on its servers.

Do not claim zero retention until the Anthropic organization has a confirmed contractual configuration that supports it.

### Claude subscription handoff

Creators may choose a local Claude subscription handoff instead of an in-app Cy request. agent.cy prepares a bounded text prompt and presents it through the iOS share sheet. The creator chooses whether to send that text to the official Claude app or website. Claude credentials are never requested, read, or stored by agent.cy. A Claude response returns to agent.cy only when the creator explicitly pastes it and confirms **Add response**; the imported response is then stored with the creator's local conversation data.

## Operational records

Content-free request metadata and consented product events are retained for 30 days, then aggregated or deleted. Invite redemption, free-journey consumption, and subscription entitlement records are durable because they enforce access and prevent abuse.

## Export and erasure

Export produces a ZIP with canonical JSON, readable Markdown briefs, and creator-added reference files. The JSON includes staged compositions, scoped revisions, and Teach Cy proposals so an unaccepted creator-visible proposal is not omitted from export.

When a live installation credential exists, Erase All Data first sends the authenticated `/v1/privacy/delete` request. The app deletes the device-only Keychain credential only after that request succeeds. If the service cannot be reached in a live build, local data and the credential remain intact so the creator can retry. Debug and fixture builds may continue with a clearly labeled local-only erase when no live identity or service is available.

Erase All Data removes:

- Local SwiftData.
- Private CloudKit records.
- Export files.
- Keychain installation credentials.
- Local entitlement cache.
- Device-local calendar preferences and linked calendar events created by agent.cy.
- Persisted composition, revision, and voice-profile proposals.
- Installation-linked proxy metadata.

A redeemed invitation remains a detached non-content tombstone so the same code cannot be reused.
