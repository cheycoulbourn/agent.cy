import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PagePlan08Tests: XCTestCase {
    func testEditorPreviewRouteRequiresExplicitLaunchArgument() {
        XCTAssertTrue(PlanRuntimeFixture.requestsDailyFocusEditor(
            arguments: ["agent.cy", "-agentCyPreviewDailyFocusEditor"]
        ))
        XCTAssertFalse(PlanRuntimeFixture.requestsDailyFocusEditor(
            arguments: ["agent.cy", "-agentCyPreviewData"]
        ))
    }

    func testDateEditCreatesOneOverrideWithoutRewritingRecurringWeekdays() throws {
        let calendar = Calendar.current
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 12
        )))
        let wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: monday))
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let mondayTemplate = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            title: "Planning"
        )
        let tuesdayTemplate = DailyFocusTemplateEntry(
            weekday: .tuesday,
            kind: .filming,
            title: "Filming"
        )
        let otherOverride = DailyFocusOverride(
            date: wednesday,
            kind: .editing,
            title: "Editing"
        )
        context.insert(mondayTemplate)
        context.insert(tuesdayTemplate)
        context.insert(otherOverride)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.saveDailyFocus(
            date: monday,
            scope: .date,
            selection: [.scripting],
            note: "Write one clean draft.",
            durationMinutes: 60,
            startMinutesFromMidnight: 10 * 60,
            context: context
        ))

        XCTAssertEqual(mondayTemplate.kind, .planning)
        XCTAssertEqual(tuesdayTemplate.kind, .filming)
        let overrides = try context.fetch(FetchDescriptor<DailyFocusOverride>())
        XCTAssertEqual(overrides.count, 2)
        let edited = try XCTUnwrap(DailyFocusOverrideIndex.canonical(
            on: monday,
            from: overrides,
            calendar: calendar
        ))
        XCTAssertEqual(edited.kind, .scripting)
        XCTAssertEqual(edited.note, "Write one clean draft.")
        XCTAssertEqual(edited.durationMinutes, 60)
        XCTAssertEqual(edited.startMinutesFromMidnight, 10 * 60)
        XCTAssertTrue(overrides.contains(where: { $0.id == otherOverride.id }))
    }

    func testRecurringEditUsesCanonicalWeekdayAndLeavesOtherDaysUntouched() throws {
        let calendar = Calendar.current
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 12
        )))
        let nextMonday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: monday))
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let olderMonday = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            title: "Planning",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        olderMonday.updatedAt = Date(timeIntervalSince1970: 200)
        let currentMonday = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .filming,
            title: "Filming",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        currentMonday.updatedAt = Date(timeIntervalSince1970: 400)
        let tuesday = DailyFocusTemplateEntry(
            weekday: .tuesday,
            kind: .community,
            title: "Community"
        )
        let selectedDateOverride = DailyFocusOverride(
            date: monday,
            kind: .editing,
            title: "Editing"
        )
        let futureOverride = DailyFocusOverride(
            date: nextMonday,
            kind: .publishing,
            title: "Publishing"
        )
        [olderMonday, currentMonday, tuesday].forEach(context.insert)
        context.insert(selectedDateOverride)
        context.insert(futureOverride)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.saveDailyFocus(
            date: monday,
            scope: .recurring,
            selection: [.scripting, .editing],
            note: "Batch both together.",
            durationMinutes: 120,
            startMinutesFromMidnight: 9 * 60,
            context: context
        ))

        XCTAssertEqual(olderMonday.kind, .planning)
        XCTAssertEqual(currentMonday.kind, .scripting)
        XCTAssertEqual(currentMonday.secondaryKind, .editing)
        XCTAssertEqual(currentMonday.note, "Batch both together.")
        XCTAssertEqual(tuesday.kind, .community)
        let overrides = try context.fetch(FetchDescriptor<DailyFocusOverride>())
        XCTAssertFalse(overrides.contains(where: { $0.id == selectedDateOverride.id }))
        XCTAssertTrue(overrides.contains(where: { $0.id == futureOverride.id }))
    }

    func testDateRestClearsOnlyThatDateAndDropsHiddenDetails() throws {
        let day = Date(timeIntervalSince1970: 1_777_776_000)
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())

        XCTAssertTrue(model.saveDailyFocus(
            date: day,
            scope: .date,
            selection: [],
            note: "Should not survive",
            durationMinutes: 90,
            startMinutesFromMidnight: 8 * 60,
            context: context
        ))

        let item = try XCTUnwrap(context.fetch(FetchDescriptor<DailyFocusOverride>()).first)
        XCTAssertTrue(item.isCleared)
        XCTAssertEqual(item.title, "Rest")
        XCTAssertEqual(item.note, "")
        XCTAssertNil(item.durationMinutes)
        XCTAssertNil(item.startMinutesFromMidnight)
    }
}
