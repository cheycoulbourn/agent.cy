import XCTest
@testable import AgentCy

final class DesktopNavigationTests: XCTestCase {
    func testDesktopSidebarUsesPlanningFirstInformationArchitecture() {
        XCTAssertEqual(
            DesktopNavigationPolicy.sidebarSections,
            [
                DesktopNavigationSection(
                    title: "Plan",
                    destinations: [.home, .plan, .feed, .tasks, .pillars]
                ),
                DesktopNavigationSection(
                    title: "Library",
                    destinations: [.ideaBank, .savedPosts]
                ),
            ]
        )
        XCTAssertEqual(DesktopNavigationPolicy.defaultDestination, .plan)
        XCTAssertTrue(
            DesktopNavigationPolicy.sidebarSections
                .flatMap(\.destinations)
                .contains(.tasks),
            "Tasks is a primary desktop destination and must remain visible in the sidebar."
        )
    }

    func testDesktopLayoutKeepsUtilityRailForWideWindows() {
        let metrics = DesktopLayoutPolicy.metrics(forWindowWidth: 1_440)

        XCTAssertEqual(metrics.leadingSidebarWidth, 220)
        XCTAssertEqual(metrics.utilitySidebarWidth, 320)
        XCTAssertEqual(metrics.contentMaximumWidth, 1_040)
        XCTAssertEqual(metrics.contentHorizontalPadding, 32)
        XCTAssertTrue(metrics.showsUtilitySidebar)
    }

    func testDesktopLayoutReclaimsUtilityRailSpaceInNarrowWindows() {
        let metrics = DesktopLayoutPolicy.metrics(forWindowWidth: 1_100)

        XCTAssertEqual(metrics.leadingSidebarWidth, 208)
        XCTAssertEqual(metrics.utilitySidebarWidth, 0)
        XCTAssertEqual(metrics.contentMaximumWidth, 960)
        XCTAssertEqual(metrics.contentHorizontalPadding, 24)
        XCTAssertFalse(metrics.showsUtilitySidebar)
    }

    func testDesktopSheetSizingMakesQuickActionsAWorkspaceInsteadOfAPhoneCard() {
        XCTAssertEqual(
            DesktopLayoutPolicy.sheetMetrics(for: .creationHub),
            DesktopSheetMetrics(width: 780, height: 720)
        )
        XCTAssertEqual(
            DesktopLayoutPolicy.sheetMetrics(for: .askCy),
            DesktopSheetMetrics(width: 760, height: 780)
        )
    }

    func testDesktopHomeWidgetsAlwaysUseOneColumn() {
        XCTAssertEqual(DesktopHomeWidgetColumnPolicy.columnCount, 1)
    }

    func testDesktopTypographyUsesACompactDescendingScale() {
        XCTAssertEqual(DesktopTypographyScale.utilityTitle, 16)
        XCTAssertEqual(DesktopTypographyScale.quickAction, 15)
        XCTAssertEqual(DesktopTypographyScale.navigation, 13)
        XCTAssertEqual(DesktopTypographyScale.utilityBody, 13)
        XCTAssertEqual(DesktopTypographyScale.utilityAction, 12)
        XCTAssertEqual(DesktopTypographyScale.utilityMetadata, 11)

        XCTAssertGreaterThan(
            DesktopTypographyScale.utilityTitle,
            DesktopTypographyScale.utilityBody
        )
        XCTAssertGreaterThan(
            DesktopTypographyScale.utilityBody,
            DesktopTypographyScale.utilityMetadata
        )
    }

    func testDesktopUtilityWidgetVisibilityRoundTripsInStableOrder() {
        let hiddenWidgets: Set<DesktopUtilityWidget> = [.savedPosts, .tasks]
        let storageValue = DesktopUtilityWidgetVisibilityPolicy.storageValue(for: hiddenWidgets)

        XCTAssertEqual(storageValue, "tasks,savedPosts")
        XCTAssertEqual(
            DesktopUtilityWidgetVisibilityPolicy.hiddenWidgets(from: storageValue),
            hiddenWidgets
        )
    }

    func testDesktopUtilitySidebarOffersFocusedPlanningAndLibraryWidgets() {
        XCTAssertEqual(
            DesktopUtilityWidget.allCases,
            [.tasks, .upcomingPosts, .ideas, .savedPosts, .pillars]
        )
        XCTAssertEqual(DesktopUtilityWidgetContentPolicy.ideaPreviewLimit, 3)
    }

    func testDesktopUtilityWidgetOrderRestoresSavedOrderAndAddsNewWidgets() {
        XCTAssertEqual(
            DesktopUtilityWidgetOrderPolicy.orderedWidgets(
                from: "savedPosts,tasks,ideas"
            ),
            [.savedPosts, .tasks, .ideas, .upcomingPosts, .pillars]
        )
    }

    func testDesktopUtilityWidgetOrderRemovesDuplicatesAndRoundTrips() {
        let widgets: [DesktopUtilityWidget] = [.pillars, .tasks, .savedPosts, .ideas, .upcomingPosts]
        let stored = DesktopUtilityWidgetOrderPolicy.storageValue(for: widgets)

        XCTAssertEqual(stored, "pillars,tasks,savedPosts,ideas,upcomingPosts")
        XCTAssertEqual(DesktopUtilityWidgetOrderPolicy.orderedWidgets(from: stored), widgets)
        XCTAssertEqual(
            DesktopUtilityWidgetOrderPolicy.orderedWidgets(from: "tasks,tasks"),
            [.tasks, .upcomingPosts, .ideas, .savedPosts, .pillars]
        )
    }

    func testSavedPostsLibraryIsStrictlyScopedToTheActiveWorkspace() {
        let activeWorkspaceID = UUID()
        let otherWorkspaceID = UUID()

        XCTAssertTrue(
            SavedPostsScopePolicy.includes(
                recordWorkspaceID: activeWorkspaceID,
                activeWorkspaceID: activeWorkspaceID
            )
        )
        XCTAssertFalse(
            SavedPostsScopePolicy.includes(
                recordWorkspaceID: otherWorkspaceID,
                activeWorkspaceID: activeWorkspaceID
            )
        )
        XCTAssertFalse(
            SavedPostsScopePolicy.includes(
                recordWorkspaceID: nil,
                activeWorkspaceID: activeWorkspaceID
            )
        )
        XCTAssertFalse(
            SavedPostsScopePolicy.includes(
                recordWorkspaceID: activeWorkspaceID,
                activeWorkspaceID: nil
            )
        )
    }

    func testDesktopDestinationsRoundTripThroughSharedAppTabs() {
        for tab in AppTab.allCases {
            let destination = DesktopNavigationPolicy.destination(for: tab)
            XCTAssertEqual(destination.appTab, tab)
        }
        XCTAssertNil(DesktopNavigationDestination.feed.appTab)
        XCTAssertNil(DesktopNavigationDestination.savedPosts.appTab)
    }

    func testSavedPostsUsesTheExternalReferenceIcon() {
        XCTAssertEqual(DesktopNavigationDestination.savedPosts.icon, .link)
        XCTAssertEqual(DesktopUtilityWidget.savedPosts.icon, .link)
        XCTAssertNotEqual(DesktopNavigationDestination.savedPosts.icon, DesktopNavigationDestination.ideaBank.icon)
    }

    func testFeedUsesTheSharedInstagramCameraIcon() {
        XCTAssertEqual(DesktopNavigationDestination.feed.icon, .instagramCamera)
    }

}
