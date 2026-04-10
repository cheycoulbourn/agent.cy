import Foundation

actor APIClient {
    static let shared = APIClient()

    private let session = URLSession.shared
    private let apiKey = "QZmVf43PT2M60PKDrXEAVqbqBrymZbPG324oExX0ME8"

    // MARK: - AI Endpoints

    func expandIdea(_ idea: String, context: CreatorContext) async throws -> String {
        let body: [String: Any] = [
            "idea": idea,
            "context": contextDict(context)
        ]
        return try await post(to: APIConfig.aiExpandIdea, body: body)
    }

    func generateCaption(
        topic: String,
        platform: String,
        format: String,
        pillar: String?,
        context: CreatorContext
    ) async throws -> String {
        let body: [String: Any] = [
            "topic": topic,
            "platform": platform,
            "format": format,
            "pillar": pillar ?? "",
            "context": contextDict(context)
        ]
        return try await post(to: APIConfig.aiGenerateCaption, body: body)
    }

    func chat(messages: [[String: String]], context: CreatorContext) async throws -> String {
        let body: [String: Any] = [
            "messages": messages,
            "context": contextDict(context)
        ]
        return try await post(to: APIConfig.aiChat, body: body)
    }

    func adaptCaption(_ caption: String, to platform: String, context: CreatorContext) async throws -> String {
        let body: [String: Any] = [
            "caption": caption,
            "targetPlatform": platform,
            "context": contextDict(context)
        ]
        return try await post(to: APIConfig.aiAdaptCaption, body: body)
    }

    func analyzeInspiration(text: String?, sourceURL: String?) async throws -> String {
        var body: [String: Any] = [:]
        if let text { body["text"] = text }
        if let sourceURL { body["sourceURL"] = sourceURL }
        return try await post(to: APIConfig.aiAnalyzeInspiration, body: body)
    }

    // MARK: - Networking

    private func post(to url: URL, body: [String: Any]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        guard let result = String(data: data, encoding: .utf8) else {
            throw APIError.decodingFailed
        }

        return result
    }

    private func contextDict(_ context: CreatorContext) -> [String: Any] {
        [
            "displayName": context.displayName,
            "niche": context.niche,
            "voiceAdjectives": context.voiceAdjectives,
            "voiceDescription": context.voiceDescription ?? "",
            "pillarNames": context.pillarNames,
            "recentContentTitles": context.recentContentTitles,
            "platforms": context.platforms.map(\.rawValue),
            "goals": context.goals
        ]
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .httpError(let code): "Server error (\(code))"
        case .decodingFailed: "Failed to read response"
        }
    }
}
