import SwiftUI
import UIKit

enum AgentSpacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
    static let x12: CGFloat = 48
    static let x16: CGFloat = 64
}

enum AgentRadius {
    static let structural: CGFloat = 8
    static let control: CGFloat = 8
    static let panel: CGFloat = 16
    static let floating: CGFloat = 28
}

extension Color {
    static let agentCanvas = adaptive(light: 0xF5F6F3, dark: 0x1A1A1A)
    static let agentSurface = adaptive(light: 0xFDFDFB, dark: 0x141414)
    static let agentText = adaptive(light: 0x141414, dark: 0xF5F6F3)
    static let agentSecondary = adaptive(light: 0x5C554B, dark: 0xC8BEAA)
    static let agentBorder = adaptive(light: 0x6B6151, dark: 0x786F62)
    static let actionAccent = adaptive(light: 0x141414, dark: 0xF5F6F3)
    static let cyAccent = adaptive(light: 0x9B3A2E, dark: 0x9B3A2E)
    static let onAccent = adaptive(light: 0xF5F6F3, dark: 0x141414)
    static let agentSuccess = adaptive(light: 0x2B6B4F, dark: 0x6FC49B)
    static let agentDestructive = adaptive(light: 0xB42318, dark: 0xFF8A80)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    static var agentDisplay: Font {
        if UIFont(name: "InterVariable-Bold", size: 32) != nil {
            return .custom("InterVariable-Bold", size: 32, relativeTo: .largeTitle)
        }
        return .system(size: 32, weight: .bold, design: .default)
    }

    static var agentTitle: Font {
        if UIFont(name: "InterVariable-Bold", size: 22) != nil {
            return .custom("InterVariable-Bold", size: 22, relativeTo: .title2)
        }
        return .system(size: 22, weight: .bold, design: .default)
    }

    static var agentHeadline: Font {
        if UIFont(name: "InterVariable-SemiBold", size: 18) != nil {
            return .custom("InterVariable-SemiBold", size: 18, relativeTo: .headline)
        }
        return .system(size: 18, weight: .semibold, design: .default)
    }

    static var agentBody: Font {
        if UIFont(name: "InterVariable", size: 15) != nil {
            return .custom("InterVariable", size: 15, relativeTo: .body)
        }
        return .system(size: 15, weight: .regular, design: .default)
    }

    static var agentSubtext: Font {
        if UIFont(name: "InterVariable", size: 13) != nil {
            return .custom("InterVariable", size: 13, relativeTo: .subheadline)
        }
        return .system(size: 13, weight: .regular, design: .default)
    }

    static var agentMono: Font {
        if UIFont(name: "IBMPlexMono-Medm", size: 11) != nil {
            return .custom("IBMPlexMono-Medm", size: 11, relativeTo: .caption)
        }
        return .system(size: 11, weight: .medium, design: .monospaced)
    }
}

struct AgentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AgentSpacing.x6)
            .foregroundStyle(Color.onAccent)
            .background(Color.actionAccent, in: .capsule)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, AgentSpacing.x6)
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .capsule)
            .overlay(Capsule().stroke(Color.agentBorder, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

struct AgentCompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var background: Color = .actionAccent
    var foreground: Color = .onAccent
    var border: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 44)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentCompactSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 44)
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .capsule)
            .overlay(Capsule().stroke(Color.agentBorder, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

struct AgentIconPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(width: 48, height: 48)
            .foregroundStyle(Color.onAccent)
            .background(Color.actionAccent, in: .circle)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentCyFloatingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 48)
            .foregroundStyle(Color.agentCanvas)
            .background(Color.cyAccent, in: .capsule)
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 5)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Color {
    init(agentHex rawValue: String) {
        let cleaned = rawValue.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0x5D6B58
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct EditorialHeader: View {
    let kicker: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel(kicker)
            Text(title)
                .font(.agentDisplay)
                .tracking(-0.64)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetaLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.agentMono)
            .tracking(1.4)
            .foregroundStyle(Color.agentSecondary)
            .accessibilityLabel(text)
    }
}

struct AgentDurationPicker: View {
    static let options = [15, 30, 45, 60, 90]

    @Binding var seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Duration")
            Picker("Duration", selection: $seconds) {
                ForEach(Self.options, id: \.self) { duration in
                    Text("\(duration) SEC")
                        .font(.agentMono)
                        .lineLimit(1)
                        .tag(duration)
                        .accessibilityLabel("\(duration) seconds")
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SectionRuleHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            MetaLabel(title)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.bottom, AgentSpacing.x2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
    }
}

struct CyCallout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            Text("CY")
                .font(.agentMono)
                .tracking(1)
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, AgentSpacing.x3)
                .frame(minHeight: 32)
                .background(Color.cyAccent, in: .capsule)
                .accessibilityLabel("Cy")
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: AgentRadius.panel))
        .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.cyAccent, lineWidth: 1))
        .shadow(color: Color.agentText.opacity(0.08), radius: 6, y: 2)
    }
}

struct EditorialRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, AgentSpacing.x3)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.agentBorder.opacity(0.7)).frame(height: 1)
            }
    }
}

extension View {
    func agentScreen() -> some View {
        background(Color.agentCanvas.ignoresSafeArea())
            .foregroundStyle(Color.agentText)
    }
}
