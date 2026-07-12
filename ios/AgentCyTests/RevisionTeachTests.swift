import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class RevisionTeachTests: XCTestCase {
    func testRevisionStagesWithoutMutationAndRehydratesAfterRelaunch() async throws {
        let fixture = makeFixture(access: .freeJourney)
        let originalTitle = fixture.brief.title

        await fixture.model.requestRevision(
            for: fixture.brief,
            scope: .title,
            instruction: "Make the title more concrete.",
            context: fixture.context
        )

        XCTAssertEqual(fixture.brief.title, originalTitle)
        XCTAssertEqual(fixture.state.revisionRequestsUsed, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<PendingBriefProposal>()).filter { $0.proposalKindRaw == "revision" }.count, 1)
        let relaunched = AppModel(reminderService: PreviewReminderService())
        XCTAssertEqual(relaunched.revisionProposal(for: fixture.brief, context: fixture.context)?.requestedScope, .title)
    }

    func testThirdFreeRevisionWorksAndFourthIsBlockedWithoutRefundOnDiscard() async throws {
        let fixture = makeFixture(access: .freeJourney)
        fixture.state.revisionRequestsUsed = 2

        await fixture.model.requestRevision(for: fixture.brief, scope: .spokenHook, instruction: "Shorten it.", context: fixture.context)
        XCTAssertEqual(fixture.state.revisionRequestsUsed, 3)
        XCTAssertNotNil(fixture.model.revisionProposal(for: fixture.brief, context: fixture.context))

        fixture.model.discardRevision(for: fixture.brief, context: fixture.context)
        XCTAssertEqual(fixture.state.revisionRequestsUsed, 3)
        await fixture.model.requestRevision(for: fixture.brief, scope: .close, instruction: "Make it calmer.", context: fixture.context)
        XCTAssertNil(fixture.model.revisionProposal(for: fixture.brief, context: fixture.context))
        XCTAssertEqual(fixture.state.revisionRequestsUsed, 3)
    }

    func testRevisionAcceptancePreservesPostingLifecycleAndCompletedTaskHistory() async throws {
        let fixture = makeFixture(access: .paid, status: .posted)
        fixture.output.status = .posted
        fixture.output.targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        fixture.output.postedAt = Date(timeIntervalSince1970: 1_800_000_100)
        fixture.task.isCompleted = true
        fixture.task.completedAt = Date(timeIntervalSince1970: 1_799_999_000)
        fixture.task.recordingMilestoneEmitted = true
        let outputID = fixture.output.id
        let target = fixture.output.targetDate
        let posted = fixture.output.postedAt
        let taskID = fixture.task.id
        let completedAt = fixture.task.completedAt

        await fixture.model.requestRevision(for: fixture.brief, scope: .wholeBrief, instruction: "Make it more grounded.", context: fixture.context)
        let revision = try XCTUnwrap(fixture.model.revisionProposal(for: fixture.brief, context: fixture.context))
        fixture.model.acceptRevision(revision, for: fixture.brief, context: fixture.context)

        XCTAssertEqual(fixture.brief.status, .posted)
        XCTAssertEqual(fixture.output.id, outputID)
        XCTAssertEqual(fixture.output.status, .posted)
        XCTAssertEqual(fixture.output.targetDate, target)
        XCTAssertEqual(fixture.output.postedAt, posted)
        let tasks = fixture.model.tasks(for: fixture.brief, context: fixture.context)
        let preserved = try XCTUnwrap(tasks.first(where: { $0.id == taskID }))
        XCTAssertTrue(preserved.isCompleted)
        XCTAssertEqual(preserved.completedAt, completedAt)
        XCTAssertTrue(preserved.recordingMilestoneEmitted)
        XCTAssertEqual(tasks.filter { $0.id == taskID }.count, 1)
        XCTAssertFalse(fixture.brief.readyBriefPayloadJSON.isEmpty)
    }

    func testStaleRevisionProposalIsRejected() async throws {
        let fixture = makeFixture(access: .paid)
        let originalTitle = fixture.brief.title
        await fixture.model.requestRevision(for: fixture.brief, scope: .title, instruction: "Make it specific.", context: fixture.context)
        let revision = try XCTUnwrap(fixture.model.revisionProposal(for: fixture.brief, context: fixture.context))
        fixture.brief.updatedAt = revision.sourceUpdatedAt.addingTimeInterval(1)

        fixture.model.acceptRevision(revision, for: fixture.brief, context: fixture.context)

        XCTAssertEqual(fixture.brief.title, originalTitle)
        XCTAssertNotNil(fixture.model.revisionProposal(for: fixture.brief, context: fixture.context))
    }

    func testTeachCyStagesPersistsAndDiscardDoesNotRefund() async throws {
        let fixture = makeFixture(access: .freeJourney)
        let originalSummary = fixture.voice.summary

        await fixture.model.requestTeachCy(instruction: "Keep openings shorter.", context: fixture.context)

        XCTAssertEqual(fixture.voice.summary, originalSummary)
        XCTAssertEqual(fixture.state.teachCyUpdatesUsed, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).count, 1)
        let relaunched = AppModel(reminderService: PreviewReminderService())
        XCTAssertNotNil(relaunched.voiceProfileProposal(context: fixture.context))

        fixture.model.discardVoiceProfileChange(context: fixture.context)
        XCTAssertEqual(fixture.state.teachCyUpdatesUsed, 1)
        await fixture.model.requestTeachCy(instruction: "Use fewer adjectives.", context: fixture.context)
        XCTAssertNil(fixture.model.voiceProfileProposal(context: fixture.context))
    }

    func testTeachCyAcceptanceCreatesNewApprovedVersionAndLeavesExamples() async throws {
        let fixture = makeFixture(access: .paid)
        let exampleIDs = try fixture.context.fetch(FetchDescriptor<VoiceExample>()).map(\.id)

        await fixture.model.requestTeachCy(instruction: "Use one concrete example before advice.", context: fixture.context)
        let proposal = try XCTUnwrap(fixture.model.voiceProfileProposal(context: fixture.context))
        fixture.model.acceptVoiceProfileChange(proposal, context: fixture.context)

        let profiles = try fixture.context.fetch(FetchDescriptor<VoiceProfile>()).filter { $0.profileID == fixture.profile.id }
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.filter(\.isApproved).count, 1)
        let approved = try XCTUnwrap(profiles.first(where: \.isApproved))
        XCTAssertEqual(approved.version, 2)
        XCTAssertFalse(approved.canonicalPayloadJSON.isEmpty)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<VoiceExample>()).map(\.id), exampleIDs)
    }

    func testStaleVoiceProposalIsRejectedWithoutChangingApprovedVersion() async throws {
        let fixture = makeFixture(access: .paid)
        await fixture.model.requestTeachCy(instruction: "Make the tone plainer.", context: fixture.context)
        let proposal = try XCTUnwrap(fixture.model.voiceProfileProposal(context: fixture.context))
        fixture.voice.updatedAt = proposal.sourceUpdatedAt.addingTimeInterval(1)

        fixture.model.acceptVoiceProfileChange(proposal, context: fixture.context)

        XCTAssertTrue(fixture.voice.isApproved)
        XCTAssertEqual(fixture.voice.version, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<VoiceProfile>()).count, 1)
    }

    private func makeFixture(access: SubscriptionAccess, status: BriefStatus = .ready) -> Fixture {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(
            name: "Casey",
            goal: "Teach solo creators",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        )
        context.insert(profile)
        for index in 0..<3 {
            context.insert(VoiceExample(profileID: profile.id, text: "Example \(index) with one practical point.", sortOrder: index))
        }
        let voice = VoiceProfile(
            profileID: profile.id,
            summary: "Direct, grounded teaching",
            traitsText: "specific, plainspoken",
            avoidText: "hype",
            isApproved: true
        )
        context.insert(voice)
        let state = SubscriptionState(access: access)
        state.freeBriefConsumed = access == .freeJourney
        context.insert(state)
        let brief = CreativeBrief(title: "One useful move", premise: "Make the next creator step smaller", status: status)
        brief.audience = "Solo creators"
        brief.creativeGoal = "Make action feel possible"
        brief.takeaway = "Choose the smallest useful version"
        brief.spokenHook = "Your idea may be carrying too many jobs."
        brief.firstFrameText = "ONE IDEA. ONE JOB."
        brief.scriptBeats = ["Name the friction", "Show the small move"]
        brief.close = "Make the version you can finish today."
        brief.ctaIntent = "Save this for the next rough note."
        brief.filmingGuidance = "Direct to camera"
        brief.editingGuidance = "Keep the edit light"
        brief.assumptions = ["The creator can film a direct take."]
        brief.voiceConfidence = 0.8
        context.insert(brief)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready)
        output.caption = "Choose one audience and one takeaway."
        context.insert(output)
        let task = CreatorTask(
            briefID: brief.id,
            title: "Film the primary take",
            kind: .filming,
            notes: "Use one clean setup",
            estimatedMinutes: 25,
            isRecordingMilestoneDesignated: true
        )
        context.insert(task)
        try? context.save()
        return Fixture(
            container: container,
            context: context,
            model: AppModel(reminderService: PreviewReminderService()),
            profile: profile,
            voice: voice,
            state: state,
            brief: brief,
            output: output,
            task: task
        )
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let context: ModelContext
    let model: AppModel
    let profile: CreatorProfile
    let voice: VoiceProfile
    let state: SubscriptionState
    let brief: CreativeBrief
    let output: PlatformOutput
    let task: CreatorTask
}
