import UIKit
import XCTest
@testable import AgentCy

// Creator request 2026-08-19: the checkbox top must rest on the title's cap
// line across Tasks, Home, Quick Capture, the desktop Control Center, and
// widgets — not on the line-box top, which floats the box above the letters.
final class TaskCheckboxAlignmentTests: XCTestCase {
    func testCheckboxBaselineGuideEqualsScaledCapHeight() {
        let base = UIFont(name: "InterVariable", size: 15) ?? .systemFont(ofSize: 15)
        let expected = UIFontMetrics(forTextStyle: .body).scaledFont(for: base).capHeight
        XCTAssertEqual(
            AgentTaskCheckboxAlignment.baselineGuide(titlePointSize: 15),
            expected,
            accuracy: 0.001,
            "Guide must place the box top exactly a cap height above the baseline"
        )
        XCTAssertGreaterThan(AgentTaskCheckboxAlignment.baselineGuide(titlePointSize: 15), 0)
    }

    func testCheckboxBaselineGuideTracksTitleSize() {
        XCTAssertLessThan(
            AgentTaskCheckboxAlignment.baselineGuide(titlePointSize: 13),
            AgentTaskCheckboxAlignment.baselineGuide(titlePointSize: 15),
            "Smaller titles need a shorter drop to their cap line"
        )
    }
}

final class PageMain03Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    func testTaskOwnedDateNeverFallsBackToLinkedPostPlacement() throws {
        let focusDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18
        )))
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19,
            hour: 9
        )))

        XCTAssertEqual(
            TaskRootDatePolicy.taskOwnedDate(targetDate: dueDate, dailyFocusDate: focusDate),
            dueDate
        )
        XCTAssertEqual(
            TaskRootDatePolicy.taskOwnedDate(targetDate: nil, dailyFocusDate: focusDate),
            focusDate
        )
        XCTAssertNil(TaskRootDatePolicy.taskOwnedDate(targetDate: nil, dailyFocusDate: nil))
    }

    func testRootKeepsPostTasksAndHistoryReachableOutsideTheCurrentWeek() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 12
        )))
        let farFuture = try XCTUnwrap(calendar.date(byAdding: .day, value: 30, to: now))

        XCTAssertTrue(TaskRootVisibilityPolicy.includes(
            collection: .postTasks,
            isCompleted: false,
            isArchived: false,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: nil,
            taskOwnedDate: farFuture,
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(TaskRootVisibilityPolicy.includes(
            collection: .myTasks,
            isCompleted: true,
            isArchived: false,
            focusTaskTemplateID: UUID(),
            recurrence: .weekly,
            recurrenceRootTaskID: UUID(),
            taskOwnedDate: farFuture,
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(TaskRootVisibilityPolicy.includes(
            collection: .myTasks,
            isCompleted: false,
            isArchived: false,
            focusTaskTemplateID: nil,
            recurrence: .weekly,
            recurrenceRootTaskID: UUID(),
            taskOwnedDate: farFuture,
            now: now,
            calendar: calendar
        ))
    }

    func testOutputOnlyTaskInheritsArchivedBriefState() {
        let outputID = UUID()
        let archivedBriefID = UUID()

        XCTAssertEqual(
            TaskRootLinkPolicy.linkedBriefID(
                taskBriefID: nil,
                platformOutputID: outputID,
                outputBriefIDs: [outputID: archivedBriefID]
            ),
            archivedBriefID
        )
        XCTAssertTrue(TaskRootLinkPolicy.isArchived(
            taskBriefID: nil,
            platformOutputID: outputID,
            outputBriefIDs: [outputID: archivedBriefID],
            archivedBriefIDs: [archivedBriefID]
        ))
    }

    func testThisWeekUsesTheSameMondayWindowInSundayFirstLocales() throws {
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 12
        )))
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 23,
            hour: 18
        )))
        let priorSunday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 16,
            hour: 18
        )))
        let nextMonday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24
        )))

        XCTAssertTrue(TaskListFilterPolicy.matchesDate(
            sunday,
            filter: .thisWeek,
            selectedDate: tuesday,
            now: tuesday,
            calendar: calendar
        ))
        XCTAssertFalse(TaskListFilterPolicy.matchesDate(
            priorSunday,
            filter: .thisWeek,
            selectedDate: tuesday,
            now: tuesday,
            calendar: calendar
        ))
        XCTAssertFalse(TaskListFilterPolicy.matchesDate(
            nextMonday,
            filter: .thisWeek,
            selectedDate: tuesday,
            now: tuesday,
            calendar: calendar
        ))
    }

    func testDueDatePresentationChangesAcrossMidnightFromOneReferenceClock() throws {
        let dueDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18
        )))
        let beforeMidnight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 23,
            minute: 59
        )))
        let afterMidnight = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: beforeMidnight))

        XCTAssertEqual(
            TaskDueDatePresentation.title(for: dueDay, now: beforeMidnight, calendar: calendar),
            "Today"
        )
        XCTAssertEqual(
            TaskDueDatePresentation.title(for: dueDay, now: afterMidnight, calendar: calendar),
            "Past due · Tuesday, Aug 18"
        )
        XCTAssertFalse(TaskDueDatePresentation.isPastDue(dueDay, now: beforeMidnight, calendar: calendar))
        XCTAssertTrue(TaskDueDatePresentation.isPastDue(dueDay, now: afterMidnight, calendar: calendar))
    }

    func testTaskCollectionAnimationStopsUnderReduceMotion() {
        XCTAssertFalse(TaskRootMotionPolicy.usesCollectionAnimation(reduceMotion: true))
        XCTAssertTrue(TaskRootMotionPolicy.usesCollectionAnimation(reduceMotion: false))
    }

    func testAccessibilityPresentationStacksMetadataAndCapsFixedBadges() {
        XCTAssertEqual(TaskRootAccessibilityPolicy.maximumFixedControlDynamicTypeSize, .large)
        XCTAssertTrue(TaskRootAccessibilityPolicy.usesStackedMetadata(dynamicTypeSize: .accessibility1))
        XCTAssertFalse(TaskRootAccessibilityPolicy.usesStackedMetadata(dynamicTypeSize: .large))
        XCTAssertEqual(TaskRootAccessibilityPolicy.taskTitleLineLimit(dynamicTypeSize: .accessibility1), 3)
        XCTAssertEqual(TaskRootAccessibilityPolicy.taskTitleLineLimit(dynamicTypeSize: .large), 2)
        XCTAssertEqual(
            TaskRootAccessibilityPolicy.groupLabel(title: "Today", taskCount: 2),
            "Today, 2 tasks"
        )
        XCTAssertEqual(
            TaskRootAccessibilityPolicy.groupLabel(title: "No due date", taskCount: 1),
            "No due date, 1 task"
        )
    }

    func testTaskRowsResolveTheCanonicalDetailRoute() {
        let taskID = UUID()

        XCTAssertEqual(TaskRootNavigationPolicy.route(for: taskID).taskID, taskID)
    }
}
