import SwiftUI
import XCTest
@testable import AgentCy

@MainActor
final class PageMain05Tests: XCTestCase {
    func testProjectionScopesIdeasAndSavedPostsToTheResolvedWorkspace() {
        let profileID = UUID()
        let active = CreatorWorkspace(profileID: profileID, name: "Active", sortOrder: 0)
        let other = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let pillar = Pillar(role: .anchor, name: "Systems")
        pillar.workspaceID = active.id

        let activeIdea = CreativeBrief(title: "Active idea", status: .developing)
        activeIdea.workspaceID = active.id
        activeIdea.pillarID = pillar.id
        let otherIdea = CreativeBrief(title: "Other idea", status: .developing)
        otherIdea.workspaceID = other.id

        let activeSource = InspirationSource(
            workspaceID: active.id,
            canonicalURLString: "https://example.com/active",
            platform: .web
        )
        activeSource.sourceTitle = "Active reference"
        let otherSource = InspirationSource(
            workspaceID: other.id,
            canonicalURLString: "https://example.com/other",
            platform: .web
        )
        otherSource.sourceTitle = "Other reference"

        let projection = IdeaBankRootProjectionPolicy.make(
            briefs: [activeIdea, otherIdea],
            inspirationSources: [activeSource, otherSource],
            pillars: [pillar],
            preferredWorkspaceID: active.id,
            workspaces: [active, other],
            search: "",
            selectedFilter: .all
        )

        XCTAssertEqual(projection.ideas.map(\.id), [activeIdea.id])
        XCTAssertEqual(projection.savedInspirations.map(\.id), [activeSource.id])
        XCTAssertEqual(projection.savedInspirationPreview.map(\.id), [activeSource.id])
        XCTAssertEqual(projection.resolvedWorkspaceID, active.id)
    }

    func testProjectionNormalizesAStalePillarFilterAndNeverHandsItToCapture() {
        let stalePillarID = UUID()

        XCTAssertEqual(
            IdeaBankRootStatePolicy.normalizedFilter(
                .pillar(stalePillarID),
                activePillarIDs: []
            ),
            .all
        )
        XCTAssertNil(IdeaBankRootStatePolicy.capturePillarID(
            for: .pillar(stalePillarID),
            activePillarIDs: []
        ))
    }

    func testProjectionKeepsArchivedIdeasSearchableByAttachedPillar() {
        let workspace = CreatorWorkspace(profileID: UUID(), name: "Active")
        let pillar = Pillar(role: .anchor, name: "Creator systems")
        pillar.workspaceID = workspace.id
        let archived = CreativeBrief(title: "Old framework", status: .archived)
        archived.workspaceID = workspace.id
        archived.pillarID = pillar.id

        let projection = IdeaBankRootProjectionPolicy.make(
            briefs: [archived],
            inspirationSources: [],
            pillars: [pillar],
            preferredWorkspaceID: workspace.id,
            workspaces: [workspace],
            search: "systems",
            selectedFilter: .archived
        )

        XCTAssertEqual(projection.ideas.map(\.id), [archived.id])
        XCTAssertEqual(projection.pillarByID[pillar.id]?.name, "Creator systems")
    }

    func testVisibleSelectionReconciliationDropsHiddenIdeasAndSavedPosts() {
        let visibleIdeaID = UUID()
        let visibleSavedPostID = UUID()
        let result = IdeaBankRootStatePolicy.reconciledSelection(
            ideaIDs: [visibleIdeaID, UUID()],
            savedPostIDs: [visibleSavedPostID, UUID()],
            visibleIdeaIDs: [visibleIdeaID],
            visibleSavedPostIDs: [visibleSavedPostID]
        )

        XCTAssertEqual(result.ideaIDs, [visibleIdeaID])
        XCTAssertEqual(result.savedPostIDs, [visibleSavedPostID])
        XCTAssertEqual(
            IdeaBankRootStatePolicy.selectableSavedPostIDs(
                previewIDs: [visibleSavedPostID],
                savedPostsAreVisible: true
            ),
            [visibleSavedPostID]
        )
        XCTAssertTrue(IdeaBankRootStatePolicy.selectableSavedPostIDs(
            previewIDs: [visibleSavedPostID],
            savedPostsAreVisible: false
        ).isEmpty)
    }

    func testRequestedIdeaIsConsumedWhetherItExistsOrIsMissing() {
        let idea = CreativeBrief(title: "Reachable", status: .developing)

        XCTAssertEqual(
            IdeaBankRequestedRoutePolicy.resolve(requestedID: idea.id, scopedBriefs: [idea]),
            .idea(idea.id)
        )
        XCTAssertEqual(
            IdeaBankRequestedRoutePolicy.resolve(requestedID: UUID(), scopedBriefs: [idea]),
            .missing
        )
        XCTAssertEqual(
            IdeaBankRequestedRoutePolicy.resolve(requestedID: nil, scopedBriefs: [idea]),
            .none
        )
    }

    func testSelectionMotionHonorsReduceMotion() {
        XCTAssertTrue(IdeaBankRootAccessibilityPolicy.shouldAnimateSelection(reduceMotion: false))
        XCTAssertFalse(IdeaBankRootAccessibilityPolicy.shouldAnimateSelection(reduceMotion: true))
    }

    func testAccessibilityStacksActionsAndLetsIdeaMetadataWrap() {
        XCTAssertTrue(IdeaBankRootAccessibilityPolicy.usesStackedSelectionActions(
            dynamicTypeSize: .accessibility1
        ))
        XCTAssertFalse(IdeaBankRootAccessibilityPolicy.usesStackedSelectionActions(
            dynamicTypeSize: .large
        ))
        XCTAssertTrue(IdeaBankRootAccessibilityPolicy.usesBoundedCancelAction(
            dynamicTypeSize: .accessibility1
        ))
        XCTAssertEqual(
            IdeaBankRootAccessibilityPolicy.ideaTitleLineLimit(dynamicTypeSize: .accessibility1),
            4
        )
        XCTAssertEqual(
            IdeaBankRootAccessibilityPolicy.ideaMetadataLineLimit(dynamicTypeSize: .accessibility1),
            3
        )
        XCTAssertEqual(
            SavedPostRowAccessibilityPolicy.titleLineLimit(dynamicTypeSize: .accessibility1),
            4
        )
        XCTAssertEqual(
            SavedPostRowAccessibilityPolicy.metadataLineLimit(dynamicTypeSize: .accessibility1),
            3
        )
    }
}
