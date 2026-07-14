import XCTest
@testable import AgentCy

final class ClaudeHandoffPromptBuilderTests: XCTestCase {
    func testPromptIncludesCreatorContextHistoryAndCurrentRequest() {
        let prompt = ClaudeHandoffPromptBuilder.makePrompt(
            creatorName: "Chey",
            primaryGoal: "Teach creators to make useful content.",
            history: [
                ClaudeHandoffTurn(speaker: .creator, text: "I want a simple video."),
                ClaudeHandoffTurn(speaker: .cy, text: "Start with one clear promise."),
            ],
            request: "Give me three hooks."
        )

        XCTAssertTrue(prompt.contains("CREATOR\nChey"))
        XCTAssertTrue(prompt.contains("PRIMARY GOAL\nTeach creators to make useful content."))
        XCTAssertTrue(prompt.contains("Creator: I want a simple video."))
        XCTAssertTrue(prompt.contains("Cy: Start with one clear promise."))
        XCTAssertTrue(prompt.contains("CURRENT REQUEST\nGive me three hooks."))
    }

    func testPromptKeepsOnlyTheMostRecentBoundedHistory() {
        let history = (0..<20).map {
            ClaudeHandoffTurn(speaker: .creator, text: "Turn \($0)")
        }

        let prompt = ClaudeHandoffPromptBuilder.makePrompt(
            creatorName: "",
            primaryGoal: "",
            history: history,
            request: "Continue."
        )

        XCTAssertFalse(prompt.contains("Creator: Turn 7\n"))
        XCTAssertTrue(prompt.contains("Creator: Turn 8"))
        XCTAssertTrue(prompt.contains("Creator: Turn 19"))
    }

    func testPromptTrimsEmptyContextAndBoundsLongRequest() {
        let prompt = ClaudeHandoffPromptBuilder.makePrompt(
            creatorName: "   ",
            primaryGoal: "\n",
            history: [ClaudeHandoffTurn(speaker: .claude, text: "  ")],
            request: String(repeating: "a", count: ClaudeHandoffPromptBuilder.maximumRequestLength + 20)
        )

        XCTAssertFalse(prompt.contains("CREATOR\n"))
        XCTAssertFalse(prompt.contains("PRIMARY GOAL\n"))
        XCTAssertFalse(prompt.contains("RECENT CONVERSATION\n"))
        XCTAssertTrue(prompt.hasSuffix("…"))
    }
}
