import Foundation

struct VoiceExampleWire: Codable, Sendable {
    let exampleId: UUID
    let order: Int
    let source: VoiceExampleSource
    let text: String
    let creatorConfirmed: Bool

    init(
        exampleId: UUID,
        order: Int,
        text: String,
        source: VoiceExampleSource = .text,
        creatorConfirmed: Bool = true
    ) {
        self.exampleId = exampleId
        self.order = order
        self.source = source
        self.text = text
        self.creatorConfirmed = creatorConfirmed
    }
}

struct VoiceProfileWire: Codable, Equatable, Sendable {
    let summary: String
    let tone: [String]
    let sentenceStyle: String
    let signatureQualities: [String]
    let phrasesToUse: [String]
    let phrasesToAvoid: [String]
    let guidance: [String]
    let confidence: Double
}

struct PillarSummaryWire: Codable, Sendable {
    let pillarId: UUID
    let name: String
    let description: String?
}

struct BriefSummaryWire: Codable, Sendable {
    let briefId: UUID
    let title: String
    let premise: String
    let takeaway: String
    let status: BriefStatus
    let platforms: [CreatorPlatform]
}

struct CreatorContextWire: Codable, Sendable {
    let name: String
    let primaryGoal: String
    let selectedPlatforms: [CreatorPlatform]
    let voiceExamples: [VoiceExampleWire]
    let voiceProfile: VoiceProfileWire?
    let pillars: [PillarSummaryWire]
    let librarySummaries: [BriefSummaryWire]
}

struct SparkWire: Codable, Sendable {
    let sparkId: UUID
    let source: SparkSource
    let text: String
    let sourceBriefId: UUID?
}

enum ConversationRoleWire: String, Codable, Sendable {
    case user
    case assistant
}

struct ConversationMessageWire: Codable, Sendable {
    let messageId: UUID
    let role: ConversationRoleWire
    let content: String
}

struct SparkDevelopmentStateWire: Codable, Sendable {
    let premise: String?
    let audience: String?
    let creativeGoal: String?
    let proofOrStory: String?
    let desiredTakeaway: String?
    let constraints: [String]
}

enum AIContractVersion {
    static let schema = "1"
    static let voiceProfilePrompt = "voice-profile.v1"
    static let ideasPrompt = "ideas.v1"
    static let sparkTurnPrompt = "spark-turn.v1"
    static let composeBriefPrompt = "compose-brief.v1"
    static let reviseBriefPrompt = "revise-brief.v1"
    static let chatTurnPrompt = "chat-turn.v1"
}

enum VoiceProfileIntentWire: String, Codable, Sendable {
    case onboarding
    case teachCy
}

struct VoiceProfileRequestWire: Codable, Sendable, AIRequestIdentifying {
    let schemaVersion: String
    let promptVersion: String
    let operationId: UUID
    let appBuild: String
    let assistanceMode: AssistanceMode
    let creatorContext: CreatorContextWire
    let intent: VoiceProfileIntentWire
    let teachingInstruction: String?
}

struct VoiceProfileResultWire: Codable, Equatable, Sendable {
    let profile: VoiceProfileWire
    let assumptions: [String]
    let evidenceNotes: [String]
}

struct IdeasRequestWire: Codable, Sendable, AIRequestIdentifying {
    let schemaVersion: String
    let promptVersion: String
    let operationId: UUID
    let appBuild: String
    let assistanceMode: AssistanceMode
    let creatorContext: CreatorContextWire
    let count: Int
    let startingPoint: String?
    let constraints: [String]
}

struct IdeaDirectionWire: Codable, Sendable {
    let directionId: String
    let title: String
    let premise: String
    let opening: String
    let whyItFits: String
    let assumedTakeaway: String
    let assumptions: [String]
}

struct IdeasResultWire: Codable, Sendable {
    let ideas: [IdeaDirectionWire]
}

enum SparkDevelopmentFieldWire: String, Codable, Sendable {
    case premise
    case audience
    case creativeGoal
    case proofOrStory
    case desiredTakeaway
    case constraints
}

enum SparkRecommendedNextStepWire: String, Codable, Sendable {
    case answerQuestion
    case composeNow
    case reviewWorkingState
}

struct SparkTurnRequestWire: Codable, Sendable, AIRequestIdentifying {
    let schemaVersion: String
    let promptVersion: String
    let operationId: UUID
    let appBuild: String
    let assistanceMode: AssistanceMode
    let creatorContext: CreatorContextWire
    let spark: SparkWire
    let turnNumber: Int
    let composeNow: Bool
    let conversation: [ConversationMessageWire]
    let workingState: SparkDevelopmentStateWire
}

struct SparkTurnResultWire: Codable, Sendable {
    let assistantMessage: String
    let focusedQuestion: String?
    let recommendedNextStep: SparkRecommendedNextStepWire
    let readyToCompose: Bool
    let missingFields: [SparkDevelopmentFieldWire]
    let workingState: SparkDevelopmentStateWire
}

struct ChatTurnRequestWire: Codable, Sendable, AIRequestIdentifying {
    let schemaVersion: String
    let promptVersion: String
    let operationId: UUID
    let appBuild: String
    let assistanceMode: AssistanceMode
    let creatorContext: CreatorContextWire
    let conversation: [ConversationMessageWire]
    let relevantBriefIds: [UUID]
}

struct ChatSuggestionWire: Codable, Sendable {
    let label: String
    let prompt: String
}

enum ChatProposedActionKindWire: String, Codable, Sendable {
    case developSpark
    case reviseBrief
    case createTask
    case planWeek
}

struct ChatProposedActionWire: Codable, Sendable {
    let kind: ChatProposedActionKindWire
    let summary: String
}

struct ChatTurnResultWire: Codable, Sendable {
    let assistantMessage: String
    let suggestions: [ChatSuggestionWire]
    let proposedAction: ChatProposedActionWire?
}

struct ComposeBriefRequestWire: Codable, Sendable, AIRequestIdentifying {
    let schemaVersion: String
    let promptVersion: String
    let operationId: UUID
    let appBuild: String
    let assistanceMode: AssistanceMode
    let creatorContext: CreatorContextWire
    let briefId: UUID
    let spark: SparkWire
    let conversation: [ConversationMessageWire]
    let workingState: SparkDevelopmentStateWire
    let durationSeconds: Int
    let selectedPlatforms: [CreatorPlatform]
    let additionalDirection: String?
}

struct ScriptBeatWire: Codable, Equatable, Sendable {
    let order: Int
    let label: String
    let purpose: String
    let script: String
}

struct FilmingGuidanceWire: Codable, Equatable, Sendable {
    let setup: String
    let shots: [String]
    let bRoll: [String]
    let delivery: String
    let editing: String
    let audio: String
    let onScreenText: [String]
}

struct ProposedTaskWire: Codable, Equatable, Sendable {
    let title: String
    let kind: CreatorTaskKind
    let notes: String?
    let estimatedMinutes: Int?
    let isRecordingMilestone: Bool
    let order: Int
}

struct PlatformVariantWire: Codable, Equatable, Sendable {
    let platform: CreatorPlatform
    let caption: String?
    let title: String?
    let openingAdjustment: String?
    let ctaAdjustment: String?
    let editChanges: [String]
}

struct ReadyBriefWire: Codable, Equatable, Sendable {
    let briefId: UUID
    let title: String
    let premise: String
    let audience: String
    let creativeGoal: String
    let desiredTakeaway: String
    let durationSeconds: Int
    let spokenHook: String
    let firstFrameText: String
    let scriptBeats: [ScriptBeatWire]
    let close: String
    let ctaIntent: String
    let filmingGuidance: FilmingGuidanceWire
    let proposedTasks: [ProposedTaskWire]
    let assumptions: [String]
    let voiceConfidence: Double
    let platformVariants: [PlatformVariantWire]

    func proposal(for localBriefID: UUID) -> BriefProposal {
        let guidance = [
            filmingGuidance.setup,
            "Shots: \(filmingGuidance.shots.joined(separator: "; "))",
            "B-roll: \(filmingGuidance.bRoll.joined(separator: "; "))",
            "Delivery: \(filmingGuidance.delivery)"
        ].joined(separator: "\n")
        let edit = [
            filmingGuidance.editing,
            "Audio: \(filmingGuidance.audio)",
            "On-screen text: \(filmingGuidance.onScreenText.joined(separator: "; "))"
        ].joined(separator: "\n")
        return BriefProposal(
            briefID: localBriefID,
            draft: BriefDraft(
                title: title,
                premise: premise,
                audience: audience,
                goal: creativeGoal,
                takeaway: desiredTakeaway,
                durationSeconds: durationSeconds,
                spokenHook: spokenHook,
                firstFrameText: firstFrameText,
                scriptBeats: scriptBeats.sorted { $0.order < $1.order }.map { "\($0.label): \($0.script)" },
                close: close,
                ctaIntent: ctaIntent,
                filmingGuidance: guidance,
                editingGuidance: edit,
                assumptions: assumptions,
                voiceConfidence: voiceConfidence
            ),
            variants: platformVariants.map {
                PlatformVariantDraft(
                    platform: $0.platform,
                    caption: $0.caption ?? "",
                    openingAdjustment: $0.openingAdjustment ?? "",
                    titleOverride: $0.title ?? "",
                    cta: $0.ctaAdjustment ?? "",
                    editChanges: $0.editChanges.joined(separator: "\n")
                )
            },
            tasks: proposedTasks.sorted { $0.order < $1.order }.map {
                ProposedCreatorTask(title: $0.title, kind: $0.kind, notes: $0.notes ?? "", estimatedMinutes: $0.estimatedMinutes, isRecordingMilestone: $0.isRecordingMilestone)
            },
            canonicalBrief: self
        )
    }

    func overlaying(_ proposal: BriefProposal) -> ReadyBriefWire {
        let orderedBeats = proposal.draft.scriptBeats.enumerated().map { index, script -> ScriptBeatWire in
            if scriptBeats.indices.contains(index) {
                let existing = scriptBeats[index]
                return ScriptBeatWire(order: index, label: existing.label, purpose: existing.purpose, script: script)
            }
            return ScriptBeatWire(order: index, label: "Beat \(index + 1)", purpose: "Advance the idea", script: script)
        }
        let guidance = Self.guidance(from: proposal.draft, fallback: filmingGuidance)
        return ReadyBriefWire(
            briefId: proposal.briefID,
            title: proposal.draft.title,
            premise: proposal.draft.premise,
            audience: proposal.draft.audience,
            creativeGoal: proposal.draft.goal,
            desiredTakeaway: proposal.draft.takeaway,
            durationSeconds: proposal.draft.durationSeconds,
            spokenHook: proposal.draft.spokenHook,
            firstFrameText: proposal.draft.firstFrameText,
            scriptBeats: orderedBeats,
            close: proposal.draft.close,
            ctaIntent: proposal.draft.ctaIntent,
            filmingGuidance: guidance,
            proposedTasks: proposal.tasks.enumerated().map { index, task in
                ProposedTaskWire(
                    title: task.title,
                    kind: task.kind,
                    notes: task.notes.isEmpty ? nil : task.notes,
                    estimatedMinutes: task.estimatedMinutes,
                    isRecordingMilestone: task.isRecordingMilestone,
                    order: index
                )
            },
            assumptions: proposal.draft.assumptions,
            voiceConfidence: proposal.draft.voiceConfidence,
            platformVariants: proposal.variants.map { variant in
                PlatformVariantWire(
                    platform: variant.platform,
                    caption: variant.caption.isEmpty ? nil : variant.caption,
                    title: variant.titleOverride.isEmpty ? nil : variant.titleOverride,
                    openingAdjustment: variant.openingAdjustment.isEmpty ? nil : variant.openingAdjustment,
                    ctaAdjustment: variant.cta.isEmpty ? nil : variant.cta,
                    editChanges: variant.editChanges.split(separator: "\n").map(String.init)
                )
            }
        )
    }

    private static func guidance(from draft: BriefDraft, fallback: FilmingGuidanceWire) -> FilmingGuidanceWire {
        let filmingLines = draft.filmingGuidance.split(separator: "\n").map(String.init)
        let editingLines = draft.editingGuidance.split(separator: "\n").map(String.init)
        return FilmingGuidanceWire(
            setup: filmingLines.first ?? fallback.setup,
            shots: list(after: "Shots: ", in: filmingLines) ?? fallback.shots,
            bRoll: list(after: "B-roll: ", in: filmingLines) ?? fallback.bRoll,
            delivery: value(after: "Delivery: ", in: filmingLines) ?? fallback.delivery,
            editing: editingLines.first ?? fallback.editing,
            audio: value(after: "Audio: ", in: editingLines) ?? fallback.audio,
            onScreenText: list(after: "On-screen text: ", in: editingLines) ?? fallback.onScreenText
        )
    }

    private static func value(after prefix: String, in lines: [String]) -> String? {
        lines.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
    }

    private static func list(after prefix: String, in lines: [String]) -> [String]? {
        value(after: prefix, in: lines)?.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct ComposeBriefResultWire: Codable, Sendable {
    let brief: ReadyBriefWire
}

enum BriefRevisionFieldWire: String, CaseIterable, Codable, Identifiable, Sendable {
    case title
    case premise
    case audience
    case creativeGoal
    case desiredTakeaway
    case durationSeconds
    case spokenHook
    case firstFrameText
    case scriptBeats
    case close
    case ctaIntent
    case filmingGuidance
    case proposedTasks
    case assumptions
    case platformVariants
    case wholeBrief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creativeGoal: "Creative goal"
        case .desiredTakeaway: "Desired takeaway"
        case .durationSeconds: "Duration"
        case .spokenHook: "Spoken hook"
        case .firstFrameText: "First-frame text"
        case .scriptBeats: "Script beats"
        case .ctaIntent: "CTA intent"
        case .filmingGuidance: "Production guidance"
        case .proposedTasks: "Production tasks"
        case .platformVariants: "Platform differences"
        case .wholeBrief: "Whole brief"
        default: rawValue.capitalized
        }
    }
}

struct ReviseBriefRequestWire: Codable, Sendable, AIRequestIdentifying {
    let schemaVersion: String
    let promptVersion: String
    let operationId: UUID
    let appBuild: String
    let assistanceMode: AssistanceMode
    let creatorContext: CreatorContextWire
    let brief: ReadyBriefWire
    let revisionNumber: Int
    let scope: BriefRevisionFieldWire
    let instruction: String
}

struct ReviseBriefResultWire: Codable, Equatable, Sendable {
    let brief: ReadyBriefWire
    let changedFields: [BriefRevisionFieldWire]
    let explanation: String
}

actor RemoteCreativeGateway {
    private let client: AgentCyAPIClient

    init(client: AgentCyAPIClient = AgentCyAPIClient()) {
        self.client = client
    }

    func compose(_ request: ComposeBriefRequestWire, onPhase: (@Sendable (AIProgressPhase) async -> Void)? = nil) async throws -> BriefProposal {
        let result = try await client.perform(operation: .composeBrief, request: request, result: ComposeBriefResultWire.self, onPhase: onPhase)
        return result.brief.proposal(for: request.briefId)
    }
}
