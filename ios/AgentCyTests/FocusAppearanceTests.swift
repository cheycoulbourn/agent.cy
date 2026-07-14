import SwiftUI
import UIKit
import XCTest
@testable import AgentCy

final class FocusAppearanceTests: XCTestCase {
    func testFocusToggleOnTrackContrastsWithWhiteThumbInBothAppearances() {
        let track = UIColor(Color.agentFocusControl)
        let whiteThumb = UIColor.white

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let resolvedTrack = track.resolvedColor(with: traits)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(resolvedTrack, whiteThumb),
                3,
                "The enabled focus toggle must remain distinguishable in \(style == .dark ? "dark" : "light") mode."
            )
        }
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        guard let components = color.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .relativeColorimetric,
            options: nil
        )?.components else { return 0 }

        let channels = components.count >= 3
            ? Array(components.prefix(3))
            : Array(repeating: components[0], count: 3)
        let linear = channels.map { channel -> CGFloat in
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
