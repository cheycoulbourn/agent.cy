import XCTest
@testable import AgentCy

final class DashboardWidgetLayoutTests: XCTestCase {
    func testDefaultLayoutContainsEveryWidgetOnce() {
        let layout = DashboardWidgetLayoutState()

        XCTAssertEqual(layout.orderedCards, HomeDashboardCard.defaultOrder)
        XCTAssertTrue(layout.hiddenCards.isEmpty)
        assertValid(layout)
    }

    func testRestoreRepairsDuplicatesUnknownValuesAndHiddenConflicts() {
        let layout = DashboardWidgetLayoutState(
            savedOrderRawValues: [
                HomeDashboardCard.tasks.rawValue,
                "removed-widget",
                HomeDashboardCard.tasks.rawValue,
                HomeDashboardCard.scheduledToday.rawValue,
            ],
            savedHiddenRawValues: [
                HomeDashboardCard.scheduledToday.rawValue,
                HomeDashboardCard.recentIdeas.rawValue,
                "unknown-hidden-widget",
            ]
        )

        XCTAssertEqual(layout.orderedCards.first, .tasks)
        XCTAssertFalse(layout.orderedCards.contains(.scheduledToday))
        XCTAssertFalse(layout.orderedCards.contains(.recentIdeas))
        XCTAssertEqual(layout.hiddenCards, [.scheduledToday, .recentIdeas])
        assertValid(layout)
    }

    func testHideRestoreAndEmptyDashboardRemainValid() {
        var layout = DashboardWidgetLayoutState()

        XCTAssertTrue(layout.setCard(.tasks, isVisible: false))
        XCTAssertFalse(layout.orderedCards.contains(.tasks))
        XCTAssertTrue(layout.hiddenCards.contains(.tasks))
        XCTAssertFalse(layout.setCard(.tasks, isVisible: false))

        XCTAssertTrue(layout.setCard(.tasks, isVisible: true))
        XCTAssertEqual(layout.orderedCards.last, .tasks)
        XCTAssertFalse(layout.hiddenCards.contains(.tasks))
        XCTAssertFalse(layout.setCard(.tasks, isVisible: true))

        for card in HomeDashboardCard.defaultOrder {
            _ = layout.setCard(card, isVisible: false)
        }
        XCTAssertTrue(layout.orderedCards.isEmpty)
        XCTAssertEqual(layout.hiddenCards, Set(HomeDashboardCard.defaultOrder))
        assertValid(layout)
    }

    func testMoveControlsRespectBoundaries() {
        var layout = DashboardWidgetLayoutState()
        let eligibleCards = layout.orderedCards

        XCTAssertFalse(layout.moveCard(.scheduledToday, by: -1, within: eligibleCards))
        XCTAssertFalse(layout.moveCard(.brandCabinet, by: 1, within: eligibleCards))
        XCTAssertTrue(layout.moveCard(.tasks, by: -1, within: eligibleCards))
        XCTAssertEqual(layout.orderedCards.prefix(3), [.scheduledToday, .tasks, .continueWorking])
        assertValid(layout)
    }

    func testMoveKeepsUnavailableWidgetSlotStable() {
        var layout = DashboardWidgetLayoutState(
            savedOrderRawValues: [
                HomeDashboardCard.scheduledToday.rawValue,
                HomeDashboardCard.brandCabinet.rawValue,
                HomeDashboardCard.tasks.rawValue,
                HomeDashboardCard.recentIdeas.rawValue,
            ]
        )
        let eligibleCards = layout.orderedCards.filter { $0 != .brandCabinet }

        XCTAssertTrue(layout.moveCard(.recentIdeas, by: -1, within: eligibleCards))
        XCTAssertEqual(layout.orderedCards.first, .scheduledToday)
        XCTAssertEqual(layout.orderedCards[1], .brandCabinet)
        XCTAssertEqual(layout.orderedCards[2], .recentIdeas)
        XCTAssertEqual(layout.orderedCards[3], .tasks)
        XCTAssertFalse(layout.moveCard(.brandCabinet, by: -1, within: eligibleCards))
        assertValid(layout)
    }

    func testPreferencesRoundTripPerWorkspaceAndMalformedStorageFallsBackSafely() throws {
        var firstLayout = DashboardWidgetLayoutState()
        _ = firstLayout.setCard(.tasks, isVisible: false)
        var secondLayout = DashboardWidgetLayoutState()
        _ = secondLayout.moveCard(.recentIdeas, by: -1, within: secondLayout.orderedCards)

        var preferences = DashboardWidgetPreferencesStore()
        preferences.layoutsByWorkspace["first"] = firstLayout.snapshot
        preferences.layoutsByWorkspace["second"] = secondLayout.snapshot

        let encoded = try XCTUnwrap(preferences.encoded())
        let decoded = try XCTUnwrap(DashboardWidgetPreferencesStore.decode(encoded))
        XCTAssertEqual(DashboardWidgetLayoutState(snapshot: try XCTUnwrap(decoded.layoutsByWorkspace["first"])), firstLayout)
        XCTAssertEqual(DashboardWidgetLayoutState(snapshot: try XCTUnwrap(decoded.layoutsByWorkspace["second"])), secondLayout)
        XCTAssertNil(DashboardWidgetPreferencesStore.decode("{not-json"))
        XCTAssertEqual(DashboardWidgetPreferencesStore.decodeLegacyMap("{not-json"), [:])
    }

    func testTwoHundredCustomizationOperationsKeepLayoutConsistent() {
        var layout = DashboardWidgetLayoutState()

        for index in 0..<200 {
            let card = HomeDashboardCard.defaultOrder[index % HomeDashboardCard.defaultOrder.count]
            switch index % 4 {
            case 0:
                _ = layout.setCard(card, isVisible: false)
            case 1:
                _ = layout.setCard(card, isVisible: true)
            case 2:
                _ = layout.moveCard(card, by: -1, within: layout.orderedCards)
            default:
                _ = layout.moveCard(card, by: 1, within: layout.orderedCards)
            }
            assertValid(layout, file: #filePath, line: #line)
        }

        let snapshot = layout.snapshot
        XCTAssertEqual(DashboardWidgetLayoutState(snapshot: snapshot), layout)
    }

    private func assertValid(
        _ layout: DashboardWidgetLayoutState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(layout.orderedCards).count, layout.orderedCards.count, file: file, line: line)
        XCTAssertTrue(Set(layout.orderedCards).isDisjoint(with: layout.hiddenCards), file: file, line: line)
        XCTAssertEqual(
            Set(layout.orderedCards).union(layout.hiddenCards),
            Set(HomeDashboardCard.defaultOrder),
            file: file,
            line: line
        )
    }
}
