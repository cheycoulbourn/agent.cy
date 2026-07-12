import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PrivacyEraseTests: XCTestCase {
    func testEraseDeletesServerMetadataBeforeCredentialAndCleansLocalArtifacts() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "e", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: identity, recorder: recorder)
        let privacyService = OrderedPrivacyService(recorder: recorder)
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true))
        let brief = CreativeBrief(title: "Pending", premise: "A premise", status: .developing)
        context.insert(brief)
        context.insert(PendingBriefProposal(briefID: brief.id, payloadJSON: "{}"))
        context.insert(SubscriptionState(access: .comped))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyDeletionService: privacyService,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )
        model.export(context: context)
        let exportURL = try XCTUnwrap(model.exportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        await model.eraseAll(context: context)

        let events = await recorder.snapshot()
        let remainingIdentity = await credentialStore.currentIdentity()
        XCTAssertEqual(events, ["credential.load", "privacy.delete", "credential.delete"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
        XCTAssertNil(remainingIdentity)
    }

    func testLivePrivacyFailurePreservesDataAndCredentialForRetry() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "r", count: 48),
            access: .paid,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: identity, recorder: recorder)
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyDeletionService: FailingPrivacyService(recorder: recorder),
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        await model.eraseAll(context: context)

        let events = await recorder.snapshot()
        let remainingIdentity = await credentialStore.currentIdentity()
        XCTAssertEqual(events, ["credential.load", "privacy.delete"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertEqual(remainingIdentity, identity)
        guard case .error = model.notice else { return XCTFail("Expected a retryable privacy error") }
    }
}

private actor EraseOrderRecorder {
    private var events: [String] = []

    func append(_ event: String) { events.append(event) }
    func snapshot() -> [String] { events }
}

private actor OrderedCredentialStore: InstallationCredentialStoring {
    private var identity: InstallationIdentity?
    private let recorder: EraseOrderRecorder

    init(identity: InstallationIdentity?, recorder: EraseOrderRecorder) {
        self.identity = identity
        self.recorder = recorder
    }

    func load() async throws -> InstallationIdentity? {
        await recorder.append("credential.load")
        return identity
    }

    func save(_ identity: InstallationIdentity) async throws {
        self.identity = identity
    }

    func delete() async throws {
        await recorder.append("credential.delete")
        identity = nil
    }

    func currentIdentity() -> InstallationIdentity? { identity }
}

private actor OrderedPrivacyService: PrivacyDeletionServicing {
    private let recorder: EraseOrderRecorder

    init(recorder: EraseOrderRecorder) {
        self.recorder = recorder
    }

    func deleteServerMetadata(for identity: InstallationIdentity) async throws -> PrivacyDeleteResult {
        await recorder.append("privacy.delete")
        return PrivacyDeleteResult(
            requestId: UUID(),
            deletedAt: "2026-07-11T12:00:00.000Z",
            retained: [
                PrivacyRetainedRecord(category: .inviteRedemptionTombstone, reason: .fraudPrevention),
                PrivacyRetainedRecord(category: .freeBriefConsumption, reason: .entitlementIntegrity),
                PrivacyRetainedRecord(category: .entitlementHistory, reason: .entitlementIntegrity)
            ]
        )
    }
}

private actor FailingPrivacyService: PrivacyDeletionServicing {
    private let recorder: EraseOrderRecorder

    init(recorder: EraseOrderRecorder) {
        self.recorder = recorder
    }

    func deleteServerMetadata(for identity: InstallationIdentity) async throws -> PrivacyDeleteResult {
        await recorder.append("privacy.delete")
        throw URLError(.notConnectedToInternet)
    }
}
