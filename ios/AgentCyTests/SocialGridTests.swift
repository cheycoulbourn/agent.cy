import XCTest
@testable import AgentCy

final class SocialGridTests: XCTestCase {
    func testPhoneGridLivesInsidePlanWithoutAddingASeventhTab() {
        XCTAssertEqual(PlanNavigationRoute.allCases, [.socialGrid])
        XCTAssertEqual(AppTab.allCases, [.home, .today, .tasks, .pillars, .ideaBank, .cy])
    }

    func testPresentationKeepsPhoneBottomNavigationClear() {
        XCTAssertFalse(SocialGridPresentation.desktop.isPhone)
        XCTAssertEqual(SocialGridPresentation.desktop.bottomClearance, 0)

        let phone = SocialGridPresentation.phone(bottomClearance: 76)
        XCTAssertTrue(phone.isPhone)
        XCTAssertEqual(phone.bottomClearance, 76)
        XCTAssertTrue(phone.placesArrangeInProfileSummary)
        XCTAssertFalse(SocialGridPresentation.desktop.placesArrangeInProfileSummary)
    }

    func testGridUsesInstagramPortraitPreviewRatio() {
        XCTAssertEqual(SocialGridLayoutPolicy.tileWidthToHeightRatio, 0.75)
    }

    func testProjectionIncludesScheduledAndPostedInstagramOutputs() {
        let now = Date()
        let scheduled = SocialGridProjectionRecord(
            outputID: UUID(),
            status: .scheduled,
            targetDate: now.addingTimeInterval(3_600),
            postedAt: nil,
            createdAt: now,
            publishedURLString: ""
        )
        let posted = SocialGridProjectionRecord(
            outputID: UUID(),
            status: .posted,
            targetDate: nil,
            postedAt: now,
            createdAt: now.addingTimeInterval(-3_600),
            publishedURLString: "https://www.instagram.com/p/example/"
        )
        let draft = SocialGridProjectionRecord(
            outputID: UUID(),
            status: .draft,
            targetDate: now,
            postedAt: nil,
            createdAt: now,
            publishedURLString: ""
        )
        let unscheduled = SocialGridProjectionRecord(
            outputID: UUID(),
            status: .scheduled,
            targetDate: nil,
            postedAt: nil,
            createdAt: now,
            publishedURLString: ""
        )

        XCTAssertTrue(SocialGridProjectionPolicy.includes(scheduled))
        XCTAssertTrue(SocialGridProjectionPolicy.includes(posted))
        XCTAssertFalse(SocialGridProjectionPolicy.includes(draft))
        XCTAssertFalse(SocialGridProjectionPolicy.includes(unscheduled))
    }

    func testProjectionUsesProfileGridOrderWithNewestFirst() {
        let now = Date()
        let olderID = UUID()
        let newerID = UUID()
        let records = [
            SocialGridProjectionRecord(
                outputID: olderID,
                status: .posted,
                targetDate: nil,
                postedAt: now,
                createdAt: now,
                publishedURLString: ""
            ),
            SocialGridProjectionRecord(
                outputID: newerID,
                status: .scheduled,
                targetDate: now.addingTimeInterval(86_400),
                postedAt: nil,
                createdAt: now,
                publishedURLString: ""
            ),
        ]

        XCTAssertEqual(
            SocialGridProjectionPolicy.orderedRecords(records).map(\.outputID),
            [newerID, olderID]
        )
    }

    func testFiltersSeparatePlannedAndLivePosts() {
        XCTAssertTrue(SocialGridFilter.all.includes(.scheduled))
        XCTAssertTrue(SocialGridFilter.all.includes(.posted))
        XCTAssertTrue(SocialGridFilter.planned.includes(.scheduled))
        XCTAssertFalse(SocialGridFilter.planned.includes(.posted))
        XCTAssertTrue(SocialGridFilter.live.includes(.posted))
        XCTAssertFalse(SocialGridFilter.live.includes(.scheduled))
    }

    func testInstagramURLValidationAcceptsPostLinksAndRejectsOtherHosts() {
        XCTAssertEqual(
            SocialGridURLPolicy.instagramURL(from: "instagram.com/p/example/")?.host,
            "instagram.com"
        )
        XCTAssertEqual(
            SocialGridURLPolicy.instagramURL(from: "https://www.instagram.com/reel/example/")?.host,
            "www.instagram.com"
        )
        XCTAssertNil(SocialGridURLPolicy.instagramURL(from: "https://example.com/post"))
        XCTAssertNil(SocialGridURLPolicy.instagramURL(from: "javascript:alert(1)"))
    }

    func testThumbnailHydrationKeyIsStableAcrossGridReordering() {
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(
            SocialGridThumbnailHydrationPolicy.taskKey(
                workspaceKey: "workspace",
                linkedPostedOutputIDs: [first, second]
            ),
            SocialGridThumbnailHydrationPolicy.taskKey(
                workspaceKey: "workspace",
                linkedPostedOutputIDs: [second, first]
            )
        )
    }

    func testThumbnailHydrationKeyChangesForAnotherWorkspaceOrPost() {
        let outputID = UUID()
        let base = SocialGridThumbnailHydrationPolicy.taskKey(
            workspaceKey: "first-workspace",
            linkedPostedOutputIDs: [outputID]
        )

        XCTAssertNotEqual(
            base,
            SocialGridThumbnailHydrationPolicy.taskKey(
                workspaceKey: "second-workspace",
                linkedPostedOutputIDs: [outputID]
            )
        )
        XCTAssertNotEqual(
            base,
            SocialGridThumbnailHydrationPolicy.taskKey(
                workspaceKey: "first-workspace",
                linkedPostedOutputIDs: [outputID, UUID()]
            )
        )
    }

    func testOrderRepairsMalformedDuplicateAndUnknownStoredIdentifiers() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let state = SocialGridOrderState(
            savedRawIDs: [second.uuidString, "not-a-uuid", second.uuidString, UUID().uuidString],
            defaultIDs: [first, second, third]
        )

        XCTAssertEqual(state.orderedIDs, [first, third, second])
    }

    func testOrderMovesWithinVisibleFilterAndHonorsBoundaries() {
        let first = UUID()
        let hidden = UUID()
        let second = UUID()
        var state = SocialGridOrderState(savedRawIDs: [], defaultIDs: [first, hidden, second])

        XCTAssertFalse(state.move(first, by: -1, within: [first, second]))
        XCTAssertTrue(state.move(first, by: 1, within: [first, second]))
        XCTAssertEqual(state.orderedIDs, [second, hidden, first])
        XCTAssertFalse(state.move(first, by: 1, within: [second, first]))
    }

    func testOrderPreferencesRoundTripPerWorkspace() throws {
        let firstWorkspace = UUID().uuidString
        let secondWorkspace = UUID().uuidString
        let firstPost = UUID().uuidString
        let secondPost = UUID().uuidString
        let store = SocialGridOrderPreferencesStore(
            orderByWorkspace: [
                firstWorkspace: [firstPost],
                secondWorkspace: [secondPost],
            ]
        )

        let encoded = try XCTUnwrap(store.encoded())
        XCTAssertEqual(SocialGridOrderPreferencesStore.decode(encoded), store)
        XCTAssertNil(SocialGridOrderPreferencesStore.decode("not-json"))
    }
}
