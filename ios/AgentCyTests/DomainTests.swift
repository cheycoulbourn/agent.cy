import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class DomainTests: XCTestCase {
    func testCreatorFacingPostCopyFieldsStayCanonical() {
        XCTAssertEqual(
            CreatorPostCopyField.allCases.map(\.title),
            ["Hook", "Script", "Caption", "Call to action"]
        )
        XCTAssertEqual(CreatorPostCopyField.script.editorTitle, "Script (optional)")
        XCTAssertFalse(CreatorPostCopyField.allCases.map(\.title).contains("Ending"))
    }

    func testPaletteSelectionRecolorsFiveOrFewerPillarsInOrder() {
        let pillars = (0..<5).map { index in
            Pillar(name: "Pillar \(index + 1)", colorHex: "000000")
        }

        XCTAssertEqual(PillarPaletteAssignment.apply(.pastel, to: pillars), 5)
        XCTAssertEqual(pillars.map(\.colorHex), CreatorVibePalette.pastel.pillarColorHexes)
    }

    func testOnboardingOffersFourCuratedColorways() {
        XCTAssertEqual(
            CreatorVibePalette.onboardingPalettes,
            [.pastel, .neutral, .soho, .tooCool]
        )
        XCTAssertEqual(CreatorVibePalette.onboardingPalettes.count, 4)
    }

    func testPaletteSelectionLeavesMoreThanFivePillarsUnchanged() {
        let pillars = (0..<6).map { index in
            Pillar(name: "Pillar \(index + 1)", colorHex: "ABCDEF")
        }

        XCTAssertEqual(PillarPaletteAssignment.apply(.colorful, to: pillars), 0)
        XCTAssertTrue(pillars.allSatisfy { $0.colorHex == "ABCDEF" })
    }

    func testOverdueMyTaskCanMoveToTodayWithoutChangingItsFocusTemplate() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 16,
            hour: 9
        )))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let task = CreatorTask(
            title: "Finish the edit",
            targetDate: yesterday,
            dailyFocusDate: yesterday,
            focusTaskTemplateID: UUID()
        )
        context.insert(task)
        try context.save()

        AppModel(reminderService: PreviewReminderService()).moveTaskToToday(
            task,
            context: context,
            now: today
        )

        XCTAssertEqual(task.targetDate.map(calendar.startOfDay(for:)), calendar.startOfDay(for: today))
        XCTAssertEqual(task.dailyFocusDate.map(calendar.startOfDay(for:)), calendar.startOfDay(for: today))
        XCTAssertTrue(task.isFocusTemplateCustomized)
        XCTAssertNotNil(task.focusTaskTemplateID)
    }

    func testSkippingAnOverdueTaskDoesNotCompleteIt() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let task = CreatorTask(title: "Review the week", targetDate: Date().addingTimeInterval(-86_400))
        context.insert(task)
        try context.save()

        AppModel(reminderService: PreviewReminderService()).skipTask(task, context: context)

        XCTAssertTrue(task.isSkipped)
        XCTAssertNotNil(task.skippedAt)
        XCTAssertFalse(task.isCompleted)
    }

    func testUndoTaskCompletionRestoresTaskAndRemovesGeneratedRecurrence() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())
        let task = CreatorTask(
            title: "Plan next week",
            targetDate: Date(),
            recurrence: .weekly
        )
        context.insert(task)
        try context.save()

        model.toggleTask(task, context: context)

        XCTAssertTrue(task.isCompleted)
        XCTAssertNotNil(model.taskCompletionUndo)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).count, 2)

        model.undoLastTaskCompletion(context: context)

        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
        XCTAssertNil(model.taskCompletionUndo)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).count, 1)
    }

    func testConversationTitleKeepsWholeWordsAtTheLengthBoundary() {
        let prompt = "Keep shaping My favorite things to take with me on a trip"

        XCTAssertEqual(
            ConversationTitleFormatter.title(from: prompt),
            prompt
        )
        XCTAssertFalse(ConversationTitleFormatter.title(from: prompt).hasSuffix(" t"))
    }

    func testConversationTitleTruncatesOnlyBetweenWords() {
        XCTAssertEqual(
            ConversationTitleFormatter.title(
                from: "one two three four five",
                maximumLength: 13
            ),
            "one two three"
        )
    }

    func testConversationTitleRepairsAnExistingCharacterTruncatedTitle() {
        let prompt = "Keep shaping My favorite things to take with me on a trip"

        XCTAssertEqual(
            ConversationTitleFormatter.resolvedTitle(
                savedTitle: String(prompt.prefix(54)),
                firstCreatorMessage: prompt
            ),
            prompt
        )
    }

    func testPostActionRemovesDuplicateSendToPostSuggestion() {
        let suggestions = [
            ChatSuggestionWire(label: "Send to post", prompt: "Send this to a post"),
            ChatSuggestionWire(label: "Make the hook shorter", prompt: "Shorten the hook")
        ]

        let visible = CyChatActionPolicy.visibleSuggestions(
            suggestions,
            hasPostAction: true
        )

        XCTAssertEqual(visible.map(\.label), ["Make the hook shorter"])
    }

    func testPostActionKeepsSuggestionsWhenThereIsNoPostAction() {
        let suggestions = [
            ChatSuggestionWire(label: "Send to post", prompt: "Send this to a post")
        ]

        XCTAssertEqual(
            CyChatActionPolicy.visibleSuggestions(
                suggestions,
                hasPostAction: false
            ).map(\.label),
            ["Send to post"]
        )
    }

    func testSuggestedPostDateUsesTheNextAssignedPillarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 16,
            hour: 17
        )))

        let result = try XCTUnwrap(CyPostSchedulingPolicy.nextSuggestedDate(
            assignedWeekdays: [.monday, .wednesday],
            from: thursday,
            calendar: calendar
        ))

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: result),
            DateComponents(year: 2026, month: 7, day: 20)
        )
    }

    func testCyResponseCreatesOneUnscheduledPostDraft() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let pillar = Pillar(
            name: "Lifestyle",
            colorHex: "55705B",
            assignedWeekdays: [.monday]
        )
        context.insert(pillar)
        let model = AppModel(reminderService: PreviewReminderService())
        let response = "A realistic morning routine that makes the day feel easier."

        let result = try XCTUnwrap(model.createPostDraftFromCyResponse(
            response,
            pillarID: pillar.id,
            context: context
        ))

        XCTAssertEqual(result.brief.pillarID, pillar.id)
        XCTAssertEqual(result.brief.premise, "")
        XCTAssertEqual(result.brief.notes, response)
        XCTAssertEqual(result.output.status, .draft)
        XCTAssertNil(result.brief.agendaDate)
        XCTAssertNil(result.output.targetDate)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlatformOutput>()).count, 1)
    }

    func testDeletingConversationRemovesOnlyItsMessages() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let deletedThread = ConversationThread(title: "Delete me")
        let keptThread = ConversationThread(title: "Keep me")
        let deletedMessage = ConversationMessage(
            threadID: deletedThread.id,
            role: .creator,
            text: "Remove this transcript"
        )
        let keptMessage = ConversationMessage(
            threadID: keptThread.id,
            role: .creator,
            text: "Keep this transcript"
        )
        [deletedThread, keptThread].forEach(context.insert)
        [deletedMessage, keptMessage].forEach(context.insert)
        try context.save()

        try ConversationDeletionService.delete(
            deletedThread,
            messages: [deletedMessage, keptMessage],
            context: context
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationThread>()).map(\.id),
            [keptThread.id]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationMessage>()).map(\.id),
            [keptMessage.id]
        )
    }

    func testCreatorVibePalettesProvideAtLeastFiveDistinctPillarColors() {
        for palette in CreatorVibePalette.allCases {
            XCTAssertGreaterThanOrEqual(palette.pillarColorHexes.count, 5)
            XCTAssertEqual(Set(palette.pillarColorHexes).count, palette.pillarColorHexes.count)
            XCTAssertTrue(palette.pillarColorHexes.allSatisfy { $0.count == 6 })
        }
    }

    func testNamedCreatorPalettesMatchTheirReferenceColors() {
        XCTAssertEqual(CreatorVibePalette.grayscale.title, "Stone")
        XCTAssertEqual(CreatorVibePalette.pastel.title, "Soft Girl Era")
        XCTAssertEqual(CreatorVibePalette.neutral.title, "Aesthetica")
        XCTAssertEqual(CreatorVibePalette.colorful.title, "Vivrant Thing")
        XCTAssertEqual(CreatorVibePalette.dark.title, "(not) Vivrant Thing")
        XCTAssertEqual(CreatorVibePalette.soho.title, "Soho")
        XCTAssertEqual(CreatorVibePalette.midnight.pillarColorHexes, ["0D0502", "4C2421", "B2A998", "CBCAC2", "998368"])
        XCTAssertEqual(CreatorVibePalette.tooCool.pillarColorHexes, ["440607", "1B2345", "E3DFD4", "020202", "4F4439", "64646D"])
        XCTAssertEqual(CreatorVibePalette.scraper.title, "Scraper")
        XCTAssertEqual(CreatorVibePalette.scraper.pillarColorHexes, ["F15B3A", "101010", "2A2D2E", "E3E3E3", "E6E2A3", "FEFBFA"])
        XCTAssertEqual(CreatorVibePalette.allCases.suffix(3), [.soho, .tooCool, .scraper])
        XCTAssertEqual(CreatorVibePalette.signaturePalettes, [.soho, .tooCool, .scraper])
    }

    func testCreatorProfileStoresTwoCompleteCustomCyQuickPrompts() {
        let profile = CreatorProfile(name: "Chey")
        XCTAssertNil(profile.customCyQuickPrompts)

        profile.setCustomCyQuickPrompts([
            "  Plan my week  ",
            "Shape this idea"
        ])

        XCTAssertEqual(profile.customCyQuickPrompts, [
            "Plan my week",
            "Shape this idea"
        ])

        let longPrompt = String(repeating: "A", count: CreatorProfile.maxCyQuickPromptLength + 20)
        profile.setCustomCyQuickPrompts([longPrompt, "Second prompt"])
        XCTAssertEqual(profile.customCyQuickPrompts?.first?.count, CreatorProfile.maxCyQuickPromptLength)

        profile.restoreDefaultCyQuickPrompts()
        XCTAssertNil(profile.customCyQuickPrompts)
    }

    func testCyTaskAttentionUsesTaskPageVisibilityAndSeparatesPastDue() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))!
        let activeBriefID = UUID()
        let visibleDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 16))!
        let pastDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
        let futureDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23))!

        let visible = CreatorTask(briefID: activeBriefID, title: "Visible", targetDate: visibleDate)
        let pastDue = CreatorTask(title: "Past due", targetDate: pastDate)
        let hiddenFuture = CreatorTask(briefID: activeBriefID, title: "Future", targetDate: futureDate)
        let hiddenRecurring = CreatorTask(title: "Future focus", targetDate: futureDate)
        hiddenRecurring.focusTaskTemplateID = UUID()
        let completed = CreatorTask(title: "Completed", targetDate: visibleDate)
        completed.isCompleted = true
        let skipped = CreatorTask(title: "Skipped", targetDate: visibleDate)
        skipped.isSkipped = true

        let result = CyTaskAttentionPolicy.visibleOpenTasks(
            tasks: [visible, pastDue, hiddenFuture, hiddenRecurring, completed, skipped],
            activeBriefIDs: [activeBriefID],
            outputs: [],
            briefs: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(Set(result.map(\.title)), ["Visible", "Past due"])
        XCTAssertEqual(result.filter { CyTaskAttentionPolicy.isPastDue($0, now: now, calendar: calendar) }.count, 1)
    }

    func testConversationMessageStoresStructuredCyActions() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let briefID = UUID()
        let message = ConversationMessage(
            role: .cy,
            text: "**Try this hook.**",
            suggestions: [
                ChatSuggestionWire(label: "Make it shorter", prompt: "Shorten the hook")
            ],
            proposedAction: ChatProposedActionWire(
                kind: .reviseBrief,
                summary: "Apply the response to the post"
            ),
            referencedBriefID: briefID
        )
        context.insert(message)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<ConversationMessage>()).first)
        XCTAssertEqual(saved.chatSuggestions.count, 1)
        XCTAssertEqual(saved.chatSuggestions.first?.label, "Make it shorter")
        XCTAssertEqual(saved.proposedActionKind, .reviseBrief)
        XCTAssertEqual(saved.proposedActionSummary, "Apply the response to the post")
        XCTAssertEqual(saved.referencedBriefID, briefID)
    }

    func testConversationMessagePreservesCyTaskProposalDetails() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let postID = UUID()
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let message = ConversationMessage(
            role: .cy,
            text: "I prepared one task for you to review.",
            proposedAction: ChatProposedActionWire(
                kind: .createTask,
                summary: "Edit the first cut for DITL vlog.",
                task: ChatTaskProposalWire(
                    title: "Edit the first cut",
                    kind: .editing,
                    priority: .high,
                    targetDate: dueDate,
                    includesTargetTime: true,
                    postId: postID
                )
            )
        )
        context.insert(message)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<ConversationMessage>()).first)
        XCTAssertEqual(saved.proposedActionKind, .createTask)
        XCTAssertEqual(saved.proposedAction?.task?.title, "Edit the first cut")
        XCTAssertEqual(saved.proposedAction?.task?.kind, .editing)
        XCTAssertEqual(saved.proposedAction?.task?.priority, .high)
        XCTAssertEqual(saved.proposedAction?.task?.targetDate, dueDate)
        XCTAssertEqual(saved.proposedAction?.task?.postId, postID)
    }

    func testCreatorVibeAndAppearancePersistTogether() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey")
        profile.vibePalette = .pastel
        profile.appearance = .dark
        context.insert(profile)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CreatorProfile>()).first)
        XCTAssertEqual(saved.vibePalette, .pastel)
        XCTAssertEqual(saved.appearance, .dark)
    }

    func testSavingPostNotesDoesNotOverwritePremise() {
        let brief = CreativeBrief(
            title: "Review-safe post",
            premise: "The original premise",
            status: .spark
        )
        brief.notes = "Detailed production notes"

        PostDraftSavePolicy.prepare(brief)

        XCTAssertEqual(brief.premise, "The original premise")
        XCTAssertEqual(brief.notes, "Detailed production notes")
    }

    func testNewPostOptionalSectionsDefaultOnAndPersistCreatorChoices() throws {
        let defaults = CreatorProfile()
        XCTAssertTrue(defaults.showsHookInPostEditor)
        XCTAssertTrue(defaults.showsBrandDealsInPostEditor)
        XCTAssertTrue(defaults.showsMoodBoardsInPostEditor)

        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(
            showsHookInPostEditor: false,
            showsBrandDealsInPostEditor: true,
            showsMoodBoardsInPostEditor: false
        )
        context.insert(profile)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CreatorProfile>()).first)
        XCTAssertFalse(saved.showsHookInPostEditor)
        XCTAssertTrue(saved.showsBrandDealsInPostEditor)
        XCTAssertFalse(saved.showsMoodBoardsInPostEditor)
    }

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
        brief.spokenHook = "Start with this."
        brief.isBrandCollaboration = true
        brief.brandName = "Example Brand"
        brief.compensationType = .paid
        brief.compensationAmount = 1_250
        brief.compensationCurrencyCode = "USD"
        brief.brandHasNetTerms = true
        brief.brandNetTermsDays = 30
        brief.moodBoardEnabled = true
        brief.moodBoardURLString = "https://pinterest.com/example/board"
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        output.caption = "One useful caption."
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
        XCTAssertTrue(briefs.allSatisfy { $0.spokenHook == "Start with this." })
        XCTAssertTrue(briefs.allSatisfy { $0.brandName == "Example Brand" })
        XCTAssertTrue(briefs.allSatisfy { $0.compensationAmount == 1_250 })
        XCTAssertTrue(briefs.allSatisfy { $0.brandHasNetTerms && $0.brandNetTermsDays == 30 })
        XCTAssertTrue(briefs.allSatisfy { $0.moodBoardURLString == "https://pinterest.com/example/board" })
        XCTAssertTrue(outputs.allSatisfy { $0.caption == "One useful caption." })
    }

    func testDeletingRecurringPostAndFuturePreservesPastAndRemovesLinkedTasks() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let calendar = Calendar.current
        let dates = [1, 8, 15, 22].map { day in
            calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: 12))!
        }

        let pastBrief = CreativeBrief(title: "Past", status: .posted)
        let selectedBrief = CreativeBrief(title: "Selected", status: .scheduled)
        let futureBrief = CreativeBrief(title: "Future", status: .scheduled)
        let alreadyPostedBrief = CreativeBrief(title: "Posted early", status: .posted)
        let briefs = [pastBrief, selectedBrief, futureBrief, alreadyPostedBrief]
        briefs.forEach(context.insert)

        let root = PlatformOutput(briefID: pastBrief.id, status: .posted)
        root.targetDate = dates[0]
        root.recurrence = .weekly
        root.seriesRootOutputID = root.id
        let selected = PlatformOutput(briefID: selectedBrief.id, status: .scheduled)
        selected.targetDate = dates[1]
        selected.seriesRootOutputID = root.id
        let future = PlatformOutput(briefID: futureBrief.id, status: .scheduled)
        future.targetDate = dates[2]
        future.seriesRootOutputID = root.id
        let alreadyPosted = PlatformOutput(briefID: alreadyPostedBrief.id, status: .posted)
        alreadyPosted.targetDate = dates[3]
        alreadyPosted.seriesRootOutputID = root.id
        let outputs = [root, selected, future, alreadyPosted]
        outputs.forEach(context.insert)

        for (brief, output) in zip(briefs, outputs) {
            context.insert(CreatorTask(
                briefID: brief.id,
                platformOutputID: output.id,
                title: "Task for \(brief.title)",
                targetDate: output.targetDate
            ))
        }
        try context.save()

        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertTrue(model.deletePost(
            brief: selectedBrief,
            output: selected,
            scope: .thisAndFuture,
            context: context
        ))

        let remainingBriefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let remainingOutputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let remainingTasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertEqual(Set(remainingBriefs.map(\.title)), ["Past", "Posted early"])
        XCTAssertEqual(Set(remainingOutputs.map(\.id)), [root.id, alreadyPosted.id])
        XCTAssertEqual(Set(remainingTasks.map(\.briefID).compactMap { $0 }), [pastBrief.id, alreadyPostedBrief.id])
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

    func testScheduledPostCanMoveBackToIdeaBankAndClearItsPostWork() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())
        let date = Date(timeIntervalSince1970: 1_752_475_600)
        let brief = CreativeBrief(title: "A post to reconsider", premise: "", status: .scheduled)
        brief.notes = "Keep this direction as an idea."
        brief.agendaDate = date
        let reel = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        reel.targetDate = date
        reel.includesTargetTime = true
        reel.recurrence = .weekly
        reel.recurrenceWeekdays = [.monday]
        let short = PlatformOutput(briefID: brief.id, platform: .youtubeShorts, status: .scheduled)
        short.targetDate = date
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: reel.id,
            title: "Edit the post",
            kind: .editing,
            targetDate: date
        )
        context.insert(brief)
        context.insert(reel)
        context.insert(short)
        context.insert(task)
        try context.save()

        XCTAssertTrue(model.movePostToIdeaBank(brief: brief, output: reel, context: context))
        XCTAssertEqual(brief.status, .spark)
        XCTAssertNil(brief.agendaDate)
        XCTAssertEqual(brief.notes, "Keep this direction as an idea.")
        XCTAssertEqual(reel.status, .draft)
        XCTAssertNil(reel.targetDate)
        XCTAssertEqual(reel.recurrence, .none)
        XCTAssertEqual(short.status, .draft)
        XCTAssertNil(short.targetDate)
        XCTAssertEqual(short.recurrence, .none)
        XCTAssertFalse(reel.includesTargetTime)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
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

    func testStoreBootstrapKeepsCanonicalDestinationAndRewritesProfileSelection() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let duplicateID = UUID()
        let duplicate = PublishingDestination(
            id: duplicateID,
            name: "Instagram duplicate",
            builtInKind: .instagram,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let profile = CreatorProfile(name: "Chey", goal: "Create")
        profile.selectedDestinationIDs = [duplicateID]
        context.insert(duplicate)
        context.insert(profile)
        try context.save()

        try StoreBootstrapService.run(context: context)
        try StoreBootstrapService.run(context: context)

        let instagram = try context.fetch(FetchDescriptor<PublishingDestination>())
            .filter { $0.builtInKind == .instagram }
        XCTAssertEqual(instagram.map(\.id), [PublishingCatalog.instagramID])
        XCTAssertEqual(profile.selectedDestinationIDs, [PublishingCatalog.instagramID])
    }

    func testStoreBootstrapDoesNotLetNewerFreeDuplicateErasePaidAccess() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let paid = SubscriptionState(
            access: .paid,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerFree = SubscriptionState(
            access: .freeJourney,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        newerFree.ideationRequestsUsed = 2
        context.insert(paid)
        context.insert(newerFree)
        try context.save()

        try StoreBootstrapService.run(context: context)

        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionState>())
        let merged = try XCTUnwrap(subscriptions.first)
        XCTAssertEqual(subscriptions.count, 1)
        XCTAssertEqual(merged.access, .paid)
        XCTAssertNil(merged.trialEnd)
        XCTAssertEqual(merged.ideationRequestsUsed, 2)
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

    func testConsumedFreeJourneyKeepsManualCreationAvailableButLocksCy() {
        let state = SubscriptionState(access: .freeJourney)
        state.freeBriefConsumed = true
        XCTAssertTrue(AccessPolicy.allows(.createSpark, state: state))
        XCTAssertTrue(AccessPolicy.allows(.createTask, state: state))
        XCTAssertFalse(AccessPolicy.allows(.sparkDialogue, state: state))
        XCTAssertFalse(AccessPolicy.allows(.askCy, state: state))
        XCTAssertTrue(AccessPolicy.allows(.schedule, state: state))
        XCTAssertFalse(AccessPolicy.allows(.createSpark, state: nil))
        XCTAssertTrue(AccessPolicy.allows(.revise, state: state))
        XCTAssertTrue(AccessPolicy.allows(.teachCy, state: state))
        state.revisionRequestsUsed = 3
        state.teachCyUpdatesUsed = 1
        XCTAssertFalse(AccessPolicy.allows(.revise, state: state))
        XCTAssertFalse(AccessPolicy.allows(.teachCy, state: state))
    }

    func testQuickCaptureModesAreMutuallyExclusive() {
        let model = AppModel(reminderService: PreviewReminderService())

        model.setQuickCaptureMode(.cyIdeas)
        XCTAssertTrue(model.quickCaptureStartsWithIdeas)

        model.setQuickCaptureMode(.post)
        XCTAssertTrue(model.quickCaptureStartsWithPost)
        XCTAssertFalse(model.quickCaptureStartsWithIdeas)
        XCTAssertFalse(model.quickCaptureStartsWithTask)

        model.setQuickCaptureMode(.task)
        XCTAssertTrue(model.quickCaptureStartsWithTask)
        XCTAssertFalse(model.quickCaptureStartsWithIdeas)
        XCTAssertFalse(model.quickCaptureStartsWithPost)

        model.setQuickCaptureMode(.idea)
        XCTAssertFalse(model.quickCaptureStartsWithIdeas)
        XCTAssertFalse(model.quickCaptureStartsWithPost)
        XCTAssertFalse(model.quickCaptureStartsWithTask)
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
        XCTAssertFalse(output.includesTargetTime)
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
        XCTAssertFalse(draft.output.includesTargetTime)
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
        original.brief.spokenHook = "Try this opening."
        original.brief.isBrandCollaboration = true
        original.brief.brandName = "Sample Partner"
        original.brief.compensationType = .both
        original.brief.compensationAmount = 950
        original.brief.compensationCurrencyCode = "USD"
        original.brief.brandHasNetTerms = true
        original.brief.brandNetTermsDays = 45
        original.brief.giftedProductDescription = "A camera bag"
        original.brief.moodBoardEnabled = true
        original.brief.moodBoardURLString = "https://cosmos.so/example"
        original.output.caption = "Save this for your next filming day."
        original.output.publishedURLString = "https://instagram.com/p/original"
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
        XCTAssertEqual(duplicated.brief.spokenHook, original.brief.spokenHook)
        XCTAssertEqual(duplicated.brief.brandName, "Sample Partner")
        XCTAssertEqual(duplicated.brief.compensationType, .both)
        XCTAssertEqual(duplicated.brief.compensationAmount, 950)
        XCTAssertEqual(duplicated.brief.brandNetTermsDays, 45)
        XCTAssertEqual(duplicated.brief.giftedProductDescription, "A camera bag")
        XCTAssertEqual(duplicated.brief.moodBoardURLString, "https://cosmos.so/example")
        XCTAssertEqual(duplicated.brief.status, .spark)
        XCTAssertEqual(duplicated.output.caption, original.output.caption)
        XCTAssertTrue(duplicated.output.publishedURLString.isEmpty)
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
        brief.moodBoardEnabled = true
        XCTAssertFalse(EmptyPostDraftDeletionPolicy.shouldOfferDirectDelete(
            brief: brief,
            output: output,
            taskCount: 0,
            attachmentCount: 0
        ))

        brief.moodBoardEnabled = false
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
            durationSeconds: 600,
            targetDate: Date(),
            context: context
        ))

        XCTAssertEqual(brief.durationSeconds, 600)
        XCTAssertEqual(model.outputs(for: brief, context: context).first?.platform, .youtubeVideo)
        XCTAssertEqual(CreatorPlatform.choices(for: .longForm), [.youtubeVideo])
        XCTAssertEqual(ContentFormat.shortForm.durationOptions, [30, 60, 90, 180])
        XCTAssertEqual(ContentFormat.longForm.durationOptions, [600, 1_200, 1_800, 2_700, 3_600])
        XCTAssertEqual(ContentFormat.shortForm.defaultDuration, 60)
        XCTAssertEqual(ContentFormat.longForm.defaultDuration, 600)
        XCTAssertEqual(ContentDurationLabel.compact(180), "3 MIN")
        XCTAssertEqual(ContentDurationLabel.compact(3_600), "1 HR")
        XCTAssertEqual(ContentDurationLabel.full(3_600), "1 hour")
    }

    func testShortFormPostKeepsThreeMinuteDuration() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        let model = AppModel(reminderService: PreviewReminderService())

        let brief = try XCTUnwrap(model.createPost(
            title: "A three-minute story",
            notes: "Keep the full short-form story intact.",
            pillarID: nil,
            platform: .instagramReels,
            durationSeconds: 180,
            targetDate: Date(),
            context: context
        ))

        XCTAssertEqual(brief.durationSeconds, 180)
        XCTAssertEqual(model.outputs(for: brief, context: context).first?.durationSeconds, 180)
        XCTAssertEqual(model.outputs(for: brief, context: context).first?.platform, .instagramReels)
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

    func testRemovingAnchorArchivesItsBranchesAndKeepsTheirWorkUnfiled() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let anchor = Pillar(role: .anchor, name: "Lifestyle")
        let branch = Pillar(parentPillarID: anchor.id, name: "Beauty")
        let unrelated = Pillar(role: .anchor, name: "Business")
        let anchorBrief = CreativeBrief(title: "Morning routine")
        anchorBrief.pillarID = anchor.id
        let branchBrief = CreativeBrief(title: "Everyday makeup")
        branchBrief.pillarID = branch.id
        let unrelatedBrief = CreativeBrief(title: "Launch notes")
        unrelatedBrief.pillarID = unrelated.id
        let task = CreatorTask(pillarID: branch.id, title: "Film the routine", lane: .pillar)

        [anchor, branch, unrelated].forEach(context.insert)
        [anchorBrief, branchBrief, unrelatedBrief].forEach(context.insert)
        context.insert(task)
        try context.save()

        try PillarRemovalService.remove(
            anchor,
            pillars: [anchor, branch, unrelated],
            briefs: [anchorBrief, branchBrief, unrelatedBrief],
            tasks: [task],
            context: context
        )

        XCTAssertTrue(anchor.isArchived)
        XCTAssertTrue(branch.isArchived)
        XCTAssertFalse(unrelated.isArchived)
        XCTAssertNil(anchorBrief.pillarID)
        XCTAssertNil(branchBrief.pillarID)
        XCTAssertNil(task.pillarID)
        XCTAssertEqual(unrelatedBrief.pillarID, unrelated.id)
        XCTAssertEqual(PillarRemovalService.IDsRemoved(with: branch, pillars: [anchor, branch]), [branch.id])
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
        XCTAssertFalse(parent.includesTargetTime)
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

    func testTaskCollectionsUsePostAssociationRatherThanLegacyLane() {
        XCTAssertEqual(
            TaskCollectionPolicy.collection(briefID: UUID(), platformOutputID: nil),
            .postTasks
        )
        XCTAssertEqual(
            TaskCollectionPolicy.collection(briefID: nil, platformOutputID: UUID()),
            .postTasks
        )
        XCTAssertEqual(
            TaskCollectionPolicy.collection(briefID: nil, platformOutputID: nil),
            .myTasks
        )
    }

    func testTasksPageLimitsPostTasksToCurrentMondayThroughSunday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: 12
        )))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 23)))
        let previousSunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 23)))
        let nextMonday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))

        XCTAssertTrue(TaskListVisibilityPolicy.includes(
            collection: .postTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: monday,
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(TaskListVisibilityPolicy.includes(
            collection: .postTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: sunday,
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(TaskListVisibilityPolicy.includes(
            collection: .postTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: previousSunday,
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(TaskListVisibilityPolicy.includes(
            collection: .postTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: nextMonday,
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(TaskListVisibilityPolicy.includes(
            collection: .postTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: nil,
            now: now,
            calendar: calendar
        ))

        XCTAssertTrue(TaskListVisibilityPolicy.includes(
            collection: .myTasks,
            focusTaskTemplateID: UUID(),
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: sunday,
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(TaskListVisibilityPolicy.includes(
            collection: .myTasks,
            focusTaskTemplateID: UUID(),
            recurrence: .none,
            recurrenceRootTaskID: nil,
            targetDate: nextMonday,
            now: now,
            calendar: calendar
        ))

        let sevenDaysOut = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: now))
        let eightDaysOut = try XCTUnwrap(calendar.date(byAdding: .day, value: 8, to: now))
        XCTAssertTrue(TaskListVisibilityPolicy.includes(
            collection: .myTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: UUID(),
            targetDate: sevenDaysOut,
            now: now,
            calendar: calendar
        ))
        XCTAssertFalse(TaskListVisibilityPolicy.includes(
            collection: .myTasks,
            focusTaskTemplateID: nil,
            recurrence: .none,
            recurrenceRootTaskID: UUID(),
            targetDate: eightDaysOut,
            now: now,
            calendar: calendar
        ))
    }

    func testReschedulingPostAlignsItsOpenLinkedTasksToPostDay() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let postDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 15, hour: 14
        )))
        let newPostDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: postDate))
        let taskDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 10
        )))

        let brief = CreativeBrief(title: "Post", premise: "Test", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = postDate
        let outputTask = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Edit post",
            targetDate: taskDate,
            includesTargetTime: true
        )
        let briefTask = CreatorTask(
            briefID: brief.id,
            title: "Write caption",
            targetDate: taskDate
        )
        let undatedTask = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Publish post"
        )
        let completedTask = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Film",
            targetDate: taskDate
        )
        completedTask.isCompleted = true
        let unrelatedTask = CreatorTask(title: "Personal task", targetDate: taskDate)
        context.insert(brief)
        context.insert(output)
        [outputTask, briefTask, undatedTask, completedTask, unrelatedTask].forEach(context.insert)

        AppModel(reminderService: PreviewReminderService()).schedule(
            output: output,
            date: newPostDate,
            context: context
        )

        let expectedTimedTaskDate = PostTaskReschedulePolicy.alignedDate(
            taskDate,
            to: newPostDate,
            includesTime: true
        )
        let expectedDateOnlyTaskDate = Calendar.current.startOfDay(for: newPostDate)
        XCTAssertEqual(outputTask.targetDate, expectedTimedTaskDate)
        XCTAssertEqual(briefTask.targetDate, expectedDateOnlyTaskDate)
        XCTAssertEqual(undatedTask.targetDate, expectedDateOnlyTaskDate)
        XCTAssertEqual(completedTask.targetDate, taskDate)
        XCTAssertEqual(unrelatedTask.targetDate, taskDate)
    }

    func testFirstSchedulingAssignsOpenPostTasksToPostDay() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let scheduledDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 17, hour: 14
        )))
        let staleTaskDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16, hour: 10
        )))

        let brief = CreativeBrief(title: "Post", premise: "Test", status: .ready)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready)
        let datedTask = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Edit post",
            targetDate: staleTaskDate,
            includesTargetTime: true
        )
        let undatedTask = CreatorTask(
            briefID: brief.id,
            title: "Write caption"
        )
        context.insert(brief)
        context.insert(output)
        context.insert(datedTask)
        context.insert(undatedTask)

        AppModel(reminderService: PreviewReminderService()).schedule(
            output: output,
            date: scheduledDate,
            context: context
        )

        XCTAssertTrue(calendar.isDate(try XCTUnwrap(datedTask.targetDate), inSameDayAs: scheduledDate))
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(undatedTask.targetDate), inSameDayAs: scheduledDate))
    }

    func testTaskAddedToScheduledPostInheritsPostingDay() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let scheduledDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 17, hour: 14
        )))
        let brief = CreativeBrief(title: "Post", premise: "Test", status: .scheduled)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = scheduledDate
        context.insert(brief)
        context.insert(output)

        let task = try XCTUnwrap(AppModel(reminderService: PreviewReminderService()).createTask(
            title: "Write caption",
            kind: .scripting,
            lane: .production,
            targetDate: nil,
            briefID: brief.id,
            platformOutputID: output.id,
            context: context
        ))

        XCTAssertTrue(calendar.isDate(try XCTUnwrap(task.targetDate), inSameDayAs: scheduledDate))
        XCTAssertFalse(task.includesTargetTime)
    }

    func testPostTaskScheduleRepairRunsOnceForOpenPostTasks() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let suiteName = "PostTaskScheduleRepairTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let postDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16, hour: 14
        )))
        let staleTaskDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 15, hour: 9
        )))

        let brief = CreativeBrief(title: "Post", premise: "Test", status: .scheduled)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = postDate
        let linkedTask = CreatorTask(
            briefID: brief.id,
            platformOutputID: output.id,
            title: "Film",
            targetDate: staleTaskDate,
            includesTargetTime: true
        )
        let briefTask = CreatorTask(
            briefID: brief.id,
            title: "General post task",
            targetDate: staleTaskDate
        )
        let personalTask = CreatorTask(
            title: "Personal task",
            targetDate: staleTaskDate
        )
        context.insert(brief)
        context.insert(output)
        context.insert(linkedTask)
        context.insert(briefTask)
        context.insert(personalTask)

        XCTAssertEqual(try PostTaskScheduleRepairService.reconcileOnce(
            context: context,
            defaults: defaults,
            calendar: calendar
        ), 2)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(linkedTask.targetDate), inSameDayAs: postDate))
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(briefTask.targetDate), inSameDayAs: postDate))
        XCTAssertEqual(personalTask.targetDate, staleTaskDate)

        linkedTask.targetDate = staleTaskDate
        XCTAssertEqual(try PostTaskScheduleRepairService.reconcileOnce(
            context: context,
            defaults: defaults,
            calendar: calendar
        ), 0)
        XCTAssertEqual(linkedTask.targetDate, staleTaskDate)
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

    func testDeniedNotificationPermissionPreservesReminderChoices() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let settings = ReminderSettings(dailyEnabled: true, weeklyEnabled: true)
        context.insert(settings)
        let model = AppModel(reminderService: DeniedReminderService())

        await model.applyReminderSettings(settings, context: context)

        XCTAssertTrue(settings.dailyEnabled)
        XCTAssertTrue(settings.weeklyEnabled)
        XCTAssertEqual(model.notice?.message, "Notifications are turned off for agent.cy in iPhone Settings.")
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

    func testPostCalendarMarksEveryDateAssignedToAPillarWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let tuesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
        let markers = [
            PillarCalendarMarker(weekday: .monday, colorHex: "FFFFD8"),
            PillarCalendarMarker(weekday: .monday, colorHex: "ffffd8"),
            PillarCalendarMarker(weekday: .monday, colorHex: "416B85"),
            PillarCalendarMarker(weekday: .tuesday, colorHex: "9B3A2E")
        ]

        XCTAssertEqual(markers.colorHexes(for: monday, calendar: calendar), ["FFFFD8", "416B85"])
        XCTAssertEqual(markers.colorHexes(for: tuesday, calendar: calendar), ["9B3A2E"])
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

    func testCyMarkdownParserPreservesReadableResponseHierarchy() {
        let blocks = CyMarkdownParser.blocks(from: """
        # Plan your week

        Start with three posts.

        - Monday: Lifestyle
        - Wednesday: Beauty
        1. Choose the strongest idea
        """)

        XCTAssertEqual(blocks.map(\.kind), [
            .heading(level: 1),
            .paragraph,
            .bullet,
            .bullet,
            .numbered(marker: "1")
        ])
        XCTAssertEqual(blocks.map(\.text), [
            "Plan your week",
            "Start with three posts.",
            "Monday: Lifestyle",
            "Wednesday: Beauty",
            "Choose the strongest idea"
        ])
    }

    func testCyMarkdownParserBreaksUpDenseInlineLabels() {
        let blocks = CyMarkdownParser.blocks(
            from: "Start with three posts. **Draft week:** **Monday — Lifestyle:** Film a day in your life. **Questions:** Which pillar matters most?"
        )

        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].text, "Start with three posts.")
        XCTAssertEqual(blocks[1].text, "**Draft week:**")
        XCTAssertEqual(blocks[2].text, "**Monday — Lifestyle:** Film a day in your life.")
        XCTAssertEqual(blocks[3].text, "**Questions:** Which pillar matters most?")
    }

    func testWorkspaceScopeKeepsLegacyNilRecordsInDefaultAccountOnly() {
        let profileID = UUID()
        let first = CreatorWorkspace(profileID: profileID, name: "Primary", sortOrder: 0)
        let second = CreatorWorkspace(profileID: profileID, name: "Second", sortOrder: 1)

        XCTAssertTrue(WorkspaceScope.includes(nil, activeWorkspaceID: first.id, workspaces: [first, second]))
        XCTAssertFalse(WorkspaceScope.includes(nil, activeWorkspaceID: second.id, workspaces: [first, second]))
        XCTAssertTrue(WorkspaceScope.includes(second.id, activeWorkspaceID: second.id, workspaces: [first, second]))
        XCTAssertFalse(WorkspaceScope.includes(first.id, activeWorkspaceID: second.id, workspaces: [first, second]))
    }

    func testActiveCreatorIdentityChangesWithWorkspace() {
        let profile = CreatorProfile(name: "Chey", avatarImageData: Data([0x01]))
        let first = CreatorWorkspace(
            profileID: profile.id,
            name: "@fromcheywithlove",
            creatorName: "Chey",
            avatarImageData: Data([0x02]),
            hasCustomIdentity: true,
            sortOrder: 0
        )
        let second = CreatorWorkspace(
            profileID: profile.id,
            name: "@secondaccount",
            creatorName: "Cheyenne",
            avatarImageData: Data([0x03]),
            hasCustomIdentity: true,
            sortOrder: 1
        )

        XCTAssertEqual(
            ActiveCreatorIdentity.resolve(
                profile: profile,
                workspaces: [first, second],
                preferredWorkspaceID: first.id
            ),
            ActiveCreatorIdentity(name: "Chey", avatarImageData: Data([0x02]))
        )
        XCTAssertEqual(
            ActiveCreatorIdentity.resolve(
                profile: profile,
                workspaces: [first, second],
                preferredWorkspaceID: second.id
            ),
            ActiveCreatorIdentity(name: "Cheyenne", avatarImageData: Data([0x03]))
        )
    }

    func testActiveCreatorIdentityFallsBackForLegacyWorkspace() {
        let profile = CreatorProfile(name: "Chey", avatarImageData: Data([0x01]))
        let workspace = CreatorWorkspace(
            profileID: profile.id,
            name: "@legacy",
            creatorName: "@legacy",
            avatarImageData: Data([0x02]),
            hasCustomIdentity: false
        )

        XCTAssertEqual(
            ActiveCreatorIdentity.resolve(
                profile: profile,
                workspaces: [workspace],
                preferredWorkspaceID: workspace.id
            ),
            ActiveCreatorIdentity(name: "Chey", avatarImageData: Data([0x01]))
        )
    }

    func testInstagramProfilePhotoLoaderAcceptsProfileLinks() throws {
        let links = [
            "https://www.instagram.com/fromcheywithlove/",
            "https://instagram.com/fromcheywithlove",
        ]

        for link in links {
            let url = try XCTUnwrap(URL(string: link))
            XCTAssertTrue(InstagramProfilePhotoLoader.isSupportedProfileURL(url), link)
        }
    }

    func testInstagramProfilePhotoLoaderRejectsNonProfileLinks() throws {
        let links = [
            "http://instagram.com/fromcheywithlove",
            "https://example.com/fromcheywithlove",
            "https://instagram.com/p/example",
            "https://instagram.com/reel/example",
            "https://instagram.com/fromcheywithlove/tagged",
        ]

        for link in links {
            let url = try XCTUnwrap(URL(string: link))
            XCTAssertFalse(InstagramProfilePhotoLoader.isSupportedProfileURL(url), link)
        }
    }

    func testWorkspaceDeletionRemovesOnlySelectedAccountContent() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", onboardingCompleted: true)
        let deletedWorkspace = CreatorWorkspace(profileID: profile.id, name: "@delete", sortOrder: 0)
        let keptWorkspace = CreatorWorkspace(profileID: profile.id, name: "@keep", sortOrder: 1)
        let deletedAccount = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: PublishingCatalog.instagramID,
            label: "@delete",
            profileURLString: "https://instagram.com/delete"
        )
        deletedAccount.workspaceID = deletedWorkspace.id
        let keptAccount = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: PublishingCatalog.instagramID,
            label: "@keep",
            profileURLString: "https://instagram.com/keep"
        )
        keptAccount.workspaceID = keptWorkspace.id

        let deletedBrief = CreativeBrief(title: "Delete me")
        deletedBrief.workspaceID = deletedWorkspace.id
        let keptBrief = CreativeBrief(title: "Keep me")
        keptBrief.workspaceID = keptWorkspace.id
        let deletedTask = CreatorTask(briefID: deletedBrief.id, title: "Delete task")
        deletedTask.workspaceID = deletedWorkspace.id
        let keptTask = CreatorTask(briefID: keptBrief.id, title: "Keep task")
        keptTask.workspaceID = keptWorkspace.id
        let deletedThread = ConversationThread(title: "Delete chat")
        deletedThread.workspaceID = deletedWorkspace.id
        let keptThread = ConversationThread(title: "Keep chat")
        keptThread.workspaceID = keptWorkspace.id
        let deletedMessage = ConversationMessage(threadID: deletedThread.id, text: "Delete message")
        let keptMessage = ConversationMessage(threadID: keptThread.id, text: "Keep message")

        context.insert(profile)
        context.insert(deletedWorkspace)
        context.insert(keptWorkspace)
        context.insert(deletedAccount)
        context.insert(keptAccount)
        context.insert(deletedBrief)
        context.insert(keptBrief)
        context.insert(deletedTask)
        context.insert(keptTask)
        context.insert(deletedThread)
        context.insert(keptThread)
        context.insert(deletedMessage)
        context.insert(keptMessage)
        try context.save()

        try WorkspaceDeletionService.delete(workspaceID: deletedWorkspace.id, context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorWorkspace>()).map(\.id), [keptWorkspace.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorSocialAccount>()).map(\.id), [keptAccount.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).map(\.id), [keptBrief.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).map(\.id), [keptTask.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationThread>()).map(\.id), [keptThread.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationMessage>()).map(\.id), [keptMessage.id])
    }

    func testWorkspaceMigrationPartitionsExistingAccountsAndTheirPosts() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", onboardingCompleted: true)
        let instagramID = PublishingCatalog.instagramID
        let firstAccount = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: instagramID,
            label: "@first",
            profileURLString: "https://instagram.com/first",
            isPrimary: true,
            sortOrder: 0
        )
        let secondAccount = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: instagramID,
            label: "@second",
            profileURLString: "https://instagram.com/second",
            sortOrder: 1
        )
        let firstBrief = CreativeBrief(title: "First account post")
        let secondBrief = CreativeBrief(title: "Second account post")
        let firstOutput = PlatformOutput(briefID: firstBrief.id, socialAccountID: firstAccount.id)
        let secondOutput = PlatformOutput(briefID: secondBrief.id, socialAccountID: secondAccount.id)
        context.insert(profile)
        context.insert(firstAccount)
        context.insert(secondAccount)
        context.insert(firstBrief)
        context.insert(secondBrief)
        context.insert(firstOutput)
        context.insert(secondOutput)

        try StoreBootstrapService.run(context: context)

        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        XCTAssertEqual(workspaces.count, 2)
        XCTAssertNotEqual(firstAccount.workspaceID, secondAccount.workspaceID)
        XCTAssertEqual(firstBrief.workspaceID, firstAccount.workspaceID)
        XCTAssertEqual(firstOutput.workspaceID, firstAccount.workspaceID)
        XCTAssertEqual(secondBrief.workspaceID, secondAccount.workspaceID)
        XCTAssertEqual(secondOutput.workspaceID, secondAccount.workspaceID)
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
