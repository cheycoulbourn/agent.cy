import CoreGraphics
import UIKit

/// Perceptually uniform color used by the shared agent.cy palette.
///
/// Creator-selected pillar colors remain serialized as sRGB hex values for
/// SwiftData and bridge compatibility. They are converted to OKLCH whenever
/// the interface needs perceptual lightness or a generated color.
struct AgentOKLCH: Equatable, Sendable {
    let lightness: Double
    let chroma: Double
    let hue: Double
    let alpha: Double

    init(
        lightness: Double,
        chroma: Double,
        hue: Double = 0,
        alpha: Double = 1
    ) {
        self.lightness = lightness.clamped(to: 0 ... 1)
        self.chroma = max(0, chroma)
        self.hue = hue.normalizedHue
        self.alpha = alpha.clamped(to: 0 ... 1)
    }

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init?(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        let red = Self.decodeSRGB(red)
        let green = Self.decodeSRGB(green)
        let blue = Self.decodeSRGB(blue)

        let l = cbrt(0.412_221_470_8 * red + 0.536_332_536_3 * green + 0.051_445_992_9 * blue)
        let m = cbrt(0.211_903_498_2 * red + 0.680_699_545_1 * green + 0.107_396_956_6 * blue)
        let s = cbrt(0.088_302_461_9 * red + 0.281_718_837_6 * green + 0.629_978_700_5 * blue)

        let computedLightness = 0.210_454_255_3 * l + 0.793_617_785 * m - 0.004_072_046_8 * s
        let a = 1.977_998_495_1 * l - 2.428_592_205 * m + 0.450_593_709_9 * s
        let b = 0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766 * s
        let computedChroma = hypot(a, b)

        lightness = computedLightness.clamped(to: 0 ... 1)
        chroma = max(0, computedChroma)
        hue = computedChroma < 0.000_001
            ? 0
            : (atan2(b, a) * 180 / .pi).normalizedHue
        self.alpha = alpha.clamped(to: 0 ... 1)
    }

    var uiColor: UIColor {
        let components = gamutMappedSRGB()
        return UIColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: alpha
        )
    }

    var hexString: String {
        let components = gamutMappedSRGB()
        let red = Int((components.red * 255).rounded()).clamped(to: 0 ... 255)
        let green = Int((components.green * 255).rounded()).clamped(to: 0 ... 255)
        let blue = Int((components.blue * 255).rounded()).clamped(to: 0 ... 255)
        return String(format: "%02X%02X%02X", red, green, blue)
    }

    private func gamutMappedSRGB() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        if let components = sRGBComponents(chroma: chroma) {
            return components
        }

        var lower = 0.0
        var upper = chroma
        for _ in 0 ..< 24 {
            let candidate = (lower + upper) / 2
            if sRGBComponents(chroma: candidate) == nil {
                upper = candidate
            } else {
                lower = candidate
            }
        }
        return sRGBComponents(chroma: lower) ?? (0, 0, 0)
    }

    private func sRGBComponents(chroma: Double) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)

        let lPrime = lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b
        let mPrime = lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b
        let sPrime = lightness - 0.089_484_177_5 * a - 1.291_485_548 * b

        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime

        let linearRed = 4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s
        let linearGreen = -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s
        let linearBlue = -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701 * s

        let epsilon = 0.000_001
        guard linearRed >= -epsilon, linearRed <= 1 + epsilon,
              linearGreen >= -epsilon, linearGreen <= 1 + epsilon,
              linearBlue >= -epsilon, linearBlue <= 1 + epsilon else {
            return nil
        }

        return (
            CGFloat(Self.encodeSRGB(linearRed.clamped(to: 0 ... 1))),
            CGFloat(Self.encodeSRGB(linearGreen.clamped(to: 0 ... 1))),
            CGFloat(Self.encodeSRGB(linearBlue.clamped(to: 0 ... 1)))
        )
    }

    private static func decodeSRGB(_ component: Double) -> Double {
        component <= 0.040_45
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func encodeSRGB(_ component: Double) -> Double {
        component <= 0.003_130_8
            ? 12.92 * component
            : 1.055 * pow(component, 1 / 2.4) - 0.055
    }
}

enum AgentColorPalette {
    static let pureBlack = AgentOKLCH(lightness: 0, chroma: 0)
    static let pureWhite = AgentOKLCH(lightness: 1, chroma: 0)
    static let canvasLight = AgentOKLCH(lightness: 0.971_550, chroma: 0.004_097, hue: 121.560)
    static let canvasDark = AgentOKLCH(lightness: 0.217_787, chroma: 0)
    static let surfaceLight = AgentOKLCH(lightness: 0.993_494, chroma: 0.002_631, hue: 106.447)
    static let surfaceDark = AgentOKLCH(lightness: 0.191_251, chroma: 0)
    static let inkLight = AgentOKLCH(lightness: 0.191_251, chroma: 0)
    static let inkDark = AgentOKLCH(lightness: 0.971_550, chroma: 0.004_097, hue: 121.560)
    static let secondaryLight = AgentOKLCH(lightness: 0.422_124, chroma: 0.011_089, hue: 78.205)
    static let secondaryDark = AgentOKLCH(lightness: 0.843_056, chroma: 0.011_833, hue: 84.582)
    static let borderLight = AgentOKLCH(lightness: 0.880_042, chroma: 0.006_849, hue: 115.721)
    static let borderDark = AgentOKLCH(lightness: 0.340_697, chroma: 0)
    static let hairlineLight = AgentOKLCH(lightness: 0.925_801, chroma: 0.006_763, hue: 115.712)
    static let hairlineDark = AgentOKLCH(lightness: 0.297_163, chroma: 0)
    static let focusLight = secondaryLight
    static let focusDark = AgentOKLCH(lightness: 0.577_487, chroma: 0.011_608, hue: 81.784)
    static let cy = AgentOKLCH(lightness: 0.482_312, chroma: 0.132_281, hue: 29.753)
    static let successLight = AgentOKLCH(lightness: 0.477_807, chroma: 0.080_431, hue: 162.116)
    static let successDark = AgentOKLCH(lightness: 0.755_022, chroma: 0.102_919, hue: 161.594)
    static let destructiveLight = cy
    static let destructiveDark = AgentOKLCH(lightness: 0.603_551, chroma: 0.144_740, hue: 29.729)

    /// Cy as a *foreground* on dark surfaces: same hue with lifted lightness so
    /// Text clears 4.5:1 against both dark canvas and surface. Fills keep using `cy`.
    static let cyTextDark = AgentOKLCH(lightness: 0.622, chroma: 0.144_740, hue: 29.729)

    /// The one fallback for pillar colors that fail to parse or are absent,
    /// shared by the app and the widgets so the two never drift apart.
    static let pillarFallbackHex = "5D6B58"
    static let priorityHighLight = AgentOKLCH(lightness: 0.765_240, chroma: 0.175_207, hue: 62.574)
    static let priorityHighDark = AgentOKLCH(lightness: 0.782_365, chroma: 0.171_055, hue: 67.223)
    static let cyPanel = AgentOKLCH(lightness: 0.232_309, chroma: 0.014_850, hue: 32.682)
}

private extension BinaryFloatingPoint {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension BinaryInteger {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Double {
    var normalizedHue: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
