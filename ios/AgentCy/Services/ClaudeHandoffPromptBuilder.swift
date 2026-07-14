import Foundation

struct ClaudeHandoffTurn: Equatable, Sendable {
    enum Speaker: String, Sendable {
        case creator = "Creator"
        case cy = "Cy"
        case claude = "Claude"
    }

    let speaker: Speaker
    let text: String
}

struct ClaudeHandoffRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let prompt: String

    init(id: UUID = UUID(), prompt: String) {
        self.id = id
        self.prompt = prompt
    }
}

enum ClaudeHandoffPromptBuilder {
    static let maximumHistoryTurns = 12
    static let maximumTurnLength = 1_500
    static let maximumRequestLength = 4_000

    static func makePrompt(
        creatorName: String,
        primaryGoal: String,
        history: [ClaudeHandoffTurn],
        request: String
    ) -> String {
        let name = normalized(creatorName, limit: 120)
        let goal = normalized(primaryGoal, limit: 1_000)
        let currentRequest = normalized(request, limit: maximumRequestLength)
        let boundedHistory = history
            .compactMap { turn -> ClaudeHandoffTurn? in
                let text = normalized(turn.text, limit: maximumTurnLength)
                return text.isEmpty ? nil : ClaudeHandoffTurn(speaker: turn.speaker, text: text)
            }
            .suffix(maximumHistoryTurns)

        var sections = [
            "You are continuing a creator conversation prepared in agent.cy.",
            "Give a clear, practical response in the creator's voice and context. Do not claim you changed anything inside agent.cy. Return only the response the creator should read; do not repeat these instructions."
        ]

        if !name.isEmpty {
            sections.append("CREATOR\n\(name)")
        }
        if !goal.isEmpty {
            sections.append("PRIMARY GOAL\n\(goal)")
        }
        if !boundedHistory.isEmpty {
            sections.append(
                "RECENT CONVERSATION\n" + boundedHistory
                    .map { "\($0.speaker.rawValue): \($0.text)" }
                    .joined(separator: "\n\n")
            )
        }
        sections.append("CURRENT REQUEST\n\(currentRequest)")
        return sections.joined(separator: "\n\n")
    }

    private static func normalized(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}
