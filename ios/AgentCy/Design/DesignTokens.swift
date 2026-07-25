import SwiftUI
import UIKit

enum AgentSpacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
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
    /// Consistent distance from the final line of a page header to its first primary surface.
    static let pageHeaderToContentSpacing: CGFloat = AgentSpacing.x8
    /// Standard vertical gap between a section's metadata heading and its primary content.
    static let sectionHeadingSpacing: CGFloat = AgentSpacing.x2
    /// Clears the floating bottom navigation without each screen inventing its own inset.
    static let bottomNavigationClearance: CGFloat = 120
}

enum AgentRadius {
    static let structural: CGFloat = 8
    static let control: CGFloat = 8
    static let panel: CGFloat = 16
    static let floating: CGFloat = 28
    static let dashboard: CGFloat = 28
}

/// Semantic icons for agent.cy. The artwork is curated from the creator's
/// licensed Nucleo UI outline library and stored as template SVG assets so the
/// same mark is used consistently in light mode, dark mode, and tinted states.
enum AgentIcon: String, CaseIterable, Sendable {
    case add = "agent-icon-add"
    case close = "agent-icon-close"
    case check = "agent-icon-check"
    case checkCircle = "agent-icon-check-circle"
    case radioEmpty = "agent-icon-radio-empty"
    case radioSelected = "agent-icon-radio-selected"
    case checkboxEmpty = "agent-icon-checkbox-empty"
    case checkboxSelected = "agent-icon-checkbox-selected"
    case back = "agent-icon-back"
    case forward = "agent-icon-forward"
    case expand = "agent-icon-expand"
    case collapse = "agent-icon-collapse"
    case moveVertical = "agent-icon-move-vertical"
    case external = "agent-icon-external"
    case arrowUp = "agent-icon-arrow-up"
    case arrowRight = "agent-icon-arrow-right"
    case branch = "agent-icon-branch"
    case refresh = "agent-icon-refresh"
    case home = "agent-icon-home"
    case calendar = "agent-icon-calendar"
    case tasks = "agent-icon-tasks"
    case pillars = "agent-icon-pillars"
    case ideas = "agent-icon-ideas"
    case more = "agent-icon-more"
    case menu = "agent-icon-menu"
    case search = "agent-icon-search"
    case filter = "agent-icon-filter"
    case download = "agent-icon-download"
    case upload = "agent-icon-upload"
    case trash = "agent-icon-trash"
    case duplicate = "agent-icon-duplicate"
    case terminal = "agent-icon-terminal"
    case image = "agent-icon-image"
    case video = "agent-icon-video"
    case microphone = "agent-icon-microphone"
    case profile = "agent-icon-profile"
    case warning = "agent-icon-warning"
    case keyboardDown = "agent-icon-keyboard-down"
    case idea = "agent-icon-idea"
    case folder = "agent-icon-folder"
    case key = "agent-icon-key"
    case pencil = "agent-icon-pencil"
    case archive = "agent-icon-archive"
    case link = "agent-icon-link"
    case attachment = "agent-icon-attachment"
    case play = "agent-icon-play"
    case stop = "agent-icon-stop"
    case copy = "agent-icon-copy"
    case text = "agent-icon-text"
    case camera = "agent-icon-camera"
    case music = "agent-icon-music"
    case messages = "agent-icon-messages"
    case verified = "agent-icon-verified"
    case send = "agent-icon-send"
    case sliders = "agent-icon-sliders"
    case business = "agent-icon-business"

    init(legacySystemName name: String) {
        switch name {
        case "archivebox": self = .archive
        case "asterisk", "sparkles": self = .idea
        case "arrow.down.to.line", "square.and.arrow.down": self = .download
        case "arrow.right": self = .arrowRight
        case "arrow.triangle.2.circlepath": self = .refresh
        case "arrow.triangle.branch": self = .branch
        case "arrow.up": self = .arrowUp
        case "arrow.up.right": self = .external
        case "calendar": self = .calendar
        case "checkmark": self = .check
        case "checkmark.circle.fill": self = .checkCircle
        case "checkmark.square", "checkmark.square.fill": self = .checkboxSelected
        case "chevron.left": self = .back
        case "chevron.right": self = .forward
        case "chevron.down": self = .expand
        case "chevron.up": self = .collapse
        case "chevron.up.chevron.down": self = .moveVertical
        case "circle": self = .radioEmpty
        case "doc.fill", "doc.on.doc", "text.page": self = .copy
        case "ellipsis": self = .more
        case "exclamationmark": self = .warning
        case "folder": self = .folder
        case "house": self = .home
        case "key": self = .key
        case "keyboard.chevron.compact.down": self = .keyboardDown
        case "lightbulb", "lightbulb.fill": self = .idea
        case "link": self = .link
        case "line.3.horizontal": self = .menu
        case "line.3.horizontal.decrease": self = .filter
        case "magnifyingglass": self = .search
        case "mic": self = .microphone
        case "music.note": self = .music
        case "pencil": self = .pencil
        case "person.fill": self = .profile
        case "camera.aperture": self = .camera
        case "photo.on.rectangle.angled": self = .image
        case "play.fill", "play.rectangle.fill": self = .play
        case "plus": self = .add
        case "square": self = .checkboxEmpty
        case "square.and.arrow.up": self = .upload
        case "square.grid.2x2": self = .pillars
        case "slider.horizontal.3": self = .sliders
        case "square.on.square": self = .duplicate
        case "stop.fill": self = .stop
        case "terminal": self = .terminal
        case "trash": self = .trash
        case "tray": self = .ideas
        case "text.alignleft", "text.viewfinder": self = .text
        case "bubble.left.and.text.bubble.right": self = .messages
        case "checkmark.seal": self = .verified
        case "paperplane", "paperplane.fill": self = .send
        case "briefcase": self = .business
        case "video.fill": self = .video
        case "xmark": self = .close
        case "xmark.circle.fill": self = .close
        default:
            #if DEBUG
            assertionFailure("Unsupported legacy system icon: \(name)")
            #endif
            self = .warning
        }
    }
}

struct AgentIconView: View {
    let icon: AgentIcon
    var size: CGFloat = 18

    nonisolated init(_ icon: AgentIcon, size: CGFloat = 18) {
        self.icon = icon
        self.size = size
    }

    nonisolated init(systemName: String, size: CGFloat = 18) {
        self.init(AgentIcon(legacySystemName: systemName), size: size)
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AgentIconLabel: View {
    let title: String
    let icon: AgentIcon
    var iconSize: CGFloat = 16

    var body: some View {
        Label {
            Text(title)
        } icon: {
            AgentIconView(icon, size: iconSize)
        }
    }
}

struct AgentToolbarIconButton: View {
    let title: String
    let icon: AgentIcon
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AgentIconView(icon, size: 17)
                .foregroundStyle(Color.agentText)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
        .overlay {
            Circle()
                .stroke(Color.agentPureWhite.opacity(0.22), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.agentPureBlack.opacity(0.08), radius: 12, y: 4)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(title)
    }
}

extension Color {
    static let agentPureBlack = Color(uiColor: AgentColorPalette.pureBlack.uiColor)
    static let agentPureWhite = Color(uiColor: AgentColorPalette.pureWhite.uiColor)
    static let agentCanvas = adaptive(light: AgentColorPalette.canvasLight, dark: AgentColorPalette.canvasDark)
    static let agentSurface = adaptive(light: AgentColorPalette.surfaceLight, dark: AgentColorPalette.surfaceDark)
    static let agentText = adaptive(light: AgentColorPalette.inkLight, dark: AgentColorPalette.inkDark)
    static let agentSecondary = adaptive(light: AgentColorPalette.secondaryLight, dark: AgentColorPalette.secondaryDark)
    static let agentBorder = adaptive(light: AgentColorPalette.borderLight, dark: AgentColorPalette.borderDark)
    static let agentHairline = adaptive(light: AgentColorPalette.hairlineLight, dark: AgentColorPalette.hairlineDark)
    static let agentFocusControl = adaptive(light: AgentColorPalette.focusLight, dark: AgentColorPalette.focusDark)
    static let actionAccent = adaptive(light: AgentColorPalette.inkLight, dark: AgentColorPalette.inkDark)
    static let cyAccent = Color(uiColor: AgentColorPalette.cy.uiColor)
    static let onCyAccent = Color(uiColor: AgentColorPalette.inkDark.uiColor)
    static let onAccent = adaptive(light: AgentColorPalette.inkDark, dark: AgentColorPalette.inkLight)
    static let agentSuccess = adaptive(light: AgentColorPalette.successLight, dark: AgentColorPalette.successDark)
    static let agentDestructive = adaptive(light: AgentColorPalette.destructiveLight, dark: AgentColorPalette.destructiveDark)
    static let agentPriorityHigh = adaptive(light: AgentColorPalette.priorityHighLight, dark: AgentColorPalette.priorityHighDark)

    private static func adaptive(light: AgentOKLCH, dark: AgentOKLCH) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        })
    }
}

enum PillarVisualContrast {
    static func outlineColor(for color: Color, colorScheme: ColorScheme) -> Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        guard let oklch = AgentOKLCH(uiColor: resolved) else {
            return Color.agentText.opacity(0.34)
        }

        if colorScheme == .dark {
            return Color.agentPureWhite.opacity(oklch.lightness < 0.52 ? 0.58 : 0.20)
        }
        return Color.agentPureBlack.opacity(oklch.lightness > 0.82 ? 0.38 : 0.16)
    }

    static func cardBorderColor(for color: Color, colorScheme: ColorScheme) -> Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        guard let oklch = AgentOKLCH(uiColor: resolved) else {
            return Color.agentText.opacity(0.34)
        }

        if colorScheme == .dark, oklch.lightness < 0.52 {
            return Color.agentPureWhite.opacity(0.52)
        }
        if colorScheme == .light, oklch.lightness > 0.82 {
            return Color.agentPureBlack.opacity(0.32)
        }
        return color.opacity(colorScheme == .dark ? 0.86 : 0.72)
    }
}

struct PillarColorMark: View {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color
    var diameter: CGFloat = 8
    var lineWidth: CGFloat = 0.75

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .stroke(
                        PillarVisualContrast.outlineColor(for: color, colorScheme: colorScheme),
                        lineWidth: lineWidth
                    )
            }
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

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
enum AgentAppearanceController {
    static func apply(_ preference: AppearancePreference) {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.overrideUserInterfaceStyle = preference.userInterfaceStyle }
    }
}

extension Font {
    static func agentInter(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: TextStyle = .body
    ) -> Font {
        if UIFont(name: "InterVariable", size: size) != nil {
            return .custom("InterVariable", size: size, relativeTo: style).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    static var agentDisplayLead: Font {
        if UIFont(name: "InterVariable", size: 32) != nil {
            return .custom("InterVariable", size: 32, relativeTo: .largeTitle)
        }
        return .system(size: 32, weight: .regular, design: .default)
    }

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

    /// Typography for every inline add action (Add task, Schedule post,
    /// Capture an idea, and similar rows). Keep these actions quiet and
    /// consistent; primary creation buttons use their dedicated button style.
    static var agentAddAction: Font {
        if UIFont(name: "InterVariable", size: 15) != nil {
            return .custom("InterVariable", size: 15, relativeTo: .body).weight(.medium)
        }
        return .system(size: 15, weight: .medium, design: .default)
    }

    /// Compact Inter style for metadata, statuses, dates, and eyebrow labels.
    /// Keep this semantic token in the same family as the rest of the app.
    static var agentMetadata: Font {
        if UIFont(name: "InterVariable", size: 11) != nil {
            return .custom("InterVariable", size: 11, relativeTo: .caption).weight(.medium)
        }
        return .system(size: 11, weight: .medium, design: .default)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AgentSpacing.x6)
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.agentBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
                    AgentIconView(.add, size: 10)
                }
                .frame(width: 18, height: 18)

                Text(title)
                    .font(.agentAddAction)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.agentText)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct AgentBlockAddActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: AgentSpacing.x2) {
                    AgentIconView(.add, size: 12)

                    Text(title)
                        .font(.agentSubtext.weight(.medium))
                        .textCase(.uppercase)
                }
                .foregroundStyle(Color.agentSecondary)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .center)
                .padding(.horizontal, AgentSpacing.x3)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct AgentTaskCheckbox: View {
    let isCompleted: Bool
    var color: Color = .agentBorder
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AgentTaskCheckboxMark(isCompleted: isCompleted, color: color)
                .frame(width: 20, height: 44, alignment: .leading)
                // Keep a full-size touch target without making the visible
                // checkbox consume 44 points of horizontal row layout.
                .contentShape(Rectangle().inset(by: -12))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AgentTaskCheckboxMark: View {
    let isCompleted: Bool
    var color: Color = .agentBorder

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(color, lineWidth: 1.25)
            .background(
                isCompleted ? color : Color.clear,
                in: .rect(cornerRadius: 4)
            )
            .overlay {
                if isCompleted {
                    AgentIconView(.check, size: 11)
                        .foregroundStyle(Color.agentCanvas)
                }
            }
            .frame(width: 19, height: 19)
    }
}

struct AgentTaskCheckboxPlaceholder: View {
    var color: Color = .agentBorder

    var body: some View {
        AgentTaskCheckboxMark(isCompleted: false, color: color)
            .frame(width: 20, height: 44, alignment: .leading)
            .accessibilityHidden(true)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentCompactSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 44)
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .capsule)
            .overlay(Capsule().stroke(Color.agentBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgentCyFloatingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentInter(size: 21, weight: .semibold, relativeTo: .title3))
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.onCyAccent)
            .background(Color.cyAccent, in: .circle)
            .shadow(color: Color.agentPureBlack.opacity(0.22), radius: 12, y: 5)
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Color {
    init(agentHex rawValue: String) {
        let oklch = AgentOKLCH(hex: rawValue) ?? AgentColorPalette.focusLight
        self.init(uiColor: oklch.uiColor)
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
            let swatchRect = CGRect(x: 0.75, y: 0.75, width: diameter - 1.5, height: diameter - 1.5)
            context.cgContext.fillEllipse(in: swatchRect)
            UIColor.label.withAlphaComponent(0.38).setStroke()
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: swatchRect)
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
            .font(.agentMetadata)
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
                        .font(.agentMetadata)
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
        ContentDurationLabel.compact(duration)
    }

    private func accessibilityDurationLabel(_ duration: Int) -> String {
        ContentDurationLabel.full(duration)
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
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.bottom, AgentSpacing.x2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
    }
}

struct AgentEmptyState: View {
    let title: String
    let message: String
    var icon: AgentIcon?

    var body: some View {
        VStack(spacing: AgentSpacing.x3) {
            if let icon {
                AgentIconView(icon, size: 22)
                    .foregroundStyle(Color.agentSecondary)
            }

            VStack(spacing: AgentSpacing.x1) {
                Text(title)
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AgentSpacing.x8)
        .accessibilityElement(children: .combine)
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

    private let foreground = Color(uiColor: AgentColorPalette.inkDark.uiColor)
    private let secondary = Color(uiColor: AgentColorPalette.secondaryDark.uiColor)

    private var background: Color {
        Color(uiColor: (colorScheme == .dark ? AgentColorPalette.cyPanel : AgentColorPalette.surfaceDark).uiColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: AgentSpacing.x2) {
                CyAsterisk()
                Text(heading.rawValue.uppercased())
                    .font(.agentMetadata)
                    .tracking(1.4)
                    .foregroundStyle(Color.cyAccent)
                    .accessibilityLabel(heading.rawValue)
                Spacer(minLength: 0)
                if let dismissAction {
                    Button(action: dismissAction) {
                        AgentIconView(.close, size: 13)
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
                        AgentIconView(.arrowRight, size: 13)
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
                        AgentIconView(.arrowRight, size: 12)
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
        .agentSurfaceChrome(
            cornerRadius: 20,
            borderColor: Color.cyAccent.opacity(colorScheme == .dark ? 0.42 : 0.18)
        )
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

/// The primary animated Cy brand mark used on high-level Cy surfaces.
/// Smaller inline references continue to use the static `CyAsterisk`.
struct CyAnimatedLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var color: Color = .cyAccent
    var size: CGFloat = 31
    var strokeWidth: CGFloat = 2.5
    var duration: TimeInterval = 2.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration
            let pulse = 1 - (abs(progress - 0.5) * 2)

            CyAsterisk(color: color, size: size, strokeWidth: strokeWidth)
                .rotationEffect(.degrees(reduceMotion ? 0 : progress * 45))
                .scaleEffect(reduceMotion ? 1 : 0.97 + (pulse * 0.06))
                .shadow(
                    color: color.opacity(reduceMotion ? 0.12 : 0.12 + (pulse * 0.12)),
                    radius: reduceMotion ? 5 : 5 + (pulse * 4)
                )
        }
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
                    .font(.agentMetadata)
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
            Color(uiColor: (colorScheme == .dark ? AgentColorPalette.cyPanel : AgentColorPalette.surfaceDark).uiColor),
            in: .rect(cornerRadius: 20)
        )
        .agentSurfaceChrome(
            cornerRadius: 20,
            borderColor: Color.cyAccent.opacity(colorScheme == .dark ? 0.42 : 0.18)
        )
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
            .agentBottomNavigationClearance()
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard, role: .structural)
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
            .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
    }
}

enum AgentSurfaceRole {
    case structural
    case card
    case floating
}

private struct AgentSurfaceChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let borderColor: Color?
    let role: AgentSurfaceRole

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        borderColor ?? (
                            colorScheme == .dark
                                ? Color.agentPureWhite.opacity(0.08)
                                : Color.agentPureBlack.opacity(0.06)
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowOffset
            )
            .shadow(
                color: secondaryShadowColor,
                radius: secondaryShadowRadius,
                y: secondaryShadowOffset
            )
    }

    private var shadowColor: Color {
        switch role {
        case .structural:
            .clear
        case .card:
            Color.agentPureBlack.opacity(colorScheme == .dark ? 0.12 : 0.045)
        case .floating:
            Color.agentPureBlack.opacity(colorScheme == .dark ? 0.22 : 0.08)
        }
    }

    private var shadowRadius: CGFloat {
        switch role {
        case .structural: 0
        case .card: 12
        case .floating: 24
        }
    }

    private var shadowOffset: CGFloat {
        switch role {
        case .structural: 0
        case .card: 4
        case .floating: 10
        }
    }

    private var secondaryShadowColor: Color {
        switch role {
        case .structural, .card:
            .clear
        case .floating:
            Color.agentPureBlack.opacity(colorScheme == .dark ? 0.10 : 0.04)
        }
    }

    private var secondaryShadowRadius: CGFloat {
        role == .floating ? 6 : 0
    }

    private var secondaryShadowOffset: CGFloat {
        role == .floating ? 2 : 0
    }
}

private struct AgentBottomNavigationClearanceModifier: ViewModifier {
    let additional: CGFloat

    func body(content: Content) -> some View {
        content.padding(.bottom, AgentLayout.bottomNavigationClearance + additional)
    }
}

extension View {
    /// The canonical card treatment used by the guided walkthrough and every
    /// elevated app surface: one neutral hairline plus two ambient shadow layers.
    func agentSurfaceChrome(
        cornerRadius: CGFloat,
        borderColor: Color? = nil,
        role: AgentSurfaceRole = .card
    ) -> some View {
        modifier(
            AgentSurfaceChromeModifier(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                role: role
            )
        )
    }

    func agentBottomNavigationClearance(additional: CGFloat = 0) -> some View {
        modifier(AgentBottomNavigationClearanceModifier(additional: additional))
    }

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
    static func adjustedHex(
        pillarHex: String,
        against backgroundHex: String,
        minimumContrast: Double = 3
    ) -> String {
        guard let pillar = AgentOKLCH(hex: pillarHex),
              let background = AgentOKLCH(hex: backgroundHex) else {
            return "5D6B58"
        }
        guard contrast(pillar, background) < minimumContrast else { return pillar.hexString }

        let shouldDarken = background.lightness > 0.56
        for step in 1 ... 100 {
            let delta = Double(step) / 100
            let candidate = AgentOKLCH(
                lightness: pillar.lightness + (shouldDarken ? -delta : delta),
                chroma: pillar.chroma,
                hue: pillar.hue,
                alpha: pillar.alpha
            )
            if contrast(candidate, background) >= minimumContrast {
                return candidate.hexString
            }
        }
        return shouldDarken
            ? AgentColorPalette.inkLight.hexString
            : AgentColorPalette.inkDark.hexString
    }

    static func foregroundHex(on backgroundHex: String) -> String {
        guard let background = AgentOKLCH(hex: backgroundHex) else {
            return AgentColorPalette.inkLight.hexString
        }
        return contrast(AgentColorPalette.inkLight, background) >= contrast(AgentColorPalette.inkDark, background)
            ? AgentColorPalette.inkLight.hexString
            : AgentColorPalette.inkDark.hexString
    }

    private static func contrast(_ first: AgentOKLCH, _ second: AgentOKLCH) -> Double {
        let firstLuminance = relativeLuminance(first.uiColor)
        let secondLuminance = relativeLuminance(second.uiColor)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }

        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
