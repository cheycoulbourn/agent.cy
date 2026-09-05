import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class WidgetTests: XCTestCase {
    func testWidgetSnapshotStoreRoundTripsWithoutUsingTheProductionSuite() throws {
        let suite = "AgentCyWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let expected = AgentCyWidgetSnapshot.preview
        try AgentCyWidgetSnapshotStore.save(expected, defaults: defaults)
        let actual = try XCTUnwrap(AgentCyWidgetSnapshotStore.load(defaults: defaults))

        XCTAssertEqual(try canonicalData(actual), try canonicalData(expected))
    }

    func testWidgetTaskCompletionUpdatesSnapshotAndFocusProgress() throws {
        var snapshot = AgentCyWidgetSnapshot.preview
        let task = try XCTUnwrap(snapshot.productionTasks.first(where: { !$0.isCompleted }))
        let previousProgress = try XCTUnwrap(snapshot.focus?.completedTaskCount)

        XCTAssertTrue(snapshot.setTaskCompletion(taskID: task.id, isCompleted: true))
        XCTAssertTrue(try XCTUnwrap(snapshot.productionTasks.first { $0.id == task.id }).isCompleted)
        XCTAssertEqual(snapshot.focus?.completedTaskCount, previousProgress + 1)
        XCTAssertFalse(snapshot.openProductionTasks(in: task.lane ?? .production).contains { $0.id == task.id })
    }

    func testWidgetTaskCompletionActionStoreKeepsLatestActionPerTask() throws {
        let suite = "AgentCyWidgetActionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let taskID = UUID()
        let first = WidgetTaskCompletionAction(taskID: taskID, isCompleted: true)
        let latest = WidgetTaskCompletionAction(taskID: taskID, isCompleted: false)

        try WidgetTaskCompletionActionStore.enqueue(first, defaults: defaults)
        try WidgetTaskCompletionActionStore.enqueue(latest, defaults: defaults)

        XCTAssertEqual(try WidgetTaskCompletionActionStore.pending(defaults: defaults), [latest])
        try WidgetTaskCompletionActionStore.remove([latest], defaults: defaults)
        XCTAssertTrue(try WidgetTaskCompletionActionStore.pending(defaults: defaults).isEmpty)
    }

    func testPhoneFeatureLaunchRequestIsConsumedOnce() throws {
        let suite = "AgentCyPhoneFeatureLaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        PhoneFeatureLaunchRequestStore.request(.voiceSpark, defaults: defaults)

        XCTAssertEqual(PhoneFeatureLaunchRequestStore.take(defaults: defaults), .voiceSpark)
        XCTAssertNil(PhoneFeatureLaunchRequestStore.take(defaults: defaults))
    }

    func testPhoneQuickActionHeaderKeepsTopControlsBelowTheSafeArea() {
        XCTAssertEqual(AgentQuickAddLayout.phoneHeaderHeight, 72)
        XCTAssertEqual(AgentQuickAddLayout.phoneHeaderTopPadding, 12)
    }

    func testRetiredCreatorSessionRoutesAreIgnoredAndConsumed() throws {
        XCTAssertNil(AgentCyDeepLink(url: try XCTUnwrap(URL(string: "agentcy://creator-session"))))
        let suite = "AgentCyRetiredRouteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("creatorSession", forKey: "agentCy.phoneFeature.pendingRoute.v1")

        XCTAssertNil(PhoneFeatureLaunchRequestStore.take(defaults: defaults))
        XCTAssertNil(defaults.string(forKey: "agentCy.phoneFeature.pendingRoute.v1"))
    }

    func testPendingWidgetTaskCompletionReconcilesIntoSwiftData() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let task = CreatorTask(title: "Finish the edit", targetDate: Date())
        context.insert(task)
        try context.save()

        let suite = "AgentCyWidgetReconcileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let action = WidgetTaskCompletionAction(taskID: task.id, isCompleted: true)
        try WidgetTaskCompletionActionStore.enqueue(action, defaults: defaults)

        let model = AppModel(reminderService: PreviewReminderService())
        model.applyPendingWidgetTaskCompletions(
            context: context,
            defaults: defaults,
            refreshWidgets: false
        )

        XCTAssertTrue(task.isCompleted)
        XCTAssertNotNil(task.completedAt)
        XCTAssertTrue(try WidgetTaskCompletionActionStore.pending(defaults: defaults).isEmpty)
    }

    func testWidgetDeepLinksRoundTrip() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let briefID = UUID()
        let destinations: [AgentCyDeepLink] = [
            .today,
            .agenda(day: nil),
            .agenda(day: day),
            .tasks,
            .pillars,
            .ideaBank,
            .quickIdea,
            .quickPost,
            .quickTask,
            .voiceSpark,
            .brief(briefID),
        ]

        for destination in destinations {
            let decoded = try XCTUnwrap(AgentCyDeepLink(url: destination.url))
            switch (destination, decoded) {
            case (.agenda(let expected?), .agenda(let actual?)):
                XCTAssertTrue(Calendar.current.isDate(expected, inSameDayAs: actual))
            default:
                XCTAssertEqual(decoded, destination)
            }
        }

        let removedSavedPostURL = try XCTUnwrap(
            URL(string: "agentcy://saved-post/00000000-0000-0000-0000-000000000001")
        )
        XCTAssertNil(AgentCyDeepLink(url: removedSavedPostURL))
    }

    func testSnapshotContainsFocusNextPostIdeaAndProductionWork() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = try XCTUnwrap(
            Calendar.current.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: Date()
            )
        )
        let weekday = try XCTUnwrap(PillarWeekday(rawValue: Calendar.current.component(.weekday, from: now)))

        let profile = CreatorProfile(name: "Chey")
        let pillar = Pillar(name: "Lifestyle", colorHex: "5E8069")
        let brief = CreativeBrief(title: "The small shift", premise: "A premise", status: .ready)
        brief.pillarID = pillar.id
        brief.updatedAt = now
        let idea = CreativeBrief(title: "A fresh angle", premise: "A thought", status: .spark)
        idea.pillarID = pillar.id
        idea.updatedAt = now.addingTimeInterval(10)
        let voiceSpark = CreativeBrief(
            title: "A spoken thought",
            premise: "A thought I recorded",
            source: .voiceTranscript,
            status: .spark
        )
        voiceSpark.pillarID = pillar.id
        voiceSpark.ideaBankPlacement = .idea
        voiceSpark.updatedAt = now.addingTimeInterval(5)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = now
        let task = CreatorTask(
            briefID: brief.id,
            title: "Film the opening",
            kind: .filming,
            targetDate: now.addingTimeInterval(1_800)
        )
        let pillarTask = CreatorTask(
            pillarID: pillar.id,
            title: "Outline a Lifestyle series",
            kind: .planning,
            lane: .pillar,
            targetDate: now.addingTimeInterval(2_400)
        )
        let focus = DailyFocusTemplateEntry(
            weekday: weekday,
            kind: .filming,
            title: "Filming",
            note: "Batch the camera work together.",
            durationMinutes: 90
        )
        context.insert(profile)
        context.insert(pillar)
        context.insert(brief)
        context.insert(idea)
        context.insert(voiceSpark)
        context.insert(output)
        context.insert(task)
        context.insert(pillarTask)
        context.insert(focus)
        try context.save()

        let snapshot = try WidgetSnapshotService.makeSnapshot(context: context, now: now)

        XCTAssertEqual(snapshot.creatorName, "Chey")
        XCTAssertEqual(snapshot.focus?.title, "Filming")
        XCTAssertEqual(snapshot.nextPost?.title, "The small shift")
        XCTAssertEqual(snapshot.nextPost?.pillarColorHex, "5E8069")
        XCTAssertEqual(snapshot.latestIdea?.title, "A fresh angle")
        XCTAssertEqual(snapshot.latestVoiceSpark?.title, "A spoken thought")
        XCTAssertEqual(snapshot.productionTasks.first?.title, "Film the opening")
        XCTAssertEqual(snapshot.productionTasks.map(\.lane), [.production, .pillar])
        XCTAssertEqual(snapshot.week.count, 7)
        XCTAssertEqual(snapshot.week.reduce(0) { $0 + ($1.postCount ?? 0) }, 1)
        XCTAssertEqual(snapshot.pillarUsage?.leadingPillarName, "Lifestyle")
        XCTAssertEqual(snapshot.pillarUsage?.leadingPercentage, 100)
        XCTAssertNil(snapshot.consistency?.goal, "No workspace goal is set in this fixture")
        XCTAssertEqual(snapshot.consistency?.postedDayCount, 0)
        XCTAssertEqual(snapshot.consistency?.days?.count, 7)
        XCTAssertEqual(snapshot.consistency?.currentPlannedCount, 0)
        XCTAssertEqual(snapshot.consistency?.currentPostedCount, 0)
    }

    func testPillarUsageSnapshotKeepsAnchorFirstAndIncludesEveryActivePillar() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = try XCTUnwrap(
            Calendar.current.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: Date()
            )
        )
        let anchor = Pillar(role: .anchor, name: "Lifestyle", colorHex: "8A5A3B")
        let beauty = Pillar(
            parentPillarID: anchor.id,
            role: .supporting,
            name: "Beauty",
            colorHex: "AFBCC6"
        )
        let business = Pillar(
            parentPillarID: anchor.id,
            role: .supporting,
            name: "Business",
            colorHex: "6B6136"
        )
        let community = Pillar(
            parentPillarID: anchor.id,
            role: .supporting,
            name: "Community",
            colorHex: "C9B48D"
        )
        let education = Pillar(
            parentPillarID: anchor.id,
            role: .supporting,
            name: "Education",
            colorHex: "416B85"
        )

        for (index, pillar) in [anchor, beauty, beauty].enumerated() {
            let brief = CreativeBrief(title: "Post \(index)", status: .scheduled)
            brief.pillarID = pillar.id
            let output = PlatformOutput(
                briefID: brief.id,
                platform: .instagramReels,
                status: .scheduled
            )
            output.targetDate = now.addingTimeInterval(Double(index * 60))
            context.insert(brief)
            context.insert(output)
        }
        context.insert(anchor)
        context.insert(beauty)
        context.insert(business)
        context.insert(community)
        context.insert(education)
        try context.save()

        let usage = try XCTUnwrap(
            WidgetSnapshotService.makeSnapshot(context: context, now: now).pillarUsage
        )
        let percentages = Dictionary(uniqueKeysWithValues: usage.segments.map { ($0.name, $0.percentage) })

        XCTAssertEqual(
            usage.segments.map(\.name),
            ["Lifestyle", "Beauty", "Business", "Community", "Education"]
        )
        XCTAssertEqual(
            percentages,
            ["Lifestyle": 33, "Beauty": 67, "Business": 0, "Community": 0, "Education": 0]
        )
        XCTAssertEqual(usage.leadingPillarName, "Lifestyle")
        XCTAssertEqual(usage.leadingPercentage, 33)
    }

    func testPillarUsagePresentationDoesNotSubstitutePreviewDataInProduction() {
        XCTAssertNil(
            WidgetPillarUsagePresentation.usage(
                for: .empty,
                isPreview: false
            )
        )
        XCTAssertEqual(
            WidgetPillarUsagePresentation.usage(
                for: .empty,
                isPreview: true
            ),
            AgentCyWidgetSnapshot.preview.pillarUsage
        )
    }

    func testPillarUsageBarWidthsStopAtTheWidgetContentInset() {
        let totalWidth: CGFloat = 300
        let widths = WidgetPillarBarLayout.segmentWidths(
            percentages: [33, 50, 17],
            totalWidth: totalWidth
        )
        let renderedWidth = widths.reduce(0, +)
            + WidgetPillarBarLayout.segmentSpacing * CGFloat(widths.count - 1)

        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(renderedWidth, totalWidth, accuracy: 0.001)
        XCTAssertTrue(widths.allSatisfy { $0 >= 8 })
    }

    func testSnapshotDoesNotPromoteTomorrowPostIntoTodaysWidget() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_784_050_200)
        let brief = CreativeBrief(title: "Tomorrow's post", status: .scheduled)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: now))
        context.insert(brief)
        context.insert(output)
        try context.save()

        let snapshot = try WidgetSnapshotService.makeSnapshot(context: context, now: now)

        XCTAssertNil(snapshot.nextPost)
    }

    func testSnapshotToleratesDuplicatePublishingMetadataAfterCloudSync() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_784_050_200)
        let destinationID = UUID()
        let formatID = UUID()
        let brief = CreativeBrief(title: "Cloud-synced post", status: .scheduled)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.destinationID = destinationID
        output.formatID = formatID
        output.targetDate = now

        context.insert(brief)
        context.insert(output)
        context.insert(PublishingDestination(id: destinationID, name: "Instagram"))
        context.insert(PublishingDestination(id: destinationID, name: "Instagram"))
        context.insert(PublishingFormat(id: formatID, destinationID: destinationID, name: "Reel", kind: .shortVideo))
        context.insert(PublishingFormat(id: formatID, destinationID: destinationID, name: "Reel", kind: .shortVideo))
        try context.save()

        let snapshot = try WidgetSnapshotService.makeSnapshot(context: context, now: now)

        XCTAssertEqual(snapshot.nextPost?.platformLabel, "Instagram · Reel")
    }

    func testSnapshotDoesNotPromoteUndatedDraftIntoTodaysWidget() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_784_050_200)
        let brief = CreativeBrief(title: "Idea bank draft", status: .spark)
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .draft)
        context.insert(brief)
        context.insert(output)
        try context.save()

        let snapshot = try WidgetSnapshotService.makeSnapshot(context: context, now: now)

        XCTAssertNil(snapshot.nextPost)
    }

    // Widget request 2026-08-19: the consistency tile mirrors the in-app goal
    // card. The wire format stays additive so installed widgets keep decoding.
    func testConsistencySnapshotWireFormatStaysAdditiveForInstalledWidgets() throws {
        let legacyJSON = Data("""
        {"completedWeeks":[true,false],"streak":1,"currentPostedCount":2,"currentPlannedCount":3}
        """.utf8)
        let legacy = try JSONDecoder().decode(WidgetConsistencySnapshot.self, from: legacyJSON)
        XCTAssertEqual(legacy.streak, 1)
        XCTAssertNil(legacy.days)
        XCTAssertNil(legacy.postedDayCount)
        XCTAssertNil(legacy.goal)

        let current = WidgetConsistencySnapshot(
            completedWeeks: [false, true],
            streak: 1,
            currentPostedCount: 2,
            currentPlannedCount: 4,
            days: [WidgetConsistencyDaySnapshot(date: Date(timeIntervalSince1970: 1_787_000_000), hasPost: true)],
            postedDayCount: 2,
            goal: 4
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
        let keys = Set(try XCTUnwrap(object as? [String: Any]).keys)
        for legacyKey in ["completedWeeks", "streak", "currentPostedCount", "currentPlannedCount"] {
            XCTAssertTrue(keys.contains(legacyKey), "Installed widgets still decode \(legacyKey)")
        }
    }

    func testConsistencySnapshotCountsDistinctPostedDaysAgainstTheWorkspaceGoal() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let calendar = Calendar.current
        func date(_ day: Int, hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
        }
        let now = date(19, hour: 12) // Wednesday; the week runs Mon 8/17 – Sun 8/23

        let workspace = CreatorWorkspace(profileID: UUID(), name: "@goal")
        workspace.weeklyPostingGoal = 2
        let brief = CreativeBrief(title: "Posted work", premise: "A premise", status: .posted)
        context.insert(workspace)
        context.insert(brief)
        // Two posts on Monday count as one day; Wednesday's post has no
        // postedAt and falls back to its target date. Last week's Tuesday and
        // Thursday posts put that week on the goal too.
        let postedDates: [(postedAt: Date?, targetDate: Date?)] = [
            (date(17, hour: 8), nil),
            (date(17, hour: 19), nil),
            (nil, date(19)),
            (date(11), nil),
            (date(13), nil),
        ]
        for entry in postedDates {
            let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .posted)
            output.postedAt = entry.postedAt
            output.targetDate = entry.targetDate
            context.insert(output)
        }
        try context.save()

        let snapshot = try WidgetSnapshotService.makeSnapshot(
            context: context,
            now: now,
            workspaceID: workspace.id
        )

        let consistency = try XCTUnwrap(snapshot.consistency)
        XCTAssertEqual(consistency.goal, 2)
        XCTAssertEqual(consistency.postedDayCount, 2)
        XCTAssertEqual(consistency.days?.map(\.hasPost), [true, false, true, false, false, false, false])
        XCTAssertEqual(consistency.streak, 2, "Last week and this week both hit the goal")
        XCTAssertEqual(Array(consistency.completedWeeks.suffix(2)), [true, true])
        XCTAssertFalse(consistency.completedWeeks.prefix(6).contains(true))
        // The legacy fields mirror the goal story for installed widgets.
        XCTAssertEqual(consistency.currentPostedCount, 2)
        XCTAssertEqual(consistency.currentPlannedCount, 2)
    }

    func testConsistencyPresentationResolvesGoalStateForTheWidget() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        func day(_ dayOfMonth: Int, hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: dayOfMonth, hour: hour))!
        }
        let now = day(19, hour: 12) // Wednesday; the week runs Mon 8/17 – Sun 8/23
        let days = (0..<7).map { offset in
            WidgetConsistencyDaySnapshot(
                date: day(17 + offset),
                hasPost: [true, false, true, false, false, false, false][offset]
            )
        }
        var snapshot = AgentCyWidgetSnapshot.empty
        snapshot.consistency = WidgetConsistencySnapshot(
            completedWeeks: [true, true],
            streak: 2,
            currentPostedCount: 2,
            currentPlannedCount: 2,
            days: days,
            postedDayCount: 2,
            goal: 2
        )

        let mode = WidgetConsistencyPresentation.mode(
            for: snapshot,
            isPreview: false,
            calendar: calendar,
            now: now
        )

        guard case let .goal(markers, postedDayCount, goal, goalMet, streak) = mode else {
            return XCTFail("Expected the goal mode, got \(mode)")
        }
        XCTAssertEqual(markers.map(\.symbol), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(markers.map(\.hasPost), [true, false, true, false, false, false, false])
        XCTAssertEqual(markers.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(postedDayCount, 2)
        XCTAssertEqual(goal, 2)
        XCTAssertTrue(goalMet)
        XCTAssertEqual(streak, 2)
    }

    func testConsistencyPresentationFallsBackForUnsetGoalLegacyAndPreviewData() {
        // Goal fields present but no goal chosen → the set-a-goal prompt.
        var unset = AgentCyWidgetSnapshot.empty
        unset.consistency = WidgetConsistencySnapshot(
            completedWeeks: [],
            streak: 0,
            currentPostedCount: 1,
            currentPlannedCount: 0,
            days: [],
            postedDayCount: 1,
            goal: nil
        )
        XCTAssertEqual(WidgetConsistencyPresentation.mode(for: unset, isPreview: false), .unset)

        // A snapshot written before the goal fields renders the legacy tile.
        var legacy = AgentCyWidgetSnapshot.empty
        let legacyConsistency = WidgetConsistencySnapshot(
            completedWeeks: [true],
            streak: 1,
            currentPostedCount: 2,
            currentPlannedCount: 3
        )
        legacy.consistency = legacyConsistency
        XCTAssertEqual(
            WidgetConsistencyPresentation.mode(for: legacy, isPreview: false),
            .legacy(legacyConsistency)
        )

        // No data at all: production tells the truth; previews substitute demo data.
        XCTAssertEqual(WidgetConsistencyPresentation.mode(for: .empty, isPreview: false), .unset)
        XCTAssertEqual(
            WidgetConsistencyPresentation.mode(for: .empty, isPreview: true),
            WidgetConsistencyPresentation.mode(for: .preview, isPreview: false)
        )
    }

    private func canonicalData(_ snapshot: AgentCyWidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(snapshot)
    }
}
