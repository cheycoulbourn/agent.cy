import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PrivacyEraseTests: XCTestCase {
    func testLegacyServerDeletionCheckpointRemainsResumable() {
        let suiteName = "PrivacyEraseTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let installationID = UUID()
        let installationKey = "test.erase.installation"
        let phaseKey = "test.erase.phase"
        defaults.set(installationID.uuidString, forKey: installationKey)

        let store = UserDefaultsPrivacyEraseProgressStore(
            defaults: defaults,
            key: installationKey,
            phaseKey: phaseKey
        )

        XCTAssertEqual(
            store.checkpoint,
            PrivacyEraseCheckpoint(installationID: installationID, phase: .serverDeleted)
        )
    }

    func testLocalDeletionPhasePersistsUntilCredentialCleanupCompletes() {
        let suiteName = "PrivacyEraseTests.phase.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let installationID = UUID()
        let installationKey = "test.erase.installation"
        let phaseKey = "test.erase.phase"
        let store = UserDefaultsPrivacyEraseProgressStore(
            defaults: defaults,
            key: installationKey,
            phaseKey: phaseKey
        )

        store.markLocalDataDeleted(installationID: installationID)

        XCTAssertEqual(
            store.checkpoint,
            PrivacyEraseCheckpoint(installationID: installationID, phase: .localDataDeleted)
        )
        store.clear()
        XCTAssertNil(store.checkpoint)
    }

    func testNewCheckpointWritesOneAtomicPayload() {
        let suiteName = "PrivacyEraseTests.atomic.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let installationID = UUID()
        let installationKey = "test.erase.installation"
        let phaseKey = "test.erase.phase"
        let checkpointKey = "test.erase.checkpoint"
        let store = UserDefaultsPrivacyEraseProgressStore(
            defaults: defaults,
            key: installationKey,
            phaseKey: phaseKey,
            checkpointKey: checkpointKey
        )

        store.markLocalDataDeleted(installationID: installationID)

        XCTAssertNotNil(defaults.data(forKey: checkpointKey))
        XCTAssertNil(defaults.object(forKey: installationKey))
        XCTAssertNil(defaults.object(forKey: phaseKey))
        XCTAssertEqual(
            store.checkpoint,
            PrivacyEraseCheckpoint(installationID: installationID, phase: .localDataDeleted)
        )
    }

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
        let profile = CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        let brief = CreativeBrief(title: "Pending", premise: "A premise", status: .developing)
        context.insert(brief)
        context.insert(PendingBriefProposal(briefID: brief.id, payloadJSON: "{}"))
        let destination = PublishingDestination(name: "Newsletter")
        context.insert(destination)
        context.insert(CreatorSocialAccount(
            profileID: profile.id,
            destinationID: destination.id,
            label: "Ari Writes",
            profileURLString: "https://example.com/ari"
        ))
        context.insert(CreatorAttachment(ownerKind: .referenceFile, briefID: brief.id, fileName: "notes.txt", kind: .document, uniformTypeIdentifier: "public.plain-text", byteCount: 5, localRelativePath: "", cloudData: Data("notes".utf8), syncState: .synced))
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

        let completed = await model.eraseAll(context: context)

        let events = await recorder.snapshot()
        let remainingIdentity = await credentialStore.currentIdentity()
        XCTAssertEqual(events, ["credential.load", "privacy.delete", "credential.delete"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PublishingDestination>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorSocialAccount>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorAttachment>()).isEmpty)
        XCTAssertNil(remainingIdentity)
        XCTAssertTrue(completed)
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

        let completed = await model.eraseAll(context: context)

        let events = await recorder.snapshot()
        let remainingIdentity = await credentialStore.currentIdentity()
        XCTAssertEqual(events, ["credential.load", "privacy.delete"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertEqual(remainingIdentity, identity)
        XCTAssertFalse(completed)
        guard case .error = model.notice else { return XCTFail("Expected a retryable privacy error") }
    }

    func testLocalEraseFailureKeepsCredentialAndResumesWithoutDeletingServerTwice() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "s", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: identity, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        let localEraser = FailOnceLocalDataEraser(recorder: recorder)
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyDeletionService: OrderedPrivacyService(recorder: recorder),
            privacyEraseProgressStore: progressStore,
            localDataEraser: localEraser,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        let firstCompleted = await model.eraseAll(context: context)

        let firstEvents = await recorder.snapshot()
        let identityAfterFailure = await credentialStore.currentIdentity()
        XCTAssertEqual(firstEvents, ["credential.load", "privacy.delete", "local.erase"])
        XCTAssertEqual(identityAfterFailure, identity)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertEqual(progressStore.checkpoint?.installationID, identity.installationID)
        XCTAssertEqual(progressStore.checkpoint?.phase, .serverDeleted)
        XCTAssertFalse(firstCompleted)

        let resumedCompleted = await model.eraseAll(context: context)

        let resumedEvents = await recorder.snapshot()
        let identityAfterResume = await credentialStore.currentIdentity()
        XCTAssertEqual(
            resumedEvents,
            ["credential.load", "privacy.delete", "local.erase", "credential.load", "local.erase", "credential.delete"]
        )
        XCTAssertNil(identityAfterResume)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertNil(progressStore.checkpoint)
        XCTAssertTrue(resumedCompleted)
    }

    func testReplacementInstallationDiscardsStaleCheckpointWithoutErasingCurrentData() async throws {
        let recorder = EraseOrderRecorder()
        let replacementIdentity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "n", count: 48),
            access: .paid,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: replacementIdentity, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        progressStore.markServerDeleted(installationID: UUID())
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "New creator", goal: "Keep this data"))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyDeletionService: OrderedPrivacyService(recorder: recorder),
            privacyEraseProgressStore: progressStore,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        await model.refreshInstallationCredentialStatus(context: context)

        let remainingIdentity = await credentialStore.currentIdentity()
        XCTAssertEqual(remainingIdentity, replacementIdentity)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertNil(progressStore.checkpoint)
        XCTAssertTrue(model.hasInstallationCredential)

        let erasedReplacement = await model.eraseAll(context: context)
        let identityAfterErase = await credentialStore.currentIdentity()
        XCTAssertTrue(erasedReplacement)
        XCTAssertNil(identityAfterErase)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
    }

    func testCheckpointWithoutCredentialDoesNotEraseLocalData() async throws {
        let recorder = EraseOrderRecorder()
        let credentialStore = OrderedCredentialStore(identity: nil, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        progressStore.markServerDeleted(installationID: UUID())
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Keep me", goal: "Restore access first"))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyEraseProgressStore: progressStore,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        await model.refreshInstallationCredentialStatus(context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertNotNil(progressStore.checkpoint)
        guard case .error = model.notice else {
            return XCTFail("Expected missing credential to pause checkpoint recovery")
        }
    }

    func testStartupLocalEraseFailureKeepsKnownCredentialState() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "k", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: identity, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        progressStore.markServerDeleted(installationID: identity.installationID)
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Keep on failure", goal: "Retry"))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyEraseProgressStore: progressStore,
            localDataEraser: FailOnceLocalDataEraser(recorder: recorder),
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        await model.refreshInstallationCredentialStatus(context: context)

        XCTAssertTrue(model.hasInstallationCredential)
        XCTAssertTrue(model.isInstallationCredentialStatusResolved)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertEqual(progressStore.checkpoint?.phase, .serverDeleted)
    }

    func testCalendarCleanupFailureKeepsCredentialAndResumesAfterCleanupSucceeds() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "c", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: identity, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        let calendar = FailOnceDisconnectCalendarSyncService()
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Erase me", goal: "Cleanly"))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            calendarSyncService: calendar,
            credentialStore: credentialStore,
            privacyDeletionService: OrderedPrivacyService(recorder: recorder),
            privacyEraseProgressStore: progressStore,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        let firstCompleted = await model.eraseAll(context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertEqual(progressStore.checkpoint?.phase, .localDataDeleted)
        let identityAfterCleanupFailure = await credentialStore.currentIdentity()
        XCTAssertFalse(firstCompleted)
        XCTAssertEqual(identityAfterCleanupFailure, identity)

        let resumedCompleted = await model.eraseAll(context: context)
        let identityAfterResume = await credentialStore.currentIdentity()
        XCTAssertTrue(resumedCompleted)
        XCTAssertNil(identityAfterResume)
        XCTAssertNil(progressStore.checkpoint)
    }

    func testExportCleanupFailureKeepsCredentialAndResumesAfterCleanupSucceeds() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "x", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = OrderedCredentialStore(identity: identity, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        let archiveCleaner = FailOnceExportArchiveCleaner()
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Erase me", goal: "Clean exports"))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            calendarSyncService: FailOnceDisconnectCalendarSyncService(shouldFail: false),
            credentialStore: credentialStore,
            privacyDeletionService: OrderedPrivacyService(recorder: recorder),
            privacyEraseProgressStore: progressStore,
            exportArchiveCleaner: archiveCleaner,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        let firstCompleted = await model.eraseAll(context: context)
        let identityAfterCleanupFailure = await credentialStore.currentIdentity()
        XCTAssertFalse(firstCompleted)
        XCTAssertEqual(identityAfterCleanupFailure, identity)
        XCTAssertEqual(progressStore.checkpoint?.phase, .localDataDeleted)

        let resumedCompleted = await model.eraseAll(context: context)
        let identityAfterResume = await credentialStore.currentIdentity()
        XCTAssertTrue(resumedCompleted)
        XCTAssertNil(identityAfterResume)
        XCTAssertNil(progressStore.checkpoint)
    }

    func testCredentialFailureResumesWithoutErasingContentCreatedAfterLocalDeletion() async throws {
        let recorder = EraseOrderRecorder()
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "f", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let credentialStore = FailOnceDeleteCredentialStore(identity: identity, recorder: recorder)
        let progressStore = InMemoryEraseProgressStore()
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Old creator", goal: "Erase me"))
        try context.save()
        let model = AppModel(
            reminderService: PreviewReminderService(),
            credentialStore: credentialStore,
            privacyDeletionService: OrderedPrivacyService(recorder: recorder),
            privacyEraseProgressStore: progressStore,
            requiresInstallationInvite: true,
            allowsOfflinePrivacyErase: false
        )

        _ = await model.eraseAll(context: context)
        XCTAssertEqual(progressStore.checkpoint?.phase, .localDataDeleted)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)

        context.insert(CreatorProfile(name: "New creator", goal: "Keep me"))
        try context.save()
        await model.refreshInstallationCredentialStatus(context: context)

        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        let remainingIdentity = await credentialStore.currentIdentity()
        XCTAssertEqual(profiles.map(\.name), ["New creator"])
        XCTAssertNil(remainingIdentity)
        XCTAssertNil(progressStore.checkpoint)
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

private actor FailOnceDeleteCredentialStore: InstallationCredentialStoring {
    private var identity: InstallationIdentity?
    private var shouldFailDelete = true
    private let recorder: EraseOrderRecorder

    init(identity: InstallationIdentity?, recorder: EraseOrderRecorder) {
        self.identity = identity
        self.recorder = recorder
    }

    func load() async -> InstallationIdentity? {
        await recorder.append("credential.load")
        return identity
    }

    func save(_ identity: InstallationIdentity) {
        self.identity = identity
    }

    func delete() async throws {
        await recorder.append("credential.delete")
        if shouldFailDelete {
            shouldFailDelete = false
            throw CocoaError(.fileWriteUnknown)
        }
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

@MainActor
private final class InMemoryEraseProgressStore: PrivacyEraseProgressStoring {
    var checkpoint: PrivacyEraseCheckpoint?

    func markServerDeleted(installationID: UUID) {
        checkpoint = PrivacyEraseCheckpoint(installationID: installationID, phase: .serverDeleted)
    }

    func markLocalDataDeleted(installationID: UUID) {
        checkpoint = PrivacyEraseCheckpoint(installationID: installationID, phase: .localDataDeleted)
    }

    func clear() {
        checkpoint = nil
    }
}

@MainActor
private final class FailOnceLocalDataEraser: LocalCreatorDataErasing {
    private let recorder: EraseOrderRecorder
    private var shouldFail = true

    init(recorder: EraseOrderRecorder) {
        self.recorder = recorder
    }

    func eraseAll(context: ModelContext) async throws {
        await recorder.append("local.erase")
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
        try await SwiftDataLocalCreatorDataEraser().eraseAll(context: context)
    }
}

@MainActor
private final class FailOnceDisconnectCalendarSyncService: CalendarSyncServicing {
    private var shouldFail: Bool

    init(shouldFail: Bool = true) {
        self.shouldFail = shouldFail
    }

    var authorization: AgentCalendarAuthorization { .fullAccess }
    func requestFullAccess() async throws -> Bool { true }
    func availableCalendars() -> [AgentCalendarChoice] { [] }
    func reconcile(context: ModelContext) throws {}

    func disconnect() throws {
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

@MainActor
private final class FailOnceExportArchiveCleaner: ExportArchiveCleaning {
    private var shouldFail = true

    func removeArchives(currentExportURL: URL?) throws {
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
