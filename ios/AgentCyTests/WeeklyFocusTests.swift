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

    func testWeeklySetupSavesRecurringFocusTasksIntoMyTasks() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())
        let task = DailyFocusTaskTemplateDefinition(
            focusKind: .planning,
            title: "Review the idea bank",
            priority: .high
        )

        XCTAssertTrue(model.saveWeeklyFocus(
            [.monday: [.planning]],
            taskTemplates: [.monday: [task]],
            context: context
        ))

        let savedTasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertFalse(savedTasks.isEmpty)
        XCTAssertTrue(savedTasks.allSatisfy { $0.focusTaskTemplateID == task.id })
        XCTAssertTrue(savedTasks.allSatisfy {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .myTasks
        })
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

    func testFocusTaskDefaultsProvideEditableNextStepsForEachSelectedFocus() {
        let definitions = DailyFocusTaskDefaults.definitions(for: [.planning, .filming])

        XCTAssertEqual(definitions.filter { $0.focusKind == .planning }.count, 2)
        XCTAssertEqual(definitions.filter { $0.focusKind == .filming }.count, 2)
        XCTAssertTrue(definitions.allSatisfy { !$0.title.isEmpty })
    }

    func testFocusTaskTemplatesRoundTripThroughCloudKitSafeJSON() {
        let template = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .planning,
            title: "Planning"
        )
        let definitions = [
            DailyFocusTaskTemplateDefinition(
                focusKind: .planning,
                title: "Review the idea bank",
                priority: .high
            )
        ]

        XCTAssertFalse(template.hasConfiguredFocusTasks)
        template.focusTaskTemplates = definitions

        XCTAssertTrue(template.hasConfiguredFocusTasks)
        XCTAssertEqual(template.focusTaskTemplates, definitions)
    }

    func testFocusTaskMaterializerCreatesWeeklyMyTasksWithoutDuplicates() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let monday = try XCTUnwrap(testCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13
        )))
        let definition = DailyFocusTaskTemplateDefinition(
            focusKind: .planning,
            title: "Choose this week's posts",
            priority: .high
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
            from: monday,
            weekCount: 2,
            calendar: testCalendar
        )
        try FocusTaskRecurrenceService.reconcile(
            context: context,
            from: monday,
            weekCount: 2,
            calendar: testCalendar
        )

        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.allSatisfy { $0.focusTaskTemplateID == definition.id })
        XCTAssertTrue(tasks.allSatisfy { $0.priority == .high })
        XCTAssertTrue(tasks.allSatisfy {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .myTasks
        })
        XCTAssertEqual(
            Set(tasks.compactMap(\.dailyFocusDate).map(testCalendar.startOfDay(for:))).count,
            2
        )
    }

    func testFocusTaskMaterializerIncludesTheWholeCurrentWeekWhenSavedMidweek() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let monday = try XCTUnwrap(testCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13
        )))
        let thursday = try XCTUnwrap(testCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 16
        )))
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
            calendar: testCalendar
        )

        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(
            tasks.first?.targetDate.map(testCalendar.startOfDay(for:)),
            testCalendar.startOfDay(for: monday)
        )
        XCTAssertTrue(TaskListVisibilityPolicy.includes(
            collection: .myTasks,
            focusTaskTemplateID: tasks.first?.focusTaskTemplateID,
            recurrence: tasks.first?.recurrence ?? .none,
            recurrenceRootTaskID: tasks.first?.recurrenceRootTaskID,
            targetDate: tasks.first?.targetDate,
            now: thursday,
            calendar: testCalendar
        ))
    }

    func testFocusTemplateTaskDoesNotSpawnASecondRecurrenceChain() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let task = CreatorTask(
            title: "Choose this week's posts",
            targetDate: Date(),
            focusTaskTemplateID: UUID(),
            recurrence: .weekly
        )
        context.insert(task)
        try context.save()

        let next = try RecurringTaskMaterializer.createNextOccurrence(
            after: task,
            context: context,
            calendar: testCalendar
        )

        XCTAssertNil(next)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).count, 1)
    }

    func testSkippingOneFocusTaskOccurrenceLeavesFutureWeeksIntact() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let monday = try XCTUnwrap(testCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13
        )))
        let definition = DailyFocusTaskTemplateDefinition(
            focusKind: .editing,
            title: "Edit the next post"
        )
        let template = DailyFocusTemplateEntry(
            weekday: .monday,
            kind: .editing,
            title: "Editing"
        )
        template.focusTaskTemplates = [definition]
        context.insert(template)
        try context.save()

        try FocusTaskRecurrenceService.reconcile(
            context: context,
            from: monday,
            weekCount: 2,
            calendar: testCalendar
        )
        var tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let skipped = try XCTUnwrap(tasks.min(by: {
            ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
        }))
        skipped.isSkipped = true
        skipped.skippedAt = monday
        template.focusTaskTemplates = [DailyFocusTaskTemplateDefinition(
            id: definition.id,
            focusKind: .editing,
            title: "Finish the next edit"
        )]
        try context.save()

        try FocusTaskRecurrenceService.reconcile(
            context: context,
            from: monday,
            weekCount: 2,
            calendar: testCalendar
        )

        tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.contains { $0.id == skipped.id && $0.isSkipped && $0.title == "Edit the next post" })
        XCTAssertTrue(tasks.contains { !$0.isSkipped && $0.title == "Finish the next edit" })
    }

    private var testCalendar: Calendar {
        Calendar.current
    }
}
