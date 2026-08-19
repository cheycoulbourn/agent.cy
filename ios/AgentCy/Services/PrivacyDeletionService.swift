import Foundation
import SwiftData
import WidgetKit

struct PrivacyDeleteRequest: Codable, Equatable, Sendable {
    let requestId: UUID
    let installationId: String
    let appBuild: String
    let scope: String
    let confirmation: String

    init(
        requestId: UUID = UUID(),
        installationId: UUID,
        appBuild: String = APIConfiguration.appBuild
    ) {
        self.requestId = requestId
        self.installationId = installationId.uuidString.lowercased()
        self.appBuild = appBuild
        self.scope = "serverMetadata"
        self.confirmation = "ERASE"
    }
}

enum PrivacyRetainedCategory: String, Codable, Sendable {
    case inviteRedemptionTombstone
    case freeBriefConsumption
    case entitlementHistory
}

enum PrivacyRetentionReason: String, Codable, Sendable {
    case fraudPrevention
    case entitlementIntegrity
}

struct PrivacyRetainedRecord: Codable, Equatable, Sendable {
    let category: PrivacyRetainedCategory
    let reason: PrivacyRetentionReason
}

struct PrivacyDeleteResult: Codable, Equatable, Sendable {
    let requestId: UUID
    let deletedAt: String
    let retained: [PrivacyRetainedRecord]
}

protocol PrivacyDeletionServicing: Sendable {
    func deleteServerMetadata(for identity: InstallationIdentity) async throws -> PrivacyDeleteResult
}

enum PrivacyErasePhase: String, Codable, Sendable {
    case serverDeleted
    case localDataDeleted
}

struct PrivacyEraseCheckpoint: Codable, Equatable, Sendable {
    let installationID: UUID
    let phase: PrivacyErasePhase
}

@MainActor
protocol PrivacyEraseProgressStoring: AnyObject {
    var checkpoint: PrivacyEraseCheckpoint? { get }
    func markServerDeleted(installationID: UUID)
    func markLocalDataDeleted(installationID: UUID)
    func clear()
}

@MainActor
final class UserDefaultsPrivacyEraseProgressStore: PrivacyEraseProgressStoring {
    private let defaults: UserDefaults
    private let legacyInstallationIDKey: String
    private let legacyPhaseKey: String
    private let checkpointKey: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "agentcy.privacyErase.serverDeletedInstallationID",
        phaseKey: String = "agentcy.privacyErase.phase",
        checkpointKey: String = "agentcy.privacyErase.checkpoint.v2"
    ) {
        self.defaults = defaults
        self.legacyInstallationIDKey = key
        self.legacyPhaseKey = phaseKey
        self.checkpointKey = checkpointKey
    }

    var checkpoint: PrivacyEraseCheckpoint? {
        if let data = defaults.data(forKey: checkpointKey),
           let checkpoint = try? JSONDecoder().decode(PrivacyEraseCheckpoint.self, from: data) {
            return checkpoint
        }
        guard let installationID = defaults.string(forKey: legacyInstallationIDKey).flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        let phase = defaults.string(forKey: legacyPhaseKey)
            .flatMap(PrivacyErasePhase.init(rawValue:)) ?? .serverDeleted
        let checkpoint = PrivacyEraseCheckpoint(installationID: installationID, phase: phase)
        persist(checkpoint)
        return checkpoint
    }

    func markServerDeleted(installationID: UUID) {
        mark(installationID: installationID, phase: .serverDeleted)
    }

    func markLocalDataDeleted(installationID: UUID) {
        mark(installationID: installationID, phase: .localDataDeleted)
    }

    func clear() {
        defaults.removeObject(forKey: checkpointKey)
        defaults.removeObject(forKey: legacyInstallationIDKey)
        defaults.removeObject(forKey: legacyPhaseKey)
    }

    private func mark(installationID: UUID, phase: PrivacyErasePhase) {
        persist(PrivacyEraseCheckpoint(installationID: installationID, phase: phase))
    }

    private func persist(_ checkpoint: PrivacyEraseCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: checkpointKey)
        defaults.removeObject(forKey: legacyInstallationIDKey)
        defaults.removeObject(forKey: legacyPhaseKey)
    }
}

@MainActor
protocol LocalCreatorDataErasing {
    func eraseAll(context: ModelContext) async throws
}

@MainActor
struct SwiftDataLocalCreatorDataEraser: LocalCreatorDataErasing {
    private let inspirationQueueStore: InspirationImportQueueStore?
    private let inspirationWorkspaceDefaults: UserDefaults?

    init(
        inspirationQueueStore: InspirationImportQueueStore? = nil,
        inspirationWorkspaceDefaults: UserDefaults? = UserDefaults(
            suiteName: InspirationSharedContainer.appGroupIdentifier
        )
    ) {
        self.inspirationQueueStore = inspirationQueueStore ?? (try? InspirationImportQueueStore())
        self.inspirationWorkspaceDefaults = inspirationWorkspaceDefaults
    }

    func eraseAll(context: ModelContext) async throws {
        // Derived from the schema so a newly added model type can never be
        // missed by this hand-off; PrivacyEraseTests asserts the store is
        // empty for every schema type afterwards.
        for type in AgentCySchema.types {
            try deleteAll(type, context: context)
        }
        try context.save()
        try inspirationQueueStore?.removeAll()
        try? InspirationShareCreatorSnapshotStore.delete()
        InspirationWorkspaceHintStore.save(nil, defaults: inspirationWorkspaceDefaults)
        CreatorWorkspacePreferences.activeWorkspaceID = nil
#if !targetEnvironment(macCatalyst)
        try VoiceSparkRecordingStore.clearAll()
#endif
        AgentCyWidgetSnapshotStore.delete()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func deleteAll(_ type: any PersistentModel.Type, context: ModelContext) throws {
        func wipe<T: PersistentModel>(_ concrete: T.Type) throws {
            try context.fetch(FetchDescriptor<T>()).forEach(context.delete)
        }
        try wipe(type)
    }
}

enum PrivacyDeletionError: LocalizedError {
    case invalidResponse
    case requestMismatch
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The privacy service returned an invalid response."
        case .requestMismatch:
            "The privacy service did not confirm this erase request."
        case .http(let status, let message):
            message ?? "The privacy service returned HTTP \(status)."
        }
    }
}

actor PrivacyDeletionClient: PrivacyDeletionServicing {
    private let baseURL: URL
    private let session: URLSession
    private let appBuild: String

    init(
        baseURL: URL = APIConfiguration.baseURL,
        session: URLSession = .shared,
        appBuild: String = APIConfiguration.appBuild
    ) {
        self.baseURL = baseURL
        self.session = session
        self.appBuild = appBuild
    }

    func deleteServerMetadata(for identity: InstallationIdentity) async throws -> PrivacyDeleteResult {
        let body = PrivacyDeleteRequest(installationId: identity.installationID, appBuild: appBuild)
        var request = URLRequest(url: baseURL.appending(path: "/v1/privacy/delete"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(identity.credential)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PrivacyDeletionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PrivacyErrorEnvelope.self, from: data))?.error.message
            throw PrivacyDeletionError.http(http.statusCode, message)
        }
        let result = try JSONDecoder().decode(PrivacyDeleteResult.self, from: data)
        guard result.requestId == body.requestId else {
            throw PrivacyDeletionError.requestMismatch
        }
        return result
    }
}

private struct PrivacyErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String
    }

    let error: Payload
}
