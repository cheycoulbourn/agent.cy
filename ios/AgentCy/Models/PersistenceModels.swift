import Foundation
import SwiftData

@Model
final class CreatorProfile {
    var id: UUID = UUID()
    var name: String = ""
    var goal: String = ""
    var selectedPlatformsRaw: String = CreatorPlatform.instagramReels.rawValue
    var assistanceModeRaw: String = AssistanceMode.collaborate.rawValue
    var adultConfirmed: Bool = false
    var telemetryConsent: Bool = false
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        goal: String = "",
        selectedPlatforms: [CreatorPlatform] = [.instagramReels],
        assistanceMode: AssistanceMode = .collaborate,
        adultConfirmed: Bool = false,
        telemetryConsent: Bool = false,
        onboardingCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.selectedPlatformsRaw = selectedPlatforms.map(\.rawValue).joined(separator: ",")
        self.assistanceModeRaw = assistanceMode.rawValue
        self.adultConfirmed = adultConfirmed
        self.telemetryConsent = telemetryConsent
        self.onboardingCompleted = onboardingCompleted
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
}

@Model
final class VoiceExample {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var text: String = ""
    var sortOrder: Int = 0
    var sourceRaw: String = VoiceExampleSource.text.rawValue
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
        self.sourceURLString = sourceURLString
        self.creatorConfirmed = creatorConfirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var source: VoiceExampleSource {
        get { VoiceExampleSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
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
    var title: String = "Untitled spark"
    var premise: String = ""
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
    var briefID: UUID = UUID()
    var platformRaw: String = CreatorPlatform.instagramReels.rawValue
    var caption: String = ""
    var openingAdjustment: String = ""
    var titleOverride: String = ""
    var cta: String = ""
    var editChanges: String = ""
    var statusRaw: String = PlatformOutputStatus.draft.rawValue
    var targetDate: Date?
    var postedAt: Date?
    var createdAt: Date = Date()

    init(id: UUID = UUID(), briefID: UUID = UUID(), platform: CreatorPlatform = .instagramReels, status: PlatformOutputStatus = .draft, createdAt: Date = Date()) {
        self.id = id
        self.briefID = briefID
        self.platformRaw = platform.rawValue
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
}

@Model
final class CreatorTask {
    var id: UUID = UUID()
    var briefID: UUID?
    var title: String = ""
    var notes: String = ""
    var estimatedMinutes: Int?
    var kindRaw: String = CreatorTaskKind.planning.rawValue
    var isCompleted: Bool = false
    var targetDate: Date?
    var sortOrder: Int = 0
    var completedAt: Date?
    var recordingMilestoneEmitted: Bool = false
    var isRecordingMilestoneDesignated: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), briefID: UUID? = nil, title: String = "", kind: CreatorTaskKind = .planning, notes: String = "", estimatedMinutes: Int? = nil, targetDate: Date? = nil, sortOrder: Int = 0, isRecordingMilestoneDesignated: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.briefID = briefID
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.kindRaw = kind.rawValue
        self.targetDate = targetDate
        self.sortOrder = sortOrder
        self.isRecordingMilestoneDesignated = isRecordingMilestoneDesignated
        self.createdAt = createdAt
    }

    var kind: CreatorTaskKind {
        get { CreatorTaskKind(rawValue: kindRaw) ?? .planning }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class Pillar {
    var id: UUID = UUID()
    var name: String = ""
    var detail: String = ""
    var colorHex: String = "9B3A2E"
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", detail: String = "", colorHex: String = "9B3A2E", createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.detail = detail
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

@Model
final class RhythmTemplate {
    var id: UUID = UUID()
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
    var briefID: UUID?
    var title: String = "Ask Cy"
    var turnCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), briefID: UUID? = nil, title: String = "Ask Cy", createdAt: Date = Date()) {
        self.id = id
        self.briefID = briefID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

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
    var dailyEnabled: Bool = false
    var dailyHour: Int = 9
    var weeklyEnabled: Bool = false
    var weeklyWeekday: Int = 2
    var weeklyHour: Int = 9
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), dailyEnabled: Bool = false, dailyHour: Int = 9, weeklyEnabled: Bool = false, weeklyWeekday: Int = 2, weeklyHour: Int = 9, updatedAt: Date = Date()) {
        self.id = id
        self.dailyEnabled = dailyEnabled
        self.dailyHour = dailyHour
        self.weeklyEnabled = weeklyEnabled
        self.weeklyWeekday = weeklyWeekday
        self.weeklyHour = weeklyHour
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
        CreatorProfile.self,
        VoiceExample.self,
        VoiceProfile.self,
        CreativeBrief.self,
        PendingBriefProposal.self,
        PendingVoiceProfileProposal.self,
        PlatformOutput.self,
        CreatorTask.self,
        Pillar.self,
        RhythmTemplate.self,
        WeekPlan.self,
        ConversationThread.self,
        ConversationMessage.self,
        ReminderSettings.self,
        SubscriptionState.self
    ]

    static var schema: Schema { Schema(types) }
}
