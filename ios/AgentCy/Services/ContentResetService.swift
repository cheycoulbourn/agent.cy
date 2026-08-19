import Foundation
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
            let inspirationSources = try context.fetch(FetchDescriptor<InspirationSource>()).filter(isActive)
            let inspirationTags = try context.fetch(FetchDescriptor<InspirationTag>()).filter(isActive)
            let activityRecords = try context.fetch(FetchDescriptor<AgentActivityRecord>()).filter(isActive)

            messages.filter { resetThreadIDs.contains($0.threadID) }.forEach(context.delete)
            resetThreads.forEach(context.delete)
            pendingBriefProposals.forEach(context.delete)
            pendingWeekProposals.forEach(context.delete)
            attachments.forEach(context.delete)
            outputs.forEach(context.delete)
            tasks.forEach(context.delete)
            briefs.forEach(context.delete)
            inspirationSources.forEach(context.delete)
            inspirationTags.forEach(context.delete)
            activityRecords.forEach(context.delete)
            try persistence.save(context: context)
#if !targetEnvironment(macCatalyst)
            try? VoiceSparkRecordingStore.clear(workspaceID: activeID)
#endif
        } catch {
            persistence.rollback(context: context)
            throw error
        }
    }
}

@MainActor
enum WorkspaceDeletionService {
    static func delete(workspaceID: UUID, context: ModelContext) throws {
        do {
            let threads = try context.fetch(FetchDescriptor<ConversationThread>())
                .filter { $0.workspaceID == workspaceID }
            let threadIDs = Set(threads.map(\.id))

            try context.fetch(FetchDescriptor<ConversationMessage>())
                .filter { threadIDs.contains($0.threadID) }
                .forEach(context.delete)
            try deleteScoped(PendingBriefProposal.self, workspaceID: workspaceID, context: context)
            try deleteScoped(PendingWeekProposal.self, workspaceID: workspaceID, context: context)
            try deleteScoped(CreatorAttachment.self, workspaceID: workspaceID, context: context)
            try deleteScoped(CreatorTask.self, workspaceID: workspaceID, context: context)
            try deleteScoped(BrandActivity.self, workspaceID: workspaceID, context: context)
            try deleteScoped(BrandContact.self, workspaceID: workspaceID, context: context)
            try deleteScoped(BrandPartner.self, workspaceID: workspaceID, context: context)
            try deleteScoped(PlatformOutput.self, workspaceID: workspaceID, context: context)
            try deleteScoped(CreativeBrief.self, workspaceID: workspaceID, context: context)
            try deleteScoped(InspirationSource.self, workspaceID: workspaceID, context: context)
            try deleteScoped(InspirationTag.self, workspaceID: workspaceID, context: context)
            try deleteScoped(Pillar.self, workspaceID: workspaceID, context: context)
            try deleteScoped(DailyFocusTemplateEntry.self, workspaceID: workspaceID, context: context)
            try deleteScoped(DailyFocusOverride.self, workspaceID: workspaceID, context: context)
            try deleteScoped(DailyFocusDayDetail.self, workspaceID: workspaceID, context: context)
            try deleteScoped(RhythmTemplate.self, workspaceID: workspaceID, context: context)
            try deleteScoped(WeekPlan.self, workspaceID: workspaceID, context: context)
            threads.forEach(context.delete)
            try deleteScoped(CreatorSocialAccount.self, workspaceID: workspaceID, context: context)
            try deleteScoped(AgentActivityRecord.self, workspaceID: workspaceID, context: context)

            if let workspace = try context.fetch(FetchDescriptor<CreatorWorkspace>())
                .first(where: { $0.id == workspaceID }) {
                context.delete(workspace)
            }
            try context.save()
#if !targetEnvironment(macCatalyst)
            try? VoiceSparkRecordingStore.clear(workspaceID: workspaceID)
#endif
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func deleteScoped<T: PersistentModel & WorkspaceScopedRecord>(
        _ type: T.Type,
        workspaceID: UUID,
        context: ModelContext
    ) throws {
        try context.fetch(FetchDescriptor<T>())
            .filter { $0.workspaceID == workspaceID }
            .forEach(context.delete)
    }
}
