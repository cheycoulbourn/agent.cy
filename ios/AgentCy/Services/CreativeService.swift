import Foundation

@MainActor
protocol CreativeServicing {
    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction
    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection]
    func findIdeasExecution(context: CreatorContextWire, mode: AssistanceMode) async throws -> CyExecution<[IdeaDirection]>
    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String
    func nextQuestionExecution(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> CyExecution<String>
    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal
    func composeProposalExecution(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> CyExecution<BriefProposal>
    func proposeRevision(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> BriefRevisionProposal
    func proposeRevisionExecution(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> CyExecution<BriefRevisionProposal>
    func proposeVoiceProfileChange(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> VoiceProfileChangeProposal
    func proposeVoiceProfileChangeExecution(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> CyExecution<VoiceProfileChangeProposal>
    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String
    func replyWithActions(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> ChatTurnResultWire
}

extension CreativeServicing {
    func nextQuestionExecution(
        for brief: CreativeBrief,
        turn: Int,
        answer: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        conversation: [ConversationMessageWire],
        postContext: String?
    ) async throws -> CyExecution<String> {
        CyExecution(
            value: try await nextQuestion(
                for: brief,
                turn: turn,
                answer: answer,
                mode: mode,
                context: context,
                conversation: conversation,
                postContext: postContext
            ),
            provider: .unmetered
        )
    }

    func findIdeasExecution(
        context: CreatorContextWire,
        mode: AssistanceMode
    ) async throws -> CyExecution<[IdeaDirection]> {
        CyExecution(
            value: try await findIdeas(context: context, mode: mode),
            provider: .hosted
        )
    }

    func composeProposalExecution(
        from brief: CreativeBrief,
        mode: AssistanceMode,
        context: CreatorContextWire,
        conversation: [ConversationMessageWire]
    ) async throws -> CyExecution<BriefProposal> {
        CyExecution(
            value: try await composeProposal(
                from: brief,
                mode: mode,
                context: context,
                conversation: conversation
            ),
            provider: .hosted
        )
    }

    func proposeRevisionExecution(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> CyExecution<BriefRevisionProposal> {
        CyExecution(
            value: try await proposeRevision(
                of: brief,
                localBriefID: localBriefID,
                revisionNumber: revisionNumber,
                scope: scope,
                instruction: instruction,
                mode: mode,
                context: context,
                baseline: baseline,
                sourceUpdatedAt: sourceUpdatedAt,
                sourceTaskIDs: sourceTaskIDs
            ),
            provider: .hosted
        )
    }

    func proposeVoiceProfileChangeExecution(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> CyExecution<VoiceProfileChangeProposal> {
        CyExecution(
            value: try await proposeVoiceProfileChange(
                profileID: profileID,
                sourceVersion: sourceVersion,
                sourceUpdatedAt: sourceUpdatedAt,
                current: current,
                instruction: instruction,
                mode: mode,
                context: context
            ),
            provider: .hosted
        )
    }

    func replyWithActions(
        to message: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        conversation: [ConversationMessageWire],
        relevantBriefIDs: [UUID]
    ) async throws -> ChatTurnResultWire {
        ChatTurnResultWire(
            assistantMessage: try await reply(
                to: message,
                mode: mode,
                context: context,
                conversation: conversation,
                relevantBriefIDs: relevantBriefIDs
            ),
            suggestions: [],
            proposedAction: nil
        )
    }
}

enum CreativeServiceError: LocalizedError {
    case missingInput
    case dialogueLimit
    case invalidCreatorContext(String)
    case invalidLiveResponse(String)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .missingInput: "Add a little more detail so Cy has something useful to work with."
        case .dialogueLimit: "You’ve reached eight turns. Build the post now or edit the idea yourself."
        case .invalidCreatorContext(let detail): detail
        case .invalidLiveResponse(let detail): "Cy returned a response that did not match the app contract: \(detail)"
        case .unsupportedOperation(let operation): "\(operation) is not available in this build."
        }
    }
}

@MainActor
struct PreviewCreativeService: CreativeServicing {
    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction {
        let usable = context.voiceExamples.filter(\.creatorConfirmed).map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard usable.count >= 3 else { throw CreativeServiceError.missingInput }
        let averageWords = usable.map { $0.split(separator: " ").count }.reduce(0, +) / usable.count
        let questionDriven = usable.contains { $0.contains("?") }
        let summary = "Clear, conversational guidance that gets to a useful point quickly."
        let traits = [
            averageWords < 45 ? "Concise sentences" : "Story-led explanations",
            questionDriven ? "Uses questions to create momentum" : "Uses confident declarative openings",
            "Specific, practical takeaways"
        ].joined(separator: ", ")
        let avoid = "Generic hype, forced urgency, and language that sounds more polished than human"
        let wire = VoiceProfileWire(
            summary: summary,
            tone: questionDriven ? ["conversational", "curious"] : ["direct", "grounded"],
            sentenceStyle: averageWords < 45 ? "Concise sentences with one practical point." : "Story-led explanations that resolve in a practical point.",
            signatureQualities: ["specific", "practical", "human"],
            phrasesToUse: [],
            phrasesToAvoid: ["you must", "game changer"],
            guidance: ["Use a real example before giving advice.", "Prefer one useful next move over a long checklist."],
            confidence: 0.84
        )
        return VoiceProfileExtraction(summary: summary, traits: traits, avoid: avoid, canonical: wire)
    }

    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] {
        let goal = context.primaryGoal.isEmpty ? "help your audience make progress" : context.primaryGoal
        let anchor = context.pillars.first?.name ?? "your real process"
        let suggestedPillarIDs = context.pillars.map(\.pillarId)
        return [
            IdeaDirection(
                title: "The small shift",
                premise: "Show one overlooked change that makes \(goal.lowercased()) easier.",
                opening: "The thing that finally made this click wasn’t what I expected.",
                assumption: "Your audience values a practical change they can try today.",
                suggestedPillarID: suggestedPillarIDs[safe: 0]
            ),
            IdeaDirection(
                title: "Behind the decision",
                premise: "Walk through a decision from \(anchor.lowercased()) and explain the tradeoff honestly.",
                opening: "I almost chose the obvious option. Here’s why I didn’t.",
                assumption: "Your audience learns from seeing your judgment, not just the finished result.",
                suggestedPillarID: suggestedPillarIDs[safe: 1]
            ),
            IdeaDirection(
                title: "What I’d do first",
                premise: "Give a grounded starting point for someone trying to \(goal.lowercased()).",
                opening: "If I had to start again this week, I’d begin here.",
                assumption: "Your audience needs a useful first move more than a complete system.",
                suggestedPillarID: suggestedPillarIDs[safe: 2]
            )
        ]
    }

    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String {
        guard turn < 8 else { throw CreativeServiceError.dialogueLimit }
        if mode == .drive {
            return "Got it. Ask about one part, or build the post when you are ready."
        }
        let questions = [
            "Who should feel like this was made specifically for them?",
            "What do you want that person to understand or do differently afterward?",
            "What real example, proof, or moment can make the point believable?",
            "What is the simplest useful takeaway you can leave them with?",
            "Is there anything you do not want this video to sound or feel like?",
            "What can you comfortably film with the time and setup you have?",
            "Which part should sound most like you, even if it is less polished?"
        ]
        if mode == .lead {
            return "Recommended next step: \(questions[min(max(turn, 0), questions.count - 1)])"
        }
        return questions[min(max(turn, 0), questions.count - 1)]
    }

    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal {
        let premise = brief.premise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !premise.isEmpty else { throw CreativeServiceError.missingInput }
        let title = brief.title == "Untitled spark" ? conciseTitle(from: premise) : brief.title
        let audience = brief.audience.isEmpty ? "A creator who is close to taking action but needs a clear first move" : brief.audience
        let goal = brief.creativeGoal.isEmpty ? context.primaryGoal : brief.creativeGoal
        let hook = brief.spokenHook.isEmpty ? "Here’s the part of \(premise.lowercased()) that most people skip." : brief.spokenHook
        let draft = BriefDraft(
            title: title,
            premise: premise,
            audience: audience,
            goal: goal.isEmpty ? "Make one useful idea easy to act on" : goal,
            takeaway: brief.takeaway.isEmpty ? "Start with the smallest version that creates real momentum." : brief.takeaway,
            durationSeconds: (ContentFormat.shortForm.durationOptions + ContentFormat.longForm.durationOptions).contains(brief.durationSeconds)
                ? brief.durationSeconds
                : ContentFormat.shortForm.defaultDuration,
            spokenHook: hook,
            firstFrameText: brief.firstFrameText.isEmpty ? title.uppercased() : brief.firstFrameText,
            scriptBeats: [
                hook,
                "Name the familiar situation in one concrete sentence.",
                "Share the decision, example, or evidence that changed your view.",
                "Translate it into one practical next step."
            ],
            close: brief.close.isEmpty ? "Try the small version first, then build from what you learn." : brief.close,
            ctaIntent: brief.ctaIntent.isEmpty ? "Invite the viewer to save the idea or share their own first step" : brief.ctaIntent,
            filmingGuidance: brief.filmingGuidance.isEmpty ? "Eye-level talking head near a window; capture one close B-roll detail that proves the point." : brief.filmingGuidance,
            editingGuidance: brief.editingGuidance.isEmpty ? "Keep the opening immediate, use clean captions, and cut only where the thought naturally turns." : brief.editingGuidance,
            assumptions: ["The viewer prefers clarity over spectacle.", "The creator can film a direct-to-camera setup."],
            voiceConfidence: context.voiceExamples.filter(\.creatorConfirmed).count >= 3 ? 0.84 : 0.62
        )
        return BriefProposal(
            briefID: brief.id,
            draft: draft,
            variants: previewPlatformVariants(for: draft, platforms: context.selectedPlatforms),
            tasks: [
                ProposedCreatorTask(title: "Read the post aloud and tighten any line that is not yours", kind: .scripting, estimatedMinutes: 10),
                ProposedCreatorTask(title: "Film the primary take", kind: .filming, estimatedMinutes: 30, isRecordingMilestone: true),
                ProposedCreatorTask(title: "Assemble the clean first edit", kind: .editing, estimatedMinutes: 35),
                ProposedCreatorTask(title: "Prepare the selected platforms", kind: .publishing, estimatedMinutes: 15)
            ]
        )
    }

    func proposeRevision(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> BriefRevisionProposal {
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CreativeServiceError.missingInput }
        var revised = brief
        let suffix = " Clearer and more specific."
        switch scope {
        case .title:
            revised = replacing(revised, title: revised.title + " refined")
        case .premise:
            revised = replacing(revised, premise: revised.premise + suffix)
        case .audience:
            revised = replacing(revised, audience: revised.audience + " who wants one practical next step")
        case .creativeGoal:
            revised = replacing(revised, creativeGoal: revised.creativeGoal + suffix)
        case .desiredTakeaway:
            revised = replacing(revised, desiredTakeaway: revised.desiredTakeaway + suffix)
        case .durationSeconds:
            let format: ContentFormat = revised.durationSeconds >= 300 ? .longForm : .shortForm
            let durations = format.durationOptions
            let next = durations.firstIndex(of: revised.durationSeconds)
                .map { durations[($0 + 1) % durations.count] }
                ?? format.defaultDuration
            revised = replacing(revised, durationSeconds: next)
        case .spokenHook:
            revised = replacing(revised, spokenHook: "Try this sharper opening: \(revised.spokenHook)")
        case .firstFrameText:
            revised = replacing(revised, firstFrameText: "START WITH ONE CLEAR MOVE")
        case .scriptBeats:
            var beats = revised.scriptBeats
            if beats.isEmpty {
                beats = [ScriptBeatWire(order: 0, label: "Make it concrete", purpose: "Give the viewer a usable move", script: "Show the smallest version they can try today.")]
            } else {
                beats[0] = ScriptBeatWire(order: beats[0].order, label: beats[0].label, purpose: beats[0].purpose, script: beats[0].script + suffix)
            }
            revised = replacing(revised, scriptBeats: beats)
        case .close:
            revised = replacing(revised, close: revised.close + " Choose the version you can make today.")
        case .ctaIntent:
            revised = replacing(revised, ctaIntent: "Invite the viewer to save this and try the smallest version today.")
        case .filmingGuidance:
            var guidance = revised.filmingGuidance
            guidance = FilmingGuidanceWire(setup: guidance.setup, shots: guidance.shots + ["One close detail"], bRoll: guidance.bRoll, delivery: "Keep the delivery calm and conversational.", editing: guidance.editing, audio: guidance.audio, onScreenText: guidance.onScreenText)
            revised = replacing(revised, filmingGuidance: guidance)
        case .proposedTasks:
            var tasks = revised.proposedTasks
            if tasks.isEmpty {
                tasks = [ProposedTaskWire(title: "Read the revised post aloud", kind: .scripting, notes: "Keep only lines that sound like you.", estimatedMinutes: 10, isRecordingMilestone: false, order: 0)]
            } else {
                let first = tasks[0]
                tasks[0] = ProposedTaskWire(title: first.title, kind: first.kind, notes: "Use the revision instruction: \(cleaned)", estimatedMinutes: first.estimatedMinutes, isRecordingMilestone: first.isRecordingMilestone, order: first.order)
            }
            revised = replacing(revised, proposedTasks: tasks)
        case .assumptions:
            revised = replacing(revised, assumptions: revised.assumptions + ["This revision follows the creator’s instruction: \(cleaned)"])
        case .platformVariants:
            var variants = revised.platformVariants
            if !variants.isEmpty {
                let first = variants[0]
                variants[0] = PlatformVariantWire(platform: first.platform, caption: (first.caption ?? revised.desiredTakeaway) + " Try the smallest version first.", title: first.title, openingAdjustment: first.openingAdjustment, ctaAdjustment: first.ctaAdjustment, editChanges: first.editChanges)
            }
            revised = replacing(revised, platformVariants: variants)
        case .wholeBrief:
            revised = replacing(revised, desiredTakeaway: revised.desiredTakeaway + suffix, spokenHook: "Here is the useful part most people skip: \(revised.spokenHook)")
        }
        let edited = revised.proposal(for: localBriefID)
        return BriefRevisionProposal(
            briefID: localBriefID,
            sourceUpdatedAt: sourceUpdatedAt,
            requestedScope: scope,
            instruction: cleaned,
            changedFields: [scope],
            explanation: "Cy prepared a focused \(scope.title.lowercased()) revision from your instruction. Nothing changes until you accept it.",
            baseline: baseline,
            edited: edited,
            sourceTaskIDs: sourceTaskIDs,
            canonicalBrief: revised
        )
    }

    func proposeVoiceProfileChange(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> VoiceProfileChangeProposal {
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CreativeServiceError.missingInput }
        var edited = current
        let guidance = "Apply this creator-approved teaching: \(cleaned)"
        if !edited.guidance.contains(guidance) { edited.guidance.append(guidance) }
        edited.summary = current.summary + " The voice now follows one explicit creator instruction."
        return VoiceProfileChangeProposal(
            profileID: profileID,
            sourceVersion: sourceVersion,
            sourceUpdatedAt: sourceUpdatedAt,
            instruction: cleaned,
            baseline: current,
            edited: edited,
            assumptions: ["The instruction describes how the creator wants future writing to sound."],
            evidenceNotes: ["This proposal is based on the approved profile plus the visible teaching instruction."]
        )
    }

    private func previewPlatformVariants(for draft: BriefDraft, platforms: [CreatorPlatform]) -> [PlatformVariantDraft] {
        platforms.map { platform in
            switch platform {
            case .instagramReels:
                PlatformVariantDraft(platform: platform, caption: "\(draft.takeaway)\n\nSave this for the next time you feel stuck.", openingAdjustment: "Lead with the first-frame text before the spoken hook.", titleOverride: "", cta: "Save this for your next filming session.", editChanges: "Use readable in-frame captions and a clean cover frame.")
            case .tiktok:
                PlatformVariantDraft(platform: platform, caption: draft.takeaway, openingAdjustment: "Start mid-thought and deliver the hook in the first breath.", titleOverride: "", cta: "What would your smallest version look like?", editChanges: "Favor conversational pacing and one pattern interrupt after the proof beat.")
            case .youtubeShorts:
                PlatformVariantDraft(platform: platform, caption: draft.takeaway, openingAdjustment: "State the promise cleanly before adding context.", titleOverride: draft.title, cta: "Subscribe for more practical creator systems.", editChanges: "Keep the title searchable and the close self-contained.")
            case .youtubeVideo:
                PlatformVariantDraft(platform: platform, caption: draft.takeaway, openingAdjustment: "Open with the clearest promise, then preview the path through the full video.", titleOverride: draft.title, cta: "Subscribe for the next practical creator guide.", editChanges: "Use chapters, room for examples, and a deliberate closing recap.")
            }
        }
    }

    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CreativeServiceError.missingInput }
        if let brief = context.librarySummaries.first(where: { relevantBriefIDs.contains($0.briefId) }) {
            return "For “\(brief.title),” I’d protect the core premise and simplify the next move: make the opening specific, use one real example, then end with one action your viewer can take. Nothing changes until you approve it."
        }
        let goal = context.primaryGoal.isEmpty ? "your creator goal" : context.primaryGoal
        return "Given \(goal.lowercased()), choose the idea you can explain from lived experience today. I can help shape it into a post, but I won’t save changes without your approval."
    }

    private func conciseTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(7).joined(separator: " ")
        return words.isEmpty ? "Untitled spark" : words.prefix(1).uppercased() + words.dropFirst()
    }

    private func replacing(
        _ brief: ReadyBriefWire,
        title: String? = nil,
        premise: String? = nil,
        audience: String? = nil,
        creativeGoal: String? = nil,
        desiredTakeaway: String? = nil,
        durationSeconds: Int? = nil,
        spokenHook: String? = nil,
        firstFrameText: String? = nil,
        scriptBeats: [ScriptBeatWire]? = nil,
        close: String? = nil,
        ctaIntent: String? = nil,
        filmingGuidance: FilmingGuidanceWire? = nil,
        proposedTasks: [ProposedTaskWire]? = nil,
        assumptions: [String]? = nil,
        platformVariants: [PlatformVariantWire]? = nil
    ) -> ReadyBriefWire {
        ReadyBriefWire(
            briefId: brief.briefId,
            title: title ?? brief.title,
            premise: premise ?? brief.premise,
            audience: audience ?? brief.audience,
            creativeGoal: creativeGoal ?? brief.creativeGoal,
            desiredTakeaway: desiredTakeaway ?? brief.desiredTakeaway,
            durationSeconds: durationSeconds ?? brief.durationSeconds,
            spokenHook: spokenHook ?? brief.spokenHook,
            firstFrameText: firstFrameText ?? brief.firstFrameText,
            scriptBeats: scriptBeats ?? brief.scriptBeats,
            close: close ?? brief.close,
            ctaIntent: ctaIntent ?? brief.ctaIntent,
            filmingGuidance: filmingGuidance ?? brief.filmingGuidance,
            proposedTasks: proposedTasks ?? brief.proposedTasks,
            assumptions: assumptions ?? brief.assumptions,
            voiceConfidence: brief.voiceConfidence,
            platformVariants: platformVariants ?? brief.platformVariants
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum SparkContextBuilder {
    static func text(for brief: CreativeBrief, postContext: String?) -> String {
        let candidates = [
            brief.title,
            brief.premise,
            brief.spokenHook,
            brief.scriptBeatsText,
            brief.notes,
            brief.ctaIntent,
            postContext ?? ""
        ]

        var seen = Set<String>()
        let parts = candidates.compactMap { candidate -> String? in
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }

        return AIRequestNormalizer.text(parts.joined(separator: "\n\n"), maxUTF16Units: 20_000)
    }
}

/// Keeps locally persisted creator content inside the canonical AI contract.
///
/// Swift counts extended grapheme clusters while Zod/JavaScript counts UTF-16
/// code units. Truncating with `String.prefix` can therefore still produce a
/// request that the server rejects (especially when the content contains emoji).
/// Normalize once at the provider boundary so a stale or oversized library item
/// cannot prevent Cy from reading an otherwise valid post.
enum AIRequestNormalizer {
    static func text(_ value: String, maxUTF16Units: Int) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.utf16.count > maxUTF16Units else { return cleaned }

        var units = Array(cleaned.utf16.prefix(maxUTF16Units))
        if let last = units.last, (0xD800...0xDBFF).contains(last) {
            units.removeLast()
        }
        return String(decoding: units, as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optionalText(_ value: String?, maxUTF16Units: Int) -> String? {
        guard let value else { return nil }
        let cleaned = text(value, maxUTF16Units: maxUTF16Units)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func creatorContext(_ context: CreatorContextWire) -> CreatorContextWire {
        let platforms = uniquePlatforms(context.selectedPlatforms)
        let safePlatforms = platforms.isEmpty ? [.instagramReels] : platforms

        let pillars = context.pillars.prefix(10).compactMap { pillar -> PillarSummaryWire? in
            let name = text(pillar.name, maxUTF16Units: 160)
            guard !name.isEmpty else { return nil }
            return PillarSummaryWire(
                pillarId: pillar.pillarId,
                name: name,
                description: optionalText(pillar.description, maxUTF16Units: 2_000)
            )
        }

        let library = context.librarySummaries.prefix(20).compactMap { summary -> BriefSummaryWire? in
            let title = text(summary.title, maxUTF16Units: 160)
            guard !title.isEmpty else { return nil }
            let summaryPlatforms = uniquePlatforms(summary.platforms)
            let taskCount = min(max(summary.taskCount, 0), 100)
            let completedTaskCount = min(max(summary.completedTaskCount, 0), taskCount)
            return BriefSummaryWire(
                briefId: summary.briefId,
                title: title,
                premise: optionalText(summary.premise, maxUTF16Units: 2_000),
                takeaway: optionalText(summary.takeaway, maxUTF16Units: 2_000),
                notes: optionalText(summary.notes, maxUTF16Units: 500),
                hook: optionalText(summary.hook, maxUTF16Units: 500),
                caption: optionalText(summary.caption, maxUTF16Units: 500),
                pillarId: summary.pillarId,
                pillarName: optionalText(summary.pillarName, maxUTF16Units: 160),
                format: optionalText(summary.format, maxUTF16Units: 160),
                status: summary.status,
                platforms: summaryPlatforms.isEmpty ? safePlatforms : summaryPlatforms,
                targetDate: summary.targetDate,
                includesTargetTime: summary.includesTargetTime,
                postedAt: summary.postedAt,
                taskCount: taskCount,
                completedTaskCount: completedTaskCount
            )
        }

        let tasks = context.taskSummaries.prefix(20).compactMap { task -> TaskSummaryWire? in
            let title = text(task.title, maxUTF16Units: 160)
            guard !title.isEmpty else { return nil }
            return TaskSummaryWire(
                taskId: task.taskId,
                title: title,
                kind: task.kind,
                priority: task.priority,
                isCompleted: task.isCompleted,
                targetDate: task.targetDate,
                includesTargetTime: task.includesTargetTime,
                postId: task.postId,
                pillarId: task.pillarId
            )
        }

        return CreatorContextWire(
            name: nonempty(text(context.name, maxUTF16Units: 80)) ?? "Creator",
            primaryGoal: nonempty(text(context.primaryGoal, maxUTF16Units: 2_000)) ?? "Create clear, authentic content.",
            selectedPlatforms: safePlatforms,
            // Voice personalization is dormant in this release. Excluding it
            // here also prevents retained legacy records from invalidating a
            // current Spark request.
            voiceExamples: [],
            voiceProfile: nil,
            pillars: Array(pillars),
            librarySummaries: Array(library),
            taskSummaries: Array(tasks)
        )
    }

    static func spark(_ spark: SparkWire) -> SparkWire {
        let value = text(spark.text, maxUTF16Units: 20_000)
        return SparkWire(
            sparkId: spark.sparkId,
            source: spark.source,
            text: nonempty(value) ?? "Untitled post",
            sourceBriefId: spark.sourceBriefId
        )
    }

    static func conversation(_ messages: [ConversationMessageWire], limit: Int) -> [ConversationMessageWire] {
        messages.suffix(limit).compactMap { message in
            let content = text(message.content, maxUTF16Units: 20_000)
            guard !content.isEmpty else { return nil }
            return ConversationMessageWire(messageId: message.messageId, role: message.role, content: content)
        }
    }

    static func developmentState(_ state: SparkDevelopmentStateWire) -> SparkDevelopmentStateWire {
        SparkDevelopmentStateWire(
            premise: optionalText(state.premise, maxUTF16Units: 2_000),
            audience: optionalText(state.audience, maxUTF16Units: 2_000),
            creativeGoal: optionalText(state.creativeGoal, maxUTF16Units: 2_000),
            proofOrStory: optionalText(state.proofOrStory, maxUTF16Units: 2_000),
            desiredTakeaway: optionalText(state.desiredTakeaway, maxUTF16Units: 2_000),
            constraints: state.constraints.prefix(10).compactMap {
                optionalText($0, maxUTF16Units: 2_000)
            }
        )
    }

    private static func uniquePlatforms(_ values: [CreatorPlatform]) -> [CreatorPlatform] {
        var seen = Set<CreatorPlatform>()
        return values.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }

    private static func nonempty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

@MainActor
struct RemoteCreativeService: CreativeServicing {
    private let client: AgentCyAPIClient
    private let operationIDs: AIOperationIDRegistry
    private static let fingerprintOperationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    init(
        client: AgentCyAPIClient = AgentCyAPIClient(),
        operationIDs: AIOperationIDRegistry = .shared
    ) {
        self.client = client
        self.operationIDs = operationIDs
    }

    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction {
        try validateContext(context)
        guard (3...5).contains(context.voiceExamples.filter(\.creatorConfirmed).count) else { throw CreativeServiceError.missingInput }
        let result = try await perform(operation: .voiceProfile, result: VoiceProfileResultWire.self) { operationID in
            VoiceProfileRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.voiceProfilePrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: context,
                intent: .onboarding,
                teachingInstruction: nil
            )
        }
        let profile = result.profile
        guard !profile.summary.isEmpty,
              !profile.tone.isEmpty,
              !profile.signatureQualities.isEmpty,
              !profile.guidance.isEmpty,
              (0...1).contains(profile.confidence) else {
            throw CreativeServiceError.invalidLiveResponse("voice profile fields were incomplete")
        }
        let traits = (profile.tone + profile.signatureQualities + [profile.sentenceStyle]).joined(separator: ", ")
        return VoiceProfileExtraction(summary: profile.summary, traits: traits, avoid: profile.phrasesToAvoid.joined(separator: ", "), canonical: profile)
    }

    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] {
        let execution = try await findIdeasExecution(context: context, mode: mode)
        return execution.value
    }

    func findIdeasExecution(
        context: CreatorContextWire,
        mode: AssistanceMode
    ) async throws -> CyExecution<[IdeaDirection]> {
        let safeContext = AIRequestNormalizer.creatorContext(context)
        try validateContext(safeContext)
        let execution = try await performWithProvider(
            operation: .ideas,
            result: IdeasResultWire.self,
            validateResult: { result in
                guard result.ideas.count == 3,
                      Set(result.ideas.map(\.directionId)).count == 3,
                      Set(result.ideas.map(\.title)).count == 3 else {
                    throw CreativeServiceError.invalidLiveResponse("ideation must return three distinct directions")
                }
            }
        ) { operationID in
            IdeasRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.ideasPrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: safeContext,
                count: 3,
                startingPoint: nil,
                constraints: []
            )
        }
        let result = execution.value
        let validPillarIDs = Set(safeContext.pillars.map(\.pillarId))
        let ideas = result.ideas.map { idea in
            IdeaDirection(
                title: idea.title,
                premise: idea.premise,
                opening: idea.opening,
                assumption: idea.assumptions.first ?? idea.assumedTakeaway,
                suggestedPillarID: idea.suggestedPillarId.flatMap { validPillarIDs.contains($0) ? $0 : nil }
            )
        }
        return CyExecution(value: ideas, provider: execution.provider)
    }

    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String {
        try await nextQuestionExecution(
            for: brief,
            turn: turn,
            answer: answer,
            mode: mode,
            context: context,
            conversation: conversation,
            postContext: postContext
        ).value
    }

    func nextQuestionExecution(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> CyExecution<String> {
        guard turn < 8 else { throw CreativeServiceError.dialogueLimit }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CreativeServiceError.missingInput }
        let safeContext = AIRequestNormalizer.creatorContext(context)
        try validateContext(safeContext)
        let safeSpark = AIRequestNormalizer.spark(spark(from: brief, postContext: postContext))
        guard !safeSpark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CreativeServiceError.missingInput
        }
        let safeConversation = AIRequestNormalizer.conversation(conversation, limit: 16)
        let safeState = AIRequestNormalizer.developmentState(developmentState(from: brief))
        let execution = try await performWithProvider(
            operation: .sparkTurn,
            result: SparkTurnResultWire.self,
            validateResult: { result in
                guard !result.assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CreativeServiceError.invalidLiveResponse("dialogue response was empty")
                }
            }
        ) { operationID in
            SparkTurnRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.sparkTurnPrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: safeContext,
                spark: safeSpark,
                turnNumber: turn + 1,
                composeNow: false,
                conversation: safeConversation,
                workingState: safeState
            )
        }
        let result = execution.value
        return CyExecution(value: result.assistantMessage, provider: execution.provider)
    }

    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal {
        let execution = try await composeProposalExecution(
            from: brief,
            mode: mode,
            context: context,
            conversation: conversation
        )
        return execution.value
    }

    func composeProposalExecution(
        from brief: CreativeBrief,
        mode: AssistanceMode,
        context: CreatorContextWire,
        conversation: [ConversationMessageWire]
    ) async throws -> CyExecution<BriefProposal> {
        let safeContext = AIRequestNormalizer.creatorContext(context)
        try validateContext(safeContext)
        let safeSpark = AIRequestNormalizer.spark(spark(from: brief, postContext: nil))
        let safeConversation = AIRequestNormalizer.conversation(conversation, limit: 16)
        let safeState = AIRequestNormalizer.developmentState(developmentState(from: brief))
        guard (ContentFormat.shortForm.durationOptions + ContentFormat.longForm.durationOptions).contains(brief.durationSeconds) else {
            throw CreativeServiceError.invalidLiveResponse("the selected duration is unsupported")
        }
        let execution = try await performWithProvider(operation: .composeBrief, result: ComposeBriefResultWire.self) { operationID in
            ComposeBriefRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.composeBriefPrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: safeContext,
                briefId: brief.id,
                spark: safeSpark,
                conversation: safeConversation,
                workingState: safeState,
                durationSeconds: brief.durationSeconds,
                selectedPlatforms: safeContext.selectedPlatforms,
                additionalDirection: nil
            )
        }
        let result = execution.value
        let readyBrief = result.brief
        guard readyBrief.briefId == brief.id else {
            throw CreativeServiceError.invalidLiveResponse("brief ID changed")
        }
        guard readyBrief.durationSeconds == brief.durationSeconds else {
            throw CreativeServiceError.invalidLiveResponse("duration changed from the creator selection")
        }
        let returnedPlatforms = readyBrief.platformVariants.map(\.platform)
        guard Set(returnedPlatforms) == Set(safeContext.selectedPlatforms), returnedPlatforms.count == safeContext.selectedPlatforms.count else {
            throw CreativeServiceError.invalidLiveResponse("platform variants did not match the creator selection")
        }
        let milestones = readyBrief.proposedTasks.filter(\.isRecordingMilestone)
        guard milestones.count <= 1, milestones.allSatisfy({ $0.kind == .filming }) else {
            throw CreativeServiceError.invalidLiveResponse("recording milestone task was invalid")
        }
        return CyExecution(
            value: readyBrief.proposal(for: brief.id),
            provider: execution.provider
        )
    }

    func proposeRevision(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> BriefRevisionProposal {
        let execution = try await proposeRevisionExecution(
            of: brief,
            localBriefID: localBriefID,
            revisionNumber: revisionNumber,
            scope: scope,
            instruction: instruction,
            mode: mode,
            context: context,
            baseline: baseline,
            sourceUpdatedAt: sourceUpdatedAt,
            sourceTaskIDs: sourceTaskIDs
        )
        return execution.value
    }

    func proposeRevisionExecution(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> CyExecution<BriefRevisionProposal> {
        let safeContext = AIRequestNormalizer.creatorContext(context)
        try validateContext(safeContext)
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CreativeServiceError.missingInput }
        let safeInstruction = AIRequestNormalizer.text(cleaned, maxUTF16Units: 20_000)
        let execution = try await performWithProvider(operation: .reviseBrief, result: ReviseBriefResultWire.self) { operationID in
            ReviseBriefRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.reviseBriefPrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: safeContext,
                brief: brief,
                revisionNumber: revisionNumber,
                scope: scope,
                instruction: safeInstruction
            )
        }
        let result = execution.value
        guard result.brief.briefId == brief.briefId, result.brief.briefId == localBriefID else {
            throw CreativeServiceError.invalidLiveResponse("brief ID changed")
        }
        let expectedPlatforms = brief.platformVariants.map(\.platform)
        let returnedPlatforms = result.brief.platformVariants.map(\.platform)
        guard Set(returnedPlatforms) == Set(expectedPlatforms), returnedPlatforms.count == expectedPlatforms.count else {
            throw CreativeServiceError.invalidLiveResponse("platform variants changed")
        }
        guard result.changedFields.contains(scope), Set(result.changedFields).count == result.changedFields.count else {
            throw CreativeServiceError.invalidLiveResponse("the requested revision scope was not confirmed")
        }
        let milestones = result.brief.proposedTasks.filter(\.isRecordingMilestone)
        guard milestones.count <= 1, milestones.allSatisfy({ $0.kind == .filming }) else {
            throw CreativeServiceError.invalidLiveResponse("recording milestone task was invalid")
        }
        guard !result.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.brief != brief else {
            throw CreativeServiceError.invalidLiveResponse("the revision did not contain a meaningful change")
        }
        return CyExecution(
            value: BriefRevisionProposal(
                briefID: localBriefID,
                sourceUpdatedAt: sourceUpdatedAt,
                requestedScope: scope,
                instruction: cleaned,
                changedFields: result.changedFields,
                explanation: result.explanation,
                baseline: baseline,
                edited: result.brief.proposal(for: localBriefID),
                sourceTaskIDs: sourceTaskIDs,
                canonicalBrief: result.brief
            ),
            provider: execution.provider
        )
    }

    func proposeVoiceProfileChange(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> VoiceProfileChangeProposal {
        let execution = try await proposeVoiceProfileChangeExecution(
            profileID: profileID,
            sourceVersion: sourceVersion,
            sourceUpdatedAt: sourceUpdatedAt,
            current: current,
            instruction: instruction,
            mode: mode,
            context: context
        )
        return execution.value
    }

    func proposeVoiceProfileChangeExecution(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> CyExecution<VoiceProfileChangeProposal> {
        try validateContext(context)
        let cleaned = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CreativeServiceError.missingInput }
        let execution = try await performWithProvider(operation: .voiceProfile, result: VoiceProfileResultWire.self) { operationID in
            VoiceProfileRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.voiceProfilePrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: context,
                intent: .teachCy,
                teachingInstruction: cleaned
            )
        }
        let result = execution.value
        let edited = VoiceProfileDraft(result.profile)
        guard edited != current else {
            throw CreativeServiceError.invalidLiveResponse("Teach Cy returned the current profile without a change")
        }
        guard !edited.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !edited.tone.isEmpty,
              !edited.signatureQualities.isEmpty,
              !edited.guidance.isEmpty,
              (0...1).contains(edited.confidence) else {
            throw CreativeServiceError.invalidLiveResponse("the proposed voice profile was incomplete")
        }
        return CyExecution(
            value: VoiceProfileChangeProposal(
                profileID: profileID,
                sourceVersion: sourceVersion,
                sourceUpdatedAt: sourceUpdatedAt,
                instruction: cleaned,
                baseline: current,
                edited: edited,
                assumptions: result.assumptions,
                evidenceNotes: result.evidenceNotes
            ),
            provider: execution.provider
        )
    }

    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String {
        try await replyWithActions(
            to: message,
            mode: mode,
            context: context,
            conversation: conversation,
            relevantBriefIDs: relevantBriefIDs
        ).assistantMessage
    }

    func replyWithActions(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> ChatTurnResultWire {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CreativeServiceError.missingInput }
        let safeContext = AIRequestNormalizer.creatorContext(context)
        try validateContext(safeContext)
        let boundedConversation = AIRequestNormalizer.conversation(conversation, limit: 24)
        guard !boundedConversation.isEmpty else { throw CreativeServiceError.missingInput }
        let result = try await perform(
            operation: .chatTurn,
            result: ChatTurnResultWire.self,
            validateResult: { result in
                guard !result.assistantMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CreativeServiceError.invalidLiveResponse("chat response was empty")
                }
            }
        ) { operationID in
            ChatTurnRequestWire(
                schemaVersion: AIContractVersion.schema,
                promptVersion: AIContractVersion.chatTurnPrompt,
                operationId: operationID,
                appBuild: APIConfiguration.appBuild,
                assistanceMode: mode,
                creatorContext: safeContext,
                conversation: boundedConversation,
                relevantBriefIds: Array(stableUnique(relevantBriefIDs).prefix(5))
            )
        }
        return result
    }

    private func validateContext(_ context: CreatorContextWire) throws {
        if let issue = VoiceExampleEvidenceLimits.issue(in: context.voiceExamples) {
            throw CreativeServiceError.invalidCreatorContext(issue)
        }
        guard !context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !context.primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !context.selectedPlatforms.isEmpty,
              context.selectedPlatforms.count <= 4,
              context.voiceExamples.count <= 5,
              context.voiceExamples.allSatisfy(\.creatorConfirmed),
              context.pillars.count <= 10,
              context.librarySummaries.count <= 20,
              context.taskSummaries.count <= 20 else {
            throw CreativeServiceError.invalidCreatorContext("Cy could not use this creator context safely. Review your profile and try again.")
        }
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private func perform<Request: AIRequestIdentifying, Result: Decodable & Sendable>(
        operation: AIOperation,
        result: Result.Type,
        validateResult: (@Sendable (Result) throws -> Void)? = nil,
        makeRequest: (UUID) -> Request
    ) async throws -> Result {
        let execution = try await performWithProvider(
            operation: operation,
            result: result,
            validateResult: validateResult,
            makeRequest: makeRequest
        )
        return execution.value
    }

    private func performWithProvider<Request: AIRequestIdentifying, Result: Decodable & Sendable>(
        operation: AIOperation,
        result: Result.Type,
        validateResult: (@Sendable (Result) throws -> Void)? = nil,
        makeRequest: (UUID) -> Request
    ) async throws -> CyExecution<Result> {
        let fingerprintRequest = makeRequest(Self.fingerprintOperationID)
        let reservation = try await operationIDs.reserve(
            operation: operation,
            fingerprintRequest: fingerprintRequest
        )
        do {
            let execution = try await client.performWithProvider(
                operation: operation,
                request: makeRequest(reservation.operationID),
                result: result,
                validateResult: validateResult
            )
            await operationIDs.complete(reservation)
            return execution
        } catch {
            if !shouldRetainOperationID(after: error) {
                await operationIDs.complete(reservation)
            }
            throw error
        }
    }

    private func shouldRetainOperationID(after error: Error) -> Bool {
        guard let apiError = error as? AgentCyAPIError else { return false }
        switch apiError {
        case .invalidStream:
            // The server may already have completed and cached this operation.
            // Reusing the ID lets a direct hosted retry retrieve that result
            // without charging or generating twice.
            return true
        case .server(let serverError):
            return serverError.code == .conflict && serverError.retryable
        default:
            return false
        }
    }

    private func spark(from brief: CreativeBrief, postContext: String?) -> SparkWire {
        SparkWire(
            sparkId: brief.id,
            source: brief.source,
            text: SparkContextBuilder.text(for: brief, postContext: postContext),
            sourceBriefId: nil
        )
    }

    private func developmentState(from brief: CreativeBrief) -> SparkDevelopmentStateWire {
        SparkDevelopmentStateWire(
            premise: nonempty(brief.premise),
            audience: nonempty(brief.audience),
            creativeGoal: nonempty(brief.creativeGoal),
            proofOrStory: nil,
            desiredTakeaway: nonempty(brief.takeaway),
            constraints: []
        )
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
