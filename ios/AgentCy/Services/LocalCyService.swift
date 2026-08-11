import Foundation

enum LocalCyPreferences {
    static let enabledKey = "agentcy.localCy.enabled"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return MCPBridgePreferences.isConnected
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isEnabledAndConnected: Bool {
        shouldAttemptLocal(
            isEnabled: isEnabled,
            hasBridgeCredential: MCPBridgePreferences.isConnected
        )
    }

    static func shouldAttemptLocal(
        isEnabled: Bool,
        hasBridgeCredential: Bool
    ) -> Bool {
        isEnabled && hasBridgeCredential
    }
}

enum LocalCyError: LocalizedError, Equatable {
    case notConnected
    case runtimeUnavailable
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Connect the Claude & Codex folder before turning on Local Cy."
        case .runtimeUnavailable:
            "Local Cy is not running on your Mac. Open the agent.cy bridge and make sure Claude Code is signed in."
        case .timedOut:
            "Local Cy took too long to respond. Your work is saved. Check that your Mac is awake and connected."
        case .invalidResponse:
            "Local Cy returned a response the app could not safely use."
        }
    }
}

struct LocalCyRuntimeStatus: Codable, Equatable {
    let schemaVersion: Int
    let status: String
    let updatedAt: Date
    let model: String
    let message: String

    var isRecentlyAvailable: Bool {
        ["ready", "working"].contains(status) && Date().timeIntervalSince(updatedAt) < 10 * 60
    }
}

struct LocalCyConnectionConfig: Codable, Equatable {
    let schemaVersion: Int
    let baseURL: URL
    let token: String
    let updatedAt: Date
}

private enum LocalCyDirectTransportError: Error {
    case unavailable
}

private struct LocalCyRequestEnvelope<Request: Encodable>: Encodable {
    let schemaVersion = 1
    let id: UUID
    let operation: AIOperation
    let createdAt: Date
    let workspaceId: UUID?
    let payload: Request
}

private struct LocalCyResponseEnvelope<Result: Decodable>: Decodable {
    let schemaVersion: Int
    let id: UUID
    let operation: AIOperation
    let completedAt: Date
    let status: String
    let model: String?
    let result: Result?
    let error: AIWireError?
}

actor LocalCyAIClient {
    static let shared = LocalCyAIClient()

    func isAvailable() async -> Bool {
        guard LocalCyPreferences.isEnabledAndConnected else { return false }
        if let connection = try? connectionConfig(),
           await isDirectlyReachable(connection) {
            return true
        }
        return (try? runtimeStatus()?.isRecentlyAvailable) == true
    }

    func perform<Request: AIRequestIdentifying, Result: Decodable & Sendable>(
        operation: AIOperation,
        request body: Request,
        result: Result.Type,
        onPhase: (@Sendable (AIProgressPhase) async -> Void)? = nil
    ) async throws -> Result {
        guard LocalCyPreferences.isEnabledAndConnected else { throw LocalCyError.notConnected }
        let requestID = body.operationId
        let envelope = LocalCyRequestEnvelope(
            id: requestID,
            operation: operation,
            createdAt: Date(),
            workspaceId: CreatorWorkspacePreferences.activeWorkspaceID,
            payload: body
        )

        if let connection = try connectionConfig(), await isDirectlyReachable(connection) {
            do {
                return try await performDirect(
                    envelope,
                    requestID: requestID,
                    operation: operation,
                    result: result,
                    connection: connection,
                    onPhase: onPhase
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AgentCyAPIError {
                throw error
            } catch {
                // The direct Mac connection may disappear when the network
                // changes. The iCloud queue remains a slower safe fallback.
            }
        }

        guard try runtimeStatus()?.isRecentlyAvailable == true else { throw LocalCyError.runtimeUnavailable }
        return try await performQueued(
            envelope,
            requestID: requestID,
            operation: operation,
            result: result,
            onPhase: onPhase
        )
    }

    func isRemoteAvailable() async -> Bool {
        await isAvailable()
    }

    private func performQueued<Request: Encodable, Result: Decodable & Sendable>(
        _ envelope: Request,
        requestID: UUID,
        operation: AIOperation,
        result: Result.Type,
        onPhase: (@Sendable (AIProgressPhase) async -> Void)?
    ) async throws -> Result {
        // Operation IDs may be retried. Remove both halves of an older
        // exchange first so a stale failure cannot be mistaken for the new
        // request, then clean up regardless of how this attempt finishes.
        try? removeExchangeFiles(requestID: requestID)
        defer { try? removeExchangeFiles(requestID: requestID) }
        try write(envelope, requestID: requestID)
        await onPhase?(.accepted)
        await onPhase?(.generating)

        // A local bridge is an optimization, not a reason to strand Cy. If a
        // configured Mac stops answering, hand the same request to hosted Cy
        // quickly enough that the creator can keep working on the phone.
        let deadline = Date().addingTimeInterval(10)
        do {
            while Date() < deadline {
                try Task.checkCancellation()
                if let response: LocalCyResponseEnvelope<Result> = try readResponse(
                    requestID: requestID,
                    operation: operation
                ) {
                    let result = try validatedResult(
                        response,
                        requestID: requestID,
                        operation: operation
                    )
                    await onPhase?(.validating)
                    return result
                }
                try await Task.sleep(for: .milliseconds(650))
            }
        } catch {
            throw error
        }
        throw LocalCyError.timedOut
    }

    private func performDirect<Request: Encodable, Result: Decodable & Sendable>(
        _ envelope: Request,
        requestID: UUID,
        operation: AIOperation,
        result: Result.Type,
        connection: LocalCyConnectionConfig,
        onPhase: (@Sendable (AIProgressPhase) async -> Void)?
    ) async throws -> Result {
        var request = URLRequest(url: connection.baseURL.appending(path: "v1/local-cy"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(envelope)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        await onPhase?(.accepted)
        await onPhase?(.generating)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw LocalCyDirectTransportError.unavailable
        }
        let responseEnvelope = try decoder.decode(LocalCyResponseEnvelope<Result>.self, from: data)
        defer { try? removeExchangeFiles(requestID: requestID) }
        let value = try validatedResult(responseEnvelope, requestID: requestID, operation: operation)
        await onPhase?(.validating)
        return value
    }

    private func validatedResult<Result: Decodable>(
        _ response: LocalCyResponseEnvelope<Result>,
        requestID: UUID,
        operation: AIOperation
    ) throws -> Result {
        guard response.schemaVersion == 1,
              response.id == requestID,
              response.operation == operation else {
            throw LocalCyError.invalidResponse
        }
        if let error = response.error { throw AgentCyAPIError.server(error) }
        guard response.status == "succeeded", let result = response.result else {
            throw LocalCyError.invalidResponse
        }
        return result
    }

    private func isDirectlyReachable(_ connection: LocalCyConnectionConfig) async -> Bool {
        var request = URLRequest(url: connection.baseURL.appending(path: "healthz"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func runtimeStatus() throws -> LocalCyRuntimeStatus? {
        guard MCPBridgePreferences.isConnected else { return nil }
        return try MCPBridgePreferences.withDirectory { directory in
            let url = directory.appending(path: "cy-runtime.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try decoder.decode(LocalCyRuntimeStatus.self, from: Data(contentsOf: url))
        }
    }

    private func connectionConfig() throws -> LocalCyConnectionConfig? {
        guard MCPBridgePreferences.isConnected else { return nil }
        return try MCPBridgePreferences.withDirectory { directory in
            let url = directory.appending(path: "cy-connection.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let config = try decoder.decode(LocalCyConnectionConfig.self, from: Data(contentsOf: url))
            guard config.schemaVersion == 1, config.token.count >= 32 else {
                throw LocalCyError.invalidResponse
            }
            return config
        }
    }

    private func write<Request: Encodable>(_ envelope: Request, requestID: UUID) throws {
        try MCPBridgePreferences.withDirectory { directory in
            let requests = directory.appending(path: "cy-requests", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
            let url = requests.appending(path: "\(requestID.uuidString.lowercased()).json")
            try encoder.encode(envelope).write(
                to: url,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
        }
    }

    private func readResponse<Result: Decodable>(
        requestID: UUID,
        operation: AIOperation
    ) throws -> LocalCyResponseEnvelope<Result>? {
        try MCPBridgePreferences.withDirectory { directory in
            let url = directory
                .appending(path: "cy-responses", directoryHint: .isDirectory)
                .appending(path: "\(requestID.uuidString.lowercased()).json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do {
                let response = try decoder.decode(LocalCyResponseEnvelope<Result>.self, from: Data(contentsOf: url))
                guard response.operation == operation else { throw LocalCyError.invalidResponse }
                return response
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
        }
    }

    private func removeExchangeFiles(requestID: UUID) throws {
        try MCPBridgePreferences.withDirectory { directory in
            for folder in ["cy-requests", "cy-responses"] {
                let url = directory
                    .appending(path: folder, directoryHint: .isDirectory)
                    .appending(path: "\(requestID.uuidString.lowercased()).json")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func removeRequest(requestID: UUID) throws {
        try MCPBridgePreferences.withDirectory { directory in
            let url = directory
                .appending(path: "cy-requests", directoryHint: .isDirectory)
                .appending(path: "\(requestID.uuidString.lowercased()).json")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
