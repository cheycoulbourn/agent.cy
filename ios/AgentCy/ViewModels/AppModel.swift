import Foundation
import Observation
import SwiftData

enum AppSheet: String, Identifiable {
    case quickCapture
    case askCy
    case settings

    var id: String { rawValue }
}

enum AppNotice: Equatable {
    case info(String)
    case error(String)

    var message: String {
        switch self {
        case .info(let message), .error(let message): message
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .today
    var presentedSheet: AppSheet?
    var notice: AppNotice?
    var isWorking = false
    var recordingMilestones = 0
    var exportURL: URL?
    var quickCaptureStartsWithIdeas = false
    var quickCaptureStartsWithTask = false
    var quickCaptureStartsWithPost = false
    var quickCaptureStartsRecording = false
    var quickCaptureTargetDate: Date?
    var quickCapturePillarID: UUID?
    var briefProposals: [UUID: BriefProposal] = [:]
    var revisionProposals: [UUID: BriefRevisionProposal] = [:]
    var voiceProfileChangeProposal: VoiceProfileChangeProposal?
    var hasInstallationCredential = false
    var isRedeemingInvite = false

    @ObservationIgnored let requiresInstallationInvite: Bool

    @ObservationIgnored private let creativeService: any CreativeServicing
    @ObservationIgnored private let reminderService: any ReminderServicing
    @ObservationIgnored private let subscriptionService: any SubscriptionServicing
    @ObservationIgnored private let exportService: any ExportServicing
    @ObservationIgnored private let credentialStore: any InstallationCredentialStoring
    @ObservationIgnored private let installationRedemptionClient: InstallationRedemptionClient
    @ObservationIgnored private let privacyDeletionService: (any PrivacyDeletionServicing)?
    @ObservationIgnored private let allowsOfflinePrivacyErase: Bool

    init(
        creativeService: any CreativeServicing = PreviewCreativeService(),
        reminderService: any ReminderServicing = LocalReminderService(),
        subscriptionService: any SubscriptionServicing = PreviewSubscriptionService(),
        exportService: any ExportServicing = LocalExportService(),
        credentialStore: any InstallationCredentialStoring = DeviceOnlyKeychainCredentialStore.shared,
        installationRedemptionClient: InstallationRedemptionClient? = nil,
        privacyDeletionService: (any PrivacyDeletionServicing)? = nil,
        requiresInstallationInvite: Bool = false,
        allowsOfflinePrivacyErase: Bool = true
    ) {
        self.creativeService = creativeService
        self.reminderService = reminderService
        self.subscriptionService = subscriptionService
        self.exportService = exportService
        self.credentialStore = credentialStore
        self.installationRedemptionClient = installationRedemptionClient ?? InstallationRedemptionClient(store: credentialStore)
        self.privacyDeletionService = privacyDeletionService
        self.requiresInstallationInvite = requiresInstallationInvite
        self.allowsOfflinePrivacyErase = allowsOfflinePrivacyErase
    }

    func refreshInstallationCredentialStatus() async {
        guard requiresInstallationInvite else {
            hasInstallationCredential = true
            return
        }
        do {
            guard let identity = try await credentialStore.load() else {
                hasInstallationCredential = false
                return
            }
            hasInstallationCredential = identity.credentialExpiresAt.map { $0 > Date() } ?? true
        } catch {
            hasInstallationCredential = false
            notice = .error(error.localizedDescription)
        }
    }

    @discardableResult
    func redeemInstallationInvite(_ code: String) async -> Bool {
        guard requiresInstallationInvite else {
            hasInstallationCredential = true
            return true
        }
        isRedeemingInvite = true
        defer { isRedeemingInvite = false }
        do {
            _ = try await installationRedemptionClient.redeem(inviteCode: code)
            hasInstallationCredential = true
            return true
        } catch {
            hasInstallationCredential = false
            notice = .error(error.localizedDescription)
            return false
        }
    }

    func prepareVoiceProfile(from draft: OnboardingDraft) async -> VoiceProfileExtraction? {
        let creatorContext = onboardingCreatorContext(from: draft)
        if let issue = voiceEvidenceIssue(in: creatorContext) {
            notice = .info(issue)
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            return try await creativeService.extractVoiceProfile(context: creatorContext, mode: draft.assistanceMode)
        } catch {
            notice = .error(error.localizedDescription)
            return nil
        }
    }

    func voiceExampleDrafts(context: ModelContext) -> [VoiceExampleDraft] {
        guard let profile = fetchOne(CreatorProfile.self, context: context) else { return [] }
        return ((try? context.fetch(FetchDescriptor<VoiceExample>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { $0.profileID == profile.id }
            .prefix(5)
            .map {
                VoiceExampleDraft(
                    id: $0.id,
                    text: $0.text,
                    source: $0.source,
                    sourceURLString: $0.sourceURLString
                )
            }
    }

    @discardableResult
    func saveVoiceExamples(_ drafts: [VoiceExampleDraft], context: ModelContext) -> Bool {
        guard let profile = fetchOne(CreatorProfile.self, context: context) else {
            notice = .error("Your creator profile is unavailable.")
            return false
        }

        let retained = Array(drafts.filter { $0.isUsableEvidence || $0.hasLocalReference }.prefix(5))
        if let issue = VoiceExampleEvidenceLimits.issue(in: retained) {
            notice = .info(issue)
            return false
        }
        if drafts.contains(where: {
            !$0.sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                InstagramPostReference.canonicalURL(from: $0.sourceURLString) == nil
        }) {
            notice = .info("Check the Instagram link. Use a full HTTPS post or Reel URL.")
            return false
        }

        let normalizedTexts = retained
            .map(\.trimmedText)
            .filter { !$0.isEmpty }
            .map(normalizedExampleText)
        guard Set(normalizedTexts).count == normalizedTexts.count else {
            notice = .info("Two examples contain the same text. Keep one and use a different piece for the other.")
            return false
        }
        let normalizedURLs = retained.compactMap { InstagramPostReference.canonicalURL(from: $0.sourceURLString)?.absoluteString }
        guard Set(normalizedURLs).count == normalizedURLs.count else {
            notice = .info("That Instagram post is already included in another example.")
            return false
        }

        do {
            let stored = try context.fetch(FetchDescriptor<VoiceExample>()).filter { $0.profileID == profile.id }
            let previousEvidenceFingerprint = VoiceExampleFingerprint.make(from: stored)
            let retainedEvidenceFingerprint = VoiceExampleFingerprint.make(from: retained)
            let retainedIDs = Set(retained.map(\.id))
            for existing in stored where !retainedIDs.contains(existing.id) { context.delete(existing) }

            for (index, draft) in retained.enumerated() {
                let canonicalURL = InstagramPostReference.canonicalURL(from: draft.sourceURLString)?.absoluteString ?? ""
                if let existing = stored.first(where: { $0.id == draft.id }) {
                    existing.text = draft.trimmedText
                    existing.sortOrder = index
                    existing.source = draft.source
                    existing.sourceURLString = canonicalURL
                    existing.creatorConfirmed = true
                    existing.updatedAt = Date()
                } else {
                    context.insert(VoiceExample(
                        id: draft.id,
                        profileID: profile.id,
                        text: draft.trimmedText,
                        sortOrder: index,
                        source: draft.source,
                        sourceURLString: canonicalURL,
                        creatorConfirmed: true
                    ))
                }
            }
            if previousEvidenceFingerprint != retainedEvidenceFingerprint {
                try deletePendingVoiceProposals(kind: "initial", context: context)
            }
            try context.save()
            return true
        } catch {
            notice = .error("Your examples could not be saved: \(error.localizedDescription)")
            return false
        }
    }

    func prepareInitialVoiceProfile(context: ModelContext) async -> InitialVoiceProfileProposal? {
        guard can(.extractVoiceProfile, context: context) else { return nil }
        guard let profile = fetchOne(CreatorProfile.self, context: context),
              let creatorContext = creatorContextWire(profile: profile, context: context),
              creatorContext.voiceExamples.count >= 3 else {
            notice = .info("Add and review at least three real examples before Cy builds your voice profile.")
            return nil
        }
        if let issue = voiceEvidenceIssue(in: creatorContext) {
            notice = .info(issue)
            return nil
        }
        let requestEvidenceFingerprint = VoiceExampleFingerprint.make(from: creatorContext.voiceExamples)
        if let existing = initialVoiceProfileProposal(context: context),
           existing.profileID == profile.id,
           existing.evidenceFingerprint == requestEvidenceFingerprint {
            return existing
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let extraction = try await creativeService.extractVoiceProfile(context: creatorContext, mode: profile.assistanceMode)
            try deletePendingVoiceProposals(kind: "initial", context: context)
            let proposal = InitialVoiceProfileProposal(
                profileID: profile.id,
                edited: VoiceProfileDraft(extraction.canonical),
                evidenceFingerprint: requestEvidenceFingerprint
            )
            try persist(initialVoiceProposal: proposal, context: context)
            try context.save()
            return proposal
        } catch {
            notice = .error(error.localizedDescription)
            return nil
        }
    }

    func initialVoiceProfileProposal(context: ModelContext) -> InitialVoiceProfileProposal? {
        let descriptor = FetchDescriptor<PendingVoiceProfileProposal>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let record = try? context.fetch(descriptor).first(where: { $0.proposalKindRaw == "initial" }),
              let data = record.payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InitialVoiceProfileProposal.self, from: data)
    }

    func acceptInitialVoiceProfile(_ proposal: InitialVoiceProfileProposal, context: ModelContext) {
        guard let staged = initialVoiceProfileProposal(context: context), staged.id == proposal.id,
              let profile = fetchOne(CreatorProfile.self, context: context),
              profile.id == proposal.profileID,
              validVoiceDraft(proposal.edited) else {
            notice = .error("This voice-profile proposal is no longer valid.")
            return
        }
        let examples = ((try? context.fetch(FetchDescriptor<VoiceExample>())) ?? [])
            .filter { $0.profileID == profile.id && $0.creatorConfirmed && !$0.text.isEmpty }
        guard VoiceExampleFingerprint.make(from: examples) == proposal.evidenceFingerprint else {
            notice = .info("Your examples changed after this profile was prepared. Build it again from the current examples.")
            discardInitialVoiceProfile(context: context)
            return
        }

        do {
            let related = try context.fetch(FetchDescriptor<VoiceProfile>()).filter { $0.profileID == profile.id }
            related.forEach { $0.isApproved = false }
            let wire = proposal.edited.wire
            context.insert(VoiceProfile(
                profileID: profile.id,
                summary: wire.summary,
                traitsText: (wire.tone + wire.signatureQualities).joined(separator: ", "),
                avoidText: wire.phrasesToAvoid.joined(separator: ", "),
                isApproved: true,
                version: (related.map(\.version).max() ?? 0) + 1,
                canonicalPayloadJSON: try encodeJSONString(wire),
                evidenceFingerprint: proposal.evidenceFingerprint
            ))
            try deletePendingVoiceProposals(kind: "initial", context: context)
            try context.save()
        } catch {
            notice = .error("The voice profile could not be accepted: \(error.localizedDescription)")
        }
    }

    func discardInitialVoiceProfile(context: ModelContext) {
        do {
            try deletePendingVoiceProposals(kind: "initial", context: context)
            try context.save()
        } catch {
            notice = .error("The voice-profile proposal could not be discarded: \(error.localizedDescription)")
        }
    }

    func isVoiceProfileStale(_ voiceProfile: VoiceProfile, context: ModelContext) -> Bool {
        guard !voiceProfile.evidenceFingerprint.isEmpty else { return false }
        let examples = ((try? context.fetch(FetchDescriptor<VoiceExample>())) ?? [])
            .filter { $0.profileID == voiceProfile.profileID && $0.creatorConfirmed && !$0.text.isEmpty }
        return VoiceExampleFingerprint.make(from: examples) != voiceProfile.evidenceFingerprint
    }

    @discardableResult
    func completeOnboarding(_ draft: OnboardingDraft, context: ModelContext) async -> Bool {
        let retainedExamples = Array(draft.voiceExamples.filter { $0.isUsableEvidence || $0.hasLocalReference }.prefix(5))
        if let issue = VoiceExampleEvidenceLimits.issue(in: retainedExamples) {
            notice = .info(issue)
            return false
        }
        let profile = CreatorProfile(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedPlatforms: draft.platforms.sorted { $0.rawValue < $1.rawValue },
            assistanceMode: draft.assistanceMode,
            adultConfirmed: draft.adultConfirmed,
            telemetryConsent: draft.telemetryConsent,
            onboardingCompleted: false
        )
        context.insert(profile)
        for (index, example) in retainedExamples.enumerated() {
            context.insert(VoiceExample(
                id: example.id,
                profileID: profile.id,
                text: example.trimmedText,
                sortOrder: index,
                source: example.source,
                sourceURLString: InstagramPostReference.canonicalURL(from: example.sourceURLString)?.absoluteString ?? "",
                creatorConfirmed: true
            ))
        }
        if let approvedVoiceProfile = onboardingVoiceProfile(from: draft) {
            context.insert(VoiceProfile(
                profileID: profile.id,
                summary: approvedVoiceProfile.summary,
                traitsText: (approvedVoiceProfile.tone + approvedVoiceProfile.signatureQualities).joined(separator: ", "),
                avoidText: approvedVoiceProfile.phrasesToAvoid.joined(separator: ", "),
                isApproved: true,
                canonicalPayloadJSON: (try? encodeJSONString(approvedVoiceProfile)) ?? "",
                evidenceFingerprint: VoiceExampleFingerprint.make(from: retainedExamples)
            ))
        }
        let settings = ReminderSettings(
            dailyEnabled: draft.dailyReminderEnabled,
            dailyHour: draft.dailyReminderHour,
            weeklyEnabled: draft.weeklyReminderEnabled,
            weeklyWeekday: draft.weeklyReminderWeekday,
            weeklyHour: draft.weeklyReminderHour
        )
        context.insert(settings)
        let installationIdentity = try? await credentialStore.load()
        context.insert(SubscriptionState(access: installationIdentity?.access ?? .freeJourney, trialEnd: installationIdentity?.promotionalEntitlementEndsAt))
        try? context.save()
        do {
            try await reminderService.apply(settings)
        } catch {
            notice = .info("Your profile is ready. Reminders stayed off because notification permission was not available.")
        }
        return true
    }

    @discardableResult
    func createSpark(
        text: String,
        source: SparkSource,
        targetDate: Date? = nil,
        context: ModelContext
    ) -> CreativeBrief? {
        guard can(.createSpark, context: context) else { return nil }
        let premise = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !premise.isEmpty else {
            notice = .error("Add an idea before saving.")
            return nil
        }
        let title = titleFromSpark(premise)
        let brief = CreativeBrief(title: title, premise: premise, source: source)
        brief.agendaDate = targetDate
        context.insert(brief)
        try? context.save()
        return brief
    }

    @discardableResult
    func createPost(
        title: String,
        notes: String,
        pillarID: UUID?,
        platform: CreatorPlatform,
        durationSeconds: Int,
        targetDate: Date,
        firstTaskTitle: String,
        context: ModelContext
    ) -> CreativeBrief? {
        guard can(.createSpark, context: context) else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            notice = .error("Name the post before saving it.")
            return nil
        }

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let brief = CreativeBrief(
            title: cleanTitle,
            premise: cleanNotes,
            source: .text,
            status: .spark
        )
        brief.notes = cleanNotes
        brief.pillarID = pillarID
        brief.durationSeconds = platform.format.durationOptions.contains(durationSeconds)
            ? durationSeconds
            : platform.format.defaultDuration
        brief.agendaDate = targetDate
        context.insert(brief)

        let output = PlatformOutput(briefID: brief.id, platform: platform, status: .draft)
        output.targetDate = targetDate
        context.insert(output)

        let cleanTask = firstTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTask.isEmpty {
            context.insert(CreatorTask(
                briefID: brief.id,
                title: cleanTask,
                kind: .planning
            ))
        }

        do {
            try context.save()
            return brief
        } catch {
            notice = .error("That post could not be saved.")
            return nil
        }
    }

    @discardableResult
    func plan(_ brief: CreativeBrief, on date: Date, context: ModelContext) -> Bool {
        guard can(.schedule, context: context), brief.status != .archived else { return false }
        brief.agendaDate = date
        brief.updatedAt = Date()
        do {
            try context.save()
            return true
        } catch {
            notice = .error("That content could not be added to \(date.formatted(.dateTime.weekday())).")
            return false
        }
    }

    @discardableResult
    func createTask(title: String, kind: CreatorTaskKind, priority: TaskPriority = .medium, targetDate: Date?, context: ModelContext) -> CreatorTask? {
        guard can(.createTask, context: context) else { return nil }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .error("Give the task a clear next action.")
            return nil
        }
        let task = CreatorTask(title: cleaned, kind: kind, priority: priority, targetDate: targetDate)
        context.insert(task)
        try? context.save()
        return task
    }

    @discardableResult
    func createSubtask(
        title: String,
        parent: CreatorTask,
        context: ModelContext
    ) -> CreatorTask? {
        guard can(.createTask, context: context), parent.parentTaskID == nil else { return nil }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .error("Name the subtask before adding it.")
            return nil
        }
        let siblings = subtasks(for: parent, context: context)
        let subtask = CreatorTask(
            briefID: parent.briefID,
            parentTaskID: parent.id,
            title: cleaned,
            kind: parent.kind,
            priority: parent.priority,
            sortOrder: siblings.count
        )
        context.insert(subtask)
        try? context.save()
        return subtask
    }

    func findIdeas(context: ModelContext) async -> [IdeaDirection] {
        guard can(.ideate, context: context) else { return [] }
        guard let profile = fetchOne(CreatorProfile.self, context: context) else { return [] }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            let ideas = try await creativeService.findIdeas(context: creatorContext, mode: profile.assistanceMode)
            let state = subscriptionState(context)
            state?.ideationRequestsUsed += 1
            state?.updatedAt = Date()
            try? context.save()
            return ideas
        } catch {
            notice = .error(error.localizedDescription)
            return []
        }
    }

    func sendDialogueTurn(brief: CreativeBrief, answer: String, context: ModelContext) async {
        guard can(.sparkDialogue, context: context) else { return }
        let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let thread = developmentThread(for: brief, context: context)
        guard thread.turnCount < 8 else {
            notice = .info("You’ve reached eight turns. Build the brief now or edit the idea yourself.")
            return
        }
        context.insert(ConversationMessage(threadID: thread.id, role: .creator, text: cleaned))
        BriefLifecycle.beginDevelopment(brief)
        isWorking = true
        defer { isWorking = false }
        do {
            guard let profile = fetchOne(CreatorProfile.self, context: context),
                  let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            let conversation = conversationWire(messages(for: thread, context: context))
            let response = try await creativeService.nextQuestion(
                for: brief,
                turn: thread.turnCount,
                answer: cleaned,
                mode: profile.assistanceMode,
                context: creatorContext,
                conversation: conversation
            )
            context.insert(ConversationMessage(threadID: thread.id, role: .cy, text: response))
            thread.turnCount += 1
            thread.updatedAt = Date()
            try? context.save()
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func compose(brief: CreativeBrief, context: ModelContext) async {
        guard can(.compose, context: context) else { return }
        guard let profile = fetchOne(CreatorProfile.self, context: context) else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            let thread = developmentThread(for: brief, context: context)
            let conversation = conversationWire(messages(for: thread, context: context))
            let proposal = try await creativeService.composeProposal(
                from: brief,
                mode: profile.assistanceMode,
                context: creatorContext,
                conversation: conversation
            )
            try persist(proposal: proposal, context: context)
            BriefLifecycle.beginDevelopment(brief)
            try context.save()
            briefProposals[brief.id] = proposal
            if let state = subscriptionState(context), state.access == .freeJourney {
                let wasConsumed = state.freeBriefConsumed
                state.freeBriefConsumed = true
                state.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    state.freeBriefConsumed = wasConsumed
                    throw error
                }
            }
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func acceptProposal(_ proposal: BriefProposal, for brief: CreativeBrief, context: ModelContext) {
        guard proposal.briefID == brief.id else { return }
        apply(proposal.draft, to: brief)

        let existingOutputs = outputs(for: brief, context: context)
        for variant in proposal.variants where !existingOutputs.contains(where: { $0.platform == variant.platform }) {
            let output = PlatformOutput(briefID: brief.id, platform: variant.platform, status: .ready)
            apply(variant, to: output)
            context.insert(output)
        }

        let existingTasks = tasks(for: brief, context: context)
        for (index, proposed) in proposal.tasks.enumerated() where !existingTasks.contains(where: { $0.title == proposed.title && $0.kind == proposed.kind }) {
            context.insert(CreatorTask(
                briefID: brief.id,
                title: proposed.title,
                kind: proposed.kind,
                notes: proposed.notes,
                estimatedMinutes: proposed.estimatedMinutes,
                sortOrder: existingTasks.count + index,
                isRecordingMilestoneDesignated: proposed.isRecordingMilestone
            ))
        }

        do {
            let accepted = localProposal(for: brief, context: context)
            let canonical = (proposal.canonicalBrief ?? fallbackReadyBrief(from: accepted)).overlaying(accepted)
            brief.readyBriefPayloadJSON = try encodeJSONString(canonical)
            try deletePendingProposals(for: brief.id, kind: "composition", context: context)
            try context.save()
            briefProposals.removeValue(forKey: brief.id)
        } catch {
            notice = .error("The proposal was applied, but its pending copy could not be cleared: \(error.localizedDescription)")
        }
    }

    func discardProposal(for brief: CreativeBrief, context: ModelContext) {
        do {
            try deletePendingProposals(for: brief.id, kind: "composition", context: context)
            try context.save()
            briefProposals.removeValue(forKey: brief.id)
        } catch {
            notice = .error("The proposal could not be discarded: \(error.localizedDescription)")
        }
    }

    func proposal(for brief: CreativeBrief, context: ModelContext) -> BriefProposal? {
        if let proposal = briefProposals[brief.id] { return proposal }
        let briefID = brief.id
        let descriptor = FetchDescriptor<PendingBriefProposal>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let record = (try? context.fetch(descriptor))?.first(where: { $0.proposalKindRaw == "composition" }),
              let data = record.payloadJSON.data(using: .utf8),
              let proposal = try? JSONDecoder().decode(BriefProposal.self, from: data),
              proposal.briefID == brief.id else {
            return nil
        }
        return proposal
    }

    func requestRevision(
        for brief: CreativeBrief,
        scope: BriefRevisionFieldWire,
        instruction: String,
        context: ModelContext
    ) async {
        guard can(.revise, context: context) else { return }
        guard proposal(for: brief, context: context) == nil else {
            notice = .info("Review or discard the current composition proposal before asking for a revision.")
            return
        }
        guard revisionProposal(for: brief, context: context) == nil else {
            notice = .info("A revision proposal is already waiting for your review.")
            return
        }
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .info("Tell Cy what should change before preparing a revision.")
            return
        }
        guard let profile = fetchOne(CreatorProfile.self, context: context),
              let creatorContext = creatorContextWire(profile: profile, context: context),
              let state = subscriptionState(context) else {
            notice = .error("The approved creator context is incomplete.")
            return
        }

        let baseline = localProposal(for: brief, context: context)
        let canonical = canonicalReadyBrief(for: brief, baseline: baseline)
        let sourceTasks = tasks(for: brief, context: context)
        let sourceUpdatedAt = brief.updatedAt
        isWorking = true
        defer { isWorking = false }
        do {
            let revision = try await creativeService.proposeRevision(
                of: canonical,
                localBriefID: brief.id,
                revisionNumber: state.revisionRequestsUsed + 1,
                scope: scope,
                instruction: cleaned,
                mode: profile.assistanceMode,
                context: creatorContext,
                baseline: baseline,
                sourceUpdatedAt: sourceUpdatedAt,
                sourceTaskIDs: sourceTasks.map(\.id)
            )
            guard revision.briefID == brief.id,
                  revision.sourceUpdatedAt == sourceUpdatedAt,
                  revision.requestedScope == scope,
                  revision.changedFields.contains(scope),
                  revision.edited != revision.baseline else {
                throw CreativeServiceError.invalidLiveResponse("the revision proposal failed local integrity checks")
            }
            try persist(revision: revision, context: context)
            state.revisionRequestsUsed += 1
            state.updatedAt = Date()
            try context.save()
            revisionProposals[brief.id] = revision
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func revisionProposal(for brief: CreativeBrief, context: ModelContext) -> BriefRevisionProposal? {
        if let proposal = revisionProposals[brief.id] { return proposal }
        let briefID = brief.id
        let descriptor = FetchDescriptor<PendingBriefProposal>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let record = (try? context.fetch(descriptor))?.first(where: { $0.proposalKindRaw == "revision" }),
              let data = record.payloadJSON.data(using: .utf8),
              let proposal = try? JSONDecoder().decode(BriefRevisionProposal.self, from: data),
              proposal.briefID == brief.id else {
            return nil
        }
        return proposal
    }

    func acceptRevision(_ proposal: BriefRevisionProposal, for brief: CreativeBrief, context: ModelContext) {
        guard let staged = revisionProposal(for: brief, context: context), staged.id == proposal.id else {
            notice = .error("This revision is no longer the proposal waiting for review.")
            return
        }
        guard brief.updatedAt == proposal.sourceUpdatedAt else {
            notice = .info("The brief changed after this revision was generated. Keep your current brief, discard this proposal, and ask Cy again if you still want help.")
            return
        }
        let currentAccepted = localProposal(for: brief, context: context)
        guard currentAccepted.draft == proposal.baseline.draft,
              currentAccepted.variants == proposal.baseline.variants,
              currentAccepted.tasks == proposal.baseline.tasks else {
            notice = .info("The brief changed after this revision was generated. Keep your current edits, discard this proposal, and ask Cy again if you still want help.")
            return
        }
        let milestones = proposal.edited.tasks.filter(\.isRecordingMilestone)
        guard milestones.count <= 1, milestones.allSatisfy({ $0.kind == .filming }) else {
            notice = .error("Choose at most one filming task as the recording milestone.")
            return
        }

        let priorStatus = brief.status
        let priorArchivedAt = brief.archivedAt
        apply(proposal.edited.draft, to: brief)
        brief.status = priorStatus
        brief.archivedAt = priorArchivedAt

        let existingOutputs = outputs(for: brief, context: context)
        for variant in proposal.edited.variants {
            if let output = existingOutputs.first(where: { $0.platform == variant.platform }) {
                apply(variant, to: output)
            } else {
                let output = PlatformOutput(briefID: brief.id, platform: variant.platform, status: .ready)
                apply(variant, to: output)
                context.insert(output)
            }
        }
        reconcileTasks(for: brief, proposal: proposal, context: context)

        do {
            brief.readyBriefPayloadJSON = try encodeJSONString(proposal.canonicalBrief.overlaying(proposal.edited))
            try deletePendingProposals(for: brief.id, kind: "revision", context: context)
            try context.save()
            revisionProposals.removeValue(forKey: brief.id)
        } catch {
            notice = .error("The revision could not be applied: \(error.localizedDescription)")
        }
    }

    func discardRevision(for brief: CreativeBrief, context: ModelContext) {
        do {
            try deletePendingProposals(for: brief.id, kind: "revision", context: context)
            try context.save()
            revisionProposals.removeValue(forKey: brief.id)
        } catch {
            notice = .error("The revision could not be discarded: \(error.localizedDescription)")
        }
    }

    func requestTeachCy(instruction: String, context: ModelContext) async {
        guard can(.teachCy, context: context) else { return }
        guard voiceProfileProposal(context: context) == nil else {
            notice = .info("A voice-profile proposal is already waiting for your review.")
            return
        }
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            notice = .info("Teach Cy needs one specific instruction from you.")
            return
        }
        guard let creator = fetchOne(CreatorProfile.self, context: context),
              let profile = approvedVoiceProfile(context: context),
              let currentWire = voiceProfileWire(profile),
              let creatorContext = creatorContextWire(profile: creator, context: context),
              let state = subscriptionState(context) else {
            notice = .error("The approved voice profile is incomplete.")
            return
        }
        let current = VoiceProfileDraft(currentWire)
        isWorking = true
        defer { isWorking = false }
        do {
            let proposal = try await creativeService.proposeVoiceProfileChange(
                profileID: profile.profileID,
                sourceVersion: profile.version,
                sourceUpdatedAt: profile.updatedAt,
                current: current,
                instruction: cleaned,
                mode: creator.assistanceMode,
                context: creatorContext
            )
            guard proposal.profileID == profile.profileID,
                  proposal.sourceVersion == profile.version,
                  proposal.sourceUpdatedAt == profile.updatedAt,
                  proposal.edited != proposal.baseline else {
                throw CreativeServiceError.invalidLiveResponse("Teach Cy did not produce a valid profile change")
            }
            try persist(voiceProposal: proposal, context: context)
            state.teachCyUpdatesUsed += 1
            state.updatedAt = Date()
            try context.save()
            voiceProfileChangeProposal = proposal
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func voiceProfileProposal(context: ModelContext) -> VoiceProfileChangeProposal? {
        if let voiceProfileChangeProposal { return voiceProfileChangeProposal }
        let descriptor = FetchDescriptor<PendingVoiceProfileProposal>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let record = try? context.fetch(descriptor).first(where: { $0.proposalKindRaw == "teach" }),
              let data = record.payloadJSON.data(using: .utf8),
              let proposal = try? JSONDecoder().decode(VoiceProfileChangeProposal.self, from: data) else {
            return nil
        }
        return proposal
    }

    func acceptVoiceProfileChange(_ proposal: VoiceProfileChangeProposal, context: ModelContext) {
        guard let staged = voiceProfileProposal(context: context), staged.id == proposal.id,
              let current = approvedVoiceProfile(context: context),
              current.profileID == proposal.profileID,
              current.version == proposal.sourceVersion,
              current.updatedAt == proposal.sourceUpdatedAt else {
            notice = .info("The approved voice profile changed after this proposal was generated. Keep the current profile and teach Cy again if needed.")
            return
        }
        guard validVoiceDraft(proposal.edited), proposal.edited != proposal.baseline else {
            notice = .error("The proposed voice profile needs a visible, valid change before it can be accepted.")
            return
        }
        let profiles = (try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? []
        let related = profiles.filter { $0.profileID == proposal.profileID }
        related.forEach { $0.isApproved = false }
        do {
            let nextVersion = (related.map(\.version).max() ?? 0) + 1
            let wire = proposal.edited.wire
            let newProfile = VoiceProfile(
                profileID: proposal.profileID,
                summary: wire.summary,
                traitsText: (wire.tone + wire.signatureQualities).joined(separator: ", "),
                avoidText: wire.phrasesToAvoid.joined(separator: ", "),
                isApproved: true,
                version: nextVersion,
                canonicalPayloadJSON: try encodeJSONString(wire),
                evidenceFingerprint: VoiceExampleFingerprint.make(from: ((try? context.fetch(FetchDescriptor<VoiceExample>())) ?? []).filter {
                    $0.profileID == proposal.profileID && $0.creatorConfirmed && !$0.text.isEmpty
                })
            )
            context.insert(newProfile)
            try deletePendingVoiceProposals(context: context)
            try context.save()
            voiceProfileChangeProposal = nil
        } catch {
            current.isApproved = true
            notice = .error("The voice-profile update could not be accepted: \(error.localizedDescription)")
        }
    }

    func discardVoiceProfileChange(context: ModelContext) {
        do {
            try deletePendingVoiceProposals(context: context)
            try context.save()
            voiceProfileChangeProposal = nil
        } catch {
            notice = .error("The voice-profile proposal could not be discarded: \(error.localizedDescription)")
        }
    }

    func approvedVoiceProfile(context: ModelContext) -> VoiceProfile? {
        ((try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? [])
            .filter(\.isApproved)
            .sorted {
                if $0.version == $1.version { return $0.updatedAt > $1.updatedAt }
                return $0.version > $1.version
            }
            .first
    }

    func allows(_ action: AccessAction, context: ModelContext) -> Bool {
        AccessPolicy.allows(action, state: subscriptionState(context))
    }

    func approve(brief: CreativeBrief, context: ModelContext) {
        BriefLifecycle.approve(brief)
        if let profile = fetchOne(CreatorProfile.self, context: context), !profile.onboardingCompleted {
            profile.onboardingCompleted = true
        }
        try? context.save()
    }

    func noteManualDevelopment(of brief: CreativeBrief, context: ModelContext) {
        guard brief.status == .spark else { return }
        BriefLifecycle.beginDevelopment(brief)
        try? context.save()
    }

    func schedule(output: PlatformOutput, date: Date?, context: ModelContext) {
        guard can(.schedule, context: context) else { return }
        guard let brief = brief(id: output.briefID, context: context) else {
            notice = .error("That post is no longer available.")
            return
        }
        let previousDate = output.targetDate
        if [.spark, .developing].contains(brief.status), output.status == .draft {
            output.targetDate = date
            if brief.agendaDate == nil || brief.agendaDate == previousDate { brief.agendaDate = date }
            brief.updatedAt = Date()
            try? context.save()
            return
        }
        guard BriefLifecycle.schedule(output, for: date, brief: brief) else {
            notice = .info("Approve this brief before adding production or posting targets.")
            return
        }
        if brief.agendaDate == nil || brief.agendaDate == previousDate { brief.agendaDate = date }
        BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        try? context.save()
    }

    func togglePosted(output: PlatformOutput, context: ModelContext) {
        guard can(.updatePosting, context: context) else { return }
        guard let brief = brief(id: output.briefID, context: context),
              BriefLifecycle.togglePosted(output, brief: brief) else {
            notice = .info("Approve this brief before updating its posting progress.")
            return
        }
        BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        try? context.save()
    }

    func toggleTask(_ task: CreatorTask, context: ModelContext) {
        let linkedBrief = task.briefID.flatMap { brief(id: $0, context: context) }
        if task.briefID != nil, linkedBrief == nil || linkedBrief?.status == .archived {
            notice = .info("This task belongs to content that is no longer active.")
            return
        }
        let previousMilestoneExists: Bool
        if let briefID = task.briefID {
            let descriptor = FetchDescriptor<CreatorTask>(predicate: #Predicate { $0.briefID == briefID })
            previousMilestoneExists = ((try? context.fetch(descriptor)) ?? []).contains { $0.id != task.id && $0.recordingMilestoneEmitted }
        } else {
            previousMilestoneExists = true
        }
        if BriefLifecycle.toggleTask(task, brief: linkedBrief), !previousMilestoneExists {
            recordingMilestones += 1
            notice = .info("Recording marked complete. Your brief stays in its current lifecycle stage until you post an output.")
        } else if previousMilestoneExists && task.recordingMilestoneEmitted {
            task.recordingMilestoneEmitted = false
        }
        try? context.save()
    }

    func archive(_ brief: CreativeBrief, context: ModelContext) {
        BriefLifecycle.archive(brief)
        try? context.save()
    }

    func replan(task: CreatorTask, choice: ReplanChoice, context: ModelContext) {
        switch choice {
        case .move:
            task.targetDate = Calendar.current.date(byAdding: .day, value: 1, to: task.targetDate ?? Date())
        case .pause:
            task.targetDate = nil
        case .archive:
            deleteTask(task, context: context)
            return
        }
        try? context.save()
    }

    func deleteTask(_ task: CreatorTask, context: ModelContext) {
        subtasks(for: task, context: context).forEach(context.delete)
        context.delete(task)
        try? context.save()
    }

    func removeLegacySimplifyPrefixes(context: ModelContext) {
        let tasks = (try? context.fetch(FetchDescriptor<CreatorTask>())) ?? []
        var changed = false
        for task in tasks where task.title.hasPrefix("Simplify: ") {
            task.title = String(task.title.dropFirst("Simplify: ".count))
            changed = true
        }
        if changed { try? context.save() }
    }

    func replan(output: PlatformOutput, choice: ReplanChoice, context: ModelContext) {
        guard let brief = brief(id: output.briefID, context: context), brief.status != .archived else {
            notice = .info("That content is no longer active.")
            return
        }
        let previousDate = output.targetDate
        if output.status == .draft, [.spark, .developing].contains(brief.status) {
            switch choice {
            case .move:
                output.targetDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            case .pause:
                output.targetDate = nil
            case .archive:
                BriefLifecycle.archive(brief)
            }
            if brief.agendaDate == nil || brief.agendaDate == previousDate {
                brief.agendaDate = output.targetDate
            }
            try? context.save()
            return
        }
        guard BriefLifecycle.canPlan(brief) else {
            notice = .info("Approve this brief before adjusting its posting target.")
            return
        }
        switch choice {
        case .move:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            _ = BriefLifecycle.schedule(output, for: tomorrow, brief: brief)
            BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        case .pause:
            _ = BriefLifecycle.schedule(output, for: nil, brief: brief)
            BriefLifecycle.synchronize(brief, outputs: outputs(for: brief, context: context))
        case .archive:
            BriefLifecycle.archive(brief)
        }
        if (choice == .move || choice == .pause),
           (brief.agendaDate == nil || brief.agendaDate == previousDate) {
            brief.agendaDate = output.targetDate
        }
        try? context.save()
    }

    func createRepurposedSpark(from brief: CreativeBrief, context: ModelContext) -> CreativeBrief? {
        createSpark(text: "A new angle from \(brief.title): \(brief.takeaway)", source: .repurposedBrief, context: context)
    }

    func askCy(_ message: String, conversation: [ConversationMessageWire]? = nil, about brief: CreativeBrief? = nil, context: ModelContext) async -> String? {
        guard can(.askCy, context: context) else { return nil }
        do {
            guard let profile = fetchOne(CreatorProfile.self, context: context),
                  let creatorContext = creatorContextWire(profile: profile, context: context) else {
                throw CreativeServiceError.invalidLiveResponse("the approved creator context is incomplete")
            }
            let resolvedConversation = conversation ?? [ConversationMessageWire(messageId: UUID(), role: .user, content: message)]
            return try await creativeService.reply(
                to: message,
                mode: profile.assistanceMode,
                context: creatorContext,
                conversation: resolvedConversation,
                relevantBriefIDs: brief.map { [$0.id] } ?? []
            )
        } catch {
            notice = .error(error.localizedDescription)
            return nil
        }
    }

    func proposedPillars(context: ModelContext) -> [Pillar] {
        let briefs = ((try? context.fetch(FetchDescriptor<CreativeBrief>())) ?? []).filter { $0.status != .spark && $0.status != .archived }
        guard briefs.count >= 3 else { return [] }
        return Array(briefs.prefix(3)).enumerated().map { index, brief in
            let fallback = ["Practical shifts", "Behind the work", "Starting points"][index]
            let name = brief.title.split(separator: " ").prefix(3).joined(separator: " ")
            return Pillar(name: name.isEmpty ? fallback : name, detail: "A recurring theme inferred from your developed briefs.")
        }
    }

    func acceptPillar(_ proposal: Pillar, context: ModelContext) {
        context.insert(Pillar(name: proposal.name, detail: proposal.detail, colorHex: proposal.colorHex))
        try? context.save()
    }

    func ensureWeek(startingAt requestedStart: Date, context: ModelContext) -> WeekPlan {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: requestedStart)?.start ?? calendar.startOfDay(for: requestedStart)
        let plans = (try? context.fetch(FetchDescriptor<WeekPlan>())) ?? []
        if let current = plans.first(where: { calendar.isDate($0.weekStart, inSameDayAs: start) }) { return current }
        let template = fetchOne(RhythmTemplate.self, context: context)
        let plan = WeekPlan(weekStart: start, rhythmEntriesText: template?.entriesText ?? "")
        context.insert(plan)
        try? context.save()
        return plan
    }

    func ensureCurrentWeek(context: ModelContext) -> WeekPlan {
        ensureWeek(startingAt: Date(), context: context)
    }

    func saveWeekToTemplate(_ plan: WeekPlan, context: ModelContext) {
        let template = fetchOne(RhythmTemplate.self, context: context) ?? RhythmTemplate()
        if template.modelContext == nil { context.insert(template) }
        template.entriesText = plan.rhythmEntriesText
        template.updatedAt = Date()
        try? context.save()
    }

    func export(context: ModelContext) {
        do {
            exportURL = try exportService.makeArchive(context: context)
        } catch {
            notice = .error("The export could not be prepared: \(error.localizedDescription)")
        }
    }

    func startTrial(context: ModelContext) async {
        guard let state = subscriptionState(context) else { return }
        do {
            try await subscriptionService.startTrial(state: state)
            try? context.save()
        } catch {
            notice = .error("The trial could not be started: \(error.localizedDescription)")
        }
    }

    func refreshAccess(context: ModelContext) async {
        guard let state = subscriptionState(context) else {
            notice = .error("Access state is unavailable. Existing data remains safe, but new creation is paused.")
            return
        }
        await subscriptionService.refresh(state: state)
        try? context.save()
    }

    func restorePurchases(context: ModelContext) async {
        guard let state = subscriptionState(context) else { return }
        do {
            try await subscriptionService.restore(state: state)
            try? context.save()
        } catch {
            notice = .error("Purchases could not be restored: \(error.localizedDescription)")
        }
    }

    func eraseAll(context: ModelContext) async {
        var completionNotice: AppNotice?
        let identity: InstallationIdentity?
        do {
            identity = try await credentialStore.load()
        } catch {
            if allowsOfflinePrivacyErase {
                identity = nil
                completionNotice = .info("Local data will be erased. This Debug or fixture run could not read a live installation credential.")
            } else {
                notice = .error("Erase paused because the installation credential could not be read. Local data and the credential were left intact so you can retry.")
                return
            }
        }

        if let identity {
            guard let privacyDeletionService else {
                if allowsOfflinePrivacyErase {
                    completionNotice = .info("Local data was erased. This Debug or fixture run did not have a live privacy service configured.")
                } else {
                    notice = .error("Erase paused because the privacy service is unavailable. Local data and the credential were left intact so you can retry.")
                    return
                }
                await finishLocalErase(context: context, completionNotice: completionNotice)
                return
            }
            do {
                _ = try await privacyDeletionService.deleteServerMetadata(for: identity)
                completionNotice = .info("Your local and server-linked data were erased. Only non-content anti-abuse and entitlement records remain on the server.")
            } catch {
                if allowsOfflinePrivacyErase {
                    completionNotice = .info("Local data was erased. This Debug or fixture run could not reach the privacy service.")
                } else {
                    notice = .error("Erase paused because server metadata could not be deleted: \(error.localizedDescription) Your local data and device credential were left intact so you can retry.")
                    return
                }
            }
        } else if completionNotice == nil {
            if allowsOfflinePrivacyErase {
                completionNotice = .info("Local data was erased. No live installation credential was present in this Debug or fixture run.")
            } else {
                notice = .error("Erase paused because no installation credential was available. Local data was left intact so you can retry after restoring access.")
                return
            }
        }

        await finishLocalErase(context: context, completionNotice: completionNotice)
    }

    private func finishLocalErase(context: ModelContext, completionNotice: AppNotice?) async {
        await reminderService.cancelAll()
        removeExportArchives()
        var credentialNotice: AppNotice?
        do {
            try await credentialStore.delete()
        } catch {
            credentialNotice = .error("Creator data was erased, but the device credential could not be removed: \(error.localizedDescription)")
        }
        deleteAll(CreatorProfile.self, context: context)
        deleteAll(VoiceExample.self, context: context)
        deleteAll(VoiceProfile.self, context: context)
        deleteAll(CreativeBrief.self, context: context)
        deleteAll(PendingBriefProposal.self, context: context)
        deleteAll(PendingVoiceProfileProposal.self, context: context)
        deleteAll(PlatformOutput.self, context: context)
        deleteAll(CreatorTask.self, context: context)
        deleteAll(Pillar.self, context: context)
        deleteAll(RhythmTemplate.self, context: context)
        deleteAll(WeekPlan.self, context: context)
        deleteAll(ConversationThread.self, context: context)
        deleteAll(ConversationMessage.self, context: context)
        deleteAll(ReminderSettings.self, context: context)
        deleteAll(SubscriptionState.self, context: context)
        var localDeletionNotice: AppNotice?
        do {
            try context.save()
        } catch {
            localDeletionNotice = .error("The local store could not confirm every deletion: \(error.localizedDescription)")
        }
        exportURL = nil
        briefProposals.removeAll()
        revisionProposals.removeAll()
        voiceProfileChangeProposal = nil
        hasInstallationCredential = false
        notice = localDeletionNotice ?? credentialNotice ?? completionNotice
    }

    func subscriptionState(_ context: ModelContext) -> SubscriptionState? {
        fetchOne(SubscriptionState.self, context: context)
    }

    func outputs(for brief: CreativeBrief, context: ModelContext) -> [PlatformOutput] {
        let id = brief.id
        let descriptor = FetchDescriptor<PlatformOutput>(predicate: #Predicate { $0.briefID == id }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addPlatformOutput(
        to brief: CreativeBrief,
        platform: CreatorPlatform,
        context: ModelContext
    ) -> PlatformOutput? {
        guard can(.editExisting, context: context), brief.status != .archived else { return nil }
        let existing = outputs(for: brief, context: context)
        guard !existing.contains(where: { $0.platform == platform }) else {
            notice = .info("\(platform.title) is already part of this brief.")
            return nil
        }
        let format: ContentFormat = existing.contains(where: { $0.platform == .youtubeVideo }) || brief.durationSeconds > 90
            ? .longForm
            : .shortForm
        guard platform.format == format else {
            notice = .info("Choose a \(format.title.lowercased()) platform for this brief.")
            return nil
        }

        let output = PlatformOutput(
            briefID: brief.id,
            platform: platform,
            status: [.ready, .scheduled, .posted].contains(brief.status) ? .ready : .draft
        )
        if let source = existing.first {
            output.caption = source.caption
            output.cta = source.cta
        } else {
            output.cta = brief.ctaIntent
        }
        if platform == .youtubeShorts || platform == .youtubeVideo {
            output.titleOverride = brief.title
        }
        context.insert(output)
        brief.updatedAt = Date()
        do {
            try context.save()
            return output
        } catch {
            context.delete(output)
            notice = .error("That platform could not be added.")
            return nil
        }
    }

    func deletePlatformOutput(
        _ output: PlatformOutput,
        from brief: CreativeBrief,
        context: ModelContext
    ) {
        guard can(.editExisting, context: context),
              brief.status != .archived,
              output.briefID == brief.id else { return }

        let remaining = outputs(for: brief, context: context).filter { $0.id != output.id }
        if let removedTarget = output.targetDate, brief.agendaDate == removedTarget {
            brief.agendaDate = remaining.compactMap(\.targetDate).min()
        }
        context.delete(output)
        BriefLifecycle.synchronize(brief, outputs: remaining)
        brief.updatedAt = Date()
        do {
            try context.save()
        } catch {
            notice = .error("That platform could not be deleted.")
        }
    }

    func tasks(for brief: CreativeBrief, context: ModelContext) -> [CreatorTask] {
        let id = brief.id
        let descriptor = FetchDescriptor<CreatorTask>(predicate: #Predicate { $0.briefID == id }, sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func subtasks(for task: CreatorTask, context: ModelContext) -> [CreatorTask] {
        let parentID = task.id
        let descriptor = FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.parentTaskID == parentID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func messages(for thread: ConversationThread, context: ModelContext) -> [ConversationMessage] {
        let id = thread.id
        let descriptor = FetchDescriptor<ConversationMessage>(predicate: #Predicate { $0.threadID == id }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func developmentThread(for brief: CreativeBrief, context: ModelContext) -> ConversationThread {
        let briefID = brief.id
        let descriptor = FetchDescriptor<ConversationThread>(predicate: #Predicate { $0.briefID == briefID })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let thread = ConversationThread(briefID: brief.id, title: "Develop \(brief.title)")
        context.insert(thread)
        let mode = fetchOne(CreatorProfile.self, context: context)?.assistanceMode ?? .collaborate
        switch mode {
        case .drive:
            break
        case .collaborate:
            context.insert(ConversationMessage(threadID: thread.id, role: .cy, text: "What is the one point you most want this video to make?"))
        case .lead:
            context.insert(ConversationMessage(
                threadID: thread.id,
                role: .cy,
                text: "Recommended first step: name the exact viewer and the one change you want for them. Assumption: this spark is strongest as one focused promise. What should that viewer understand or do afterward?"
            ))
        }
        try? context.save()
        return thread
    }

    private func apply(_ draft: BriefDraft, to brief: CreativeBrief) {
        brief.title = draft.title
        brief.premise = draft.premise
        brief.audience = draft.audience
        brief.creativeGoal = draft.goal
        brief.takeaway = draft.takeaway
        brief.durationSeconds = draft.durationSeconds
        brief.spokenHook = draft.spokenHook
        brief.firstFrameText = draft.firstFrameText
        brief.scriptBeats = draft.scriptBeats
        brief.close = draft.close
        brief.ctaIntent = draft.ctaIntent
        brief.filmingGuidance = draft.filmingGuidance
        brief.editingGuidance = draft.editingGuidance
        brief.assumptions = draft.assumptions
        brief.voiceConfidence = draft.voiceConfidence
        brief.updatedAt = Date()
    }

    private func apply(_ variant: PlatformVariantDraft, to output: PlatformOutput) {
        output.caption = variant.caption
        output.openingAdjustment = variant.openingAdjustment
        output.titleOverride = variant.titleOverride
        output.cta = variant.cta
        output.editChanges = variant.editChanges
    }

    private func localProposal(for brief: CreativeBrief, context: ModelContext) -> BriefProposal {
        let storedCanonical = brief.readyBriefPayloadJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode(ReadyBriefWire.self, from: $0) }
        let outputDrafts = outputs(for: brief, context: context).map { output in
            PlatformVariantDraft(
                platform: output.platform,
                caption: output.caption,
                openingAdjustment: output.openingAdjustment,
                titleOverride: output.titleOverride,
                cta: output.cta,
                editChanges: output.editChanges
            )
        }
        let variants = outputDrafts.isEmpty
            ? (storedCanonical?.platformVariants.map {
                PlatformVariantDraft(
                    platform: $0.platform,
                    caption: $0.caption ?? "",
                    openingAdjustment: $0.openingAdjustment ?? "",
                    titleOverride: $0.title ?? "",
                    cta: $0.ctaAdjustment ?? "",
                    editChanges: $0.editChanges.joined(separator: "\n")
                )
            } ?? [])
            : outputDrafts
        let taskDrafts = tasks(for: brief, context: context).map { task in
            ProposedCreatorTask(
                title: task.title,
                kind: task.kind,
                notes: task.notes,
                estimatedMinutes: task.estimatedMinutes,
                isRecordingMilestone: task.isRecordingMilestoneDesignated
            )
        }
        return BriefProposal(
            briefID: brief.id,
            draft: BriefDraft(
                title: brief.title,
                premise: brief.premise,
                audience: brief.audience,
                goal: brief.creativeGoal,
                takeaway: brief.takeaway,
                durationSeconds: brief.durationSeconds,
                spokenHook: brief.spokenHook,
                firstFrameText: brief.firstFrameText,
                scriptBeats: brief.scriptBeats,
                close: brief.close,
                ctaIntent: brief.ctaIntent,
                filmingGuidance: brief.filmingGuidance,
                editingGuidance: brief.editingGuidance,
                assumptions: brief.assumptions,
                voiceConfidence: brief.voiceConfidence
            ),
            variants: variants,
            tasks: taskDrafts,
            canonicalBrief: storedCanonical
        )
    }

    private func canonicalReadyBrief(for brief: CreativeBrief, baseline: BriefProposal) -> ReadyBriefWire {
        if let data = brief.readyBriefPayloadJSON.data(using: .utf8),
           let stored = try? JSONDecoder().decode(ReadyBriefWire.self, from: data),
           stored.briefId == brief.id {
            return stored.overlaying(baseline)
        }
        return fallbackReadyBrief(from: baseline)
    }

    private func fallbackReadyBrief(from proposal: BriefProposal) -> ReadyBriefWire {
        let fallback = ReadyBriefWire(
            briefId: proposal.briefID,
            title: proposal.draft.title,
            premise: proposal.draft.premise,
            audience: proposal.draft.audience,
            creativeGoal: proposal.draft.goal,
            desiredTakeaway: proposal.draft.takeaway,
            durationSeconds: proposal.draft.durationSeconds,
            spokenHook: proposal.draft.spokenHook,
            firstFrameText: proposal.draft.firstFrameText,
            scriptBeats: proposal.draft.scriptBeats.enumerated().map {
                ScriptBeatWire(order: $0.offset, label: "Beat \($0.offset + 1)", purpose: "Advance the idea", script: $0.element)
            },
            close: proposal.draft.close,
            ctaIntent: proposal.draft.ctaIntent,
            filmingGuidance: FilmingGuidanceWire(
                setup: proposal.draft.filmingGuidance.isEmpty ? "Use the creator’s available setup." : proposal.draft.filmingGuidance,
                shots: ["Primary talking-head take"],
                bRoll: [],
                delivery: "Use the approved voice profile.",
                editing: proposal.draft.editingGuidance.isEmpty ? "Keep the edit light." : proposal.draft.editingGuidance,
                audio: "Prioritize a clear voice recording.",
                onScreenText: [proposal.draft.firstFrameText]
            ),
            proposedTasks: [],
            assumptions: proposal.draft.assumptions,
            voiceConfidence: proposal.draft.voiceConfidence,
            platformVariants: []
        )
        return fallback.overlaying(proposal)
    }

    private func reconcileTasks(for brief: CreativeBrief, proposal: BriefRevisionProposal, context: ModelContext) {
        let existing = tasks(for: brief, context: context)
        let sourceSet = Set(proposal.sourceTaskIDs)
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var usedSourceIDs = Set<UUID>()
        let milestoneAlreadyEmitted = existing.contains(where: \.recordingMilestoneEmitted)

        for (index, proposed) in proposal.edited.tasks.enumerated() {
            let sourceTask = proposal.sourceTaskIDs.indices.contains(index) ? existingByID[proposal.sourceTaskIDs[index]] : nil
            let exactTask = existing.first {
                !usedSourceIDs.contains($0.id) && $0.title == proposed.title && $0.kind == proposed.kind
            }
            if let task = sourceTask ?? exactTask {
                usedSourceIDs.insert(task.id)
                if task.isCompleted || task.recordingMilestoneEmitted {
                    if task.title != proposed.title || task.kind != proposed.kind {
                        insertTask(proposed, for: brief, sortOrder: existing.count + index, milestoneAlreadyEmitted: milestoneAlreadyEmitted, context: context)
                    }
                } else {
                    task.title = proposed.title
                    task.kind = proposed.kind
                    task.notes = proposed.notes
                    task.estimatedMinutes = proposed.estimatedMinutes
                    task.sortOrder = index
                    task.isRecordingMilestoneDesignated = proposed.isRecordingMilestone && !milestoneAlreadyEmitted
                }
            } else {
                insertTask(proposed, for: brief, sortOrder: existing.count + index, milestoneAlreadyEmitted: milestoneAlreadyEmitted, context: context)
            }
        }

        for task in existing where sourceSet.contains(task.id) && !usedSourceIDs.contains(task.id) {
            if !task.isCompleted && !task.recordingMilestoneEmitted { context.delete(task) }
        }
    }

    private func insertTask(_ proposed: ProposedCreatorTask, for brief: CreativeBrief, sortOrder: Int, milestoneAlreadyEmitted: Bool, context: ModelContext) {
        context.insert(CreatorTask(
            briefID: brief.id,
            title: proposed.title,
            kind: proposed.kind,
            notes: proposed.notes,
            estimatedMinutes: proposed.estimatedMinutes,
            sortOrder: sortOrder,
            isRecordingMilestoneDesignated: proposed.isRecordingMilestone && !milestoneAlreadyEmitted
        ))
    }

    private func persist(proposal: BriefProposal, context: ModelContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(proposal)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let briefID = proposal.briefID
        let descriptor = FetchDescriptor<PendingBriefProposal>(
            predicate: #Predicate { $0.briefID == briefID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor).filter { $0.proposalKindRaw == "composition" }
        if let existing = records.first {
            existing.payloadJSON = payload
            existing.updatedAt = Date()
            for duplicate in records.dropFirst() { context.delete(duplicate) }
        } else {
            context.insert(PendingBriefProposal(briefID: proposal.briefID, payloadJSON: payload, proposalKindRaw: "composition"))
        }
    }

    private func persist(revision: BriefRevisionProposal, context: ModelContext) throws {
        let payload = try encodeJSONString(revision)
        let briefID = revision.briefID
        let descriptor = FetchDescriptor<PendingBriefProposal>(predicate: #Predicate { $0.briefID == briefID })
        let records = try context.fetch(descriptor).filter { $0.proposalKindRaw == "revision" }
        guard records.isEmpty else { throw CreativeServiceError.invalidLiveResponse("a revision proposal is already pending") }
        context.insert(PendingBriefProposal(briefID: briefID, payloadJSON: payload, proposalKindRaw: "revision"))
    }

    private func persist(voiceProposal: VoiceProfileChangeProposal, context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).allSatisfy({ $0.proposalKindRaw != "teach" }) else {
            throw CreativeServiceError.invalidLiveResponse("a voice-profile proposal is already pending")
        }
        context.insert(PendingVoiceProfileProposal(
            profileID: voiceProposal.profileID,
            sourceVersion: voiceProposal.sourceVersion,
            payloadJSON: try encodeJSONString(voiceProposal),
            proposalKindRaw: "teach"
        ))
    }

    private func persist(initialVoiceProposal: InitialVoiceProfileProposal, context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).allSatisfy({ $0.proposalKindRaw != "initial" }) else {
            throw CreativeServiceError.invalidLiveResponse("an initial voice-profile proposal is already pending")
        }
        context.insert(PendingVoiceProfileProposal(
            profileID: initialVoiceProposal.profileID,
            sourceVersion: 0,
            payloadJSON: try encodeJSONString(initialVoiceProposal),
            proposalKindRaw: "initial"
        ))
    }

    private func deletePendingProposals(for briefID: UUID, kind: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<PendingBriefProposal>(predicate: #Predicate { $0.briefID == briefID })
        for record in try context.fetch(descriptor) where record.proposalKindRaw == kind {
            context.delete(record)
        }
    }

    private func deletePendingVoiceProposals(context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()) { context.delete(record) }
    }

    private func deletePendingVoiceProposals(kind: String, context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()) where record.proposalKindRaw == kind {
            context.delete(record)
        }
    }

    private func encodeJSONString<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func validVoiceDraft(_ draft: VoiceProfileDraft) -> Bool {
        !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.tone.isEmpty &&
        !draft.sentenceStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.signatureQualities.isEmpty &&
        !draft.guidance.isEmpty &&
        (0...1).contains(draft.confidence)
    }

    private func onboardingVoiceProfile(from draft: OnboardingDraft) -> VoiceProfileWire? {
        guard let data = draft.voiceProfilePayloadJSON.data(using: .utf8),
              let baseline = try? JSONDecoder().decode(VoiceProfileWire.self, from: data) else {
            return nil
        }
        let summary = draft.voiceSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let signatureQualities = editableVoiceList(draft.voiceTraits)
        guard !summary.isEmpty, !signatureQualities.isEmpty else { return nil }

        return VoiceProfileWire(
            summary: summary,
            tone: baseline.tone,
            sentenceStyle: baseline.sentenceStyle,
            signatureQualities: signatureQualities,
            phrasesToUse: baseline.phrasesToUse,
            phrasesToAvoid: editableVoiceList(draft.voiceAvoid),
            guidance: baseline.guidance,
            confidence: baseline.confidence
        )
    }

    private func editableVoiceList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedExampleText(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    private func voiceEvidenceIssue(in context: CreatorContextWire) -> String? {
        guard context.voiceExamples.count >= 3 else {
            return "Add and review at least three real examples before Cy builds your voice profile."
        }
        return VoiceExampleEvidenceLimits.issue(in: context.voiceExamples)
    }

    private func removeExportArchives() {
        let fileManager = FileManager.default
        if let exportURL { try? fileManager.removeItem(at: exportURL) }
        let temporaryDirectory = fileManager.temporaryDirectory
        let candidates = (try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for candidate in candidates where candidate.lastPathComponent.hasPrefix("agentcy-export-") && candidate.pathExtension == "zip" {
            try? fileManager.removeItem(at: candidate)
        }
    }

    private func can(_ action: AccessAction, context: ModelContext) -> Bool {
        guard let state = subscriptionState(context) else {
            notice = .error("Access state is unavailable. New creation is paused so the free journey cannot be reset accidentally.")
            return false
        }
        let allowed = AccessPolicy.allows(action, state: state)
        if !allowed {
            notice = .info("Your existing work is still yours to edit and finish. Start the trial to create something new or ask Cy.")
        }
        return allowed
    }

    private func titleFromSpark(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).prefix(7).joined(separator: " ")
        guard let first = words.first else { return "Untitled spark" }
        return String(first).uppercased() + words.dropFirst()
    }

    private func brief(id: UUID, context: ModelContext) -> CreativeBrief? {
        let descriptor = FetchDescriptor<CreativeBrief>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, context: ModelContext) -> T? {
        try? context.fetch(FetchDescriptor<T>()).first
    }

    private func onboardingCreatorContext(from draft: OnboardingDraft) -> CreatorContextWire {
        let examples = draft.voiceExamples.filter(\.isUsableEvidence).prefix(5).enumerated().map { index, example in
            VoiceExampleWire(
                exampleId: example.id,
                order: index,
                text: example.trimmedText,
                source: example.source,
                creatorConfirmed: true
            )
        }
        return CreatorContextWire(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryGoal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedPlatforms: draft.platforms.sorted { $0.rawValue < $1.rawValue },
            voiceExamples: examples,
            voiceProfile: nil,
            pillars: [],
            librarySummaries: []
        )
    }

    private func creatorContextWire(profile: CreatorProfile, context: ModelContext) -> CreatorContextWire? {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = profile.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedPlatforms = Array(Set(profile.selectedPlatforms)).sorted { $0.rawValue < $1.rawValue }
        guard !name.isEmpty, !goal.isEmpty, !selectedPlatforms.isEmpty else { return nil }

        let storedExamples = ((try? context.fetch(FetchDescriptor<VoiceExample>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? [])
            .filter { $0.profileID == profile.id && $0.creatorConfirmed && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let voiceExamples = storedExamples.prefix(5).enumerated().map { index, example in
            VoiceExampleWire(
                exampleId: example.id,
                order: index,
                text: example.text.trimmingCharacters(in: .whitespacesAndNewlines),
                source: example.source,
                creatorConfirmed: true
            )
        }

        let approvedProfile = ((try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? [])
            .filter { $0.profileID == profile.id && $0.isApproved }
            .sorted {
                if $0.version == $1.version { return $0.updatedAt > $1.updatedAt }
                return $0.version > $1.version
            }
            .first
        let voiceProfile = approvedProfile.flatMap(voiceProfileWire)

        let pillars = ((try? context.fetch(FetchDescriptor<Pillar>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter { !$0.isArchived && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(10)
            .map { pillar in
                let detail = pillar.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                return PillarSummaryWire(pillarId: pillar.id, name: pillar.name.trimmingCharacters(in: .whitespacesAndNewlines), description: detail.isEmpty ? nil : detail)
            }

        let allOutputs = (try? context.fetch(FetchDescriptor<PlatformOutput>())) ?? []
        let summaries = ((try? context.fetch(FetchDescriptor<CreativeBrief>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? [])
            .filter {
                $0.status != .archived &&
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.premise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.takeaway.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .prefix(20)
            .map { brief -> BriefSummaryWire in
                let outputPlatforms = Array(Set(allOutputs.filter { $0.briefID == brief.id }.map(\.platform)))
                    .sorted { $0.rawValue < $1.rawValue }
                return BriefSummaryWire(
                    briefId: brief.id,
                    title: brief.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    premise: brief.premise.trimmingCharacters(in: .whitespacesAndNewlines),
                    takeaway: brief.takeaway.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: brief.status,
                    platforms: outputPlatforms.isEmpty ? selectedPlatforms : outputPlatforms
                )
            }

        return CreatorContextWire(
            name: name,
            primaryGoal: goal,
            selectedPlatforms: selectedPlatforms,
            voiceExamples: voiceExamples,
            voiceProfile: voiceProfile,
            pillars: Array(pillars),
            librarySummaries: Array(summaries)
        )
    }

    private func voiceProfileWire(_ profile: VoiceProfile) -> VoiceProfileWire? {
        if let data = profile.canonicalPayloadJSON.data(using: .utf8),
           let canonical = try? JSONDecoder().decode(VoiceProfileWire.self, from: data) {
            return canonical
        }
        let summary = profile.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let traits = splitProfileList(profile.traitsText)
        guard !summary.isEmpty, !traits.isEmpty else { return nil }
        return VoiceProfileWire(
            summary: summary,
            tone: Array(traits.prefix(4)),
            sentenceStyle: summary,
            signatureQualities: Array(traits.prefix(8)),
            phrasesToUse: [],
            phrasesToAvoid: Array(splitProfileList(profile.avoidText).prefix(12)),
            guidance: ["Preserve the approved voice summary and recurring traits."],
            confidence: 0.7
        )
    }

    private func splitProfileList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func conversationWire(_ messages: [ConversationMessage]) -> [ConversationMessageWire] {
        messages.suffix(24).map { message in
            ConversationMessageWire(
                messageId: message.id,
                role: message.role == .creator ? .user : .assistant,
                content: message.text
            )
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) {
        let values = (try? context.fetch(FetchDescriptor<T>())) ?? []
        values.forEach(context.delete)
    }
}
