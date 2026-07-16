import Foundation
import SwiftData

@Model
final class CreatorWorkspace {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var name: String = ""
    var primarySocialAccountID: UUID?
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        name: String,
        primarySocialAccountID: UUID? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.primarySocialAccountID = primarySocialAccountID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class CreatorProfile {
    var id: UUID = UUID()
    var name: String = ""
    var goal: String = ""
    var selectedPlatformsRaw: String = CreatorPlatform.instagramReels.rawValue
    var selectedDestinationIDsRaw: String = ""
    var assistanceModeRaw: String = AssistanceMode.collaborate.rawValue
    var appearanceRaw: String = AppearancePreference.system.rawValue
    var vibePaletteRaw: String = ""
    var avatarImageData: Data?
    var adultConfirmed: Bool = false
    var telemetryConsent: Bool = false
    var onboardingCompleted: Bool = false
    var showsHookInPostEditor: Bool = true
    var showsBrandDealsInPostEditor: Bool = true
    var showsMoodBoardsInPostEditor: Bool = true
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        goal: String = "",
        selectedPlatforms: [CreatorPlatform] = [.instagramReels],
        assistanceMode: AssistanceMode = .collaborate,
        avatarImageData: Data? = nil,
        adultConfirmed: Bool = false,
        telemetryConsent: Bool = false,
        onboardingCompleted: Bool = false,
        showsHookInPostEditor: Bool = true,
        showsBrandDealsInPostEditor: Bool = true,
        showsMoodBoardsInPostEditor: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.selectedPlatformsRaw = selectedPlatforms.map(\.rawValue).joined(separator: ",")
        self.assistanceModeRaw = assistanceMode.rawValue
        self.avatarImageData = avatarImageData
        self.adultConfirmed = adultConfirmed
        self.telemetryConsent = telemetryConsent
        self.onboardingCompleted = onboardingCompleted
        self.showsHookInPostEditor = showsHookInPostEditor
        self.showsBrandDealsInPostEditor = showsBrandDealsInPostEditor
        self.showsMoodBoardsInPostEditor = showsMoodBoardsInPostEditor
        self.createdAt = createdAt
    }

    var selectedPlatforms: [CreatorPlatform] {
        get { selectedPlatformsRaw.split(separator: ",").compactMap { CreatorPlatform(rawValue: String($0)) } }
        set { selectedPlatformsRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    var assistanceMode: AssistanceMode {
        get { AssistanceMode(rawValue: assistanceModeRaw) ?? .collaborate }
        set { assistanceModeRaw = newValue.rawValue }
    }

    var selectedDestinationIDs: [UUID] {
        get { selectedDestinationIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { selectedDestinationIDsRaw = newValue.map(\.uuidString).joined(separator: ",") }
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var vibePalette: CreatorVibePalette? {
        get { CreatorVibePalette(rawValue: vibePaletteRaw) }
        set { vibePaletteRaw = newValue?.rawValue ?? "" }
    }
}

@Model
final class VoiceExample {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var text: String = ""
    var sortOrder: Int = 0
    var sourceRaw: String = VoiceExampleSource.text.rawValue
    var roleRaw: String = VoiceSourceRole.ownVoice.rawValue
    var sourceURLString: String = ""
    var creatorConfirmed: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID = UUID(),
        text: String = "",
        sortOrder: Int = 0,
        source: VoiceExampleSource = .text,
        role: VoiceSourceRole = .ownVoice,
        sourceURLString: String = "",
        creatorConfirmed: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.text = text
        self.sortOrder = sortOrder
        self.sourceRaw = source.rawValue
        self.roleRaw = role.rawValue
        self.sourceURLString = sourceURLString
        self.creatorConfirmed = creatorConfirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var source: VoiceExampleSource {
        get { VoiceExampleSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
    }

    var role: VoiceSourceRole {
        get { VoiceSourceRole(rawValue: roleRaw) ?? .ownVoice }
        set { roleRaw = newValue.rawValue }
    }

    var sourceURL: URL? {
        InstagramPostReference.canonicalURL(from: sourceURLString)
    }
}

@Model
final class VoiceProfile {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var summary: String = ""
    var traitsText: String = ""
    var avoidText: String = ""
    var isApproved: Bool = false
    var version: Int = 1
    var canonicalPayloadJSON: String = ""
    var evidenceFingerprint: String = ""
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), profileID: UUID = UUID(), summary: String = "", traitsText: String = "", avoidText: String = "", isApproved: Bool = false, version: Int = 1, canonicalPayloadJSON: String = "", evidenceFingerprint: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.profileID = profileID
        self.summary = summary
        self.traitsText = traitsText
        self.avoidText = avoidText
        self.isApproved = isApproved
        self.version = version
        self.canonicalPayloadJSON = canonicalPayloadJSON
        self.evidenceFingerprint = evidenceFingerprint
        self.updatedAt = updatedAt
    }
}

@Model
final class CreativeBrief {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var title: String = "Untitled spark"
    var premise: String = ""
    var notes: String = ""
    var scriptEnabled: Bool = true
    var audience: String = ""
    var creativeGoal: String = ""
    var takeaway: String = ""
    var durationSeconds: Int = 45
    var spokenHook: String = ""
    var firstFrameText: String = ""
    var scriptBeatsText: String = ""
    var close: String = ""
    var ctaIntent: String = ""
    var filmingGuidance: String = ""
    var editingGuidance: String = ""
    var assumptionsText: String = ""
    var voiceConfidence: Double = 0
    var readyBriefPayloadJSON: String = ""
    var lifecycleHistoryText: String = ""
    var sourceRaw: String = SparkSource.text.rawValue
    var statusRaw: String = BriefStatus.spark.rawValue
    var pillarID: UUID?
    var isBrandCollaboration: Bool = false
    var brandName: String = ""
    var compensationTypeRaw: String = CompensationType.paid.rawValue
    var compensationAmount: Double?
    var compensationCurrencyCode: String = ""
    var brandHasNetTerms: Bool = false
    var brandNetTermsDays: Int = 30
    var giftedProductDescription: String = ""
    var giftedEstimatedValue: Double?
    var promoCode: String = ""
    var promoLinkString: String = ""
    var moodBoardEnabled: Bool = false
    var moodBoardURLString: String = ""
    var agendaDate: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        title: String = "Untitled spark",
        premise: String = "",
        source: SparkSource = .text,
        status: BriefStatus = .spark,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.premise = premise
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lifecycleHistoryText = Self.lifecycleLine(status: status, date: createdAt)
    }

    var source: SparkSource {
        get { SparkSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
    }

    var status: BriefStatus {
        get { BriefStatus(rawValue: statusRaw) ?? .spark }
        set { statusRaw = newValue.rawValue }
    }

    var compensationType: CompensationType {
        get { CompensationType(rawValue: compensationTypeRaw) ?? .paid }
        set { compensationTypeRaw = newValue.rawValue }
    }

    var scriptBeats: [String] {
        get { scriptBeatsText.split(separator: "\n").map(String.init) }
        set { scriptBeatsText = newValue.joined(separator: "\n") }
    }

    var assumptions: [String] {
        get { assumptionsText.split(separator: "\n").map(String.init) }
        set { assumptionsText = newValue.joined(separator: "\n") }
    }

    var lifecycleHistory: [BriefLifecycleEntry] {
        lifecycleHistoryText
            .split(separator: "\n")
            .compactMap { line in
                let pieces = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard pieces.count == 2,
                      let date = ISO8601DateFormatter().date(from: pieces[0]),
                      let status = BriefStatus(rawValue: pieces[1]) else { return nil }
                return BriefLifecycleEntry(status: status, date: date)
            }
    }

    func appendLifecycleStatus(_ status: BriefStatus, at date: Date) {
        if lifecycleHistory.last?.status == status { return }
        let line = Self.lifecycleLine(status: status, date: date)
        lifecycleHistoryText = lifecycleHistoryText.isEmpty ? line : "\(lifecycleHistoryText)\n\(line)"
    }

    private static func lifecycleLine(status: BriefStatus, date: Date) -> String {
        "\(ISO8601DateFormatter().string(from: date))|\(status.rawValue)"
    }
}

@Model
final class PendingBriefProposal {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var briefID: UUID = UUID()
    var payloadJSON: String = ""
    var proposalKindRaw: String = "composition"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        briefID: UUID,
        payloadJSON: String,
        proposalKindRaw: String = "composition",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.briefID = briefID
        self.payloadJSON = payloadJSON
        self.proposalKindRaw = proposalKindRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PendingVoiceProfileProposal {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var sourceVersion: Int = 1
    var proposalKindRaw: String = "teach"
    var payloadJSON: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        sourceVersion: Int,
        payloadJSON: String,
        proposalKindRaw: String = "teach",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.sourceVersion = sourceVersion
        self.payloadJSON = payloadJSON
        self.proposalKindRaw = proposalKindRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PlatformOutput {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var briefID: UUID = UUID()
    var platformRaw: String = CreatorPlatform.instagramReels.rawValue
    var destinationID: UUID?
    var formatID: UUID?
    var socialAccountID: UUID?
    var durationSeconds: Int = 45
    var caption: String = ""
    var openingAdjustment: String = ""
    var titleOverride: String = ""
    var cta: String = ""
    var editChanges: String = ""
    var statusRaw: String = PlatformOutputStatus.draft.rawValue
    var targetDate: Date?
    var postedAt: Date?
    var seriesName: String = ""
    var recurrenceRaw: String = PostRecurrenceFrequency.none.rawValue
    var recurrenceWeekdaysRaw: String = ""
    var recurrenceMonthDay: Int?
    var recurrenceEndDate: Date?
    var includesTargetTime: Bool = true
    var seriesRootOutputID: UUID?
    var publishedURLString: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), briefID: UUID = UUID(), platform: CreatorPlatform = .instagramReels, destinationID: UUID? = nil, formatID: UUID? = nil, socialAccountID: UUID? = nil, durationSeconds: Int = 45, status: PlatformOutputStatus = .draft, createdAt: Date = Date()) {
        self.id = id
        self.briefID = briefID
        self.platformRaw = platform.rawValue
        self.destinationID = destinationID
        self.formatID = formatID
        self.socialAccountID = socialAccountID
        self.durationSeconds = durationSeconds
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
    }

    var platform: CreatorPlatform {
        get { CreatorPlatform(rawValue: platformRaw) ?? .instagramReels }
        set { platformRaw = newValue.rawValue }
    }

    var status: PlatformOutputStatus {
        get { PlatformOutputStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var recurrence: PostRecurrenceFrequency {
        get { PostRecurrenceFrequency(rawValue: recurrenceRaw) ?? .none }
        set {
            recurrenceRaw = newValue.rawValue
            if newValue != .weekly { recurrenceWeekdaysRaw = "" }
            if newValue != .monthly { recurrenceMonthDay = nil }
        }
    }

    var recurrenceWeekdays: Set<PillarWeekday> {
        get {
            Set(recurrenceWeekdaysRaw.split(separator: ",").compactMap { value in
                Int(value).flatMap(PillarWeekday.init(rawValue:))
            })
        }
        set {
            recurrenceWeekdaysRaw = newValue.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        }
    }
}

@Model
final class CreatorSocialAccount {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var profileID: UUID = UUID()
    var destinationID: UUID = UUID()
    var label: String = ""
    var profileURLString: String = ""
    var isPrimary: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        profileID: UUID,
        destinationID: UUID,
        label: String,
        profileURLString: String,
        isPrimary: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.destinationID = destinationID
        self.label = label
        self.profileURLString = Self.normalizedURLString(profileURLString) ?? ""
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var profileURL: URL? {
        guard let normalized = Self.normalizedURLString(profileURLString) else { return nil }
        return URL(string: normalized)
    }

    static func normalizedURLString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url.absoluteString
    }

    static func profileURLString(
        forHandle rawHandle: String,
        destination: BuiltInDestinationKind
    ) -> String? {
        var handle = rawHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        while handle.hasPrefix("@") { handle.removeFirst() }
        guard !handle.isEmpty,
              handle.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        switch destination {
        case .instagram:
            return "https://www.instagram.com/\(handle)/"
        case .tiktok:
            return "https://www.tiktok.com/@\(handle)"
        case .youtube:
            return "https://www.youtube.com/@\(handle)"
        }
    }
}

@Model
final class CreatorTask {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var briefID: UUID?
    var pillarID: UUID?
    var platformOutputID: UUID?
    var parentTaskID: UUID?
    var title: String = ""
    var notes: String = ""
    var estimatedMinutes: Int?
    var kindRaw: String = CreatorTaskKind.planning.rawValue
    var laneRaw: String = TaskLane.production.rawValue
    var priorityRaw: String = TaskPriority.medium.rawValue
    var isCompleted: Bool = false
    var targetDate: Date?
    /// Existing records default to timed so an additive migration preserves their meaning.
    /// New tasks default to date-only through the initializer below.
    var includesTargetTime: Bool = true
    var dailyFocusDate: Date?
    var dailyFocusTitle: String?
    var dailyFocusTemplateEntryID: UUID?
    /// Links a materialized weekly focus task back to its editable template.
    var focusTaskTemplateID: UUID?
    /// Once a creator edits one occurrence, recurring template reconciliation leaves it alone.
    var isFocusTemplateCustomized: Bool = false
    var recurrenceRaw: String = TaskRecurrenceFrequency.none.rawValue
    var recurrenceRootTaskID: UUID?
    var sortOrder: Int = 0
    var completedAt: Date?
    var recordingMilestoneEmitted: Bool = false
    var isRecordingMilestoneDesignated: Bool = false
    var createdAt: Date = Date()
    /// Zero identifies a record created before task-lane backfilling became one-shot.
    /// New records start at the current version so launch preparation never rewrites
    /// a creator's explicit lane choice.
    var bootstrapVersion: Int = 0

    init(id: UUID = UUID(), briefID: UUID? = nil, pillarID: UUID? = nil, platformOutputID: UUID? = nil, parentTaskID: UUID? = nil, title: String = "", kind: CreatorTaskKind = .planning, lane: TaskLane = .production, priority: TaskPriority = .none, notes: String = "", estimatedMinutes: Int? = nil, targetDate: Date? = nil, includesTargetTime: Bool = false, dailyFocusDate: Date? = nil, dailyFocusTitle: String? = nil, dailyFocusTemplateEntryID: UUID? = nil, focusTaskTemplateID: UUID? = nil, isFocusTemplateCustomized: Bool = false, recurrence: TaskRecurrenceFrequency = .none, recurrenceRootTaskID: UUID? = nil, sortOrder: Int = 0, isRecordingMilestoneDesignated: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.briefID = briefID
        self.pillarID = pillarID
        self.platformOutputID = platformOutputID
        self.parentTaskID = parentTaskID
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.kindRaw = kind.rawValue
        self.laneRaw = lane.rawValue
        self.priorityRaw = priority.rawValue
        self.targetDate = targetDate
        self.includesTargetTime = includesTargetTime
        self.dailyFocusDate = dailyFocusDate.map { Calendar.current.startOfDay(for: $0) }
        self.dailyFocusTitle = dailyFocusTitle
        self.dailyFocusTemplateEntryID = dailyFocusTemplateEntryID
        self.focusTaskTemplateID = focusTaskTemplateID
        self.isFocusTemplateCustomized = isFocusTemplateCustomized
        self.recurrenceRaw = recurrence.rawValue
        self.recurrenceRootTaskID = recurrenceRootTaskID
        self.sortOrder = sortOrder
        self.isRecordingMilestoneDesignated = isRecordingMilestoneDesignated
        self.createdAt = createdAt
        self.bootstrapVersion = 1
    }

    var kind: CreatorTaskKind {
        get { CreatorTaskKind(rawValue: kindRaw) ?? .planning }
        set { kindRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var lane: TaskLane {
        get { TaskLane(rawValue: laneRaw) ?? .production }
        set { laneRaw = newValue.rawValue }
    }

    var recurrence: TaskRecurrenceFrequency {
        get { TaskRecurrenceFrequency(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
}

@Model
final class Pillar {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var parentPillarID: UUID?
    var roleRaw: String = PillarRole.supporting.rawValue
    var name: String = ""
    var detail: String = ""
    var colorHex: String = "55705B"
    var assignedWeekdaysRaw: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    /// Zero identifies a record created before pillar-role backfilling became one-shot.
    var bootstrapVersion: Int = 0

    init(id: UUID = UUID(), parentPillarID: UUID? = nil, role: PillarRole = .supporting, name: String = "", detail: String = "", colorHex: String = "55705B", assignedWeekdays: Set<PillarWeekday> = [], createdAt: Date = Date()) {
        self.id = id
        self.parentPillarID = parentPillarID
        self.roleRaw = role.rawValue
        self.name = name
        self.detail = detail
        self.colorHex = colorHex
        self.assignedWeekdaysRaw = assignedWeekdays.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        self.createdAt = createdAt
        self.bootstrapVersion = 1
    }

    var assignedWeekdays: Set<PillarWeekday> {
        get {
            Set(assignedWeekdaysRaw.split(separator: ",").compactMap { value in
                Int(value).flatMap(PillarWeekday.init(rawValue:))
            })
        }
        set {
            assignedWeekdaysRaw = newValue.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        }
    }

    var isBranch: Bool { parentPillarID != nil }

    var role: PillarRole {
        get { PillarRole(rawValue: roleRaw) ?? (parentPillarID == nil ? .anchor : .supporting) }
        set { roleRaw = newValue.rawValue }
    }

    func resolvedAnchor(in pillars: [Pillar]) -> Pillar {
        guard let parentPillarID,
              let parent = pillars.first(where: { $0.id == parentPillarID && !$0.isArchived }) else {
            return self
        }
        return parent
    }

    func resolvedColorHex(in pillars: [Pillar]) -> String {
        colorHex
    }

    func resolvedWeekdays(in pillars: [Pillar]) -> Set<PillarWeekday> {
        assignedWeekdays
    }
}

@Model
final class PublishingDestination {
    var id: UUID = UUID()
    var name: String = ""
    var builtInKindRaw: String = ""
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, builtInKind: BuiltInDestinationKind? = nil, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.builtInKindRaw = builtInKind?.rawValue ?? ""
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var builtInKind: BuiltInDestinationKind? {
        get { BuiltInDestinationKind(rawValue: builtInKindRaw) }
        set { builtInKindRaw = newValue?.rawValue ?? "" }
    }
}

@Model
final class PublishingFormat {
    var id: UUID = UUID()
    var destinationID: UUID = UUID()
    var name: String = ""
    var kindRaw: String = PublishingFormatKind.nonVideo.rawValue
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), destinationID: UUID, name: String, kind: PublishingFormatKind, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.destinationID = destinationID
        self.name = name
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var kind: PublishingFormatKind {
        get { PublishingFormatKind(rawValue: kindRaw) ?? .nonVideo }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class DailyFocusTemplateEntry {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var weekdayRaw: Int = PillarWeekday.monday.rawValue
    var kindRaw: String = DailyFocusKind.custom.rawValue
    var secondaryKindRaw: String?
    var title: String = ""
    var note: String = ""
    var durationMinutes: Int?
    var startMinutesFromMidnight: Int?
    /// JSON keeps the editable per-day task template additive and CloudKit-safe.
    /// An empty string means the creator has not configured tasks for this day yet.
    var focusTaskTemplatesJSON: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), weekday: PillarWeekday, kind: DailyFocusKind, secondaryKind: DailyFocusKind? = nil, title: String, note: String = "", durationMinutes: Int? = nil, startMinutesFromMidnight: Int? = nil, createdAt: Date = Date()) {
        self.id = id
        self.weekdayRaw = weekday.rawValue
        self.kindRaw = kind.rawValue
        self.secondaryKindRaw = secondaryKind?.rawValue
        self.title = title
        self.note = note
        self.durationMinutes = durationMinutes
        self.startMinutesFromMidnight = startMinutesFromMidnight
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var weekday: PillarWeekday {
        get { PillarWeekday(rawValue: weekdayRaw) ?? .monday }
        set { weekdayRaw = newValue.rawValue }
    }
    var kind: DailyFocusKind {
        get { DailyFocusKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }
    var secondaryKind: DailyFocusKind? {
        get { secondaryKindRaw.flatMap(DailyFocusKind.init(rawValue:)) }
        set { secondaryKindRaw = newValue?.rawValue }
    }

    var hasConfiguredFocusTasks: Bool {
        !focusTaskTemplatesJSON.isEmpty
    }

    var focusTaskTemplates: [DailyFocusTaskTemplateDefinition] {
        get {
            guard let data = focusTaskTemplatesJSON.data(using: .utf8),
                  let value = try? JSONDecoder().decode([DailyFocusTaskTemplateDefinition].self, from: data)
            else { return [] }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8)
            else { return }
            focusTaskTemplatesJSON = value
        }
    }
}

@Model
final class DailyFocusOverride {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var date: Date = Date()
    var templateEntryID: UUID?
    var isCleared: Bool = false
    var kindRaw: String = DailyFocusKind.custom.rawValue
    var secondaryKindRaw: String?
    var title: String = ""
    var note: String = ""
    var durationMinutes: Int?
    var startMinutesFromMidnight: Int?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), date: Date, templateEntryID: UUID? = nil, isCleared: Bool = false, kind: DailyFocusKind = .custom, secondaryKind: DailyFocusKind? = nil, title: String = "", note: String = "", durationMinutes: Int? = nil, startMinutesFromMidnight: Int? = nil, createdAt: Date = Date()) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.templateEntryID = templateEntryID
        self.isCleared = isCleared
        self.kindRaw = kind.rawValue
        self.secondaryKindRaw = secondaryKind?.rawValue
        self.title = title
        self.note = note
        self.durationMinutes = durationMinutes
        self.startMinutesFromMidnight = startMinutesFromMidnight
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var kind: DailyFocusKind {
        get { DailyFocusKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }
    var secondaryKind: DailyFocusKind? {
        get { secondaryKindRaw.flatMap(DailyFocusKind.init(rawValue:)) }
        set { secondaryKindRaw = newValue?.rawValue }
    }
}

@Model
final class DailyFocusDayDetail {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var date: Date = Date()
    var note: String = ""
    var reminderEnabled: Bool = false
    var reminderDate: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        date: Date,
        note: String = "",
        reminderEnabled: Bool = false,
        reminderDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.note = note
        self.reminderEnabled = reminderEnabled
        self.reminderDate = reminderDate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class PendingWeekProposal {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var weekStart: Date = Date()
    var payloadJSON: String = ""
    var sourceFingerprint: String = ""
    var statusRaw: String = "pending"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var appliedAt: Date?

    init(id: UUID = UUID(), weekStart: Date, payloadJSON: String, sourceFingerprint: String, createdAt: Date = Date()) {
        self.id = id
        self.weekStart = weekStart
        self.payloadJSON = payloadJSON
        self.sourceFingerprint = sourceFingerprint
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class CreatorAttachment {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var ownerKindRaw: String = AttachmentOwnerKind.referenceFile.rawValue
    var briefID: UUID = UUID()
    var platformOutputID: UUID?
    var fileName: String = ""
    var kindRaw: String = AttachmentKind.other.rawValue
    var uniformTypeIdentifier: String = "public.data"
    var byteCount: Int64 = 0
    var localRelativePath: String = ""
    @Attribute(.externalStorage) var cloudData: Data?
    var syncStateRaw: String = AttachmentSyncState.localOnly.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), ownerKind: AttachmentOwnerKind, briefID: UUID, platformOutputID: UUID? = nil, fileName: String, kind: AttachmentKind, uniformTypeIdentifier: String, byteCount: Int64, localRelativePath: String, cloudData: Data? = nil, syncState: AttachmentSyncState = .localOnly, createdAt: Date = Date()) {
        self.id = id
        self.ownerKindRaw = ownerKind.rawValue
        self.briefID = briefID
        self.platformOutputID = platformOutputID
        self.fileName = fileName
        self.kindRaw = kind.rawValue
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.byteCount = byteCount
        self.localRelativePath = localRelativePath
        self.cloudData = cloudData
        self.syncStateRaw = syncState.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var ownerKind: AttachmentOwnerKind {
        get { AttachmentOwnerKind(rawValue: ownerKindRaw) ?? .referenceFile }
        set { ownerKindRaw = newValue.rawValue }
    }
    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
    var syncState: AttachmentSyncState {
        get { AttachmentSyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }
}

@Model
final class RhythmTemplate {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var name: String = "My rhythm"
    var entriesText: String = ""
    var isActive: Bool = true
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), name: String = "My rhythm", entriesText: String = "", isActive: Bool = true, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.entriesText = entriesText
        self.isActive = isActive
        self.updatedAt = updatedAt
    }
}

@Model
final class WeekPlan {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var weekStart: Date = Date()
    var rhythmEntriesText: String = ""
    var notes: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), weekStart: Date = Date(), rhythmEntriesText: String = "", notes: String = "", createdAt: Date = Date()) {
        self.id = id
        self.weekStart = weekStart
        self.rhythmEntriesText = rhythmEntriesText
        self.notes = notes
        self.createdAt = createdAt
    }
}

@Model
final class ConversationThread {
    var id: UUID = UUID()
    var workspaceID: UUID?
    var briefID: UUID?
    var contextKindRaw: String = ConversationContextKind.none.rawValue
    var contextID: UUID?
    var isArchived: Bool = false
    var title: String = "Ask Cy"
    var turnCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), briefID: UUID? = nil, contextKind: ConversationContextKind = .none, contextID: UUID? = nil, title: String = "Ask Cy", createdAt: Date = Date()) {
        self.id = id
        self.briefID = briefID
        self.contextKindRaw = contextKind.rawValue
        self.contextID = contextID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var contextKind: ConversationContextKind {
        get { ConversationContextKind(rawValue: contextKindRaw) ?? .none }
        set { contextKindRaw = newValue.rawValue }
    }
}

extension CreativeBrief: WorkspaceScopedRecord {}
extension PendingBriefProposal: WorkspaceScopedRecord {}
extension PlatformOutput: WorkspaceScopedRecord {}
extension CreatorSocialAccount: WorkspaceScopedRecord {}
extension CreatorTask: WorkspaceScopedRecord {}
extension Pillar: WorkspaceScopedRecord {}
extension DailyFocusTemplateEntry: WorkspaceScopedRecord {}
extension DailyFocusOverride: WorkspaceScopedRecord {}
extension DailyFocusDayDetail: WorkspaceScopedRecord {}
extension PendingWeekProposal: WorkspaceScopedRecord {}
extension CreatorAttachment: WorkspaceScopedRecord {}
extension RhythmTemplate: WorkspaceScopedRecord {}
extension WeekPlan: WorkspaceScopedRecord {}
extension ConversationThread: WorkspaceScopedRecord {}

@Model
final class ConversationMessage {
    var id: UUID = UUID()
    var threadID: UUID = UUID()
    var roleRaw: String = ConversationRole.creator.rawValue
    var text: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), threadID: UUID = UUID(), role: ConversationRole = .creator, text: String = "", createdAt: Date = Date()) {
        self.id = id
        self.threadID = threadID
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
    }

    var role: ConversationRole {
        get { ConversationRole(rawValue: roleRaw) ?? .creator }
        set { roleRaw = newValue.rawValue }
    }
}

@Model
final class ReminderSettings {
    var id: UUID = UUID()
    /// The master switch is additive and defaults on so existing Daily and Weekly choices remain effective.
    var masterEnabled: Bool = true
    var dailyEnabled: Bool = false
    var dailyHour: Int = 9
    var dailyMinute: Int = 0
    var weeklyEnabled: Bool = false
    var weeklyWeekday: Int = 2
    var weeklyHour: Int = 9
    var weeklyMinute: Int = 0
    var postRemindersEnabled: Bool = true
    var missedPostRemindersEnabled: Bool = true
    var taskRemindersEnabled: Bool = true
    var draftPrepRemindersEnabled: Bool = true
    var accessRemindersEnabled: Bool = true
    var draftPrepHour: Int = 18
    var draftPrepMinute: Int = 0
    var dateOnlyDeadlineHour: Int = 18
    var dateOnlyDeadlineMinute: Int = 0
    var quietHoursEnabled: Bool = true
    var quietHoursStartHour: Int = 20
    var quietHoursStartMinute: Int = 0
    var quietHoursEndHour: Int = 8
    var quietHoursEndMinute: Int = 0
    var showNotificationTitles: Bool = true
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        masterEnabled: Bool = true,
        dailyEnabled: Bool = false,
        dailyHour: Int = 9,
        dailyMinute: Int = 0,
        weeklyEnabled: Bool = false,
        weeklyWeekday: Int = 2,
        weeklyHour: Int = 9,
        weeklyMinute: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.masterEnabled = masterEnabled
        self.dailyEnabled = dailyEnabled
        self.dailyHour = dailyHour
        self.dailyMinute = dailyMinute
        self.weeklyEnabled = weeklyEnabled
        self.weeklyWeekday = weeklyWeekday
        self.weeklyHour = weeklyHour
        self.weeklyMinute = weeklyMinute
        self.updatedAt = updatedAt
    }
}

@Model
final class SubscriptionState {
    var id: UUID = UUID()
    var accessRaw: String = SubscriptionAccess.freeJourney.rawValue
    var trialEnd: Date?
    var freeBriefConsumed: Bool = false
    var ideationRequestsUsed: Int = 0
    var revisionRequestsUsed: Int = 0
    var teachCyUpdatesUsed: Int = 0
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), access: SubscriptionAccess = .freeJourney, trialEnd: Date? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.accessRaw = access.rawValue
        self.trialEnd = trialEnd
        self.updatedAt = updatedAt
    }

    var access: SubscriptionAccess {
        get { SubscriptionAccess(rawValue: accessRaw) ?? .freeJourney }
        set { accessRaw = newValue.rawValue }
    }
}

enum AgentCySchema {
    static let types: [any PersistentModel.Type] = [
        CreatorWorkspace.self,
        CreatorProfile.self,
        VoiceExample.self,
        VoiceProfile.self,
        CreativeBrief.self,
        PendingBriefProposal.self,
        PendingVoiceProfileProposal.self,
        PlatformOutput.self,
        CreatorSocialAccount.self,
        CreatorTask.self,
        Pillar.self,
        PublishingDestination.self,
        PublishingFormat.self,
        DailyFocusTemplateEntry.self,
        DailyFocusOverride.self,
        DailyFocusDayDetail.self,
        PendingWeekProposal.self,
        CreatorAttachment.self,
        RhythmTemplate.self,
        WeekPlan.self,
        ConversationThread.self,
        ConversationMessage.self,
        ReminderSettings.self,
        SubscriptionState.self
    ]

    static var schema: Schema { Schema(types) }
}
