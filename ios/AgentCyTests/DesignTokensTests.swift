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

    /// L1-04: six screens hand-rolled a solid pure-white
    /// `.buttonStyle(.borderedProminent)` circle for Save instead of the
    /// shared glass control. `AgentToolbarSaveButton` is built on the same
    /// `AgentToolbarIconMetrics` geometry as every other toolbar icon
    /// control, not a new size of its own; this pins that so the Save
    /// control can never quietly drift back to a bespoke diameter or glyph
    /// size the way the six call sites did.
    func testSaveButtonUsesToolbarIconMetrics() {
        XCTAssertEqual(AgentToolbarSaveButton.diameter, AgentToolbarIconMetrics.diameter)
        XCTAssertEqual(AgentToolbarSaveButton.glyph, AgentToolbarIconMetrics.glyph)
    }

    /// L1-05 / G-5: nine buttons shipped the brick accent as a solid fill.
    /// design.md's "No solid accent fills, anywhere" (2026-08-14) allows the
    /// accent only as tint, mark, glyph, or text, and its light CyCallout
    /// action spells the sanctioned values out: `cy @ 12%` ground, a 0.75-pt
    /// `cy @ 40%` border, brick semibold label. These pin those numbers so the
    /// one accent action can never quietly grow back into a filled button.
    func testQuietAccentThemeValues() {
        XCTAssertEqual(AgentQuietAccentTheme.fillOpacity, 0.12, accuracy: 0.0001)
        XCTAssertEqual(AgentQuietAccentTheme.borderOpacity, 0.40, accuracy: 0.0001)
        XCTAssertEqual(AgentQuietAccentTheme.borderWidth, 0.75)
    }

    /// The accent action is a member of the shared action-button family, not a
    /// shape of its own: same 10-pt corner as every other standalone button.
    func testQuietAccentUsesSharedButtonRadius() {
        XCTAssertEqual(AgentQuietAccentTheme.radius, AgentActionButtonTheme.radius)
        XCTAssertEqual(AgentQuietAccentTheme.radius, AgentRadius.button)
    }

    /// Both label sizes match an existing family footprint (the ink primary's
    /// 52 pt, the CyCallout action's 44 pt) so an accent action never
    /// introduces a third button height on a screen, and neither falls below
    /// the 44-pt tap floor the toolbar controls are held to.
    func testQuietAccentButtonSizesMatchTheButtonFamily() {
        XCTAssertEqual(AgentQuietAccentButtonSize.page.minimumHeight, 52)
        XCTAssertEqual(
            AgentQuietAccentButtonSize.compact.minimumHeight,
            AgentQuietAccentTheme.minimumHeight
        )
        XCTAssertGreaterThanOrEqual(
            AgentQuietAccentButtonSize.compact.minimumHeight,
            AgentToolbarIconMetrics.diameter
        )
    }

    /// The circular sibling (Cy's composer send, Cy's inline "add this")
    /// inherits the toolbar control diameter rather than picking its own, the
    /// mistake L1-01..L1-03 caught in the close controls.
    func testQuietAccentIconLabelDefaultsToToolbarDiameter() {
        XCTAssertEqual(
            AgentQuietAccentIconLabel(icon: .arrowUp).diameter,
            AgentToolbarIconMetrics.diameter
        )
    }
}
