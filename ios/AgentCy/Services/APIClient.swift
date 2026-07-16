import Foundation
import Security

struct InstallationIdentity: Codable, Equatable, Sendable {
    let installationID: UUID
    let credential: String
    let access: SubscriptionAccess
    let credentialExpiresAt: Date?
    let promotionalEntitlementEndsAt: Date?
}

protocol InstallationCredentialStoring: Sendable {
    func load() async throws -> InstallationIdentity?
    func save(_ identity: InstallationIdentity) async throws
    func delete() async throws
}

enum CredentialStoreError: LocalizedError {
    case encoding
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encoding: "The installation credential could not be encoded."
        case .keychain(let status): "The device Keychain operation failed (\(status))."
        }
    }
}

actor DeviceOnlyKeychainCredentialStore: InstallationCredentialStoring {
    static let shared = DeviceOnlyKeychainCredentialStore()
    private let service = "com.agentcy.app.installation"
    private let account = "primary"

    func load() throws -> InstallationIdentity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialStoreError.keychain(status) }
        return try JSONDecoder.agentCy.decode(InstallationIdentity.self, from: data)
    }

    func save(_ identity: InstallationIdentity) throws {
        let data = try JSONEncoder.agentCy.encode(identity)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

actor PreviewCredentialStore: InstallationCredentialStoring {
    private var identity: InstallationIdentity?

    init(identity: InstallationIdentity? = nil) {
        self.identity = identity
    }

    func load() -> InstallationIdentity? { identity }
    func save(_ identity: InstallationIdentity) { self.identity = identity }
    func delete() { identity = nil }
}

enum APIConfiguration {
    static var baseURL: URL {
        if let value = ProcessInfo.processInfo.environment["AGENTCY_API_BASE_URL"],
           let url = validatedBaseURL(value, allowInsecureLocalhost: allowsInsecureLocalhost) {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "AGENTCY_API_BASE_URL") as? String,
           let url = validatedBaseURL(value, allowInsecureLocalhost: allowsInsecureLocalhost) {
            return url
        }
#if DEBUG
        return URL(string: "http://127.0.0.1:3000")!
#else
        return URL(string: "https://replace-me.invalid")!
#endif
    }

    static var appBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    static var useLiveAI: Bool {
        if let value = ProcessInfo.processInfo.environment["AGENTCY_USE_LIVE_AI"],
           let parsed = parseBoolean(value) {
            return parsed
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "AGENTCY_USE_LIVE_AI") {
            if let boolean = value as? Bool { return boolean }
            if let parsed = parseBoolean(String(describing: value)) { return parsed }
        }
#if DEBUG
        return false
#else
        return true
#endif
    }

    static func validatedBaseURL(_ value: String, allowInsecureLocalhost: Bool) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$("),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return nil }
        if scheme == "https" { return url }
        guard scheme == "http",
              allowInsecureLocalhost,
              ["localhost", "127.0.0.1", "::1"].contains(host) else { return nil }
        return url
    }

    private static var allowsInsecureLocalhost: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }
}

private struct InstallationRedeemRequest: Encodable {
    let inviteCode: String
    let appBuild: String
    let platform = "ios"
}

private struct InstallationRedeemResponse: Decodable {
    let installationId: UUID
    let credential: String
    let access: SubscriptionAccess
    let credentialExpiresAt: Date?
    let promotionalEntitlementEndsAt: Date?
}

private struct HTTPErrorEnvelope: Decodable {
    let error: AIWireError
}

actor InstallationRedemptionClient {
    private let baseURL: URL
    private let session: URLSession
    private let store: any InstallationCredentialStoring

    init(baseURL: URL = APIConfiguration.baseURL, session: URLSession = .shared, store: any InstallationCredentialStoring = DeviceOnlyKeychainCredentialStore.shared) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
    }

    func redeem(inviteCode: String) async throws -> InstallationIdentity {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count >= 6 else { throw AgentCyAPIError.invalidRequest("Enter the complete invitation code.") }
        guard code.count <= 128 else { throw AgentCyAPIError.invalidRequest("The invitation code is too long.") }
        var request = URLRequest(url: baseURL.appending(path: "/v1/installations/redeem"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.agentCy.encode(InstallationRedeemRequest(inviteCode: code, appBuild: APIConfiguration.appBuild))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder.agentCy.decode(HTTPErrorEnvelope.self, from: data) {
                throw AgentCyAPIError.server(envelope.error)
            }
            throw AgentCyAPIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let result = try JSONDecoder.agentCy.decode(InstallationRedeemResponse.self, from: data)
        let identity = InstallationIdentity(
            installationID: result.installationId,
            credential: result.credential,
            access: result.access,
            credentialExpiresAt: result.credentialExpiresAt,
            promotionalEntitlementEndsAt: result.promotionalEntitlementEndsAt
        )
        try await store.save(identity)
        return identity
    }
}

enum AIOperation: String, Codable, CaseIterable, Sendable {
    case voiceProfile
    case ideas
    case sparkTurn
    case composeBrief
    case reviseBrief
    case chatTurn
    case rhythmProposal
    case tasksProposal

    var path: String {
        switch self {
        case .voiceProfile: "/v1/ai/voice-profile"
        case .ideas: "/v1/ai/ideas"
        case .sparkTurn: "/v1/ai/spark/turn"
        case .composeBrief: "/v1/ai/brief/compose"
        case .reviseBrief: "/v1/ai/brief/revise"
        case .chatTurn: "/v1/ai/chat/turn"
        case .rhythmProposal: "/v1/ai/rhythm/propose"
        case .tasksProposal: "/v1/ai/tasks/propose"
        }
    }

    var resultSchemaVersion: String {
        switch self {
        case .voiceProfile: "voice-profile.result.v1"
        case .ideas: "ideas.result.v1"
        case .sparkTurn: "spark-turn.result.v1"
        case .composeBrief: "compose-brief.result.v1"
        case .reviseBrief: "revise-brief.result.v1"
        case .chatTurn: "chat-turn.result.v1"
        case .rhythmProposal: "rhythm-proposal.result.v1"
        case .tasksProposal: "tasks-proposal.result.v1"
        }
    }
}

enum AIProgressPhase: String, Codable, Sendable {
    case accepted
    case generating
    case validating
}

protocol AIRequestIdentifying: Encodable, Sendable {
    var operationId: UUID { get }
}

enum AIErrorCodeWire: String, Decodable, Sendable, Equatable {
    case invalidInput = "invalid_input"
    case payloadTooLarge = "payload_too_large"
    case installationInvalid = "installation_invalid"
    case entitlementRequired = "entitlement_required"
    case quotaExceeded = "quota_exceeded"
    case rateLimited = "rate_limited"
    case upstreamUnavailable = "upstream_unavailable"
    case generationInvalid = "generation_invalid"
    case refusal
    case maxTokens = "max_tokens"
    case timeout
    case usageLimit = "usage_limit"
    case cancelled
    case conflict
}

enum AIQuotaScopeWire: String, Decodable, Sendable, Equatable {
    case freeAllowance
    case installationShortWindow
    case installationDaily
    case globalDailySpend
    case providerRateLimit
    case providerCredits
}

enum AIFieldPathComponentWire: Decodable, Sendable, Equatable {
    case key(String)
    case index(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let index = try? container.decode(Int.self) {
            self = .index(index)
        } else {
            self = .key(try container.decode(String.self))
        }
    }
}

struct AIFieldIssueWire: Decodable, Sendable {
    let path: [AIFieldPathComponentWire]
    let message: String
}

struct AIWireError: Decodable, LocalizedError, Sendable {
    let code: AIErrorCodeWire
    let message: String
    let retryable: Bool
    let retryAfterSeconds: Int?
    let quotaScope: AIQuotaScopeWire?
    let fieldIssues: [AIFieldIssueWire]?

    var errorDescription: String? { message }

    var requiresSubscriptionUpgrade: Bool {
        code == .entitlementRequired || quotaScope == .freeAllowance
    }
}

enum AgentCyAPIError: LocalizedError {
    case invalidRequest(String)
    case missingCredential
    case payloadTooLarge
    case http(Int)
    case invalidStream(String)
    case server(AIWireError)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): message
        case .missingCredential: "A valid installation invitation is required before live Cy requests can run."
        case .payloadTooLarge: "This request is larger than the 128 KB privacy boundary. Remove unrelated context and try again."
        case .http(let status): "The agent.cy service returned HTTP \(status)."
        case .invalidStream(let message): "The Cy response stream was invalid: \(message)"
        case .server(let error): error.message
        }
    }
}

struct SSEBlock: Equatable, Sendable {
    let event: String
    let data: Data
}

struct SSELineDecoder: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []

    mutating func consume(_ line: String) -> SSEBlock? {
        if line.isEmpty { return flush() }
        if line.hasPrefix("event:") {
            let pending = dataLines.isEmpty ? nil : flush()
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return pending
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    mutating func finish() -> SSEBlock? { flush() }

    private mutating func flush() -> SSEBlock? {
        defer { eventName = nil; dataLines.removeAll(keepingCapacity: true) }
        guard let eventName, !dataLines.isEmpty else { return nil }
        return SSEBlock(event: eventName, data: Data(dataLines.joined(separator: "\n").utf8))
    }
}

enum SSESequenceDecoder {
    private struct Meta: Decodable {
        let operationId: UUID
        let requestId: UUID
        let operation: AIOperation
        let schemaVersion: String
        let model: String
        let startedAt: Date
    }
    private struct Phase: Decodable { let operationId: UUID; let phase: AIProgressPhase }
    private struct ResultEnvelope<Result: Decodable>: Decodable {
        let operationId: UUID
        let payload: Payload
        struct Payload: Decodable { let operation: AIOperation; let result: Result }
    }
    private struct ErrorEnvelope: Decodable { let operationId: UUID; let error: AIWireError }
    private struct Done: Decodable { let operationId: UUID; let status: String; let completedAt: Date }

    static func decode<Result: Decodable>(_ type: Result.Type, blocks: [SSEBlock], expectedOperation: AIOperation, expectedOperationID: UUID) throws -> Result {
        guard blocks.count >= 4 else { throw AgentCyAPIError.invalidStream("the stream was shorter than the canonical sequence") }
        guard blocks.first?.event == "meta" else { throw AgentCyAPIError.invalidStream("meta must be first") }
        guard blocks.last?.event == "done" else { throw AgentCyAPIError.invalidStream("done must be last") }
        guard blocks.filter({ $0.event == "meta" }).count == 1,
              blocks.filter({ $0.event == "done" }).count == 1 else {
            throw AgentCyAPIError.invalidStream("meta and done must occur exactly once")
        }
        let terminalIndexes = blocks.indices.filter { blocks[$0].event == "result" || blocks[$0].event == "error" }
        guard terminalIndexes == [blocks.count - 2] else {
            throw AgentCyAPIError.invalidStream("result or error must immediately precede done")
        }
        var sawPhase = false
        var terminalCount = 0
        var result: Result?
        var serverError: AIWireError?
        var doneStatus: String?
        for block in blocks {
            switch block.event {
            case "meta":
                let meta = try JSONDecoder.agentCy.decode(Meta.self, from: block.data)
                guard meta.operationId == expectedOperationID,
                      meta.operation == expectedOperation,
                      meta.model == "claude-sonnet-5",
                      meta.schemaVersion == expectedOperation.resultSchemaVersion else {
                    throw AgentCyAPIError.invalidStream("meta did not match the request contract")
                }
            case "phase":
                let phase = try JSONDecoder.agentCy.decode(Phase.self, from: block.data)
                guard phase.operationId == expectedOperationID else { throw AgentCyAPIError.invalidStream("operation ID changed") }
                sawPhase = true
            case "result":
                terminalCount += 1
                let envelope = try JSONDecoder.agentCy.decode(ResultEnvelope<Result>.self, from: block.data)
                guard envelope.operationId == expectedOperationID, envelope.payload.operation == expectedOperation else {
                    throw AgentCyAPIError.invalidStream("result operation did not match")
                }
                result = envelope.payload.result
            case "error":
                terminalCount += 1
                let envelope = try JSONDecoder.agentCy.decode(ErrorEnvelope.self, from: block.data)
                guard envelope.operationId == expectedOperationID else { throw AgentCyAPIError.invalidStream("error operation ID changed") }
                serverError = envelope.error
            case "done":
                let done = try JSONDecoder.agentCy.decode(Done.self, from: block.data)
                guard done.operationId == expectedOperationID else { throw AgentCyAPIError.invalidStream("done operation ID changed") }
                doneStatus = done.status
            default:
                throw AgentCyAPIError.invalidStream("unknown event \(block.event)")
            }
        }
        guard sawPhase, terminalCount == 1, let doneStatus else { throw AgentCyAPIError.invalidStream("missing phase or terminal result") }
        if let serverError {
            guard doneStatus == "failed" || doneStatus == "cancelled" else { throw AgentCyAPIError.invalidStream("error stream ended with an invalid status") }
            throw AgentCyAPIError.server(serverError)
        }
        guard doneStatus == "succeeded", let result else { throw AgentCyAPIError.invalidStream("successful result did not finish successfully") }
        return result
    }
}

actor AgentCyAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let store: any InstallationCredentialStoring

    init(baseURL: URL = APIConfiguration.baseURL, session: URLSession = .shared, store: any InstallationCredentialStoring = DeviceOnlyKeychainCredentialStore.shared) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
    }

    func perform<Request: AIRequestIdentifying, Result: Decodable & Sendable>(
        operation: AIOperation,
        request body: Request,
        result: Result.Type,
        onPhase: (@Sendable (AIProgressPhase) async -> Void)? = nil
    ) async throws -> Result {
        if LocalCyPreferences.isEnabledAndConnected {
            return try await LocalCyAIClient.shared.perform(
                operation: operation,
                request: body,
                result: result,
                onPhase: onPhase
            )
        }
        guard let identity = try await store.load() else { throw AgentCyAPIError.missingCredential }
        if let expiry = identity.credentialExpiresAt, expiry <= Date() { throw AgentCyAPIError.missingCredential }
        let data = try JSONEncoder.agentCy.encode(body)
        guard data.count <= 128 * 1_024 else { throw AgentCyAPIError.payloadTooLarge }
        var request = URLRequest(url: baseURL.appending(path: operation.path))
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(identity.credential)", forHTTPHeaderField: "Authorization")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            if let envelope = try? JSONDecoder.agentCy.decode(HTTPErrorEnvelope.self, from: errorData) {
                throw AgentCyAPIError.server(envelope.error)
            }
            throw AgentCyAPIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        var decoder = SSELineDecoder()
        var blocks: [SSEBlock] = []
        for try await line in bytes.lines {
            if let block = decoder.consume(line) {
                blocks.append(block)
                if block.event == "phase",
                   let phase = try? JSONDecoder.agentCy.decode(PhaseProbe.self, from: block.data).phase {
                    await onPhase?(phase)
                }
            }
        }
        if let block = decoder.finish() { blocks.append(block) }
        return try SSESequenceDecoder.decode(Result.self, blocks: blocks, expectedOperation: operation, expectedOperationID: body.operationId)
    }

    private struct PhaseProbe: Decodable { let phase: AIProgressPhase }
}

extension JSONEncoder {
    static var agentCy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var agentCy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
