import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PagePlan05Tests: XCTestCase {
    func testReschedulingOneOutputRecomputesTheParentsEarliestScheduledDate() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))

        let calendar = Calendar(identifier: .gregorian)
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 1, hour: 12
        )))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 12
        )))
        let movedDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3, hour: 12
        )))

        let brief = CreativeBrief(title: "Two destinations", status: .scheduled)
        brief.agendaDate = firstDate
        let first = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        first.targetDate = firstDate
        let second = PlatformOutput(briefID: brief.id, platform: .youtubeShorts, status: .scheduled)
        second.targetDate = secondDate
        context.insert(brief)
        context.insert(first)
        context.insert(second)
        try context.save()

        let appModel = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(appModel.schedule(output: first, date: movedDate, context: context))

        XCTAssertEqual(first.targetDate, movedDate)
        XCTAssertEqual(brief.agendaDate, secondDate)
    }

    func testFailedRescheduleDoesNotApplyRequestedTimeToMissingPost() {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let output = PlatformOutput(briefID: UUID(), status: .scheduled)
        output.includesTargetTime = false
        context.insert(output)

        let appModel = AppModel(reminderService: PreviewReminderService())
        XCTAssertFalse(appModel.schedule(
            output: output,
            date: Date().addingTimeInterval(86_400),
            includesTargetTime: true,
            context: context
        ))

        XCTAssertNil(output.targetDate)
        XCTAssertFalse(output.includesTargetTime)
    }

    func testDateOnlyRescheduleNormalizesTheOutputAndOpenLinkedTask() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let calendar = Calendar.current
        let priorDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 1, hour: 9
        )))
        let requestedDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 4, hour: 18, minute: 30
        )))
        let brief = CreativeBrief(title: "Date-only post", status: .scheduled)
        brief.agendaDate = priorDate
        let output = PlatformOutput(briefID: brief.id, status: .scheduled)
        output.targetDate = priorDate
        output.includesTargetTime = true
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Finish caption",
            targetDate: priorDate,
            includesTargetTime: false
        )
        context.insert(brief)
        context.insert(output)
        context.insert(task)
        try context.save()

        let appModel = AppModel(reminderService: PreviewReminderService())
        let resolvedDate = RecurringPostSchedule.normalizedTargetDate(
            requestedDate,
            includesTime: false
        )
        XCTAssertTrue(appModel.schedule(
            output: output,
            date: resolvedDate,
            includesTargetTime: false,
            context: context
        ))

        XCTAssertEqual(output.targetDate, resolvedDate)
        XCTAssertFalse(output.includesTargetTime)
        XCTAssertEqual(task.targetDate, calendar.startOfDay(for: requestedDate))
    }

    func testClearingOneOutputKeepsTheOtherOutputAsParentSchedule() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let firstDate = Date(timeIntervalSince1970: 1_788_200_000)
        let secondDate = firstDate.addingTimeInterval(86_400)
        let brief = CreativeBrief(title: "Two scheduled outputs", status: .scheduled)
        brief.agendaDate = firstDate
        let first = PlatformOutput(briefID: brief.id, status: .scheduled)
        first.targetDate = firstDate
        let second = PlatformOutput(briefID: brief.id, platform: .youtubeShorts, status: .scheduled)
        second.targetDate = secondDate
        context.insert(brief)
        context.insert(first)
        context.insert(second)
        try context.save()

        let appModel = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(appModel.clearPostDate(output: first, context: context))

        XCTAssertNil(first.targetDate)
        XCTAssertEqual(first.status, .ready)
        XCTAssertEqual(second.targetDate, secondDate)
        XCTAssertEqual(brief.agendaDate, secondDate)
        XCTAssertEqual(brief.status, .scheduled)
    }

    func testReschedulePreviewRouteRequiresItsOwnArgument() {
        XCTAssertTrue(PreviewAgendaRuntimeFixture.requestsPostReschedule(
            arguments: ["agent.cy", "-agentCyPreviewPostReschedule"]
        ))
        XCTAssertFalse(PreviewAgendaRuntimeFixture.requestsPostReschedule(
            arguments: ["agent.cy", "-agentCyPreviewSchedulePost"]
        ))
    }
}
