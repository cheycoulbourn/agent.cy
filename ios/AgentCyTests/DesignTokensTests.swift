import XCTest
@testable import AgentCy

final class DesignTokensTests: XCTestCase {
    /// L1-08: the contract's Radius table says `AgentRadius.button = 10` for
    /// every standalone button; the shared action-button theme must read
    /// that token (not `AgentRadius.control`) so all button call sites agree
    /// with the design contract.
    func testActionButtonThemeUsesButtonRadius() {
        XCTAssertEqual(AgentActionButtonTheme.radius, AgentRadius.button)
    }
}
