import CryptoKit
import Foundation

struct AIOperationReservation: Equatable, Sendable {
    let key: String
    let operationID: UUID
}

/// Keeps a content-free idempotency key long enough for an interrupted request
/// to retrieve the server's cached result. No creator text is written to disk.
actor AIOperationIDRegistry {
    static let shared = AIOperationIDRegistry()

    private struct Entry: Codable {
        let operationID: UUID
        let createdAt: Date
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let reuseInterval: TimeInterval
    private var entries: [String: Entry]

    init(
        defaultsSuiteName: String? = nil,
        storageKey: String = "agentcy.ai.pending-operation-ids.v1",
        reuseInterval: TimeInterval = 10 * 60
    ) {
        let defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        self.storageKey = storageKey
        self.reuseInterval = reuseInterval
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func reserve<Request: Encodable & Sendable>(
        operation: AIOperation,
        fingerprintRequest: Request,
        now: Date = Date()
    ) throws -> AIOperationReservation {
        pruneExpired(now: now)
        let key = try Self.fingerprint(operation: operation, request: fingerprintRequest)
        if let existing = entries[key] {
            return AIOperationReservation(key: key, operationID: existing.operationID)
        }

        let operationID = UUID()
        entries[key] = Entry(operationID: operationID, createdAt: now)
        persist()
        return AIOperationReservation(key: key, operationID: operationID)
    }

    func complete(_ reservation: AIOperationReservation) {
        guard entries[reservation.key]?.operationID == reservation.operationID else { return }
        entries.removeValue(forKey: reservation.key)
        persist()
    }

    func removeAll() {
        entries.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func pruneExpired(now: Date) {
        let active = entries.filter { now.timeIntervalSince($0.value.createdAt) < reuseInterval }
        guard active.count != entries.count else { return }
        entries = active
        persist()
    }

    private func persist() {
        guard !entries.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func fingerprint<Request: Encodable>(operation: AIOperation, request: Request) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data(operation.rawValue.utf8)
        data.append(0)
        data.append(try encoder.encode(request))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
