import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import AgentCy

@MainActor
final class WorkspaceQueryScopeTests: XCTestCase {
    func testSQLitePredicatesMatchExistingOwnershipRulesForEveryModel() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerFactory.makeLocal(at: directory.appending(path: "scope.sqlite"))
        let context = container.mainContext
        let first = CreatorWorkspace(profileID: UUID(), name: "First", sortOrder: 0)
        let second = CreatorWorkspace(profileID: first.profileID, name: "Second", sortOrder: 1)
        let archived = CreatorWorkspace(profileID: first.profileID, name: "Archived", sortOrder: -1)
        archived.isArchived = true
        for workspace in [first, second, archived] { context.insert(workspace) }
        for owner in [nil, first.id, second.id, archived.id, UUID()] {
            let brief = CreativeBrief(title: "Draft")
            brief.workspaceID = owner
            context.insert(brief)
            let output = PlatformOutput(briefID: brief.id, platform: .instagramReels)
            output.workspaceID = owner
            context.insert(output)
            let task = CreatorTask(briefID: brief.id, title: "Task")
            task.workspaceID = owner
            context.insert(task)
            let pillar = Pillar(name: "Pillar")
            pillar.workspaceID = owner
            context.insert(pillar)
            let series = ContentSeries(workspaceID: owner, name: "Series")
            context.insert(series)
            context.insert(SeriesEpisodeSlot(workspaceID: owner, seriesID: series.id, plannedDate: Date()))
            let template = DailyFocusTemplateEntry(weekday: .monday, kind: .custom, title: "Focus")
            template.workspaceID = owner
            context.insert(template)
            let override = DailyFocusOverride(date: Date(), title: "Override")
            override.workspaceID = owner
            context.insert(override)
            context.insert(BrandPartner(workspaceID: owner, name: "Brand"))
            let thread = ConversationThread(title: "Conversation")
            thread.workspaceID = owner
            context.insert(thread)
            context.insert(InspirationSource(workspaceID: owner, canonicalURLString: "https://example.com/post", platform: .web))
        }
        try context.save()

        func verify(preferred: UUID?, workspaces: [CreatorWorkspace]) throws {
            let scope = WorkspaceQueryScope(preferredID: preferred, workspaces: workspaces)
            try assertEquivalent(scope.briefs, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.outputs, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.tasks, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.pillars, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.series, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.episodeSlots, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.focusTemplates, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.focusOverrides, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.brandPartners, context: context, preferred: preferred, workspaces: workspaces)
            try assertEquivalent(scope.threads, context: context, preferred: preferred, workspaces: workspaces)
            let sources = try context.fetch(FetchDescriptor<InspirationSource>())
            let expected = sources.filter {
                SavedPostsScopePolicy.includes(recordWorkspaceID: $0.workspaceID, activeWorkspaceID: scope.workspaceID)
            }
            let actual = try context.fetch(FetchDescriptor(predicate: scope.savedPosts))
            XCTAssertEqual(Set(actual.map(\.id)), Set(expected.map(\.id)))
        }

        for preferred in [nil, first.id, second.id, archived.id, UUID()] {
            try verify(preferred: preferred, workspaces: [first, second, archived])
        }
        try verify(preferred: second.id, workspaces: [])
        first.isArchived = true
        try context.save()
        try verify(preferred: first.id, workspaces: [first, second, archived])
        first.isArchived = false
        second.sortOrder = -2
        try context.save()
        try verify(preferred: nil, workspaces: [first, second, archived])
    }

    func testLargeSQLiteStoreExcludesUnrelatedWorkspacesAndRetainsAllActiveRows() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerFactory.makeLocal(at: directory.appending(path: "large.sqlite"))
        let context = container.mainContext
        let active = CreatorWorkspace(profileID: UUID(), name: "Active")
        context.insert(active)
        let unrelated = UUID()
        for index in 0..<2_000 {
            let brief = CreativeBrief(title: "Draft \(index)")
            brief.workspaceID = index < 40 ? active.id : unrelated
            context.insert(brief)
        }
        try context.save()
        let scope = WorkspaceQueryScope(preferredID: active.id, workspaces: [active])
        let descriptor = FetchDescriptor(predicate: scope.briefs)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CreativeBrief>()), 2_000)
        XCTAssertEqual(try context.fetchCount(descriptor), 40)
        XCTAssertEqual(try context.fetch(descriptor).count, 40)
    }

    func testWorkspaceChangesReconfigureQueryWithoutResettingViewState() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let first = CreatorWorkspace(profileID: UUID(), name: "First")
        let second = CreatorWorkspace(profileID: first.profileID, name: "Second", sortOrder: 1)
        context.insert(first)
        context.insert(second)
        let owned = CreativeBrief(title: "Owned")
        owned.workspaceID = second.id
        let legacy = CreativeBrief(title: "Legacy")
        context.insert(owned)
        context.insert(legacy)
        try context.save()
        let model = AppModel(reminderService: PreviewReminderService())
        model.activeWorkspaceID = first.id
        var last: (UUID, Set<UUID>)?
        var expectedIDs: Set<UUID> = [legacy.id]
        var arrived = expectation(description: "Initial workspace")
        let root = WorkspaceQueryScopeReader { scope in
            WorkspaceQueryProbe(scope: scope) { identity, ids in
                last = (identity, ids)
                if ids == expectedIDs { arrived.fulfill() }
            }
        }.environment(model).modelContainer(container)
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [arrived], timeout: 3)
        let identity = try XCTUnwrap(last?.0)

        arrived = expectation(description: "Switch workspace")
        expectedIDs = [owned.id]
        model.activeWorkspaceID = second.id
        await fulfillment(of: [arrived], timeout: 3)
        XCTAssertEqual(last?.0, identity)

        arrived = expectation(description: "Default workspace changes")
        expectedIDs = [owned.id, legacy.id]
        first.isArchived = true
        try context.save()
        await fulfillment(of: [arrived], timeout: 3)
        XCTAssertEqual(last?.0, identity)
    }

    private func assertEquivalent<T: PersistentModel & WorkspaceScopedRecord>(
        _ predicate: Predicate<T>, context: ModelContext, preferred: UUID?, workspaces: [CreatorWorkspace]
    ) throws {
        let expected = try context.fetch(FetchDescriptor<T>()).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: preferred, workspaces: workspaces)
        }
        let actual = try context.fetch(FetchDescriptor(predicate: predicate))
        XCTAssertEqual(Set(actual.map(\.persistentModelID)), Set(expected.map(\.persistentModelID)), "\(T.self)")
    }
}

private struct WorkspaceQueryProbe: View {
    @Query private var briefs: [CreativeBrief]
    @State private var identity = UUID()
    let observe: (UUID, Set<UUID>) -> Void

    init(scope: WorkspaceQueryScope, observe: @escaping (UUID, Set<UUID>) -> Void) {
        _briefs = Query(filter: scope.briefs)
        self.observe = observe
    }

    var body: some View {
        Text("\(briefs.count)")
            .onChange(of: Set(briefs.map(\.id)), initial: true) { _, ids in
                observe(identity, ids)
            }
    }
}
