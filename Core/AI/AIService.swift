import Foundation

// MARK: - AI Service Protocol

protocol AIServiceProtocol: Sendable {
    func expandIdea(_ idea: IdeaExpansionRequest) async throws -> IdeaExpansion
    func generateCaption(_ request: CaptionRequest) async throws -> CaptionResult
    func adaptCaption(_ caption: String, to platform: SocialPlatform) async throws -> String
    func analyzeInspiration(_ request: InspirationAnalysisRequest) async throws -> InspirationAnalysis
    func chat(_ messages: [ChatMessage], context: CreatorContext) async throws -> ChatMessage
    func suggestContentPlan(for days: Int, context: CreatorContext) async throws -> [ContentSuggestion]
}

// MARK: - Request/Response Types

struct IdeaExpansionRequest: Sendable {
    let rawIdea: String
    let sourceURL: String?
    let context: CreatorContext
}

struct IdeaExpansion: Sendable {
    let title: String
    let suggestedPillar: String?
    let platforms: [SocialPlatform]
    let format: ContentFormat
    let caption: String
    let hooks: [String]
    let hashtags: [String]
}

struct CaptionRequest: Sendable {
    let topic: String
    let platform: SocialPlatform
    let format: ContentFormat
    let pillar: String?
    let context: CreatorContext
}

struct CaptionResult: Sendable {
    let variations: [String]
    let hashtags: [String]
}

struct InspirationAnalysisRequest: Sendable {
    let sourceURL: String?
    let text: String?
    let imageData: Data?
}

struct InspirationAnalysis: Sendable {
    let summary: String
    let themes: [String]
    let contentAngles: [String]
    let suggestedPillar: String?
}

struct ChatMessage: Sendable, Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }
}

enum ChatRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

struct CreatorContext: Sendable {
    let displayName: String
    let niche: String
    let voiceAdjectives: [String]
    let voiceDescription: String?
    let pillarNames: [String]
    let recentContentTitles: [String]
    let platforms: [SocialPlatform]
    let goals: String
}

struct ContentSuggestion: Sendable, Identifiable {
    let id = UUID()
    let title: String
    let pillar: String
    let platform: SocialPlatform
    let format: ContentFormat
    let hook: String
    let suggestedDate: Date
}

// MARK: - Mock AI Service (for development)

final class MockAIService: AIServiceProtocol {
    func expandIdea(_ idea: IdeaExpansionRequest) async throws -> IdeaExpansion {
        try await Task.sleep(for: .seconds(1))
        return IdeaExpansion(
            title: "5 Morning Habits That Changed My Productivity",
            suggestedPillar: "Education",
            platforms: [.instagram, .tiktok],
            format: .carousel,
            caption: "I used to wake up and scroll for 30 minutes. Here's what I do instead...",
            hooks: [
                "Stop doing this every morning",
                "The 5am secret nobody talks about",
                "I tried this for 30 days and everything changed"
            ],
            hashtags: ["#productivity", "#morningroutine", "#habits", "#selfimprovement"]
        )
    }

    func generateCaption(_ request: CaptionRequest) async throws -> CaptionResult {
        try await Task.sleep(for: .seconds(1))
        return CaptionResult(
            variations: [
                "Here's what nobody tells you about \(request.topic)...",
                "I spent 6 months learning about \(request.topic). Here are my takeaways.",
                "The truth about \(request.topic) that changed my perspective."
            ],
            hashtags: ["#content", "#creator", "#tips"]
        )
    }

    func adaptCaption(_ caption: String, to platform: SocialPlatform) async throws -> String {
        try await Task.sleep(for: .milliseconds(500))
        switch platform {
        case .x: return String(caption.prefix(280))
        case .tiktok: return String(caption.prefix(150))
        default: return caption
        }
    }

    func analyzeInspiration(_ request: InspirationAnalysisRequest) async throws -> InspirationAnalysis {
        try await Task.sleep(for: .seconds(1))
        return InspirationAnalysis(
            summary: "Engaging visual content with strong hook and clean aesthetic.",
            themes: ["minimalism", "productivity", "lifestyle"],
            contentAngles: [
                "Create your own version with a personal twist",
                "Do a reaction or response",
                "Break down why this works"
            ],
            suggestedPillar: nil
        )
    }

    func chat(_ messages: [ChatMessage], context: CreatorContext) async throws -> ChatMessage {
        try await Task.sleep(for: .seconds(1))
        return ChatMessage(
            role: .assistant,
            content: "Based on your \(context.niche) focus and your \(context.voiceAdjectives.joined(separator: ", ")) voice, I'd suggest leaning into carousel content this week. Your audience engages most with educational breakdowns."
        )
    }

    func suggestContentPlan(for days: Int, context: CreatorContext) async throws -> [ContentSuggestion] {
        try await Task.sleep(for: .seconds(1))
        return []
    }
}
