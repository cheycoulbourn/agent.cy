import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageTask01Tests: XCTestCase {
    func testTaskDetailPreviewRequiresExplicitLaunchArgument() {
        XCTAssertTrue(AppShellRuntimeFixture.requestsFirstPreviewTask(
            arguments: ["agent.cy", "-agentCyPreviewTaskRoute"]
        ))
        XCTAssertFalse(AppShellRuntimeFixture.requestsFirstPreviewTask(
            arguments: ["agent.cy", "-agentCyPreviewData"]
        ))
    }

    func testTaskDetailPreviewSelectsATopLevelTask() {
        let parent = CreatorTask(title: "Parent")
        let child = CreatorTask(parentTaskID: parent.id, title: "Child")

        XCTAssertEqual(
            AppShellRuntimeFixture.firstPreviewTask(in: [child, parent])?.id,
            parent.id
        )
    }

    func testDuplicateKeepsOwnershipAndEditableConfigurationWithoutCloningRecurrence() {
        let workspaceID = UUID()
        let partnerID = UUID()
        let source = CreatorTask(
            briefID: UUID(),
            pillarID: UUID(),
            platformOutputID: UUID(),
            title: "Publish the studio tour",
            kind: .publishing,
            lane: .production,
            priority: .high,
            notes: "Add the final cover.",
            estimatedMinutes: 25,
            targetDate: Date(timeIntervalSince1970: 1_800_000_000),
            includesTargetTime: true,
            recurrence: .weekly,
            recurrenceRootTaskID: UUID()
        )
        source.workspaceID = workspaceID
        source.brandPartnerID = partnerID

        let copy = TaskDetailDuplicationPolicy.copy(of: source)

        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.workspaceID, workspaceID)
        XCTAssertEqual(copy.brandPartnerID, partnerID)
        XCTAssertEqual(copy.briefID, source.briefID)
        XCTAssertEqual(copy.pillarID, source.pillarID)
        XCTAssertEqual(copy.platformOutputID, source.platformOutputID)
        XCTAssertEqual(copy.title, "Publish the studio tour copy")
        XCTAssertEqual(copy.notes, source.notes)
        XCTAssertEqual(copy.estimatedMinutes, source.estimatedMinutes)
        XCTAssertEqual(copy.targetDate, source.targetDate)
        XCTAssertTrue(copy.includesTargetTime)
        XCTAssertEqual(copy.recurrence, .none)
        XCTAssertNil(copy.recurrenceRootTaskID)
        XCTAssertNil(copy.parentTaskID)
        XCTAssertFalse(copy.isCompleted)
        XCTAssertFalse(copy.isSkipped)
    }

    func testOnlyAnImplicitBackExitAutosaves() {
        XCTAssertTrue(TaskDetailExitPolicy.shouldPersistOnDisappear(state: .editing))
        XCTAssertFalse(TaskDetailExitPolicy.shouldPersistOnDisappear(state: .persisted))
        XCTAssertFalse(TaskDetailExitPolicy.shouldPersistOnDisappear(state: .deleted))
    }

    func testPillarChoicesStayInsideTheTaskWorkspace() {
        let profileID = UUID()
        let activeWorkspace = CreatorWorkspace(profileID: profileID, name: "Active")
        let otherWorkspace = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let active = Pillar(name: "Active pillar")
        active.workspaceID = activeWorkspace.id
        let archived = Pillar(name: "Archived pillar")
        archived.isArchived = true
        archived.workspaceID = activeWorkspace.id
        let other = Pillar(name: "Other pillar")
        other.workspaceID = otherWorkspace.id

        XCTAssertEqual(
            TaskDetailPillarPolicy.activePillars(
                from: [other, archived, active],
                taskWorkspaceID: activeWorkspace.id,
                workspaces: [activeWorkspace, otherWorkspace]
            ).map(\.id),
            [active.id]
        )
    }

    func testDeleteReportsSuccessAndRemovesParentAndSubtasks() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let parent = CreatorTask(title: "Parent")
        let child = CreatorTask(parentTaskID: parent.id, title: "Child")
        parent.workspaceID = UUID()
        child.workspaceID = parent.workspaceID
        context.insert(parent)
        context.insert(child)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.deleteTask(parent, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
    }
}
