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

    /// Fix round 1 (L1-08 follow-up): `AgentDesktopQuietActionButtonStyle`
    /// (the desktop Pillar detail rail's Cancel / Save / Edit buttons) had
    /// hard-coded `AgentRadius.control` instead of reading the shared token,
    /// so it rendered at 8pt while every other standalone button read 10pt.
    /// It now reads `AgentActionButtonTheme.radius`; this asserts it stays
    /// wired to the shared token instead of drifting back to a literal.
    func testDesktopQuietActionButtonStyleUsesButtonRadius() {
        XCTAssertEqual(AgentDesktopQuietActionButtonStyle.radius, AgentRadius.button)
        XCTAssertEqual(AgentDesktopQuietActionButtonStyle.radius, AgentActionButtonTheme.radius)
    }
}
