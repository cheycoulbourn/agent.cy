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

    func testMCPIdeaReviewKeepsItsPillarNameAndIdentifiesMetadataAsAnIdea() {
        XCTAssertEqual(
            MCPReviewPillarPresentation.label(type: "createIdea", pillarName: "Lifestyle"),
            "Lifestyle"
        )
        XCTAssertEqual(
            MCPReviewPillarPresentation.label(type: "createIdea", pillarName: "Unfiled"),
            "Unfiled"
        )
        XCTAssertEqual(
            MCPReviewPillarPresentation.metadata(type: "createIdea", fallback: "Post"),
            "Idea"
        )
    }

    func testMCPPostReviewKeepsPostPillarAndMetadata() {
        XCTAssertEqual(
            MCPReviewPillarPresentation.label(type: "createPostDraft", pillarName: "Lifestyle"),
            "Lifestyle"
        )
        XCTAssertEqual(
            MCPReviewPillarPresentation.metadata(type: "createPostDraft", fallback: "Instagram"),
            "Instagram"
        )
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

    func testPastScheduledPostUsesMissedPresentation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertTrue(FinalizedPostPresentation.isMissed(
            outputStatus: .scheduled,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(FinalizedPostPresentation.pageTitle(
            outputStatus: .scheduled,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "Missed post")
        XCTAssertEqual(FinalizedPostPresentation.statusTitle(
            outputStatus: .scheduled,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "MISSED")
    }

    func testPostedPostNeverUsesMissedPresentation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertFalse(FinalizedPostPresentation.isMissed(
            outputStatus: .posted,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(FinalizedPostPresentation.pageTitle(
            outputStatus: .posted,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "Posted")
        XCTAssertEqual(FinalizedPostPresentation.statusTitle(
            outputStatus: .posted,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "POSTED")
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
