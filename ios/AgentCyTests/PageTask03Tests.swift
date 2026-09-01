import XCTest
@testable import AgentCy

@MainActor
final class PageTask03Tests: XCTestCase {
    private enum SaveFailure: Error {
        case injected
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testRecurringTaskCannotLoseItsOnlyDate() throws {
        let original = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 9
        )))
        let task = CreatorTask(
            title: "Weekly review",
            targetDate: original,
            recurrence: .weekly,
            recurrenceRootTaskID: UUID()
        )

        XCTAssertThrowsError(try TaskDueDatePolicy.apply(
            to: task,
            hasDate: false,
            selectedDate: original,
            includesTime: false,
            calendar: calendar,
            persist: { XCTFail("An invalid recurring date must not be persisted") }
        )) { error in
            XCTAssertEqual(error as? TaskDueDatePolicy.Error, .recurringRequiresDate)
        }
        XCTAssertEqual(task.targetDate, original)
        XCTAssertEqual(task.recurrence, .weekly)
    }

    func testDateOnlyAndTimedValuesNormalizeWithoutChangingRecurrence() throws {
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 27, hour: 14, minute: 35
        )))
        let task = CreatorTask(
            title: "Edit video",
            targetDate: selected,
            recurrence: .daily,
            recurrenceRootTaskID: UUID()
        )

        try TaskDueDatePolicy.apply(
            to: task,
            hasDate: true,
            selectedDate: selected,
            includesTime: false,
            calendar: calendar,
            persist: {}
        )
        XCTAssertEqual(task.targetDate, calendar.startOfDay(for: selected))
        XCTAssertFalse(task.includesTargetTime)
        XCTAssertEqual(task.recurrence, .daily)

        try TaskDueDatePolicy.apply(
            to: task,
            hasDate: true,
            selectedDate: selected,
            includesTime: true,
            calendar: calendar,
            persist: {}
        )
        XCTAssertEqual(task.targetDate, selected)
        XCTAssertTrue(task.includesTargetTime)
        XCTAssertEqual(task.recurrence, .daily)
    }

    func testFocusTimeChangeMarksTheOccurrenceCustomizedAndFailureRestoresIt() throws {
        let focusDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 25, hour: 12
        )))
        let original = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 25, hour: 9
        )))
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 29, hour: 15, minute: 20
        )))
        let task = CreatorTask(
            title: "Write the hook",
            targetDate: original,
            includesTargetTime: true,
            dailyFocusDate: focusDay,
            focusTaskTemplateID: UUID()
        )

        XCTAssertThrowsError(try TaskDueDatePolicy.apply(
            to: task,
            hasDate: true,
            selectedDate: selected,
            includesTime: true,
            calendar: calendar,
            persist: { throw SaveFailure.injected }
        ))
        XCTAssertEqual(task.targetDate, original)
        XCTAssertTrue(task.includesTargetTime)
        XCTAssertFalse(task.isFocusTemplateCustomized)

        try TaskDueDatePolicy.apply(
            to: task,
            hasDate: true,
            selectedDate: selected,
            includesTime: true,
            calendar: calendar,
            persist: {}
        )
        XCTAssertEqual(
            task.targetDate,
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 8, day: 25, hour: 15, minute: 20
            )))
        )
        XCTAssertTrue(task.includesTargetTime)
        XCTAssertTrue(task.isFocusTemplateCustomized)
    }

    func testRemovingACaptureDateAlsoClearsItsHiddenTimeFlag() {
        XCTAssertEqual(
            CaptureTaskDueDatePolicy.removingDate(
                from: .init(hasDueDate: true, includesTime: true)
            ),
            .init(hasDueDate: false, includesTime: false)
        )
        XCTAssertFalse(TaskDueDatePolicy.allowsRemoval(recurrence: .daily))
        XCTAssertTrue(TaskDueDatePolicy.allowsRemoval(recurrence: .none))
    }

    func testLinkedTaskDateChangeDoesNotRescheduleItsPost() throws {
        let brief = CreativeBrief(title: "Studio tour", status: .scheduled)
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .scheduled
        )
        let postDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 28, hour: 12
        )))
        let taskDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 26, hour: 9
        )))
        output.targetDate = postDate
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Write caption",
            targetDate: taskDate,
            includesTargetTime: true
        )

        try TaskDueDatePolicy.apply(
            to: task,
            hasDate: false,
            selectedDate: taskDate,
            includesTime: false,
            calendar: calendar,
            persist: {}
        )

        XCTAssertNil(task.targetDate)
        XCTAssertFalse(task.includesTargetTime)
        XCTAssertEqual(output.targetDate, postDate)
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertEqual(brief.status, .scheduled)
    }

    func testDueDateEditorPreviewRequiresItsOwnLaunchArgument() {
        XCTAssertTrue(TaskRuntimeFixture.requestsCaptureDueDateEditor(
            arguments: ["agent.cy", "-agentCyPreviewCaptureTaskDueDate"]
        ))
        XCTAssertFalse(TaskRuntimeFixture.requestsCaptureDueDateEditor(
            arguments: ["agent.cy", "-agentCyPreviewTaskRoute"]
        ))
        XCTAssertTrue(TaskRuntimeFixture.requestsDueDateEditor(
            arguments: ["agent.cy", "-agentCyPreviewTaskDueDate"]
        ))
        XCTAssertFalse(TaskRuntimeFixture.requestsDueDateEditor(
            arguments: ["agent.cy", "-agentCyPreviewTaskRoute"]
        ))
    }
}
