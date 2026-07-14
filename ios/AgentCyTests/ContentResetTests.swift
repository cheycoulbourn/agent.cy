import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class ContentResetTests: XCTestCase {
    func testServiceRemovesPostsAndTasksWhileKeepingCreatorFoundation() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Create", adultConfirmed: true, onboardingCompleted: true)
        let pillar = Pillar(name: "Lifestyle", colorHex: "#5F7D68")
        let brief = CreativeBrief(title: "A post", premise: "Draft")
        let output = PlatformOutput(briefID: brief.id)
        let destination = PublishingDestination(name: "Instagram")
        let globalThread = ConversationThread(contextKind: .none, title: "Cy")
        let pillarThread = ConversationThread(contextKind: .pillar, contextID: pillar.id, title: "Pillar ideas")
        let briefThread = ConversationThread(briefID: brief.id, contextKind: .brief, contextID: brief.id, title: "Post chat")
        let linkedThread = ConversationThread(briefID: brief.id, contextKind: .none, title: "Linked post chat")
        let taskThread = ConversationThread(contextKind: .task, title: "Task chat")
        let dayThread = ConversationThread(contextKind: .day, title: "Day chat")

        context.insert(profile)
        context.insert(pillar)
        context.insert(brief)
        context.insert(output)
        context.insert(destination)
        context.insert(CreatorTask(briefID: brief.id, pillarID: pillar.id, platformOutputID: output.id, title: "Film"))
        context.insert(PendingBriefProposal(briefID: brief.id, payloadJSON: "{}"))
        context.insert(PendingWeekProposal(weekStart: Date(), payloadJSON: "{}", sourceFingerprint: "test"))
        context.insert(CreatorAttachment(ownerKind: .postMedia, briefID: brief.id, platformOutputID: output.id, fileName: "still.jpg", kind: .photo, uniformTypeIdentifier: "public.jpeg", byteCount: 1, localRelativePath: ""))
        context.insert(globalThread)
        context.insert(pillarThread)
        context.insert(briefThread)
        context.insert(linkedThread)
        context.insert(taskThread)
        context.insert(dayThread)
        context.insert(ConversationMessage(threadID: globalThread.id, role: .creator, text: "Keep this"))
        context.insert(ConversationMessage(threadID: pillarThread.id, role: .cy, text: "Keep this too"))
        context.insert(ConversationMessage(threadID: briefThread.id, role: .creator, text: "Remove this"))
        context.insert(ConversationMessage(threadID: linkedThread.id, role: .creator, text: "Remove linked chat"))
        context.insert(ConversationMessage(threadID: taskThread.id, role: .creator, text: "Remove task chat"))
        context.insert(ConversationMessage(threadID: dayThread.id, role: .creator, text: "Remove day chat"))
        context.insert(ReminderSettings(dailyEnabled: true))
        context.insert(SubscriptionState(access: .comped))
        try context.save()

        try ContentResetService().reset(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingWeekProposal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorAttachment>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).map(\.id), [profile.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pillar>()).map(\.id), [pillar.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PublishingDestination>()).map(\.id), [destination.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderSettings>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SubscriptionState>()).count, 1)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<ConversationThread>()).map(\.id)),
            Set([globalThread.id, pillarThread.id])
        )
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<ConversationMessage>()).map(\.text)),
            Set(["Keep this", "Keep this too"])
        )
    }

    func testServiceRollsBackEveryDeletionWhenPersistenceFails() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Create", adultConfirmed: true, onboardingCompleted: true)
        let pillar = Pillar(name: "Lifestyle", colorHex: "#5F7D68")
        let brief = CreativeBrief(title: "A post", premise: "Draft")
        let output = PlatformOutput(briefID: brief.id)
        let thread = ConversationThread(briefID: brief.id, contextKind: .brief, contextID: brief.id, title: "Post chat")
        let message = ConversationMessage(threadID: thread.id, role: .creator, text: "Keep after rollback")

        context.insert(profile)
        context.insert(pillar)
        context.insert(brief)
        context.insert(output)
        context.insert(CreatorTask(briefID: brief.id, pillarID: pillar.id, platformOutputID: output.id, title: "Film"))
        context.insert(PendingBriefProposal(briefID: brief.id, payloadJSON: "{}"))
        context.insert(PendingWeekProposal(weekStart: Date(), payloadJSON: "{}", sourceFingerprint: "test"))
        context.insert(CreatorAttachment(ownerKind: .postMedia, briefID: brief.id, platformOutputID: output.id, fileName: "still.jpg", kind: .photo, uniformTypeIdentifier: "public.jpeg", byteCount: 1, localRelativePath: ""))
        context.insert(thread)
        context.insert(message)
        try context.save()

        let persistence = FailingContentResetPersistence()
        let service = ContentResetService(persistence: persistence)

        XCTAssertThrowsError(try service.reset(context: context)) { error in
            XCTAssertEqual(error as? ContentResetTestError, .saveFailed)
        }
        XCTAssertTrue(persistence.didRollback)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).map(\.id), [brief.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlatformOutput>()).map(\.id), [output.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingBriefProposal>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingWeekProposal>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorAttachment>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationThread>()).map(\.id), [thread.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationMessage>()).map(\.id), [message.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).map(\.id), [profile.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pillar>()).map(\.id), [pillar.id])
    }

    func testResetRemovesPostsAndTasksWhileKeepingPillarsAndCreatorSetup() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Create", adultConfirmed: true, onboardingCompleted: true)
        let pillar = Pillar(name: "Lifestyle", colorHex: "#5F7D68")
        let brief = CreativeBrief(title: "A post", premise: "Draft")
        let output = PlatformOutput(briefID: brief.id)
        let destination = PublishingDestination(name: "Instagram")
        let globalThread = ConversationThread(contextKind: .none, title: "Cy")
        let pillarThread = ConversationThread(contextKind: .pillar, contextID: pillar.id, title: "Pillar ideas")
        let briefThread = ConversationThread(briefID: brief.id, contextKind: .brief, contextID: brief.id, title: "Post chat")

        context.insert(profile)
        context.insert(pillar)
        context.insert(brief)
        context.insert(output)
        context.insert(destination)
        context.insert(CreatorTask(briefID: brief.id, pillarID: pillar.id, platformOutputID: output.id, title: "Film"))
        context.insert(PendingBriefProposal(briefID: brief.id, payloadJSON: "{}"))
        context.insert(PendingWeekProposal(weekStart: Date(), payloadJSON: "{}", sourceFingerprint: "test"))
        context.insert(CreatorAttachment(ownerKind: .postMedia, briefID: brief.id, platformOutputID: output.id, fileName: "still.jpg", kind: .photo, uniformTypeIdentifier: "public.jpeg", byteCount: 1, localRelativePath: ""))
        context.insert(globalThread)
        context.insert(pillarThread)
        context.insert(briefThread)
        context.insert(ConversationMessage(threadID: globalThread.id, role: .creator, text: "Keep this"))
        context.insert(ConversationMessage(threadID: pillarThread.id, role: .cy, text: "Keep this too"))
        context.insert(ConversationMessage(threadID: briefThread.id, role: .creator, text: "Remove this"))
        context.insert(ReminderSettings(dailyEnabled: true))
        context.insert(SubscriptionState(access: .comped))
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.resetPostsAndTasks(context: context))

        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingWeekProposal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorAttachment>()).isEmpty)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).map(\.id), [profile.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pillar>()).map(\.id), [pillar.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PublishingDestination>()).map(\.id), [destination.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderSettings>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SubscriptionState>()).count, 1)

        let remainingThreads = try context.fetch(FetchDescriptor<ConversationThread>())
        XCTAssertEqual(Set(remainingThreads.map(\.id)), Set([globalThread.id, pillarThread.id]))
        let remainingMessages = try context.fetch(FetchDescriptor<ConversationMessage>())
        XCTAssertEqual(Set(remainingMessages.map(\.text)), Set(["Keep this", "Keep this too"]))
    }
}

private enum ContentResetTestError: Error {
    case saveFailed
}

@MainActor
private final class FailingContentResetPersistence: ContentResetPersisting {
    private(set) var didRollback = false

    func save(context: ModelContext) throws {
        throw ContentResetTestError.saveFailed
    }

    func rollback(context: ModelContext) {
        didRollback = true
        context.rollback()
    }
}
