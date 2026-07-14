import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class CaptureIdeaShortcutTests: XCTestCase {
    func testShortcutSavesAnIdeaToTheSelectedPillar() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(name: "Lifestyle", colorHex: "55705B")
        context.insert(SubscriptionState(access: .paid))
        context.insert(pillar)
        try context.save()

        let store = CaptureIdeaShortcutStore(modelContainer: container)
        let outcome = try await store.save(
            idea: "  film a quiet morning routine with three honest moments  ",
            pillarID: pillar.id
        )

        XCTAssertEqual(outcome, .saved(title: "Film a quiet morning routine with three"))
        let brief = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        XCTAssertEqual(brief.premise, "film a quiet morning routine with three honest moments")
        XCTAssertEqual(brief.pillarID, pillar.id)
        XCTAssertEqual(brief.status, .spark)
        XCTAssertEqual(brief.source, .text)
    }

    func testShortcutOffersUnfiledAndOnlyActivePillars() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let active = Pillar(name: "Teaching")
        let archived = Pillar(name: "Old")
        archived.isArchived = true
        context.insert(active)
        context.insert(archived)
        try context.save()

        let store = CaptureIdeaShortcutStore(modelContainer: container)
        let entities = try await store.activePillarEntities()

        XCTAssertEqual(entities.map(\.name), ["No pillar", "Teaching"])
    }

    func testShortcutRespectsExpiredCreationAccess() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .expired))
        try context.save()

        let store = CaptureIdeaShortcutStore(modelContainer: container)
        let outcome = try await store.save(idea: "A fresh idea", pillarID: nil)

        XCTAssertEqual(outcome, .creationUnavailable)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
    }
}
