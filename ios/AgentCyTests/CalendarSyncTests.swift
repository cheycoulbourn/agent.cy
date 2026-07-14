import Foundation
import XCTest
@testable import AgentCy

final class CalendarSyncTests: XCTestCase {
    func testOnlyScheduledAndPostedOutputsAreEligibleForCalendarSync() {
        XCTAssertTrue(CalendarSyncPolicy.shouldSyncPost(
            status: .scheduled,
            hasTargetDate: true,
            briefIsArchived: false,
            syncEnabled: true
        ))
        XCTAssertTrue(CalendarSyncPolicy.shouldSyncPost(
            status: .posted,
            hasTargetDate: true,
            briefIsArchived: false,
            syncEnabled: true
        ))
        XCTAssertFalse(CalendarSyncPolicy.shouldSyncPost(
            status: .draft,
            hasTargetDate: true,
            briefIsArchived: false,
            syncEnabled: true
        ))
        XCTAssertFalse(CalendarSyncPolicy.shouldSyncPost(
            status: .scheduled,
            hasTargetDate: true,
            briefIsArchived: true,
            syncEnabled: true
        ))
    }

    func testOnlyTopLevelDatedTasksAreEligibleForCalendarSync() {
        XCTAssertTrue(CalendarSyncPolicy.shouldSyncTask(
            hasTargetDate: true,
            isSubtask: false,
            linkedBriefIsArchived: false,
            syncEnabled: true
        ))
        XCTAssertFalse(CalendarSyncPolicy.shouldSyncTask(
            hasTargetDate: true,
            isSubtask: true,
            linkedBriefIsArchived: false,
            syncEnabled: true
        ))
        XCTAssertFalse(CalendarSyncPolicy.shouldSyncTask(
            hasTargetDate: false,
            isSubtask: false,
            linkedBriefIsArchived: false,
            syncEnabled: true
        ))
    }

    func testPostsWithoutTimesBecomeOneDayEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let target = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))

        let timing = CalendarSyncPolicy.postTiming(
            targetDate: target,
            includesTime: false,
            calendar: calendar
        )

        XCTAssertTrue(timing.isAllDay)
        XCTAssertEqual(calendar.component(.hour, from: timing.start), 0)
        XCTAssertEqual(calendar.dateComponents([.day], from: timing.start, to: timing.end).day, 1)
    }

    func testTimedPostsReserveFifteenMinutes() {
        let target = Date(timeIntervalSince1970: 1_784_041_200)
        let timing = CalendarSyncPolicy.postTiming(targetDate: target, includesTime: true)

        XCTAssertFalse(timing.isAllDay)
        XCTAssertEqual(timing.start, target)
        XCTAssertEqual(timing.end.timeIntervalSince(timing.start), 15 * 60)
    }

    func testCalendarPreferencesAreDeviceLocalAndClearCompletely() throws {
        let suite = "CalendarSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("calendar-id", forKey: CalendarIntegrationPreferences.selectedCalendarIdentifierKey)
        defaults.set("Google", forKey: CalendarIntegrationPreferences.selectedCalendarTitleKey)
        defaults.set(true, forKey: CalendarIntegrationPreferences.syncScheduledPostsKey)
        defaults.set(["post:1": "event-1"], forKey: CalendarIntegrationPreferences.eventLinksKey)

        XCTAssertTrue(CalendarIntegrationPreferences.isEnabled(defaults: defaults))

        CalendarIntegrationPreferences.clear(defaults: defaults)

        XCTAssertFalse(CalendarIntegrationPreferences.isEnabled(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: CalendarIntegrationPreferences.eventLinksKey))
    }
}
