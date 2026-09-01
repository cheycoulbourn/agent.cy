import XCTest
@testable import AgentCy

final class PagePlan03Tests: XCTestCase {
    func testPostSearchPreviewRouteRequiresExplicitArguments() {
        XCTAssertTrue(PlanRuntimeFixture.requestsPostSearch(
            arguments: ["agent.cy", "-agentCyPreviewPostSearch"]
        ))
        XCTAssertFalse(PlanRuntimeFixture.requestsPostSearch(
            arguments: ["agent.cy", "-agentCyPreviewTab", "today"]
        ))
        XCTAssertEqual(
            PlanRuntimeFixture.postSearchQuery(arguments: [
                "agent.cy", "-agentCyPreviewPostSearchQuery", "creator systems"
            ]),
            "creator systems"
        )
        XCTAssertNil(PlanRuntimeFixture.postSearchQuery(arguments: ["agent.cy"]))
    }

    func testPostSearchScopesActiveWorkAndDropsArchivedOrBrokenLinks() {
        let profileID = UUID()
        let activeWorkspace = CreatorWorkspace(profileID: profileID, name: "Active", sortOrder: 0)
        let otherWorkspace = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)

        let activeBrief = CreativeBrief(title: "Active post", status: .scheduled)
        activeBrief.workspaceID = activeWorkspace.id
        let archivedBrief = CreativeBrief(title: "Archived post", status: .archived)
        archivedBrief.workspaceID = activeWorkspace.id
        let foreignBrief = CreativeBrief(title: "Foreign post", status: .scheduled)
        foreignBrief.workspaceID = otherWorkspace.id

        let activeOutput = PlatformOutput(briefID: activeBrief.id, platform: .tiktok)
        activeOutput.workspaceID = activeWorkspace.id
        let archivedOutput = PlatformOutput(briefID: archivedBrief.id, platform: .tiktok)
        archivedOutput.workspaceID = activeWorkspace.id
        let foreignOutput = PlatformOutput(briefID: foreignBrief.id, platform: .tiktok)
        foreignOutput.workspaceID = otherWorkspace.id
        let brokenOutput = PlatformOutput(briefID: UUID(), platform: .tiktok)
        brokenOutput.workspaceID = activeWorkspace.id

        let projection = AgendaPostSearchProjection.make(
            briefs: [activeBrief, archivedBrief, foreignBrief],
            outputs: [activeOutput, archivedOutput, foreignOutput, brokenOutput],
            pillars: [],
            destinations: [],
            formats: [],
            preferredWorkspaceID: activeWorkspace.id,
            workspaces: [activeWorkspace, otherWorkspace],
            query: ""
        )

        XCTAssertEqual(projection.results.map(\.output.id), [activeOutput.id])
    }

    func testPostSearchMatchesFormatAndRawPlatformWhenDestinationExists() {
        let workspace = CreatorWorkspace(profileID: UUID(), name: "Active")
        let destination = PublishingDestination(name: "Instagram")
        let format = PublishingFormat(
            destinationID: destination.id,
            name: "Tutorial Reel",
            kind: .shortVideo
        )
        let brief = CreativeBrief(title: "Editing workflow", status: .scheduled)
        brief.workspaceID = workspace.id
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            destinationID: destination.id,
            formatID: format.id
        )
        output.workspaceID = workspace.id

        let formatProjection = AgendaPostSearchProjection.make(
            briefs: [brief],
            outputs: [output],
            pillars: [],
            destinations: [destination],
            formats: [format],
            preferredWorkspaceID: workspace.id,
            workspaces: [workspace],
            query: "tutorial reel"
        )
        let platformProjection = AgendaPostSearchProjection.make(
            briefs: [brief],
            outputs: [output],
            pillars: [],
            destinations: [destination],
            formats: [format],
            preferredWorkspaceID: workspace.id,
            workspaces: [workspace],
            query: "instagram reels"
        )

        XCTAssertEqual(formatProjection.results.map(\.output.id), [output.id])
        XCTAssertEqual(platformProjection.results.map(\.output.id), [output.id])
        XCTAssertEqual(formatProjection.results.first?.metadata, "Instagram")
    }
}
