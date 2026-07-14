import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class WeeklyFocusTests: XCTestCase {
    func testTwoFocusesUseSentenceCaseAmpersandTitle() {
        XCTAssertEqual(
            DailyFocusKind.combinedTitle([.planning, .scripting]),
            "Planning & scripting"
        )
        XCTAssertEqual(DailyFocusKind.combinedTitle([]), "Rest")
    }

    func testWeeklySetupPersistsEveryDayIncludingRest() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())

        XCTAssertTrue(model.saveWeeklyFocus([
            .monday: [.planning, .scripting],
            .friday: [.filming],
        ], context: context))

        let entries = try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>())
        XCTAssertEqual(entries.count, 7)

        let monday = try XCTUnwrap(entries.first(where: { $0.weekday == .monday }))
        XCTAssertTrue(monday.isActive)
        XCTAssertEqual(monday.kind, .planning)
        XCTAssertEqual(monday.secondaryKind, .scripting)
        XCTAssertEqual(monday.title, "Planning & scripting")

        let tuesday = try XCTUnwrap(entries.first(where: { $0.weekday == .tuesday }))
        XCTAssertFalse(tuesday.isActive)
        XCTAssertEqual(tuesday.title, "Rest")
        XCTAssertNil(tuesday.secondaryKind)
    }

    func testResolverCombinesRecurringFocusAndClearedOverrideBecomesRest() throws {
        let calendar = testCalendar
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let template = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            secondaryKind: .scripting,
            title: "Legacy title"
        )

        let resolved = try XCTUnwrap(DailyFocusResolver.resolve(
            date: monday,
            templates: [template],
            overrides: [],
            calendar: calendar
        ))
        XCTAssertEqual(resolved.kinds, [.planning, .scripting])
        XCTAssertEqual(resolved.title, "Planning & scripting")
        XCTAssertEqual(
            resolved.note,
            "Choose what to make and map the next steps. Write hooks, beats, and calls to action."
        )

        let cleared = DailyFocusOverride(date: monday, isCleared: true)
        XCTAssertNil(DailyFocusResolver.resolve(
            date: monday,
            templates: [template],
            overrides: [cleared],
            calendar: calendar
        ))
    }

    func testTaskRecommendationUsesNextMatchingFocusAndRespectsRestOverride() throws {
        let calendar = testCalendar
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: monday))
        let filming = DailyFocusTemplateEntry(
            weekday: .wednesday,
            kind: .filming,
            title: "Filming",
            startMinutesFromMidnight: 9 * 60
        )

        let first = try XCTUnwrap(DailyFocusRecommendation.nextDate(
            for: .filming,
            templates: [filming],
            overrides: [],
            after: monday,
            calendar: calendar
        ))
        XCTAssertTrue(calendar.isDate(first.date, inSameDayAs: wednesday))
        XCTAssertEqual(calendar.component(.hour, from: first.date), 9)

        let restOverride = DailyFocusOverride(date: wednesday, isCleared: true)
        let nextWeek = try XCTUnwrap(DailyFocusRecommendation.nextDate(
            for: .filming,
            templates: [filming],
            overrides: [restOverride],
            after: monday,
            calendar: calendar
        ))
        let followingWednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 9, to: monday))
        XCTAssertTrue(calendar.isDate(nextWeek.date, inSameDayAs: followingWednesday))
    }

    func testLegacyCustomFocusInfersBuiltInSelectionAndDropsStaleCopy() throws {
        let calendar = testCalendar
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let template = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .custom,
            title: "Batch Film",
            note: "An old custom description"
        )

        let resolved = try XCTUnwrap(DailyFocusResolver.resolve(
            date: monday,
            templates: [template],
            overrides: [],
            calendar: calendar
        ))

        XCTAssertEqual(resolved.kinds, [.filming])
        XCTAssertEqual(resolved.title, "Filming")
        XCTAssertEqual(resolved.note, DailyFocusKind.filming.directive)
    }

    func testLegacyPostingAndAdminKindsNormalizeToCurrentOptions() {
        XCTAssertEqual(
            DailyFocusResolver.normalizedKinds(
                primary: .posting,
                secondary: .admin,
                storedTitle: "Publishing & business/admin"
            ),
            [.publishing, .businessAdmin]
        )
    }

    private var testCalendar: Calendar {
        Calendar.current
    }
}
