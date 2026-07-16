import SwiftData

@MainActor
protocol ContentResetServicing {
    func reset(context: ModelContext) throws
}

@MainActor
protocol ContentResetPersisting {
    func save(context: ModelContext) throws
    func rollback(context: ModelContext)
}

@MainActor
struct SwiftDataContentResetPersistence: ContentResetPersisting {
    func save(context: ModelContext) throws {
        try context.save()
    }

    func rollback(context: ModelContext) {
        context.rollback()
    }
}

@MainActor
struct ContentResetService: ContentResetServicing {
    private let persistence: any ContentResetPersisting

    init(persistence: any ContentResetPersisting = SwiftDataContentResetPersistence()) {
        self.persistence = persistence
    }

    func reset(context: ModelContext) throws {
        do {
            let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
            let activeID = WorkspaceScope.activeWorkspaceID(
                preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
                workspaces: workspaces
            )
            func isActive<T: WorkspaceScopedRecord>(_ record: T) -> Bool {
                WorkspaceScope.includes(
                    record.workspaceID,
                    activeWorkspaceID: activeID,
                    workspaces: workspaces
                )
            }
            let resetThreads = try context.fetch(FetchDescriptor<ConversationThread>())
                .filter { thread in
                    isActive(thread) && (
                        thread.briefID != nil ||
                            thread.contextKind == .brief ||
                            thread.contextKind == .task ||
                            thread.contextKind == .day
                    )
                }
            let resetThreadIDs = Set(resetThreads.map(\.id))
            let messages = try context.fetch(FetchDescriptor<ConversationMessage>())
            let pendingBriefProposals = try context.fetch(FetchDescriptor<PendingBriefProposal>()).filter(isActive)
            let pendingWeekProposals = try context.fetch(FetchDescriptor<PendingWeekProposal>()).filter(isActive)
            let attachments = try context.fetch(FetchDescriptor<CreatorAttachment>()).filter(isActive)
            let outputs = try context.fetch(FetchDescriptor<PlatformOutput>()).filter(isActive)
            let tasks = try context.fetch(FetchDescriptor<CreatorTask>()).filter(isActive)
            let briefs = try context.fetch(FetchDescriptor<CreativeBrief>()).filter(isActive)

            messages.filter { resetThreadIDs.contains($0.threadID) }.forEach(context.delete)
            resetThreads.forEach(context.delete)
            pendingBriefProposals.forEach(context.delete)
            pendingWeekProposals.forEach(context.delete)
            attachments.forEach(context.delete)
            outputs.forEach(context.delete)
            tasks.forEach(context.delete)
            briefs.forEach(context.delete)
            try persistence.save(context: context)
        } catch {
            persistence.rollback(context: context)
            throw error
        }
    }
}
