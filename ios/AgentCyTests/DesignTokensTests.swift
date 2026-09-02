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

    /// L1-01/L1-02/L1-03: the app used to carry four close-control geometries
    /// (44 pt glass, 48 pt glass, 40 pt opaque, 44 pt opaque). There is now one
    /// glass circle and these are the numbers it renders at; `measure-close-
    /// controls.py` checks the same two values against real screenshots.
    func testToolbarIconControlGeometry() {
        XCTAssertEqual(AgentToolbarIconMetrics.diameter, 44)
        XCTAssertEqual(AgentToolbarIconMetrics.glyph, 17)
    }

    /// The control is also the app's tap-target floor: nothing that leaves or
    /// acts on a screen may be smaller than 44 pt, which is what the 40 pt and
    /// 48 pt copies got wrong in both directions.
    func testToolbarIconControlMeetsTapTargetFloor() {
        XCTAssertGreaterThanOrEqual(AgentToolbarIconMetrics.diameter, 44)
        XCTAssertLessThan(AgentToolbarIconMetrics.glyph, AgentToolbarIconMetrics.diameter)
    }

    /// The hairline is the other half of "identical interior fill": the two
    /// deleted glass copies drew it at 0.16 rather than 0.22.
    func testToolbarIconControlStroke() {
        XCTAssertEqual(AgentToolbarIconMetrics.strokeOpacity, 0.22, accuracy: 0.0001)
        XCTAssertEqual(AgentToolbarIconMetrics.strokeWidth, 0.5)
    }
}
