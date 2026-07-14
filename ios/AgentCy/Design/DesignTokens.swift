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

enum AgentLayout {
    /// Standard inset for page headers, forms, and unboxed content.
    static let pageMargin: CGFloat = AgentSpacing.x6
    /// Outer gutter for the rounded dashboard surfaces used by Today, Agenda, and Pillars.
    static let dashboardGutter: CGFloat = AgentSpacing.x3
}

enum AgentRadius {
    static let structural: CGFloat = 8
    static let control: CGFloat = 8
    static let panel: CGFloat = 16
    static let floating: CGFloat = 28
    static let dashboard: CGFloat = 28
}

extension Color {
    static let agentCanvas = adaptive(light: 0xF5F6F3, dark: 0x1A1A1A)
    static let agentSurface = adaptive(light: 0xFDFDFB, dark: 0x141414)
    static let agentText = adaptive(light: 0x141414, dark: 0xF5F6F3)
    static let agentSecondary = adaptive(light: 0x514D47, dark: 0xCFCBC3)
    static let agentBorder = adaptive(light: 0xD7D8D3, dark: 0x383838)
    static let agentHairline = adaptive(light: 0xE6E7E2, dark: 0x2D2D2D)
    static let agentFocusControl = adaptive(light: 0x514D47, dark: 0x7D7972)
    static let actionAccent = adaptive(light: 0x141414, dark: 0xF5F6F3)
    static let cyAccent = adaptive(light: 0x9B3A2E, dark: 0x9B3A2E)
    static let onCyAccent = adaptive(light: 0xF5F6F3, dark: 0xF5F6F3)
    static let onAccent = adaptive(light: 0xF5F6F3, dark: 0x141414)
    static let agentSuccess = adaptive(light: 0x2B6B4F, dark: 0x6FC49B)
    static let agentDestructive = adaptive(light: 0x9B3A2E, dark: 0xC95A4B)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension AppearancePreference {
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
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
        if UIFont(name: "InterVariable", size: 32) != nil {
            return .custom("InterVariable", size: 32, relativeTo: .largeTitle).weight(.bold)
        }
        return .system(size: 32, weight: .bold, design: .default)
    }

    static var agentTitle: Font {
        if UIFont(name: "InterVariable", size: 22) != nil {
            return .custom("InterVariable", size: 22, relativeTo: .title2).weight(.bold)
        }
        return .system(size: 22, weight: .bold, design: .default)
    }

    static var agentBriefTitle: Font {
        if UIFont(name: "InterVariable", size: 28) != nil {
            return .custom("InterVariable", size: 28, relativeTo: .title).weight(.semibold)
        }
        return .system(size: 28, weight: .semibold, design: .default)
    }

    static var agentHeadline: Font {
        if UIFont(name: "InterVariable", size: 18) != nil {
            return .custom("InterVariable", size: 18, relativeTo: .headline).weight(.semibold)
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
    var background: Color = .actionAccent
    var foreground: Color = .onAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AgentLayout.pageMargin)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentCyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AgentSpacing.x6)
            .foregroundStyle(Color.onCyAccent)
            .background(Color.cyAccent, in: .capsule)
            .shadow(color: Color.cyAccent.opacity(0.28), radius: 16, y: 6)
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
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AgentSpacing.x6)
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.agentBorder, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

struct AgentAddActionRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            Color.agentSecondary,
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                        )
                        .frame(width: 18, height: 18)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(width: 18, height: 18)

                Text(title)
                    .font(.agentBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.agentText)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
            .font(.system(size: 21, weight: .semibold))
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.onCyAccent)
            .background(Color.cyAccent, in: .circle)
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 5)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
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

/// A menu-safe pillar label. Native menus render ordinary SwiftUI shapes and
/// SF Symbols as template images, which turns every swatch into the menu tint.
/// Supplying an always-original bitmap preserves the creator's chosen color.
struct PillarMenuChoiceLabel: View {
    let title: String
    let colorHex: String
    var isSelected = false

    var body: some View {
        Label {
            Text(isSelected ? "\(title) ✓" : title)
        } icon: {
            Image(uiImage: swatchImage)
                .renderingMode(.original)
        }
    }

    private var swatchImage: UIImage {
        let diameter: CGFloat = 14
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { context in
            UIColor(Color(agentHex: colorHex)).setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: 0, y: 0, width: diameter, height: diameter)
            )
        }
        return image.withRenderingMode(.alwaysOriginal)
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
    @Binding var seconds: Int
    var format: ContentFormat = .shortForm

    private var options: [Int] { format.durationOptions }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Duration")
            Picker("Duration", selection: $seconds) {
                ForEach(options, id: \.self) { duration in
                    Text(durationLabel(duration))
                        .font(.agentMono)
                        .lineLimit(1)
                        .tag(duration)
                        .accessibilityLabel(accessibilityDurationLabel(duration))
                }
            }
            .pickerStyle(.segmented)
            .onAppear {
                if !format.durationOptions.contains(seconds) {
                    seconds = format.defaultDuration
                }
            }
            .onChange(of: format) { _, newFormat in
                if !newFormat.durationOptions.contains(seconds) {
                    seconds = newFormat.defaultDuration
                }
            }
        }
    }

    private func durationLabel(_ duration: Int) -> String {
        duration < 120 ? "\(duration) SEC" : "\(duration / 60) MIN"
    }

    private func accessibilityDurationLabel(_ duration: Int) -> String {
        duration < 120 ? "\(duration) seconds" : "\(duration / 60) minutes"
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

enum CyVoiceHeading: String, CaseIterable, Sendable {
    case says = "Cy says"
    case thinksYouShould = "Cy thinks you should"
    case noticed = "Cy noticed"
    case wantsToKnow = "Cy wants to know"
    case hasAnIdea = "Cy has an idea"
    case madeThisForYou = "Cy made this for you"
    case suggestedForYou = "Suggested for you"
    case keepsItPrivate = "Cy keeps it private"

    static func forMessage(_ message: String, index: Int) -> CyVoiceHeading {
        let normalized = message.lowercased()
        if message.contains("?") { return .wantsToKnow }
        if normalized.contains("recommend") || normalized.contains("you should") {
            return .thinksYouShould
        }
        if normalized.contains("notice") || normalized.contains("pattern") {
            return .noticed
        }
        return index.isMultiple(of: 2) ? .says : .hasAnIdea
    }
}

struct CyVoiceAction {
    let title: String
    var isEnabled = true
    let action: () -> Void

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct CyVoiceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let heading: CyVoiceHeading
    let title: String
    var message: String?
    var primaryAction: CyVoiceAction?
    var secondaryAction: CyVoiceAction?
    var dismissAction: (() -> Void)?

    private let foreground = Color(agentHex: "F5F6F3")
    private let secondary = Color(agentHex: "CFCBC3")

    private var background: Color {
        colorScheme == .dark ? Color(agentHex: "241B19") : Color(agentHex: "141414")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: AgentSpacing.x2) {
                CyAsterisk()
                Text(heading.rawValue.uppercased())
                    .font(.agentMono)
                    .tracking(1.4)
                    .foregroundStyle(Color.cyAccent)
                    .accessibilityLabel(heading.rawValue)
                Spacer(minLength: 0)
                if let dismissAction {
                    Button(action: dismissAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(secondary)
                    .accessibilityLabel("Dismiss Cy suggestion")
                    .padding(.trailing, -14)
                    .padding(.vertical, -14)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.agentTitle)
                    .tracking(-0.2)
                    .foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.agentBody)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let primaryAction {
                Button(action: primaryAction.action) {
                    HStack(spacing: AgentSpacing.x2) {
                        Text(primaryAction.title)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(background)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, AgentSpacing.x4)
                    .background(foreground, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!primaryAction.isEnabled)
                .opacity(primaryAction.isEnabled ? 1 : 0.48)
            }

            if let secondaryAction {
                Button(action: secondaryAction.action) {
                    HStack(spacing: 6) {
                        Text(secondaryAction.title)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .font(.agentSubtext)
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!secondaryAction.isEnabled)
            }
        }
        .padding(AgentSpacing.x6)
        .background(background, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.cyAccent.opacity(colorScheme == .dark ? 0.42 : 0.18), lineWidth: 1)
        }
        .shadow(color: Color.cyAccent.opacity(colorScheme == .dark ? 0.14 : 0.08), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
    }
}

struct CyAsterisk: View {
    var color: Color = .cyAccent
    var size: CGFloat = 14
    var strokeWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            Capsule().frame(width: strokeWidth, height: size)
            Capsule().frame(width: strokeWidth, height: size).rotationEffect(.degrees(45))
            Capsule().frame(width: strokeWidth, height: size).rotationEffect(.degrees(90))
            Capsule().frame(width: strokeWidth, height: size).rotationEffect(.degrees(135))
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CyThinkingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var color: Color = .cyAccent
    var size: CGFloat = 18

    var body: some View {
        TimelineView(.animation) { timeline in
            let duration = reduceMotion ? 1.8 : 1.1
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration
            let pulse = abs(progress - 0.5) * 2

            CyAsterisk(
                color: color,
                size: size,
                strokeWidth: max(1.5, size * 0.1)
            )
            .frame(width: size, height: size)
            .compositingGroup()
            .rotationEffect(.degrees(reduceMotion ? 0 : progress * 360), anchor: .center)
            .scaleEffect(reduceMotion ? 0.94 + (pulse * 0.12) : 1, anchor: .center)
            .opacity(reduceMotion ? 0.68 + (pulse * 0.32) : 1)
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct CyCallout<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let heading: CyVoiceHeading
    @ViewBuilder let content: Content

    init(heading: CyVoiceHeading = .says, @ViewBuilder content: () -> Content) {
        self.heading = heading
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(spacing: AgentSpacing.x2) {
                CyAsterisk()
                Text(heading.rawValue.uppercased())
                    .font(.agentMono)
                    .tracking(1.4)
                    .foregroundStyle(Color.cyAccent)
                    .accessibilityLabel(heading.rawValue)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.agentText)
        .padding(AgentSpacing.x6)
        .background(
            colorScheme == .dark ? Color(agentHex: "241B19") : Color(agentHex: "141414"),
            in: .rect(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.cyAccent.opacity(colorScheme == .dark ? 0.42 : 0.18), lineWidth: 1)
        }
        .shadow(color: Color.cyAccent.opacity(colorScheme == .dark ? 0.14 : 0.08), radius: 18, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
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

struct AgentDashboardSurface<Content: View>: View {
    let minimumHeight: CGFloat?
    @ViewBuilder let content: Content

    init(minimumHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.minimumHeight = minimumHeight
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x8)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .shadow(color: Color.black.opacity(0.045), radius: 18, y: 2)
    }
}

struct AgentViewHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AgentInsetSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AgentLayout.pageMargin)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
    }
}

extension View {
    func reportAgentViewHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: AgentViewHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
    }

    func agentScreen() -> some View {
        background(Color.agentCanvas.ignoresSafeArea())
            .foregroundStyle(Color.agentText)
    }

    func agentDashboardScreen() -> some View {
        background(Color.agentCanvas.ignoresSafeArea())
        .foregroundStyle(Color.agentText)
    }

    func agentKeyboardDismissal() -> some View {
        modifier(AgentKeyboardDismissalModifier())
    }

    /// Gives short fields the native blue Done return key and releases SwiftUI focus on submit.
    func agentSingleLineSubmit() -> some View {
        modifier(AgentSingleLineSubmitModifier())
    }
}

@MainActor
enum AgentKeyboard {
    static func dismiss() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .endEditing(true)
    }
}

struct AgentInputHeader: View {
    let title: String
    var isEditing = false
    var onDone: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            MetaLabel(title)
            Spacer()
            if isEditing {
                Button("Done") {
                    onDone()
                    AgentKeyboard.dismiss()
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .accessibilityHint("Keeps your writing and hides the keyboard")
            }
        }
    }
}

/// A writing field that owns its focus so the dismissal action remains reliable in sheets and forms.
struct AgentMultilineField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 2...8
    @FocusState private var isFocused: Bool

    private var visiblePlaceholder: String {
        label.localizedCaseInsensitiveContains("note") ? "" : placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) { isFocused = false }
            TextField(visiblePlaceholder, text: $text, axis: .vertical)
                .font(.agentBody)
                .lineLimit(lineLimit)
                .focused($isFocused)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .strokeBorder(Color.agentBorder, lineWidth: 1)
                )
        }
    }
}

private struct AgentSingleLineSubmitModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit {
                isFocused = false
                AgentKeyboard.dismiss()
            }
    }
}

private struct AgentKeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

enum AgentChipContrast {
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init?(hex: String) {
            let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        }

        func mixed(toward target: RGB, amount: Double) -> RGB {
            RGB(
                red: red + (target.red - red) * amount,
                green: green + (target.green - green) * amount,
                blue: blue + (target.blue - blue) * amount
            )
        }

        private init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var luminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        var hex: String {
            let redValue = Int((red * 255).rounded()).clamped(to: 0...255)
            let greenValue = Int((green * 255).rounded()).clamped(to: 0...255)
            let blueValue = Int((blue * 255).rounded()).clamped(to: 0...255)
            return String(format: "%02X%02X%02X", redValue, greenValue, blueValue)
        }

        static let black = RGB(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255)
        static let offWhite = RGB(red: 0xF5 / 255, green: 0xF6 / 255, blue: 0xF3 / 255)
    }

    static func adjustedHex(
        pillarHex: String,
        against backgroundHex: String,
        minimumContrast: Double = 3
    ) -> String {
        guard let pillar = RGB(hex: pillarHex), let background = RGB(hex: backgroundHex) else {
            return "5D6B58"
        }
        guard contrast(pillar, background) < minimumContrast else { return pillar.hex }

        let target = background.luminance > 0.5 ? RGB.black : RGB.offWhite
        for step in 1...20 {
            let candidate = pillar.mixed(toward: target, amount: Double(step) * 0.05)
            if contrast(candidate, background) >= minimumContrast { return candidate.hex }
        }
        return target.hex
    }

    static func foregroundHex(on backgroundHex: String) -> String {
        guard let background = RGB(hex: backgroundHex) else { return "141414" }
        return contrast(RGB.black, background) >= contrast(RGB.offWhite, background)
            ? RGB.black.hex
            : RGB.offWhite.hex
    }

    private static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(first.luminance, second.luminance)
        let darker = min(first.luminance, second.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
