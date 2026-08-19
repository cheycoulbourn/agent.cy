import SwiftUI
import XCTest
@testable import AgentCy

@MainActor
final class PageMain08Tests: XCTestCase {

    // Reported 2026-08-19: opening a saved post visibly relocated the app to
    // the Idea Bank behind the review sheet. The review is shell-owned, so
    // opening a saved post must present it without moving the user's tab.
    func testOpeningASavedPostPresentsReviewWithoutSwitchingTabs() {
        let appModel = AppModel(creativeService: PreviewCreativeService())
        let workspace = CreatorWorkspace(profileID: UUID(), name: "@audit", sortOrder: 0)
        appModel.activeWorkspaceID = workspace.id

        let source = InspirationSource(
            workspaceID: workspace.id,
            canonicalURLString: "https://example.com/saved/reference",
            platform: .web
        )

        appModel.selectedTab = .home
        appModel.openInspiration(source)

        XCTAssertEqual(appModel.inspirationReviewRoute?.id, source.id, "Review route missing")
        XCTAssertEqual(appModel.selectedTab, .home, "Opening a saved post must not switch tabs")
    }

    // Out-of-scope sources stay closed and move nothing.
    func testOpeningAForeignSavedPostDoesNothing() {
        let appModel = AppModel(creativeService: PreviewCreativeService())
        appModel.activeWorkspaceID = UUID()

        let source = InspirationSource(
            workspaceID: UUID(),
            canonicalURLString: "https://example.com/saved/foreign",
            platform: .web
        )

        appModel.selectedTab = .tasks
        appModel.openInspiration(source)

        XCTAssertNil(appModel.inspirationReviewRoute)
        XCTAssertEqual(appModel.selectedTab, .tasks)
    }

    // Creator feature 2026-08-19: "Save a post" above the Saved Posts section
    // saves a reference by pasted link, in-app, without the share extension.
    // The link is canonicalized exactly like a shared one, and re-saving a
    // link reopens the existing reference instead of duplicating it.
    func testSaveAPostLinkCaptureCanonicalizesDedupesAndRejects() {
        let workspaceID = UUID()
        let saved = InspirationSource(
            workspaceID: workspaceID,
            canonicalURLString: "https://www.instagram.com/reel/DEF456/",
            platform: .instagram
        )

        let fresh = SavedPostLinkCapturePolicy.outcome(
            rawLink: " https://www.instagram.com/reel/ABC123/?utm_source=share&igsh=x ",
            workspaceID: workspaceID,
            existing: [saved]
        )
        XCTAssertEqual(fresh, .save(
            canonicalURLString: "https://www.instagram.com/reel/ABC123/",
            platform: .instagram
        ), "Tracking junk is stripped before saving")

        XCTAssertEqual(SavedPostLinkCapturePolicy.outcome(
            rawLink: "http://www.instagram.com/reel/GHI789/",
            workspaceID: workspaceID,
            existing: []
        ), .save(
            canonicalURLString: "https://www.instagram.com/reel/GHI789/",
            platform: .instagram
        ), "Plain http upgrades to https like the live-post flow")

        XCTAssertEqual(SavedPostLinkCapturePolicy.outcome(
            rawLink: "https://www.instagram.com/reel/DEF456/?utm_medium=copy",
            workspaceID: workspaceID,
            existing: [saved]
        ), .duplicate(existingID: saved.id), "Same account, same link reopens the saved post")

        XCTAssertEqual(SavedPostLinkCapturePolicy.outcome(
            rawLink: "https://www.instagram.com/reel/DEF456/",
            workspaceID: UUID(),
            existing: [saved]
        ), .save(
            canonicalURLString: "https://www.instagram.com/reel/DEF456/",
            platform: .instagram
        ), "Another account may save the same link")

        XCTAssertEqual(SavedPostLinkCapturePolicy.outcome(
            rawLink: "not a link",
            workspaceID: workspaceID,
            existing: []
        ), .invalid, "Garbage is rejected")
    }
}
