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
        XCTAssertEqual(DesktopNavigationDestination.plan.title, "Agenda")
        XCTAssertTrue(
            DesktopNavigationPolicy.sidebarSections
                .flatMap(\.destinations)
                .contains(.tasks),
            "Tasks is a primary desktop destination and must remain visible in the sidebar."
        )
        XCTAssertTrue(
            DesktopNavigationPolicy.sidebarSections
                .flatMap(\.destinations)
                .contains(.pillars),
            "Pillars must remain visible in the menu sidebar."
        )
        XCTAssertTrue(
            DesktopNavigationPolicy.sidebarSections
                .flatMap(\.destinations)
                .contains(.savedPosts),
            "Saved Posts must remain visible in the menu sidebar."
        )
    }

    func testAgendaListDefaultsToOpenPosts() {
        XCTAssertEqual(AgendaListStatusFilter.defaultFilter, .open)
    }

    func testDesktopLayoutKeepsUtilityRailForWideWindows() {
        let metrics = DesktopLayoutPolicy.metrics(forWindowWidth: 1_440)

        XCTAssertEqual(metrics.leadingSidebarWidth, 220)
        XCTAssertEqual(metrics.utilitySidebarWidth, 344)
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
        let approvedMetrics = DesktopSheetMetrics(width: 900, height: 860)
        XCTAssertEqual(DesktopLayoutPolicy.workspaceModalMetrics, approvedMetrics)
        XCTAssertEqual(DesktopLayoutPolicy.sheetMetrics(for: .quickCapture), approvedMetrics)
        XCTAssertEqual(DesktopLayoutPolicy.sheetMetrics(for: .settings), approvedMetrics)
        XCTAssertEqual(DesktopLayoutPolicy.sheetMetrics(for: .askCy), approvedMetrics)
    }

    // Creator feedback 2026-08-19: post cards in the Cy review sidebar
    // truncated their pillar names at the standard 900pt width. Cy hosts a
    // sidebar plus a detail pane, so it is the one sheet that needs more room.
    func testCySizesItselfAndOnlyTheReviewWorkspaceIsWider() {
        XCTAssertTrue(DesktopLayoutPolicy.sizesItself(.askCy))
        XCTAssertFalse(DesktopLayoutPolicy.sizesItself(.settings))

        let review = DesktopLayoutPolicy.cyReviewModalMetrics
        XCTAssertEqual(review, DesktopSheetMetrics(width: 1_180, height: 860))
        XCTAssertGreaterThan(review.width, DesktopLayoutPolicy.workspaceModalMetrics.width)
        XCTAssertEqual(review.height, DesktopLayoutPolicy.workspaceModalMetrics.height)
        // Chat keeps the standard footprint.
        XCTAssertEqual(DesktopLayoutPolicy.sheetMetrics(for: .askCy), DesktopLayoutPolicy.workspaceModalMetrics)
    }

    // Creator feedback 2026-08-19: the Quick Add modal felt oversized and
    // uncentered. The menu stage is a compact choice card sized to its five
    // options; only the embedded capture flows need the canonical workspace
    // footprint.
    func testQuickAddMenuIsACompactCardAndCaptureKeepsTheWorkspaceFootprint() {
        let menu = DesktopLayoutPolicy.creationHubMetrics(stage: .menu)
        XCTAssertEqual(menu, DesktopSheetMetrics(width: 600, height: 560))
        XCTAssertEqual(
            DesktopLayoutPolicy.creationHubMetrics(stage: .capture),
            DesktopLayoutPolicy.workspaceModalMetrics
        )
    }

    func testDesktopHomeWidgetsAlwaysUseOneColumn() {
        XCTAssertEqual(DesktopHomeWidgetColumnPolicy.columnCount, 1)
    }

    func testDesktopTypographyUsesACompactDescendingScale() {
        XCTAssertEqual(DesktopTypographyScale.utilityTitle, 17)
        XCTAssertEqual(DesktopTypographyScale.quickAction, 16)
        XCTAssertEqual(DesktopTypographyScale.navigation, 15)
        XCTAssertEqual(DesktopTypographyScale.utilityBody, 14)
        XCTAssertEqual(DesktopTypographyScale.utilityAction, 13)
        XCTAssertEqual(DesktopTypographyScale.utilityMetadata, 12)

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
        let hiddenWidgets: Set<DesktopUtilityWidget> = [.upcomingPosts, .tasks]
        let storageValue = DesktopUtilityWidgetVisibilityPolicy.storageValue(for: hiddenWidgets)

        XCTAssertEqual(storageValue, "v2:tasks,upcomingPosts")
        XCTAssertEqual(
            DesktopUtilityWidgetVisibilityPolicy.hiddenWidgets(from: storageValue),
            hiddenWidgets
        )
        let legacyHidden = DesktopUtilityWidgetVisibilityPolicy.hiddenWidgets(
            from: "tasks,savedPosts,pillars"
        )
        XCTAssertTrue(legacyHidden.contains(.tasks))
        XCTAssertTrue(DesktopUtilityWidget.optionalWidgets.isSubset(of: legacyHidden))
    }

    func testDesktopUtilitySidebarOffersFocusedPlanningAndLibraryWidgets() {
        XCTAssertEqual(
            DesktopUtilityWidget.allCases,
            [
                .tasks, .upcomingPosts, .ideas, .pillarUsage, .needsNewDate,
                .cyNoticed, .weekAtAGlance, .consistency, .recentlyPosted,
                .draftsInProgress, .brandCabinet, .weeklyFocus,
            ]
        )
        XCTAssertEqual(DesktopUtilityWidgetContentPolicy.ideaPreviewLimit, 3)
        XCTAssertEqual(DesktopUtilityWidgetContentPolicy.taskPreviewLimit, 3)
        XCTAssertFalse(DesktopUtilityWidget.optionalWidgets.contains(.cyNoticed))
        XCTAssertNil(DesktopUtilityWidget.cyNoticed.icon)
    }

    func testDesktopUtilityWidgetOrderRestoresSavedOrderAndAddsNewWidgets() {
        XCTAssertEqual(
            DesktopUtilityWidgetOrderPolicy.orderedWidgets(
                from: "savedPosts,pillars,tasks,ideas"
            ),
            [
                .tasks, .ideas, .upcomingPosts, .pillarUsage, .needsNewDate,
                .cyNoticed, .weekAtAGlance, .consistency, .recentlyPosted,
                .draftsInProgress, .brandCabinet, .weeklyFocus,
            ]
        )
    }

    func testDesktopUtilityWidgetOrderRemovesDuplicatesAndRoundTrips() {
        let widgets: [DesktopUtilityWidget] = [.ideas, .tasks, .upcomingPosts]
        let stored = DesktopUtilityWidgetOrderPolicy.storageValue(for: widgets)

        XCTAssertEqual(stored, "ideas,tasks,upcomingPosts")
        XCTAssertEqual(
            DesktopUtilityWidgetOrderPolicy.orderedWidgets(from: stored),
            widgets + DesktopUtilityWidget.allCases.filter { !widgets.contains($0) }
        )
        XCTAssertEqual(
            DesktopUtilityWidgetOrderPolicy.orderedWidgets(from: "tasks,tasks"),
            [.tasks] + DesktopUtilityWidget.allCases.filter { $0 != .tasks }
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
        XCTAssertNotEqual(DesktopNavigationDestination.savedPosts.icon, DesktopNavigationDestination.ideaBank.icon)
    }

    func testFeedUsesTheSharedInstagramCameraIcon() {
        XCTAssertEqual(DesktopNavigationDestination.feed.icon, .instagramCamera)
    }

}
