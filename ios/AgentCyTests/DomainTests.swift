import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class DomainTests: XCTestCase {
    func testRecurringScheduleBuildsFutureDatesAndSupportsDateOnlyTargets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 9,
            minute: 45
        )))

        let openEnded = RecurringPostSchedule.futureDates(
            after: first,
            frequency: .daily,
            includesTime: false,
            calendar: calendar
        )
        XCTAssertEqual(openEnded.count, 12)
        XCTAssertTrue(openEnded.allSatisfy { calendar.component(.hour, from: $0) == 12 })

        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 27)))
        let weekly = RecurringPostSchedule.futureDates(
            after: first,
            frequency: .weekly,
            weekdays: [.monday],
            endDate: end,
            calendar: calendar
        )
        XCTAssertEqual(weekly.map { calendar.component(.day, from: $0) }, [20, 27])
        XCTAssertTrue(weekly.allSatisfy { calendar.component(.hour, from: $0) == 9 })
    }

    func testSchedulingSeriesCreatesSeparateFutureScheduledPosts() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))

        let calendar = Calendar.current
        let first = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 9,
            minute: 45
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 27)))
        let brief = CreativeBrief(title: "Weekly series", premise: "One useful post each Monday")
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        output.recurrence = .weekly
        output.recurrenceWeekdays = [.monday]
        output.recurrenceEndDate = end
        output.includesTargetTime = false
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Draft the opening",
            kind: .scripting,
            targetDate: first
        )
        context.insert(brief)
        context.insert(output)
        context.insert(task)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.schedulePostSeries(output: output, date: first, context: context))

        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertEqual(briefs.count, 3)
        XCTAssertEqual(outputs.count, 3)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertTrue(briefs.allSatisfy { $0.status == .scheduled })
        XCTAssertTrue(outputs.allSatisfy { $0.status == .scheduled })
        XCTAssertTrue(outputs.allSatisfy { $0.targetDate.map { calendar.component(.hour, from: $0) == 12 } ?? false })
        XCTAssertEqual(outputs.filter { $0.seriesRootOutputID == output.id }.count, 3)
    }

    func testTodayKeepsDraftWorkOutOfGoingLive() {
        XCTAssertEqual(
            TodayOutputPresentation.section(outputStatus: .draft, briefStatus: .spark),
            .drafted
        )
        XCTAssertEqual(
            TodayOutputPresentation.section(outputStatus: .scheduled, briefStatus: .developing),
            .drafted
        )
        XCTAssertEqual(
            TodayOutputPresentation.section(outputStatus: .scheduled, briefStatus: .scheduled),
            .goingLive
        )
        XCTAssertEqual(
            TodayOutputPresentation.section(outputStatus: .posted, briefStatus: .posted),
            .goingLive
        )
    }

    func testDraftPostResumesEditorEvenIfItsOutputWasMarkedScheduled() {
        XCTAssertTrue(PostDraftResumePolicy.shouldResume(briefStatus: .spark))
        XCTAssertTrue(PostDraftResumePolicy.shouldResume(briefStatus: .developing))
        XCTAssertFalse(PostDraftResumePolicy.shouldResume(briefStatus: .ready))
        XCTAssertTrue(
            PostDraftResumePolicy.shouldResume(
                briefStatus: .scheduled,
                outputStatus: .draft
            )
        )
        XCTAssertEqual(
            PostDraftResumePolicy.outputStatus(briefStatus: .developing, current: .scheduled),
            .draft
        )
    }

    func testIdeaBankIdeaOpensAsOneUnscheduledPostDraft() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Create", selectedPlatforms: [.youtubeShorts])
        let idea = CreativeBrief(title: "The one-job idea", premise: "A useful note to carry into the post.")
        context.insert(profile)
        context.insert(idea)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        let first = try XCTUnwrap(model.ensurePostDraft(for: idea, context: context))
        let second = try XCTUnwrap(model.ensurePostDraft(for: idea, context: context))
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(first.status, .draft)
        XCTAssertEqual(first.platform, .youtubeShorts)
        XCTAssertNil(first.targetDate)
        XCTAssertNil(idea.agendaDate)
        XCTAssertEqual(idea.title, "The one-job idea")
        XCTAssertEqual(idea.notes, "A useful note to carry into the post.")
    }

    func testSuggestedAgendaDayIsNotPersistedUntilCreatorCommitsIt() {
        XCTAssertFalse(PostDraftTargetPersistencePolicy.shouldWriteTargetDate(
            hadPersistedTargetDate: false,
            explicitlyCommitted: false
        ))
        XCTAssertTrue(PostDraftTargetPersistencePolicy.shouldWriteTargetDate(
            hadPersistedTargetDate: false,
            explicitlyCommitted: true
        ))
        XCTAssertTrue(PostDraftTargetPersistencePolicy.shouldWriteTargetDate(
            hadPersistedTargetDate: true,
            explicitlyCommitted: false
        ))
    }

    func testDraftCanMoveBackToIdeaBankWithoutLosingItsContent() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())
        let date = Date(timeIntervalSince1970: 1_752_475_600)
        let draft = try XCTUnwrap(model.beginPostDraft(
            pillarID: nil,
            platform: .instagramReels,
            durationSeconds: 45,
            targetDate: date,
            context: context
        ))
        draft.brief.title = "A useful unfinished idea"
        draft.brief.notes = "Keep this creative direction."
        draft.output.recurrence = .weekly
        draft.output.recurrenceWeekdays = [.monday]

        XCTAssertTrue(model.movePostDraftToIdeaBank(
            brief: draft.brief,
            output: draft.output,
            context: context
        ))
        XCTAssertEqual(draft.brief.status, .spark)
        XCTAssertNil(draft.brief.agendaDate)
        XCTAssertNil(draft.output.targetDate)
        XCTAssertEqual(draft.output.status, .draft)
        XCTAssertEqual(draft.output.recurrence, .none)
        XCTAssertEqual(draft.brief.title, "A useful unfinished idea")
        XCTAssertEqual(draft.brief.notes, "Keep this creative direction.")
    }

    @MainActor
    func testStoreBootstrapBackfillsLegacyDataAndIsIdempotent() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Teach", selectedPlatforms: [.instagramReels, .youtubeVideo])
        let brief = CreativeBrief(title: "Legacy", premise: "A legacy post")
        let output = PlatformOutput(briefID: brief.id, platform: .youtubeVideo)
        output.durationSeconds = 0
        let task = CreatorTask(title: "Plan the pillar", kind: .planning, priority: .medium)
        task.bootstrapVersion = 0
        let first = Pillar(name: "First", colorHex: "55705B")
        let second = Pillar(name: "Second", colorHex: "416B85")
        first.bootstrapVersion = 0
        second.bootstrapVersion = 0
        context.insert(profile)
        context.insert(brief)
        context.insert(output)
        context.insert(task)
        context.insert(first)
        context.insert(second)
        try context.save()

        try StoreBootstrapService.run(context: context)
        let firstDestinationCount = try context.fetch(FetchDescriptor<PublishingDestination>()).count
        let firstFormatCount = try context.fetch(FetchDescriptor<PublishingFormat>()).count
        XCTAssertEqual(task.lane, .pillar)
        task.lane = .production
        try StoreBootstrapService.run(context: context)

        XCTAssertEqual(firstDestinationCount, 3)
        XCTAssertEqual(firstFormatCount, 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PublishingDestination>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PublishingFormat>()).count, 8)
        XCTAssertEqual(output.destinationID, PublishingCatalog.youtubeID)
        XCTAssertEqual(output.formatID, PublishingCatalog.youtubeVideoID)
        XCTAssertEqual(output.durationSeconds, brief.durationSeconds)
        XCTAssertEqual(task.priority, .none)
        XCTAssertEqual(task.lane, .production)
        XCTAssertEqual(profile.selectedDestinationIDs.count, 2)
        XCTAssertEqual([first, second].filter { $0.role == .anchor }.count, 1)
    }

    func testStoreBootstrapPreservesCreatorEditedTaskLanesAndPillarHierarchy() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let selectedAnchor = Pillar(role: .anchor, name: "Education")
        let selectedBranch = Pillar(parentPillarID: selectedAnchor.id, role: .supporting, name: "Tutorials")
        let legacyBranch = Pillar(name: "Legacy")
        legacyBranch.bootstrapVersion = 0
        let creatorEditedTask = CreatorTask(
            pillarID: selectedBranch.id,
            title: "A deliberately production-scoped task",
            kind: .planning,
            lane: .production
        )
        context.insert(selectedAnchor)
        context.insert(selectedBranch)
        context.insert(legacyBranch)
        context.insert(creatorEditedTask)
        try context.save()

        try StoreBootstrapService.run(context: context)
        try StoreBootstrapService.run(context: context)

        XCTAssertEqual(creatorEditedTask.lane, .production)
        XCTAssertEqual(selectedAnchor.role, .anchor)
        XCTAssertNil(selectedAnchor.parentPillarID)
        XCTAssertEqual(selectedBranch.role, .supporting)
        XCTAssertEqual(selectedBranch.parentPillarID, selectedAnchor.id)
        XCTAssertEqual(legacyBranch.role, .supporting)
        XCTAssertEqual(legacyBranch.parentPillarID, selectedAnchor.id)
        XCTAssertEqual(legacyBranch.bootstrapVersion, 1)
    }

    func testStoreBootstrapDeterministicallyMergesCloudKitSingletonDuplicates() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)

        let incompleteProfile = CreatorProfile(name: "", goal: "Recovered goal", createdAt: recent)
        incompleteProfile.telemetryConsent = true
        let completeProfile = CreatorProfile(
            name: "Chey",
            goal: "Create clearly",
            selectedPlatforms: [.instagramReels, .youtubeVideo],
            adultConfirmed: true,
            onboardingCompleted: true,
            createdAt: old
        )
        let example = VoiceExample(profileID: incompleteProfile.id, text: "A synced example")
        let pending = PendingVoiceProfileProposal(profileID: incompleteProfile.id, sourceVersion: 1, payloadJSON: "{}")
        let account = CreatorSocialAccount(
            profileID: incompleteProfile.id,
            destinationID: PublishingCatalog.instagramID,
            label: "@chey",
            profileURLString: "https://instagram.com/chey"
        )
        context.insert(incompleteProfile)
        context.insert(completeProfile)
        context.insert(example)
        context.insert(pending)
        context.insert(account)

        let oldSubscription = SubscriptionState(access: .paid, updatedAt: old)
        oldSubscription.freeBriefConsumed = true
        oldSubscription.ideationRequestsUsed = 3
        let currentSubscription = SubscriptionState(access: .expired, updatedAt: recent)
        currentSubscription.ideationRequestsUsed = 1
        context.insert(oldSubscription)
        context.insert(currentSubscription)

        context.insert(ReminderSettings(dailyEnabled: true, updatedAt: old))
        context.insert(ReminderSettings(weeklyEnabled: true, updatedAt: recent))
        context.insert(RhythmTemplate(name: "Active", entriesText: "Monday: plan", isActive: true, updatedAt: old))
        context.insert(RhythmTemplate(name: "Inactive", entriesText: "", isActive: false, updatedAt: recent))

        let calendar = Calendar.current
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: recent)?.start)
        context.insert(WeekPlan(weekStart: weekStart, rhythmEntriesText: "Monday: plan", createdAt: old))
        context.insert(WeekPlan(weekStart: weekStart.addingTimeInterval(2 * 86_400), notes: "Keep it light", createdAt: recent))
        try context.save()

        try StoreBootstrapService.run(context: context)
        try StoreBootstrapService.run(context: context)

        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profile.id, completeProfile.id)
        XCTAssertFalse(profile.telemetryConsent)
        XCTAssertEqual(example.profileID, profile.id)
        XCTAssertEqual(pending.profileID, profile.id)
        XCTAssertEqual(account.profileID, profile.id)

        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionState>())
        let subscription = try XCTUnwrap(subscriptions.first)
        XCTAssertEqual(subscriptions.count, 1)
        XCTAssertEqual(subscription.access, .expired)
        XCTAssertTrue(subscription.freeBriefConsumed)
        XCTAssertEqual(subscription.ideationRequestsUsed, 3)

        let reminders = try context.fetch(FetchDescriptor<ReminderSettings>())
        XCTAssertEqual(reminders.count, 1)
        XCTAssertTrue(try XCTUnwrap(reminders.first).weeklyEnabled)
        XCTAssertFalse(try XCTUnwrap(reminders.first).dailyEnabled)

        let templates = try context.fetch(FetchDescriptor<RhythmTemplate>())
        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates.first?.name, "Active")

        let plans = try context.fetch(FetchDescriptor<WeekPlan>())
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plan.rhythmEntriesText, "Monday: plan")
        XCTAssertEqual(plan.notes, "Keep it light")
        XCTAssertEqual(plan.weekStart, weekStart)
    }

    func testStoreBootstrapPreservesDisjointPlatformSelectionsWhenMergingProfiles() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let keeper = CreatorProfile(
            name: "Chey",
            goal: "Create clearly",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        keeper.selectedDestinationIDs = [PublishingCatalog.instagramID]
        let syncedDuplicate = CreatorProfile(
            selectedPlatforms: [.youtubeVideo, .tiktok],
            createdAt: Date(timeIntervalSince1970: 200)
        )
        syncedDuplicate.selectedDestinationIDs = [PublishingCatalog.youtubeID, PublishingCatalog.tiktokID]
        context.insert(keeper)
        context.insert(syncedDuplicate)
        try context.save()

        try StoreBootstrapService.run(context: context)

        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        let merged = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(merged.id, keeper.id)
        XCTAssertEqual(
            merged.selectedDestinationIDs,
            [PublishingCatalog.instagramID, PublishingCatalog.youtubeID, PublishingCatalog.tiktokID]
        )
        XCTAssertEqual(merged.selectedPlatforms, [.instagramReels, .youtubeVideo, .tiktok])
    }

    func testPopulatedFileBackedStoreReopensWithoutRewritingCreatorChoices() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentCyMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("AgentCy.store")
        let taskID = UUID()
        let anchorID = UUID()

        do {
            let container = try ModelContainerFactory.makeLocal(at: storeURL)
            let context = container.mainContext
            let anchor = Pillar(id: anchorID, role: .anchor, name: "Anchor")
            let task = CreatorTask(id: taskID, pillarID: anchor.id, title: "Creator choice", lane: .production)
            context.insert(CreatorProfile(name: "Chey", goal: "Create", adultConfirmed: true, onboardingCompleted: true))
            context.insert(SubscriptionState(access: .comped))
            context.insert(anchor)
            context.insert(task)
            try context.save()
        }

        do {
            let reopened = try ModelContainerFactory.makeLocal(at: storeURL)
            let context = reopened.mainContext
            try StoreBootstrapService.run(context: context)
            let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
            let pillars = try context.fetch(FetchDescriptor<Pillar>())
            let task = try XCTUnwrap(tasks.first(where: { $0.id == taskID }))
            let anchor = try XCTUnwrap(pillars.first(where: { $0.id == anchorID }))
            XCTAssertEqual(task.lane, .production)
            XCTAssertEqual(anchor.role, .anchor)
            XCTAssertNil(anchor.parentPillarID)
        }
    }

    func testStoreUsesCloudKitOnlyWhenTheBuildExplicitlyEnablesIt() {
        XCTAssertTrue(ModelContainerFactory.shouldUseCloudKit(
            cloudKitEnabled: true,
            forceLocalOnly: false
        ))
        XCTAssertFalse(ModelContainerFactory.shouldUseCloudKit(
            cloudKitEnabled: false,
            forceLocalOnly: false
        ))
        XCTAssertFalse(ModelContainerFactory.shouldUseCloudKit(
            cloudKitEnabled: true,
            forceLocalOnly: true
        ))
    }

    func testPostedStatusAndUnpostingRollback() throws {
        let brief = CreativeBrief(title: "Test", premise: "A premise", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .tiktok, status: .ready)
        BriefLifecycle.schedule(output, for: Date(), brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .scheduled)

        BriefLifecycle.togglePosted(output, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .posted)

        BriefLifecycle.togglePosted(output, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .scheduled)

        BriefLifecycle.schedule(output, for: nil, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .ready)
    }

    func testArchiveIsNotOverwrittenByDistributionSync() {
        let brief = CreativeBrief(title: "Archived", premise: "A premise", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .posted)
        BriefLifecycle.archive(brief)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .archived)
    }

    func testRecordingMilestoneOnlyFiresOnceForBriefFilmingTask() {
        let briefID = UUID()
        let brief = CreativeBrief(id: briefID, title: "Ready", premise: "A premise", status: .ready)
        let filming = CreatorTask(briefID: briefID, title: "Film", kind: .filming, isRecordingMilestoneDesignated: true)
        XCTAssertTrue(BriefLifecycle.toggleTask(filming, brief: brief))
        XCTAssertTrue(filming.recordingMilestoneEmitted)
        XCTAssertFalse(BriefLifecycle.toggleTask(filming, brief: brief))
        XCTAssertFalse(filming.isCompleted)
        XCTAssertFalse(BriefLifecycle.toggleTask(filming, brief: brief))

        let standalone = CreatorTask(title: "Film something", kind: .filming)
        XCTAssertFalse(BriefLifecycle.toggleTask(standalone))
    }

    func testExpiredAccessCanFinishButCannotCreate() {
        let state = SubscriptionState(access: .expired)
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: state))
        XCTAssertFalse(AccessPolicy.allows(.schedule, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        XCTAssertTrue(AccessPolicy.allows(.editExisting, state: state))
        XCTAssertTrue(AccessPolicy.allows(.updatePosting, state: state))
        XCTAssertTrue(AccessPolicy.allows(.export, state: state))
        XCTAssertTrue(AccessPolicy.allows(.erase, state: state))
    }

    func testDatedPromotionalAccessExpiresWithoutRelaunchingTheApp() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = SubscriptionState(
            access: .comped,
            trialEnd: now.addingTimeInterval(-1)
        )

        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: state, at: now))
        XCTAssertFalse(AccessPolicy.allows(.schedule, state: state, at: now))
        XCTAssertTrue(AccessPolicy.allows(.editExisting, state: state, at: now))
        XCTAssertTrue(AccessPolicy.allows(.export, state: state, at: now))
    }

    func testConsumedFreeJourneyFailsClosedForNewWork() {
        let state = SubscriptionState(access: .freeJourney)
        state.freeBriefConsumed = true
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: state))
        XCTAssertFalse(AccessPolicy.allows(.createTask, state: state))
        XCTAssertFalse(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        XCTAssertFalse(AccessPolicy.allows(.schedule, state: state))
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: nil))
        XCTAssertTrue(AccessPolicy.allows(.revise, state: state))
        XCTAssertTrue(AccessPolicy.allows(.teachCy, state: state))
        state.revisionRequestsUsed = 3
        state.teachCyUpdatesUsed = 1
        XCTAssertFalse(AccessPolicy.allows(.revise, state: state))
        XCTAssertFalse(AccessPolicy.allows(.teachCy, state: state))
    }

    func testFreeAllowanceCounters() {
        let state = SubscriptionState(access: .freeJourney)
        XCTAssertTrue(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        state.ideationRequestsUsed = 3
        state.revisionRequestsUsed = 3
        state.teachCyUpdatesUsed = 1
        XCTAssertFalse(AccessPolicy.allows(.ideate, state: state))
        XCTAssertFalse(AccessPolicy.allows(.revise, state: state))
        XCTAssertFalse(AccessPolicy.allows(.teachCy, state: state))
        XCTAssertTrue(AccessPolicy.allows(.compose, state: state))
    }

    func testPaidAccessIncludesSparkDialogueAndGlobalAskCy() {
        let state = SubscriptionState(access: .paid)
        XCTAssertTrue(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertTrue(AccessPolicy.allows(.askCy, state: state))
    }

    func testPlanningSparkUsesItsOwnAgendaDateWithoutCreatingATask() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())
        let monday = Date(timeIntervalSince1970: 1_752_475_600)
        let tuesday = monday.addingTimeInterval(86_400)

        let brief = try XCTUnwrap(model.createSpark(
            text: "A clear idea for this week",
            source: .text,
            targetDate: monday,
            context: context
        ))
        XCTAssertEqual(brief.agendaDate, monday)
        XCTAssertTrue(model.tasks(for: brief, context: context).isEmpty)

        XCTAssertTrue(model.plan(brief, on: tuesday, context: context))
        XCTAssertEqual(brief.agendaDate, tuesday)
        XCTAssertTrue(model.tasks(for: brief, context: context).isEmpty)
    }

    func testIdeaCaptureKeepsExplicitTitleNotesAndPillar() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let pillar = Pillar(name: "Lifestyle", colorHex: "55705B")
        context.insert(pillar)
        let model = AppModel(reminderService: PreviewReminderService())

        let brief = try XCTUnwrap(model.createSpark(
            text: "A short note about the idea.",
            source: .text,
            title: "Morning reset",
            notes: "A short note about the idea.",
            pillarID: pillar.id,
            context: context
        ))

        XCTAssertEqual(brief.title, "Morning reset")
        XCTAssertEqual(brief.notes, "A short note about the idea.")
        XCTAssertEqual(brief.pillarID, pillar.id)
    }

    func testQuickPostCreatesDraftOutputWithoutCreatingDuplicateTaskOrAdvancingLifecycle() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let pillar = Pillar(name: "Lifestyle", colorHex: "55705B")
        context.insert(pillar)
        let model = AppModel(reminderService: PreviewReminderService())
        let postDate = Date(timeIntervalSince1970: 1_752_475_600)

        let brief = try XCTUnwrap(model.createPost(
            title: "A quiet morning reset",
            notes: "Show the three things I do before opening my laptop.",
            pillarID: pillar.id,
            platform: .instagramReels,
            durationSeconds: 45,
            targetDate: postDate,
            context: context
        ))

        XCTAssertEqual(brief.status, .spark)
        XCTAssertEqual(brief.notes, "Show the three things I do before opening my laptop.")
        XCTAssertEqual(brief.pillarID, pillar.id)
        let output = try XCTUnwrap(model.outputs(for: brief, context: context).first)
        XCTAssertEqual(output.status, .draft)
        XCTAssertEqual(output.targetDate, postDate)
        XCTAssertEqual(brief.agendaDate, postDate)
        XCTAssertTrue(model.tasks(for: brief, context: context).isEmpty)

        let movedDate = postDate.addingTimeInterval(86_400)
        model.schedule(output: output, date: movedDate, context: context)
        XCTAssertEqual(output.targetDate, movedDate)
        XCTAssertEqual(brief.agendaDate, movedDate)
        XCTAssertEqual(output.status, .draft)
        XCTAssertEqual(brief.status, .spark)

        XCTAssertEqual(brief.status, .spark)
    }

    func testQuickPostCanOpenDirectlyIntoAnEmptyResumableDraft() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())
        let postDate = Date(timeIntervalSince1970: 1_752_475_600)

        let draft = try XCTUnwrap(model.beginPostDraft(
            pillarID: nil,
            platform: .instagramReels,
            destinationID: PublishingCatalog.instagramID,
            formatID: PublishingCatalog.instagramReelID,
            durationSeconds: 45,
            targetDate: postDate,
            context: context
        ))

        XCTAssertTrue(draft.brief.title.isEmpty)
        XCTAssertEqual(draft.brief.status, .spark)
        XCTAssertEqual(draft.brief.agendaDate, postDate)
        XCTAssertEqual(draft.output.status, .draft)
        XCTAssertEqual(draft.output.targetDate, postDate)
        XCTAssertEqual(draft.output.destinationID, PublishingCatalog.instagramID)
        XCTAssertEqual(draft.output.formatID, PublishingCatalog.instagramReelID)
    }

    func testPostDraftDuplicateCreatesAnIndependentEditableCopy() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())
        let postDate = Date(timeIntervalSince1970: 1_752_475_600)
        let original = try XCTUnwrap(model.beginPostDraft(
            pillarID: nil,
            platform: .instagramReels,
            durationSeconds: 45,
            targetDate: postDate,
            context: context
        ))
        original.brief.title = "A clear creative habit"
        original.brief.notes = "Show the habit in three simple beats."
        original.output.caption = "Save this for your next filming day."
        let task = CreatorTask(
            briefID: original.brief.id,
            platformOutputID: original.output.id,
            title: "Film the opening",
            kind: .filming,
            lane: .production,
            priority: .high
        )
        context.insert(task)
        context.insert(CreatorAttachment(
            ownerKind: .postMedia,
            briefID: original.brief.id,
            platformOutputID: original.output.id,
            fileName: "reference.jpg",
            kind: .photo,
            uniformTypeIdentifier: "public.jpeg",
            byteCount: 3,
            localRelativePath: "",
            cloudData: Data([1, 2, 3]),
            syncState: .synced
        ))
        try context.save()

        let duplicated = try XCTUnwrap(model.duplicatePostDraft(
            brief: original.brief,
            output: original.output,
            context: context
        ))

        XCTAssertNotEqual(duplicated.brief.id, original.brief.id)
        XCTAssertNotEqual(duplicated.output.id, original.output.id)
        XCTAssertEqual(duplicated.brief.title, "A clear creative habit copy")
        XCTAssertEqual(duplicated.brief.notes, original.brief.notes)
        XCTAssertEqual(duplicated.brief.status, .spark)
        XCTAssertEqual(duplicated.output.caption, original.output.caption)
        XCTAssertEqual(duplicated.output.status, .draft)
        XCTAssertEqual(duplicated.output.targetDate, postDate)

        let copiedTasks = model.tasks(for: duplicated.brief, context: context)
        XCTAssertEqual(copiedTasks.count, 1)
        XCTAssertEqual(copiedTasks.first?.title, "Film the opening")
        XCTAssertEqual(copiedTasks.first?.platformOutputID, duplicated.output.id)

        let copyBriefID = duplicated.brief.id
        let copiedAttachments = try context.fetch(FetchDescriptor<CreatorAttachment>(
            predicate: #Predicate { $0.briefID == copyBriefID }
        ))
        XCTAssertEqual(copiedAttachments.count, 1)
        XCTAssertEqual(copiedAttachments.first?.platformOutputID, duplicated.output.id)
    }

    func testOnlyCompletelyEmptyDraftOffersDirectTrashAction() {
        let brief = CreativeBrief(title: "", status: .spark)
        let output = PlatformOutput(briefID: brief.id, status: .draft)
        output.targetDate = Date()
        output.destinationID = PublishingCatalog.instagramID
        output.formatID = PublishingCatalog.instagramReelID

        XCTAssertTrue(EmptyPostDraftDeletionPolicy.shouldOfferDirectDelete(
            brief: brief,
            output: output,
            taskCount: 0,
            attachmentCount: 0
        ))

        brief.notes = "A rough direction"
        XCTAssertFalse(EmptyPostDraftDeletionPolicy.shouldOfferDirectDelete(
            brief: brief,
            output: output,
            taskCount: 0,
            attachmentCount: 0
        ))

        brief.notes = ""
        XCTAssertFalse(EmptyPostDraftDeletionPolicy.shouldOfferDirectDelete(
            brief: brief,
            output: output,
            taskCount: 1,
            attachmentCount: 0
        ))

        output.status = .scheduled
        XCTAssertFalse(EmptyPostDraftDeletionPolicy.shouldOfferDirectDelete(
            brief: brief,
            output: output,
            taskCount: 0,
            attachmentCount: 0
        ))
    }

    func testDeletingDraftRemovesItsLinkedWorkOnly() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let draft = CreativeBrief(title: "Draft", premise: "A premise", status: .developing)
        let otherBrief = CreativeBrief(title: "Keep", premise: "Another premise", status: .ready)
        let output = PlatformOutput(briefID: draft.id, platform: .instagramReels, status: .draft)
        let task = CreatorTask(briefID: draft.id, title: "Write caption", kind: .scripting)
        let attachment = CreatorAttachment(
            ownerKind: .referenceFile,
            briefID: draft.id,
            fileName: "reference.txt",
            kind: .document,
            uniformTypeIdentifier: "public.plain-text",
            byteCount: 8,
            localRelativePath: "references/reference.txt"
        )
        let proposal = PendingBriefProposal(
            briefID: draft.id,
            payloadJSON: "{}",
            proposalKindRaw: "composition"
        )
        let thread = ConversationThread(briefID: draft.id, contextKind: .brief, contextID: draft.id)
        let message = ConversationMessage(threadID: thread.id, role: .creator, text: "Help")
        context.insert(draft)
        context.insert(otherBrief)
        context.insert(output)
        context.insert(task)
        context.insert(attachment)
        context.insert(proposal)
        context.insert(thread)
        context.insert(message)
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.deleteDraft(draft, context: context))

        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).map(\.id), [otherBrief.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorAttachment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ConversationThread>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ConversationMessage>()).isEmpty)
    }

    func testPostRecurrenceKeepsOnlyRelevantDaySelections() {
        let output = PlatformOutput()

        output.seriesName = "Weekly creator diary"
        output.recurrence = .weekly
        output.recurrenceWeekdays = [.monday, .thursday]

        XCTAssertEqual(output.seriesName, "Weekly creator diary")
        XCTAssertEqual(output.recurrence, .weekly)
        XCTAssertEqual(output.recurrenceWeekdays, [.monday, .thursday])

        output.recurrence = .monthly
        output.recurrenceMonthDay = 14

        XCTAssertTrue(output.recurrenceWeekdays.isEmpty)
        XCTAssertEqual(output.recurrenceMonthDay, 14)

        output.recurrence = .none

        XCTAssertNil(output.recurrenceMonthDay)
    }

    func testSocialProfileLinksNormalizeAndNewPostsUseThePrimaryAccount() throws {
        XCTAssertEqual(
            CreatorSocialAccount.normalizedURLString("instagram.com/cheycreates"),
            "https://instagram.com/cheycreates"
        )
        XCTAssertNil(CreatorSocialAccount.normalizedURLString("not a profile link"))

        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Teach")
        let primary = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: PublishingCatalog.instagramID,
            label: "@cheycreates",
            profileURLString: "instagram.com/cheycreates",
            isPrimary: true,
            sortOrder: 0
        )
        let second = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: PublishingCatalog.instagramID,
            label: "@cheybts",
            profileURLString: "https://instagram.com/cheybts",
            sortOrder: 1
        )
        context.insert(profile)
        context.insert(primary)
        context.insert(second)
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())

        let defaultPost = try XCTUnwrap(model.createPost(
            title: "Primary account post",
            notes: "",
            pillarID: nil,
            platform: .instagramReels,
            destinationID: PublishingCatalog.instagramID,
            formatID: PublishingCatalog.instagramReelID,
            durationSeconds: 45,
            targetDate: Date(),
            context: context
        ))
        XCTAssertEqual(model.outputs(for: defaultPost, context: context).first?.socialAccountID, primary.id)

        let secondAccountPost = try XCTUnwrap(model.createPost(
            title: "Second account post",
            notes: "",
            pillarID: nil,
            platform: .instagramReels,
            destinationID: PublishingCatalog.instagramID,
            formatID: PublishingCatalog.instagramReelID,
            socialAccountID: second.id,
            durationSeconds: 45,
            targetDate: Date(),
            context: context
        ))
        XCTAssertEqual(model.outputs(for: secondAccountPost, context: context).first?.socialAccountID, second.id)
    }

    func testEnsureWeekSupportsNextWeekWithoutDuplicates() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())
        let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()

        let first = model.ensureWeek(startingAt: nextWeek, context: context)
        let second = model.ensureWeek(startingAt: nextWeek.addingTimeInterval(86_400), context: context)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeekPlan>()).count, 1)
    }

    func testLongFormYouTubePostKeepsFormatAwareDuration() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())

        let brief = try XCTUnwrap(model.createPost(
            title: "A complete creator workflow",
            notes: "Walk through the full process with examples.",
            pillarID: nil,
            platform: .youtubeVideo,
            durationSeconds: 480,
            targetDate: Date(),
            context: context
        ))

        XCTAssertEqual(brief.durationSeconds, 480)
        XCTAssertEqual(model.outputs(for: brief, context: context).first?.platform, .youtubeVideo)
        XCTAssertEqual(CreatorPlatform.choices(for: .longForm), [.youtubeVideo])
        XCTAssertEqual(ContentFormat.longForm.durationOptions, [180, 300, 480, 600, 900])
    }

    func testEligiblePlatformsCanBeAddedOnceAndEditedIndependently() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let brief = CreativeBrief(title: "A clear system", premise: "Show the system", status: .ready)
        brief.durationSeconds = 45
        let instagram = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready)
        instagram.caption = "Shared starting caption"
        instagram.cta = "Save this"
        context.insert(brief)
        context.insert(instagram)
        try context.save()
        let model = AppModel(reminderService: PreviewReminderService())

        let tiktok = try XCTUnwrap(model.addPlatformOutput(to: brief, platform: .tiktok, context: context))
        XCTAssertEqual(tiktok.status, .ready)
        XCTAssertEqual(tiktok.caption, "Shared starting caption")
        XCTAssertEqual(tiktok.cta, "Save this")
        XCTAssertTrue(tiktok.openingAdjustment.isEmpty)
        XCTAssertTrue(tiktok.editChanges.isEmpty)
        XCTAssertNil(model.addPlatformOutput(to: brief, platform: .tiktok, context: context))
        XCTAssertNil(model.addPlatformOutput(to: brief, platform: .youtubeVideo, context: context))

        let shorts = try XCTUnwrap(model.addPlatformOutput(to: brief, platform: .youtubeShorts, context: context))
        XCTAssertEqual(shorts.titleOverride, brief.title)
        XCTAssertEqual(model.outputs(for: brief, context: context).count, 3)
        XCTAssertEqual(brief.status, .ready)

        model.deletePlatformOutput(tiktok, from: brief, context: context)
        XCTAssertEqual(model.outputs(for: brief, context: context).map(\.platform), [.instagramReels, .youtubeShorts])
    }

    func testDeletingPlatformRecalculatesMasterStatusAndAgendaDate() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let target = Date().addingTimeInterval(3_600)
        let brief = CreativeBrief(title: "Two platforms", premise: "A premise", status: .posted)
        brief.agendaDate = target
        let posted = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .posted)
        posted.postedAt = Date()
        let scheduled = PlatformOutput(briefID: brief.id, platform: .tiktok, status: .scheduled)
        scheduled.targetDate = target
        context.insert(brief)
        context.insert(posted)
        context.insert(scheduled)
        try context.save()
        let model = AppModel(reminderService: PreviewReminderService())

        model.deletePlatformOutput(posted, from: brief, context: context)
        XCTAssertEqual(brief.status, .scheduled)
        XCTAssertEqual(brief.agendaDate, target)

        model.deletePlatformOutput(scheduled, from: brief, context: context)
        XCTAssertEqual(brief.status, .ready)
        XCTAssertNil(brief.agendaDate)
        XCTAssertTrue(model.outputs(for: brief, context: context).isEmpty)
    }

    func testSupportingPillarKeepsOwnColorAndDaysAndFallsBackSafely() {
        let anchor = Pillar(
            name: "Teaching",
            colorHex: "9B3A2E",
            assignedWeekdays: [.monday, .wednesday]
        )
        let branch = Pillar(
            parentPillarID: anchor.id,
            name: "Tutorials",
            colorHex: "416B85",
            assignedWeekdays: [.friday]
        )
        let pillars = [anchor, branch]

        XCTAssertEqual(branch.resolvedAnchor(in: pillars).id, anchor.id)
        XCTAssertEqual(branch.resolvedColorHex(in: pillars), "416B85")
        XCTAssertEqual(branch.resolvedWeekdays(in: pillars), [.friday])
        XCTAssertEqual(PillarWeekday.mondayFirst.map(\.letter), ["M", "T", "W", "T", "F", "S", "S"])

        anchor.isArchived = true
        XCTAssertEqual(branch.resolvedAnchor(in: pillars).id, branch.id)
        XCTAssertEqual(branch.resolvedColorHex(in: pillars), "416B85")
        XCTAssertEqual(branch.resolvedWeekdays(in: pillars), [.friday])
        XCTAssertEqual(branch.resolvedAnchor(in: [branch]).id, branch.id)
    }

    func testSubtasksCompleteIndependentlyAndDeleteWithParent() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())
        let parent = try XCTUnwrap(model.createTask(
            title: "Prepare the post",
            kind: .editing,
            priority: .high,
            targetDate: nil,
            context: context
        ))
        let first = try XCTUnwrap(model.createSubtask(title: "Choose the clips", parent: parent, context: context))
        let second = try XCTUnwrap(model.createSubtask(title: "Add captions", parent: parent, context: context))

        XCTAssertEqual(first.parentTaskID, parent.id)
        XCTAssertEqual(second.parentTaskID, parent.id)
        XCTAssertEqual(parent.priority, .high)
        XCTAssertEqual(first.priority, .high)
        XCTAssertEqual(second.priority, .high)
        XCTAssertEqual(model.subtasks(for: parent, context: context).map(\.title), ["Choose the clips", "Add captions"])

        model.toggleTask(first, context: context)
        XCTAssertTrue(first.isCompleted)
        XCTAssertFalse(parent.isCompleted)
        XCTAssertFalse(second.isCompleted)

        model.deleteTask(parent, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
    }

    func testLegacySimplifyPrefixIsRemovedFromSavedTasks() {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let task = CreatorTask(title: "Simplify: Read the brief aloud", kind: .scripting)
        context.insert(task)

        AppModel(reminderService: PreviewReminderService()).removeLegacySimplifyPrefixes(context: context)

        XCTAssertEqual(task.title, "Read the brief aloud")
    }

    func testAssistancePolicyControlsUnsolicitedPillarProposals() {
        XCTAssertEqual(AssistancePolicy(mode: .drive).pillarProposalLimit(explicitlyRequested: false), 0)
        XCTAssertEqual(AssistancePolicy(mode: .drive).pillarProposalLimit(explicitlyRequested: true), 3)
        XCTAssertEqual(AssistancePolicy(mode: .collaborate).pillarProposalLimit(explicitlyRequested: false), 1)
        XCTAssertEqual(AssistancePolicy(mode: .lead).pillarProposalLimit(explicitlyRequested: false), 3)
    }

    func testComposeStagesProposalUntilExplicitAcceptance() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Casey", goal: "Teach creators", selectedPlatforms: [.instagramReels, .tiktok], adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        context.insert(SubscriptionState())
        for index in 0..<3 { context.insert(VoiceExample(profileID: profile.id, text: "Example \(index) with a clear practical point.", sortOrder: index)) }
        let brief = CreativeBrief(title: "A rough spark", premise: "Make the first creative step smaller")
        context.insert(brief)
        let model = AppModel(reminderService: PreviewReminderService())

        await model.compose(brief: brief, context: context)

        XCTAssertNotNil(model.proposal(for: brief, context: context))
        XCTAssertTrue(brief.spokenHook.isEmpty)
        XCTAssertTrue(model.outputs(for: brief, context: context).isEmpty)
        XCTAssertTrue(model.tasks(for: brief, context: context).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).count == 1)
        XCTAssertTrue(try XCTUnwrap(model.subscriptionState(context)).freeBriefConsumed)

        let relaunchedModel = AppModel(reminderService: PreviewReminderService())
        let proposal = try XCTUnwrap(relaunchedModel.proposal(for: brief, context: context))
        relaunchedModel.acceptProposal(proposal, for: brief, context: context)
        XCTAssertFalse(brief.spokenHook.isEmpty)
        XCTAssertEqual(relaunchedModel.outputs(for: brief, context: context).count, 2)
        XCTAssertEqual(relaunchedModel.tasks(for: brief, context: context).count, 4)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
    }

    func testAcceptingRegenerationPreservesScheduledOutputAndCompletedTask() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Casey", goal: "Teach creators", selectedPlatforms: [.instagramReels], adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        let state = SubscriptionState(access: .paid)
        context.insert(state)
        let brief = CreativeBrief(title: "Keep this", premise: "A real premise", status: .developing)
        context.insert(brief)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.caption = "Accepted caption"
        output.targetDate = Date()
        context.insert(output)
        let task = CreatorTask(briefID: brief.id, title: "Completed filming", kind: .filming)
        task.isCompleted = true
        task.recordingMilestoneEmitted = true
        context.insert(task)
        let model = AppModel(reminderService: PreviewReminderService())

        await model.compose(brief: brief, context: context)
        let proposal = try XCTUnwrap(model.proposal(for: brief, context: context))
        model.acceptProposal(proposal, for: brief, context: context)

        XCTAssertEqual(model.outputs(for: brief, context: context).count, 1)
        XCTAssertEqual(output.caption, "Accepted caption")
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertTrue(task.isCompleted)
        XCTAssertTrue(task.recordingMilestoneEmitted)
    }

    func testDiscardClearsPersistedProposalAfterRelaunch() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Casey", goal: "Teach creators", selectedPlatforms: [.youtubeShorts], adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        context.insert(SubscriptionState(access: .paid))
        let brief = CreativeBrief(title: "Keep the spark", premise: "A useful starting point")
        context.insert(brief)
        let composingModel = AppModel(reminderService: PreviewReminderService())

        await composingModel.compose(brief: brief, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingBriefProposal>()).count, 1)

        let relaunchedModel = AppModel(reminderService: PreviewReminderService())
        XCTAssertNotNil(relaunchedModel.proposal(for: brief, context: context))
        relaunchedModel.discardProposal(for: brief, context: context)
        XCTAssertNil(relaunchedModel.proposal(for: brief, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
    }

    func testDevelopingBriefCannotScheduleOrPostButCanCompleteLinkedTask() {
        let brief = CreativeBrief(title: "Not approved", premise: "A premise", status: .developing)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready)
        let task = CreatorTask(briefID: brief.id, title: "Film", kind: .filming, isRecordingMilestoneDesignated: true)

        XCTAssertFalse(BriefLifecycle.schedule(output, for: Date(), brief: brief))
        XCTAssertNil(output.targetDate)
        XCTAssertEqual(output.status, .ready)
        XCTAssertFalse(BriefLifecycle.togglePosted(output, brief: brief))
        XCTAssertNil(output.postedAt)
        XCTAssertTrue(BriefLifecycle.toggleTask(task, brief: brief))
        XCTAssertTrue(task.isCompleted)
        BriefLifecycle.synchronize(brief, outputs: [output])
        XCTAssertEqual(brief.status, .developing)

        let standalone = CreatorTask(title: "Update media kit", kind: .creatorBusiness)
        XCTAssertFalse(BriefLifecycle.toggleTask(standalone))
        XCTAssertTrue(standalone.isCompleted)
    }

    func testLifecycleHistoryRecordsTransitionsRollbackAndArchiveWithoutDuplicates() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let brief = CreativeBrief(title: "History", premise: "A premise", createdAt: start)
        let output = PlatformOutput(briefID: brief.id, platform: .tiktok, status: .ready)

        BriefLifecycle.beginDevelopment(brief, now: start.addingTimeInterval(10))
        BriefLifecycle.approve(brief, now: start.addingTimeInterval(20))
        _ = BriefLifecycle.schedule(output, for: start.addingTimeInterval(3_600), brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(30))
        _ = BriefLifecycle.togglePosted(output, brief: brief, now: start.addingTimeInterval(40))
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(40))
        _ = BriefLifecycle.togglePosted(output, brief: brief, now: start.addingTimeInterval(50))
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(50))
        _ = BriefLifecycle.schedule(output, for: nil, brief: brief)
        BriefLifecycle.synchronize(brief, outputs: [output], now: start.addingTimeInterval(60))
        BriefLifecycle.archive(brief, now: start.addingTimeInterval(70))
        BriefLifecycle.archive(brief, now: start.addingTimeInterval(80))

        XCTAssertEqual(
            brief.lifecycleHistory.map(\.status),
            [.spark, .developing, .ready, .scheduled, .posted, .scheduled, .ready, .archived]
        )
        XCTAssertEqual(brief.lifecycleHistory.last?.date, start.addingTimeInterval(70))
    }

    func testPlatformOutputReplanMovesPausesAndArchivesCalmly() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let brief = CreativeBrief(title: "Replan", premise: "A premise", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = Date().addingTimeInterval(-3_600)
        context.insert(brief)
        context.insert(output)
        let model = AppModel(reminderService: PreviewReminderService())

        model.replan(output: output, choice: .move, context: context)
        XCTAssertGreaterThan(output.targetDate ?? .distantPast, Date())
        XCTAssertEqual(brief.status, .scheduled)
        model.replan(output: output, choice: .pause, context: context)
        XCTAssertNil(output.targetDate)
        XCTAssertEqual(brief.status, .ready)
        model.replan(output: output, choice: .archive, context: context)
        XCTAssertEqual(brief.status, .archived)
        XCTAssertEqual(brief.lifecycleHistory.last?.status, .archived)
    }

    func testAssistanceModeControlsDevelopmentThreadOpener() throws {
        func messageTexts(for mode: AssistanceMode) throws -> [String] {
            let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
            let context = container.mainContext
            context.insert(CreatorProfile(name: "Ari", goal: "Teach", assistanceMode: mode))
            let brief = CreativeBrief(title: "A spark", premise: "A premise")
            context.insert(brief)
            let model = AppModel(reminderService: PreviewReminderService())
            let thread = model.developmentThread(for: brief, context: context)
            return model.messages(for: thread, context: context).map(\.text)
        }

        XCTAssertTrue(try messageTexts(for: .drive).isEmpty)
        let collaborate = try messageTexts(for: .collaborate)
        XCTAssertEqual(collaborate.count, 1)
        XCTAssertTrue(collaborate[0].contains("one point"))
        let lead = try messageTexts(for: .lead)
        XCTAssertEqual(lead.count, 1)
        XCTAssertTrue(lead[0].contains("Recommended first step"))
        XCTAssertTrue(lead[0].contains("Assumption"))
    }

    func testDeniedNotificationPermissionTurnsReminderSettingsBackOff() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let settings = ReminderSettings(dailyEnabled: true, weeklyEnabled: true)
        context.insert(settings)
        let model = AppModel(reminderService: DeniedReminderService())

        await model.applyReminderSettings(settings, context: context)

        XCTAssertFalse(settings.dailyEnabled)
        XCTAssertFalse(settings.weeklyEnabled)
        XCTAssertEqual(model.notice?.message, "Notifications stayed off because permission was not available.")
    }

    func testSocialProfileLinksAreGeneratedFromHandles() {
        XCTAssertEqual(
            CreatorSocialAccount.profileURLString(forHandle: "@fromcheywithlove", destination: .instagram),
            "https://www.instagram.com/fromcheywithlove/"
        )
        XCTAssertEqual(
            CreatorSocialAccount.profileURLString(forHandle: "@chey.creates", destination: .tiktok),
            "https://www.tiktok.com/@chey.creates"
        )
        XCTAssertEqual(
            CreatorSocialAccount.profileURLString(forHandle: "CheyCreates", destination: .youtube),
            "https://www.youtube.com/@CheyCreates"
        )
        XCTAssertNil(CreatorSocialAccount.profileURLString(forHandle: "not a handle", destination: .instagram))
    }

    func testAgendaCompactsElapsedDaysUnlessARealScheduledPostWasMissed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))
        let past = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 9)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 9)))

        XCTAssertTrue(AgendaDayPresentation.shouldCompact(day: past, outputs: [], now: now, calendar: calendar))
        XCTAssertTrue(AgendaDayPresentation.shouldCompact(
            day: past,
            outputs: [AgendaOutputState(outputStatus: .posted, briefStatus: .posted)],
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(AgendaDayPresentation.shouldCompact(
            day: past,
            outputs: [AgendaOutputState(outputStatus: .draft, briefStatus: .spark)],
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(AgendaDayPresentation.shouldCompact(
            day: past,
            outputs: [AgendaOutputState(outputStatus: .scheduled, briefStatus: .developing)],
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(AgendaDayPresentation.shouldCompact(
            day: past,
            outputs: [AgendaOutputState(outputStatus: .posted, briefStatus: .posted),
                      AgendaOutputState(outputStatus: .scheduled, briefStatus: .scheduled)],
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(AgendaDayPresentation.shouldCompact(
            day: today,
            outputs: [AgendaOutputState(outputStatus: .posted, briefStatus: .posted)],
            now: now,
            calendar: calendar
        ))
    }

    func testAgendaOffersTaskCreationOnlyTodayAndLater() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))
        let past = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16)))
        let future = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17)))

        XCTAssertFalse(AgendaDayPresentation.allowsTaskCreation(day: past, now: now, calendar: calendar))
        XCTAssertTrue(AgendaDayPresentation.allowsTaskCreation(day: today, now: now, calendar: calendar))
        XCTAssertTrue(AgendaDayPresentation.allowsTaskCreation(day: future, now: now, calendar: calendar))
    }

    func testAgendaMarksOnlyUnpostedPastTargetsOverdue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))
        let past = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 18)))
        let future = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 8)))

        XCTAssertTrue(AgendaDayPresentation.isOverdue(targetDate: past, status: .scheduled, now: now, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.isOverdue(targetDate: past, status: .posted, now: now, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.isOverdue(targetDate: future, status: .scheduled, now: now, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.isOverdue(targetDate: nil, status: .draft, now: now, calendar: calendar))
    }

    func testAgendaUsesEarliestTaskTimeForUpcomingMetadata() throws {
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(AgendaDayPresentation.firstTaskDate(in: [second, nil, first]), first)
        XCTAssertNil(AgendaDayPresentation.firstTaskDate(in: [nil, nil]))
    }

    func testCollapsedPastDayPostCountUsesCorrectPluralization() {
        XCTAssertEqual(AgendaDayPresentation.postCountLabel(0), "0 posts")
        XCTAssertEqual(AgendaDayPresentation.postCountLabel(1), "1 post")
        XCTAssertEqual(AgendaDayPresentation.postCountLabel(2), "2 posts")
    }

    func testOnlyPastDayDrillDownShowsExplicitSaveControl() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12)))
        let past = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))

        XCTAssertTrue(AgendaDayPresentation.showsPastDaySaveControl(day: past, now: now, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.showsPastDaySaveControl(day: now, now: now, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.showsPastDaySaveControl(day: future, now: now, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.showsSaveControl(day: past, now: now, hasChanges: false, calendar: calendar))
        XCTAssertTrue(AgendaDayPresentation.showsSaveControl(day: past, now: now, hasChanges: true, calendar: calendar))
        XCTAssertFalse(AgendaDayPresentation.showsSaveControl(day: now, now: now, hasChanges: true, calendar: calendar))
    }

    func testEmptyAgendaDayUsesPlusInsteadOfChevron() {
        XCTAssertEqual(AgendaDayPresentation.trailingActionSymbol(hasPosts: false), "plus")
        XCTAssertEqual(AgendaDayPresentation.trailingActionSymbol(hasPosts: true), "chevron.right")
    }

    func testDayPillarAssignmentOverwritesTheWeekdayAndScheduledPostPillars() {
        let original = Pillar(name: "Original", colorHex: "55705B", assignedWeekdays: [.monday])
        let replacement = Pillar(name: "Replacement", colorHex: "416B85")
        let scheduledBrief = CreativeBrief(title: "Scheduled post", status: .scheduled)
        let untouchedBrief = CreativeBrief(title: "Another day", status: .scheduled)
        scheduledBrief.pillarID = original.id
        untouchedBrief.pillarID = original.id

        AgendaPillarAssignment.apply(
            selectedPillarID: replacement.id,
            weekday: .monday,
            pillars: [original, replacement],
            briefs: [scheduledBrief, untouchedBrief],
            affectedBriefIDs: [scheduledBrief.id]
        )

        XCTAssertFalse(original.assignedWeekdays.contains(.monday))
        XCTAssertTrue(replacement.assignedWeekdays.contains(.monday))
        XCTAssertEqual(scheduledBrief.pillarID, replacement.id)
        XCTAssertEqual(untouchedBrief.pillarID, original.id)
    }

    func testAgendaAlwaysSortsDraftsAfterScheduledPosts() {
        XCTAssertEqual(
            AgendaOutputOrdering.rank(outputStatus: .scheduled, briefStatus: .scheduled),
            0
        )
        XCTAssertEqual(
            AgendaOutputOrdering.rank(outputStatus: .posted, briefStatus: .posted),
            0
        )
        XCTAssertEqual(
            AgendaOutputOrdering.rank(outputStatus: .draft, briefStatus: .spark),
            1
        )
        XCTAssertEqual(
            AgendaOutputOrdering.rank(outputStatus: .scheduled, briefStatus: .developing),
            1
        )
    }

    func testDayAgendaHidesArchivedBriefOutputsAndTheirTasks() {
        let activeID = UUID()
        let archivedID = UUID()
        let activeBriefIDs: Set<UUID> = [activeID]

        XCTAssertTrue(AgendaContentVisibility.includesOutput(
            briefID: activeID,
            activeBriefIDs: activeBriefIDs
        ))
        XCTAssertFalse(AgendaContentVisibility.includesOutput(
            briefID: archivedID,
            activeBriefIDs: activeBriefIDs
        ))
        XCTAssertTrue(AgendaContentVisibility.includesTask(
            briefID: nil,
            activeBriefIDs: activeBriefIDs
        ))
        XCTAssertTrue(AgendaContentVisibility.includesTask(
            briefID: activeID,
            activeBriefIDs: activeBriefIDs
        ))
        XCTAssertFalse(AgendaContentVisibility.includesTask(
            briefID: archivedID,
            activeBriefIDs: activeBriefIDs
        ))
    }

    func testPillarChipColorsAreAdjustedWhenTheyBlendIntoTheSurface() {
        let paleYellow = AgentChipContrast.adjustedHex(pillarHex: "FFFFD8", against: "FDFDFB")
        let darkGray = AgentChipContrast.adjustedHex(pillarHex: "141414", against: "141414")

        XCTAssertNotEqual(paleYellow, "FFFFD8")
        XCTAssertNotEqual(darkGray, "141414")
        XCTAssertEqual(AgentChipContrast.foregroundHex(on: paleYellow), "141414")
        XCTAssertEqual(AgentChipContrast.foregroundHex(on: "141414"), "F5F6F3")
    }

    func testAgendaPillarDotsPreserveTheCreatorsExactColor() {
        XCTAssertEqual(
            AgendaPillarDotPresentation.displayedHex(storedHex: "FFFFD8"),
            "FFFFD8"
        )
        XCTAssertEqual(
            AgendaPillarDotPresentation.displayedHex(storedHex: "416B85"),
            "416B85"
        )
    }

    func testCaptureDraftResolverIgnoresEmptyFormsAndNamesNotesOnlyPosts() {
        XCTAssertNil(CaptureDraftResolver.ideaText("  \n "))
        XCTAssertEqual(CaptureDraftResolver.ideaText("  A useful idea  "), "A useful idea")
        XCTAssertNil(CaptureDraftResolver.postTitle(title: "", notes: "  "))
        XCTAssertEqual(
            CaptureDraftResolver.postTitle(title: "", notes: "  A rough post angle\nwith a second line  "),
            "A rough post angle with a second line"
        )
        XCTAssertEqual(CaptureDraftResolver.postTitle(title: "Named post", notes: "ignored"), "Named post")
    }

    func testCyUsesContextualPersonalityHeadings() {
        XCTAssertEqual(CyVoiceHeading.forMessage("What would feel easiest to film?", index: 0), .wantsToKnow)
        XCTAssertEqual(CyVoiceHeading.forMessage("I recommend starting with the hook.", index: 0), .thinksYouShould)
        XCTAssertEqual(CyVoiceHeading.forMessage("I noticed a pattern in your strongest ideas.", index: 0), .noticed)
        XCTAssertEqual(CyVoiceHeading.forMessage("Here is a clean first draft.", index: 0), .says)
        XCTAssertEqual(CyVoiceHeading.forMessage("Here is another direction.", index: 1), .hasAnIdea)
    }
}

@MainActor
private final class DeniedReminderService: ReminderServicing {
    func apply(_ settings: ReminderSettings) async throws {
        throw ReminderServiceError.permissionDenied
    }

    func applyFocusReminder(
        id: UUID,
        enabled: Bool,
        date: Date?,
        title: String,
        body: String
    ) async throws {
        throw ReminderServiceError.permissionDenied
    }

    func cancelAll() async {}
}
