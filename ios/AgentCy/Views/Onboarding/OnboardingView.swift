import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct OnboardingView: View {
    private enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case name
        case vibe
        case pillars
        case platforms
        case ai
        case notifications
        case ready

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .welcome: "Welcome"
            case .name: "About you"
            case .vibe: "Your vibe"
            case .pillars: "Your content"
            case .platforms: "Where you post"
            case .ai: "Your AI"
            case .notifications: "Notifications"
            case .ready: "Ready"
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let previewOnly: Bool
    @State private var step: Step = .welcome
    @State private var draft: OnboardingDraft
    @State private var transitionEdge: Edge = .trailing
    @State private var pillarEditorDraft: OnboardingPillarDraft?
    @State private var chooseMCPFolder = false
    @State private var bridgeStatus: MCPBridgeConnectionStatus?
    @State private var localCyStatus: LocalCyRuntimeStatus?
    @State private var bridgeNotice: String?
    @State private var copiedCommand: String?
    @State private var showsBridgeSetupDetails = false

    init(previewOnly: Bool = false, initialDraft: OnboardingDraft = OnboardingDraft()) {
        self.previewOnly = previewOnly
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                stepContent
                    .id(step)
                    .transition(stepTransition)
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, step == .welcome ? AgentSpacing.x8 : AgentSpacing.x12)
                    .padding(.bottom, AgentSpacing.x12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigationControls
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x2)
                .padding(.bottom, AgentSpacing.x4)
                .background(Color.agentCanvas)
        }
        .sheet(item: $pillarEditorDraft) { editingDraft in
            OnboardingPillarEditor(
                pillar: editingDraft,
                role: pillarRole(for: editingDraft.id),
                canDelete: draft.pillars.contains(where: { $0.id == editingDraft.id }),
                paletteHexes: draft.vibePalette?.pillarColorHexes ?? CreatorVibePalette.fallbackPillarColorHexes,
                onSave: savePillar,
                onDelete: { deletePillar(id: editingDraft.id) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $chooseMCPFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let folder = try result.get().first else { return }
                try MCPBridgePreferences.connect(to: folder)
                try? MCPBridgeService.sync(context: context)
                refreshBridgeStatus()
            } catch {
                bridgeNotice = CreatorFacingErrorMapper.presentation(
                    for: error,
                    action: "The Claude & Codex connection"
                ).message
            }
        }
        .alert("agent.cy", isPresented: Binding(
            get: { bridgeNotice != nil },
            set: { if !$0 { bridgeNotice = nil } }
        )) {
            Button("Close", role: .cancel) { bridgeNotice = nil }
        } message: {
            Text(bridgeNotice ?? "")
        }
        .agentScreen()
        .preferredColorScheme(draft.appearance?.colorSchemeOverride)
        .agentKeyboardDismissal()
        .onChange(of: draft.appearance, initial: true) { _, appearance in
            AgentAppearanceController.apply(appearance ?? .system)
        }
        .onDisappear {
            if previewOnly {
                AgentAppearanceController.apply(appModel.appearancePreference)
            }
        }
        .task { await appModel.refreshReminderSchedule(context: context) }
        .task(id: step) {
            guard step == .ai else { return }
            while !Task.isCancelled, step == .ai {
                refreshBridgeStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(spacing: 6) {
                ForEach(Step.allCases) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.agentText : Color.agentHairline)
                        .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
                }
            }
            HStack(alignment: .center) {
                Text(step.label.uppercased())
                    .font(.paperMetadata(size: 11, weight: .medium, relativeTo: .caption))
                    .tracking(1.1)
                Spacer()
                Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                    .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(Color.agentSecondary)
                if previewOnly {
                    Button {
                        dismiss()
                    } label: {
                        AgentIconView(.close, size: 12)
                            .frame(width: 32, height: 32)
                            .background(Color.agentSurface, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close onboarding preview")
                }
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .name:
            nameStep
        case .vibe:
            vibeStep
        case .pillars:
            pillarsStep
        case .platforms:
            platformsStep
        case .ai:
            aiStep
        case .notifications:
            notificationsStep
        case .ready:
            readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: AgentSpacing.x6) {
                CyAsterisk(size: 56, strokeWidth: 4)
                VStack(spacing: AgentSpacing.x3) {
                    Text("From idea to ready.")
                        .font(.paperInter(size: 36, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-0.8)
                        .multilineTextAlignment(.center)
                    Text("A clear place to save ideas, plan your week, and create the work.")
                        .font(.paperInter(size: 18, weight: .regular, relativeTo: .body))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(maxWidth: 310)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                PaperOnboardingFeature(title: "Capture the idea", detail: "Save it before it disappears.")
                PaperOnboardingFeature(title: "Shape the post", detail: "Turn a rough thought into something usable.")
                PaperOnboardingFeature(title: "Plan the work", detail: "Keep posts and tasks in one plan.")
                PaperOnboardingFeature(title: "Bring your own AI", detail: "Power up your workflow with Claude or Codex.")
            }
            .padding(.top, AgentSpacing.x12)

            VStack(spacing: 0) {
                PaperConsentRow(
                    title: "I am 18 or older",
                    detail: "agent.cy is made for adult creators.",
                    isOn: $draft.adultConfirmed
                )
                PaperConsentRow(
                    title: "Share app diagnostics",
                    detail: "Optional. Your ideas and writing are never included.",
                    isOn: $draft.telemetryConsent
                )
            }
            .padding(.top, AgentSpacing.x8)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x12) {
            PaperOnboardingPrompt(
                title: "What should Cy call you?",
                subtitle: "This is how Cy will greet you."
            )

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                PaperFieldLabel("Your name")
                TextField("Name", text: $draft.name)
                    .font(.paperInter(size: 22, weight: .regular, relativeTo: .title3))
                    .textContentType(.name)
                    .agentSingleLineSubmit()
                    .padding(.horizontal, AgentSpacing.x6)
                    .frame(minHeight: 64)
                    .background(Color.agentSurface, in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.agentText.opacity(0.08), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                PaperFieldLabel("What are you working toward?")
                TextField("", text: $draft.goal, axis: .vertical)
                    .font(.paperInter(size: 17, weight: .regular, relativeTo: .body))
                    .lineLimit(2...4)
                    .padding(AgentSpacing.x4)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .background(Color.agentSurface, in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.agentText.opacity(0.08), lineWidth: 1)
                    }
                Text("Cy uses this goal to keep suggestions relevant.")
                    .font(.paperInter(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
            }
        }
    }

    private var vibeStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            PaperOnboardingPrompt(
                title: "What’s your vibe?",
                subtitle: "Choose one starting palette and the appearance that feels right."
            )

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                PaperFieldLabel("Pillar colors")
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AgentSpacing.x3),
                        GridItem(.flexible(), spacing: AgentSpacing.x3)
                    ],
                    spacing: AgentSpacing.x3
                ) {
                    ForEach(CreatorVibePalette.onboardingPalettes) { palette in
                        vibePaletteButton(palette)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                PaperFieldLabel("Appearance")
                HStack(spacing: AgentSpacing.x3) {
                    vibeAppearanceButton(.system)
                    vibeAppearanceButton(.light)
                    vibeAppearanceButton(.dark)
                }
            }

            Text("This is only a starting point. You can change your palette and appearance later in Settings.")
                .font(.paperInter(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func vibePaletteButton(_ palette: CreatorVibePalette) -> some View {
        let isSelected = draft.vibePalette == palette
        return Button {
            selectVibePalette(palette)
        } label: {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x2) {
                    Text(palette.title)
                        .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
                    Spacer(minLength: 0)
                    if isSelected {
                        AgentIconView(.check, size: 12)
                    }
                }

                HStack(spacing: 5) {
                    ForEach(Array(palette.pillarColorHexes.enumerated()), id: \.offset) { _, colorHex in
                        Circle()
                            .fill(Color(agentHex: colorHex))
                            .frame(width: 15, height: 15)
                            .overlay {
                                Circle().stroke(Color.agentText.opacity(0.10), lineWidth: 0.5)
                            }
                    }
                }

                Text(palette.detail)
                    .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)
            }
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
            .agentSurfaceChrome(
                cornerRadius: 16,
                borderColor: isSelected ? Color.agentText : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(palette.title), \(palette.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func vibeAppearanceButton(_ appearance: AppearancePreference) -> some View {
        let isSelected = draft.appearance == appearance
        return Button {
            draft.appearance = appearance
        } label: {
            VStack(spacing: AgentSpacing.x2) {
                vibeAppearanceSwatch(appearance)
                Text(appearance.title)
                    .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isSelected {
                    AgentIconView(.check, size: 11)
                        .frame(height: 12)
                } else {
                    Color.clear.frame(height: 12)
                }
            }
            .padding(.horizontal, AgentSpacing.x2)
            .padding(.vertical, AgentSpacing.x3)
            .frame(maxWidth: .infinity, minHeight: 102)
            .background(Color.agentSurface, in: .rect(cornerRadius: 14))
            .agentSurfaceChrome(
                cornerRadius: 14,
                borderColor: isSelected ? Color.agentText : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func vibeAppearanceSwatch(_ appearance: AppearancePreference) -> some View {
        Group {
            switch appearance {
            case .system:
                LinearGradient(
                    colors: [
                        Color(uiColor: AgentColorPalette.surfaceLight.uiColor),
                        Color(uiColor: AgentColorPalette.surfaceDark.uiColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .light:
                Color(uiColor: AgentColorPalette.surfaceLight.uiColor)
            case .dark:
                Color(uiColor: AgentColorPalette.surfaceDark.uiColor)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    Color(
                        uiColor: appearance == .dark
                            ? AgentOKLCH(lightness: 0.470, chroma: 0).uiColor
                            : AgentColorPalette.borderLight.uiColor
                    ),
                    lineWidth: 1
                )
        }
    }

    private var pillarsStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            PaperOnboardingPrompt(
                title: "What brings your content together?",
                subtitle: "Start with the anchor pillar everything leads back to. Add supporting pillars now or later."
            )

            VStack(spacing: AgentSpacing.x3) {
                ForEach(Array(draft.pillars.enumerated()), id: \.element.id) { index, pillar in
                    Button {
                        pillarEditorDraft = pillar
                    } label: {
                        HStack(spacing: AgentSpacing.x4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(agentHex: pillar.colorHex))
                                .frame(width: 7, height: 38)
                            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                Text(pillar.name)
                                    .font(.paperInter(size: 18, weight: .semibold, relativeTo: .headline))
                                Text(index == 0 ? "Anchor pillar" : weekdaySummary(pillar.assignedWeekdays))
                                    .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
                                    .tracking(0.8)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            Spacer()
                            AgentIconView(.forward, size: 14)
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                        .agentSurfaceChrome(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }

                if draft.pillars.count < 4 {
                    Button {
                        pillarEditorDraft = OnboardingPillarDraft(colorHex: nextPillarColorHex)
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            AgentIconView(.add)
                            Text(draft.pillars.isEmpty ? "Add your anchor pillar" : "Add a branch")
                            Spacer()
                        }
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.agentText.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("\(draft.pillars.count) of 4")
                Spacer()
                Text(draft.pillars.isEmpty ? "Optional" : "You can edit these later")
            }
            .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Color.agentSecondary)
        }
    }

    private var platformsStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            PaperOnboardingPrompt(
                title: "Where do you post?",
                subtitle: "Choose your platforms and formats. Add a handle only if you want it saved as a private reference."
            )

            VStack(spacing: AgentSpacing.x3) {
                PaperPlatformCard(
                    title: "Instagram",
                    detail: "Reels",
                    symbol: "camera.aperture",
                    selected: draft.platforms.contains(.instagramReels),
                    handle: handleBinding(for: .instagram),
                    onToggle: { toggle(.instagramReels) }
                )
                PaperPlatformCard(
                    title: "TikTok",
                    detail: "Short-form video",
                    symbol: "music.note",
                    selected: draft.platforms.contains(.tiktok),
                    handle: handleBinding(for: .tiktok),
                    onToggle: { toggle(.tiktok) }
                )
                PaperYouTubeCard(
                    selectedFormats: $draft.platforms,
                    handle: handleBinding(for: .youtube)
                )
            }

            Text("Nothing is connected, fetched, or posted automatically.")
                .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.agentSecondary)
        }
    }

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            PaperOnboardingPrompt(
                title: "How should Cy work with you?",
                subtitle: "Use Agent Cy in the app, or power up your workflow with your Claude or Codex account through a private local bridge."
            )

            VStack(spacing: AgentSpacing.x3) {
                aiProviderCard(
                    provider: .agentCy,
                    title: "Agent Cy AI",
                    detail: "Start in the app. No computer setup or API key required.",
                    badge: "Easiest"
                ) {
                    CyAsterisk(size: 21, strokeWidth: 2)
                }

                aiProviderCard(
                    provider: .claudeOrCodex,
                    title: "Claude or Codex",
                    detail: "Use your own CLI subscription on a Mac or Windows computer.",
                    badge: "MCP"
                ) {
                    AgentIconView(.terminal, size: 18)
                }
            }

            if draft.aiProvider == .agentCy {
                AgentInsetSurface {
                    HStack(alignment: .top, spacing: AgentSpacing.x3) {
                        Circle()
                            .fill(Color.agentSuccess)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                            Text("Ready to use")
                                .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                            Text("Cy uses agent.cy’s included AI access. You can connect Claude or Codex later in Settings.")
                                .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                                .foregroundStyle(Color.agentSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                bridgeSetup
            }
        }
    }

    private func aiProviderCard<Icon: View>(
        provider: OnboardingAIProvider,
        title: String,
        detail: String,
        badge: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let selected = draft.aiProvider == provider
        return Button {
            draft.aiProvider = provider
        } label: {
            HStack(alignment: .center, spacing: AgentSpacing.x4) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.cyAccent.opacity(0.10) : Color.agentCanvas)
                        .frame(width: 46, height: 46)
                    icon()
                }
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    HStack(spacing: AgentSpacing.x2) {
                        Text(title)
                            .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        Text(badge.uppercased())
                            .font(.paperMetadata(size: 9, weight: .medium, relativeTo: .caption))
                            .tracking(0.7)
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Text(detail)
                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AgentSpacing.x2)
                AgentIconView(selected ? .checkCircle : .radioEmpty)
                    .font(.agentInter(size: 20, weight: .medium, relativeTo: .body))
                    .foregroundStyle(selected ? Color.cyAccent : Color.agentSecondary)
            }
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
            .agentSurfaceChrome(
                cornerRadius: 16,
                borderColor: selected ? Color.cyAccent : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bridgeSetup: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            bridgeStatusCard

            VStack(spacing: AgentSpacing.x3) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                        showsBridgeSetupDetails.toggle()
                    }
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        Text(showsBridgeSetupDetails ? "Hide setup" : "Set up now")
                        Spacer()
                        AgentIconView(showsBridgeSetupDetails ? .collapse : .expand, size: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperOnboardingOutlineButtonStyle())

                if !showsBridgeSetupDetails {
                    Button("Finish later") {
                        moveForward()
                    }
                    .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                }
            }

            if showsBridgeSetupDetails {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                PaperFieldLabel("Set up on your computer")
                onboardingInstruction(number: "1", text: "Download the agent.cy bridge on your Mac or Windows computer. Keep iCloud Drive signed in with the same Apple Account as this iPhone.")

                Link(destination: URL(string: "https://github.com/cheycoulbourn/agent.cy/releases/latest")!) {
                    HStack(spacing: AgentSpacing.x3) {
                        AgentIconView(.download, size: 16)
                            .frame(width: 24, height: 40)
                            .foregroundStyle(Color.agentText)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download bridge")
                                .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
                            Text("MAC & WINDOWS")
                                .font(.paperMetadata(size: 10, weight: .medium, relativeTo: .caption))
                                .tracking(0.9)
                                .foregroundStyle(Color.agentSecondary)
                        }

                        Spacer(minLength: AgentSpacing.x2)

                        AgentIconView(.external, size: 14)
                            .foregroundStyle(Color.agentSecondary)
                    }
                    .foregroundStyle(Color.agentText)
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(Color.agentSurface, in: .rect(cornerRadius: 16))
                    .agentSurfaceChrome(cornerRadius: 16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download the agent.cy bridge for Mac or Windows")
                .accessibilityHint("Opens the latest installer download page")

                onboardingInstruction(number: "2", text: "Open Terminal or PowerShell in the downloaded folder and run the command for your computer.")
                OnboardingCommandBlock(
                    label: "Mac",
                    command: "./agentcy-setup",
                    copied: copiedCommand == "./agentcy-setup",
                    onCopy: copyCommand
                )
                OnboardingCommandBlock(
                    label: "Windows",
                    command: ".\\agentcy-setup.exe",
                    copied: copiedCommand == ".\\agentcy-setup.exe",
                    onCopy: copyCommand
                )

                onboardingInstruction(number: "3", text: "Confirm that the installer registered agentcy with the CLI you use.")
                OnboardingCommandBlock(
                    label: "Claude Code",
                    command: "claude mcp get agentcy",
                    copied: copiedCommand == "claude mcp get agentcy",
                    onCopy: copyCommand
                )
                OnboardingCommandBlock(
                    label: "Codex",
                    command: "codex mcp get agentcy",
                    copied: copiedCommand == "codex mcp get agentcy",
                    onCopy: copyCommand
                )

                onboardingInstruction(number: "4", text: "In Claude or Codex, paste this request. It creates the live heartbeat the iPhone can detect.")
                OnboardingCommandBlock(
                    label: "Ask your AI",
                    command: "Call bridge_status for agent.cy.",
                    copied: copiedCommand == "Call bridge_status for agent.cy.",
                    onCopy: copyCommand
                )

                onboardingInstruction(number: "5", text: "Choose the same agent.cy MCP folder from iCloud Drive on this iPhone, then check the connection.")

                Button {
                    chooseMCPFolder = true
                } label: {
                    AgentIconLabel(
                        title: MCPBridgePreferences.isConnected ? "Choose a different folder" : "Choose MCP folder",
                        icon: .folder
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperOnboardingOutlineButtonStyle())

                Button {
                    checkBridgeConnection()
                } label: {
                    AgentIconLabel(title: "Check connection", icon: .refresh)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperOnboardingPrimaryButtonStyle())
                }
            }

            Text("Your Claude or Codex credentials stay on your computer. agent.cy only sees the shared workspace and review proposals. You can finish this setup later in Settings.")
                .font(.paperInter(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bridgeStatusCard: some View {
        let recentlyConnected = bridgeStatus?.isRecentlyConnected == true || localCyStatus?.isRecentlyAvailable == true
        let hasFolder = MCPBridgePreferences.isConnected
        let title: String = {
            if recentlyConnected { return "Connected" }
            if bridgeStatus != nil { return "Bridge found" }
            if hasFolder { return "Folder connected" }
            return "Not connected yet"
        }()
        let detail: String = {
            if let bridgeStatus, recentlyConnected {
                return "\(bridgeStatus.clientSummary) checked in \(bridgeStatus.updatedAt.formatted(.relative(presentation: .named)))."
            }
            if let localCyStatus, localCyStatus.isRecentlyAvailable {
                return "Claude is available on your computer."
            }
            if let bridgeStatus {
                return "\(bridgeStatus.clientSummary) was last verified \(bridgeStatus.updatedAt.formatted(date: .abbreviated, time: .shortened))."
            }
            if hasFolder {
                return "The iCloud folder is ready. Run bridge_status from Claude or Codex to finish verification."
            }
            return "Complete the computer steps, then choose the shared iCloud Drive folder."
        }()

        return AgentInsetSurface {
            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                Circle()
                    .fill(recentlyConnected ? Color.agentSuccess : Color.agentSecondary)
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title)
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                    Text(detail)
                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func onboardingInstruction(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            Text(number)
                .font(.paperMetadata(size: 11, weight: .medium, relativeTo: .caption))
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            PaperOnboardingPrompt(
                title: "Want a calm heads-up?",
                subtitle: "Start with a daily overview and one Monday planning note. Rest days stay quiet."
            )

            VStack(spacing: 0) {
                onboardingReminderRow(
                    title: "Daily overview",
                    detail: "Your focus and next commitment on active days.",
                    isOn: $draft.dailyReminderEnabled,
                    time: onboardingTimeBinding(hour: \.dailyReminderHour, minute: \.dailyReminderMinute)
                )
                Rectangle().fill(Color.agentHairline).frame(height: 1)
                onboardingReminderRow(
                    title: "Monday planning",
                    detail: "Your week, saved ideas, and what is already planned.",
                    isOn: $draft.weeklyReminderEnabled,
                    time: onboardingTimeBinding(hour: \.weeklyReminderHour, minute: \.weeklyReminderMinute)
                )
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
            .agentSurfaceChrome(cornerRadius: 16)

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                PaperFieldLabel("Preview")
                Text("A new week is here")
                    .font(.paperInter(size: 18, weight: .semibold, relativeTo: .headline))
                Text("Start with Planning. You have four saved ideas.")
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
            }
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
            .agentSurfaceChrome(cornerRadius: 16)

            Text("Notifications are scheduled locally on this iPhone. You can change every category later in Settings.")
                .font(.paperInter(size: 13, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.agentSecondary)
        }
    }

    private func onboardingReminderRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        time: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title)
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                    Text(detail)
                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(Color.agentSecondary)
                }
            }
            .tint(.actionAccent)

            if isOn.wrappedValue {
                HStack {
                    PaperFieldLabel("Time")
                    Spacer()
                    DatePicker(title, selection: time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
        .padding(.vertical, AgentSpacing.x4)
    }

    private func onboardingTimeBinding(
        hour: WritableKeyPath<OnboardingDraft, Int>,
        minute: WritableKeyPath<OnboardingDraft, Int>
    ) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: draft[keyPath: hour],
                    minute: draft[keyPath: minute],
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { value in
                draft[keyPath: hour] = Calendar.current.component(.hour, from: value)
                draft[keyPath: minute] = Calendar.current.component(.minute, from: value)
            }
        )
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x12) {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                CyAsterisk(size: 64, strokeWidth: 4.5)
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    Text("You’re ready, \(displayName).")
                        .font(.paperInter(size: 36, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-0.8)
                    Text("Let’s take a quick look at how ideas become scheduled posts.")
                        .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            VStack(spacing: 0) {
                PaperReadyRow(label: "Vibe", value: vibeReadySummary)
                PaperReadyRow(label: "Pillars", value: pillarReadySummary)
                PaperReadyRow(label: "Platforms", value: platformReadySummary)
                PaperReadyRow(label: "AI", value: aiReadySummary, statusColor: aiReadyStatusColor)
                PaperReadyRow(label: "Notifications", value: notificationReadySummary, showsDivider: false)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
            .agentSurfaceChrome(cornerRadius: 16)

            AgentInsetSurface {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    PaperFieldLabel("Up next")
                    Text("See your Dashboard, open Quick Add, plan your week, organize pillars, and shape work with Cy.")
                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
    }

    private var navigationControls: some View {
        VStack(spacing: AgentSpacing.x2) {
            if step == .ready {
                Button {
                    finish(startWalkthrough: true)
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        if appModel.isWorking {
                            ProgressView().tint(Color.onAccent)
                        }
                        Text("Show me around")
                        AgentIconView(.forward, size: 16)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PaperOnboardingPrimaryButtonStyle())
                .disabled(appModel.isWorking)

                Button("Go to dashboard") {
                    finish(startWalkthrough: false)
                }
                .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.agentSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .disabled(appModel.isWorking)
            } else {
            HStack(spacing: AgentSpacing.x3) {
                if step != .welcome {
                    Button {
                        moveBack()
                    } label: {
                        AgentIconView(.back, size: 17)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(PaperOnboardingSecondaryButtonStyle())
                    .accessibilityLabel("Back")
                }

                Button {
                    performPrimaryAction()
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        if appModel.isWorking && step == .ready {
                            ProgressView().tint(Color.onAccent)
                        }
                        Text(primaryButtonTitle)
                        if step == .ready {
                            CyAsterisk(color: .onAccent, size: 17, strokeWidth: 1.8)
                        }
                    }
                }
                .buttonStyle(PaperOnboardingPrimaryButtonStyle())
                .disabled(!isStepValid || appModel.isWorking)
            }

            }

            if skipIsAvailable {
                Button("Skip for now") {
                    if step == .vibe {
                        draft.vibePalette = nil
                        draft.appearance = nil
                    } else if step == .notifications {
                        draft.dailyReminderEnabled = false
                        draft.weeklyReminderEnabled = false
                    }
                    moveForward()
                }
                    .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(minHeight: 32)
            }
        }
    }

    private var stepTransition: AnyTransition {
        let insertion = AnyTransition.move(edge: transitionEdge)
        let removal = AnyTransition.move(edge: transitionEdge == .trailing ? .leading : .trailing)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: "Get started"
        case .ai where draft.aiProvider == .claudeOrCodex && bridgeStatus?.isRecentlyConnected == true:
            "Use Claude & Codex"
        case .ai: "Continue"
        case .notifications: appModel.notificationAuthorization.canSchedule ? "Continue" : "Turn on notifications"
        case .ready: "Show me around"
        default: "Continue"
        }
    }

    private var skipIsAvailable: Bool {
        step == .vibe ||
            (step == .pillars && draft.pillars.isEmpty) ||
            (step == .platforms && draft.platforms.isEmpty) ||
            step == .notifications
    }

    private var isStepValid: Bool {
        switch step {
        case .welcome:
            draft.adultConfirmed
        case .name:
            !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vibe:
            draft.vibePalette != nil && draft.appearance != nil
        case .ready:
            true
        case .pillars, .platforms, .ai, .notifications:
            true
        }
    }

    private var displayName: String {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "creator" : trimmed
    }

    private var vibeReadySummary: String {
        guard let palette = draft.vibePalette, let appearance = draft.appearance else { return "Choose later" }
        return "\(palette.title) · \(appearance.title)"
    }

    private var pillarReadySummary: String {
        guard !draft.pillars.isEmpty else { return "Add later" }
        return draft.pillars.count == 1 ? "1 anchor" : "1 anchor + \(draft.pillars.count - 1)"
    }

    private var platformReadySummary: String {
        let destinations = selectedDestinationKinds
        guard !destinations.isEmpty else { return "Add later" }
        return destinations.count == 1 ? destinations[0].title : "\(destinations.count) selected"
    }

    private var notificationReadySummary: String {
        let count = [draft.dailyReminderEnabled, draft.weeklyReminderEnabled].filter { $0 }.count
        return count == 0 ? "Off" : "\(count) selected"
    }

    private var aiReadySummary: String {
        switch draft.aiProvider {
        case .agentCy:
            "Connected"
        case .claudeOrCodex:
            aiConnectionIsVerified ? "Connected" : "Finish setup later"
        }
    }

    private var aiReadyStatusColor: Color {
        switch draft.aiProvider {
        case .agentCy:
            Color.agentSuccess
        case .claudeOrCodex:
            aiConnectionIsVerified ? Color.agentSuccess : Color.agentSecondary
        }
    }

    private var aiConnectionIsVerified: Bool {
        bridgeStatus?.isRecentlyConnected == true || localCyStatus?.isRecentlyAvailable == true
    }

    private func performPrimaryAction() {
        if step == .ready {
            finish(startWalkthrough: true)
            return
        }
        guard step == .notifications, !previewOnly, !appModel.notificationAuthorization.canSchedule else {
            moveForward()
            return
        }
        Task {
            _ = await appModel.requestNotificationPermission(context: context)
            moveForward()
        }
    }

    private var selectedDestinationKinds: [BuiltInDestinationKind] {
        BuiltInDestinationKind.allCases.filter { kind in
            switch kind {
            case .instagram: draft.platforms.contains(.instagramReels)
            case .tiktok: draft.platforms.contains(.tiktok)
            case .youtube: draft.platforms.contains(.youtubeShorts) || draft.platforms.contains(.youtubeVideo)
            }
        }
    }

    private func moveForward() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        transitionEdge = .trailing
        setStep(next)
    }

    private func moveBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        transitionEdge = .leading
        setStep(previous)
    }

    private func setStep(_ value: Step) {
        if reduceMotion {
            step = value
        } else {
            withAnimation(.easeInOut(duration: 0.24)) { step = value }
        }
    }

    private func finish(startWalkthrough: Bool) {
        if previewOnly {
            if startWalkthrough {
                appModel.startWalkthrough()
            } else {
                appModel.selectedTab = .home
            }
            dismiss()
            return
        }
        Task {
            let completed = await appModel.completeOnboarding(draft, context: context)
            guard completed else { return }
            if startWalkthrough {
                appModel.startWalkthrough()
            } else {
                appModel.selectedTab = .home
            }
        }
    }

    private func savePillar(_ pillar: OnboardingPillarDraft) {
        if let index = draft.pillars.firstIndex(where: { $0.id == pillar.id }) {
            draft.pillars[index] = pillar
        } else if draft.pillars.count < 4 {
            draft.pillars.append(pillar)
        }
        pillarEditorDraft = nil
    }

    private var nextPillarColorHex: String {
        guard let colors = draft.vibePalette?.pillarColorHexes, !colors.isEmpty else { return "55705B" }
        return colors[draft.pillars.count % colors.count]
    }

    private func selectVibePalette(_ palette: CreatorVibePalette) {
        draft.vibePalette = palette
        let colors = palette.pillarColorHexes
        for index in draft.pillars.indices {
            draft.pillars[index].colorHex = colors[index % colors.count]
        }
    }

    private func deletePillar(id: UUID) {
        draft.pillars.removeAll { $0.id == id }
        pillarEditorDraft = nil
    }

    private func pillarRole(for id: UUID) -> PillarRole {
        guard let index = draft.pillars.firstIndex(where: { $0.id == id }) else {
            return draft.pillars.isEmpty ? .anchor : .supporting
        }
        return index == 0 ? .anchor : .supporting
    }

    private func toggle(_ platform: CreatorPlatform) {
        if draft.platforms.contains(platform) {
            draft.platforms.remove(platform)
        } else {
            draft.platforms.insert(platform)
        }
    }

    private func handleBinding(for destination: BuiltInDestinationKind) -> Binding<String> {
        Binding(
            get: { draft.accountHandles[destination, default: ""] },
            set: { draft.accountHandles[destination] = $0 }
        )
    }

    private func copyCommand(_ command: String) {
        UIPasteboard.general.string = command
        copiedCommand = command
    }

    private func refreshBridgeStatus() {
        bridgeStatus = try? MCPBridgeService.connectionStatus()
        Task {
            localCyStatus = try? await LocalCyAIClient.shared.runtimeStatus()
        }
    }

    private func checkBridgeConnection() {
        guard MCPBridgePreferences.isConnected else {
            chooseMCPFolder = true
            return
        }
        try? MCPBridgeService.sync(context: context)
        refreshBridgeStatus()
        if bridgeStatus?.isRecentlyConnected == true || localCyStatus?.isRecentlyAvailable == true {
            bridgeNotice = "Claude or Codex is connected."
        } else {
            bridgeNotice = "The shared folder is connected. On your computer, ask Claude or Codex to call bridge_status, then check again."
        }
    }
}

private struct OnboardingCommandBlock: View {
    let label: String
    let command: String
    let copied: Bool
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack {
                Text(label.uppercased())
                    .font(.paperMetadata(size: 9, weight: .medium, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(Color.agentSecondary)
                Spacer()
                Button {
                    onCopy(command)
                } label: {
                    AgentIconLabel(title: copied ? "Copied" : "Copy", icon: copied ? .check : .copy)
                        .font(.paperInter(size: 12, weight: .semibold, relativeTo: .caption))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 32)
            }

            Text(command)
                .font(.paperMetadata(size: 13, weight: .regular, relativeTo: .body))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x3)
        .background(Color.agentText.opacity(0.045), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.agentText.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct PaperOnboardingPrompt: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            Text(title)
                .font(.paperInter(size: 32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PaperFieldLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.paperMetadata(size: 10, weight: .medium, relativeTo: .caption))
            .tracking(1.1)
    }
}

private struct PaperOnboardingFeature: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x4) {
            CyAsterisk(size: 15, strokeWidth: 1.6)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(Color.agentSecondary)
            }
            Spacer()
        }
        .padding(.vertical, AgentSpacing.x3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(0.1)).frame(height: 1)
        }
    }
}

private struct PaperConsentRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                AgentIconView(isOn ? .checkboxSelected : .checkboxEmpty)
                    .font(.agentInter(size: 20, relativeTo: .body))
                    .foregroundStyle(isOn ? Color.agentText : Color.agentSecondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                    Text(detail)
                        .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.agentSecondary)
                }
                Spacer()
            }
            .padding(.vertical, AgentSpacing.x3)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

private struct PaperOnboardingActionRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: AgentSpacing.x4) {
            AgentIconView(AgentIcon(legacySystemName: symbol))
                .font(.agentInter(size: 19, relativeTo: .body))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(title)
                    .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(.paperInter(size: 13, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(2)
            }
            Spacer()
            AgentIconView(.forward, size: 14)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
        .agentSurfaceChrome(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.agentText.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PaperPlatformCard: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    @Binding var handle: String
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: AgentSpacing.x4) {
                    AgentIconView(AgentIcon(legacySystemName: symbol))
                        .font(.agentInter(size: 18, relativeTo: .body))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        Text(detail)
                            .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Spacer()
                    AgentIconView(selected ? .checkCircle : .radioEmpty)
                        .font(.agentInter(size: 20, relativeTo: .body))
                }
                .contentShape(.rect)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 68)
            }
            .buttonStyle(.plain)

            if selected {
                Rectangle().fill(Color.agentText.opacity(0.1)).frame(height: 1)
                    .padding(.horizontal, AgentSpacing.x4)
                TextField("@handle · optional", text: $handle)
                    .font(.paperInter(size: 14, weight: .regular, relativeTo: .body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .agentSingleLineSubmit()
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 52)
            }
        }
        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
        .agentSurfaceChrome(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Color.agentText : Color.agentText.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PaperYouTubeCard: View {
    @Binding var selectedFormats: Set<CreatorPlatform>
    @Binding var handle: String

    private var selected: Bool {
        selectedFormats.contains(.youtubeShorts) || selectedFormats.contains(.youtubeVideo)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if selected {
                    selectedFormats.remove(.youtubeShorts)
                    selectedFormats.remove(.youtubeVideo)
                } else {
                    selectedFormats.insert(.youtubeShorts)
                }
            } label: {
                HStack(spacing: AgentSpacing.x4) {
                    AgentIconView(.play, size: 18)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube")
                            .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        Text("Shorts and long-form video")
                            .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Spacer()
                    AgentIconView(selected ? .checkCircle : .radioEmpty)
                        .font(.agentInter(size: 20, relativeTo: .body))
                }
                .contentShape(.rect)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 68)
            }
            .buttonStyle(.plain)

            if selected {
                Rectangle().fill(Color.agentText.opacity(0.1)).frame(height: 1)
                    .padding(.horizontal, AgentSpacing.x4)
                HStack(spacing: AgentSpacing.x2) {
                    formatButton("Shorts", platform: .youtubeShorts)
                    formatButton("Long-form", platform: .youtubeVideo)
                }
                .padding(.horizontal, AgentSpacing.x4)
                .padding(.vertical, AgentSpacing.x3)
                TextField("@handle · optional", text: $handle)
                    .font(.paperInter(size: 14, weight: .regular, relativeTo: .body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .agentSingleLineSubmit()
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 48)
            }
        }
        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
        .agentSurfaceChrome(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Color.agentText : Color.agentText.opacity(0.08), lineWidth: 1)
        }
    }

    private func formatButton(_ title: String, platform: CreatorPlatform) -> some View {
        let isSelected = selectedFormats.contains(platform)
        return Button {
            if isSelected {
                selectedFormats.remove(platform)
            } else {
                selectedFormats.insert(platform)
            }
        } label: {
            Text(title)
                .font(.paperInter(size: 13, weight: .semibold, relativeTo: .subheadline))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isSelected ? Color.onAccent : Color.agentText)
                .background(isSelected ? Color.actionAccent : Color.agentCanvas, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

private struct PaperReadyRow: View {
    let label: String
    let value: String
    var statusColor: Color? = nil
    var showsDivider = true

    var body: some View {
        HStack {
            Text(label)
                .font(.paperMetadata(size: 10, weight: .medium, relativeTo: .caption))
                .tracking(0.9)
                .textCase(.uppercase)
            Spacer()
            HStack(spacing: AgentSpacing.x2) {
                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.agentText.opacity(0.1))
                    .frame(height: 1)
            }
        }
    }
}

private struct OnboardingPillarEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OnboardingPillarDraft
    let role: PillarRole
    let canDelete: Bool
    let paletteHexes: [String]
    let onSave: (OnboardingPillarDraft) -> Void
    let onDelete: () -> Void

    init(
        pillar: OnboardingPillarDraft,
        role: PillarRole,
        canDelete: Bool,
        paletteHexes: [String],
        onSave: @escaping (OnboardingPillarDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: pillar)
        self.role = role
        self.canDelete = canDelete
        self.paletteHexes = paletteHexes
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        PaperFieldLabel(role == .anchor ? "Anchor pillar" : "Branch")
                        TextField("Pillar name", text: $draft.name)
                            .font(.paperInter(size: 22, weight: .regular, relativeTo: .title3))
                            .agentSingleLineSubmit()
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 64)
                            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        PaperFieldLabel("Color")
                        OnboardingColorChooser(colors: paletteHexes, selectedHex: $draft.colorHex)
                    }

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        HStack {
                            PaperFieldLabel("Preferred days")
                            Spacer()
                            Text("\(draft.assignedWeekdays.count) of 7")
                                .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
                                .foregroundStyle(Color.agentSecondary)
                        }
                        OnboardingWeekdayChooser(
                            selection: $draft.assignedWeekdays,
                            accentHex: draft.colorHex
                        )
                    }

                    if canDelete {
                        Button("Delete pillar", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .font(.paperInter(size: 15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.agentDestructive)
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .padding(AgentLayout.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(role == .anchor ? "Anchor pillar" : "Branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    AgentToolbarIconButton(
                        title: "Save",
                        icon: .check,
                        isEnabled: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        onSave(draft)
                        dismiss()
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .agentScreen()
            .agentKeyboardDismissal()
        }
    }
}

private struct OnboardingColorChooser: View {
    let colors: [String]
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: AgentSpacing.x2) {
            ForEach(colors, id: \.self) { hex in
                Button { selectedHex = hex } label: {
                    Circle()
                        .fill(Color(agentHex: hex))
                        .frame(width: 32, height: 32)
                        .padding(AgentSpacing.x1)
                        .overlay {
                            Circle().stroke(Color.agentBorder, lineWidth: 0.75)
                        }
                        .overlay {
                            Circle().stroke(selectedHex.caseInsensitiveCompare(hex) == .orderedSame ? Color.agentText : Color.clear, lineWidth: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pillar color")
                .accessibilityValue(selectedHex.caseInsensitiveCompare(hex) == .orderedSame ? "Selected" : "Not selected")
            }
            ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(agentHex: selectedHex) },
            set: { selectedHex = $0.onboardingHexString }
        )
    }
}

private struct OnboardingWeekdayChooser: View {
    @Binding var selection: Set<PillarWeekday>
    let accentHex: String

    var body: some View {
        let foregroundHex = AgentChipContrast.foregroundHex(on: accentHex)
        HStack(spacing: AgentSpacing.x2) {
            ForEach(PillarWeekday.mondayFirst) { day in
                Button {
                    if selection.contains(day) {
                        selection.remove(day)
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    Text(day.letter)
                        .font(.paperMetadata(size: 11, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(selection.contains(day) ? Color(agentHex: foregroundHex) : Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection.contains(day) ? Color(agentHex: accentHex) : Color.agentSurface, in: .circle)
                        .overlay {
                            Circle().stroke(selection.contains(day) ? Color.clear : Color.agentBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.title)
                .accessibilityValue(selection.contains(day) ? "Selected" : "Not selected")
            }
        }
    }
}

private struct PaperOnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color.onAccent)
            .background(Color.actionAccent, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.36)
    }
}

private struct PaperOnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .circle)
            .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct PaperOnboardingOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, AgentSpacing.x4)
            .foregroundStyle(Color.agentText)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

private extension Color {
    var onboardingHexString: String {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "55705B" }
        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

private func weekdaySummary(_ days: Set<PillarWeekday>) -> String {
    let values = PillarWeekday.mondayFirst.filter(days.contains).map(\.shortTitle)
    return values.isEmpty ? "No preferred days" : values.joined(separator: " · ")
}
