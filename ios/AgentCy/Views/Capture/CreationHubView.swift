import SwiftUI

struct CreationHubView: View {
    private let onDismiss: (() -> Void)?
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuickCapture = false
    @State private var showLivePost = false
    @State private var showVoiceSpark = false

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        Group {
            if showLivePost {
                AddLivePostView(onDismiss: returnToCreationHub)
            } else if showQuickCapture {
                QuickCaptureView(onExit: returnToCreationHub)
            } else {
                creationHubContent
            }
        }
        .background(Color.agentCanvas.ignoresSafeArea())
        #if targetEnvironment(macCatalyst)
        .preference(
            key: DesktopCreationHubStagePreferenceKey.self,
            value: showLivePost || showQuickCapture ? .capture : .menu
        )
        #else
            .presentationBackground(Color.agentCanvas)
            .presentationDetents([.large])
            .sheet(isPresented: $showVoiceSpark) {
                VoiceSparkView()
                    .environment(appModel)
            }
        #endif
    }

    private var creationHubContent: some View {
        NavigationStack {
            Group {
                #if targetEnvironment(macCatalyst)
                desktopContent
                #else
                mobileContent
                #endif
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .agentDashboardScreen()
        }
        .background(Color.agentCanvas.ignoresSafeArea())
    }

    private var mobileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                mobileHeader
                createActions
                phoneActions
                cyAction
                if appModel.walkthroughStep == .quickAdd {
                    quickAddWalkthroughCard
                }
            }
            .padding(.horizontal, AgentLayout.dashboardGutter)
            .padding(.bottom, AgentSpacing.x16)
        }
    }

    #if targetEnvironment(macCatalyst)
    private var desktopContent: some View {
        // One compact card, one voice: the editorial heading carries the
        // header role and the close control sits on its cap line, so the
        // content column and chrome share a single left edge.
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                HStack(alignment: .top, spacing: AgentSpacing.x4) {
                    desktopHeading
                    Spacer(minLength: AgentSpacing.x4)
                    AgentToolbarIconButton(title: "Close", icon: .close, action: closeCreationHub)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Closes Quick Add")
                }

                desktopCreateActions
                desktopCyAction

                if appModel.walkthroughStep == .quickAdd {
                    quickAddWalkthroughCard
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x6)
        }
        .scrollIndicators(.hidden)
        .background(Color.agentCanvas)
    }

    private var desktopHeading: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            Text("What are you making?")
                .font(.agentDisplay)
                .tracking(-0.56)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose a starting point. You can change the details later.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var desktopCreateActions: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Create")

            VStack(spacing: 0) {
                DesktopQuickActionRow(
                    icon: .idea,
                    title: "Idea",
                    detail: "Capture a thought before it disappears.",
                    showsDivider: true
                ) { openCapture(.idea) }

                DesktopQuickActionRow(
                    icon: .calendar,
                    title: "Post",
                    detail: "Plan the platform, format, and publishing date.",
                    showsDivider: true
                ) { openCapture(.post) }

                DesktopQuickActionRow(
                    icon: .tasks,
                    title: "Task",
                    detail: "Add one clear next step.",
                    showsDivider: true
                ) { openCapture(.task) }

                DesktopQuickActionRow(
                    icon: .link,
                    title: "Live post",
                    detail: "Track a published post by link.",
                    showsDivider: false
                ) { openCapture(.livePost) }
            }
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .clipShape(.rect(cornerRadius: AgentRadius.panel))
            .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: .structural)
        }
    }

    private var desktopCyAction: some View {
        Button { openCapture(.cyIdeas) } label: {
            HStack(spacing: AgentSpacing.x4) {
                CyAsterisk(color: .cyAccent, size: 24, strokeWidth: 2)
                    .frame(width: 44, height: 44)
                    .background(Color.cyAccent.opacity(0.09), in: .circle)

                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    HStack(spacing: AgentSpacing.x2) {
                        Text("Find three ideas")
                            .font(.agentHeadline)
                        Text("WITH CY")
                            .font(.agentMetadata)
                            .tracking(0.7)
                            .foregroundStyle(Color.cyAccentText)
                    }
                    Text("Get directions grounded in your pillars and saved work.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: AgentSpacing.x3)

                AgentIconView(.arrowRight, size: 13)
                    .foregroundStyle(Color.cyAccentText)
                    .frame(width: 40, height: 40)
            }
            .foregroundStyle(Color.agentText)
            .padding(.leading, AgentSpacing.x4)
            .padding(.trailing, AgentSpacing.x3)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(Color.cyAccent.opacity(0.055), in: .rect(cornerRadius: AgentRadius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.panel)
                    .stroke(Color.cyAccent.opacity(0.18), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: AgentRadius.panel))
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint("Creates three personalized ideas")
    }
    #endif

    private var mobileHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            ZStack {
                HStack {
                    AgentToolbarIconButton(
                        title: "Close",
                        icon: .close,
                        highlight: appModel.walkthroughStep == .quickAdd,
                        action: closeCreationHub
                    )
                    .accessibilityHint(
                        appModel.walkthroughStep == .quickAdd
                            ? "Closes Quick Add and continues the guided tour"
                            : "Closes Quick Add"
                    )
                    Spacer()
                }

                MetaLabel("Quick actions")
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text("Let’s make something.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                Text("Start small. You can shape it later.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.horizontal, AgentLayout.dashboardGutter)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x2)
    }

    private enum Destination { case idea, post, task, livePost, cyIdeas }

    private func openCapture(_ destination: Destination) {
        appModel.quickCaptureTargetDate = nil
        appModel.quickCapturePillarID = nil
        switch destination {
        case .idea: appModel.setQuickCaptureMode(.idea)
        case .post: appModel.setQuickCaptureMode(.post)
        case .task: appModel.setQuickCaptureMode(.task)
        case .livePost:
            setLivePostVisible(true)
            return
        case .cyIdeas: appModel.setQuickCaptureMode(.cyIdeas)
        }
        setQuickCaptureVisible(true)
    }

    private func returnToCreationHub() {
        setQuickCaptureVisible(false)
        setLivePostVisible(false)
    }

    private func setLivePostVisible(_ isVisible: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showLivePost = isVisible
        }
    }

    private func setQuickCaptureVisible(_ isVisible: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showQuickCapture = isVisible
        }
    }

    private func closeCreationHub() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var createActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetaLabel("Create")
                .padding(.horizontal, AgentSpacing.x5)
                .padding(.top, AgentSpacing.x5)
                .padding(.bottom, AgentSpacing.x2)

            quickActionRow(
                title: "Idea",
                detail: "Save a thought to shape later.",
                showsDivider: true
            ) { openCapture(.idea) }

            quickActionRow(
                title: "Post",
                detail: "Choose the platform, format, and date.",
                showsDivider: true
            ) { openCapture(.post) }

            quickActionRow(
                title: "Task",
                detail: "Add one clear next step.",
                showsDivider: true
            ) { openCapture(.task) }

            quickActionRow(
                title: "Live post",
                detail: "Track a published post by link.",
                showsDivider: false
            ) { openCapture(.livePost) }
        }
        .padding(.bottom, AgentSpacing.x2)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
    }

    private var phoneActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetaLabel("Create on iPhone")
                .padding(.horizontal, AgentSpacing.x5)
                .padding(.top, AgentSpacing.x5)
                .padding(.bottom, AgentSpacing.x2)

            quickActionRow(
                title: "Voice Spark",
                detail: "Record a thought and save the editable transcript.",
                showsDivider: false
            ) {
                showVoiceSpark = true
            }
        }
        .padding(.bottom, AgentSpacing.x2)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
    }

    private var quickAddWalkthroughCard: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x2) {
                AgentIconView(.add, size: 15)
                    .foregroundStyle(Color.cyAccentText)
                Text("QUICK ADD")
                    .font(.agentMetadata)
                    .tracking(0.8)
                    .foregroundStyle(Color.cyAccentText)
            }

            Text("Start with what you have.")
                .font(.agentHeadline)

            Text("Save a thought as an Idea, shape something ready to publish as a Post, or capture the next step as a Task. Cy can suggest three directions when you want help getting started.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                closeCreationHub()
            } label: {
                HStack(spacing: AgentSpacing.x2) {
                    Text("Close and continue")
                    Spacer()
                    AgentIconView(.close, size: 13)
                }
            }
            .buttonStyle(AgentQuietAccentButtonStyle())
            .accessibilityHint("Returns to the app and continues the guided tour")
        }
        .padding(AgentSpacing.x5)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(
            cornerRadius: AgentRadius.panel,
            borderColor: colorScheme == .dark
                ? Color.agentPureWhite.opacity(0.16)
                : Color.agentPureBlack.opacity(0.10),
            role: .walkthrough
        )
    }

    private var cyAction: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("With Cy")
                .foregroundStyle(Color.cyAccentText)
                .padding(.leading, AgentLayout.dashboardGutter)

            Button { openCapture(.cyIdeas) } label: {
                HStack(spacing: AgentSpacing.x4) {
                    CyAsterisk(color: .cyAccent, size: 22, strokeWidth: 1.7)
                        .frame(width: 26, height: 26)

                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("Find three ideas")
                            .font(.agentHeadline)
                        Text("Grounded in your pillars and saved work.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: AgentSpacing.x2)

                    AgentIconView(.arrowRight, size: 13)
                        .foregroundStyle(Color.cyAccentText)
                        .frame(width: 32, height: 32)
                }
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x5)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(Color.cyAccent.opacity(0.055), in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.cyAccent.opacity(0.2), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: AgentRadius.control))
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityHint("Creates three personalized ideas")
        }
    }

    private func quickActionRow(
        title: String,
        detail: String,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title).font(.agentHeadline)
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: AgentSpacing.x2)

                AgentToolbarIconLabel(icon: .add)
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x5)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)
                        .padding(.leading, AgentSpacing.x5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint(detail)
    }
}

#if targetEnvironment(macCatalyst)
private struct DesktopQuickActionRow: View {
    let icon: AgentIcon
    let title: String
    let detail: String
    let showsDivider: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x4) {
                AgentIconView(icon, size: 18)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 40, height: 40)
                    .background(
                        Color.agentCanvas,
                        in: .rect(cornerRadius: AgentRadius.control)
                    )

                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title)
                        .font(.agentHeadline)
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AgentSpacing.x3)

                AgentIconView(.arrowRight, size: 12)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 40, height: 40)
            }
            .foregroundStyle(Color.agentText)
            .padding(.leading, AgentSpacing.x4)
            .padding(.trailing, AgentSpacing.x3)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(isHovered ? Color.agentSelectionFill : Color.clear)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)
                        .padding(.leading, 72)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .onHover { isHovered = $0 }
        .accessibilityHint(detail)
    }
}

/// Lets the shell size the Quick Add card to the stage the hub is showing —
/// compact for the menu, the canonical workspace footprint for capture.
struct DesktopCreationHubStagePreferenceKey: PreferenceKey {
    static let defaultValue: DesktopCreationHubStage = .menu

    static func reduce(value: inout DesktopCreationHubStage, nextValue: () -> DesktopCreationHubStage) {
        value = nextValue()
    }
}
#endif
