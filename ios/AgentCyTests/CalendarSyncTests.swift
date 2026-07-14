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

    func testDisconnectWithRevokedAccessKeepsEventLinksForLaterCleanup() throws {
        let suite = "CalendarSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let links = ["post:1": "event-1", "task:2": "event-2"]
        defaults.set("calendar-id", forKey: CalendarIntegrationPreferences.selectedCalendarIdentifierKey)
        defaults.set(true, forKey: CalendarIntegrationPreferences.syncScheduledPostsKey)
        defaults.set(links, forKey: CalendarIntegrationPreferences.eventLinksKey)

        CalendarIntegrationPreferences.disable(preservingEventLinks: true, defaults: defaults)

        XCTAssertFalse(CalendarIntegrationPreferences.isEnabled(defaults: defaults))
        XCTAssertEqual(
            defaults.dictionary(forKey: CalendarIntegrationPreferences.eventLinksKey) as? [String: String],
            links
        )
    }

    func testCalendarCleanupRetainsFailedAndUnattemptedLinksThenRetries() throws {
        var links = [
            "post:1": "event-1",
            "post:2": "event-2",
            "task:1": "event-3",
        ]
        var firstAttempt: [String] = []

        XCTAssertThrowsError(try CalendarEventLinkCleanup.removeAll(links: &links) { identifier in
            firstAttempt.append(identifier)
            if identifier == "event-2" { throw CalendarCleanupTestError.failed }
        })
        XCTAssertEqual(firstAttempt, ["event-1", "event-2"])
        XCTAssertEqual(links, ["post:2": "event-2", "task:1": "event-3"])

        var retry: [String] = []
        try CalendarEventLinkCleanup.removeAll(links: &links) { retry.append($0) }
        XCTAssertEqual(retry, ["event-2", "event-3"])
        XCTAssertTrue(links.isEmpty)
    }
}

private enum CalendarCleanupTestError: Error {
    case failed
}
