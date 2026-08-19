import SwiftData
import XCTest
@testable import AgentCy

final class ConsistencyGoalTests: XCTestCase {

    // Widget request 2026-08-19: consistency counts days of the week against
    // a creator-set weekly posting goal, and the card shows exactly which
    // days landed.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testSnapshotCountsDistinctPostedDaysAgainstTheGoal() {
        let weekStart = date(2026, 8, 17)
        // Two posts on Monday still count as one posted day.
        let snapshot = WeeklyConsistencyPolicy.snapshot(
            postedDates: [date(2026, 8, 17, hour: 8), date(2026, 8, 17, hour: 19), date(2026, 8, 19)],
            goal: 4,
            weekStart: weekStart,
            calendar: calendar,
            today: date(2026, 8, 19)
        )

        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertEqual(snapshot.postedDayCount, 2)
        XCTAssertEqual(snapshot.days.map(\.hasPost), [true, false, true, false, false, false, false])
        XCTAssertTrue(snapshot.days[2].isToday, "Wednesday is today in this fixture")
        XCTAssertEqual(snapshot.days.filter(\.isToday).count, 1)
        XCTAssertEqual(snapshot.goalState, .below)
    }

    func testGoalStates() {
        let weekStart = date(2026, 8, 17)
        let threeDays = [date(2026, 8, 17), date(2026, 8, 18), date(2026, 8, 19)]

        XCTAssertEqual(WeeklyConsistencyPolicy.snapshot(
            postedDates: threeDays, goal: 3, weekStart: weekStart,
            calendar: calendar, today: date(2026, 8, 19)
        ).goalState, .met)

        XCTAssertEqual(WeeklyConsistencyPolicy.snapshot(
            postedDates: threeDays, goal: nil, weekStart: weekStart,
            calendar: calendar, today: date(2026, 8, 19)
        ).goalState, .unset)
    }

    func testGoalStreakCountsConsecutiveGoalWeeksFromTheCurrentWeek() {
        XCTAssertEqual(WeeklyConsistencyPolicy.goalStreak(weeklyPostedDayCounts: [1, 4, 5, 4], goal: 4), 3)
        XCTAssertEqual(WeeklyConsistencyPolicy.goalStreak(weeklyPostedDayCounts: [4, 2, 4], goal: 4), 1)
        XCTAssertEqual(WeeklyConsistencyPolicy.goalStreak(weeklyPostedDayCounts: [4, 4, 1], goal: 4), 0)
    }

    func testWeeklyPostedDayCountsBucketsDistinctDaysPerWeek() {
        let currentWeekStart = date(2026, 8, 17)
        let counts = WeeklyConsistencyPolicy.weeklyPostedDayCounts(
            postedDates: [
                date(2026, 8, 10), date(2026, 8, 10, hour: 20), date(2026, 8, 12),
                date(2026, 8, 17), date(2026, 8, 19)
            ],
            weekCount: 3,
            currentWeekStart: currentWeekStart,
            calendar: calendar
        )
        XCTAssertEqual(counts, [0, 2, 2], "Oldest week first, current week last")
    }

    func testGoalClampAndWorkspacePersistence() throws {
        XCTAssertEqual(WeeklyConsistencyPolicy.clampedGoal(0), 1)
        XCTAssertEqual(WeeklyConsistencyPolicy.clampedGoal(4), 4)
        XCTAssertEqual(WeeklyConsistencyPolicy.clampedGoal(9), 7)

        let container = try ModelContainer(
            for: CreatorWorkspace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let workspace = CreatorWorkspace(profileID: UUID(), name: "@goal")
        workspace.weeklyPostingGoal = 4
        context.insert(workspace)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<CreatorWorkspace>()).first)
        XCTAssertEqual(fetched.weeklyPostingGoal, 4)
    }
}
