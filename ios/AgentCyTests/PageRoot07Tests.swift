import XCTest
@testable import AgentCy

@MainActor
final class PageRoot07Tests: XCTestCase {
    func testAssigningTheSameSharedTabStillCreatesADesktopSelectionRequest() {
        let model = AppModel(reminderService: PreviewReminderService())
        model.selectedTab = .today
        let revision = model.selectedTabRevision

        model.selectedTab = .today

        XCTAssertEqual(model.selectedTabRevision, revision + 1)
        XCTAssertEqual(
            DesktopNavigationPolicy.destination(for: model.selectedTab),
            .plan
        )
    }

    func testMCPReviewDoesNotRepeatOrInterruptAnyDesktopPresentation() {
        let existing = UUID()
        let newRequest = UUID()

        XCTAssertFalse(DesktopShellMCPReviewPolicy.shouldPresent(
            requestIDs: [existing],
            presentedRequestIDs: [existing],
            hasGlobalPresentation: false,
            hasLocalPresentation: false
        ))
        XCTAssertFalse(DesktopShellMCPReviewPolicy.shouldPresent(
            requestIDs: [newRequest],
            presentedRequestIDs: [],
            hasGlobalPresentation: true,
            hasLocalPresentation: false
        ))
        XCTAssertFalse(DesktopShellMCPReviewPolicy.shouldPresent(
            requestIDs: [newRequest],
            presentedRequestIDs: [],
            hasGlobalPresentation: false,
            hasLocalPresentation: true
        ))
        XCTAssertTrue(DesktopShellMCPReviewPolicy.shouldPresent(
            requestIDs: [newRequest],
            presentedRequestIDs: [],
            hasGlobalPresentation: false,
            hasLocalPresentation: false
        ))
    }

    func testMCPResultFromThePreviousWorkspaceIsDiscarded() {
        let previousWorkspaceID = UUID()
        let activeWorkspaceID = UUID()

        XCTAssertTrue(DesktopShellWorkspacePolicy.acceptsMCPResult(
            requestedWorkspaceID: activeWorkspaceID,
            activeWorkspaceID: activeWorkspaceID
        ))
        XCTAssertFalse(DesktopShellWorkspacePolicy.acceptsMCPResult(
            requestedWorkspaceID: previousWorkspaceID,
            activeWorkspaceID: activeWorkspaceID
        ))
    }

    func testQuickAddRemainsAvailableOnBothSidesOfTheUtilityBreakpoint() {
        XCTAssertEqual(
            DesktopLayoutPolicy.quickAddPlacement(forWindowWidth: 1_279),
            .leadingSidebar
        )
        XCTAssertEqual(
            DesktopLayoutPolicy.quickAddPlacement(forWindowWidth: 1_280),
            .utilitySidebar
        )
    }

    func testReduceMotionDisablesUtilityRailTransition() {
        XCTAssertFalse(DesktopShellMotionPolicy.animatesUtilityRail(reduceMotion: true))
        XCTAssertTrue(DesktopShellMotionPolicy.animatesUtilityRail(reduceMotion: false))
    }

    func testDesktopUtilityOutputsExcludeArchivedAndCrossWorkspaceRecords() {
        XCTAssertTrue(DesktopUtilityOutputPolicy.includes(
            briefStatus: .scheduled,
            outputIsInActiveWorkspace: true,
            briefIsInActiveWorkspace: true
        ))
        XCTAssertFalse(DesktopUtilityOutputPolicy.includes(
            briefStatus: .archived,
            outputIsInActiveWorkspace: true,
            briefIsInActiveWorkspace: true
        ))
        XCTAssertFalse(DesktopUtilityOutputPolicy.includes(
            briefStatus: .scheduled,
            outputIsInActiveWorkspace: false,
            briefIsInActiveWorkspace: true
        ))
        XCTAssertFalse(DesktopUtilityOutputPolicy.includes(
            briefStatus: .scheduled,
            outputIsInActiveWorkspace: true,
            briefIsInActiveWorkspace: false
        ))
    }

    func testPendingTaskConsumptionDismissesGlobalPresentationOnce() {
        let model = AppModel(reminderService: PreviewReminderService())
        let taskID = UUID()
        model.presentedSheet = .settings
        model.requestedTaskID = taskID

        XCTAssertEqual(model.consumeRequestedTaskRoute(), taskID)
        XCTAssertNil(model.presentedSheet)
        XCTAssertNil(model.requestedTaskID)
        XCTAssertNil(model.consumeRequestedTaskRoute())
    }
}
