import XCTest
@testable import AgentCy

final class PageMain01Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testTodayTaskPolicyExcludesArchivedLinkedWorkAndInactiveTasks() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 10
        )))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        XCTAssertTrue(HomeTodayTaskPolicy.includes(
            isCompleted: false,
            isSkipped: false,
            isTopLevel: true,
            targetDate: today,
            dailyFocusDate: nil,
            isLinkedToArchivedBrief: false,
            referenceDate: today,
            calendar: calendar
        ))
        XCTAssertFalse(HomeTodayTaskPolicy.includes(
            isCompleted: false,
            isSkipped: false,
            isTopLevel: true,
            targetDate: today,
            dailyFocusDate: nil,
            isLinkedToArchivedBrief: true,
            referenceDate: today,
            calendar: calendar
        ))
        XCTAssertFalse(HomeTodayTaskPolicy.includes(
            isCompleted: true,
            isSkipped: false,
            isTopLevel: true,
            targetDate: today,
            dailyFocusDate: nil,
            isLinkedToArchivedBrief: false,
            referenceDate: today,
            calendar: calendar
        ))
        XCTAssertFalse(HomeTodayTaskPolicy.includes(
            isCompleted: false,
            isSkipped: false,
            isTopLevel: false,
            targetDate: today,
            dailyFocusDate: nil,
            isLinkedToArchivedBrief: false,
            referenceDate: today,
            calendar: calendar
        ))
        XCTAssertFalse(HomeTodayTaskPolicy.includes(
            isCompleted: false,
            isSkipped: false,
            isTopLevel: true,
            targetDate: tomorrow,
            dailyFocusDate: nil,
            isLinkedToArchivedBrief: false,
            referenceDate: today,
            calendar: calendar
        ))
    }

    func testRecentlyPostedPolicyExcludesArchivedBriefs() {
        XCTAssertTrue(HomeRecentlyPostedPolicy.includes(
            briefStatus: .posted,
            outputStatus: .draft
        ))
        XCTAssertTrue(HomeRecentlyPostedPolicy.includes(
            briefStatus: .ready,
            outputStatus: .posted
        ))
        XCTAssertFalse(HomeRecentlyPostedPolicy.includes(
            briefStatus: .archived,
            outputStatus: .posted
        ))
        XCTAssertFalse(HomeRecentlyPostedPolicy.includes(
            briefStatus: .ready,
            outputStatus: .scheduled
        ))
    }

    func testDashboardClockUsesTheProvidedInstantForDayAndGreeting() throws {
        let beforeMidnight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 23,
            minute: 59
        )))
        let afterMidnight = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: beforeMidnight))
        let afternoon = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 14
        )))

        XCTAssertNotEqual(
            HomeDashboardClockPolicy.day(for: beforeMidnight, calendar: calendar),
            HomeDashboardClockPolicy.day(for: afterMidnight, calendar: calendar)
        )
        XCTAssertEqual(
            HomeDashboardClockPolicy.greeting(for: afternoon, calendar: calendar),
            "Good afternoon"
        )
    }

    func testHomeEntryPointsUseTheShellPresentationOwner() {
        XCTAssertEqual(HomeDashboardPresentationPolicy.weeklyFocusSheet, .weeklyFocus)
        XCTAssertEqual(HomeDashboardPresentationPolicy.activityCenterSheet, .activityCenter)
    }

    // PERF-RISK-09 repair: Home's scope filter must resolve the active
    // workspace once per pass — with results identical to per-element
    // WorkspaceScope.includes — instead of re-resolving per record.
    func testHomeScopeFilterMatchesWorkspaceScopeSemantics() {
        let profileID = UUID()
        let active = CreatorWorkspace(profileID: profileID, name: "Active", sortOrder: 0)
        let other = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let workspaces = [active, other]

        let ownedByActive = CreatorTask(title: "Owned")
        ownedByActive.workspaceID = active.id
        let ownedByOther = CreatorTask(title: "Foreign")
        ownedByOther.workspaceID = other.id
        let legacy = CreatorTask(title: "Legacy")
        legacy.workspaceID = nil
        let values = [ownedByActive, ownedByOther, legacy]

        for preferred in [active.id, other.id, nil] {
            let fast = HomeWorkspaceScopePolicy.scoped(
                values,
                preferredWorkspaceID: preferred,
                workspaces: workspaces
            ).map(\.id)
            let reference = values.filter {
                WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: preferred,
                    workspaces: workspaces
                )
            }.map(\.id)
            XCTAssertEqual(fast, reference, "Mismatch for preferred=\(String(describing: preferred))")
        }
    }

    func testHomeScopeFilterWithNoWorkspacesKeepsOnlyUnownedRecords() {
        let owned = CreatorTask(title: "Owned")
        owned.workspaceID = UUID()
        let legacy = CreatorTask(title: "Legacy")
        legacy.workspaceID = nil

        let scoped = HomeWorkspaceScopePolicy.scoped(
            [owned, legacy],
            preferredWorkspaceID: nil,
            workspaces: []
        )
        XCTAssertEqual(scoped.map(\.id), [legacy.id])
    }

    func testReducedMotionDoesNotKeepTheHomeLogoTimelineAlive() {
        XCTAssertFalse(CyAnimatedLogoMotionPolicy.usesTimeline(reduceMotion: true))
        XCTAssertTrue(CyAnimatedLogoMotionPolicy.usesTimeline(reduceMotion: false))
    }

    func testActivityBadgeStaysBoundedAndCapsItsVisualCount() {
        XCTAssertEqual(HomeActivityBadgePolicy.displayText(unreadCount: 1), "1")
        XCTAssertEqual(HomeActivityBadgePolicy.displayText(unreadCount: 12), "9+")
        XCTAssertEqual(HomeActivityBadgePolicy.maximumDynamicTypeSize, .large)
    }
}
