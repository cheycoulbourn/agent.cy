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
            .ideaBank,
            .quickIdea,
            .quickPost,
            .quickTask,
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
    }

    func testSnapshotContainsFocusNextPostIdeaAndProductionWork() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let weekday = try XCTUnwrap(PillarWeekday(rawValue: Calendar.current.component(.weekday, from: now)))

        let profile = CreatorProfile(name: "Chey")
        let pillar = Pillar(name: "Lifestyle", colorHex: "5E8069")
        let brief = CreativeBrief(title: "The small shift", premise: "A premise", status: .ready)
        brief.pillarID = pillar.id
        brief.updatedAt = now
        let idea = CreativeBrief(title: "A fresh angle", premise: "A thought", status: .spark)
        idea.pillarID = pillar.id
        idea.updatedAt = now.addingTimeInterval(10)
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
        XCTAssertEqual(snapshot.productionTasks.first?.title, "Film the opening")
        XCTAssertEqual(snapshot.productionTasks.map(\.lane), [.production, .pillar])
        XCTAssertEqual(snapshot.week.count, 7)
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

    private func canonicalData(_ snapshot: AgentCyWidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(snapshot)
    }
}
