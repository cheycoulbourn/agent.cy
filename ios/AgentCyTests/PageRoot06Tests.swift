import XCTest
@testable import AgentCy

@MainActor
final class PageRoot06Tests: XCTestCase {
    func testSwitchingTabsPreservesTheDestinationStackAndReselectingPopsToRoot() {
        for current in AppTab.allCases {
            for tapped in AppTab.allCases {
                XCTAssertEqual(
                    AppShellNavigationPolicy.shouldResetPath(current: current, tapped: tapped),
                    current == tapped,
                    "current=\(current.rawValue), tapped=\(tapped.rawValue)"
                )
            }
        }
    }

    func testGlobalPresentationsAreMutuallyExclusive() {
        let model = AppModel(reminderService: PreviewReminderService())
        let inspirationRoute = InspirationReviewRoute(id: UUID())

        model.presentedSheet = .quickCapture
        model.inspirationReviewRoute = inspirationRoute

        XCTAssertNil(model.presentedSheet)
        XCTAssertEqual(model.inspirationReviewRoute, inspirationRoute)

        model.presentedSheet = .settings

        XCTAssertEqual(model.presentedSheet, .settings)
        XCTAssertNil(model.inspirationReviewRoute)
    }

    func testPendingTaskRouteDismissesPresentationAndIsConsumedOnce() {
        let model = AppModel(reminderService: PreviewReminderService())
        let taskID = UUID()
        model.presentedSheet = .quickCapture
        model.requestedTaskID = taskID

        XCTAssertEqual(model.consumeRequestedTaskRoute(), taskID)
        XCTAssertNil(model.presentedSheet)
        XCTAssertNil(model.inspirationReviewRoute)
        XCTAssertNil(model.requestedTaskID)
        XCTAssertNil(model.consumeRequestedTaskRoute())
    }

    func testWorkspaceSwitchClearsRecordScopedShellStateButKeepsSettings() {
        let model = AppModel(reminderService: PreviewReminderService())
        model.requestedTaskID = UUID()
        model.inspirationReviewRoute = InspirationReviewRoute(id: UUID())

        model.prepareShellForWorkspaceSwitch()

        XCTAssertNil(model.requestedTaskID)
        XCTAssertNil(model.inspirationReviewRoute)

        model.presentedSheet = .askCy
        model.prepareShellForWorkspaceSwitch()
        XCTAssertNil(model.presentedSheet)

        model.presentedSheet = .settings
        model.prepareShellForWorkspaceSwitch()
        XCTAssertEqual(model.presentedSheet, .settings)
    }

    func testReduceMotionUsesAStaticPlanningCue() {
        XCTAssertFalse(AppShellMotionPolicy.shouldRunContinuousPlanningCue(reduceMotion: true))
        XCTAssertTrue(AppShellMotionPolicy.shouldRunContinuousPlanningCue(reduceMotion: false))
    }

    func testMCPReviewDoesNotRepeatOrInterruptAnotherPresentation() {
        let existing = UUID()
        let newRequest = UUID()

        XCTAssertFalse(AppShellMCPReviewPolicy.shouldPresent(
            requestIDs: [existing],
            presentedRequestIDs: [existing],
            hasGlobalPresentation: false
        ))
        XCTAssertFalse(AppShellMCPReviewPolicy.shouldPresent(
            requestIDs: [newRequest],
            presentedRequestIDs: [],
            hasGlobalPresentation: true
        ))
        XCTAssertTrue(AppShellMCPReviewPolicy.shouldPresent(
            requestIDs: [newRequest],
            presentedRequestIDs: [],
            hasGlobalPresentation: false
        ))
    }

    #if DEBUG
    func testRuntimeFixtureCanRequestAPreviewTaskRoute() {
        XCTAssertFalse(AppShellRuntimeFixture.requestsFirstPreviewTask(
            arguments: ["agent.cy"]
        ))
        XCTAssertTrue(AppShellRuntimeFixture.requestsFirstPreviewTask(
            arguments: ["agent.cy", "-agentCyPreviewTaskRoute"]
        ))
    }
    #endif
}
