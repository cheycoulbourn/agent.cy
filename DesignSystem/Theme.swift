import SwiftUI

// MARK: - Color Palette

// Used for Color.brandBlack, Color.brandPink etc. in backgrounds/fills
extension Color {
    static let brandBlack = Color(hex: "1A1A1A")
    static let brandBeige = Color(hex: "E8DDD3")
    static let brandBrown = Color(hex: "A68B7B")
    static let brandPink = Color(hex: "F2C4C4")
    static let bgLight = Color(hex: "FAF8F5")
    static let bgDark = Color(hex: "0F0F0F")
    static let cardLight = Color.white
    static let cardDark = Color(hex: "1C1C1C")
    static let borderLight = Color(hex: "E5E0DA")
    static let borderDark = Color(hex: "2A2A2A")
    static let textPrimary = Color(hex: "1A1A1A")
    static let textSecondary = Color(hex: "A68B7B")
    static let textTertiary = Color(hex: "8E8C99")
    static let textOnDark = Color(hex: "F0EEF5")
    static let aiAccent = Color(hex: "F2C4C4")
    static let success = Color(hex: "7BC47F")
    static let warning = Color(hex: "E8C547")
    static let error = Color(hex: "E85D5D")
}


// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Colors

struct AppColors {
    @Environment(\.colorScheme) private var colorScheme

    static let shared = AppColors()

    func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .bgDark : .bgLight
    }

    func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .cardDark : .cardLight
    }

    func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .borderDark : .borderLight
    }

    func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .textOnDark : .textPrimary
    }
}

// MARK: - Typography

struct AppFont {
    static func largeTitle(_ weight: Font.Weight = .bold) -> Font {
        .system(size: 34, weight: weight, design: .default)
    }

    static func title1(_ weight: Font.Weight = .bold) -> Font {
        .system(size: 28, weight: weight, design: .default)
    }

    static func title2(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 22, weight: weight, design: .default)
    }

    static func title3(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 20, weight: weight, design: .default)
    }

    static func headline(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 17, weight: weight, design: .default)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 17, weight: weight, design: .default)
    }

    static func callout(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 16, weight: weight, design: .default)
    }

    static func subhead(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 15, weight: weight, design: .default)
    }

    static func footnote(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight, design: .default)
    }

    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
}

// MARK: - Corner Radius

enum CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 24
}

// MARK: - Shadows

struct AppShadow {
    static let card = ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    static let elevated = ShadowStyle(color: .black.opacity(0.1), radius: 16, x: 0, y: 4)
    static let subtle = ShadowStyle(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func appShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
