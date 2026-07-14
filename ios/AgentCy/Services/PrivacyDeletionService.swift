import Foundation

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
