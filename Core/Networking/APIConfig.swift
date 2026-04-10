import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "https://agentcy-production.up.railway.app")!
    #else
    static let baseURL = URL(string: "https://agentcy-production.up.railway.app")!
    #endif

    static let aiExpandIdea = baseURL.appendingPathComponent("/api/ai/expand-idea")
    static let aiGenerateCaption = baseURL.appendingPathComponent("/api/ai/generate-caption")
    static let aiChat = baseURL.appendingPathComponent("/api/ai/chat")
    static let aiAdaptCaption = baseURL.appendingPathComponent("/api/ai/adapt-caption")
    static let aiAnalyzeInspiration = baseURL.appendingPathComponent("/api/ai/analyze-inspiration")
}
