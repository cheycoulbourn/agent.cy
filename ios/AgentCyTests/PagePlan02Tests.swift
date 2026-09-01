import XCTest
@testable import AgentCy

final class PagePlan02Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDayAgendaKeepsLinkedTaskOnItsOwnedWorkDayOnly() throws {
        let workDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 20
        )))
        let publishingDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: workDay))
        let brief = CreativeBrief(title: "Launch post")
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        output.targetDate = publishingDay
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Edit the launch post",
            targetDate: workDay
        )

        let workProjection = DayAgendaTaskProjection.make(
            tasks: [task],
            outputByID: [output.id: output],
            activeBriefIDs: [brief.id],
            day: workDay,
            calendar: calendar
        )
        let publishingProjection = DayAgendaTaskProjection.make(
            tasks: [task],
            outputByID: [output.id: output],
            activeBriefIDs: [brief.id],
            day: publishingDay,
            calendar: calendar
        )

        XCTAssertEqual(workProjection.dayTasks.map(\.id), [task.id])
        XCTAssertTrue(publishingProjection.dayTasks.isEmpty)
    }

    func testDayAgendaResolvesArchivedBriefThroughAnOutputOnlyTaskLink() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 21
        )))
        let archivedBrief = CreativeBrief(title: "Archived", status: .archived)
        let archivedOutput = PlatformOutput(
            briefID: archivedBrief.id,
            platform: .youtubeShorts
        )
        let task = CreatorTask(
            platformOutputID: archivedOutput.id,
            title: "Hidden task",
            targetDate: day
        )

        let projection = DayAgendaTaskProjection.make(
            tasks: [task],
            outputByID: [archivedOutput.id: archivedOutput],
            activeBriefIDs: [],
            day: day,
            calendar: calendar
        )

        XCTAssertTrue(projection.dayTasks.isEmpty)
    }

    func testDayAgendaOutputMetadataFallsBackToPlatform() {
        XCTAssertEqual(
            DayAgendaOutputMetadata.label(
                destination: nil,
                format: nil,
                account: nil,
                platform: "YouTube Shorts"
            ),
            "YouTube Shorts"
        )
        XCTAssertEqual(
            DayAgendaOutputMetadata.label(
                destination: "YouTube",
                format: "Short",
                account: "Studio",
                platform: "YouTube Shorts"
            ),
            "YouTube · Short · Studio"
        )
    }

    func testDayAgendaPrefersTheAnchorWhenABranchSharesItsWeekdays() {
        let anchor = Pillar(
            role: .anchor,
            name: "Creator systems",
            assignedWeekdays: [.friday]
        )
        let branch = Pillar(
            parentPillarID: anchor.id,
            role: .supporting,
            name: "Practical tutorials",
            assignedWeekdays: [.friday]
        )

        XCTAssertEqual(
            AgendaAssignedPillarPolicy.pillar(for: .friday, in: [branch, anchor])?.id,
            anchor.id
        )
        XCTAssertEqual(
            AgendaAssignedPillarPolicy.pillar(for: .friday, in: [anchor, branch])?.id,
            anchor.id
        )
    }

    func testDayAgendaPreviewRouteRequiresItsExplicitArgument() {
        XCTAssertTrue(AppShellRuntimeFixture.requestsPreviewAgendaDay(
            arguments: ["agent.cy", "-agentCyPreviewAgendaDay"]
        ))
        XCTAssertFalse(AppShellRuntimeFixture.requestsPreviewAgendaDay(
            arguments: ["agent.cy", "-agentCyPreviewAgendaMode", "week"]
        ))
    }
}
