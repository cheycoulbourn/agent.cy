import XCTest
import UIKit
@testable import AgentCy

final class AgentOKLCHTests: XCTestCase {
    func testSemanticPaletteKeepsApprovedVisualIdentity() {
        let expected: [(AgentOKLCH, String)] = [
            (AgentColorPalette.canvasLight, "F5F6F3"),
            (AgentColorPalette.canvasDark, "1A1A1A"),
            (AgentColorPalette.surfaceLight, "FDFDFB"),
            (AgentColorPalette.surfaceDark, "141414"),
            (AgentColorPalette.secondaryLight, "514D47"),
            (AgentColorPalette.secondaryDark, "CFCBC3"),
            (AgentColorPalette.borderLight, "D7D8D3"),
            (AgentColorPalette.borderDark, "383838"),
            (AgentColorPalette.hairlineLight, "E6E7E2"),
            (AgentColorPalette.hairlineDark, "2D2D2D"),
            (AgentColorPalette.cy, "9B3A2E"),
            (AgentColorPalette.successLight, "2B6B4F"),
            (AgentColorPalette.successDark, "6FC49B"),
            (AgentColorPalette.destructiveDark, "C95A4B"),
        ]

        for (color, hex) in expected {
            XCTAssertEqual(color.hexString, hex)
        }
    }

    func testPersistedPillarHexRoundTripsThroughOKLCH() throws {
        for hex in ["9B3A2E", "B47724", "55705B", "416B85", "76506F", "FDFDFB", "141414"] {
            let color = try XCTUnwrap(AgentOKLCH(hex: hex))
            XCTAssertEqual(color.hexString, hex)
        }
    }

    func testOutOfGamutColorMapsIntoSRGB() {
        let color = AgentOKLCH(lightness: 0.72, chroma: 0.45, hue: 145).uiColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertTrue((0 ... 1).contains(red))
        XCTAssertTrue((0 ... 1).contains(green))
        XCTAssertTrue((0 ... 1).contains(blue))
    }

    func testCoreTextContrastMeetsAA() {
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.cy.uiColor, AgentColorPalette.canvasLight.uiColor),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.cyTextDark.uiColor, AgentColorPalette.canvasDark.uiColor),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.inkLight.uiColor, AgentColorPalette.canvasLight.uiColor),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.secondaryLight.uiColor, AgentColorPalette.canvasLight.uiColor),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.inkDark.uiColor, AgentColorPalette.canvasDark.uiColor),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.secondaryDark.uiColor, AgentColorPalette.canvasDark.uiColor),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            contrast(AgentColorPalette.inkDark.uiColor, AgentColorPalette.cy.uiColor),
            4.5
        )
    }

    private func contrast(_ foreground: UIColor, _ background: UIColor) -> CGFloat {
        let foregroundLuminance = luminance(foreground)
        let backgroundLuminance = luminance(background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
