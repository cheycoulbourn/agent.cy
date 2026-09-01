import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageWork01Tests: XCTestCase {
    private enum SaveFailure: Error {
        case injected
    }

    func testIdeaFormUsesTheVisibleNotesAndFallsBackToPremise() {
        let notesIdea = CreativeBrief(title: "Notes", premise: "Legacy premise")
        notesIdea.notes = "Creator-edited thought"
        XCTAssertEqual(IdeaDraftForm(brief: notesIdea).text, "Creator-edited thought")

        let premiseIdea = CreativeBrief(title: "Premise", premise: "Captured thought")
        XCTAssertEqual(IdeaDraftForm(brief: premiseIdea).text, "Captured thought")
    }

    func testSavingAnIdeaChangesOnlyIdeaFields() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let originalDate = now.addingTimeInterval(86_400)
        let pillarID = UUID()
        let brief = CreativeBrief(title: "Old title", premise: "Old thought", status: .developing)
        brief.ideaBankPlacement = .idea
        brief.agendaDate = originalDate
        brief.workDate = originalDate

        try IdeaDraftPersistencePolicy.save(
            IdeaDraftForm(title: "  Clear title  ", text: "  Clear thought  ", pillarID: pillarID),
            to: brief,
            now: now,
            persist: {}
        )

        XCTAssertEqual(brief.title, "Clear title")
        XCTAssertEqual(brief.premise, "Clear thought")
        XCTAssertEqual(brief.notes, "Clear thought")
        XCTAssertEqual(brief.pillarID, pillarID)
        XCTAssertEqual(brief.status, .developing)
        XCTAssertEqual(brief.ideaBankPlacement, .idea)
        XCTAssertEqual(brief.agendaDate, originalDate)
        XCTAssertEqual(brief.workDate, originalDate)
        XCTAssertEqual(brief.updatedAt, now)
    }

    func testInvalidOrFailedSaveDoesNotMutateTheStoredIdea() {
        let brief = CreativeBrief(title: "Saved title", premise: "Saved thought")
        brief.notes = "Saved thought"
        let originalUpdatedAt = brief.updatedAt
        var persisted = false

        XCTAssertThrowsError(try IdeaDraftPersistencePolicy.save(
            IdeaDraftForm(title: "   ", text: "New thought", pillarID: UUID()),
            to: brief,
            persist: { persisted = true }
        )) { error in
            XCTAssertEqual(error as? IdeaDraftPersistencePolicy.Error, .emptyTitle)
        }
        XCTAssertFalse(persisted)
        XCTAssertEqual(brief.title, "Saved title")
        XCTAssertEqual(brief.premise, "Saved thought")

        XCTAssertThrowsError(try IdeaDraftPersistencePolicy.save(
            IdeaDraftForm(title: "New title", text: "New thought", pillarID: UUID()),
            to: brief,
            persist: { throw SaveFailure.injected }
        ))
        XCTAssertEqual(brief.title, "Saved title")
        XCTAssertEqual(brief.premise, "Saved thought")
        XCTAssertEqual(brief.notes, "Saved thought")
        XCTAssertNil(brief.pillarID)
        XCTAssertEqual(brief.updatedAt, originalUpdatedAt)
    }

    func testArchiveIsAtomicAndArchivedIdeasCannotBeEdited() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let brief = CreativeBrief(title: "Keep me", premise: "Original")
        let originalHistory = brief.lifecycleHistoryText

        XCTAssertThrowsError(try IdeaDraftPersistencePolicy.archive(
            IdeaDraftForm(title: "Updated", text: "Updated thought", pillarID: nil),
            brief: brief,
            now: now,
            persist: { throw SaveFailure.injected }
        ))
        XCTAssertEqual(brief.status, .spark)
        XCTAssertNil(brief.archivedAt)
        XCTAssertEqual(brief.lifecycleHistoryText, originalHistory)
        XCTAssertEqual(brief.title, "Keep me")

        try IdeaDraftPersistencePolicy.archive(
            IdeaDraftForm(title: "Updated", text: "Updated thought", pillarID: nil),
            brief: brief,
            now: now,
            persist: {}
        )
        XCTAssertEqual(brief.status, .archived)
        XCTAssertEqual(brief.archivedAt, now)
        XCTAssertEqual(brief.title, "Updated")
        XCTAssertEqual(brief.lifecycleHistory.last?.status, .archived)

        XCTAssertThrowsError(try IdeaDraftPersistencePolicy.save(
            IdeaDraftForm(title: "Resurrected", text: "No", pillarID: nil),
            to: brief,
            persist: {}
        )) { error in
            XCTAssertEqual(error as? IdeaDraftPersistencePolicy.Error, .notEditable)
        }
        XCTAssertEqual(brief.status, .archived)
        XCTAssertEqual(brief.title, "Updated")
    }

    func testRoutePolicyKeepsIdeaPostAndArchiveStagesSeparate() {
        XCTAssertEqual(IdeaDraftRoutePolicy.destination(for: .spark), .editor)
        XCTAssertEqual(IdeaDraftRoutePolicy.destination(for: .developing), .editor)
        XCTAssertEqual(IdeaDraftRoutePolicy.destination(for: .ready), .post)
        XCTAssertEqual(IdeaDraftRoutePolicy.destination(for: .scheduled), .post)
        XCTAssertEqual(IdeaDraftRoutePolicy.destination(for: .posted), .post)
        XCTAssertEqual(IdeaDraftRoutePolicy.destination(for: .archived), .archived)
    }

    func testExpiredAccessStillAllowsExistingIdeaEditsButNotNewPlanningOrCyWork() {
        let state = SubscriptionState(access: .expired)
        XCTAssertTrue(AccessPolicy.allows(.editExisting, state: state))
        XCTAssertFalse(AccessPolicy.allows(.schedule, state: state))
        XCTAssertFalse(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertFalse(AccessPolicy.allows(.compose, state: state))
    }

    func testIdeaDraftPreviewRequiresItsOwnLaunchArgument() {
        XCTAssertTrue(IdeaDraftRuntimeFixture.requestsIdeaDraft(
            arguments: ["agent.cy", "-agentCyPreviewIdeaDraft"]
        ))
        XCTAssertFalse(IdeaDraftRuntimeFixture.requestsIdeaDraft(
            arguments: ["agent.cy", "-agentCyPreviewScheduledPost"]
        ))
    }

    func testEnsuringAnExistingPostOutputNeverDowngradesItsLifecycle() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Already scheduled", status: .scheduled)
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        output.targetDate = Date().addingTimeInterval(86_400)
        let originalUpdatedAt = brief.updatedAt
        context.insert(brief)
        context.insert(output)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        let resolved = try XCTUnwrap(model.ensurePostDraft(for: brief, context: context))

        XCTAssertEqual(resolved.id, output.id)
        XCTAssertEqual(resolved.status, .scheduled)
        XCTAssertEqual(brief.status, .scheduled)
        XCTAssertNotNil(resolved.targetDate)
        XCTAssertTrue(brief.notes.isEmpty)
        XCTAssertEqual(brief.updatedAt, originalUpdatedAt)
    }
}
