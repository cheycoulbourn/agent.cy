import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageTask02Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testChooserProjectionIsWorkspaceScopedAndRequiresARealScheduledDate() throws {
        let profileID = UUID()
        let activeWorkspace = CreatorWorkspace(profileID: profileID, name: "Active")
        let otherWorkspace = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let pillar = Pillar(name: "Studio")
        pillar.workspaceID = activeWorkspace.id

        let currentBrief = CreativeBrief(title: "Current week", status: .scheduled)
        currentBrief.workspaceID = activeWorkspace.id
        currentBrief.pillarID = pillar.id
        let currentOutput = PlatformOutput(
            briefID: currentBrief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        currentOutput.workspaceID = activeWorkspace.id
        currentOutput.targetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19
        )))

        let outsideBrief = CreativeBrief(title: "Outside week", status: .scheduled)
        outsideBrief.workspaceID = activeWorkspace.id
        let outsideOutput = PlatformOutput(
            briefID: outsideBrief.id,
            platform: .tiktok,
            status: .scheduled
        )
        outsideOutput.workspaceID = activeWorkspace.id
        outsideOutput.targetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2
        )))

        let missingDateBrief = CreativeBrief(title: "Missing date", status: .scheduled)
        missingDateBrief.workspaceID = activeWorkspace.id
        let missingDateOutput = PlatformOutput(
            briefID: missingDateBrief.id,
            platform: .youtubeShorts,
            status: .scheduled
        )
        missingDateOutput.workspaceID = activeWorkspace.id

        let archivedBrief = CreativeBrief(title: "Archived", status: .archived)
        archivedBrief.workspaceID = activeWorkspace.id
        let archivedOutput = PlatformOutput(
            briefID: archivedBrief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        archivedOutput.workspaceID = activeWorkspace.id
        archivedOutput.targetDate = currentOutput.targetDate

        let otherBrief = CreativeBrief(title: "Other workspace", status: .scheduled)
        otherBrief.workspaceID = otherWorkspace.id
        let otherOutput = PlatformOutput(
            briefID: otherBrief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        otherOutput.workspaceID = otherWorkspace.id
        otherOutput.targetDate = currentOutput.targetDate

        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 18, hour: 12
        )))
        let inputs = PostTaskCreationProjection.Inputs(
            briefs: [otherBrief, archivedBrief, outsideBrief, currentBrief, missingDateBrief],
            outputs: [otherOutput, archivedOutput, outsideOutput, currentOutput, missingDateOutput],
            pillars: [pillar],
            workspaces: [activeWorkspace, otherWorkspace],
            activeWorkspaceID: activeWorkspace.id,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            PostTaskCreationProjection.make(inputs: inputs, search: "").candidates.map(\.output.id),
            [currentOutput.id]
        )
        XCTAssertEqual(
            PostTaskCreationProjection.make(inputs: inputs, search: "outside").candidates.map(\.output.id),
            [outsideOutput.id]
        )
        XCTAssertTrue(
            PostTaskCreationProjection.make(inputs: inputs, search: "missing date").candidates.isEmpty
        )
    }

    func testAtomicSaveHonorsExplicitNoDateAndCreatesCompletedSubtasks() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let workspace = CreatorWorkspace(profileID: profileID, name: "Main")
        let brief = CreativeBrief(title: "Studio tour", status: .scheduled)
        brief.workspaceID = workspace.id
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        output.workspaceID = workspace.id
        output.targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(SubscriptionState(access: .paid))
        context.insert(workspace)
        context.insert(brief)
        context.insert(output)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        model.activeWorkspaceID = workspace.id
        let task = try XCTUnwrap(model.createLinkedPostTask(
            title: "  Write the caption  ",
            notes: "  Keep it concise.  ",
            priority: .high,
            targetDate: nil,
            includesTargetTime: true,
            recurrence: .none,
            briefID: brief.id,
            outputID: output.id,
            subtasks: [
                TaskCreationSubtaskDraft(title: "  Draft opening  ", isCompleted: true),
                TaskCreationSubtaskDraft(title: "   ", isCompleted: false),
            ],
            context: context
        ))

        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let child = try XCTUnwrap(tasks.first(where: { $0.parentTaskID == task.id }))
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(task.title, "Write the caption")
        XCTAssertEqual(task.notes, "Keep it concise.")
        XCTAssertEqual(task.workspaceID, workspace.id)
        XCTAssertEqual(task.briefID, brief.id)
        XCTAssertEqual(task.platformOutputID, output.id)
        XCTAssertNil(task.targetDate)
        XCTAssertFalse(task.includesTargetTime)
        XCTAssertEqual(child.title, "Draft opening")
        XCTAssertEqual(child.workspaceID, workspace.id)
        XCTAssertTrue(child.isCompleted)
        XCTAssertNotNil(child.completedAt)
        XCTAssertEqual(output.targetDate, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertEqual(brief.status, .scheduled)
    }

    func testSaveRejectsASelectionFromAnotherWorkspaceWithoutPartialTask() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let activeWorkspace = CreatorWorkspace(profileID: profileID, name: "Active")
        let otherWorkspace = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let brief = CreativeBrief(title: "Other post", status: .scheduled)
        brief.workspaceID = otherWorkspace.id
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        output.workspaceID = otherWorkspace.id
        output.targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(SubscriptionState(access: .paid))
        context.insert(activeWorkspace)
        context.insert(otherWorkspace)
        context.insert(brief)
        context.insert(output)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        model.activeWorkspaceID = activeWorkspace.id
        XCTAssertNil(model.createLinkedPostTask(
            title: "Should not save",
            notes: "",
            priority: .none,
            targetDate: nil,
            includesTargetTime: false,
            recurrence: .none,
            briefID: brief.id,
            outputID: output.id,
            subtasks: [],
            context: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
        XCTAssertEqual(brief.status, .scheduled)
        XCTAssertEqual(output.status, .scheduled)
    }

    func testComposerPreviewRequiresItsOwnLaunchArgument() {
        XCTAssertTrue(TaskRuntimeFixture.requestsPostTaskChooser(
            arguments: ["agent.cy", "-agentCyPreviewPostTaskChooser"]
        ))
        XCTAssertFalse(TaskRuntimeFixture.requestsPostTaskChooser(
            arguments: ["agent.cy", "-agentCyPreviewPostTaskComposer"]
        ))
        XCTAssertTrue(TaskRuntimeFixture.requestsPostTaskComposer(
            arguments: ["agent.cy", "-agentCyPreviewPostTaskComposer"]
        ))
        XCTAssertFalse(TaskRuntimeFixture.requestsPostTaskComposer(
            arguments: ["agent.cy", "-agentCyPreviewTaskRoute"]
        ))
    }
}
