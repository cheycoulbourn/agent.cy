import SwiftUI

enum ShareSpacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
}

enum ShareRadius {
    static let control: CGFloat = 8
    static let panel: CGFloat = 16
    static let dashboard: CGFloat = 20
}

extension Color {
    static let shareCanvas = shareAdaptive(
        light: AgentColorPalette.canvasLight,
        dark: AgentColorPalette.canvasDark
    )
    static let shareSurface = shareAdaptive(
        light: AgentColorPalette.surfaceLight,
        dark: AgentColorPalette.surfaceDark
    )
    static let shareText = shareAdaptive(
        light: AgentColorPalette.inkLight,
        dark: AgentColorPalette.inkDark
    )
    static let shareSecondary = shareAdaptive(
        light: AgentColorPalette.secondaryLight,
        dark: AgentColorPalette.secondaryDark
    )
    static let shareBorder = shareAdaptive(
        light: AgentColorPalette.borderLight,
        dark: AgentColorPalette.borderDark
    )
    static let shareHairline = shareAdaptive(
        light: AgentColorPalette.hairlineLight,
        dark: AgentColorPalette.hairlineDark
    )
    static let shareCy = Color(uiColor: AgentColorPalette.cy.uiColor)
    static let shareCyText = shareAdaptive(
        light: AgentColorPalette.cy,
        dark: AgentColorPalette.cyTextDark
    )
    static let shareOnCy = Color(uiColor: AgentColorPalette.inkDark.uiColor)
    static let shareSuccess = shareAdaptive(
        light: AgentColorPalette.successLight,
        dark: AgentColorPalette.successDark
    )

    static func sharePillar(hex: String?) -> Color {
        guard let hex, let color = AgentOKLCH(hex: hex) else { return .shareSecondary }
        return Color(uiColor: color.uiColor)
    }

    private static func shareAdaptive(light: AgentOKLCH, dark: AgentOKLCH) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        })
    }
}

extension Font {
    static let shareTitle = Font.custom("InterVariable", size: 26).weight(.semibold)
    static let shareHeadline = Font.custom("InterVariable", size: 20).weight(.semibold)
    static let shareBody = Font.custom("InterVariable", size: 16)
    static let shareBodyStrong = Font.custom("InterVariable", size: 16).weight(.semibold)
    static let shareMeta = Font.custom("InterVariable", size: 12).weight(.semibold)
    static let shareCaption = Font.custom("InterVariable", size: 14)
}

struct SharePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.shareBodyStrong)
            .foregroundStyle(Color.shareOnCy)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, ShareSpacing.x5)
            .background(Color.shareCy, in: .capsule)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ShareSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.shareBodyStrong)
            .foregroundStyle(Color.shareText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, ShareSpacing.x5)
            .background(Color.shareSurface, in: .capsule)
            .overlay { Capsule().stroke(Color.shareBorder, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SharePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ShareSpacing.x5)
            .background(Color.shareSurface, in: .rect(cornerRadius: ShareRadius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: ShareRadius.panel)
                    .stroke(Color.shareBorder, lineWidth: 1)
            }
    }
}

struct ShareMetaLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.shareMeta)
            .tracking(1.2)
            .foregroundStyle(Color.shareSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ShareCyThinkingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let duration = reduceMotion ? 1.8 : 1.1
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration
            let pulse = abs(progress - 0.5) * 2

            ZStack {
                Capsule().frame(width: max(2, size * 0.1), height: size)
                Capsule().frame(width: max(2, size * 0.1), height: size)
                    .rotationEffect(.degrees(45))
                Capsule().frame(width: max(2, size * 0.1), height: size)
                    .rotationEffect(.degrees(90))
                Capsule().frame(width: max(2, size * 0.1), height: size)
                    .rotationEffect(.degrees(135))
            }
            .foregroundStyle(Color.shareCyText)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(reduceMotion ? 0 : progress * 360))
            .scaleEffect(reduceMotion ? 0.94 + (pulse * 0.12) : 1)
            .opacity(reduceMotion ? 0.68 + (pulse * 0.32) : 1)
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityLabel("Cy is analyzing")
    }
}
