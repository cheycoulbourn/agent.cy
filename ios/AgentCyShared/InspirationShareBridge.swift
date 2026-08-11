import Foundation
import Security

struct InspirationSharedCredential: Codable, Equatable, Sendable {
    let installationID: UUID
    let credential: String
    let credentialExpiresAt: Date?
}

enum InspirationSharedCredentialStore {
    private static let service = "com.agentcy.shared.installation"
    private static let account = "primary"
    private static let accessGroup = "2S27MSM8G8.com.agentcy.shared"

    static func load() throws -> InspirationSharedCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw InspirationShareBridgeError.keychain(status)
        }
        return try decoder.decode(InspirationSharedCredential.self, from: data)
    }

    static func save(_ credential: InspirationSharedCredential) throws {
        let data = try encoder.encode(credential)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw InspirationShareBridgeError.keychain(status)
        }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw InspirationShareBridgeError.keychain(status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct InspirationShareCreatorSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let updatedAt: Date
    let assistanceMode: String
    let creatorContextJSON: Data
    /// The creator context intentionally stays API-compatible and does not
    /// include presentation data. The share extension still needs the exact
    /// locally selected pillar colors to match the containing app.
    let pillarColorHexByID: [String: String]?

    init(
        schemaVersion: Int = currentSchemaVersion,
        updatedAt: Date = Date(),
        assistanceMode: String,
        creatorContextJSON: Data,
        pillarColorHexByID: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.assistanceMode = assistanceMode
        self.creatorContextJSON = creatorContextJSON
        self.pillarColorHexByID = pillarColorHexByID
    }
}

enum InspirationShareCreatorSnapshotStore {
    private static let directoryName = "InspirationContext"
    private static let filename = "current.json"
    private static let maximumSnapshotBytes = 128 * 1_024

    static func load(fileManager: FileManager = .default) throws -> InspirationShareCreatorSnapshot? {
        let url = try snapshotURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumSnapshotBytes else {
            throw InspirationShareBridgeError.invalidSnapshot
        }
        let snapshot = try decoder.decode(InspirationShareCreatorSnapshot.self, from: data)
        guard snapshot.schemaVersion == InspirationShareCreatorSnapshot.currentSchemaVersion,
              snapshot.creatorContextJSON.count <= maximumSnapshotBytes,
              !snapshot.assistanceMode.isEmpty else {
            throw InspirationShareBridgeError.invalidSnapshot
        }
        return snapshot
    }

    static func save(
        _ snapshot: InspirationShareCreatorSnapshot,
        fileManager: FileManager = .default
    ) throws {
        guard snapshot.schemaVersion == InspirationShareCreatorSnapshot.currentSchemaVersion,
              snapshot.creatorContextJSON.count <= maximumSnapshotBytes else {
            throw InspirationShareBridgeError.invalidSnapshot
        }
        let url = try snapshotURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
        let data = try encoder.encode(snapshot)
        guard data.count <= maximumSnapshotBytes else {
            throw InspirationShareBridgeError.invalidSnapshot
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func delete(fileManager: FileManager = .default) throws {
        let url = try snapshotURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private static func snapshotURL(fileManager: FileManager) throws -> URL {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: InspirationSharedContainer.appGroupIdentifier
        ) else {
            throw InspirationShareBridgeError.unavailableSharedContainer
        }
        return container
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum InspirationShareBridgeError: Error, LocalizedError {
    case keychain(OSStatus)
    case unavailableSharedContainer
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .keychain:
            "Open agent.cy once, then try sharing the post again."
        case .unavailableSharedContainer:
            "agent.cy could not access its private share workspace."
        case .invalidSnapshot:
            "Open agent.cy once to refresh your creator context, then try again."
        }
    }
}
