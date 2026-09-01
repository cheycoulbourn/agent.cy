import XCTest
@testable import AgentCy

@MainActor
final class PagePlan07Tests: XCTestCase {
    func testFocusDetailPreviewRouteRequiresItsExplicitArgument() {
        XCTAssertFalse(PlanRuntimeFixture.requestsDailyFocusDetail(arguments: []))
        XCTAssertTrue(PlanRuntimeFixture.requestsDailyFocusDetail(
            arguments: ["agent.cy", "-agentCyPreviewDailyFocusDetail"]
        ))
    }

    func testFocusDetailUsesOneCanonicalTaskOwnedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 13
        )))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 17
        )))
        let task = CreatorTask(
            title: "Draft the hook",
            targetDate: friday,
            dailyFocusDate: monday
        )

        XCTAssertFalse(DailyFocusTaskProjection.includes(task, on: monday, calendar: calendar))
        XCTAssertTrue(DailyFocusTaskProjection.includes(task, on: friday, calendar: calendar))
    }

    func testFocusDetailExcludesPostTasksSkippedTasksAndSubtasks() {
        let day = Date(timeIntervalSince1970: 1_721_001_600)
        let postTask = CreatorTask(briefID: UUID(), title: "Film post", targetDate: day)
        let skippedTask = CreatorTask(title: "Skipped", targetDate: day)
        skippedTask.isSkipped = true
        let subtask = CreatorTask(parentTaskID: UUID(), title: "Child", targetDate: day)

        XCTAssertFalse(DailyFocusTaskProjection.includes(postTask, on: day))
        XCTAssertFalse(DailyFocusTaskProjection.includes(skippedTask, on: day))
        XCTAssertFalse(DailyFocusTaskProjection.includes(subtask, on: day))
    }

    func testNewestFocusOverrideWinsForTheDisplayedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 13
        )))
        let olderFocus = DailyFocusOverride(
            date: monday,
            kind: .planning,
            title: "Planning",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        olderFocus.updatedAt = Date(timeIntervalSince1970: 200)
        let newerRest = DailyFocusOverride(
            date: monday,
            isCleared: true,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        newerRest.updatedAt = Date(timeIntervalSince1970: 400)

        XCTAssertNil(DailyFocusResolver.resolve(
            date: monday,
            templates: [],
            overrides: [olderFocus, newerRest],
            calendar: calendar
        ))
        XCTAssertNil(DailyFocusResolver.resolve(
            date: monday,
            templates: [],
            overrides: [newerRest, olderFocus],
            calendar: calendar
        ))
    }

    func testNewestSavedDayDetailWinsInEitherFetchOrder() {
        let day = Date(timeIntervalSince1970: 1_721_001_600)
        let older = DailyFocusDayDetail(
            date: day,
            note: "Old note",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        older.updatedAt = Date(timeIntervalSince1970: 200)
        let newer = DailyFocusDayDetail(
            date: day,
            note: "Current note",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        newer.updatedAt = Date(timeIntervalSince1970: 400)

        XCTAssertEqual(
            DailyFocusDayDetailIndex.canonical(on: day, from: [older, newer])?.id,
            newer.id
        )
        XCTAssertEqual(
            DailyFocusDayDetailIndex.canonical(on: day, from: [newer, older])?.id,
            newer.id
        )
    }
}
