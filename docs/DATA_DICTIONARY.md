# Data dictionary

## Paper redesign additions

- `PublishingDestination` stores built-in and creator-defined destinations. `PublishingFormat` stores one or more formats per destination, including short video, long video, and non-video. Legacy `PlatformOutput.platformRaw` remains dual-written; new output identity uses `destinationID` + `formatID`.
- `CreatorSocialAccount` stores a creator-owned profile name or handle and its public HTTPS profile link. Multiple accounts may share one destination; one may be the default for new post versions.
- `CreatorTask.laneRaw` separates Pillar tasks from Production without changing the legacy task kind vocabulary. `pillarID` and `platformOutputID` are optional links; task lifecycle remains independent from content lifecycle.
- `DailyFocusTemplateEntry` stores recurring weekday focus. `DailyFocusOverride` stores one-day replacement or clear behavior.
- `CreatorAttachment` stores private creator reference files with external SwiftData storage and a 25 MB client cap. Attachment bytes never enter AI requests.
- `PendingWeekProposal` stores a reviewable, unapplied Cy week proposal. It is not applied until explicit creator confirmation.
- `ConversationThread.contextKindRaw` and `contextID` provide optional brief, task, pillar, or day context while preserving global threads.
- `Pillar.roleRaw` identifies the one anchor pillar and supporting pillars. Supporting pillars own their color and weekdays; they do not inherit those values.

All additions are CloudKit-safe: stable UUIDs, no unique constraints, defaulted or optional properties, and app-level idempotent backfill.

All local records use stable UUIDs. SwiftData uniqueness is enforced in application code rather than with unique constraints so the first schema remains compatible with private CloudKit mirroring. Creator-authored content is local and may mirror to the creator's private iCloud database.

## Local entities

### CreatorProfile

The single local creator configuration.

- `id`: stable UUID.
- `name`: creator-facing display name.
- `goal`: primary creator goal used in relevant Cy requests.
- `selectedPlatforms`: one or more supported destinations: `instagramReels`, `tiktok`, `youtubeShorts`, or `youtubeVideo`.
- `assistanceMode`: `drive`, `collaborate`, or `lead`.
- `adultConfirmed`: required age gate.
- `telemetryConsent`: optional content-free product telemetry consent.
- `onboardingCompleted`: local onboarding gate.
- `createdAt`: creation date.

### VoiceExample

One genuine creator-authored caption, script, post, or transcript. The creator can defer examples and begin with zero. A profile needs at least three confirmed text examples before voice extraction.

- `id`, `profileID`, `text`, `sortOrder`, `createdAt`, `updatedAt`.
- `source`: pasted or dictated text, confirmed public-post text, or confirmed screenshot text.
- `sourceURL`: optional canonical Instagram post reference stored locally. It is not sent in AI requests.
- `creatorConfirmed`: records that the editable text was reviewed by the creator.
- No screenshot image, thumbnail, EXIF, page HTML, or cookie data is persisted.
- AI-visible evidence fingerprints include only the ordered example identifier, confirmed source label, confirmation state, and reviewed text. Local source URLs are deliberately excluded.
- Reviewed text is capped at 20,000 UTF-16 units per example and 40,000 UTF-8 bytes across the request context.

### CreatorSocialAccount

A manually managed reference to one social profile the creator owns. This record is not an OAuth connection and does not authorize reading or publishing.

- `id`, `profileID`, and `destinationID`: stable local identity and ownership links.
- `label`: editable account name or handle, such as `@cheycreates`.
- `profileURLString`: normalized public HTTPS profile link.
- `isPrimary`: preferred account for new outputs on this destination. Other accounts remain selectable per post.
- `isArchived`, `sortOrder`, `createdAt`, and `updatedAt`: additive lifecycle and display fields.
- Multiple active records may use the same `destinationID`, allowing multiple Instagram, TikTok, YouTube, or custom accounts.

### VoiceProfile

The visible, editable interpretation of the creator's voice. Generated changes remain proposals until approved.

- `id`, `profileID`, `summary`, `traits`, `avoid`, `isApproved`, `version`, `updatedAt`.
- `canonicalPayloadJSON`: the complete approved `VoiceProfile` contract used for future Teach Cy requests. Readable fields remain local projections.
- `evidenceFingerprint`: detects when examples changed without silently changing the approved profile.

### CreativeBrief

The master content object across the full lifecycle. A new record begins as a Spark.

- Identity: `id`, `source`, `status`, optional `pillarID`.
- Intent: `title`, `premise`, editable lightweight `notes`, `audience`, `creativeGoal`, `takeaway`.
- Script: format-aware `durationSeconds`, `spokenHook`, `firstFrameText`, modular `scriptBeats`, `close`, `ctaIntent`. Short-form choices are 30, 60, and 90 seconds or 3 minutes. Long-form YouTube choices are 10, 20, 30, 45, or 60 minutes.
- Production: filming and editing guidance.
- Trust: visible `assumptions` and `voiceConfidence` from 0 through 1.
- `readyBriefPayloadJSON`: the last approved canonical `ReadyBrief` contract, overlaid with creator edits before later scoped revisions.
- `lifecycleHistoryText`: ordered, timestamped status transitions. Repeated writes of the same status do not create duplicate history entries.
- Dates: `createdAt`, `updatedAt`, optional `archivedAt`.
- Optional `agendaDate` places the content once in Agenda. It is not a task or a lifecycle transition.

### PendingBriefProposal

A locally persisted, approval-gated Cy composition or scoped revision. Persisting this record before settling an allowance makes a generated proposal recoverable after an app exit or device restart.

- `id`, `briefID`, `proposalKind`, `createdAt`, `updatedAt`.
- `payloadJSON`: canonical composition or `BriefRevisionProposal` JSON containing the editable master draft, selected-platform differences, proposed tasks, source timestamp, changed fields, and explanation.
- Accepting or discarding the proposal deletes this record. Export includes the decoded canonical payload.

### PendingVoiceProfileProposal

A locally persisted initial extraction or Teach Cy proposal. `proposalKind` distinguishes the two. Initial extraction stores the evidence fingerprint so example changes invalidate stale proposals. Teach Cy stores the source profile version and timestamp, creator instruction, editable proposed profile, assumptions, and evidence notes. Acceptance creates a new approved `VoiceProfile` version. Discarding does not refund a successful generation.

### PlatformOutput

Meaningful differences for one selected destination. It does not duplicate the master script.

- `id`, `briefID`, `platform`, `destinationID`, `formatID`, optional `socialAccountID`, and `status`.
- `caption`, `openingAdjustment`, `titleOverride`, `cta`, `editChanges`.
- Optional `targetDate` and `postedAt`; `includesTargetTime` distinguishes a precise date-and-time target from date-only planning.
- `seriesName`, recurrence frequency and day fields, optional `recurrenceEndDate`, and `seriesRootOutputID` define a recurring series. The first scheduled output is the stable root; each future occurrence is a separate scheduled brief/output so it can be edited and completed independently.
- An open-ended recurrence materializes the next 12 future posts. An end date materializes every matching occurrence through that date, subject to a defensive 500-occurrence cap.
- A draft output may carry a flexible target while its master remains Spark or Developing. Scheduling lifecycle begins only after the master is Ready.

### CreatorTask

A first-class creator-work item stored once and queried into every relevant surface.

- `id`, optional `briefID`, optional `parentTaskID`, `title`, `kind`, `priority`, `notes`, optional `estimatedMinutes`, `sortOrder`.
- Optional `targetDate`, `isCompleted`, optional `completedAt`.
- `recordingMilestoneEmitted` prevents duplicate filming milestones.
- A task without `parentTaskID` is top-level. Subtasks complete independently and appear only beneath their parent.

### Pillar

An optional content theme. Briefs without a pillar remain valid.

- `id`, optional `parentPillarID`, `name`, legacy `detail`, `colorHex`, assigned weekdays, `isArchived`, `createdAt`. `detail` remains stored for migration compatibility but is no longer shown or edited.
- A top-level pillar is an anchor. A branch inherits its active anchor's color and assigned weekdays.
- If an anchor is missing, its former branches remain valid and display with their stored fallback color and weekdays.

### RhythmTemplate

A reusable weekly production pattern.

- `id`, `name`, ordered rhythm entries, `isActive`, `updatedAt`.

### WeekPlan

A legacy dated copy of a rhythm template retained for migration compatibility. It is not exposed in the current Agenda experience.

- `id`, `weekStart`, copied rhythm entries, `notes`, `createdAt`.

### ConversationThread and ConversationMessage

Local dialogue history for a global Ask Cy thread or one brief-scoped development thread.

- Thread: `id`, optional `briefID`, `title`, `turnCount`, `createdAt`, `updatedAt`.
- Message: `id`, `threadID`, `role`, `text`, `createdAt`.

### ReminderSettings

Local notification choices. iOS permission is requested only after at least one reminder is enabled.

- Daily: `dailyEnabled`, `dailyHour`.
- Weekly: `weeklyEnabled`, `weeklyWeekday`, `weeklyHour`.
- Identity: `id`, `updatedAt`.

### CalendarIntegrationPreferences

Device-local EventKit connection preferences. These values do not enter SwiftData or private CloudKit because calendar identifiers are specific to one device.

- Selected writable calendar identifier and display title.
- Independent `syncScheduledPosts` and `syncTasks` switches.
- A local mapping from agent.cy post/task UUIDs to EventKit event identifiers for one-way reconciliation and cleanup.
- No Google credential, OAuth token, or unrelated calendar event content.

### SubscriptionState

The local projection of access and first-journey allowances. Durable enforcement also occurs on the proxy.

- `id`, `access`, optional `trialEnd`, `updatedAt`.
- `freeBriefConsumed`, `ideationRequestsUsed`, `revisionRequestsUsed`, `teachCyUpdatesUsed`.

## Server records

The proxy stores no creator content. It stores only access and operational records:

- Invite tombstone: salted code hash, redeemed time, and installation link.
- Installation: salted credential hash, pseudonymous installation ID, creation time, deletion state.
- Entitlement projection: access state, source, and latest effective dates.
- Allowance counters: free-journey consumption and per-operation counters.
- Idempotency record: installation ID, operation ID, operation type, and final outcome metadata.
- Quota window: concurrent reservation and timestamped operation counts.
- Operational event: content-free event name, app build, prompt/schema versions, duration, error category, and timestamp.

Operational events expire after 30 days. Invite redemption, entitlement enforcement, and free-journey consumption are durable.
