import Foundation

enum CreatorWorkspacePreferences {
    static let activeWorkspaceKey = "agentcy.creator.activeWorkspaceID"

    static var activeWorkspaceID: UUID? {
        get {
            UserDefaults.standard.string(forKey: activeWorkspaceKey).flatMap(UUID.init(uuidString:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: activeWorkspaceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeWorkspaceKey)
            }
        }
    }
}

enum WorkspaceScope {
    static func defaultWorkspace(in workspaces: [CreatorWorkspace]) -> CreatorWorkspace? {
        workspaces
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    static func activeWorkspaceID(
        preferredID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> UUID? {
        if let preferredID,
           workspaces.contains(where: { $0.id == preferredID && !$0.isArchived }) {
            return preferredID
        }
        return defaultWorkspace(in: workspaces)?.id
    }

    static func includes(
        _ recordWorkspaceID: UUID?,
        activeWorkspaceID preferredID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> Bool {
        guard let activeID = activeWorkspaceID(preferredID: preferredID, workspaces: workspaces) else {
            return recordWorkspaceID == nil
        }
        if let recordWorkspaceID { return recordWorkspaceID == activeID }
        return defaultWorkspace(in: workspaces)?.id == activeID
    }
}

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

enum VoiceSourceRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case ownVoice
    case inspiration

    var id: String { rawValue }
    var title: String { self == .ownVoice ? "Your voice" : "Inspiration" }
    var detail: String {
        self == .ownVoice
            ? "Counts toward the three examples Cy needs to learn your voice."
            : "Guides high-level traits only. Cy will not copy wording."
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

enum ContentFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case shortForm
    case longForm

    var id: String { rawValue }
    var title: String { self == .shortForm ? "Short-form" : "Long-form" }
    var durationOptions: [Int] {
        switch self {
        case .shortForm: [15, 30, 45, 60, 90]
        case .longForm: [180, 300, 480, 600, 900]
        }
    }
    var defaultDuration: Int { self == .shortForm ? 45 : 480 }
}

enum PublishingFormatKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case shortVideo
    case longVideo
    case nonVideo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shortVideo: "Short video"
        case .longVideo: "Long video"
        case .nonVideo: "Non-video"
        }
    }
    var contentFormat: ContentFormat? {
        switch self {
        case .shortVideo: .shortForm
        case .longVideo: .longForm
        case .nonVideo: nil
        }
    }
    var defaultDurationSeconds: Int? {
        switch self {
        case .shortVideo: 45
        case .longVideo: 480
        case .nonVideo: nil
        }
    }
}

enum BuiltInDestinationKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case instagram
    case tiktok
    case youtube

    var id: String { rawValue }
    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        }
    }
}

enum CreatorPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case instagramReels
    case tiktok
    case youtubeShorts
    case youtubeVideo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagramReels: "Instagram Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "YouTube Shorts"
        case .youtubeVideo: "YouTube"
        }
    }

    var shortTitle: String {
        switch self {
        case .instagramReels: "Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "Shorts"
        case .youtubeVideo: "YouTube"
        }
    }

    var symbol: String {
        switch self {
        case .instagramReels: "camera.aperture"
        case .tiktok: "music.note"
        case .youtubeShorts, .youtubeVideo: "play.rectangle.fill"
        }
    }

    var format: ContentFormat {
        self == .youtubeVideo ? .longForm : .shortForm
    }

    static func choices(for format: ContentFormat) -> [CreatorPlatform] {
        allCases.filter { $0.format == format }
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

enum PostRecurrenceFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Does not repeat"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

enum TaskRecurrenceFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "One time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
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

enum TaskLane: String, CaseIterable, Codable, Identifiable, Sendable {
    case pillar
    case production

    var id: String { rawValue }
    var title: String { self == .pillar ? "Pillar" : "Focus" }
    var shortTitle: String { self == .pillar ? "Pillar" : "Focus" }
}

enum TaskCollection: String, CaseIterable, Identifiable, Sendable {
    case postTasks
    case myTasks

    var id: String { rawValue }
    var title: String { self == .postTasks ? "Post tasks" : "My tasks" }
}

enum TaskCollectionPolicy {
    static func collection(briefID: UUID?, platformOutputID: UUID?) -> TaskCollection {
        briefID != nil || platformOutputID != nil ? .postTasks : .myTasks
    }
}

enum TaskListVisibilityPolicy {
    /// Post Tasks are scoped to the calendar week shown by the Tasks page.
    /// Recurring My Tasks keep the existing short rolling horizon so their
    /// materialized future occurrences do not flood the list.
    static func includes(
        collection: TaskCollection,
        focusTaskTemplateID: UUID?,
        recurrence: TaskRecurrenceFrequency,
        recurrenceRootTaskID: UUID?,
        targetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if collection == .postTasks || focusTaskTemplateID != nil {
            guard let targetDate else { return true }
            let targetDay = calendar.startOfDay(for: targetDate)
            let today = calendar.startOfDay(for: now)
            let weekday = calendar.component(.weekday, from: today)
            let daysSinceMonday = (weekday + 5) % 7
            guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today),
                  let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)
            else { return true }
            return targetDay >= monday && targetDay < nextMonday
        }

        let isRecurring = focusTaskTemplateID != nil ||
            recurrence != .none ||
            recurrenceRootTaskID != nil
        guard isRecurring, let targetDate else { return true }

        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 7, to: today) else {
            return true
        }
        return calendar.startOfDay(for: targetDate) <= horizon
    }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case high
    case urgent
    // Retained only so populated stores decode before the idempotent backfill.
    case low
    case medium

    var id: String { rawValue }
    static var selectableCases: [TaskPriority] { [.none, .high, .urgent] }
    var title: String {
        switch self {
        case .none, .low, .medium: "None"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }
    var normalized: TaskPriority {
        switch self {
        case .low, .medium: .none
        default: self
        }
    }
}

enum DailyFocusKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case planning
    case scripting
    case filming
    case editing
    case publishing
    case community
    case businessAdmin

    // Kept so existing stores migrate without losing earlier focus choices.
    case posting
    case admin
    case custom

    var id: String { rawValue }

    static let selectableCases: [DailyFocusKind] = [
        .planning,
        .scripting,
        .filming,
        .editing,
        .publishing,
        .community,
        .businessAdmin,
    ]

    var title: String {
        switch self {
        case .planning: "Planning"
        case .scripting: "Scripting"
        case .filming: "Filming"
        case .editing: "Editing"
        case .publishing, .posting: "Publishing"
        case .community: "Community"
        case .businessAdmin, .admin: "Business & admin"
        case .custom: "Custom"
        }
    }

    var taskKind: CreatorTaskKind? {
        switch self {
        case .planning: .planning
        case .scripting: .scripting
        case .filming: .filming
        case .editing: .editing
        case .publishing, .posting: .publishing
        case .community, .businessAdmin, .admin: .creatorBusiness
        case .custom: nil
        }
    }

    var directive: String {
        switch self {
        case .planning:
            "Choose what to make and map the next steps."
        case .scripting:
            "Write hooks, beats, and calls to action."
        case .filming:
            "Batch record while your setup is ready."
        case .editing:
            "Shape footage into clean, finished cuts."
        case .publishing, .posting:
            "Finish captions, covers, and posting details."
        case .community:
            "Reply, engage, and connect with your audience."
        case .businessAdmin, .admin:
            "Handle the work that keeps your creator business moving."
        case .custom:
            "Use this day for the work that matters most."
        }
    }

    static func combinedTitle(_ kinds: [DailyFocusKind]) -> String {
        let unique = kinds.reduce(into: [DailyFocusKind]()) { values, kind in
            if !values.contains(kind) { values.append(kind) }
        }
        guard let first = unique.first else { return "Rest" }
        guard unique.count > 1 else { return first.title }
        return "\(first.title) & \(unique[1].title.lowercased())"
    }

    static func combinedDirective(_ kinds: [DailyFocusKind]) -> String {
        let unique = kinds.reduce(into: [DailyFocusKind]()) { values, kind in
            if !values.contains(kind) { values.append(kind) }
        }
        guard !unique.isEmpty else { return "Recover, reset, or leave the day open." }
        return unique.prefix(2).map(\.directive).joined(separator: " ")
    }
}

enum PillarRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case anchor
    case supporting

    var id: String { rawValue }
    var title: String { self == .anchor ? "Anchor pillar" : "Supporting pillar" }
}

enum CompensationType: String, CaseIterable, Codable, Identifiable, Sendable {
    case paid
    case gifted
    case both

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AttachmentOwnerKind: String, Codable, Sendable {
    case referenceFile
    case postMedia
    case collaborationFile
    case moodBoardMedia
}

enum AttachmentKind: String, Codable, Sendable {
    case photo
    case video
    case document
    case other
}

enum AttachmentSyncState: String, Codable, Sendable {
    case localOnly
    case eligible
    case synced
    case failed
}

enum AppearancePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CreatorVibePalette: String, CaseIterable, Codable, Identifiable, Sendable {
    case grayscale
    case pastel
    case neutral
    case colorful
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static let fallbackPillarColorHexes = ["9B3A2E", "B47724", "55705B", "416B85", "76506F"]

    var detail: String {
        switch self {
        case .grayscale: "Quiet and minimal"
        case .pastel: "Soft and airy"
        case .neutral: "Grounded and warm"
        case .colorful: "Bright and expressive"
        case .dark: "Deep and moody"
        }
    }

    var pillarColorHexes: [String] {
        switch self {
        case .grayscale: ["343434", "5A5A5A", "7C7C7C", "9E9E9E", "C2C2C2"]
        case .pastel: ["D9A5A5", "F2D18A", "A7CBB0", "A9C8E8", "C5B1DD"]
        case .neutral: ["443A35", "252525", "E4DDCC", "F8F4EE", "C5B49D"]
        case .colorful: ["E45545", "F0A202", "2E8B57", "3973C6", "8D4BC7"]
        case .dark: ["6C3547", "755321", "31594A", "2E4A66", "4F3D66"]
        }
    }
}

enum ConversationContextKind: String, Codable, Sendable {
    case none
    case brief
    case task
    case pillar
    case day
}

enum PillarWeekday: Int, CaseIterable, Codable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var title: String {
        Calendar.current.weekdaySymbols[rawValue - 1]
    }

    var shortTitle: String {
        Calendar.current.shortWeekdaySymbols[rawValue - 1]
    }

    var letter: String {
        String(title.prefix(1)).uppercased()
    }

    static var mondayFirst: [PillarWeekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
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
    case claude
}

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case tasks
    case pillars
    case ideaBank
    case cy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Plan"
        case .ideaBank: "Idea Bank"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .tasks: "checkmark"
        case .pillars: "rectangle.3.group"
        case .ideaBank: "tray"
        case .cy: "sparkles"
        }
    }
}

enum WeeklyPlanningCue {
    static let lastOpenedStorageKey = "agentcy.cy.weekly-planning.last-opened-week"

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
    }

    static func shouldPulse(
        on date: Date,
        lastOpenedWeekKey: String,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.component(.weekday, from: date) == 2 &&
            lastOpenedWeekKey != weekKey(for: date, calendar: calendar)
    }
}

enum ReplanChoice: String, CaseIterable, Identifiable, Sendable {
    case move
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
    let suggestedPillarID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        premise: String,
        opening: String,
        assumption: String,
        suggestedPillarID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.premise = premise
        self.opening = opening
        self.assumption = assumption
        self.suggestedPillarID = suggestedPillarID
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

struct OnboardingPillarDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var colorHex = "55705B"
    var assignedWeekdays: Set<PillarWeekday> = []
}

struct OnboardingDraft: Equatable, Sendable {
    var adultConfirmed = false
    var telemetryConsent = false
    var name = ""
    var goal = ""
    var vibePalette: CreatorVibePalette?
    var appearance: AppearancePreference? = .system
    var platforms: Set<CreatorPlatform> = []
    // Retained while the Paper-led onboarding flow is migrated so existing
    // onboarding services and saved drafts continue to compile and decode.
    var assistanceMode: AssistanceMode = .collaborate
    var pillars: [OnboardingPillarDraft] = []
    var voiceExamples: [VoiceExampleDraft] = []
    var voiceSummary = ""
    var voiceTraits = ""
    var voiceAvoid = ""
    var voiceProfilePayloadJSON = ""
    var accountHandles: [BuiltInDestinationKind: String] = [:]
    var dailyReminderEnabled = true
    var dailyReminderHour = 9
    var dailyReminderMinute = 0
    var weeklyReminderEnabled = true
    var weeklyReminderWeekday = 2
    var weeklyReminderHour = 9
    var weeklyReminderMinute = 0
}

/// Adopted by creator-owned records that belong to one account workspace.
/// A nil value is intentionally retained for CloudKit migration compatibility
/// and is treated as belonging to the default workspace.
protocol WorkspaceScopedRecord {
    var workspaceID: UUID? { get }
}
