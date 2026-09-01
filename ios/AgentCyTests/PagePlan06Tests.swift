import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PagePlan06Tests: XCTestCase {
    func testMidweekReconcileDoesNotManufacturePastDueFocusTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 13
        )))
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16
        )))
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let definition = DailyFocusTaskTemplateDefinition(
            focusKind: .planning,
            title: "Review the idea bank"
        )
        let template = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            title: "Planning"
        )
        template.focusTaskTemplates = [definition]
        context.insert(template)
        try context.save()

        try FocusTaskRecurrenceService.reconcile(
            context: context,
            from: thursday,
            weekCount: 1,
            calendar: calendar
        )

        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertFalse(tasks.contains {
            ($0.targetDate ?? .distantFuture) < calendar.startOfDay(for: thursday)
        })
        XCTAssertFalse(tasks.contains {
            $0.targetDate.map { calendar.isDate($0, inSameDayAs: monday) } ?? false
        })
    }

    func testNewestFocusTemplateWinsDuplicateWeekdayDeterministically() {
        let older = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            title: "Planning",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        older.updatedAt = Date(timeIntervalSince1970: 200)
        let newer = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .filming,
            title: "Filming",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        newer.updatedAt = Date(timeIntervalSince1970: 400)

        XCTAssertEqual(
            DailyFocusTemplateIndex.canonicalByWeekday([older, newer])[.monday]?.id,
            newer.id
        )
        XCTAssertEqual(
            DailyFocusTemplateIndex.canonicalByWeekday([newer, older])[.monday]?.id,
            newer.id
        )
    }

    func testNewestRestTemplateOverridesOlderActiveDuplicate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 13
        )))
        let olderFocus = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            title: "Planning",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        olderFocus.updatedAt = Date(timeIntervalSince1970: 200)
        let newerRest = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .custom,
            title: "Rest",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        newerRest.updatedAt = Date(timeIntervalSince1970: 400)
        newerRest.isActive = false

        XCTAssertNil(DailyFocusResolver.resolve(
            date: monday,
            templates: [olderFocus, newerRest],
            overrides: [],
            calendar: calendar
        ))
    }
}
