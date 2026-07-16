import SwiftData
import SwiftUI

@MainActor
struct OnboardingView: View {
    private enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case name
        case vibe
        case pillars
        case platforms
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
        .preferredColorScheme(draft.appearance?.colorSchemeOverride)
        .agentScreen()
        .agentKeyboardDismissal()
        .task { await appModel.refreshReminderSchedule(context: context) }
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
                    .font(.paperMono(size: 11, weight: .medium, relativeTo: .caption))
                    .tracking(1.1)
                Spacer()
                Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                    .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(Color.agentSecondary)
                if previewOnly {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
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
                subtitle: "Choose a starting palette for your pillars and the app appearance you prefer."
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
                    ForEach(CreatorVibePalette.standardPalettes) { palette in
                        vibePaletteButton(palette)
                    }
                }

                PaperFieldLabel("Signature")
                    .padding(.top, AgentSpacing.x2)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AgentSpacing.x3),
                        GridItem(.flexible(), spacing: AgentSpacing.x3)
                    ],
                    spacing: AgentSpacing.x3
                ) {
                    ForEach(CreatorVibePalette.signaturePalettes) { palette in
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

            Text("This is only a starting point. You can choose custom pillar colors and change your appearance later.")
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
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
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.agentText : Color.agentText.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
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
            HStack(spacing: AgentSpacing.x3) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(appearance == .dark ? Color(agentHex: "141414") : Color(agentHex: "FDFDFB"))
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(appearance == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.12), lineWidth: 1)
                    }
                Text(appearance.title)
                    .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.agentSurface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.agentText : Color.agentText.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                                    .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
                                    .tracking(0.8)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.agentText.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if draft.pillars.count < 4 {
                    Button {
                        pillarEditorDraft = OnboardingPillarDraft(colorHex: nextPillarColorHex)
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            Image(systemName: "plus")
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
            .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
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
                .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.agentSecondary)
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
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.agentText.opacity(0.08), lineWidth: 1)
            }

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
                    Text("Your workspace is ready. You can change any of this later.")
                        .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            VStack(spacing: 0) {
                PaperReadyRow(label: "Vibe", value: vibeReadySummary)
                PaperReadyRow(label: "Pillars", value: pillarReadySummary)
                PaperReadyRow(label: "Platforms", value: platformReadySummary)
                PaperReadyRow(label: "Notifications", value: notificationReadySummary)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: 16))

        }
    }

    private var navigationControls: some View {
        VStack(spacing: AgentSpacing.x2) {
            HStack(spacing: AgentSpacing.x3) {
                if step != .welcome {
                    Button {
                        moveBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
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
        let insertion = AnyTransition.move(edge: transitionEdge).combined(with: .opacity)
        let removal = AnyTransition.move(edge: transitionEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: "Get started"
        case .notifications: appModel.notificationAuthorization.canSchedule ? "Continue" : "Turn on notifications"
        case .ready: previewOnly ? "Close preview" : "Start with Cy"
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
        case .pillars, .platforms, .notifications:
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

    private func performPrimaryAction() {
        if step == .ready {
            finish()
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

    private func finish() {
        if previewOnly {
            dismiss()
            return
        }
        Task {
            _ = await appModel.completeOnboarding(draft, context: context)
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
            .font(.paperMono(size: 10, weight: .medium, relativeTo: .caption))
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
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .regular))
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
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
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
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
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
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        Text(detail)
                            .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
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
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube")
                            .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        Text("Shorts and long-form video")
                            .font(.paperInter(size: 12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
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

    var body: some View {
        HStack {
            Text(label)
                .font(.paperMono(size: 10, weight: .medium, relativeTo: .caption))
                .tracking(0.9)
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .font(.paperInter(size: 14, weight: .semibold, relativeTo: .subheadline))
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(label == "Platforms" ? 0 : 0.1)).frame(height: 1)
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
                                .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
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
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        onSave(draft)
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                        .font(.paperMono(size: 11, weight: .medium, relativeTo: .caption))
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
