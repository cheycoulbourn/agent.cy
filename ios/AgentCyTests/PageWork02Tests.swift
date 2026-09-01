import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageWork02Tests: XCTestCase {
    private enum SaveFailure: Error {
        case injected
    }

    func testSavingOneOutputPreservesItsLifecycleAndItsSibling() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "  Multi-output post  ", status: .developing)
        let editedOutput = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        let sibling = PlatformOutput(
            briefID: brief.id,
            platform: .youtubeShorts,
            status: .ready
        )
        let earlierDate = Date(timeIntervalSince1970: 1_800_000_000)
        let laterDate = earlierDate.addingTimeInterval(86_400)
        sibling.targetDate = earlierDate
        brief.includesWorkTime = true
        context.insert(brief)
        context.insert(editedOutput)
        context.insert(sibling)
        try context.save()

        _ = try PostDraftEditorPersistencePolicy.save(
            brief: brief,
            output: editedOutput,
            outputs: [editedOutput, sibling],
            notes: "Updated notes",
            hasWorkDate: true,
            workDate: earlierDate,
            hasTargetDate: true,
            targetDate: laterDate,
            writesTargetDate: true,
            rescheduleLinkedTasks: { _, _ in },
            persist: { try context.save() },
            rollback: { context.rollback() }
        )

        XCTAssertEqual(brief.title, "Multi-output post")
        XCTAssertEqual(brief.notes, "Updated notes")
        XCTAssertEqual(brief.workDate, earlierDate)
        XCTAssertEqual(editedOutput.status, .scheduled)
        XCTAssertEqual(sibling.status, .ready)
        XCTAssertEqual(editedOutput.targetDate, laterDate)
        XCTAssertEqual(brief.agendaDate, earlierDate)
    }

    func testFailedEditorSaveRollsBackLiveModelEditsAndDates() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let savedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let brief = CreativeBrief(title: "Saved title", status: .ready)
        brief.notes = "Saved notes"
        brief.agendaDate = savedDate
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        output.caption = "Saved caption"
        output.targetDate = savedDate
        context.insert(brief)
        context.insert(output)
        try context.save()
        let storedState = try PostDraftEditorStoredState.load(
            briefID: brief.id,
            outputID: output.id,
            context: context
        )

        brief.title = "Unsaved title"
        output.caption = "Unsaved caption"
        let attemptedDate = savedDate.addingTimeInterval(86_400)

        XCTAssertThrowsError(try PostDraftEditorPersistencePolicy.save(
            brief: brief,
            output: output,
            outputs: [output],
            notes: "Unsaved notes",
            hasWorkDate: true,
            workDate: attemptedDate,
            hasTargetDate: true,
            targetDate: attemptedDate,
            writesTargetDate: true,
            rescheduleLinkedTasks: { _, _ in },
            persist: { throw SaveFailure.injected },
            rollback: {
                context.rollback()
                storedState.restore(brief: brief, output: output, tasks: [])
            }
        ))

        XCTAssertEqual(brief.title, "Saved title")
        XCTAssertEqual(brief.notes, "Saved notes")
        XCTAssertEqual(output.caption, "Saved caption")
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertEqual(output.targetDate, savedDate)
        XCTAssertEqual(brief.agendaDate, savedDate)
    }

    func testEmptyTitleCannotPersistAndRestoresLastSavedVersion() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Saved title")
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        context.insert(brief)
        context.insert(output)
        try context.save()
        let storedState = try PostDraftEditorStoredState.load(
            briefID: brief.id,
            outputID: output.id,
            context: context
        )
        brief.title = "   "

        XCTAssertThrowsError(try PostDraftEditorPersistencePolicy.save(
            brief: brief,
            output: output,
            outputs: [output],
            notes: "",
            hasWorkDate: false,
            workDate: Date(),
            hasTargetDate: false,
            targetDate: Date(),
            writesTargetDate: false,
            rescheduleLinkedTasks: { _, _ in },
            persist: { XCTFail("An invalid title must not reach persistence") },
            rollback: {
                context.rollback()
                storedState.restore(brief: brief, output: output, tasks: [])
            }
        )) { error in
            XCTAssertEqual(error as? PostDraftEditorPersistencePolicy.Error, .emptyTitle)
        }
        XCTAssertEqual(brief.title, "Saved title")
    }

    func testExplicitSaveSuppressesDuplicateExitPersistence() {
        XCTAssertTrue(PostDraftExitPersistencePolicy.shouldPersist(
            isDeleting: false,
            didMoveToIdeaBank: false,
            didPersistBeforeExit: false
        ))
        XCTAssertFalse(PostDraftExitPersistencePolicy.shouldPersist(
            isDeleting: false,
            didMoveToIdeaBank: false,
            didPersistBeforeExit: true
        ))
    }

    func testTextCoordinatorKeepsTypingLocalUntilExplicitCommit() {
        let coordinator = PostEditorTextCommitCoordinator()
        var storedTitle = "Saved title"

        coordinator.update(key: "post-title", value: "First keystroke") { storedTitle = $0 }
        coordinator.update(key: "post-title", value: "Complete edit") { storedTitle = $0 }
        XCTAssertEqual(storedTitle, "Saved title")

        coordinator.commitAll()
        XCTAssertEqual(storedTitle, "Complete edit")
    }

    func testResumePolicyNeverDowngradesAnOutputAsASaveSideEffect() {
        for status in [PlatformOutputStatus.draft, .ready, .scheduled, .posted] {
            XCTAssertEqual(
                PostDraftResumePolicy.outputStatus(briefStatus: .developing, current: status),
                status
            )
        }
    }

    func testPostEditorPreviewRequiresItsOwnLaunchArgument() {
        XCTAssertTrue(PostEditorRuntimeFixture.requestsPostEditor(
            arguments: ["agent.cy", "-agentCyPreviewPostEditor"]
        ))
        XCTAssertFalse(PostEditorRuntimeFixture.requestsPostEditor(
            arguments: ["agent.cy", "-agentCyPreviewScheduledPost"]
        ))
    }
}
