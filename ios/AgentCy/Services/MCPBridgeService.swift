import Foundation
import SwiftData

enum MCPBridgeError: LocalizedError {
    case notConnected
    case inaccessibleFolder
    case invalidRequest(String)
    case missingRecord(String)
    case actionNotAllowed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Choose the agent.cy MCP folder first."
        case .inaccessibleFolder: "The selected Files folder is no longer available. Choose it again."
        case .invalidRequest: "The proposal could not be read. Ask Claude or Codex to prepare it again."
        case .missingRecord(let message): message
        case .actionNotAllowed(let message): message
        }
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
        let bookmark = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
            options: [.withoutUI],
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

struct MCPBridgeConnectionStatus: Codable, Equatable {
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
        case id, platform, destination, format, account, status, targetDate
        case includesTargetTime, durationSeconds, title, caption, openingAdjustment
        case callToAction, editNotes, publishedUrl
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(platform, forKey: .platform)
        try container.encode(destination, forKey: .destination)
        try container.encode(format, forKey: .format)
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

    private enum CodingKeys: String, CodingKey {
        case id, title, premise, notes, status, pillarId, workDate, includesWorkTime
        case durationSeconds, hook
        case firstFrameText, script, ending, callToAction, createdAt, updatedAt
        case markdown, outputs, tasks
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
    }
}

struct MCPBridgeWorkspaceSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let workspaceId: UUID?
    let workspaceName: String?
    let profile: MCPBridgeProfileSnapshot?
    let pillars: [MCPBridgePillarSnapshot]
    let posts: [MCPBridgePostSnapshot]
    let tasks: [MCPBridgeTaskSnapshot]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, workspaceId, workspaceName, profile, pillars, posts, tasks
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeOptional(workspaceId, forKey: .workspaceId)
        try container.encodeOptional(workspaceName, forKey: .workspaceName)
        try container.encodeOptional(profile, forKey: .profile)
        try container.encode(pillars, forKey: .pillars)
        try container.encode(posts, forKey: .posts)
        try container.encode(tasks, forKey: .tasks)
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

struct MCPBridgeRequestPayload: Codable {
    var title: String?
    var premise: String?
    var notes: String?
    var pillarId: UUID?
    var platform: String?
    var format: String?
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
}

struct MCPBridgeChangeRequest: Codable, Identifiable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let source: String
    let workspaceId: UUID?
    let type: String
    let payload: MCPBridgeRequestPayload

    var title: String {
        switch type {
        case "createIdea": "Save an idea"
        case "createPostDraft": payload.targetDate == nil ? "Create a post draft" : "Create and schedule a post"
        case "updatePost": "Update a post"
        case "schedulePost": "Schedule a post"
        case "addTask": "Add a task"
        case "completeTask": "Complete a task"
        default: "Proposal"
        }
    }

    var summary: String {
        payload.title ?? payload.postId?.uuidString ?? payload.taskId?.uuidString ?? "Review the requested change."
    }

    func replacingPayload(_ payload: MCPBridgeRequestPayload) -> MCPBridgeChangeRequest {
        MCPBridgeChangeRequest(
            schemaVersion: schemaVersion,
            id: id,
            createdAt: createdAt,
            source: source,
            workspaceId: workspaceId,
            type: type,
            payload: payload
        )
    }
}

private struct MCPBridgeReceipt: Codable {
    let schemaVersion: Int
    let requestId: UUID
    let processedAt: Date
    let status: String
    let message: String
}

@MainActor
enum MCPBridgeService {
    static func connectionStatus() throws -> MCPBridgeConnectionStatus? {
        guard MCPBridgePreferences.isConnected else { return nil }
        return try MCPBridgePreferences.withDirectory { directory in
            let url = directory.appending(path: "bridge-status.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MCPBridgeConnectionStatus.self, from: Data(contentsOf: url))
        }
    }

    static let schemaVersion = 1

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
        let snapshot = try makeSnapshot(context: context, workspaceID: workspaceID)
        try prepare(directory: directory)
        try encoder.encode(snapshot).write(
            to: directory.appending(path: "snapshot.json"),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        try writeReadme(directory: directory)
        UserDefaults.standard.set(Date(), forKey: MCPBridgePreferences.lastSyncKey)
    }

    static func pendingRequests(
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
    ) throws -> [MCPBridgeChangeRequest] {
        guard MCPBridgePreferences.isConnected else { return [] }
        return try MCPBridgePreferences.withDirectory { directory in
            try pendingRequests(directory: directory, workspaceID: workspaceID)
        }
    }

    static func pendingRequests(
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

        return try requestURLs.map { url in
            do {
                let data = try Data(contentsOf: url)
                let request = try decoder.decode(MCPBridgeChangeRequest.self, from: data)
                guard request.schemaVersion == schemaVersion else {
                    throw MCPBridgeError.invalidRequest("Unsupported schema version in \(url.lastPathComponent).")
                }
                return request
            } catch let error as MCPBridgeError {
                throw error
            } catch {
                throw MCPBridgeError.invalidRequest(
                    "Could not read \(url.lastPathComponent). The review queue was left unchanged."
                )
            }
        }
        .filter { request in
            guard let requestWorkspaceID = request.workspaceId else { return true }
            return requestWorkspaceID == workspaceID
        }
        .sorted { $0.createdAt < $1.createdAt }
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
        do {
            // Establish a clean rollback boundary so an invalid proposal cannot
            // leave partially mutated or inserted models in the live context.
            try context.save()
            try apply(request, context: context)
            try context.save()
            try finish(request, status: "approved", message: "Applied in agent.cy.")
            try sync(context: context)
            WidgetSnapshotService.refresh(context: context)
        } catch {
            context.rollback()
            try? finish(request, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    static func reject(_ request: MCPBridgeChangeRequest) throws {
        try finish(request, status: "rejected", message: "Declined in agent.cy.")
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
        workspaceID: UUID? = CreatorWorkspacePreferences.activeWorkspaceID
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
        let destinations = try context.fetch(FetchDescriptor<PublishingDestination>())
        let formats = try context.fetch(FetchDescriptor<PublishingFormat>())
        let accounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>()).filter {
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
        let destinationByID = Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0) })
        let formatByID = Dictionary(uniqueKeysWithValues: formats.map { ($0.id, $0) })
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
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
                tasks: postTasks.map(MCPBridgeTaskSnapshot.init)
            )
        }
        return MCPBridgeWorkspaceSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: Date(),
            workspaceId: activeID,
            workspaceName: activeWorkspace?.name,
            profile: profile,
            pillars: pillarSnapshots,
            posts: postSnapshots,
            tasks: taskSnapshots
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
            if let pillarID = request.payload.pillarId {
                brief.pillarID = try validatedPillarID(pillarID, context: context, workspaceID: workspaceID, workspaces: workspaces)
            }
            if request.payload.caption != nil || request.payload.callToAction != nil || request.payload.format != nil {
                let output = try fetchOutputs(postID, context: context, workspaceID: workspaceID, workspaces: workspaces).first ?? {
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
            }
            brief.updatedAt = Date()
        case "schedulePost":
            guard let postID = request.payload.postId,
                  let targetDate = request.payload.targetDate,
                  let brief = try fetchBrief(postID, context: context, workspaceID: workspaceID, workspaces: workspaces) else {
                throw MCPBridgeError.missingRecord("The post or posting date is missing.")
            }
            let outputs = try fetchOutputs(postID, context: context, workspaceID: workspaceID, workspaces: workspaces)
            guard let output = request.payload.outputId.flatMap({ id in outputs.first { $0.id == id } }) ?? outputs.first else {
                throw MCPBridgeError.missingRecord("Add a platform to the post before scheduling it.")
            }
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
                on: targetDate
            )
        case "addTask":
            let title = try requiredTitle(request.payload.title)
            let postID = request.payload.postId
            if let postID, try fetchBrief(postID, context: context, workspaceID: workspaceID, workspaces: workspaces) == nil {
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

    private static func finish(_ request: MCPBridgeChangeRequest, status: String, message: String) throws {
        try MCPBridgePreferences.withDirectory { directory in
            try prepare(directory: directory)
            let receipt = MCPBridgeReceipt(
                schemaVersion: schemaVersion,
                requestId: request.id,
                processedAt: Date(),
                status: status,
                message: message
            )
            try encoder.encode(receipt).write(
                to: directory.appending(path: "responses/\(request.id.uuidString.lowercased()).json"),
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
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
    }

    private static func prepare(directory: URL) throws {
        for folder in ["requests", "responses", "cy-requests", "cy-responses", "cy-processing"] {
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

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
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
