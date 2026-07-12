import Foundation

enum AssistanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case drive
    case collaborate
    case lead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: "I lead"
        case .collaborate: "Work together"
        case .lead: "Cy leads"
        }
    }

    var detail: String {
        switch self {
        case .drive: "Cy waits until you ask."
        case .collaborate: "Cy asks and suggests as you go."
        case .lead: "Cy guides you through the shortest path."
        }
    }
}

enum SparkSource: String, CaseIterable, Codable, Sendable {
    case text
    case voiceTranscript
    case cyDirection
    case repurposedBrief
}

enum VoiceExampleSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case text
    case publicPostText
    case screenshotText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Pasted or dictated"
        case .publicPostText: "Instagram post"
        case .screenshotText: "Screenshot text"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .publicPostText: "link"
        case .screenshotText: "text.viewfinder"
        }
    }
}

struct VoiceExampleDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var text: String
    var source: VoiceExampleSource
    var sourceURLString: String

    init(
        id: UUID = UUID(),
        text: String = "",
        source: VoiceExampleSource = .text,
        sourceURLString: String = ""
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.sourceURLString = sourceURLString
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isUsableEvidence: Bool { !trimmedText.isEmpty }

    var hasLocalReference: Bool {
        InstagramPostReference.canonicalURL(from: sourceURLString) != nil
    }
}

enum InstagramPostReference {
    static func canonicalURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["instagram.com", "www.instagram.com", "m.instagram.com"].contains(host) else {
            return nil
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2,
              ["p", "reel", "tv"].contains(pathParts[0].lowercased()),
              !pathParts[1].isEmpty else {
            return nil
        }

        components.scheme = "https"
        components.host = "www.instagram.com"
        components.path = "/\(pathParts[0].lowercased())/\(pathParts[1])/"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

enum CreatorPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case instagramReels
    case tiktok
    case youtubeShorts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagramReels: "Instagram Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "YouTube Shorts"
        }
    }

    var shortTitle: String {
        switch self {
        case .instagramReels: "Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "Shorts"
        }
    }

    var symbol: String {
        switch self {
        case .instagramReels: "camera.aperture"
        case .tiktok: "music.note"
        case .youtubeShorts: "play.rectangle.fill"
        }
    }
}

enum BriefStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case spark
    case developing
    case ready
    case scheduled
    case posted
    case archived

    var id: String { rawValue }
    var title: String {
        switch self {
        case .spark: "Idea"
        case .developing: "Draft"
        case .ready: "Ready"
        case .scheduled: "Planned"
        case .posted: "Posted"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .spark: "sparkles"
        case .developing: "bubble.left.and.text.bubble.right"
        case .ready: "checkmark.seal"
        case .scheduled: "calendar"
        case .posted: "paperplane.fill"
        case .archived: "archivebox"
        }
    }
}

enum PlatformOutputStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case ready
    case scheduled
    case posted
}

enum CreatorTaskKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case planning
    case scripting
    case filming
    case editing
    case publishing
    case creatorBusiness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creatorBusiness: "Creator business"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .planning: "lightbulb"
        case .scripting: "text.page"
        case .filming: "video"
        case .editing: "slider.horizontal.3"
        case .publishing: "paperplane"
        case .creatorBusiness: "briefcase"
        }
    }
}

enum SubscriptionAccess: String, CaseIterable, Codable, Sendable {
    case freeJourney
    case trial
    case paid
    case comped
    case expired

    var canCreate: Bool { self != .expired }
    var canUseCy: Bool { self != .expired }
    var canEditExisting: Bool { true }
}

enum ConversationRole: String, Codable, Sendable {
    case creator
    case cy
}

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case agenda
    case tasks
    case pillars
    case library

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .today: "house.fill"
        case .agenda: "calendar"
        case .tasks: "checkmark.circle"
        case .pillars: "square.grid.2x2"
        case .library: "books.vertical"
        }
    }
}

enum ReplanChoice: String, CaseIterable, Identifiable, Sendable {
    case move
    case simplify
    case pause
    case archive

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct BriefLifecycleEntry: Identifiable, Equatable, Sendable {
    let status: BriefStatus
    let date: Date

    var id: String { "\(date.timeIntervalSince1970)|\(status.rawValue)" }
}

struct IdeaDirection: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let premise: String
    let opening: String
    let assumption: String

    init(id: UUID = UUID(), title: String, premise: String, opening: String, assumption: String) {
        self.id = id
        self.title = title
        self.premise = premise
        self.opening = opening
        self.assumption = assumption
    }
}

struct BriefDraft: Codable, Equatable, Sendable {
    var title: String
    var premise: String
    var audience: String
    var goal: String
    var takeaway: String
    var durationSeconds: Int
    var spokenHook: String
    var firstFrameText: String
    var scriptBeats: [String]
    var close: String
    var ctaIntent: String
    var filmingGuidance: String
    var editingGuidance: String
    var assumptions: [String]
    var voiceConfidence: Double
}

struct PlatformVariantDraft: Codable, Equatable, Sendable {
    var platform: CreatorPlatform
    var caption: String
    var openingAdjustment: String
    var titleOverride: String
    var cta: String
    var editChanges: String
}

struct ProposedCreatorTask: Codable, Equatable, Sendable {
    var title: String
    var kind: CreatorTaskKind
    var notes: String = ""
    var estimatedMinutes: Int?
    var isRecordingMilestone = false
}

struct BriefProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let briefID: UUID
    var draft: BriefDraft
    var variants: [PlatformVariantDraft]
    var tasks: [ProposedCreatorTask]
    var canonicalBrief: ReadyBriefWire?

    init(id: UUID = UUID(), briefID: UUID, draft: BriefDraft, variants: [PlatformVariantDraft], tasks: [ProposedCreatorTask], canonicalBrief: ReadyBriefWire? = nil) {
        self.id = id
        self.briefID = briefID
        self.draft = draft
        self.variants = variants
        self.tasks = tasks
        self.canonicalBrief = canonicalBrief
    }
}

struct BriefRevisionProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let briefID: UUID
    let sourceUpdatedAt: Date
    let requestedScope: BriefRevisionFieldWire
    let instruction: String
    let changedFields: [BriefRevisionFieldWire]
    let explanation: String
    let baseline: BriefProposal
    var edited: BriefProposal
    let sourceTaskIDs: [UUID]
    let canonicalBrief: ReadyBriefWire

    init(
        id: UUID = UUID(),
        briefID: UUID,
        sourceUpdatedAt: Date,
        requestedScope: BriefRevisionFieldWire,
        instruction: String,
        changedFields: [BriefRevisionFieldWire],
        explanation: String,
        baseline: BriefProposal,
        edited: BriefProposal,
        sourceTaskIDs: [UUID],
        canonicalBrief: ReadyBriefWire
    ) {
        self.id = id
        self.briefID = briefID
        self.sourceUpdatedAt = sourceUpdatedAt
        self.requestedScope = requestedScope
        self.instruction = instruction
        self.changedFields = changedFields
        self.explanation = explanation
        self.baseline = baseline
        self.edited = edited
        self.sourceTaskIDs = sourceTaskIDs
        self.canonicalBrief = canonicalBrief
    }
}

struct VoiceProfileDraft: Codable, Equatable, Sendable {
    var summary: String
    var tone: [String]
    var sentenceStyle: String
    var signatureQualities: [String]
    var phrasesToUse: [String]
    var phrasesToAvoid: [String]
    var guidance: [String]
    var confidence: Double

    init(_ profile: VoiceProfileWire) {
        summary = profile.summary
        tone = profile.tone
        sentenceStyle = profile.sentenceStyle
        signatureQualities = profile.signatureQualities
        phrasesToUse = profile.phrasesToUse
        phrasesToAvoid = profile.phrasesToAvoid
        guidance = profile.guidance
        confidence = profile.confidence
    }

    var wire: VoiceProfileWire {
        VoiceProfileWire(
            summary: summary,
            tone: tone,
            sentenceStyle: sentenceStyle,
            signatureQualities: signatureQualities,
            phrasesToUse: phrasesToUse,
            phrasesToAvoid: phrasesToAvoid,
            guidance: guidance,
            confidence: confidence
        )
    }
}

struct VoiceProfileChangeProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    let sourceVersion: Int
    let sourceUpdatedAt: Date
    let instruction: String
    let baseline: VoiceProfileDraft
    var edited: VoiceProfileDraft
    let assumptions: [String]
    let evidenceNotes: [String]

    init(
        id: UUID = UUID(),
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        instruction: String,
        baseline: VoiceProfileDraft,
        edited: VoiceProfileDraft,
        assumptions: [String],
        evidenceNotes: [String]
    ) {
        self.id = id
        self.profileID = profileID
        self.sourceVersion = sourceVersion
        self.sourceUpdatedAt = sourceUpdatedAt
        self.instruction = instruction
        self.baseline = baseline
        self.edited = edited
        self.assumptions = assumptions
        self.evidenceNotes = evidenceNotes
    }
}

struct VoiceProfileExtraction: Equatable, Sendable {
    let summary: String
    let traits: String
    let avoid: String
    let canonical: VoiceProfileWire
}

enum AssistanceInitiative: Sendable {
    case quiet
    case contextual
    case proactive
}

struct AssistancePolicy: Sendable {
    let mode: AssistanceMode

    var initiative: AssistanceInitiative {
        switch mode {
        case .drive: .quiet
        case .collaborate: .contextual
        case .lead: .proactive
        }
    }

    func pillarProposalLimit(explicitlyRequested: Bool) -> Int {
        switch mode {
        case .drive: explicitlyRequested ? 3 : 0
        case .collaborate: 1
        case .lead: 3
        }
    }
}

struct OnboardingDraft: Equatable, Sendable {
    var adultConfirmed = false
    var telemetryConsent = false
    var name = ""
    var goal = ""
    var platforms: Set<CreatorPlatform> = [.instagramReels]
    var assistanceMode: AssistanceMode = .collaborate
    var voiceExamples = [VoiceExampleDraft(), VoiceExampleDraft(), VoiceExampleDraft()]
    var voiceSummary = ""
    var voiceTraits = ""
    var voiceAvoid = ""
    var voiceProfilePayloadJSON = ""
    var dailyReminderEnabled = false
    var dailyReminderHour = 9
    var weeklyReminderEnabled = false
    var weeklyReminderWeekday = 2
    var weeklyReminderHour = 9
}
