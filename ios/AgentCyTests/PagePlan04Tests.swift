import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PagePlan04Tests: XCTestCase {
    func testSchedulePickerShowsSavedIdeasButNotPostDraftsOrForeignWork() {
        let profileID = UUID()
        let activeWorkspace = CreatorWorkspace(profileID: profileID, name: "Active", sortOrder: 0)
        let otherWorkspace = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let archivedPillar = Pillar(role: .anchor, name: "Old pillar")
        archivedPillar.workspaceID = activeWorkspace.id
        archivedPillar.isArchived = true

        let savedIdea = CreativeBrief(title: "Saved idea", status: .developing)
        savedIdea.workspaceID = activeWorkspace.id
        savedIdea.ideaBankPlacement = .idea
        savedIdea.pillarID = archivedPillar.id
        let legacyIdea = CreativeBrief(title: "Legacy idea", status: .spark)
        legacyIdea.workspaceID = activeWorkspace.id
        let postDraft = CreativeBrief(title: "Already a post", status: .spark)
        postDraft.workspaceID = activeWorkspace.id
        postDraft.ideaBankPlacement = .post
        let foreignIdea = CreativeBrief(title: "Foreign idea", status: .spark)
        foreignIdea.workspaceID = otherWorkspace.id
        foreignIdea.ideaBankPlacement = .idea
        let archivedIdea = CreativeBrief(title: "Archived idea", status: .archived)
        archivedIdea.workspaceID = activeWorkspace.id
        archivedIdea.ideaBankPlacement = .idea

        let projection = AgendaPostIdeaPickerProjection.make(
            briefs: [postDraft, savedIdea, legacyIdea, foreignIdea, archivedIdea],
            pillars: [archivedPillar],
            preferredWorkspaceID: activeWorkspace.id,
            workspaces: [activeWorkspace, otherWorkspace],
            query: ""
        )

        XCTAssertEqual(Set(projection.ideas.map(\.id)), Set([savedIdea.id, legacyIdea.id]))
        XCTAssertNil(projection.activePillarByID[archivedPillar.id])
    }

    func testSchedulePickerSearchesIdeaTextAndActivePillar() {
        let workspace = CreatorWorkspace(profileID: UUID(), name: "Active")
        let pillar = Pillar(role: .anchor, name: "Creator systems")
        pillar.workspaceID = workspace.id
        let idea = CreativeBrief(title: "Morning workflow", status: .spark)
        idea.workspaceID = workspace.id
        idea.ideaBankPlacement = .idea
        idea.pillarID = pillar.id
        idea.notes = "Show the three setup steps."

        let byNotes = AgendaPostIdeaPickerProjection.make(
            briefs: [idea],
            pillars: [pillar],
            preferredWorkspaceID: workspace.id,
            workspaces: [workspace],
            query: "setup steps"
        )
        let byPillar = AgendaPostIdeaPickerProjection.make(
            briefs: [idea],
            pillars: [pillar],
            preferredWorkspaceID: workspace.id,
            workspaces: [workspace],
            query: "creator systems"
        )

        XCTAssertEqual(byNotes.ideas.map(\.id), [idea.id])
        XCTAssertEqual(byPillar.ideas.map(\.id), [idea.id])
    }

    func testSchedulePickerUsesNoonWithoutClaimingAnExplicitTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let plannedDate = AgendaPostIdeaPickerDatePolicy.plannedDate(for: day, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: plannedDate), 12)
        XCTAssertEqual(calendar.component(.minute, from: plannedDate), 0)
    }

    func testOpeningSavedIdeaCreatesDateOnlyDraft() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let idea = CreativeBrief(title: "Saved idea", status: .developing)
        idea.ideaBankPlacement = .idea
        context.insert(idea)
        try context.save()

        let appModel = AppModel(reminderService: PreviewReminderService())
        let output = try XCTUnwrap(appModel.ensurePostDraft(for: idea, context: context))

        XCTAssertNil(output.targetDate)
        XCTAssertFalse(output.includesTargetTime)
    }

    func testSchedulePickerPreviewRouteRequiresItsOwnArgument() {
        XCTAssertTrue(PreviewAgendaRuntimeFixture.requestsSchedulePost(
            arguments: ["agent.cy", "-agentCyPreviewSchedulePost"]
        ))
        XCTAssertFalse(PreviewAgendaRuntimeFixture.requestsSchedulePost(
            arguments: ["agent.cy", "-agentCyPreviewAgendaMode", "week"]
        ))
        XCTAssertEqual(
            PreviewAgendaRuntimeFixture.schedulePostEditorRoute(arguments: [
                "agent.cy", "-agentCyPreviewSchedulePostEditor", "new"
            ]),
            .newPost
        )
        XCTAssertEqual(
            PreviewAgendaRuntimeFixture.schedulePostEditorRoute(arguments: [
                "agent.cy", "-agentCyPreviewSchedulePostEditor", "idea"
            ]),
            .firstIdea
        )
        XCTAssertNil(PreviewAgendaRuntimeFixture.schedulePostEditorRoute(
            arguments: ["agent.cy"]
        ))
    }
}
