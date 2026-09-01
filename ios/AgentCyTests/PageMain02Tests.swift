import XCTest
@testable import AgentCy

final class PageMain02Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testPlanClockMovesTheCurrentWeekAcrossMidnight() throws {
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 23,
            hour: 23,
            minute: 59
        )))
        let monday = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: sunday))

        XCTAssertNotEqual(
            PlanClockPolicy.weekStart(referenceDate: sunday, offset: 0, calendar: calendar),
            PlanClockPolicy.weekStart(referenceDate: monday, offset: 0, calendar: calendar)
        )
        XCTAssertEqual(
            PlanClockPolicy.greeting(referenceDate: monday, calendar: calendar),
            "Good evening"
        )
    }

    func testPlanClockComputesRequestedWeekRelativeToTheProvidedInstant() throws {
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 12
        )))
        let followingWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 8, to: referenceDate))

        XCTAssertEqual(
            PlanClockPolicy.weekOffset(
                containing: followingWeek,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            1
        )
    }

    func testPlanClockPreservesSelectedWeekdayAcrossAWeekRollover() throws {
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 23,
            hour: 23,
            minute: 59
        )))
        let oldWednesday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 19
        )))
        let monday = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: sunday))
        let newWednesday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 26
        )))

        XCTAssertEqual(
            PlanClockPolicy.rebasedSelection(
                oldWednesday,
                oldReferenceDate: sunday,
                newReferenceDate: monday,
                weekOffset: 0,
                calendar: calendar
            ),
            newWednesday
        )
    }

    func testPostOccurrenceUsesOnlyTheOutputTargetTime() throws {
        let postDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 18
        )))

        XCTAssertEqual(
            AgendaCardTimePolicy.displayTime(
                kind: .post,
                occurrenceDate: postDate,
                includesWorkTime: true,
                includesTargetTime: true
            ),
            postDate
        )
        XCTAssertNil(
            AgendaCardTimePolicy.displayTime(
                kind: .post,
                occurrenceDate: postDate,
                includesWorkTime: true,
                includesTargetTime: false
            )
        )
    }

    func testWorkOccurrenceUsesOnlyTheBriefWorkTimeFlag() throws {
        let workDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 9
        )))

        XCTAssertEqual(
            AgendaCardTimePolicy.displayTime(
                kind: .work,
                occurrenceDate: workDate,
                includesWorkTime: true,
                includesTargetTime: false
            ),
            workDate
        )
        XCTAssertNil(
            AgendaCardTimePolicy.displayTime(
                kind: .work,
                occurrenceDate: workDate,
                includesWorkTime: false,
                includesTargetTime: true
            )
        )
    }

    func testAgendaBriefIndexKeepsTheFirstDuplicateInsteadOfTrapping() {
        let sharedID = UUID()
        let first = CreativeBrief(id: sharedID, title: "First")
        let duplicate = CreativeBrief(id: sharedID, title: "Duplicate")

        let index = AgendaBriefIndexPolicy.index([first, duplicate])

        XCTAssertTrue(index[sharedID] === first)
        XCTAssertEqual(index.count, 1)
    }

    func testAgendaAnimationsStopUnderReduceMotion() {
        XCTAssertFalse(AgendaMotionPolicy.usesAnimation(reduceMotion: true))
        XCTAssertTrue(AgendaMotionPolicy.usesAnimation(reduceMotion: false))
    }

    func testFixedCalendarAndAvatarControlsCapVisualDynamicType() {
        XCTAssertEqual(AgendaCompactCalendarPolicy.maximumDynamicTypeSize, .large)
        XCTAssertEqual(CreatorAvatarPresentationPolicy.maximumDynamicTypeSize, .large)
        XCTAssertTrue(
            AgendaCompactCalendarPolicy.usesStackedCompletedDayLayout(
                dynamicTypeSize: .accessibility1
            )
        )
        XCTAssertFalse(
            AgendaCompactCalendarPolicy.usesStackedCompletedDayLayout(
                dynamicTypeSize: .large
            )
        )
        XCTAssertFalse(
            AgendaCompactCalendarPolicy.showsWeekdayChips(
                dynamicTypeSize: .accessibility1
            )
        )
        XCTAssertTrue(
            AgendaCompactCalendarPolicy.showsWeekdayChips(
                dynamicTypeSize: .large
            )
        )
        XCTAssertTrue(
            AgendaCompactCalendarPolicy.usesStackedListFilters(
                dynamicTypeSize: .accessibility1
            )
        )
        XCTAssertFalse(
            AgendaCompactCalendarPolicy.usesStackedListFilters(
                dynamicTypeSize: .large
            )
        )
    }

    func testMonthCalendarPlacesPillarColorsOnlyInWeekdayHeaders() {
        let headers = AgendaMonthCalendarColorPolicy.weekdayHeaders(
            symbols: ["S", "M", "T", "W", "T", "F", "S"],
            firstWeekday: 2,
            pillarHexByWeekday: [
                .monday: "416B85",
                .wednesday: "FFFFD8"
            ]
        )

        XCTAssertEqual(headers.map(\.weekday), [
            .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
        ])
        XCTAssertEqual(headers.map(\.symbol), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(headers.map(\.pillarHex), [
            "416B85", nil, "FFFFD8", nil, nil, nil, nil
        ])
        XCTAssertFalse(AgendaMonthCalendarColorPolicy.showsPillarColorOnMonthDates)
    }

    func testAgendaProjectsOnlyTopLevelTasksUsingTaskOwnedDates() throws {
        let targetDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 9
        )))
        let focusDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: targetDate))
        let parent = CreatorTask(
            title: "Edit the launch post",
            targetDate: targetDate,
            dailyFocusDate: focusDate
        )
        let subtask = CreatorTask(
            parentTaskID: parent.id,
            title: "Trim the intro",
            targetDate: targetDate
        )
        let skipped = CreatorTask(title: "Old task", targetDate: targetDate)
        skipped.isSkipped = true
        let undated = CreatorTask(title: "Someday")

        let projection = AgendaTaskProjection.make(
            tasks: [parent, subtask, skipped, undated],
            outputByID: [:],
            activeBriefIDs: [],
            calendar: calendar
        )

        XCTAssertEqual(projection.datedTasks.map(\.id), [parent.id])
        XCTAssertEqual(projection.tasks(on: targetDate, calendar: calendar).map(\.id), [parent.id])
        XCTAssertTrue(projection.tasks(on: focusDate, calendar: calendar).isEmpty)
    }

    func testAgendaDoesNotUsePostPlacementAsAnUndatedTasksDate() throws {
        let postDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 20
        )))
        let brief = CreativeBrief(title: "Studio update")
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        output.targetDate = postDate
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Choose the cover"
        )

        let projection = AgendaTaskProjection.make(
            tasks: [task],
            outputByID: [output.id: output],
            activeBriefIDs: [brief.id],
            calendar: calendar
        )

        XCTAssertTrue(projection.datedTasks.isEmpty)
        XCTAssertTrue(projection.tasks(on: postDate, calendar: calendar).isEmpty)
    }

    func testAgendaHidesTasksLinkedOnlyToArchivedWork() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 21
        )))
        let activeBrief = CreativeBrief(title: "Active")
        let archivedBrief = CreativeBrief(title: "Archived", status: .archived)
        let activeOutput = PlatformOutput(briefID: activeBrief.id, platform: .instagramReels)
        let archivedOutput = PlatformOutput(briefID: archivedBrief.id, platform: .youtubeShorts)
        let activeTask = CreatorTask(
            platformOutputID: activeOutput.id,
            title: "Active task",
            targetDate: day
        )
        let archivedTask = CreatorTask(
            platformOutputID: archivedOutput.id,
            title: "Archived task",
            targetDate: day
        )

        let projection = AgendaTaskProjection.make(
            tasks: [activeTask, archivedTask],
            outputByID: [
                activeOutput.id: activeOutput,
                archivedOutput.id: archivedOutput
            ],
            activeBriefIDs: [activeBrief.id],
            calendar: calendar
        )

        XCTAssertEqual(projection.datedTasks.map(\.id), [activeTask.id])
    }
}
