import Foundation
import SwiftData

enum MCPBridgeError: LocalizedError {
    case notConnected
    case inaccessibleFolder
    case unableToSaveFolderAccess
    case invalidRequest(String)
    case missingRecord(String)
    case actionNotAllowed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Choose the agent.cy MCP folder first."
        case .inaccessibleFolder: "The selected Files folder is no longer available. Choose it again."
        case .unableToSaveFolderAccess: "agent.cy could not keep access to that folder. Choose the agent.cy MCP folder itself in iCloud Drive."
        case .invalidRequest: "The proposal could not be read. Ask Claude or Codex to prepare it again."
        case .missingRecord(let message): message
        case .actionNotAllowed(let message): message
        }
    }
}

enum MCPBridgeBookmarkStrategy: Equatable {
    case minimal
    case securityScoped
}

enum MCPBridgeBookmarkPolicy {
    static func strategy(isMacCatalyst: Bool) -> MCPBridgeBookmarkStrategy {
        isMacCatalyst ? .securityScoped : .minimal
    }

    static var currentStrategy: MCPBridgeBookmarkStrategy {
        #if targetEnvironment(macCatalyst)
        strategy(isMacCatalyst: true)
        #else
        strategy(isMacCatalyst: false)
        #endif
    }

    static var creationOptions: URL.BookmarkCreationOptions {
        switch currentStrategy {
        case .minimal:
            [.minimalBookmark]
        case .securityScoped:
            #if targetEnvironment(macCatalyst)
            [.withSecurityScope]
            #else
            [.minimalBookmark]
            #endif
        }
    }

    static var resolutionOptions: URL.BookmarkResolutionOptions {
        switch currentStrategy {
        case .minimal:
            [.withoutUI]
        case .securityScoped:
            #if targetEnvironment(macCatalyst)
            [.withSecurityScope, .withoutUI]
            #else
            [.withoutUI]
            #endif
        }
    }
}

enum MCPBridgeQueueMaterializationPolicy {
    static let maximumRefreshAttempts = 20
    static let minimumEmptyRefreshAttempts = 5

    static func logicalURL(forICloudPlaceholder url: URL) -> URL? {
        let name = url.lastPathComponent
        let suffix = ".icloud"
        guard name.hasPrefix("."), name.hasSuffix(suffix) else { return nil }
        let logicalName = String(name.dropFirst().dropLast(suffix.count))
        guard !logicalName.isEmpty else { return nil }
        return url.deletingLastPathComponent().appending(path: logicalName)
    }

    static func downloadCandidates(
        rootDirectory: URL,
        requestsDirectory: URL,
        entries: [URL]
    ) -> [URL] {
        var seen: Set<URL> = []
        return ([rootDirectory, requestsDirectory] + entries.flatMap { entry in
            if let logicalURL = logicalURL(forICloudPlaceholder: entry) {
                return [entry, logicalURL]
            }
            return [entry]
        }).filter { seen.insert($0).inserted }
    }

    static func shouldRetry(
        completedAttempt: Int,
        hasUndownloadedPlaceholders: Bool,
        requestCount: Int
    ) -> Bool {
        guard completedAttempt + 1 < maximumRefreshAttempts else { return false }
        if hasUndownloadedPlaceholders { return true }
        return requestCount == 0 && completedAttempt + 1 < minimumEmptyRefreshAttempts
    }
}

enum MCPBridgePreferences {
    static let bookmarkKey = "agentcy.mcp.folderBookmark"
    static let folderNameKey = "agentcy.mcp.folderName"
    static let lastSyncKey = "agentcy.mcp.lastSync"

    static var isConnected: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var folderName: String {
        UserDefaults.standard.string(forKey: folderNameKey) ?? "agent.cy MCP"
    }

    static var lastSyncAt: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    static func connect(to url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: MCPBridgeBookmarkPolicy.creationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw MCPBridgeError.unableToSaveFolderAccess
        }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
    }

    static func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderNameKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
    }

    static func withDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw MCPBridgeError.notConnected
        }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: MCPBridgeBookmarkPolicy.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale { try connect(to: url) }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPBridgeError.inaccessibleFolder
        }
        return try body(url)
    }
}

struct MCPBridgeProfileSnapshot: Codable {
    let id: UUID
    let name: String
    let goal: String
}

struct MCPBridgeSocialAccountSnapshot: Codable {
    let id: UUID
    let destinationId: UUID
    let destination: String
    let label: String
    let isPrimary: Bool
}

struct MCPBridgeConnectionStatus: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let status: String
    let updatedAt: Date
    let clients: [String]
    let message: String

    var isRecentlyConnected: Bool {
        status == "connected" && Date().timeIntervalSince(updatedAt) < 10 * 60
    }

    var clientSummary: String {
        let names = clients.compactMap { client -> String? in
            switch client.lowercased() {
            case "claude": "Claude Code"
            case "codex": "Codex"
            default: nil
            }
        }
        guard !names.isEmpty else { return "Claude or Codex" }
        return ListFormatter.localizedString(byJoining: names)
    }
}

struct MCPBridgePillarSnapshot: Codable {
    let id: UUID
    let parentPillarId: UUID?
    let name: String
    let colorHex: String
    let role: String
    let assignedWeekdays: [Int]

    private enum CodingKeys: String, CodingKey {
        case id, parentPillarId, name, colorHex, role, assignedWeekdays
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeOptional(parentPillarId, forKey: .parentPillarId)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(role, forKey: .role)
        try container.encode(assignedWeekdays, forKey: .assignedWeekdays)
    }
}

struct MCPBridgeOutputSnapshot: Codable {
    let id: UUID
    let platform: String
    let destination: String
    let format: String
    let socialAccountId: UUID?
    let account: String?
    let status: String
    let targetDate: Date?
    let includesTargetTime: Bool
    let durationSeconds: Int
    let title: String
    let caption: String
    let openingAdjustment: String
    let callToAction: String
    let editNotes: String
    let publishedUrl: String

    private enum CodingKeys: String, CodingKey {
        case id, platform, destination, format, socialAccountId, account, status, targetDate
        case includesTargetTime, durationSeconds, title, caption, openingAdjustment
        case callToAction, editNotes, publishedUrl
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(platform, forKey: .platform)
        try container.encode(destination, forKey: .destination)
        try container.encode(format, forKey: .format)
        try container.encodeOptional(socialAccountId, forKey: .socialAccountId)
        try container.encodeOptional(account, forKey: .account)
        try container.encode(status, forKey: .status)
        try container.encodeOptional(targetDate, forKey: .targetDate)
        try container.encode(includesTargetTime, forKey: .includesTargetTime)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(title, forKey: .title)
        try container.encode(caption, forKey: .caption)
        try container.encode(openingAdjustment, forKey: .openingAdjustment)
        try container.encode(callToAction, forKey: .callToAction)
        try container.encode(editNotes, forKey: .editNotes)
        try container.encode(publishedUrl, forKey: .publishedUrl)
    }
}

struct MCPBridgeTaskSnapshot: Codable {
    let id: UUID
    let briefId: UUID?
    let pillarId: UUID?
    let outputId: UUID?
    let parentTaskId: UUID?
    let title: String
    let notes: String
    let kind: String
    let lane: String
    let priority: String
    let completed: Bool
    let targetDate: Date?
    let includesTargetTime: Bool

    private enum CodingKeys: String, CodingKey {
        case id, briefId, pillarId, outputId, parentTaskId, title, notes, kind
        case lane, priority, completed, targetDate, includesTargetTime
    }

    init(_ task: CreatorTask) {
        id = task.id
        briefId = task.briefID
        pillarId = task.pillarID
        outputId = task.platformOutputID
        parentTaskId = task.parentTaskID
        title = task.title
        notes = task.notes
        kind = task.kind.rawValue
        lane = task.lane.rawValue
        priority = task.priority.rawValue
        completed = task.isCompleted
        targetDate = task.targetDate
        includesTargetTime = task.includesTargetTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeOptional(briefId, forKey: .briefId)
        try container.encodeOptional(pillarId, forKey: .pillarId)
        try container.encodeOptional(outputId, forKey: .outputId)
        try container.encodeOptional(parentTaskId, forKey: .parentTaskId)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(kind, forKey: .kind)
        try container.encode(lane, forKey: .lane)
        try container.encode(priority, forKey: .priority)
        try container.encode(completed, forKey: .completed)
        try container.encodeOptional(targetDate, forKey: .targetDate)
        try container.encode(includesTargetTime, forKey: .includesTargetTime)
    }
}

struct MCPBridgePostSnapshot: Codable {
    let id: UUID
    let title: String
    let premise: String
    let notes: String
    let status: String
    let pillarId: UUID?
    let workDate: Date?
    let includesWorkTime: Bool
    let durationSeconds: Int
    let hook: String
    let firstFrameText: String
    let script: [String]
    let ending: String
    let callToAction: String
    let createdAt: Date
    let updatedAt: Date
    let markdown: String
    let outputs: [MCPBridgeOutputSnapshot]
    let tasks: [MCPBridgeTaskSnapshot]
    let seriesId: UUID?
    let episodeNumber: Int?
    let episodeLabel: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, premise, notes, status, pillarId, workDate, includesWorkTime
        case durationSeconds, hook
        case firstFrameText, script, ending, callToAction, createdAt, updatedAt
        case markdown, outputs, tasks, seriesId, episodeNumber, episodeLabel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(premise, forKey: .premise)
        try container.encode(notes, forKey: .notes)
        try container.encode(status, forKey: .status)
        try container.encodeOptional(pillarId, forKey: .pillarId)
        try container.encodeOptional(workDate, forKey: .workDate)
        try container.encode(includesWorkTime, forKey: .includesWorkTime)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(hook, forKey: .hook)
        try container.encode(firstFrameText, forKey: .firstFrameText)
        try container.encode(script, forKey: .script)
        try container.encode(ending, forKey: .ending)
        try container.encode(callToAction, forKey: .callToAction)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(markdown, forKey: .markdown)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(tasks, forKey: .tasks)
        try container.encodeOptional(seriesId, forKey: .seriesId)
        try container.encodeOptional(episodeNumber, forKey: .episodeNumber)
        try container.encodeOptional(episodeLabel, forKey: .episodeLabel)
    }
}

struct MCPBridgeSeriesSnapshot: Codable {
    let id: UUID
    let name: String
    let pillarId: UUID?
    let state: String
    let defaultPlatform: String?
    let defaultDestinationId: UUID?
    let defaultFormatId: UUID?
    let defaultSocialAccountId: UUID?
    let defaultDurationSeconds: Int?
    let cadence: String
    let cadenceStartDate: Date?
    let cadenceWeekdays: [Int]
    let cadenceMonthDay: Int?
    let cadenceEndDate: Date?
    let cadenceIncludesTime: Bool
    let taskTemplate: [MCPBridgeSeriesTaskTemplateSnapshot]
}

struct MCPBridgeSeriesTaskTemplateSnapshot: Codable {
    let id: UUID
    let title: String
    let notes: String
    let kind: String
    let priority: String
    let estimatedMinutes: Int?
    let sortOrder: Int
}

struct MCPBridgeEpisodeSlotSnapshot: Codable {
    let id: UUID
    let seriesId: UUID
    let plannedDate: Date
    let includesTime: Bool
    let status: String
    let convertedPostId: UUID?
}

struct MCPBridgeBrandPartnerSnapshot: Codable {
    let id: UUID
    let name: String
    let type: String
    let stage: String
    let website: String
    let socialHandle: String
    let notes: String
    let nextFollowUpAt: Date?
    let lastContactedAt: Date?
}

struct MCPBridgeWorkspaceSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let workspaceId: UUID?
    let workspaceName: String?
    let profile: MCPBridgeProfileSnapshot?
    let socialAccounts: [MCPBridgeSocialAccountSnapshot]
    let pillars: [MCPBridgePillarSnapshot]
    let posts: [MCPBridgePostSnapshot]
    let tasks: [MCPBridgeTaskSnapshot]
    let series: [MCPBridgeSeriesSnapshot]
    let episodeSlots: [MCPBridgeEpisodeSlotSnapshot]
    let brandPartners: [MCPBridgeBrandPartnerSnapshot]
    let notification: MCPBridgePushCapability?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, workspaceId, workspaceName, profile, socialAccounts, pillars, posts, tasks
        case series, episodeSlots, brandPartners, notification
    }

    init(
        schemaVersion: Int,
        generatedAt: Date,
        workspaceId: UUID?,
        workspaceName: String?,
        profile: MCPBridgeProfileSnapshot?,
        socialAccounts: [MCPBridgeSocialAccountSnapshot],
        pillars: [MCPBridgePillarSnapshot],
        posts: [MCPBridgePostSnapshot],
        tasks: [MCPBridgeTaskSnapshot],
        series: [MCPBridgeSeriesSnapshot],
        episodeSlots: [MCPBridgeEpisodeSlotSnapshot],
        brandPartners: [MCPBridgeBrandPartnerSnapshot],
        notification: MCPBridgePushCapability? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.profile = profile
        self.socialAccounts = socialAccounts
        self.pillars = pillars
        self.posts = posts
        self.tasks = tasks
        self.series = series
        self.episodeSlots = episodeSlots
        self.brandPartners = brandPartners
        self.notification = notification
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        workspaceId = try container.decodeIfPresent(UUID.self, forKey: .workspaceId)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        profile = try container.decodeIfPresent(MCPBridgeProfileSnapshot.self, forKey: .profile)
        socialAccounts = try container.decodeIfPresent(
            [MCPBridgeSocialAccountSnapshot].self,
            forKey: .socialAccounts
        ) ?? []
        pillars = try container.decode([MCPBridgePillarSnapshot].self, forKey: .pillars)
        posts = try container.decode([MCPBridgePostSnapshot].self, forKey: .posts)
        tasks = try container.decode([MCPBridgeTaskSnapshot].self, forKey: .tasks)
        series = try container.decodeIfPresent([MCPBridgeSeriesSnapshot].self, forKey: .series) ?? []
        episodeSlots = try container.decodeIfPresent([MCPBridgeEpisodeSlotSnapshot].self, forKey: .episodeSlots) ?? []
        brandPartners = try container.decodeIfPresent([MCPBridgeBrandPartnerSnapshot].self, forKey: .brandPartners) ?? []
        notification = try container.decodeIfPresent(MCPBridgePushCapability.self, forKey: .notification)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeOptional(workspaceId, forKey: .workspaceId)
        try container.encodeOptional(workspaceName, forKey: .workspaceName)
        try container.encodeOptional(profile, forKey: .profile)
        try container.encode(socialAccounts, forKey: .socialAccounts)
        try container.encode(pillars, forKey: .pillars)
        try container.encode(posts, forKey: .posts)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(series, forKey: .series)
        try container.encode(episodeSlots, forKey: .episodeSlots)
        try container.encode(brandPartners, forKey: .brandPartners)
        try container.encodeOptional(notification, forKey: .notification)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

struct MCPBridgeRequestPayload: Codable, Equatable {
    var title: String?
    var premise: String?
    var notes: String?
    var pillarId: UUID?
    var platform: String?
    var format: String?
    var socialAccountId: UUID?
    var postId: UUID?
    var outputId: UUID?
    var hook: String?
    var caption: String?
    var callToAction: String?
    var targetDate: Date?
    var includesTargetTime: Bool?
    var kind: String?
    var lane: String?
    var priority: String?
    var taskId: UUID?
    var name: String?
    var seriesId: UUID?
    var episodeSlotId: UUID?
    var proposedEpisodeSlotId: UUID?
    var episodeReviewId: UUID?
    var revisionNumber: Int?
    var revisionOfRequestId: UUID?
    var episodeNumber: Int?
    var episodeLabel: String?
    var workDate: Date?
    var includesWorkTime: Bool?
    var clearWorkDate: Bool?
    var postedAt: Date?
    var cadence: String?
    var cadenceStartDate: Date?
    var cadenceWeekdays: [Int]?
    var cadenceMonthDay: Int?
    var cadenceEndDate: Date?
    var brandPartnerId: UUID?
    var brandType: String?
    var brandStage: String?
    var website: String?
    var socialHandle: String?
    var nextFollowUpAt: Date?
    var clearNextFollowUp: Bool?
}

struct MCPBridgeChangeRequest: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let source: String
    let workspaceId: UUID?
    let externalPlan: MCPBridgeExternalPlanContext?
    let type: String
    let payload: MCPBridgeRequestPayload

    init(
        schemaVersion: Int,
        id: UUID,
        createdAt: Date,
        source: String,
        workspaceId: UUID?,
        externalPlan: MCPBridgeExternalPlanContext? = nil,
        type: String,
        payload: MCPBridgeRequestPayload
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.workspaceId = workspaceId
        self.externalPlan = externalPlan
        self.type = type
        self.payload = payload
    }

    var title: String {
        switch type {
        case "createIdea": "Save an idea"
        case "createPostDraft": payload.targetDate == nil ? "Create a post draft" : "Create and schedule a post"
        case "updatePost": "Update a post"
        case "schedulePost": "Schedule a post"
        case "reschedulePost": "Reschedule a post"
        case "markPostPosted": "Mark a post as posted"
        case "createSeries": "Create a series"
        case "createSeriesEpisode": "Create a series episode"
        case "createBrandPartner": "Create a brand partner"
        case "updateBrandPartner": "Update a brand partner"
        case "makeAnchorPillar": "Make an anchor pillar"
        case "addTask": "Add a task"
        case "completeTask": "Complete a task"
        default: "Proposal"
        }
    }

    var summary: String {
        payload.title ?? payload.name ?? payload.postId?.uuidString ?? payload.taskId?.uuidString
            ?? payload.brandPartnerId?.uuidString ?? "Review the requested change."
    }

    func replacingPayload(_ payload: MCPBridgeRequestPayload) -> MCPBridgeChangeRequest {
        MCPBridgeChangeRequest(
            schemaVersion: schemaVersion,
            id: id,
            createdAt: createdAt,
            source: source,
            workspaceId: workspaceId,
            externalPlan: externalPlan,
            type: type,
            payload: payload
        )
    }
}

struct MCPBridgeExternalPlanContext: Codable, Equatable {
    let status: String
    let creatorConfirmed: Bool
    let system: String?
    let workspace: String?
    let destination: String?
    let sourceOfTruth: String?
    let syncDirection: String?
    let externalWritesRequireApproval: Bool?
}

private struct MCPBridgeReceipt: Codable {
    let schemaVersion: Int
    let requestId: UUID
    let processedAt: Date
    let status: String
    let message: String
    let workspaceId: UUID?
    let type: String?
    let seriesId: UUID?
    let episodeReviewId: UUID?
    let episodeSlotId: UUID?
    let revisionNumber: Int?
    let decisionNote: String?
    let resultPostId: UUID?
    let nextAction: String?
}

struct MCPBridgeEpisodeRevisionRecord: Codable, Equatable {
    let schemaVersion: Int
    let episodeReviewId: UUID
    let workspaceId: UUID?
    let seriesId: UUID
    let episodeSlotId: UUID?
    var requestId: UUID
    var revisionNumber: Int
    var status: String
    var decisionAt: Date
    var decisionNote: String
    var request: MCPBridgeChangeRequest
}

private struct MCPBridgeChangeRequestHeader: Decodable {
    let schemaVersion: Int
    let workspaceId: UUID?
}

@MainActor
enum MCPBridgeService {
    nonisolated static func connectionStatus() throws -> MCPBridgeConnectionStatus? {
        guard MCPBridgePreferences.isConnected else { return nil }
        return try MCPBridgePreferences.withDirectory { directory in
            let url = directory.appending(path: "bridge-status.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MCPBridgeConnectionStatus.self, from: Data(contentsOf: url))
        }
    }

    nonisolated static let schemaVersion = 1

    static func sync(context: ModelContext, workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID) throws {
        guard MCPBridgePreferences.isConnected else { return }
        try MCPBridgePreferences.withDirectory { directory in
            try sync(context: context, directory: directory, workspaceID: workspaceID)
        }
    }

    static func sync(
        context: ModelContext,
        directory: URL,
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) throws {
        if try migrateStructuredPostFields(context: context) {
            try context.save()
        }
        let notification = BridgePushRegistrationPolicy.snapshotCapabilityForCurrentPlatform(
            local: MCPBridgePushPreferences.capability,
            existing: existingNotificationCapability(in: directory)
        )
        let snapshot = try makeSnapshot(
            context: context,
            workspaceID: workspaceID,
            notification: notification
        )
        try prepare(directory: directory)
        try encoder.encode(snapshot).write(
            to: directory.appending(path: "snapshot.json"),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        try writeReadme(directory: directory)
        UserDefaults.standard.set(Date(), forKey: MCPBridgePreferences.lastSyncKey)
    }

    private static func existingNotificationCapability(in directory: URL) -> MCPBridgePushCapability? {
        let snapshotURL = directory.appending(path: "snapshot.json")
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? decoder.decode(MCPBridgeWorkspaceSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.notification
    }

    // Reading the review queue is pure file I/O; it stays callable from a
    // background task so the shells' 4-second polls never block the main
    // thread on an iCloud Drive folder.
    nonisolated static func pendingRequests(
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) throws -> [MCPBridgeChangeRequest] {
        guard MCPBridgePreferences.isConnected else { return [] }
        return try MCPBridgePreferences.withDirectory { directory in
            try pendingRequests(directory: directory, workspaceID: workspaceID)
        }
    }

    nonisolated static func pendingRequests(
        directory: URL,
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) throws -> [MCPBridgeChangeRequest] {
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        let requestURLs = try FileManager.default.contentsOfDirectory(
            at: requests,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }

        return try requestURLs.compactMap { url in
            do {
                let data = try Data(contentsOf: url)
                let header = try decoder.decode(MCPBridgeChangeRequestHeader.self, from: data)
                guard header.schemaVersion == schemaVersion else {
                    throw MCPBridgeError.invalidRequest("Unsupported schema version in \(url.lastPathComponent).")
                }
                if let requestWorkspaceID = header.workspaceId,
                   requestWorkspaceID != workspaceID {
                    return nil
                }
                let request = try decoder.decode(MCPBridgeChangeRequest.self, from: data)
                return request
            } catch let error as MCPBridgeError {
                throw error
            } catch {
                throw MCPBridgeError.invalidRequest(
                    "Could not read \(url.lastPathComponent). The review queue was left unchanged."
                )
            }
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// Asks iCloud Drive to materialize the bridge queue, then performs a
    /// short bounded re-read so manual and foreground refreshes can observe a
    /// request that arrived while the app was inactive.
    nonisolated static func refreshPendingRequests(
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) async throws -> [MCPBridgeChangeRequest] {
        guard MCPBridgePreferences.isConnected else { return [] }
        var latest: [MCPBridgeChangeRequest] = []
        for attempt in 0..<MCPBridgeQueueMaterializationPolicy.maximumRefreshAttempts {
            let result = try MCPBridgePreferences.withDirectory { directory in
                let hasUndownloadedPlaceholders = try requestUbiquitousDownloads(in: directory)
                return (
                    try pendingRequests(directory: directory, workspaceID: workspaceID),
                    hasUndownloadedPlaceholders
                )
            }
            latest = result.0
            guard MCPBridgeQueueMaterializationPolicy.shouldRetry(
                completedAttempt: attempt,
                hasUndownloadedPlaceholders: result.1,
                requestCount: latest.count
            ) else { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        return latest
    }

    nonisolated static func refreshPendingRequests(
        directory: URL,
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) async throws -> [MCPBridgeChangeRequest] {
        var latest: [MCPBridgeChangeRequest] = []
        for attempt in 0..<MCPBridgeQueueMaterializationPolicy.maximumRefreshAttempts {
            let hasUndownloadedPlaceholders = try requestUbiquitousDownloads(in: directory)
            latest = try pendingRequests(directory: directory, workspaceID: workspaceID)
            guard MCPBridgeQueueMaterializationPolicy.shouldRetry(
                completedAttempt: attempt,
                hasUndownloadedPlaceholders: hasUndownloadedPlaceholders,
                requestCount: latest.count
            ) else { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        return latest
    }

    @discardableResult
    private nonisolated static func requestUbiquitousDownloads(in directory: URL) throws -> Bool {
        let fileManager = FileManager.default
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: requests, withIntermediateDirectories: true)
        // An undownloaded iCloud item is a hidden placeholder named
        // ".<filename>.icloud". Skipping hidden files here skipped exactly the
        // items that still needed downloading, so a device that never
        // materialised the folder (typically iPhone) saw an empty queue
        // forever. Include hidden entries so the download is actually asked for.
        let entries = (try? fileManager.contentsOfDirectory(
            at: requests,
            includingPropertiesForKeys: [.isUbiquitousItemKey],
            options: []
        )) ?? []
        let candidates = MCPBridgeQueueMaterializationPolicy.downloadCandidates(
            rootDirectory: directory,
            requestsDirectory: requests,
            entries: entries
        )
        for url in candidates {
            // File Provider may expose an undownloaded item as
            // `.request.json.icloud`, while FileManager expects the logical
            // `request.json` URL when starting the download. Ask for both;
            // non-ubiquitous local files simply fail this best-effort call.
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }
        return entries.contains {
            MCPBridgeQueueMaterializationPolicy.logicalURL(forICloudPlaceholder: $0) != nil
        }
    }

    nonisolated static func updatePendingRequest(_ request: MCPBridgeChangeRequest) throws {
        guard MCPBridgePreferences.isConnected else { throw MCPBridgeError.notConnected }
        try MCPBridgePreferences.withDirectory { directory in
            try updatePendingRequest(request, directory: directory)
        }
    }

    nonisolated static func updatePendingRequest(
        _ request: MCPBridgeChangeRequest,
        directory: URL
    ) throws {
        guard request.schemaVersion == schemaVersion else {
            throw MCPBridgeError.invalidRequest("This proposal uses an unsupported schema version.")
        }
        try prepare(directory: directory)
        try encoder.encode(request).write(
            to: directory
                .appending(path: "requests", directoryHint: .isDirectory)
                .appending(path: "\(request.id.uuidString.lowercased()).json"),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    @discardableResult
    static func queueDemoDraft(context: ModelContext) throws -> MCPBridgeChangeRequest {
        guard MCPBridgePreferences.isConnected else { throw MCPBridgeError.notConnected }
        return try MCPBridgePreferences.withDirectory { directory in
            try queueDemoDraft(context: context, directory: directory)
        }
    }

    @discardableResult
    static func queueDemoDraft(
        context: ModelContext,
        directory: URL,
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) throws -> MCPBridgeChangeRequest {
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let activeID = WorkspaceScope.activeWorkspaceID(preferredID: workspaceID, workspaces: workspaces)
        let availablePillars: [Pillar] = try context.fetch(FetchDescriptor<Pillar>())
        let pillar = availablePillars
            .filter {
                !$0.isArchived && WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: activeID,
                    workspaces: workspaces
                )
            }
            .sorted(by: { lhs, rhs in
                if lhs.parentPillarID == nil, rhs.parentPillarID != nil { return true }
                if lhs.parentPillarID != nil, rhs.parentPillarID == nil { return false }
                return lhs.createdAt < rhs.createdAt
            })
            .first

        let request = MCPBridgeChangeRequest(
            schemaVersion: schemaVersion,
            id: UUID(),
            createdAt: Date(),
            source: "agentcy-demo",
            workspaceId: activeID,
            externalPlan: nil,
            type: "createPostDraft",
            payload: MCPBridgeRequestPayload(
                title: "A gentler way to plan content",
                premise: "Show how one small planning habit creates more room to make the work.",
                notes: "Keep the visuals simple: one planning screen, one working moment, and the finished result.",
                pillarId: pillar?.id,
                platform: CreatorPlatform.instagramReels.rawValue,
                format: "Reel",
                postId: nil,
                outputId: nil,
                hook: "I stopped rebuilding my content plan from scratch every morning.",
                caption: "A simple plan should make creating feel lighter, not give you another system to maintain. This is the small shift that helped me keep ideas moving without forcing the process.",
                callToAction: "Save this for your next planning session.",
                targetDate: nil,
                includesTargetTime: nil,
                kind: nil,
                lane: nil,
                priority: nil,
                taskId: nil
            )
        )

        try prepare(directory: directory)
        try encoder.encode(request).write(
            to: directory
                .appending(path: "requests", directoryHint: .isDirectory)
                .appending(path: "\(request.id.uuidString.lowercased()).json"),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        return request
    }

    static func approve(_ request: MCPBridgeChangeRequest, context: ModelContext) throws {
        guard MCPBridgePreferences.isConnected else { throw MCPBridgeError.notConnected }
        try MCPBridgePreferences.withDirectory { directory in
            try approve(request, context: context, directory: directory)
        }
    }

    static func approve(
        _ request: MCPBridgeChangeRequest,
        context: ModelContext,
        directory: URL
    ) throws {
        do {
            // Establish a clean rollback boundary so an invalid proposal cannot
            // leave partially mutated or inserted models in the live context.
            try context.save()
            try apply(request, context: context)
            try context.save()
            try finish(
                request,
                status: "approved",
                message: "Applied in agent.cy.",
                context: context,
                directory: directory
            )
            try sync(context: context, directory: directory)
            WidgetSnapshotService.refresh(context: context)
        } catch {
            context.rollback()
            try? finish(
                request,
                status: "failed",
                message: error.localizedDescription,
                directory: directory
            )
            throw error
        }
    }

    static func approve(_ requests: [MCPBridgeChangeRequest], context: ModelContext) throws {
        guard MCPBridgePreferences.isConnected else { throw MCPBridgeError.notConnected }
        try MCPBridgePreferences.withDirectory { directory in
            try approve(requests, context: context, directory: directory)
        }
    }

    static func approve(
        _ requests: [MCPBridgeChangeRequest],
        context: ModelContext,
        directory: URL
    ) throws {
        guard !requests.isEmpty else { return }
        let ordered = requests.sorted { left, right in
            if left.type == "createSeries", right.type != "createSeries" { return true }
            if left.type != "createSeries", right.type == "createSeries" { return false }
            let leftNumber = left.payload.episodeNumber ?? Int.max
            let rightNumber = right.payload.episodeNumber ?? Int.max
            if leftNumber != rightNumber { return leftNumber < rightNumber }
            return left.createdAt < right.createdAt
        }
        do {
            try context.save()
            for request in ordered {
                try apply(request, context: context)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        for request in ordered {
            try finish(
                request,
                status: "approved",
                message: "Applied in agent.cy as part of the approved series bundle.",
                context: context,
                directory: directory
            )
        }
        try sync(context: context, directory: directory)
        WidgetSnapshotService.refresh(context: context)
    }

    static func approveEpisodeInBundle(
        _ episode: MCPBridgeChangeRequest,
        seriesRequest: MCPBridgeChangeRequest,
        context: ModelContext
    ) throws {
        guard MCPBridgePreferences.isConnected else { throw MCPBridgeError.notConnected }
        try MCPBridgePreferences.withDirectory { directory in
            try approveEpisodeInBundle(
                episode,
                seriesRequest: seriesRequest,
                context: context,
                directory: directory
            )
        }
    }

    static func approveEpisodeInBundle(
        _ episode: MCPBridgeChangeRequest,
        seriesRequest: MCPBridgeChangeRequest,
        context: ModelContext,
        directory: URL
    ) throws {
        guard episode.type == "createSeriesEpisode",
              seriesRequest.type == "createSeries",
              let seriesID = seriesRequest.payload.seriesId,
              episode.payload.seriesId == seriesID else {
            throw MCPBridgeError.invalidRequest("This episode is not attached to the proposed series.")
        }
        do {
            try context.save()
            try apply(seriesRequest, context: context)
            try apply(episode, context: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        try finish(
            episode,
            status: "approved",
            message: "Applied in agent.cy after individual episode approval.",
            context: context,
            directory: directory
        )
        try sync(context: context, directory: directory)
        WidgetSnapshotService.refresh(context: context)
    }

    static func reject(_ request: MCPBridgeChangeRequest, decisionNote: String? = nil) throws {
        guard MCPBridgePreferences.isConnected else { throw MCPBridgeError.notConnected }
        try MCPBridgePreferences.withDirectory { directory in
            try reject(request, decisionNote: decisionNote, directory: directory)
        }
    }

    static func reject(
        _ request: MCPBridgeChangeRequest,
        decisionNote: String? = nil,
        directory: URL
    ) throws {
        guard request.type == "createSeriesEpisode", let seriesID = request.payload.seriesId else {
            try finish(
                request,
                status: "rejected",
                message: "Declined in agent.cy.",
                decisionNote: decisionNote,
                directory: directory
            )
            return
        }
        var payload = request.payload
        payload.episodeReviewId = payload.episodeReviewId ?? UUID()
        if payload.episodeSlotId == nil {
            payload.proposedEpisodeSlotId = payload.proposedEpisodeSlotId ?? UUID()
        }
        payload.revisionNumber = payload.revisionNumber ?? 1
        let retainedRequest = request.replacingPayload(payload)
        let note = decisionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let record = MCPBridgeEpisodeRevisionRecord(
            schemaVersion: schemaVersion,
            episodeReviewId: payload.episodeReviewId ?? UUID(),
            workspaceId: request.workspaceId,
            seriesId: seriesID,
            episodeSlotId: payload.episodeSlotId ?? payload.proposedEpisodeSlotId,
            requestId: request.id,
            revisionNumber: payload.revisionNumber ?? 1,
            status: "needsRevision",
            decisionAt: Date(),
            decisionNote: note,
            request: retainedRequest
        )
        try writeEpisodeRevision(record, directory: directory)
        try finish(
            retainedRequest,
            status: "needsRevision",
            message: "Returned for revision in agent.cy.",
            decisionNote: note,
            directory: directory
        )
    }

    nonisolated static func episodeRevisions(directory: URL) throws -> [MCPBridgeEpisodeRevisionRecord] {
        let revisionsDirectory = directory.appending(path: "episode-revisions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: revisionsDirectory, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(
            at: revisionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .map { try decoder.decode(MCPBridgeEpisodeRevisionRecord.self, from: Data(contentsOf: $0)) }
        .sorted { $0.decisionAt < $1.decisionAt }
    }

    static func restorePremiseIfNotesWereCopied(_ brief: CreativeBrief) -> Bool {
        guard MCPBridgePreferences.isConnected else { return false }
        return (try? MCPBridgePreferences.withDirectory { directory in
            try restorePremiseIfNotesWereCopied(brief, directory: directory)
        }) ?? false
    }

    static func restorePremiseIfNotesWereCopied(
        _ brief: CreativeBrief,
        directory: URL
    ) throws -> Bool {
        let notes = brief.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty,
              brief.premise.trimmingCharacters(in: .whitespacesAndNewlines) == notes else {
            return false
        }
        let snapshotURL = directory.appending(path: "snapshot.json")
        let snapshot = try decoder.decode(
            MCPBridgeWorkspaceSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        guard let priorPremise = snapshot.posts.first(where: { $0.id == brief.id })?.premise
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !priorPremise.isEmpty,
              priorPremise != notes else {
            return false
        }
        brief.premise = priorPremise
        brief.updatedAt = Date()
        return true
    }

    static func makeSnapshot(
        context: ModelContext,
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID,
        notification: MCPBridgePushCapability? = MCPBridgePushPreferences.capability
    ) throws -> MCPBridgeWorkspaceSnapshot {
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let activeID = WorkspaceScope.activeWorkspaceID(preferredID: workspaceID, workspaces: workspaces)
        let activeWorkspace = activeID.flatMap { id in workspaces.first { $0.id == id } }
        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        let pillars = try context.fetch(FetchDescriptor<Pillar>()).filter {
            !$0.isArchived && WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>()).filter {
            !$0.isSkipped &&
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let series = try context.fetch(FetchDescriptor<ContentSeries>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let episodeSlots = try context.fetch(FetchDescriptor<SeriesEpisodeSlot>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let brandPartners = try context.fetch(FetchDescriptor<BrandPartner>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let destinations = try context.fetch(FetchDescriptor<PublishingDestination>())
        let formats = try context.fetch(FetchDescriptor<PublishingFormat>())
        let accounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>()).filter {
            !$0.isArchived &&
                WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        let attachments = try context.fetch(FetchDescriptor<CreatorAttachment>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }

        let identity = ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: activeID
        )
        let profile = profiles.first.map {
            MCPBridgeProfileSnapshot(id: $0.id, name: identity.name, goal: $0.goal)
        }
        let pillarSnapshots = pillars.map {
            MCPBridgePillarSnapshot(
                id: $0.id,
                parentPillarId: $0.parentPillarID,
                name: $0.name,
                colorHex: Self.sanitizedColorHex($0.colorHex),
                role: $0.role.rawValue,
                assignedWeekdays: $0.assignedWeekdays.map(\.rawValue).sorted()
            )
        }
        let taskSnapshots = tasks.map(MCPBridgeTaskSnapshot.init)
        let destinationByID = DuplicateSafeIndex.firstValues(destinations.map { ($0.id, $0) })
        let formatByID = DuplicateSafeIndex.firstValues(formats.map { ($0.id, $0) })
        let accountByID = DuplicateSafeIndex.firstValues(accounts.map { ($0.id, $0) })
        let accountSnapshots = accounts.map { account in
            let destination = destinationByID[account.destinationID]?.name ?? "Unknown destination"
            let cleanLabel = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return MCPBridgeSocialAccountSnapshot(
                id: account.id,
                destinationId: account.destinationID,
                destination: destination,
                label: cleanLabel.isEmpty ? "Unnamed account" : cleanLabel,
                isPrimary: account.isPrimary
            )
        }
        let postSnapshots = briefs.map { brief in
            let postOutputs = outputs.filter { $0.briefID == brief.id }
            let postTasks = tasks.filter { $0.briefID == brief.id }
            return MCPBridgePostSnapshot(
                id: brief.id,
                title: brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled post" : brief.title,
                premise: brief.premise,
                notes: brief.notes,
                status: brief.status.rawValue,
                pillarId: brief.pillarID,
                workDate: brief.workDate,
                includesWorkTime: brief.includesWorkTime,
                durationSeconds: brief.durationSeconds,
                hook: brief.spokenHook,
                firstFrameText: brief.firstFrameText,
                script: brief.scriptBeats,
                ending: brief.close,
                callToAction: brief.ctaIntent,
                createdAt: brief.createdAt,
                updatedAt: brief.updatedAt,
                markdown: PostMarkdownExporter.makeMarkdown(
                    brief: brief,
                    outputs: postOutputs,
                    tasks: postTasks,
                    pillar: pillars.first { $0.id == brief.pillarID },
                    destinations: destinations,
                    formats: formats,
                    socialAccounts: accounts,
                    attachments: attachments
                ),
                outputs: postOutputs.map { output in
                    MCPBridgeOutputSnapshot(
                        id: output.id,
                        platform: output.platform.rawValue,
                        destination: output.destinationID.flatMap { destinationByID[$0]?.name } ?? output.platform.title,
                        format: output.formatID.flatMap { formatByID[$0]?.name } ?? output.platform.shortTitle,
                        socialAccountId: output.socialAccountID,
                        account: output.socialAccountID.flatMap { accountByID[$0]?.label },
                        status: output.status.rawValue,
                        targetDate: output.targetDate,
                        includesTargetTime: output.includesTargetTime,
                        durationSeconds: output.durationSeconds,
                        title: output.titleOverride,
                        caption: output.caption,
                        openingAdjustment: output.openingAdjustment,
                        callToAction: output.cta,
                        editNotes: output.editChanges,
                        publishedUrl: output.publishedURLString
                    )
                },
                tasks: postTasks.map(MCPBridgeTaskSnapshot.init),
                seriesId: brief.seriesID,
                episodeNumber: brief.episodeNumber,
                episodeLabel: brief.episodeLabel.isEmpty ? nil : brief.episodeLabel
            )
        }
        let seriesSnapshots = series.map { item in
            MCPBridgeSeriesSnapshot(
                id: item.id,
                name: item.name,
                pillarId: item.pillarID,
                state: item.state.rawValue,
                defaultPlatform: item.defaultPlatform?.rawValue,
                defaultDestinationId: item.defaultDestinationID,
                defaultFormatId: item.defaultFormatID,
                defaultSocialAccountId: item.defaultSocialAccountID,
                defaultDurationSeconds: item.defaultDurationSeconds,
                cadence: item.cadence.rawValue,
                cadenceStartDate: item.cadenceStartDate,
                cadenceWeekdays: item.cadenceWeekdays.map(\.rawValue).sorted(),
                cadenceMonthDay: item.cadenceMonthDay,
                cadenceEndDate: item.cadenceEndDate,
                cadenceIncludesTime: item.cadenceIncludesTime,
                taskTemplate: item.taskTemplate.map { template in
                    MCPBridgeSeriesTaskTemplateSnapshot(
                        id: template.id,
                        title: template.title,
                        notes: template.notes,
                        kind: template.kind.rawValue,
                        priority: template.priority.rawValue,
                        estimatedMinutes: template.estimatedMinutes,
                        sortOrder: template.sortOrder
                    )
                }
            )
        }
        let episodeSlotSnapshots = episodeSlots.map { slot in
            MCPBridgeEpisodeSlotSnapshot(
                id: slot.id,
                seriesId: slot.seriesID,
                plannedDate: slot.plannedDate,
                includesTime: slot.includesTime,
                status: slot.status.rawValue,
                convertedPostId: slot.convertedBriefID
            )
        }
        let brandPartnerSnapshots = brandPartners.map { partner in
            MCPBridgeBrandPartnerSnapshot(
                id: partner.id,
                name: partner.name,
                type: partner.type.rawValue,
                stage: partner.stage.rawValue,
                website: partner.websiteURLString,
                socialHandle: partner.socialHandle,
                notes: partner.notes,
                nextFollowUpAt: partner.nextFollowUpAt,
                lastContactedAt: partner.lastContactedAt
            )
        }
        return MCPBridgeWorkspaceSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: Date(),
            workspaceId: activeID,
            workspaceName: activeWorkspace?.name,
            profile: profile,
            socialAccounts: accountSnapshots,
            pillars: pillarSnapshots,
            posts: postSnapshots,
            tasks: taskSnapshots,
            series: seriesSnapshots,
            episodeSlots: episodeSlotSnapshots,
            brandPartners: brandPartnerSnapshots,
            notification: notification
        )
    }

    static func apply(_ request: MCPBridgeChangeRequest, context: ModelContext) throws {
        guard request.schemaVersion == schemaVersion else {
            throw MCPBridgeError.invalidRequest("Unsupported schema version.")
        }
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        if let requestedWorkspaceID = request.workspaceId,
           requestedWorkspaceID != workspaceID {
            throw MCPBridgeError.actionNotAllowed("Switch to the account this proposal was created for before approving it.")
        }
        switch request.type {
        case "createIdea":
            let title = try requiredTitle(request.payload.title)
            let pillarID = try validatedPillarID(request.payload.pillarId, context: context, workspaceID: workspaceID, workspaces: workspaces)
            let brief = CreativeBrief(title: title, premise: "", source: .text, status: .spark)
            brief.workspaceID = workspaceID
            brief.ideaBankPlacement = .idea
            brief.notes = request.payload.notes ?? ""
            brief.pillarID = pillarID
            context.insert(brief)
        case "createPostDraft":
            let title = try requiredTitle(request.payload.title)
            let pillarID = try validatedPillarID(request.payload.pillarId, context: context, workspaceID: workspaceID, workspaces: workspaces)
            let brief = CreativeBrief(
                title: title,
                premise: request.payload.premise ?? "",
                source: .text,
                status: .spark
            )
            brief.workspaceID = workspaceID
            brief.ideaBankPlacement = .post
            brief.notes = request.payload.notes ?? ""
            brief.pillarID = pillarID
            brief.spokenHook = request.payload.hook ?? ""
            brief.ctaIntent = request.payload.callToAction ?? ""
            let platform = request.payload.platform.flatMap(CreatorPlatform.init(rawValue:)) ?? .instagramReels
            let identifiers = PublishingCatalog.identifiers(for: platform)
            let output = PlatformOutput(
                briefID: brief.id,
                platform: platform,
                destinationID: identifiers.destination,
                formatID: identifiers.format,
                status: .draft
            )
            output.workspaceID = workspaceID
            output.caption = request.payload.caption ?? ""
            output.cta = request.payload.callToAction ?? ""
            try applyRequestedFormat(request.payload.format, to: output, context: context)
            output.socialAccountID = try resolvedSocialAccountID(
                requestedID: request.payload.socialAccountId,
                existingID: nil,
                destinationID: output.destinationID,
                context: context,
                workspaceID: workspaceID,
                workspaces: workspaces
            )

            if let targetDate = request.payload.targetDate {
                try prepareForApprovedScheduling(brief)
                guard BriefLifecycle.schedule(output, for: targetDate, brief: brief) else {
                    throw MCPBridgeError.actionNotAllowed("This post could not be scheduled.")
                }
                output.includesTargetTime = request.payload.includesTargetTime ?? false
                brief.agendaDate = targetDate
                BriefLifecycle.synchronize(brief, outputs: [output])
            }

            // Insert only after every requested field and lifecycle transition
            // has validated so approval is atomic from the creator's perspective.
            context.insert(brief)
            context.insert(output)
        case "updatePost":
            guard let postID = request.payload.postId,
                  let brief = try fetchBrief(postID, context: context, workspaceID: workspaceID, workspaces: workspaces) else {
                throw MCPBridgeError.missingRecord("The post no longer exists.")
            }
            guard brief.status != .archived else {
                throw MCPBridgeError.actionNotAllowed("Archived posts cannot be changed from the CLI.")
            }
            if let title = request.payload.title { brief.title = try requiredTitle(title) }
            if let premise = request.payload.premise { brief.premise = premise }
            if let notes = request.payload.notes { brief.notes = notes }
            if let hook = request.payload.hook { brief.spokenHook = hook }
            if let callToAction = request.payload.callToAction { brief.ctaIntent = callToAction }
            if request.payload.clearWorkDate == true {
                brief.workDate = nil
                brief.includesWorkTime = false
            } else if let workDate = request.payload.workDate {
                brief.workDate = workDate
                brief.includesWorkTime = request.payload.includesWorkTime ?? false
            }
            if let pillarID = request.payload.pillarId {
                brief.pillarID = try validatedPillarID(pillarID, context: context, workspaceID: workspaceID, workspaces: workspaces)
            }
            if request.payload.caption != nil || request.payload.callToAction != nil || request.payload.format != nil || request.payload.socialAccountId != nil {
                let existingOutputs = try fetchOutputs(
                    postID,
                    context: context,
                    workspaceID: workspaceID,
                    workspaces: workspaces
                )
                let output = try selectedOutput(
                    requestedID: request.payload.outputId,
                    from: existingOutputs
                ) ?? {
                    let identifiers = PublishingCatalog.identifiers(for: .instagramReels)
                    let created = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .draft)
                    created.workspaceID = brief.workspaceID
                    created.destinationID = identifiers.destination
                    created.formatID = identifiers.format
                    context.insert(created)
                    return created
                }()
                if let caption = request.payload.caption { output.caption = caption }
                if let callToAction = request.payload.callToAction { output.cta = callToAction }
                try applyRequestedFormat(request.payload.format, to: output, context: context)
                if request.payload.socialAccountId != nil {
                    output.socialAccountID = try resolvedSocialAccountID(
                        requestedID: request.payload.socialAccountId,
                        existingID: output.socialAccountID,
                        destinationID: output.destinationID,
                        context: context,
                        workspaceID: workspaceID,
                        workspaces: workspaces
                    )
                }
            }
            brief.updatedAt = Date()
        case "schedulePost", "reschedulePost":
            guard let postID = request.payload.postId,
                  let targetDate = request.payload.targetDate,
                  let brief = try fetchBrief(postID, context: context, workspaceID: workspaceID, workspaces: workspaces) else {
                throw MCPBridgeError.missingRecord("The post or posting date is missing.")
            }
            if request.type == "reschedulePost",
               Calendar.current.startOfDay(for: targetDate) < Calendar.current.startOfDay(for: Date()) {
                throw MCPBridgeError.actionNotAllowed("Choose today or a future date when rescheduling a late post.")
            }
            let outputs = try fetchOutputs(postID, context: context, workspaceID: workspaceID, workspaces: workspaces)
            guard let output = try selectedOutput(requestedID: request.payload.outputId, from: outputs) else {
                throw MCPBridgeError.missingRecord("Add a platform to the post before scheduling it.")
            }
            output.socialAccountID = try resolvedSocialAccountID(
                requestedID: request.payload.socialAccountId,
                existingID: output.socialAccountID,
                destinationID: output.destinationID,
                context: context,
                workspaceID: workspaceID,
                workspaces: workspaces
            )
            try prepareForApprovedScheduling(brief)
            guard BriefLifecycle.schedule(output, for: targetDate, brief: brief) else {
                throw MCPBridgeError.actionNotAllowed("This post could not be scheduled.")
            }
            output.includesTargetTime = request.payload.includesTargetTime ?? true
            brief.agendaDate = targetDate
            BriefLifecycle.synchronize(brief, outputs: outputs)
            let postTasks = try context.fetch(FetchDescriptor<CreatorTask>())
            _ = PostTaskReschedulePolicy.alignOpenTasks(
                postTasks,
                to: output,
                on: brief.workDate ?? targetDate
            )
        case "markPostPosted":
            guard let postID = request.payload.postId,
                  let postedAt = request.payload.postedAt,
                  let brief = try fetchBrief(postID, context: context, workspaceID: workspaceID, workspaces: workspaces) else {
                throw MCPBridgeError.missingRecord("The post or posted date is missing.")
            }
            guard PostedDatePolicy.isValid(postedAt) else {
                throw MCPBridgeError.actionNotAllowed("A post cannot be marked live in the future.")
            }
            let outputs = try fetchOutputs(postID, context: context, workspaceID: workspaceID, workspaces: workspaces)
            guard let output = try selectedOutput(requestedID: request.payload.outputId, from: outputs) else {
                throw MCPBridgeError.missingRecord("Add a platform to the post before marking it posted.")
            }
            guard output.status != .posted else { return }
            guard BriefLifecycle.togglePosted(output, brief: brief, postedAt: postedAt) else {
                throw MCPBridgeError.actionNotAllowed("This post could not be marked as posted.")
            }
            BriefLifecycle.synchronize(brief, outputs: outputs)
        case "createSeries":
            let name = try requiredTitle(request.payload.name)
            let proposedSeriesID = request.payload.seriesId ?? UUID()
            guard let requestedPillarID = request.payload.pillarId else {
                throw MCPBridgeError.invalidRequest("Choose a pillar before approving this series.")
            }
            guard let pillarID = try validatedPillarID(
                requestedPillarID,
                context: context,
                workspaceID: workspaceID,
                workspaces: workspaces
            ) else {
                throw MCPBridgeError.invalidRequest("Choose a pillar before approving this series.")
            }
            if let existingSeries = try context.fetch(FetchDescriptor<ContentSeries>()).first(where: {
                $0.id == proposedSeriesID
            }) {
                guard existingSeries.name == name else {
                    throw MCPBridgeError.actionNotAllowed("This series identifier already belongs to a different series.")
                }
                guard existingSeries.pillarID == pillarID else {
                    throw MCPBridgeError.actionNotAllowed("This series identifier already belongs to a different pillar.")
                }
                return
            }
            let platform = request.payload.platform.flatMap(CreatorPlatform.init(rawValue:)) ?? .instagramReels
            let identifiers = PublishingCatalog.identifiers(for: platform)
            let socialAccountID = try resolvedSocialAccountID(
                requestedID: request.payload.socialAccountId,
                existingID: nil,
                destinationID: identifiers.destination,
                context: context,
                workspaceID: workspaceID,
                workspaces: workspaces
            )
            let series = ContentSeries(
                id: proposedSeriesID,
                workspaceID: workspaceID,
                name: name,
                pillarID: pillarID,
                platform: platform,
                destinationID: identifiers.destination,
                formatID: identifiers.format,
                socialAccountID: socialAccountID
            )
            series.cadence = request.payload.cadence.flatMap(PostRecurrenceFrequency.init(rawValue:)) ?? .none
            series.cadenceStartDate = request.payload.cadenceStartDate
            series.cadenceWeekdays = Set((request.payload.cadenceWeekdays ?? []).compactMap(PillarWeekday.init(rawValue:)))
            series.cadenceMonthDay = request.payload.cadenceMonthDay
            series.cadenceEndDate = request.payload.cadenceEndDate
            series.cadenceIncludesTime = request.payload.includesTargetTime ?? false
            context.insert(series)
        case "createSeriesEpisode":
            guard let seriesID = request.payload.seriesId,
                  let series = try context.fetch(FetchDescriptor<ContentSeries>()).first(where: {
                      $0.id == seriesID && $0.state != .archived && WorkspaceScope.includes(
                          $0.workspaceID,
                          activeWorkspaceID: workspaceID,
                          workspaces: workspaces
                      )
                  }) else {
                throw MCPBridgeError.missingRecord("The active series no longer exists.")
            }
            // An explicit pillar chosen during review repairs an older series
            // whose stored pillar was archived or removed. Episodes still
            // inherit one series pillar; the review override updates that
            // source of truth before the episode is created.
            guard let requestedPillarID = request.payload.pillarId ?? series.pillarID,
                  let inheritedPillarID = try validatedPillarID(
                      requestedPillarID,
                      context: context,
                      workspaceID: workspaceID,
                      workspaces: workspaces
                  ) else {
                throw MCPBridgeError.actionNotAllowed("Assign an active pillar to this series before approving an MCP episode.")
            }
            if request.payload.pillarId != nil, series.pillarID != inheritedPillarID {
                series.pillarID = inheritedPillarID
                series.updatedAt = Date()
            }
            let slot: SeriesEpisodeSlot
            let isNewSlot: Bool
            if let slotID = request.payload.episodeSlotId {
                guard let existingSlot = try context.fetch(FetchDescriptor<SeriesEpisodeSlot>()).first(where: {
                    $0.id == slotID && $0.seriesID == series.id && $0.status == .open
                }) else {
                    throw MCPBridgeError.missingRecord("The open episode slot no longer exists.")
                }
                slot = existingSlot
                isNewSlot = false
            } else {
                // The creator owns the work date, so an agent may legitimately
                // propose an episode with only a publish date. Fall back to it
                // for the planning slot rather than rejecting the proposal.
                guard let plannedDate = request.payload.workDate ?? request.payload.targetDate else {
                    throw MCPBridgeError.invalidRequest("A work date, a publish date, or an open episode slot is required.")
                }
                let plannedIncludesTime = request.payload.workDate != nil
                    ? (request.payload.includesWorkTime ?? false)
                    : (request.payload.includesTargetTime ?? false)
                let proposedSlotID = request.payload.proposedEpisodeSlotId ?? UUID()
                guard try !context.fetch(FetchDescriptor<SeriesEpisodeSlot>()).contains(where: {
                    $0.id == proposedSlotID
                }) else {
                    throw MCPBridgeError.actionNotAllowed("This episode version has already entered the series pipeline.")
                }
                slot = SeriesEpisodeSlot(
                    id: proposedSlotID,
                    workspaceID: workspaceID,
                    seriesID: series.id,
                    plannedDate: plannedDate,
                    includesTime: plannedIncludesTime
                )
                isNewSlot = true
            }
            let existingEpisodes = try context.fetch(FetchDescriptor<CreativeBrief>()).filter {
                $0.seriesID == series.id && $0.status != .archived
            }
            let episodeNumber = request.payload.episodeNumber
                ?? ((existingEpisodes.compactMap(\.episodeNumber).max() ?? 0) + 1)
            let title = try requiredTitle(request.payload.title)
            let brief = CreativeBrief(
                title: title,
                premise: request.payload.premise ?? "",
                source: .text,
                status: .spark
            )
            brief.workspaceID = workspaceID
            brief.ideaBankPlacement = .post
            brief.notes = request.payload.notes ?? ""
            brief.pillarID = inheritedPillarID
            brief.seriesID = series.id
            brief.episodeNumber = episodeNumber
            brief.episodeLabel = request.payload.episodeLabel ?? ""
            brief.workDate = slot.plannedDate
            brief.includesWorkTime = slot.includesTime
            brief.agendaDate = slot.plannedDate
            brief.spokenHook = request.payload.hook ?? ""
            brief.ctaIntent = request.payload.callToAction ?? ""
            if let duration = series.defaultDurationSeconds { brief.durationSeconds = duration }

            let platform = request.payload.platform.flatMap(CreatorPlatform.init(rawValue:))
                ?? series.defaultPlatform
                ?? .instagramReels
            let identifiers = PublishingCatalog.identifiers(for: platform)
            let seriesDestinationID = series.defaultDestinationID ?? series.defaultPlatform.map { PublishingCatalog.identifiers(for: $0).destination }
            let destinationID = request.payload.platform == nil ? series.defaultDestinationID ?? identifiers.destination : identifiers.destination
            let inheritedAccountID = destinationID == seriesDestinationID ? series.defaultSocialAccountID : nil
            let output = PlatformOutput(
                briefID: brief.id,
                platform: platform,
                destinationID: destinationID,
                formatID: destinationID == seriesDestinationID ? series.defaultFormatID ?? identifiers.format : identifiers.format,
                socialAccountID: inheritedAccountID,
                durationSeconds: series.defaultDurationSeconds ?? brief.durationSeconds,
                status: .draft
            )
            output.workspaceID = workspaceID
            output.seriesName = series.name
            output.caption = request.payload.caption ?? ""
            output.cta = request.payload.callToAction ?? ""
            try applyRequestedFormat(request.payload.format, to: output, context: context)
            output.socialAccountID = try resolvedSocialAccountID(
                requestedID: request.payload.socialAccountId,
                existingID: inheritedAccountID,
                destinationID: output.destinationID,
                context: context,
                workspaceID: workspaceID,
                workspaces: workspaces
            )

            if let targetDate = request.payload.targetDate {
                guard PostDatePlanPolicy.isChronologicallyValid(
                    workDate: slot.plannedDate,
                    scheduledDate: targetDate
                ) else {
                    throw MCPBridgeError.actionNotAllowed("The scheduled date cannot be before the episode work date.")
                }
                try prepareForApprovedScheduling(brief)
                guard BriefLifecycle.schedule(output, for: targetDate, brief: brief) else {
                    throw MCPBridgeError.actionNotAllowed("This episode could not be scheduled.")
                }
                output.includesTargetTime = request.payload.includesTargetTime ?? false
                brief.agendaDate = targetDate
                BriefLifecycle.synchronize(brief, outputs: [output])
            }

            if isNewSlot { context.insert(slot) }
            context.insert(brief)
            context.insert(output)
            for item in series.taskTemplate {
                let task = CreatorTask(
                    briefID: brief.id,
                    pillarID: brief.pillarID,
                    platformOutputID: output.id,
                    title: item.title,
                    kind: item.kind,
                    lane: .production,
                    priority: item.priority,
                    notes: item.notes,
                    estimatedMinutes: item.estimatedMinutes,
                    targetDate: slot.plannedDate,
                    includesTargetTime: slot.includesTime,
                    sortOrder: item.sortOrder
                )
                task.workspaceID = workspaceID
                context.insert(task)
            }
            slot.convertedBriefID = brief.id
            slot.status = .converted
        case "createBrandPartner":
            let name = try requiredTitle(request.payload.name)
            let partner = BrandPartner(
                workspaceID: workspaceID,
                name: name,
                type: request.payload.brandType.flatMap(BrandPartnerType.init(rawValue:)) ?? .brand,
                stage: request.payload.brandStage.flatMap(BrandPartnerStage.init(rawValue:)) ?? .wishlist
            )
            partner.websiteURLString = request.payload.website ?? ""
            partner.socialHandle = request.payload.socialHandle ?? ""
            partner.notes = request.payload.notes ?? ""
            partner.nextFollowUpAt = request.payload.nextFollowUpAt
            context.insert(partner)
            let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
            BrandPartnershipService.reconcileFollowUpTask(for: partner, tasks: tasks, context: context)
        case "updateBrandPartner":
            guard let partnerID = request.payload.brandPartnerId,
                  let partner = try context.fetch(FetchDescriptor<BrandPartner>()).first(where: {
                      $0.id == partnerID && WorkspaceScope.includes(
                          $0.workspaceID,
                          activeWorkspaceID: workspaceID,
                          workspaces: workspaces
                      )
                  }) else {
                throw MCPBridgeError.missingRecord("The brand partner no longer exists.")
            }
            if let name = request.payload.name { partner.name = try requiredTitle(name) }
            if let type = request.payload.brandType.flatMap(BrandPartnerType.init(rawValue:)) { partner.type = type }
            if let stage = request.payload.brandStage.flatMap(BrandPartnerStage.init(rawValue:)) { partner.stage = stage }
            if let website = request.payload.website { partner.websiteURLString = website }
            if let socialHandle = request.payload.socialHandle { partner.socialHandle = socialHandle }
            if let notes = request.payload.notes { partner.notes = notes }
            if request.payload.clearNextFollowUp == true {
                partner.nextFollowUpAt = nil
            } else if let followUp = request.payload.nextFollowUpAt {
                partner.nextFollowUpAt = followUp
            }
            partner.updatedAt = Date()
            let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
            BrandPartnershipService.reconcileFollowUpTask(for: partner, tasks: tasks, context: context)
        case "makeAnchorPillar":
            guard let pillarID = request.payload.pillarId,
                  let pillar = try context.fetch(FetchDescriptor<Pillar>()).first(where: {
                      $0.id == pillarID && !$0.isArchived && WorkspaceScope.includes(
                          $0.workspaceID,
                          activeWorkspaceID: workspaceID,
                          workspaces: workspaces
                      )
                  }) else {
                throw MCPBridgeError.missingRecord("The pillar no longer exists.")
            }
            let pillars = try context.fetch(FetchDescriptor<Pillar>()).filter {
                !$0.isArchived && WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: workspaceID,
                    workspaces: workspaces
                )
            }
            guard PillarAnchorPromotionService.promote(pillar, pillars: pillars) else {
                throw MCPBridgeError.actionNotAllowed("This pillar could not become the anchor.")
            }
        case "addTask":
            let title = try requiredTitle(request.payload.title)
            let postID = request.payload.postId
            let linkedBrief = try postID.flatMap {
                try fetchBrief($0, context: context, workspaceID: workspaceID, workspaces: workspaces)
            }
            if postID != nil, linkedBrief == nil {
                throw MCPBridgeError.missingRecord("The linked post no longer exists.")
            }
            let pillarID = try validatedPillarID(request.payload.pillarId, context: context, workspaceID: workspaceID, workspaces: workspaces)
            if let outputID = request.payload.outputId,
               try !context.fetch(FetchDescriptor<PlatformOutput>()).contains(where: {
                   $0.id == outputID && WorkspaceScope.includes(
                       $0.workspaceID,
                       activeWorkspaceID: workspaceID,
                       workspaces: workspaces
                   )
               }) {
                throw MCPBridgeError.missingRecord("The linked platform version no longer exists.")
            }
            let taskIncludesTime = request.payload.includesTargetTime ?? false
            let taskTargetDate = PostTaskReschedulePolicy.resolvedDueDate(
                requestedDate: request.payload.targetDate,
                includesTime: taskIncludesTime,
                briefID: postID,
                outputID: request.payload.outputId,
                workDate: linkedBrief?.workDate,
                outputs: try context.fetch(FetchDescriptor<PlatformOutput>())
            )
            let task = CreatorTask(
                briefID: postID,
                pillarID: pillarID,
                platformOutputID: request.payload.outputId,
                title: title,
                kind: request.payload.kind.flatMap(CreatorTaskKind.init(rawValue:)) ?? .planning,
                lane: request.payload.lane.flatMap(TaskLane.init(rawValue:)) ?? .production,
                priority: request.payload.priority.flatMap(TaskPriority.init(rawValue:)) ?? .none,
                notes: request.payload.notes ?? "",
                targetDate: taskTargetDate,
                includesTargetTime: taskIncludesTime
            )
            task.workspaceID = postID.flatMap { id in
                try? fetchBrief(id, context: context, workspaceID: workspaceID, workspaces: workspaces)?.workspaceID
            } ?? workspaceID
            context.insert(task)
        case "completeTask":
            guard let taskID = request.payload.taskId,
                  let task = try context.fetch(FetchDescriptor<CreatorTask>()).first(where: {
                      $0.id == taskID && WorkspaceScope.includes(
                          $0.workspaceID,
                          activeWorkspaceID: workspaceID,
                          workspaces: workspaces
                      )
                  }) else {
                throw MCPBridgeError.missingRecord("The task no longer exists.")
            }
            guard !task.isCompleted else { return }
            let brief = try task.briefID.flatMap {
                try fetchBrief($0, context: context, workspaceID: workspaceID, workspaces: workspaces)
            }
            _ = BriefLifecycle.toggleTask(task, brief: brief)
        default:
            throw MCPBridgeError.invalidRequest("Unknown change type \(request.type).")
        }
    }

    static func prepareForApprovedScheduling(_ brief: CreativeBrief) throws {
        guard brief.status != .archived else {
            throw MCPBridgeError.actionNotAllowed("Archived posts cannot be scheduled from the CLI.")
        }
        if brief.status == .spark || brief.status == .developing {
            BriefLifecycle.approve(brief)
        }
    }

    /// Moves exact legacy CLI note sections into the post fields they belong to.
    /// Only explicit all-caps FORMAT and CALL TO ACTION sections are touched.
    @discardableResult
    static func migrateStructuredPostFields(context: ModelContext) throws -> Bool {
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        var changed = false

        for brief in briefs {
            let parsed = StructuredPostNotes.parse(brief.notes)
            guard parsed.didExtractFields else { continue }
            let postOutputs = outputs.filter { $0.briefID == brief.id }

            if let callToAction = parsed.callToAction {
                if brief.ctaIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    brief.ctaIntent = callToAction
                    changed = true
                }
                for output in postOutputs where output.cta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output.cta = callToAction
                    changed = true
                }
            }

            if let format = parsed.format {
                for output in postOutputs where output.formatID == nil {
                    try applyRequestedFormat(format, to: output, context: context)
                    changed = true
                }
            }

            if brief.notes != parsed.notes {
                brief.notes = parsed.notes
                brief.updatedAt = Date()
                changed = true
            }
        }
        return changed
    }

    private static func finish(
        _ request: MCPBridgeChangeRequest,
        status: String,
        message: String,
        decisionNote: String? = nil,
        context: ModelContext? = nil,
        directory: URL
    ) throws {
        try prepare(directory: directory)
        let slotID = request.payload.episodeSlotId ?? request.payload.proposedEpisodeSlotId
        let resultPostID = try context.flatMap { context in
            try context.fetch(FetchDescriptor<SeriesEpisodeSlot>())
                .first(where: { $0.id == slotID })?
                .convertedBriefID
        }
        let receipt = MCPBridgeReceipt(
            schemaVersion: schemaVersion,
            requestId: request.id,
            processedAt: Date(),
            status: status,
            message: message,
            workspaceId: request.workspaceId,
            type: request.type,
            seriesId: request.payload.seriesId,
            episodeReviewId: request.payload.episodeReviewId,
            episodeSlotId: slotID,
            revisionNumber: request.payload.revisionNumber,
            decisionNote: decisionNote,
            resultPostId: resultPostID,
            nextAction: status == "needsRevision" ? "reviseSeriesEpisode" : "none"
        )
        try encoder.encode(receipt).write(
            to: directory.appending(path: "responses/\(request.id.uuidString.lowercased()).json"),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        if status == "approved", let reviewID = request.payload.episodeReviewId {
            try updateEpisodeRevision(
                reviewID: reviewID,
                status: "approved",
                request: request,
                directory: directory
            )
        }
        let requestsDirectory = directory.appending(path: "requests", directoryHint: .isDirectory)
        let matchingRequestURL = try? FileManager.default
            .contentsOfDirectory(at: requestsDirectory, includingPropertiesForKeys: nil)
            .first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased()
                    == request.id.uuidString.lowercased()
            })
        if let matchingRequestURL {
            try? FileManager.default.removeItem(at: matchingRequestURL)
        }
    }

    private static func writeEpisodeRevision(
        _ record: MCPBridgeEpisodeRevisionRecord,
        directory: URL
    ) throws {
        try prepare(directory: directory)
        try encoder.encode(record).write(
            to: directory.appending(
                path: "episode-revisions/\(record.episodeReviewId.uuidString.lowercased()).json"
            ),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    private static func updateEpisodeRevision(
        reviewID: UUID,
        status: String,
        request: MCPBridgeChangeRequest,
        directory: URL
    ) throws {
        guard var record = try episodeRevisions(directory: directory).first(where: {
            $0.episodeReviewId == reviewID
        }) else { return }
        record.status = status
        record.requestId = request.id
        record.revisionNumber = request.payload.revisionNumber ?? record.revisionNumber
        record.decisionAt = Date()
        record.request = request
        try writeEpisodeRevision(record, directory: directory)
    }

    nonisolated private static func prepare(directory: URL) throws {
        for folder in ["requests", "responses", "episode-revisions", "cy-requests", "cy-responses", "cy-processing"] {
            try FileManager.default.createDirectory(
                at: directory.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }

    private static func writeReadme(directory: URL) throws {
        let text = """
        # agent.cy MCP workspace

        This folder is the local bridge between agent.cy on iPhone and an MCP server on your computer.

        - `snapshot.json` is a read-only workspace snapshot written by the app.
        - `requests/` contains proposals waiting for approval in Cy.
        - `responses/` contains approval receipts for Claude or Codex.
        - `episode-revisions/` retains denied series episodes and their revision history until they re-enter the series.
        - `cy-requests/` and `cy-responses/` carry private Local Cy requests between this iPhone and your Mac.
        - `cy-runtime.json` reports whether the Local Cy worker is available.

        Do not edit these files directly. agent.cy validates every result and every queued change before using it.
        """
        try Data(text.utf8).write(
            to: directory.appending(path: "README.md"),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    private static func requiredTitle(_ value: String?) throws -> String {
        let title = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500 else {
            throw MCPBridgeError.invalidRequest("A title between 1 and 500 characters is required.")
        }
        return title
    }

    private static func validatedPillarID(
        _ value: UUID?,
        context: ModelContext,
        workspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) throws -> UUID? {
        guard let value else { return nil }
        guard try context.fetch(FetchDescriptor<Pillar>()).contains(where: {
            $0.id == value && !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            )
        }) else {
            throw MCPBridgeError.missingRecord("The selected pillar no longer exists.")
        }
        return value
    }

    private static func selectedOutput(
        requestedID: UUID?,
        from outputs: [PlatformOutput]
    ) throws -> PlatformOutput? {
        if let requestedID {
            guard let output = outputs.first(where: { $0.id == requestedID }) else {
                throw MCPBridgeError.missingRecord("The selected platform output no longer exists.")
            }
            return output
        }
        guard outputs.count <= 1 else {
            throw MCPBridgeError.actionNotAllowed(
                "This post has multiple platform outputs. Choose the output and account explicitly before approving it."
            )
        }
        return outputs.first
    }

    private static func resolvedSocialAccountID(
        requestedID: UUID?,
        existingID: UUID?,
        destinationID: UUID?,
        context: ModelContext,
        workspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) throws -> UUID? {
        guard let destinationID else {
            guard requestedID == nil, existingID == nil else {
                throw MCPBridgeError.actionNotAllowed(
                    "Choose a platform before choosing its social account."
                )
            }
            return nil
        }

        let matches = try context.fetch(FetchDescriptor<CreatorSocialAccount>()).filter {
            !$0.isArchived && $0.destinationID == destinationID && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            )
        }

        if let requestedID {
            guard matches.contains(where: { $0.id == requestedID }) else {
                throw MCPBridgeError.actionNotAllowed(
                    "The selected social account is not available for this platform in the active agent.cy workspace."
                )
            }
            return requestedID
        }

        if let existingID {
            guard matches.contains(where: { $0.id == existingID }) else {
                throw MCPBridgeError.actionNotAllowed(
                    "This post's social account is no longer available. Choose an active account before scheduling it."
                )
            }
            return existingID
        }

        if matches.count == 1 { return matches[0].id }
        guard matches.count < 2 else {
            throw MCPBridgeError.actionNotAllowed(
                "This platform has multiple social accounts. Choose the intended account explicitly before approving it."
            )
        }
        return nil
    }

    private static func applyRequestedFormat(
        _ requestedValue: String?,
        to output: PlatformOutput,
        context: ModelContext
    ) throws {
        guard let requestedValue = requestedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requestedValue.isEmpty else { return }
        let requested = requestedValue
            .components(separatedBy: "·")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? requestedValue.lowercased()
        let formats = try context.fetch(FetchDescriptor<PublishingFormat>()).filter { !$0.isArchived }
        let destinationFormats = output.destinationID.map { id in formats.filter { $0.destinationID == id } } ?? formats
        guard let format = destinationFormats.first(where: { candidate in
            let name = candidate.name.lowercased()
            return requested == name || requested.hasSuffix(" \(name)")
        }) else {
            throw MCPBridgeError.invalidRequest("The format \(requestedValue) is not available for this platform.")
        }
        output.formatID = format.id
        output.destinationID = format.destinationID
        if let legacy = PublishingCatalog.legacyPlatform(destinationID: format.destinationID, formatID: format.id) {
            output.platform = legacy
        }
        if let defaultDuration = format.kind.defaultDurationSeconds, output.durationSeconds <= 0 {
            output.durationSeconds = defaultDuration
        }
    }

    private static func fetchBrief(
        _ id: UUID,
        context: ModelContext,
        workspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) throws -> CreativeBrief? {
        try context.fetch(FetchDescriptor<CreativeBrief>()).first {
            $0.id == id && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            )
        }
    }

    private static func fetchOutputs(
        _ briefID: UUID,
        context: ModelContext,
        workspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) throws -> [PlatformOutput] {
        try context.fetch(FetchDescriptor<PlatformOutput>()).filter {
            $0.briefID == briefID && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: workspaceID,
                workspaces: workspaces
            )
        }
    }

    private static func sanitizedColorHex(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return cleaned.count == 6 ? cleaned.uppercased() : "55705B"
    }

    nonisolated private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }
}

struct StructuredPostNotes: Equatable {
    let notes: String
    let format: String?
    let callToAction: String?

    var didExtractFields: Bool { format != nil || callToAction != nil }

    static func parse(_ value: String) -> StructuredPostNotes {
        let lines = value.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let recognized = Set(["FORMAT", "STRUCTURE", "CALL TO ACTION", "STORIES"])
        var kept: [String] = []
        var format: String?
        var callToAction: String?
        var index = 0

        while index < lines.count {
            let heading = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard heading == "FORMAT" || heading == "CALL TO ACTION" else {
                kept.append(lines[index])
                index += 1
                continue
            }

            var end = index + 1
            while end < lines.count,
                  !recognized.contains(lines[end].trimmingCharacters(in: .whitespacesAndNewlines)) {
                end += 1
            }
            let content = lines[(index + 1)..<end]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                if heading == "FORMAT" { format = content }
                if heading == "CALL TO ACTION" { callToAction = content }
            }
            index = end
        }

        var compacted: [String] = []
        for line in kept {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               compacted.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                continue
            }
            compacted.append(line)
        }
        let cleaned = compacted
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return StructuredPostNotes(notes: cleaned, format: format, callToAction: callToAction)
    }
}
