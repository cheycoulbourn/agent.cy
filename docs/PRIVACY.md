# Privacy and Data Handling

## Local creator data

Posts, ideas, conversations, scripts, platform details, tasks, pillars, schedules, reminders, and settings live in SwiftData and the creator's private iCloud database when available. Voice examples and voice profiles from earlier builds remain stored for backward compatibility, but the current release does not show or send them to Cy.

Creator-owned social profile names and public profile links are stored as private manual references in the same local/private-iCloud store. They are not OAuth connections. agent.cy does not sign in to, fetch from, monitor, or publish to those profiles.

Sign in with Apple is optional account access for using agent.cy across the creator's devices. The proxy validates the Apple identity token and nonce, then stores only a keyed hash of Apple's stable subject identifier. It does not request or store the creator's Apple email or name. Each device keeps its own installation credential in the device-only Keychain. Signing out removes that local credential and does not delete local SwiftData or private CloudKit content.

The iOS Share Extension can save one public HTTPS post link plus caption text, a video file, or a thumbnail when the source app explicitly provides those share representations. Capture makes no network request. The main app validates the source, may fetch public oEmbed or Apple link metadata, and analyzes available shared media on device. Temporary shared video is deleted after transcript, frame observations, on-screen text, duration, and thumbnail are derived.

The app remains usable locally without iCloud.

Calendar integration is optional and device-local. When enabled, agent.cy uses Apple's EventKit framework to add and update the creator's scheduled posts and selected tasks in a calendar already configured on the iPhone. Google credentials and OAuth tokens are never requested or stored by agent.cy. Calendar event identifiers stay in local preferences and are cleared when the calendar is disconnected or app data is erased. agent.cy does not import unrelated calendar events or send calendar data to its server or AI provider.

Creator-added reference files are copied into the private SwiftData store, capped at 25 MB per file, included in export and erase, and never attached to an AI request. SwiftData private CloudKit mirroring is store-wide; the app does not claim per-file selective sync.

## AI requests

The client sends only the context required for the current operation. The proxy must not log request bodies, response bodies, voice examples, scripts, captions, pillar names, URLs, authorization headers, or query strings containing user content.

Public-post and creator-profile links remain local references in v1. The proxy does not fetch links. Screenshot text is recognized on-device, shown to the creator for editing and confirmation, and sent only as confirmed text. Raw screenshots, page HTML, cookies, and source URLs are never included in AI requests.

For saved-post shaping, Cy receives only the broad platform category, existing creator context, and device-derived source material: optional title, caption, transcript, visual observations, analyzed-input markers, and duration. The source URL, hostname, temporary video, thumbnail bytes, tags, cookies, and social credentials are excluded from the request, proxy logs, Local Cy prompt, and telemetry.

Public wording:

> Sent securely to our AI provider to generate your result; agent.cy does not store this content on its servers.

Do not claim zero retention until the Anthropic organization has a confirmed contractual configuration that supports it.

### Claude subscription handoff

Creators may choose a local Claude subscription handoff instead of an in-app Cy request. agent.cy prepares a bounded text prompt and presents it through the iOS share sheet. The creator chooses whether to send that text to the official Claude app or website. Claude credentials are never requested, read, or stored by agent.cy. A Claude response returns to agent.cy only when the creator explicitly pastes it and confirms **Add response**; the imported response is then stored with the creator's local conversation data.

## Operational records

Content-free request metadata and consented product events are retained for 30 days, then aggregated or deleted. Invite redemption, hashed Apple-account linkage, free-journey consumption, and subscription entitlement records are durable because they enforce access and prevent abuse.

## Export and erasure

Export produces a ZIP with structured JSON, readable Markdown posts, and creator-added reference files. Earlier voice data and pending proposals remain included for backward compatibility even though the current release does not display them.

When a live installation credential exists, Erase All Data first sends the authenticated `/v1/privacy/delete` request. The app deletes the device-only Keychain credential only after that request succeeds. If the service cannot be reached in a live build, local data and the credential remain intact so the creator can retry. Debug and fixture builds may continue with a clearly labeled local-only erase when no live identity or service is available.

Erase All Data removes:

- Local SwiftData.
- Private CloudKit records.
- Export files.
- Keychain installation credentials.
- Local entitlement cache.
- Device-local calendar preferences and linked calendar events created by agent.cy.
- Persisted composition, revision, and voice-profile proposals.
- Saved posts, saved-post tags, shared import queue files and assets, and the App Group workspace hint.
- Installation-linked proxy metadata.

A minimal non-content record of a redeemed invitation remains so the same code cannot be reused.
