import SwiftData
import SwiftUI

@MainActor
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case profile
        case mode
        case invite
        case examples
        case voice
        case reminders
        case firstSpark

        var kicker: String {
            switch self {
            case .welcome: "Welcome"
            case .profile: "About you"
            case .mode: "Cy’s role"
            case .invite: "Pilot access"
            case .examples: "Your voice"
            case .voice: "Voice profile"
            case .reminders: "Reminders"
            case .firstSpark: "First idea"
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var draft = OnboardingDraft()
    @State private var recorder = OnDeviceSpeechCapture()
    @State private var dictatingExampleID: UUID?
    @State private var speechTask: Task<Void, Never>?
    @State private var inviteCode = ""
    @State private var didDeferVoiceExamples = false

    private var steps: [Step] {
        Step.allCases.filter {
            (appModel.requiresInstallationInvite || $0 != .invite) &&
                (!didDeferVoiceExamples || $0 != .voice)
        }
    }

    private var stepIndex: Int {
        steps.firstIndex(of: step) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MetaLabel("Step \(stepIndex + 1) / \(steps.count)")
                Spacer()
                ProgressView(value: Double(stepIndex + 1), total: Double(steps.count))
                    .frame(width: 96)
                    .tint(.actionAccent)
                    .accessibilityLabel("Onboarding progress")
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x4)

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    stepContent
                }
                .padding(.horizontal, AgentSpacing.x6)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, AgentSpacing.x16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            navigationControls
                .padding(.horizontal, AgentSpacing.x6)
                .padding(.vertical, AgentSpacing.x3)
                .background(Color.agentCanvas)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        }
        .agentScreen()
        .task { await appModel.refreshInstallationCredentialStatus() }
        .onChange(of: recorder.state) { _, newState in
            if !newState.isActive { dictatingExampleID = nil }
        }
        .onDisappear {
            speechTask?.cancel()
            Task { await recorder.stop() }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            EditorialHeader(
                kicker: step.kicker,
                title: "Make your next video.",
                subtitle: "Turn an idea into a clear script and plan."
            )
            VStack(spacing: AgentSpacing.x4) {
                Toggle(isOn: $draft.adultConfirmed) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("I’m 18 or older").font(.agentHeadline)
                        Text("This app is for adult creators.").font(.agentBody).foregroundStyle(Color.agentSecondary)
                    }
                }
                .tint(.actionAccent)
                Toggle(isOn: $draft.telemetryConsent) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("Share content-free diagnostics").font(.agentHeadline)
                        Text("Optional. Never includes your content.").font(.agentBody).foregroundStyle(Color.agentSecondary)
                    }
                }
                .tint(.actionAccent)
            }
            CyCallout {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Your privacy")
                    Text("Your work stays on your devices and private iCloud. Cy receives only the text needed for a request. Audio and screenshots are never uploaded.")
                        .font(.agentBody)
                }
            }

        case .profile:
            EditorialHeader(kicker: step.kicker, title: "Tell us about your content.", subtitle: "This helps Cy make relevant suggestions.")
            VStack(spacing: AgentSpacing.x4) {
                AgentLabeledField(label: "Name", placeholder: "What should Cy call you?", text: $draft.name)
                AgentLabeledField(label: "Goal", placeholder: "e.g. Teach practical design skills", text: $draft.goal, axis: .vertical)
            }
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                SectionRuleHeader(title: "Platforms")
                ForEach(CreatorPlatform.allCases) { platform in
                    Button {
                        if draft.platforms.contains(platform), draft.platforms.count > 1 {
                            draft.platforms.remove(platform)
                        } else {
                            draft.platforms.insert(platform)
                        }
                    } label: {
                        EditorialRow {
                            HStack {
                                Image(systemName: platform.symbol).frame(width: 32)
                                Text(platform.title).font(.agentBody)
                                Spacer()
                                Image(systemName: draft.platforms.contains(platform) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(draft.platforms.contains(platform) ? Color.actionAccent : Color.agentSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(draft.platforms.contains(platform) ? "Selected" : "Not selected")
                }
            }

        case .mode:
            EditorialHeader(kicker: step.kicker, title: "How should Cy help?", subtitle: "Change this anytime. You approve every change.")
            VStack(spacing: AgentSpacing.x3) {
                ForEach(AssistanceMode.allCases) { mode in
                    Button {
                        draft.assistanceMode = mode
                    } label: {
                        HStack(alignment: .top, spacing: AgentSpacing.x4) {
                            Image(systemName: draft.assistanceMode == mode ? "record.circle.fill" : "circle")
                                .foregroundStyle(draft.assistanceMode == mode ? Color.cyAccent : Color.agentSecondary)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                Text(mode.title).font(.agentHeadline)
                                Text(mode.detail).font(.agentBody).foregroundStyle(Color.agentSecondary)
                            }
                            Spacer()
                        }
                        .padding(AgentSpacing.x4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.agentSurface)
                        .clipShape(.rect(cornerRadius: AgentRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(draft.assistanceMode == mode ? Color.cyAccent : Color.agentBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

        case .invite:
            EditorialHeader(
                kicker: step.kicker,
                title: "Enter your invite.",
                subtitle: "Your one-use code unlocks Cy on this iPhone."
            )
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                AgentLabeledField(label: "Invitation code", placeholder: "Enter your pilot code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    Task { await appModel.redeemInstallationInvite(inviteCode) }
                } label: {
                    Label(
                        appModel.hasInstallationCredential ? "Connected" : "Use invite",
                        systemImage: appModel.hasInstallationCredential ? "checkmark.circle.fill" : "key"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(appModel.isRedeemingInvite || appModel.hasInstallationCredential || inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                if appModel.isRedeemingInvite {
                    ProgressView("Connecting…")
                        .font(.agentBody)
                }
            }
            CyCallout {
                Text("Your invite is checked before any content is sent.")
                    .font(.agentBody)
            }

        case .examples:
            EditorialHeader(
                kicker: step.kicker,
                title: "Show Cy your voice.",
                subtitle: "Add three real examples, or do this later."
            )
            CyCallout {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("\(usableExampleCount) of 3 ready")
                    Text("Paste, record, link an Instagram post, or use a screenshot.")
                        .font(.agentBody)
                }
            }
            VStack(spacing: AgentSpacing.x6) {
                ForEach(Array(draft.voiceExamples.enumerated()), id: \.element.id) { index, example in
                    VoiceExampleInputCard(
                        example: exampleBinding(for: example.id),
                        number: index + 1,
                        isDictating: dictatingExampleID == example.id && recorder.state.isActive,
                        otherExampleIsDictating: recorder.state.isActive && dictatingExampleID != example.id,
                        onToggleDictation: { toggleExampleDictation(example.id) },
                        onRemove: draft.voiceExamples.count > 3 ? { removeExample(id: example.id) } : nil,
                        onNotice: { appModel.notice = .info($0) }
                    )
                    .disabled(appModel.isWorking)
                }
                if draft.voiceExamples.count < 5 {
                    Button("Add example", systemImage: "plus") {
                        draft.voiceExamples.append(VoiceExampleDraft())
                    }
                    .frame(minHeight: 44)
                    .disabled(appModel.isWorking)
                }
                SpeechCaptureStatusView(
                    state: recorder.state,
                    context: dictatingExampleNumber.map { "Voice example \($0)" }
                )
            }

        case .voice:
            EditorialHeader(kicker: step.kicker, title: "Does this sound like you?", subtitle: "Edit anything before you approve it.")
            AgentLabeledField(label: "Voice summary", placeholder: "How your voice feels", text: $draft.voiceSummary, axis: .vertical)
            AgentLabeledField(label: "Recurring traits", placeholder: "What Cy should preserve", text: $draft.voiceTraits, axis: .vertical)
            AgentLabeledField(label: "Avoid", placeholder: "What Cy should not imitate", text: $draft.voiceAvoid, axis: .vertical)

        case .reminders:
            EditorialHeader(kicker: step.kicker, title: "Want reminders?", subtitle: "They are optional and easy to change later.")
            VStack(spacing: AgentSpacing.x6) {
                Toggle("Daily focus", isOn: $draft.dailyReminderEnabled).font(.agentHeadline).tint(.actionAccent)
                if draft.dailyReminderEnabled {
                    Picker("Daily time", selection: $draft.dailyReminderHour) {
                        ForEach(6..<22, id: \.self) { hour in Text(hourLabel(hour)).tag(hour) }
                    }
                }
                Toggle("Weekly reset", isOn: $draft.weeklyReminderEnabled).font(.agentHeadline).tint(.actionAccent)
                if draft.weeklyReminderEnabled {
                    Picker("Day", selection: $draft.weeklyReminderWeekday) {
                        Text("Sunday").tag(1); Text("Monday").tag(2); Text("Friday").tag(6)
                    }
                    Picker("Time", selection: $draft.weeklyReminderHour) {
                        ForEach(6..<22, id: \.self) { hour in Text(hourLabel(hour)).tag(hour) }
                    }
                }
            }

        case .firstSpark:
            EditorialHeader(
                kicker: step.kicker,
                title: "Start with an idea.",
                subtitle: usableExampleCount >= 3
                    ? "Add your own or ask Cy for three options."
                    : "Add your own or ask Cy for three options. You can teach Cy your voice later."
            )
            VStack(spacing: AgentSpacing.x4) {
                Button {
                    finish(startWithIdeas: false)
                } label: {
                    Label("Add my idea", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                Button {
                    finish(startWithIdeas: true)
                } label: {
                    Label("Give me ideas", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(AgentSecondaryButtonStyle())
            }
            CyCallout {
                Text("Either choice creates the same simple brief.")
                    .font(.agentBody)
            }
        }
    }

    @ViewBuilder
    private var navigationControls: some View {
        if step != .firstSpark {
            VStack(spacing: AgentSpacing.x2) {
                HStack(spacing: AgentSpacing.x3) {
                    if stepIndex > 0 {
                        Button("Back") { moveBack() }
                            .frame(minWidth: 72, minHeight: 52)
                            .font(.agentHeadline)
                    }
                    Button(step == .examples ? "Build my voice profile" : "Continue") { moveForward() }
                        .buttonStyle(AgentPrimaryButtonStyle())
                        .disabled(!isStepValid || appModel.isWorking || recorder.state.isActive)
                        .overlay { if appModel.isWorking { ProgressView().tint(.onAccent) } }
                }
                if step == .examples {
                    Button("Add these later") { deferVoiceExamples() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .font(.agentHeadline)
                        .disabled(appModel.isWorking || recorder.state.isActive)
                }
            }
        }
    }

    private var isStepValid: Bool {
        switch step {
        case .welcome: draft.adultConfirmed
        case .profile: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.platforms.isEmpty
        case .mode: true
        case .invite: appModel.hasInstallationCredential
        case .examples: usableExampleCount >= 3
        case .voice: !draft.voiceSummary.isEmpty && !draft.voiceTraits.isEmpty
        case .reminders, .firstSpark: true
        }
    }

    private func moveForward() {
        if step == .examples {
            Task {
                if let result = await appModel.prepareVoiceProfile(from: draft) {
                    didDeferVoiceExamples = false
                    draft.voiceSummary = result.summary
                    draft.voiceTraits = result.canonical.signatureQualities.joined(separator: ", ")
                    draft.voiceAvoid = result.avoid
                    draft.voiceProfilePayloadJSON = (try? Self.encodeVoiceProfile(result.canonical)) ?? ""
                    setStep(.voice)
                }
            }
        } else if stepIndex + 1 < steps.count {
            setStep(steps[stepIndex + 1])
        }
    }

    private static func encodeVoiceProfile(_ profile: VoiceProfileWire) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(profile), as: UTF8.self)
    }

    private func moveBack() {
        guard stepIndex > 0 else { return }
        setStep(steps[stepIndex - 1])
    }

    private func setStep(_ newStep: Step) {
        if step == .examples, newStep != .examples, recorder.state.isActive {
            speechTask?.cancel()
            speechTask = Task { await recorder.stop() }
            dictatingExampleID = nil
        }
        if reduceMotion { step = newStep } else { withAnimation(.easeInOut(duration: 0.22)) { step = newStep } }
    }

    private func finish(startWithIdeas: Bool) {
        Task {
            appModel.quickCaptureStartsWithIdeas = startWithIdeas
            if await appModel.completeOnboarding(draft, context: context) {
                appModel.presentedSheet = .quickCapture
            }
        }
    }

    private func toggleExampleDictation(_ id: UUID) {
        if dictatingExampleID == id, recorder.state.isActive {
            speechTask?.cancel()
            speechTask = Task {
                await recorder.stop()
                dictatingExampleID = nil
            }
            return
        }

        speechTask?.cancel()
        speechTask = Task {
            if recorder.state.isActive { await recorder.stop() }
            guard draft.voiceExamples.contains(where: { $0.id == id }) else { return }
            dictatingExampleID = id
            do {
                let initialTranscript = draft.voiceExamples.first(where: { $0.id == id })?.text ?? ""
                try await recorder.start(initialTranscript: initialTranscript) { transcript in
                    guard let index = draft.voiceExamples.firstIndex(where: { $0.id == id }) else { return }
                    draft.voiceExamples[index].text = transcript
                    draft.voiceExamples[index].source = .text
                }
            } catch is CancellationError {
                if dictatingExampleID == id { dictatingExampleID = nil }
            } catch {
                dictatingExampleID = nil
                appModel.notice = .info(error.localizedDescription)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        DateComponents(calendar: .current, hour: hour).date?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }

    private var usableExampleCount: Int {
        draft.voiceExamples.filter(\.isUsableEvidence).count
    }

    private var dictatingExampleNumber: Int? {
        guard let dictatingExampleID,
              let index = draft.voiceExamples.firstIndex(where: { $0.id == dictatingExampleID }) else { return nil }
        return index + 1
    }

    private func exampleBinding(for id: UUID) -> Binding<VoiceExampleDraft> {
        Binding(
            get: { draft.voiceExamples.first(where: { $0.id == id }) ?? VoiceExampleDraft(id: id) },
            set: { updated in
                guard let index = draft.voiceExamples.firstIndex(where: { $0.id == id }) else { return }
                draft.voiceExamples[index] = updated
            }
        )
    }

    private func deferVoiceExamples() {
        didDeferVoiceExamples = true
        draft.voiceSummary = ""
        draft.voiceTraits = ""
        draft.voiceAvoid = ""
        draft.voiceProfilePayloadJSON = ""
        setStep(.reminders)
    }

    private func removeExample(id: UUID) {
        guard let index = draft.voiceExamples.firstIndex(where: { $0.id == id }), draft.voiceExamples.count > 3 else { return }
        if dictatingExampleID == id {
            speechTask?.cancel()
            speechTask = Task { await recorder.stop() }
            dictatingExampleID = nil
        }
        draft.voiceExamples.remove(at: index)
    }
}

private struct AgentLabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel(label)
            TextField(placeholder, text: $text, axis: axis)
                .font(.agentBody)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
        }
    }
}
