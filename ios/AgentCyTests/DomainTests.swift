import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class DomainTests: XCTestCase {
    func testPostedStatusAndUnpostingRollback() throws {
        let brief = CreativeBrief(title: "Test", premise: "A premise", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .tiktok, status: .ready)
        BriefLifecycle.schedule(output, for: Date(), brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .scheduled)

        BriefLifecycle.togglePosted(output, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .posted)

        BriefLifecycle.togglePosted(output, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .scheduled)

        BriefLifecycle.schedule(output, for: nil, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .ready)
    }

    func testArchiveIsNotOverwrittenByDistributionSync() {
        let brief = CreativeBrief(title: "Archived", premise: "A premise", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .posted)
        BriefLifecycle.archive(brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .archived)
    }

    func testRecordingMilestoneOnlyFiresOnceForBriefFilmingTask() {
        let briefID = UUID()
        let brief = CreativeBrief(id: briefID, title: "Ready", premise: "A premise", status: .ready)
        let filming = CreatorTask(briefID: briefID, title: "Film", kind: .filming, isRecordingMilestoneDesignated: true)
        XCTAssertTrue(BriefLifecycle.toggleTask(filming, brief: brief))
        XCTAssertTrue(filming.recordingMilestoneEmitted)
        XCTAssertFalse(BriefLifecycle.toggleTask(filming, brief: brief))
        XCTAssertFalse(filming.isCompleted)
        XCTAssertFalse(BriefLifecycle.toggleTask(filming, brief: brief))

        let standalone = CreatorTask(title: "Film something", kind: .filming)
        XCTAssertFalse(BriefLifecycle.toggleTask(standalone))
    }

    func testExpiredAccessCanFinishButCannotCreate() {
        let state = SubscriptionState(access: .expired)
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: state))
        XCTAssertFalse(AccessPolicy.allows(.schedule, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        XCTAssertTrue(AccessPolicy.allows(.editExisting, state: state))
        XCTAssertTrue(AccessPolicy.allows(.updatePosting, state: state))
        XCTAssertTrue(AccessPolicy.allows(.export, state: state))
        XCTAssertTrue(AccessPolicy.allows(.erase, state: state))
    }

    func testConsumedFreeJourneyFailsClosedForNewWork() {
        let state = SubscriptionState(access: .freeJourney)
        state.freeBriefConsumed = true
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: state))
        XCTAssertFalse(AccessPolicy.allows(.createTask, state: state))
        XCTAssertFalse(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        XCTAssertFalse(AccessPolicy.allows(.schedule, state: state))
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: nil))
        XCTAssertTrue(AccessPolicy.allows(.revise, state: state))
        XCTAssertTrue(AccessPolicy.allows(.teachCy, state: state))
        state.revisionRequestsUsed = 3
        state.teachCyUpdatesUsed = 1
        XCTAssertFalse(AccessPolicy.allows(.revise, state: state))
        XCTAssertFalse(AccessPolicy.allows(.teachCy, state: state))
    }

    func testFreeAllowanceCounters() {
        let state = SubscriptionState(access: .freeJourney)
        XCTAssertTrue(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        state.ideationRequestsUsed = 3
        state.revisionRequestsUsed = 3
        state.teachCyUpdatesUsed = 1
        XCTAssertFalse(AccessPolicy.allows(.ideate, state: state))
        XCTAssertFalse(AccessPolicy.allows(.revise, state: state))
        XCTAssertFalse(AccessPolicy.allows(.teachCy, state: state))
        XCTAssertTrue(AccessPolicy.allows(.compose, state: state))
    }

    func testPaidAccessIncludesSparkDialogueAndGlobalAskCy() {
        let state = SubscriptionState(access: .paid)
        XCTAssertTrue(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertTrue(AccessPolicy.allows(.askCy, state: state))
    }

    func testPlanningSparkCreatesOneDatedTaskAndMovingItDoesNotDuplicate() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())
        let monday = Date(timeIntervalSince1970: 1_752_475_600)
        let tuesday = monday.addingTimeInterval(86_400)

        let brief = try XCTUnwrap(model.createSpark(
            text: "A clear idea for this week",
            source: .text,
            targetDate: monday,
            context: context
        ))
        XCTAssertEqual(model.tasks(for: brief, context: context).count, 1)
        XCTAssertEqual(model.tasks(for: brief, context: context).first?.targetDate, monday)

        XCTAssertTrue(model.plan(brief, on: tuesday, context: context))
        XCTAssertEqual(model.tasks(for: brief, context: context).count, 1)
        XCTAssertEqual(model.tasks(for: brief, context: context).first?.targetDate, tuesday)
    }

    func testAssistancePolicyControlsUnsolicitedPillarProposals() {
        XCTAssertEqual(AssistancePolicy(mode: .drive).pillarProposalLimit(explicitlyRequested: false), 0)
        XCTAssertEqual(AssistancePolicy(mode: .drive).pillarProposalLimit(explicitlyRequested: true), 3)
        XCTAssertEqual(AssistancePolicy(mode: .collaborate).pillarProposalLimit(explicitlyRequested: false), 1)
        XCTAssertEqual(AssistancePolicy(mode: .lead).pillarProposalLimit(explicitlyRequested: false), 3)
    }

    func testComposeStagesProposalUntilExplicitAcceptance() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Casey", goal: "Teach creators", selectedPlatforms: [.instagramReels, .tiktok], adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        context.insert(SubscriptionState())
        for index in 0..<3 { context.insert(VoiceExample(profileID: profile.id, text: "Example \(index) with a clear practical point.", sortOrder: index)) }
        let brief = CreativeBrief(title: "A rough spark", premise: "Make the first creative step smaller")
        context.insert(brief)
        let model = AppModel(reminderService: PreviewReminderService())

        await model.compose(brief: brief, context: context)

        XCTAssertNotNil(model.proposal(for: brief, context: context))
        XCTAssertTrue(brief.spokenHook.isEmpty)
        XCTAssertTrue(model.outputs(for: brief, context: context).isEmpty)
        XCTAssertTrue(model.tasks(for: brief, context: context).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).count == 1)
        XCTAssertTrue(try XCTUnwrap(model.subscriptionState(context)).freeBriefConsumed)

        let relaunchedModel = AppModel(reminderService: PreviewReminderService())
        let proposal = try XCTUnwrap(relaunchedModel.proposal(for: brief, context: context))
        relaunchedModel.acceptProposal(proposal, for: brief, context: context)
        XCTAssertFalse(brief.spokenHook.isEmpty)
        XCTAssertEqual(relaunchedModel.outputs(for: brief, context: context).count, 2)
        XCTAssertEqual(relaunchedModel.tasks(for: brief, context: context).count, 4)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
    }

    func testAcceptingRegenerationPreservesScheduledOutputAndCompletedTask() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Casey", goal: "Teach creators", selectedPlatforms: [.instagramReels], adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        let state = SubscriptionState(access: .paid)
        context.insert(state)
        let brief = CreativeBrief(title: "Keep this", premise: "A real premise", status: .developing)
        context.insert(brief)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.caption = "Accepted caption"
        output.targetDate = Date()
        context.insert(output)
        let task = CreatorTask(briefID: brief.id, title: "Completed filming", kind: .filming)
        task.isCompleted = true
        task.recordingMilestoneEmitted = true
        context.insert(task)
        let model = AppModel(reminderService: PreviewReminderService())

        await model.compose(brief: brief, context: context)
        let proposal = try XCTUnwrap(model.proposal(for: brief, context: context))
        model.acceptProposal(proposal, for: brief, context: context)

        XCTAssertEqual(model.outputs(for: brief, context: context).count, 1)
        XCTAssertEqual(output.caption, "Accepted caption")
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(task.recordingMilestoneEmitted)
    }

    func testDiscardClearsPersistedProposalAfterRelaunch() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Casey", goal: "Teach creators", selectedPlatforms: [.youtubeShorts], adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        context.insert(SubscriptionState(access: .paid))
        let brief = CreativeBrief(title: "Keep the spark", premise: "A useful starting point")
        context.insert(brief)
        let composingModel = AppModel(reminderService: PreviewReminderService())

        await composingModel.compose(brief: brief, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingBriefProposal>()).count, 1)

        let relaunchedModel = AppModel(reminderService: PreviewReminderService())
        XCTAssertNotNil(relaunchedModel.proposal(for: brief, context: context))
        relaunchedModel.discardProposal(for: brief, context: context)
        XCTAssertNil(relaunchedModel.proposal(for: brief, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
    }

    func testDevelopingBriefCannotSchedulePostOrCompleteLinkedTask() {
        let brief = CreativeBrief(title: "Not approved", premise: "A premise", status: .developing)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready)
        let task = CreatorTask(briefID: brief.id, title: "Film", kind: .filming, isRecordingMilestoneDesignated: true)

        XCTAssertFalse(BriefLifecycle.schedule(output, for: Date(), brief: brief))
        XCTAssertNil(output.targetDate)
        XCTAssertEqual(output.status, .ready)
        XCTAssertFalse(BriefLifecycle.togglePosted(output, brief: brief))
        XCTAssertNil(output.postedAt)
        XCTAssertFalse(BriefLifecycle.toggleTask(task, brief: brief))
        XCTAssertFalse(task.isCompleted)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .developing)

        let standalone = CreatorTask(title: "Update media kit", kind: .creatorBusiness)
        XCTAssertFalse(BriefLifecycle.toggleTask(standalone))
        XCTAssertTrue(standalone.isCompleted)
    }

    func testLifecycleHistoryRecordsTransitionsRollbackAndArchiveWithoutDuplicates() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let brief = CreativeBrief(title: "History", premise: "A premise", createdAt: start)
        let output = PlatformOutput(briefID: brief.id, platform: .tiktok, status: .ready)

        BriefLifecycle.beginDevelopment(brief, now: start.addingTimeInterval(10))
        BriefLifecycle.approve(brief, now: start.addingTimeInterval(20))
        _ = BriefLifecycle.schedule(output, for: start.addingTimeInterval(3_600), brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(30))
        _ = BriefLifecycle.togglePosted(output, brief: brief, now: start.addingTimeInterval(40))
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(40))
        _ = BriefLifecycle.togglePosted(output, brief: brief, now: start.addingTimeInterval(50))
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(50))
        _ = BriefLifecycle.schedule(output, for: nil, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(60))
        BriefLifecycle.archive(brief, now: start.addingTimeInterval(70))
        BriefLifecycle.archive(brief, now: start.addingTimeInterval(80))

        XCTAssertEqual(
            brief.lifecycleHistory.map(\.status),
            [.spark, .developing, .ready, .scheduled, .posted, .scheduled, .ready, .archived]
        )
        XCTAssertEqual(brief.lifecycleHistory.last?.date, start.addingTimeInterval(70))
    }

    func testPlatformOutputReplanMovesSimplifiesPausesAndArchivesCalmly() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let brief = CreativeBrief(title: "Replan", premise: "A premise", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = Date().addingTimeInterval(-3_600)
        context.insert(brief)
        context.insert(output)
        let model = AppModel(reminderService: PreviewReminderService())

        model.replan(output: output, choice: .simplify, context: context)
        XCTAssertTrue(output.editChanges.contains("Simplify to the essential cut"))
        model.replan(output: output, choice: .move, context: context)
        XCTAssertGreaterThan(output.targetDate ?? .distantPast, Date())
        XCTAssertEqual(brief.status, .scheduled)
        model.replan(output: output, choice: .pause, context: context)
        XCTAssertNil(output.targetDate)
        XCTAssertEqual(brief.status, .ready)
        model.replan(output: output, choice: .archive, context: context)
        XCTAssertEqual(brief.status, .archived)
        XCTAssertEqual(brief.lifecycleHistory.last?.status, .archived)
    }

    func testAssistanceModeControlsDevelopmentThreadOpener() throws {
        func messageTexts(for mode: AssistanceMode) throws -> [String] {
            let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
            let context = container.mainContext
            context.insert(CreatorProfile(name: "Ari", goal: "Teach", assistanceMode: mode))
            let brief = CreativeBrief(title: "A spark", premise: "A premise")
            context.insert(brief)
            let model = AppModel(reminderService: PreviewReminderService())
            let thread = model.developmentThread(for: brief, context: context)
            return model.messages(for: thread, context: context).map(\.text)
        }

        XCTAssertTrue(try messageTexts(for: .drive).isEmpty)
        let collaborate = try messageTexts(for: .collaborate)
        XCTAssertEqual(collaborate.count, 1)
        XCTAssertTrue(collaborate[0].contains("one point"))
        let lead = try messageTexts(for: .lead)
        XCTAssertEqual(lead.count, 1)
        XCTAssertTrue(lead[0].contains("Recommended first step"))
        XCTAssertTrue(lead[0].contains("Assumption"))
    }
}
