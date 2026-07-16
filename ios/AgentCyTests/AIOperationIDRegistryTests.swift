import Foundation
import XCTest
@testable import AgentCy

final class AIOperationIDRegistryTests: XCTestCase {
    func testInterruptedLogicalRequestReusesOperationIDAcrossRegistryInstances() async throws {
        let suite = "AIOperationIDRegistryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let storageKey = "pending"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = ideasRequest(operationID: UUID(), goal: "Help creators publish")

        let firstRegistry = AIOperationIDRegistry(defaultsSuiteName: suite, storageKey: storageKey)
        let first = try await firstRegistry.reserve(operation: .ideas, fingerprintRequest: request, now: now)
        let restoredRegistry = AIOperationIDRegistry(defaultsSuiteName: suite, storageKey: storageKey)
        let restored = try await restoredRegistry.reserve(
            operation: .ideas,
            fingerprintRequest: request,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(restored.operationID, first.operationID)
        let stored = try XCTUnwrap(UserDefaults(suiteName: suite)?.data(forKey: storageKey))
        XCTAssertNil(String(decoding: stored, as: UTF8.self).range(of: "Help creators publish"))
    }

    func testCompletedRequestGetsFreshOperationIDNextTime() async throws {
        let suite = "AIOperationIDRegistryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let registry = AIOperationIDRegistry(defaultsSuiteName: suite, storageKey: "pending")
        let request = ideasRequest(operationID: UUID(), goal: "Teach clearly")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try await registry.reserve(operation: .ideas, fingerprintRequest: request, now: now)
        await registry.complete(first)
        let second = try await registry.reserve(operation: .ideas, fingerprintRequest: request, now: now)

        XCTAssertNotEqual(second.operationID, first.operationID)
    }

    func testExpiredInterruptedRequestGetsFreshOperationID() async throws {
        let suite = "AIOperationIDRegistryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let registry = AIOperationIDRegistry(
            defaultsSuiteName: suite,
            storageKey: "pending",
            reuseInterval: 60
        )
        let request = ideasRequest(operationID: UUID(), goal: "Make useful work")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try await registry.reserve(operation: .ideas, fingerprintRequest: request, now: now)
        let second = try await registry.reserve(
            operation: .ideas,
            fingerprintRequest: request,
            now: now.addingTimeInterval(61)
        )

        XCTAssertNotEqual(second.operationID, first.operationID)
    }

    func testRemoveAllClearsPersistedRetryMetadata() async throws {
        let suite = "AIOperationIDRegistryTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let storageKey = "pending"
        let registry = AIOperationIDRegistry(defaultsSuiteName: suite, storageKey: storageKey)
        _ = try await registry.reserve(
            operation: .ideas,
            fingerprintRequest: ideasRequest(operationID: UUID(), goal: "Clean up private data")
        )

        await registry.removeAll()

        XCTAssertNil(UserDefaults(suiteName: suite)?.data(forKey: storageKey))
    }

    private func ideasRequest(operationID: UUID, goal: String) -> IdeasRequestWire {
        IdeasRequestWire(
            schemaVersion: AIContractVersion.schema,
            promptVersion: AIContractVersion.ideasPrompt,
            operationId: operationID,
            appBuild: "0.1 (1)",
            assistanceMode: .collaborate,
            creatorContext: CreatorContextWire(
                name: "Ari",
                primaryGoal: goal,
                selectedPlatforms: [.instagramReels],
                voiceExamples: [],
                voiceProfile: nil,
                pillars: [],
                librarySummaries: [],
                taskSummaries: []
            ),
            count: 3,
            startingPoint: nil,
            constraints: []
        )
    }
}
