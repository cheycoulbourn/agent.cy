import Foundation

struct ShareExtraction: Codable, Equatable, Sendable {
    let canonicalUrl: URL
    let platform: InspirationPlatform
    let mediaKind: String
    let sourceTitle: String?
    let creatorName: String?
    let creatorHandle: String?
    let caption: String?
    let thumbnailUrl: URL?
    let mediaUrls: [URL]
    let durationSeconds: Double?
    let evidence: [String]

    var displaySourceTitle: String? {
        if let creatorName = creatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creatorName.isEmpty {
            return "\(creatorName) on Instagram"
        }
        if let creatorHandle = creatorHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creatorHandle.isEmpty {
            return "@\(creatorHandle) on Instagram"
        }
        return sourceTitle.map { String($0.prefix(160)) }
    }
}

struct ShareInspirationMechanic: Codable, Equatable, Sendable {
    let hookPattern: String
    let structurePattern: String
    let payoffPattern: String
}

struct ShareInspirationIdea: Codable, Equatable, Sendable {
    let title: String
    let premise: String
    let audience: String
    let takeaway: String
    let spokenHook: String
    let firstFrameText: String
    let filmingApproach: String
    let recommendedFormat: String
    let durationSeconds: Int
}

struct ShareInspirationShapeResult: Codable, Equatable, Sendable {
    let sourceSummary: String
    let keyPoints: [String]
    let interpretedMechanic: ShareInspirationMechanic
    let originalityGuardrails: [String]
    let idea: ShareInspirationIdea
    let suggestedPillarId: UUID?
    let assumptions: [String]
}

struct ShareSourceMaterial: Equatable, Sendable {
    let title: String?
    let caption: String?
    let transcript: String?
    let visualObservations: [String]
    let analyzedInputs: [String]
    let durationSeconds: Int?

    var jsonObject: [String: Any] {
        var value: [String: Any] = [
            "visualObservations": visualObservations,
            "analyzedInputs": analyzedInputs,
        ]
        if let title { value["title"] = title }
        if let caption { value["caption"] = caption }
        if let transcript { value["transcript"] = transcript }
        if let durationSeconds { value["durationSeconds"] = durationSeconds }
        return value
    }
}

enum InspirationShareAPIError: Error, LocalizedError {
    case notConnected
    case invalidCreatorContext
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Open agent.cy once to reconnect Cy, then share this post again."
        case .invalidCreatorContext:
            "Open agent.cy once to refresh your pillars and content context, then try again."
        case .invalidResponse:
            "Cy returned an incomplete analysis. Try this post again."
        case .service(let message):
            message
        }
    }
}

actor InspirationShareAPIClient {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = InspirationShareAPIClient.configuredBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func extract(url: URL) async throws -> ShareExtraction {
        let credential = try activeCredential()
        var request = URLRequest(url: baseURL.appending(path: "/v1/inspiration/extract"))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["canonicalUrl": url.absoluteString],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(ShareExtraction.self, from: data)
    }

    func shape(
        platform: InspirationPlatform,
        sourceMaterial: ShareSourceMaterial,
        snapshot: InspirationShareCreatorSnapshot,
        operationID: UUID
    ) async throws -> (result: ShareInspirationShapeResult, json: String) {
        let credential = try activeCredential()
        guard let creatorContext = try JSONSerialization.jsonObject(
            with: snapshot.creatorContextJSON
        ) as? [String: Any] else {
            throw InspirationShareAPIError.invalidCreatorContext
        }
        let requestObject: [String: Any] = [
            "schemaVersion": "inspiration-shape.request.v3",
            "promptVersion": "inspiration-shape.v3",
            "operationId": operationID.uuidString.lowercased(),
            "appBuild": Self.appBuild,
            "assistanceMode": snapshot.assistanceMode,
            "creatorContext": creatorContext,
            "sourcePlatform": platform.rawValue,
            "sourceMaterial": sourceMaterial.jsonObject,
        ]
        let body = try JSONSerialization.data(
            withJSONObject: requestObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard body.count <= 128 * 1_024 else {
            throw InspirationShareAPIError.invalidCreatorContext
        }
        var request = URLRequest(url: baseURL.appending(path: "/v1/ai/inspiration/shape"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InspirationShareAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw serviceError(from: data)
        }
        let resultData = try resultPayload(from: data, operationID: operationID)
        let result = try decoder.decode(ShareInspirationShapeResult.self, from: resultData)
        guard !result.sourceSummary.isEmpty,
              !result.idea.title.isEmpty,
              (1...4).contains(result.keyPoints.count) else {
            throw InspirationShareAPIError.invalidResponse
        }
        let normalizedData = try encoder.encode(result)
        guard let json = String(data: normalizedData, encoding: .utf8) else {
            throw InspirationShareAPIError.invalidResponse
        }
        return (result, json)
    }

    private func activeCredential() throws -> InspirationSharedCredential {
        guard let credential = try InspirationSharedCredentialStore.load(),
              credential.credentialExpiresAt.map({ $0 > Date() }) ?? true else {
            throw InspirationShareAPIError.notConnected
        }
        return credential
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw InspirationShareAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw serviceError(from: data)
        }
    }

    private func serviceError(from data: Data) -> InspirationShareAPIError {
        struct Envelope: Decodable {
            struct ServiceError: Decodable { let message: String }
            let error: ServiceError
        }
        let message = try? decoder.decode(Envelope.self, from: data).error.message
        return .service(message ?? "Cy could not analyze this post right now. Try again.")
    }

    private func resultPayload(from data: Data, operationID: UUID) throws -> Data {
        struct ResultEnvelope: Decodable {
            struct Payload: Decodable {
                let operation: String
                let result: ShareInspirationShapeResult
            }
            let operationId: UUID
            let payload: Payload
        }
        struct ErrorEnvelope: Decodable {
            struct ServiceError: Decodable { let message: String }
            let operationId: UUID
            let error: ServiceError
        }

        let stream = String(decoding: data, as: UTF8.self)
        for block in stream.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: .newlines)
            let event = lines.first(where: { $0.hasPrefix("event:") })?
                .dropFirst(6)
                .trimmingCharacters(in: .whitespaces)
            let payloadText = lines
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            guard !payloadText.isEmpty, let payloadData = payloadText.data(using: .utf8) else {
                continue
            }
            if event == "error",
               let envelope = try? decoder.decode(ErrorEnvelope.self, from: payloadData),
               envelope.operationId == operationID {
                throw InspirationShareAPIError.service(envelope.error.message)
            }
            if event == "result" {
                let envelope = try decoder.decode(ResultEnvelope.self, from: payloadData)
                guard envelope.operationId == operationID,
                      envelope.payload.operation == "shapeInspiration" else {
                    throw InspirationShareAPIError.invalidResponse
                }
                return try encoder.encode(envelope.payload.result)
            }
        }
        throw InspirationShareAPIError.invalidResponse
    }

    private static var configuredBaseURL: URL {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "AGENTCY_API_BASE_URL") as? String,
              let url = URL(string: rawValue),
              url.scheme == "https" else {
            return URL(string: "https://agentcy-production.up.railway.app")!
        }
        return url
    }

    private static var appBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
