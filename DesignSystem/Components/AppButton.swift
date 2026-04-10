import SwiftUI

enum AppButtonStyle {
    case primary
    case secondary
    case tertiary
    case ai
    case destructive
}

struct AppButton: View {
    let title: String
    let style: AppButtonStyle
    let icon: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        _ title: String,
        style: AppButtonStyle = .primary,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(AppFont.headline())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay {
                if style == .secondary || style == .destructive {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: .white
        case .secondary: colorScheme == .dark ? .textOnDark : .brandBlack
        case .tertiary: .brandBrown
        case .ai: .brandBlack
        case .destructive: .error
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: .brandBlack
        case .secondary: .clear
        case .tertiary: .clear
        case .ai: .brandPink
        case .destructive: .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: colorScheme == .dark ? .borderDark : .borderLight
        case .destructive: .error.opacity(0.5)
        default: .clear
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        AppButton("Get Started", style: .primary) {}
        AppButton("Learn More", style: .secondary) {}
        AppButton("Skip", style: .tertiary) {}
        AppButton("Generate Ideas", style: .ai, icon: "sparkles") {}
        AppButton("Delete", style: .destructive, icon: "trash") {}
    }
    .padding()
}
