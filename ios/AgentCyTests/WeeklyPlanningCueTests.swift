import XCTest
@testable import AgentCy

final class WeeklyPlanningCueTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testCuePulsesOnMondayUntilCyIsOpened() throws {
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let key = WeeklyPlanningCue.weekKey(for: monday, calendar: calendar)

        XCTAssertTrue(WeeklyPlanningCue.shouldPulse(
            on: monday,
            lastOpenedWeekKey: "",
            calendar: calendar
        ))
        XCTAssertFalse(WeeklyPlanningCue.shouldPulse(
            on: monday,
            lastOpenedWeekKey: key,
            calendar: calendar
        ))
    }

    func testCueDoesNotPulseOutsideMonday() throws {
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))

        XCTAssertFalse(WeeklyPlanningCue.shouldPulse(
            on: tuesday,
            lastOpenedWeekKey: "",
            calendar: calendar
        ))
    }
}
