import XCTest
@testable import AgentCy

final class PostOutputDetailPolicyTests: XCTestCase {
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
}
