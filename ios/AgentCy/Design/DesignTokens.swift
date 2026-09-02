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
    /// Desktop pages begin closer to the title bar because they do not need the
    /// same status-bar breathing room as the iPhone shell.
    static var pageTopPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        AgentSpacing.x4
        #else
        AgentSpacing.x8
        #endif
    }
    /// Standard vertical gap between a section's metadata heading and its primary content.
    static let sectionHeadingSpacing: CGFloat = AgentSpacing.x2
    /// Clears the floating bottom navigation without each screen inventing its own inset.
    static let bottomNavigationClearance: CGFloat = 120
}

/// Shared geometry for the Quick Add launcher and every drill-down it owns.
/// Keeping these values centralized prevents embedded flows from jumping to a
/// different width or inventing a second toolbar treatment.
enum AgentQuickAddLayout {
    static let desktopHeaderHeight: CGFloat = 64
    /// Phone quick-action controls need breathing room below the safe area.
    /// Keep this geometry centralized so new capture flows cannot creep back
    /// toward the status bar.
    static let phoneHeaderHeight: CGFloat = 72
    static let phoneHeaderTopPadding: CGFloat = AgentSpacing.x3
    static var headerHeight: CGFloat {
        #if targetEnvironment(macCatalyst)
        desktopHeaderHeight
        #else
        phoneHeaderHeight
        #endif
    }
    static var headerTopPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        0
        #else
        phoneHeaderTopPadding
        #endif
    }
    static let desktopContentWidth: CGFloat = 620
    static let desktopEditorWidth: CGFloat = 680
}

enum AgentRadius {
    static let structural: CGFloat = 8
    static let control: CGFloat = 8
    static let button: CGFloat = 10
    static let card: CGFloat = 12
    static let panel: CGFloat = 16
    static let floating: CGFloat = 28
    static let dashboard: CGFloat = 20
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
    case external = "agent-icon-external"
    case arrowUp = "agent-icon-arrow-up"
    case arrowRight = "agent-icon-arrow-right"
    case branch = "agent-icon-branch"
    case refresh = "agent-icon-refresh"
    case bell = "agent-icon-bell"
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
    case instagramCamera = "agent-icon-instagram-camera"
    case video = "agent-icon-video"
    case microphone = "agent-icon-microphone"
    case profile = "agent-icon-profile"
    case warning = "agent-icon-warning"
    case info = "agent-icon-info"
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

    /// Nucleo glyphs share an 18-point canvas, but the back chevron occupies
    /// more of that canvas than Close and Ellipsis. Keep every Back control on
    /// the same touch target while matching those icons optically.
    var opticalScale: CGFloat {
        self == .back ? 0.8 : 1
    }

    init(legacySystemName name: String) {
        switch name {
        case "archivebox": self = .archive
        case "asterisk", "sparkles": self = .idea
        case "arrow.down.to.line", "square.and.arrow.down": self = .download
        case "arrow.right": self = .arrowRight
        case "arrow.triangle.2.circlepath": self = .refresh
        case "bell": self = .bell
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
        case "chevron.up.chevron.down": self = .expand
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

enum AgentNavigationIconMetrics {
    /// Matches the Back glyph inside the approved 48-point recording-detail
    /// control. Every custom and native Back indicator uses this rendered size.
    static let backGlyphSide: CGFloat = 12.8
    static let nativeBackCanvasSide: CGFloat = 18
}

@MainActor
enum AgentNavigationAppearance {
    static let backIndicatorAssetName = AgentIcon.back.rawValue

    static func configure() {
#if !targetEnvironment(macCatalyst)
        guard let source = UIImage(named: backIndicatorAssetName) else { return }
        let canvasSide = AgentNavigationIconMetrics.nativeBackCanvasSide
        let glyphSide = AgentNavigationIconMetrics.backGlyphSide
        let origin = (canvasSide - glyphSide) / 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasSide, height: canvasSide))
        let indicator = renderer.image { _ in
            source
                .withTintColor(.black, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: origin, y: origin, width: glyphSide, height: glyphSide))
        }
        .withRenderingMode(.alwaysTemplate)

        let navigationBar = UINavigationBar.appearance()
        navigationBar.backIndicatorImage = indicator
        navigationBar.backIndicatorTransitionMaskImage = indicator
#endif
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
        let renderedSize = icon == .back
            ? AgentNavigationIconMetrics.backGlyphSide
            : size * icon.opticalScale
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: renderedSize, height: renderedSize)
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

extension View {
    /// Applies the toolbar icon control's floating lift only when `active` is
    /// true, instead of always attaching a `.shadow` modifier whose color and
    /// radius collapse to zero (and still costs a render pass) when off.
    @ViewBuilder
    fileprivate func agentToolbarIconShadow(_ active: Bool) -> some View {
        if active {
            self.shadow(color: Color.agentPureBlack.opacity(0.08), radius: 12, y: 4)
        } else {
            self
        }
    }

    /// The single place in the app that writes `glassEffect(…, in: .circle)`.
    /// Routing every glass circle through here keeps the material identical
    /// across the icon controls, the tab bar's active pip, the Quick Add
    /// button, and the recorder — and keeps the eventual `.clear` → `.regular`
    /// move (DEC-01) a one-line change. `scripts/check_design_review.sh`
    /// enforces that no other file writes a circular `glassEffect`.
    func agentGlassCircle(interactive: Bool = true, tint: Color? = nil) -> some View {
        var glass: Glass = interactive ? .clear.interactive() : .clear
        if let tint {
            glass = glass.tint(tint)
        }
        return glassEffect(glass, in: .circle)
    }
}

/// The measurements of the one glass icon control. They live in a token so the
/// geometry can be asserted in a test instead of re-typed per screen.
enum AgentToolbarIconMetrics {
    /// Matches the system back-button footprint and the 44 pt tap floor.
    static let diameter: CGFloat = 44
    /// One glyph size for every icon control: close, back, save, add, refresh.
    static let glyph: CGFloat = 17
    static let strokeOpacity: Double = 0.22
    static let strokeWidth: CGFloat = 0.5
}

struct AgentToolbarIconButton: View {
    let title: String
    let icon: AgentIcon
    var isEnabled = true
    var highlight = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AgentToolbarIconLabel(icon: icon, highlight: highlight)
        }
        // `AgentPressButtonStyle` also supplies the disabled dimming, so the
        // call site never has to repeat an `.opacity` for it.
        .buttonStyle(AgentPressButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

/// The one glass circle. Every icon control that leaves or acts on a screen —
/// close, back, save, add, refresh, spark — is this container, so the diameter,
/// the material, and the `pureWhite@0.22` hairline can never drift between
/// screens. `AgentDesktopDetailBackButton` is its only desktop substitute.
struct AgentToolbarIconContainer<Content: View>: View {
    /// Walkthrough emphasis: paints the shared coach-mark cue under the glass.
    var highlight = false
    /// Lift for a control floating over scrolling content rather than sitting
    /// on a header surface. Off by default — the glass edge already separates
    /// the control from the canvas, and a per-screen shadow is what made these
    /// controls read differently from one page to the next.
    var shadow = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(
                width: AgentToolbarIconMetrics.diameter,
                height: AgentToolbarIconMetrics.diameter
            )
            .background {
                if highlight {
                    AgentWalkthroughControlCue()
                }
            }
            .contentShape(.circle)
            .agentGlassCircle()
            .overlay {
                Circle()
                    .stroke(
                        Color.agentPureWhite.opacity(AgentToolbarIconMetrics.strokeOpacity),
                        lineWidth: AgentToolbarIconMetrics.strokeWidth
                    )
                    .allowsHitTesting(false)
            }
            .agentToolbarIconShadow(shadow)
    }
}

/// Canonical 44-point phone header control. It can also be used as a Menu label
/// without changing geometry.
struct AgentToolbarIconLabel: View {
    let icon: AgentIcon
    var foreground: Color = .agentText
    var highlight = false
    var shadow = false

    var body: some View {
        AgentToolbarIconContainer(highlight: highlight, shadow: shadow) {
            AgentIconView(icon, size: AgentToolbarIconMetrics.glyph)
                .foregroundStyle(highlight ? Color.onCyAccent : foreground)
        }
    }
}

/// The one Save control. Six screens used to hand-roll a bordered-prominent
/// circle button tinted pure white for this, which is a solid accent fill —
/// the contract's "never solid fills" broken byte-for-byte (L1-04). This is
/// the same glass circle every other toolbar icon control uses, with the
/// shared `AgentIcon.check` glyph in ink rather than a filled white puck, so
/// in dark mode it reads like the Close beside it instead of being the
/// brightest object on screen.
struct AgentToolbarSaveButton: View {
    let title: String
    var hint: String = ""
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AgentToolbarIconLabel(icon: .check)
        }
        // `AgentPressButtonStyle` also supplies the disabled dimming, so the
        // call site never has to repeat an `.opacity` for it.
        .buttonStyle(AgentPressButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

extension AgentToolbarSaveButton {
    /// Exposed so a test can assert this control never grows its own
    /// geometry independent of `AgentToolbarIconMetrics`.
    static var diameter: CGFloat { AgentToolbarIconMetrics.diameter }
    static var glyph: CGFloat { AgentToolbarIconMetrics.glyph }
}

/// The walkthrough's coach mark. One cue for every control the guided tour
/// points at — the tab bar, Quick Add, and Quick Add's close button.
struct AgentWalkthroughControlCue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyAccent)  // design-review-allow: accent-mark -- the coach-mark dot

            Circle()
                .stroke(Color.cyAccent.opacity(isExpanded ? 0.10 : 0.42), lineWidth: 2)
                .padding(-5)
                .scaleEffect(isExpanded ? 1.16 : 1)
        }
            // L1-05: the cue used to carry an accent glow. The expanding ring
            // and the scale pulse already draw the eye; design.md bans glow.
            .scaleEffect(reduceMotion ? 1 : (isExpanded ? 1.04 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    isExpanded = true
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct AgentSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? Color.agentText : Color.clear)
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.agentText : Color.agentBorder, lineWidth: 1.25)
            }
            .overlay {
                if isSelected {
                    AgentIconView(.check, size: 9)
                        .foregroundStyle(Color.agentSurface)
                }
            }
            .frame(width: 20, height: 20)
            .frame(width: 28, height: 44)
            .accessibilityHidden(true)
    }
}

/// Shared desktop drill-down chrome. Keeping the navigation rail outside the
/// system toolbar prevents Catalyst from adding a scrolling material shadow,
/// and gives tasks, posts, pillars, and agenda days the same geometry.
struct AgentDesktopDetailRail<Trailing: View>: View {
    let title: String
    let backAction: () -> Void
    private let trailing: Trailing

    init(
        title: String,
        backAction: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.backAction = backAction
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack(spacing: AgentSpacing.x3) {
                AgentDesktopDetailBackButton(action: backAction)

                Spacer(minLength: 0)

                trailing
            }

            Text(title)
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .lineLimit(1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x6)
        .padding(.bottom, AgentSpacing.x4)
        .background(Color.agentCanvas)
    }
}

/// Desktop navigation stays visible without looking like a floating iPhone
/// toolbar control. The label improves wayfinding, while the background only
/// appears when a pointer confirms that the control is interactive.
struct AgentDesktopDetailBackButton: View {
    @State private var isHovered = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x2) {
                AgentIconView(.back, size: 17)
                Text("Back")
                    .font(.agentSubtext.weight(.medium))
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x2)
            .frame(height: 36)
            .background(
                isHovered ? Color.agentSelectionFill : Color.clear,
                in: .rect(cornerRadius: AgentRadius.control)
            )
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
#if targetEnvironment(macCatalyst)
        .onHover { isHovered = $0 }
#endif
        .accessibilityLabel("Back")
    }
}

struct AgentDesktopDetailIconButton: View {
    let title: String
    let icon: AgentIcon
    var foreground: Color = .agentText
    var isEnabled = true
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            AgentDesktopDetailIconLabel(icon: icon, foreground: foreground)
        }
        // `AgentPressButtonStyle` already supplies the disabled dimming (0.42);
        // an extra `.opacity` here compounded to 0.176.
        .buttonStyle(AgentPressButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

struct AgentDesktopDetailIconLabel: View {
    @State private var isHovered = false

    let icon: AgentIcon
    var foreground: Color = .agentText

    var body: some View {
        AgentIconView(icon, size: icon == .back ? 18 : 16)
            .foregroundStyle(foreground)
            .frame(width: 36, height: 36)
            .background(
                isHovered ? Color.agentSelectionFill : Color.clear,
                in: .rect(cornerRadius: AgentRadius.control)
            )
            .frame(width: 44, height: 44)
            .contentShape(.rect)
#if targetEnvironment(macCatalyst)
            .onHover { isHovered = $0 }
#endif
    }
}

extension Color {
    static let agentPureBlack = Color(uiColor: AgentColorPalette.pureBlack.uiColor)
    static let agentPureWhite = Color(uiColor: AgentColorPalette.pureWhite.uiColor)
    /// A stable warm off-white that stays light in both appearances. Reserved
    /// for explicitly light desktop records that need contrast from the canvas.
    static let agentWarmWhite = Color(uiColor: AgentColorPalette.surfaceLight.uiColor)
    static let agentCanvas = adaptive(light: AgentColorPalette.canvasLight, dark: AgentColorPalette.canvasDark)
    static let agentSurface = adaptive(light: AgentColorPalette.surfaceLight, dark: AgentColorPalette.surfaceDark)
    static let agentText = adaptive(light: AgentColorPalette.inkLight, dark: AgentColorPalette.inkDark)
    static let agentSecondary = adaptive(light: AgentColorPalette.secondaryLight, dark: AgentColorPalette.secondaryDark)
    static let agentBorder = adaptive(light: AgentColorPalette.borderLight, dark: AgentColorPalette.borderDark)
    static let agentHairline = adaptive(light: AgentColorPalette.hairlineLight, dark: AgentColorPalette.hairlineDark)
    static let agentSelectionFill = agentText.opacity(0.055)
    static let agentSelectionIndicator = agentSecondary.opacity(0.52)
    static let agentFocusControl = adaptive(light: AgentColorPalette.focusLight, dark: AgentColorPalette.focusDark)
    static let actionAccent = adaptive(light: AgentColorPalette.inkLight, dark: AgentColorPalette.inkDark)
    static let cyAccent = Color(uiColor: AgentColorPalette.cy.uiColor)
    static let cyAccentText = adaptive(light: AgentColorPalette.cy, dark: AgentColorPalette.cyTextDark)
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

/// Shared timing for desktop modals that resize between stages (the creation
/// hub, and Cy moving between chat and the review workspace). `smooth` eases
/// without the spring overshoot `snappy` adds, which reads as a settle at these
/// sizes.
enum AgentModalResize {
    static let animation: Animation = .smooth(duration: 0.34)
}

private struct AgentDesktopWorkspaceModalModifier: ViewModifier {
    var sheet: AppSheet? = nil

    func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        let selfSizing = sheet.map(DesktopLayoutPolicy.sizesItself) ?? false
        let metrics = DesktopLayoutPolicy.workspaceModalMetrics
        content
            .frame(
                width: selfSizing ? nil : metrics.width,
                height: selfSizing ? nil : metrics.height
            )
            .background(Color.agentCanvas.ignoresSafeArea())
            .presentationBackground(Color.agentCanvas)
#else
        content
#endif
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

    static var agentDesktopUtilityTitle: Font {
        agentInter(
            size: DesktopTypographyScale.utilityTitle,
            weight: .semibold,
            relativeTo: .headline
        )
    }

    static var agentDesktopQuickAction: Font {
        agentInter(
            size: DesktopTypographyScale.quickAction,
            weight: .semibold,
            relativeTo: .body
        )
    }

    static var agentDesktopNavigation: Font {
        agentInter(
            size: DesktopTypographyScale.navigation,
            weight: .medium,
            relativeTo: .body
        )
    }

    static var agentDesktopUtilityBody: Font {
        agentInter(
            size: DesktopTypographyScale.utilityBody,
            weight: .regular,
            relativeTo: .body
        )
    }

    static var agentDesktopUtilityBodyEmphasis: Font {
        agentInter(
            size: DesktopTypographyScale.utilityBody,
            weight: .semibold,
            relativeTo: .body
        )
    }

    static var agentDesktopUtilityAction: Font {
        agentInter(
            size: DesktopTypographyScale.utilityAction,
            weight: .semibold,
            relativeTo: .caption
        )
    }

    static var agentDesktopUtilityMetadata: Font {
        agentInter(
            size: DesktopTypographyScale.utilityMetadata,
            weight: .medium,
            relativeTo: .caption
        )
    }
}

enum AgentButtonPressFeedback {
    static func value<Value>(resting: Value, pressed: Value, isPressed: Bool) -> Value {
#if targetEnvironment(macCatalyst)
        resting
#else
        isPressed ? pressed : resting
#endif
    }

    static func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
#if targetEnvironment(macCatalyst)
        1
#else
        isPressed && !reduceMotion ? 0.96 : 1
#endif
    }

    static func animation(reduceMotion: Bool) -> Animation? {
#if targetEnvironment(macCatalyst)
        nil
#else
        reduceMotion ? nil : .easeOut(duration: 0.12)
#endif
    }
}

/// One visual family for every action button in the app: a rounded rect at
/// `AgentRadius.button` with a 1pt border and a flat tinted fill. Roles differ only by fill and
/// text color, never by shape, so buttons with similar purposes read as the
/// same control everywhere. The Cy accent stays reserved for the single color
/// moment on a screen and is never spent on a button fill.
enum AgentActionButtonTheme {
    static let radius = AgentRadius.button

    static let primaryFill = Color.agentText.opacity(0.09)
    static let secondaryFill = Color.agentText.opacity(0.055)
    static let destructiveFill = Color.agentDestructive.opacity(0.10)

    static let border = Color.agentBorder
    static let destructiveBorder = Color.agentDestructive.opacity(0.35)
}

/// The quiet accent action (L1-05). `design.md` reserves the brick accent for
/// one moment per surface and forbids it as a filled block, so the single
/// accent-worthy action on a Cy surface arrives as a *tint*: a `cy @ 12%`
/// ground, a 0.75-pt `cy @ 40%` border, and a brick semibold label on the same
/// `AgentActionButtonTheme.radius` corner the ink buttons use. It is the light
/// `CyCallout` action generalized out of the callout so Start trial, Upgrade to
/// Pro, Three ideas, and the walkthrough's continue button stop hand-rolling a
/// solid brick capsule each. One per surface — every other action stays ink.
enum AgentQuietAccentTheme {
    static let radius = AgentActionButtonTheme.radius
    static let fillOpacity: Double = 0.12
    static let borderOpacity: Double = 0.40
    static let borderWidth: CGFloat = 0.75
    /// design.md's CyCallout action floor, raised to the 44-pt tap target.
    static let minimumHeight: CGFloat = 44

    static var fill: Color { Color.cyAccent.opacity(fillOpacity) }
    static var border: Color { Color.cyAccent.opacity(borderOpacity) }
    /// Brick that still clears 4.5:1 on the dark canvas, not raw `cyAccent`.
    static var label: Color { Color.cyAccentText }
}

/// The two label sizes the accent action comes in, each matching an existing
/// member of the button family so an accent action is never a third height on
/// a screen: `page` is the ink primary's 18-pt/52-pt footprint, `compact` is
/// the CyCallout action's 13-pt/44-pt one for card and row-level actions.
enum AgentQuietAccentButtonSize {
    case page
    case compact

    var font: Font {
        switch self {
        case .page: .agentHeadline
        case .compact: .agentSubtext.weight(.semibold)
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case .page: 52
        case .compact: AgentQuietAccentTheme.minimumHeight
        }
    }
}

/// Accent sibling in the unified action-button family: same shape and border
/// structure as `AgentPrimaryButtonStyle`, brick tint for fill, stroke, and
/// text. Reserved for the one accent-worthy action on a Cy surface.
struct AgentQuietAccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: AgentQuietAccentButtonSize = .compact
    /// Full width by default (the action-button family's shape); the inline
    /// form is for a quiet accent action sharing a row with other controls.
    var isFullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(AgentQuietAccentTheme.label)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(
                maxWidth: isFullWidth ? .infinity : nil,
                minHeight: size.minimumHeight
            )
            .background(
                AgentQuietAccentTheme.fill,
                in: .rect(cornerRadius: AgentQuietAccentTheme.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AgentQuietAccentTheme.radius)
                    .stroke(
                        AgentQuietAccentTheme.border,
                        lineWidth: AgentQuietAccentTheme.borderWidth
                    )
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Circular sibling of the quiet accent action: the Cy composer's send control
/// and Cy's inline "add this" affordance. Same tint, border, and brick glyph —
/// a circle rather than the 10-pt rect only because it sits inside a field or
/// a card row. Inactive falls back to the neutral surface + border so the
/// accent never marks a control the user cannot use.
struct AgentQuietAccentIconLabel: View {
    let icon: AgentIcon
    var isActive = true
    var diameter: CGFloat = AgentToolbarIconMetrics.diameter
    var glyph: CGFloat = 16

    var body: some View {
        AgentIconView(icon, size: glyph)
            .foregroundStyle(isActive ? AgentQuietAccentTheme.label : Color.agentSecondary)
            .frame(width: diameter, height: diameter)
            .background(
                isActive ? AgentQuietAccentTheme.fill : Color.agentSurface,
                in: .circle
            )
            .overlay {
                Circle()
                    .stroke(
                        isActive ? AgentQuietAccentTheme.border : Color.agentBorder,
                        lineWidth: AgentQuietAccentTheme.borderWidth
                    )
            }
    }
}

/// A static accent chip — the quiet accent action's values without the press
/// behaviour, for a label that carries the accent moment on a Cy surface
/// (the Pro price on Access) instead of a tappable action.
struct AgentQuietAccentChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.agentMetadata)
            .foregroundStyle(AgentQuietAccentTheme.label)
            .padding(.horizontal, AgentSpacing.x3)
            .frame(minHeight: 30)
            .background(
                AgentQuietAccentTheme.fill,
                in: .rect(cornerRadius: AgentQuietAccentTheme.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AgentQuietAccentTheme.radius)
                    .stroke(
                        AgentQuietAccentTheme.border,
                        lineWidth: AgentQuietAccentTheme.borderWidth
                    )
            }
    }
}

/// Destructive sibling in the unified action-button family: same shape and
/// border structure, destructive tint for fill, stroke, and text.
struct AgentQuietDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSubtext.weight(.semibold))
            .foregroundStyle(Color.agentDestructive)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                AgentActionButtonTheme.destructiveFill,
                in: .rect(cornerRadius: AgentActionButtonTheme.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.destructiveBorder, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

struct AgentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentHeadline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AgentLayout.pageMargin)
            .foregroundStyle(Color.agentText)
            .background(AgentActionButtonTheme.primaryFill, in: .rect(cornerRadius: AgentActionButtonTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
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
            .foregroundStyle(Color.agentText)
            .background(AgentActionButtonTheme.primaryFill, in: .rect(cornerRadius: AgentActionButtonTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
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
            .background(AgentActionButtonTheme.secondaryFill, in: .rect(cornerRadius: AgentActionButtonTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Shared press feedback for quiet rows, icon buttons, and desktop navigation.
/// It keeps interaction feedback consistent without adding a second visual style.
struct AgentPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled
                ? AgentButtonPressFeedback.value(
                    resting: 1.0,
                    pressed: 0.72,
                    isPressed: configuration.isPressed
                )
                : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Canonical persistent post action on iPhone. Its material and highlight are
/// intentionally identical to the bottom menu bar so Schedule, Mark posted,
/// and Reschedule always read as one system-level action family.
struct AgentPhonePostActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.agentSubtext.weight(.medium))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .capsule)
        .overlay {
            Capsule()
                .stroke(
                    Color.agentPureWhite.opacity(colorScheme == .dark ? 0.14 : 0.45),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        }
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityHint(accessibilityHint)
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
        .buttonStyle(AgentPressButtonStyle())
    }
}

struct AgentBlockAddActionButton: View {
    let title: String
    var background: Color = .agentCanvas
    var foreground: Color = .agentSecondary
    var border: Color = .agentBorder
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
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .center)
                .padding(.horizontal, AgentSpacing.x3)
                .background(background, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(border, lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
    }
}

#if targetEnvironment(macCatalyst)
/// Compact desktop menu row used by custom post action popovers. Native
/// Catalyst menus inflate asset-backed icons, so this keeps their optical
/// weight aligned with the surrounding utility text.
struct AgentDesktopMenuRow: View {
    let title: String
    let icon: AgentIcon
    var isDestructive = false
    var isSelected = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            HStack(spacing: AgentSpacing.x3) {
                AgentIconView(icon, size: 15)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.agentSubtext)

                Spacer(minLength: AgentSpacing.x3)

                if isSelected {
                    AgentIconView(.check, size: 13)
                        .frame(width: 18, height: 18)
                }
            }
            .foregroundStyle(isDestructive ? Color.agentDestructive : Color.agentText)
            .padding(.horizontal, AgentSpacing.x3)
            .frame(minHeight: 40)
            .background(
                isHovered ? Color.agentSelectionFill : Color.clear,
                in: .rect(cornerRadius: AgentRadius.control)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AgentDesktopMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.agentHairline)
            .frame(height: 1)
            .padding(.horizontal, AgentSpacing.x3)
            .padding(.vertical, AgentSpacing.x1)
    }
}
#endif

enum AgentTaskCheckboxAlignment {
    /// Rows align checkboxes with `.firstTextBaseline`. On the phone the
    /// guide rests the box's top edge exactly on the title's cap line. On
    /// desktop the guide centers the box on the title's first line (never on
    /// a title+metadata block), matching the Control Center widget optics.
    static func baselineGuide(
        titlePointSize: CGFloat,
        relativeTo style: UIFont.TextStyle = .body
    ) -> CGFloat {
        let base = UIFont(name: "InterVariable", size: titlePointSize)
            ?? .systemFont(ofSize: titlePointSize)
        let capHeight = UIFontMetrics(forTextStyle: style).scaledFont(for: base).capHeight
        #if targetEnvironment(macCatalyst)
        let markTopInset = (44 - AgentTaskCheckboxMetrics.markSide) / 2
        return markTopInset + AgentTaskCheckboxMetrics.markSide / 2 + capHeight / 2
        #else
        return capHeight
        #endif
    }
}

struct AgentTaskCheckbox: View {
    let isCompleted: Bool
    var color: Color = .agentBorder
    /// Point size of the row title beside this checkbox; drives the cap-line
    /// baseline guide. Rows must use `HStack(alignment: .firstTextBaseline)`.
    var titlePointSize: CGFloat = 15
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AgentTaskCheckboxMark(isCompleted: isCompleted, color: color)
                .frame(width: 20, height: 44, alignment: AgentTaskCheckboxMetrics.markFrameAlignment)
                // Expand only horizontally. Expanding vertically makes the
                // target collide with checkboxes in adjacent 44-point rows.
                .contentShape(AgentHorizontalHitArea(horizontalExpansion: 12))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .alignmentGuide(.firstTextBaseline) { _ in
            AgentTaskCheckboxAlignment.baselineGuide(titlePointSize: titlePointSize)
        }
    }
}

private struct AgentHorizontalHitArea: Shape {
    let horizontalExpansion: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            CGRect(
                x: rect.minX - horizontalExpansion,
                y: rect.minY,
                width: rect.width + (horizontalExpansion * 2),
                height: rect.height
            )
        )
    }
}

enum AgentTaskCheckboxMetrics {
    /// The mark tracks each platform's title scale: desktop titles run
    /// smaller (14pt utility body), so its box shrinks proportionally while
    /// the phone keeps its 19pt mark beside 15pt titles.
    static var markSide: CGFloat {
        #if targetEnvironment(macCatalyst)
        16
        #else
        19
        #endif
    }

    /// Every checkbox row aligns on the first text line: the platform guide
    /// in AgentTaskCheckboxAlignment then chooses cap-top (phone) or
    /// title-line centering (desktop), so metadata lines never pull the box
    /// toward a block center.
    static var rowAlignment: VerticalAlignment { .firstTextBaseline }

    static var markFrameAlignment: Alignment {
        #if targetEnvironment(macCatalyst)
        .leading
        #else
        .topLeading
        #endif
    }
}

struct AgentTaskCheckboxMark: View {
    let isCompleted: Bool
    var color: Color = .agentBorder
    var size: CGFloat = AgentTaskCheckboxMetrics.markSide

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(color, lineWidth: 1.25)
            .background(
                isCompleted ? color : Color.clear,
                in: .rect(cornerRadius: 4)
            )
            .overlay {
                AgentIconView(.check, size: (size * 0.58).rounded())
                    .foregroundStyle(Color.agentCanvas)
                    .opacity(isCompleted ? 1 : 0)
                    .scaleEffect(isCompleted ? 1 : 0.6)
            }
            .frame(width: size, height: size)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isCompleted)
    }
}

struct AgentTaskCheckboxPlaceholder: View {
    var color: Color = .agentBorder
    var titlePointSize: CGFloat = 15

    var body: some View {
        AgentTaskCheckboxMark(isCompleted: false, color: color)
            .frame(width: 20, height: 44, alignment: AgentTaskCheckboxMetrics.markFrameAlignment)
            .accessibilityHidden(true)
            .alignmentGuide(.firstTextBaseline) { _ in
                AgentTaskCheckboxAlignment.baselineGuide(titlePointSize: titlePointSize)
            }
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
            .background(AgentActionButtonTheme.secondaryFill, in: .rect(cornerRadius: AgentActionButtonTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Compact primary action for persistent desktop rails. It keeps the main
/// action visible without turning the bottom of a form into a floating card.
struct AgentDesktopPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSubtext.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .foregroundStyle(Color.agentText)
            .background(AgentActionButtonTheme.primaryFill, in: .rect(cornerRadius: AgentActionButtonTheme.radius))
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled
                ? AgentButtonPressFeedback.value(
                    resting: 1.0,
                    pressed: 0.82,
                    isPressed: configuration.isPressed
                )
                : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

/// Compact actions that sit directly above a desktop paper surface. They keep
/// edit controls discoverable without competing with the content card.
struct AgentDesktopQuietActionButtonStyle: ButtonStyle {
    /// Reads the shared action-button token so this style tracks the same
    /// contract as every other button family instead of drifting back to
    /// `AgentRadius.control`.
    static let radius = AgentActionButtonTheme.radius

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSubtext.weight(.medium))
            .foregroundStyle(isProminent ? Color.onAccent : Color.agentText)
            .padding(.horizontal, AgentSpacing.x3)
            .frame(minHeight: 40)
            .background(
                isProminent
                    ? Color.actionAccent.opacity(AgentButtonPressFeedback.value(
                        resting: 1.0,
                        pressed: 0.82,
                        isPressed: configuration.isPressed
                    ))
                    : Color.agentSelectionFill.opacity(AgentButtonPressFeedback.value(
                        resting: 0.72,
                        pressed: 1.0,
                        isPressed: configuration.isPressed
                    )),
                in: .rect(cornerRadius: Self.radius)
            )
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
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
        let diameter: CGFloat = 10
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { context in
            UIColor(Color(agentHex: colorHex)).setFill()
            let swatchRect = CGRect(x: 0.5, y: 0.5, width: diameter - 1, height: diameter - 1)
            context.cgContext.fillEllipse(in: swatchRect)
            UIColor.label.withAlphaComponent(0.38).setStroke()
            context.cgContext.setLineWidth(0.7)
            context.cgContext.strokeEllipse(in: swatchRect)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

struct EditorialHeader: View {
    let kicker: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            if let kicker, !kicker.isEmpty {
                MetaLabel(kicker)
            }
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
                    .monospacedDigit()
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.bottom, AgentSpacing.x2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
    }
}

/// Pointer feedback for desktop rows: the selection fill appears only when a
/// pointer confirms the row is interactive. Inert on touch platforms, so it is
/// safe on shared views.
struct AgentHoverRowModifier: ViewModifier {
    var cornerRadius: CGFloat = AgentRadius.control
    /// Extends the fill beyond the content bounds. Bare-text rows need this
    /// breathing room — without it the fill starts flush at the first glyph
    /// and reads as a cramped slab. Rows with their own internal padding
    /// keep the default of zero.
    var horizontalBleed: CGFloat = 0

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                // Overlay, not background, so the fill also reads on opaque
                // surfaces like the quick-add card.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Color.agentSelectionFill : Color.clear)
                    .padding(.horizontal, -horizontalBleed)
                    .allowsHitTesting(false)
            }
#if targetEnvironment(macCatalyst)
            .onHover { isHovered = $0 }
#endif
    }
}

extension View {
    /// Canonical spacious footprint for every desktop Quick Action and the
    /// Settings modal, based on the approved Cy post-development sheet.
    func agentDesktopWorkspaceModal(sheet: AppSheet? = nil) -> some View {
        modifier(AgentDesktopWorkspaceModalModifier(sheet: sheet))
    }

    func agentHoverRow(
        cornerRadius: CGFloat = AgentRadius.control,
        bleed: CGFloat = 0
    ) -> some View {
        modifier(AgentHoverRowModifier(cornerRadius: cornerRadius, horizontalBleed: bleed))
    }

    /// Keeps sheet affordances platform-appropriate. A drag handle is useful
    /// on iPhone, but Catalyst animates it separately from a dismissing sheet,
    /// which makes the handle look like a loose bar traveling down the page.
    @ViewBuilder
    func agentSheetDragIndicator() -> some View {
#if targetEnvironment(macCatalyst)
        presentationDragIndicator(.hidden)
#else
        presentationDragIndicator(.visible)
#endif
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

/// The canonical static agent.cy logo mark. Brand headers and system-generated
/// notices use this exact component so a small notice can never drift into a
/// generic star, sparkle, or SF Symbol.
struct AgentCyLogoMark: View {
    var color: Color = .cyAccent
    var size: CGFloat = 16

    var body: some View {
        CyAsterisk(
            color: color,
            size: size,
            strokeWidth: max(1, size * (2 / 23))
        )
    }
}

/// Shared activity treatment for MCP proposals waiting in Cy. Phone and Mac
/// use the same speed and brand geometry so the signal means one thing across
/// both apps. Reduce Motion keeps the mark static while preserving the state.
struct CyPendingReviewLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var color: Color = .cyAccent
    var size: CGFloat = 20
    var strokeWidth: CGFloat = 1.8

    var body: some View {
        CyAsterisk(color: color, size: size, strokeWidth: strokeWidth)
            .rotationEffect(.degrees(reduceMotion ? 0 : (isRotating ? 360 : 0)))
            .animation(
                reduceMotion ? nil : .linear(duration: 1.8).repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear { isRotating = true }
            .accessibilityHidden(true)
    }
}

/// The primary animated Cy brand mark used on high-level Cy surfaces.
/// Smaller inline references continue to use the static `CyAsterisk`.
enum CyAnimatedLogoMotionPolicy {
    static func usesTimeline(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

struct CyAnimatedLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var color: Color = .cyAccent
    var size: CGFloat = 31
    var strokeWidth: CGFloat = 2.5
    var duration: TimeInterval = 2.8

    var body: some View {
        Group {
            if CyAnimatedLogoMotionPolicy.usesTimeline(reduceMotion: reduceMotion) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let progress = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: duration) / duration
                    let pulse = 1 - (abs(progress - 0.5) * 2)

                    animatedMark(progress: progress, pulse: pulse)
                }
            } else {
                CyAsterisk(color: color, size: size, strokeWidth: strokeWidth)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func animatedMark(progress: Double, pulse: Double) -> some View {
            // L1-05: the pulse is carried by rotation and scale alone. The
            // accent glow this mark used to breathe is banned by design.md.
            CyAsterisk(color: color, size: size, strokeWidth: strokeWidth)
                .rotationEffect(.degrees(progress * 45))
                .scaleEffect(0.97 + (pulse * 0.06))
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
                    .foregroundStyle(Color.cyAccentText)
                    .accessibilityLabel(heading.rawValue)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.agentText)
        .padding(AgentSpacing.x6)
        .background(
            Color(uiColor: (colorScheme == .dark ? AgentColorPalette.cyPanel : AgentColorPalette.surfaceDark).uiColor),
            in: .rect(cornerRadius: AgentRadius.dashboard)
        )
        .agentSurfaceChrome(
            cornerRadius: AgentRadius.dashboard,
            borderColor: Color.cyAccent.opacity(colorScheme == .dark ? 0.42 : 0.18)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
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

enum AgentScrollableSurfacePolicy {
    static func minimumHeight(
        viewportHeight: CGFloat,
        headerHeight: CGFloat,
        mobileAdjustment: CGFloat = 0
    ) -> CGFloat? {
        #if targetEnvironment(macCatalyst)
        nil
        #else
        max(0, viewportHeight - headerHeight + mobileAdjustment)
        #endif
    }

    static func bottomPadding(mobile: CGFloat) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        AgentSpacing.x8
        #else
        mobile
        #endif
    }
}

struct AgentViewHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AgentInsetSurface<Content: View>: View {
    let role: AgentSurfaceRole
    @ViewBuilder let content: Content

    init(
        role: AgentSurfaceRole = .card,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AgentLayout.pageMargin)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: role)
    }
}

enum AgentSurfaceRole {
    case structural
    case card
    case floating
    case walkthrough
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
        case .walkthrough:
            Color.agentPureBlack.opacity(colorScheme == .dark ? 0.34 : 0.14)
        }
    }

    private var shadowRadius: CGFloat {
        switch role {
        case .structural: 0
        case .card: 12
        case .floating: 24
        case .walkthrough: 28
        }
    }

    private var shadowOffset: CGFloat {
        switch role {
        case .structural: 0
        case .card: 4
        case .floating: 10
        case .walkthrough: 12
        }
    }

    private var secondaryShadowColor: Color {
        switch role {
        case .structural, .card:
            .clear
        case .floating:
            Color.agentPureBlack.opacity(colorScheme == .dark ? 0.10 : 0.04)
        case .walkthrough:
            Color.agentPureBlack.opacity(colorScheme == .dark ? 0.16 : 0.06)
        }
    }

    private var secondaryShadowRadius: CGFloat {
        switch role {
        case .floating: 6
        case .walkthrough: 8
        case .structural, .card: 0
        }
    }

    private var secondaryShadowOffset: CGFloat {
        switch role {
        case .floating: 2
        case .walkthrough: 3
        case .structural, .card: 0
        }
    }
}

private struct AgentBottomNavigationClearanceModifier: ViewModifier {
    let additional: CGFloat

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.padding(.bottom, AgentSpacing.x8 + additional)
        #else
        content.padding(.bottom, AgentLayout.bottomNavigationClearance + additional)
        #endif
    }
}

private struct AgentQuickAddHeaderSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: AgentQuickAddLayout.headerHeight)
            .padding(.top, AgentQuickAddLayout.headerTopPadding)
            .background(Color.agentCanvas)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.agentHairline)
                    .frame(height: 1)
            }
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

    /// Flat, stable Quick Add header chrome. Catalyst material headers can
    /// create separate update layers while child views swap, producing the
    /// traveling shadows and repeated layout work seen in crash reports.
    func agentQuickAddHeaderSurface() -> some View {
        modifier(AgentQuickAddHeaderSurfaceModifier())
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
                Button {
                    onDone()
                    AgentKeyboard.dismiss()
                } label: {
                    Text("Done")
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(.rect)
                }
                .buttonStyle(AgentPressButtonStyle())
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
            return AgentColorPalette.pillarFallbackHex
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
