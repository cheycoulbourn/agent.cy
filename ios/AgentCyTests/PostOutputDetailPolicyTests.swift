import XCTest
import UIKit
@testable import AgentCy

final class PostOutputDetailPolicyTests: XCTestCase {
    func testAppearancePreferencesMapToWindowStyles() {
        XCTAssertEqual(AppearancePreference.system.userInterfaceStyle, .unspecified)
        XCTAssertEqual(AppearancePreference.light.userInterfaceStyle, .light)
        XCTAssertEqual(AppearancePreference.dark.userInterfaceStyle, .dark)
    }

    func testMCPReviewEditingIsAvailableForExistingPostChanges() {
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "updatePost"))
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "schedulePost"))
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "createPostDraft"))
        XCTAssertFalse(MCPReviewEditPolicy.allowsEditing(type: "addTask"))
    }

    func testDatedDraftOnScheduledBriefAlwaysResumesPostEditor() {
        XCTAssertEqual(
            PostOutputDetailPolicy.destination(
                briefStatus: .scheduled,
                outputStatus: .draft,
                targetDate: Date()
            ),
            .draftEditor
        )
    }

    func testScheduledAndPostedOutputsUseFinalizedDetail() {
        XCTAssertTrue(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .scheduled, targetDate: nil))
        XCTAssertTrue(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .posted, targetDate: nil))
    }

    func testReadyOutputWithDateUsesFinalizedDetail() {
        XCTAssertTrue(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .ready, targetDate: Date()))
    }

    func testDraftAndUnscheduledReadyOutputsKeepTheirCreationFlow() {
        XCTAssertFalse(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .draft, targetDate: Date()))
        XCTAssertFalse(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .ready, targetDate: nil))
    }

    func testLinkedTaskUsesItsExactPlatformOutput() {
        let brief = CreativeBrief(title: "DITL vlog")
        let other = PlatformOutput(briefID: brief.id, platform: .tiktok)
        other.status = .scheduled
        let linked = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        linked.status = .scheduled
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: linked.id,
            title: "Film the vlog"
        )

        XCTAssertEqual(TaskLinkedPostPolicy.output(for: task, in: [other, linked])?.id, linked.id)
    }

    func testLegacyLinkedTaskPrefersFinalizedOutputForItsBrief() {
        let brief = CreativeBrief(title: "DITL vlog")
        let unrelated = PlatformOutput(briefID: UUID(), platform: .youtubeShorts)
        unrelated.status = .scheduled
        let draft = PlatformOutput(briefID: brief.id, platform: .tiktok)
        draft.status = .draft
        let scheduled = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        scheduled.status = .scheduled
        let task = CreatorTask(briefID: brief.id, title: "Film the vlog")

        XCTAssertEqual(
            TaskLinkedPostPolicy.output(for: task, in: [unrelated, draft, scheduled])?.id,
            scheduled.id
        )
    }
}
