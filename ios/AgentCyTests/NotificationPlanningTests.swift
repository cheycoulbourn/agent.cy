import XCTest
import SwiftData
@testable import AgentCy

final class NotificationPlanningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @MainActor
    func testPlanningInputToleratesDuplicateDestinationsAfterCloudSync() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let destinationID = UUID()
        context.insert(PublishingDestination(id: destinationID, name: "Instagram"))
        context.insert(PublishingDestination(id: destinationID, name: "Instagram"))
        try context.save()

        let input = try LocalReminderService(calendar: calendar).makePlanningInput(
            context: context,
            now: date(2026, 8, 10, 17)
        )

        XCTAssertTrue(input.outputs.isEmpty)
    }

    func testMondayPlanningReplacesDailyAndRestDaysStayQuiet() {
        let now = date(2026, 7, 19, 7)
        let monday = date(2026, 7, 20)
        let tuesday = date(2026, 7, 21)
        let wednesday = date(2026, 7, 22)
        let input = makeInput(
            now: now,
            settings: makeSettings(daily: true, weekly: true),
            focuses: [
                .init(date: monday, title: "Planning"),
                .init(date: tuesday, title: "Rest"),
                .init(date: wednesday, title: "Filming"),
            ]
        )

        let plan = AgentNotificationPlanBuilder.build(input)

        XCTAssertEqual(plan.filter { $0.kind == .weekly && calendar.isDate($0.fireDate, inSameDayAs: monday) }.count, 1)
        XCTAssertFalse(plan.contains { $0.kind == .daily && calendar.isDate($0.fireDate, inSameDayAs: monday) })
        XCTAssertFalse(plan.contains { $0.kind == .daily && calendar.isDate($0.fireDate, inSameDayAs: tuesday) })
        XCTAssertTrue(plan.contains { $0.kind == .daily && calendar.isDate($0.fireDate, inSameDayAs: wednesday) })
    }

    func testMondayPlanningDoesNotInterruptAnExplicitRestDay() {
        let now = date(2026, 7, 19, 7)
        let monday = date(2026, 7, 20)
        let input = makeInput(
            now: now,
            settings: makeSettings(daily: true, weekly: true),
            focuses: [.init(date: monday, title: "Rest")]
        )

        let plan = AgentNotificationPlanBuilder.build(input)

        XCTAssertFalse(plan.contains { calendar.isDate($0.fireDate, inSameDayAs: monday) })
    }

    func testTimedPostAndTaskUseExactLeadTimesAndSound() throws {
        let now = date(2026, 7, 15, 8)
        let briefID = UUID()
        let outputID = UUID()
        let taskID = UUID()
        let postTime = date(2026, 7, 16, 10)
        let taskTime = date(2026, 7, 16, 12)
        let input = makeInput(
            now: now,
            settings: makeSettings(posts: true, tasks: true),
            briefs: [.init(id: briefID, title: "The small shift", status: .scheduled, updatedAt: now)],
            outputs: [
                .init(
                    id: outputID,
                    briefID: briefID,
                    status: .scheduled,
                    targetDate: postTime,
                    includesTargetTime: true,
                    destinationID: UUID(),
                    destinationName: "Instagram",
                    accountID: nil
                ),
            ],
            tasks: [
                .init(
                    id: taskID,
                    briefID: briefID,
                    title: "Set up the camera",
                    priority: .high,
                    isCompleted: false,
                    targetDate: taskTime,
                    includesTargetTime: true,
                    parentTaskID: nil
                ),
            ]
        )

        let plan = AgentNotificationPlanBuilder.build(input)
        let post = try XCTUnwrap(plan.first { $0.kind == .scheduledPost })
        let task = try XCTUnwrap(plan.first { $0.kind == .timedTask })

        XCTAssertEqual(post.fireDate, postTime.addingTimeInterval(-30 * 60))
        XCTAssertEqual(task.fireDate, taskTime.addingTimeInterval(-15 * 60))
        XCTAssertTrue(post.playsSound)
        XCTAssertTrue(task.playsSound)
    }

    func testLateWorkDateSchedulesOnePostAlertAfterTheDatePasses() throws {
        let now = date(2026, 7, 15, 8)
        let briefID = UUID()
        let outputID = UUID()
        let workDate = date(2026, 7, 16)
        let input = makeInput(
            now: now,
            settings: makeSettings(missed: true),
            briefs: [
                .init(
                    id: briefID,
                    title: "Finish the Sunday reset",
                    status: .developing,
                    workDate: workDate,
                    updatedAt: now
                ),
            ],
            outputs: [
                .init(
                    id: outputID,
                    briefID: briefID,
                    status: .draft,
                    targetDate: nil,
                    includesTargetTime: false,
                    destinationID: nil,
                    destinationName: "Instagram",
                    accountID: nil
                ),
            ]
        )

        let reminder = try XCTUnwrap(
            AgentNotificationPlanBuilder.build(input).first { $0.kind == .lateWork }
        )

        XCTAssertEqual(reminder.fireDate, date(2026, 7, 17, 8))
        XCTAssertEqual(reminder.metadata[AgentNotificationMetadataKey.briefID], briefID.uuidString)
        XCTAssertEqual(reminder.metadata[AgentNotificationMetadataKey.outputID], outputID.uuidString)
        XCTAssertEqual(reminder.metadata[AgentNotificationMetadataKey.route], "draft")
        XCTAssertTrue(reminder.playsSound)
    }

    func testLateWorkAlertStopsWhenThePostIsScheduledOrPosted() {
        let now = date(2026, 7, 15, 8)
        let workDate = date(2026, 7, 16)

        for status in [PlatformOutputStatus.scheduled, .posted] {
            let briefID = UUID()
            let input = makeInput(
                now: now,
                settings: makeSettings(missed: true),
                briefs: [
                    .init(
                        id: briefID,
                        title: "Ready post",
                        status: status == .scheduled ? .scheduled : .posted,
                        workDate: workDate,
                        updatedAt: now
                    ),
                ],
                outputs: [
                    .init(
                        id: UUID(),
                        briefID: briefID,
                        status: status,
                        targetDate: date(2026, 7, 18),
                        includesTargetTime: false,
                        destinationID: nil,
                        destinationName: "Instagram",
                        accountID: nil
                    ),
                ]
            )

            XCTAssertFalse(AgentNotificationPlanBuilder.build(input).contains { $0.kind == .lateWork })
        }
    }

    func testFlexibleDailyOverviewDefersUntilQuietHoursEnd() throws {
        let now = date(2026, 7, 15, 21)
        let activeDay = date(2026, 7, 16)
        let input = makeInput(
            now: now,
            settings: makeSettings(daily: true, dailyHour: 7),
            focuses: [.init(date: activeDay, title: "Filming")]
        )

        let overview = try XCTUnwrap(AgentNotificationPlanBuilder.build(input).first { $0.kind == .daily })

        XCTAssertEqual(calendar.component(.hour, from: overview.fireDate), 8)
        XCTAssertEqual(calendar.component(.minute, from: overview.fireDate), 0)
        XCTAssertTrue(calendar.isDate(overview.fireDate, inSameDayAs: activeDay))
        XCTAssertFalse(overview.playsSound)
    }

    func testAutomaticCapKeepsThreeButCreatorFocusReminderIsExempt() {
        let now = date(2026, 7, 15, 8)
        let destinationID = UUID()
        var briefs: [NotificationBriefSnapshot] = []
        var outputs: [NotificationOutputSnapshot] = []
        for hour in 10...13 {
            let briefID = UUID()
            briefs.append(.init(id: briefID, title: "Post \(hour)", status: .scheduled, updatedAt: now))
            outputs.append(.init(
                id: UUID(),
                briefID: briefID,
                status: .scheduled,
                targetDate: date(2026, 7, 16, hour),
                includesTargetTime: true,
                destinationID: destinationID,
                destinationName: "Instagram",
                accountID: nil
            ))
        }
        let input = makeInput(
            now: now,
            settings: makeSettings(posts: true),
            briefs: briefs,
            outputs: outputs,
            focusReminders: [
                .init(id: UUID(), date: date(2026, 7, 16, 14), title: "Editing", note: "One clear pass."),
            ]
        )

        let plan = AgentNotificationPlanBuilder.build(input)

        XCTAssertEqual(plan.filter { $0.kind == .scheduledPost }.count, 3)
        XCTAssertEqual(plan.filter { $0.kind == .focus }.count, 1)
        XCTAssertEqual(plan.count, 4)
    }

    func testHiddenTitlesProtectCreatorContentAndAccountAppearsOnlyWhenNeeded() throws {
        let now = date(2026, 7, 15, 8)
        let briefID = UUID()
        let destinationID = UUID()
        let selectedAccountID = UUID()
        let output = NotificationOutputSnapshot(
            id: UUID(),
            briefID: briefID,
            status: .scheduled,
            targetDate: date(2026, 7, 16, 10),
            includesTargetTime: true,
            destinationID: destinationID,
            destinationName: "Instagram",
            accountID: selectedAccountID
        )
        let input = makeInput(
            now: now,
            settings: makeSettings(posts: true, showTitles: false),
            briefs: [.init(id: briefID, title: "Private launch title", status: .scheduled, updatedAt: now)],
            outputs: [output],
            accounts: [
                .init(id: selectedAccountID, destinationID: destinationID, label: "@primary"),
                .init(id: UUID(), destinationID: destinationID, label: "@studio"),
            ]
        )

        let notification = try XCTUnwrap(AgentNotificationPlanBuilder.build(input).first)

        XCTAssertFalse(notification.body.contains("Private launch title"))
        XCTAssertTrue(notification.body.contains("@primary"))
    }

    func testPostedOrArchivedWorkDoesNotScheduleStaleNotifications() {
        let now = date(2026, 7, 15, 8)
        let postedBriefID = UUID()
        let archivedBriefID = UUID()
        let input = makeInput(
            now: now,
            settings: makeSettings(posts: true, missed: true, drafts: true),
            briefs: [
                .init(id: postedBriefID, title: "Posted", status: .posted, updatedAt: now),
                .init(id: archivedBriefID, title: "Archived", status: .archived, updatedAt: now),
            ],
            outputs: [
                .init(id: UUID(), briefID: postedBriefID, status: .posted, targetDate: date(2026, 7, 16, 10), includesTargetTime: true, destinationID: nil, destinationName: "Instagram", accountID: nil),
                .init(id: UUID(), briefID: archivedBriefID, status: .draft, targetDate: date(2026, 7, 16, 10), includesTargetTime: true, destinationID: nil, destinationName: "Instagram", accountID: nil),
            ]
        )

        XCTAssertTrue(AgentNotificationPlanBuilder.build(input).isEmpty)
    }

    func testDateOnlyMissedDraftPreparationAndAccessUseConfiguredTimes() throws {
        let now = date(2026, 7, 15, 8)
        let scheduledBriefID = UUID()
        let draftBriefID = UUID()
        let input = NotificationPlanningInput(
            now: now,
            calendar: calendar,
            settings: makeSettings(missed: true, drafts: true, access: true),
            briefs: [
                .init(id: scheduledBriefID, title: "Scheduled", status: .scheduled, updatedAt: now),
                .init(id: draftBriefID, title: "Draft", status: .developing, updatedAt: now),
            ],
            outputs: [
                .init(id: UUID(), briefID: scheduledBriefID, status: .scheduled, targetDate: date(2026, 7, 16), includesTargetTime: false, destinationID: nil, destinationName: "Instagram", accountID: nil),
                .init(id: UUID(), briefID: draftBriefID, status: .draft, targetDate: date(2026, 7, 17), includesTargetTime: false, destinationID: nil, destinationName: "TikTok", accountID: nil),
            ],
            tasks: [],
            focuses: [],
            focusReminders: [],
            accounts: [],
            accessEndDate: date(2026, 7, 18, 18),
            horizonDays: 21
        )

        let plan = AgentNotificationPlanBuilder.build(input)
        let missed = try XCTUnwrap(plan.first { $0.kind == .missedPost })
        let draft = try XCTUnwrap(plan.first { $0.kind == .draftPreparation })
        let access = try XCTUnwrap(plan.first { $0.kind == .access })

        XCTAssertEqual(missed.fireDate, date(2026, 7, 16, 18))
        XCTAssertEqual(draft.fireDate, date(2026, 7, 16, 18))
        XCTAssertEqual(access.fireDate, date(2026, 7, 17, 18))
        XCTAssertTrue(missed.playsSound)
        XCTAssertFalse(draft.playsSound)
        XCTAssertFalse(access.playsSound)
    }

    func testMasterSwitchCancelsTheEntireAutomaticPlan() {
        let now = date(2026, 7, 15, 8)
        let enabled = makeSettings(daily: true, weekly: true, posts: true, missed: true, tasks: true, drafts: true, access: true)
        let disabled = NotificationSettingsSnapshot(
            masterEnabled: false,
            dailyEnabled: enabled.dailyEnabled,
            dailyHour: enabled.dailyHour,
            dailyMinute: enabled.dailyMinute,
            weeklyEnabled: enabled.weeklyEnabled,
            weeklyWeekday: enabled.weeklyWeekday,
            weeklyHour: enabled.weeklyHour,
            weeklyMinute: enabled.weeklyMinute,
            postRemindersEnabled: enabled.postRemindersEnabled,
            missedPostRemindersEnabled: enabled.missedPostRemindersEnabled,
            taskRemindersEnabled: enabled.taskRemindersEnabled,
            draftPrepRemindersEnabled: enabled.draftPrepRemindersEnabled,
            accessRemindersEnabled: enabled.accessRemindersEnabled,
            draftPrepHour: enabled.draftPrepHour,
            draftPrepMinute: enabled.draftPrepMinute,
            dateOnlyDeadlineHour: enabled.dateOnlyDeadlineHour,
            dateOnlyDeadlineMinute: enabled.dateOnlyDeadlineMinute,
            quietHoursEnabled: enabled.quietHoursEnabled,
            quietHoursStartHour: enabled.quietHoursStartHour,
            quietHoursStartMinute: enabled.quietHoursStartMinute,
            quietHoursEndHour: enabled.quietHoursEndHour,
            quietHoursEndMinute: enabled.quietHoursEndMinute,
            showTitles: enabled.showTitles
        )

        XCTAssertTrue(AgentNotificationPlanBuilder.build(makeInput(now: now, settings: disabled)).isEmpty)
    }

    @MainActor
    func testActivityCenterPersistsPlannedAndLiveActionItemsUntilTheyAreResolved() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = date(2026, 8, 17, 12)

        let lateBrief = CreativeBrief(title: "Finish Sunday reset", status: .developing)
        lateBrief.ideaBankPlacement = .post
        lateBrief.workDate = date(2026, 8, 16)
        let lateOutput = PlatformOutput(briefID: lateBrief.id, status: .draft)

        let missedBrief = CreativeBrief(title: "No scroll Sundays", status: .scheduled)
        missedBrief.ideaBankPlacement = .post
        let missedOutput = PlatformOutput(briefID: missedBrief.id, status: .scheduled)
        missedOutput.targetDate = date(2026, 8, 16, 10)

        let overdueTask = CreatorTask(title: "Export the reel")
        overdueTask.targetDate = date(2026, 8, 17, 10)
        overdueTask.includesTargetTime = true

        [lateBrief, missedBrief].forEach(context.insert)
        [lateOutput, missedOutput].forEach(context.insert)
        context.insert(overdueTask)
        try context.save()

        try AgentActivityCenterService.reconcile(plan: [], context: context, now: now, calendar: calendar)

        let records = try context.fetch(FetchDescriptor<AgentActivityRecord>())
        XCTAssertEqual(Set(records.map(\.kind)), [.lateWork, .missedPost, .timedTask])
        XCTAssertTrue(records.allSatisfy {
            AgentActivityPresentationPolicy.isVisible(availableAt: $0.availableAt, archivedAt: $0.archivedAt, clearedAt: $0.clearedAt, now: now)
        })

        let taskRecord = try XCTUnwrap(records.first { $0.kind == .timedTask })
        try AgentActivityCenterService.markRead(taskRecord, context: context, now: now)
        XCTAssertNotNil(taskRecord.readAt)
        XCTAssertTrue(AgentActivityPresentationPolicy.needsAttention(
            kind: taskRecord.kind,
            readAt: taskRecord.readAt,
            resolvedAt: taskRecord.resolvedAt
        ))

        overdueTask.isCompleted = true
        lateBrief.workDate = nil
        missedOutput.status = .posted
        try context.save()
        try AgentActivityCenterService.reconcile(
            plan: [],
            context: context,
            now: now.addingTimeInterval(60),
            calendar: calendar
        )

        XCTAssertTrue(records.allSatisfy { $0.resolvedAt != nil })
    }

    @MainActor
    func testPlannedActivityExistsBeforeDeliveryButDoesNotAppearEarly() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = date(2026, 8, 17, 12)
        let fireDate = date(2026, 8, 18, 9)
        let item = AgentNotificationPlanItem(
            id: "agentcy.v2.daily.20260818",
            kind: .daily,
            fireDate: fireDate,
            title: "Today’s plan",
            body: "Two items planned.",
            reason: "Daily overview",
            categoryIdentifier: AgentNotificationCategory.daily,
            playsSound: false,
            isCreatorRequested: false,
            priority: 60,
            metadata: [
                AgentNotificationMetadataKey.kind: AgentNotificationKind.daily.rawValue,
                AgentNotificationMetadataKey.route: "day",
            ]
        )

        try AgentActivityCenterService.reconcile(plan: [item], context: context, now: now, calendar: calendar)

        let record = try XCTUnwrap(context.fetch(FetchDescriptor<AgentActivityRecord>()).first)
        XCTAssertFalse(AgentActivityPresentationPolicy.isVisible(
            availableAt: record.availableAt,
            archivedAt: record.archivedAt,
            clearedAt: record.clearedAt,
            now: now
        ))
        XCTAssertTrue(AgentActivityPresentationPolicy.isVisible(
            availableAt: record.availableAt,
            archivedAt: record.archivedAt,
            clearedAt: record.clearedAt,
            now: fireDate
        ))
    }

    private func makeSettings(
        daily: Bool = false,
        dailyHour: Int = 9,
        weekly: Bool = false,
        posts: Bool = false,
        missed: Bool = false,
        tasks: Bool = false,
        drafts: Bool = false,
        access: Bool = false,
        showTitles: Bool = true
    ) -> NotificationSettingsSnapshot {
        NotificationSettingsSnapshot(
            masterEnabled: true,
            dailyEnabled: daily,
            dailyHour: dailyHour,
            dailyMinute: 0,
            weeklyEnabled: weekly,
            weeklyWeekday: 2,
            weeklyHour: 9,
            weeklyMinute: 0,
            postRemindersEnabled: posts,
            missedPostRemindersEnabled: missed,
            taskRemindersEnabled: tasks,
            draftPrepRemindersEnabled: drafts,
            accessRemindersEnabled: access,
            draftPrepHour: 18,
            draftPrepMinute: 0,
            dateOnlyDeadlineHour: 18,
            dateOnlyDeadlineMinute: 0,
            quietHoursEnabled: true,
            quietHoursStartHour: 20,
            quietHoursStartMinute: 0,
            quietHoursEndHour: 8,
            quietHoursEndMinute: 0,
            showTitles: showTitles
        )
    }

    private func makeInput(
        now: Date,
        settings: NotificationSettingsSnapshot,
        briefs: [NotificationBriefSnapshot] = [],
        outputs: [NotificationOutputSnapshot] = [],
        tasks: [NotificationTaskSnapshot] = [],
        focuses: [NotificationFocusSnapshot] = [],
        focusReminders: [NotificationFocusReminderSnapshot] = [],
        accounts: [NotificationAccountSnapshot] = []
    ) -> NotificationPlanningInput {
        NotificationPlanningInput(
            now: now,
            calendar: calendar,
            settings: settings,
            briefs: briefs,
            outputs: outputs,
            tasks: tasks,
            focuses: focuses,
            focusReminders: focusReminders,
            accounts: accounts,
            accessEndDate: nil,
            horizonDays: 21
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

@MainActor
final class NotificationActionTests: XCTestCase {
    func testCompleteTaskActionIsIdempotentAndIgnoresMissingTasks() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let task = CreatorTask(title: "Finish captions", kind: .editing)
        context.insert(task)
        try context.save()
        let mutations = NotificationActionMutationService(context: context)

        try mutations.completeTask(id: task.id)
        let completedAt = try XCTUnwrap(task.completedAt)
        try mutations.completeTask(id: task.id)
        try mutations.completeTask(id: UUID())

        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completedAt, completedAt)
    }

    func testMarkPostedActionUpdatesMasterLifecycleAndIsIdempotent() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Ready to share", premise: "A clear point", status: .scheduled)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = Date().addingTimeInterval(60 * 60)
        context.insert(brief)
        context.insert(output)
        try context.save()
        let mutations = NotificationActionMutationService(context: context)

        try mutations.markPosted(outputID: output.id)
        let postedAt = try XCTUnwrap(output.postedAt)
        try mutations.markPosted(outputID: output.id)
        try mutations.markPosted(outputID: UUID())

        XCTAssertEqual(output.status, .posted)
        XCTAssertEqual(output.postedAt, postedAt)
        XCTAssertEqual(brief.status, .posted)
    }
}
