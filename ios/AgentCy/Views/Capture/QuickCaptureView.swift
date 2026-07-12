import SwiftData
import SwiftUI

@MainActor
struct QuickCaptureView: View {
    private enum CaptureKind: String, CaseIterable, Identifiable {
        case spark = "Idea"
        case task = "Task"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CaptureKind = .spark
    @State private var sparkText = ""
    @State private var taskTitle = ""
    @State private var taskKind: CreatorTaskKind = .planning
    @State private var addTarget = false
    @State private var targetDate = Date()
    @State private var ideas: [IdeaDirection] = []
    @State private var isFindingIdeas = false
    @State private var savedBrief: CreativeBrief?
    @State private var usedVoiceTranscript = false
    @State private var recorder = OnDeviceSpeechCapture()
    @State private var speechTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: "New",
                        title: savedBrief == nil ? "Save an idea." : "Idea saved.",
                        subtitle: savedBrief == nil ? "Type it or say it. You can shape it later." : "Keep it for later or build the brief now."
                    )

                    if let savedBrief {
                        VStack(spacing: AgentSpacing.x4) {
                            NavigationLink {
                                BriefDetailView(brief: savedBrief)
                            } label: {
                                Label("Build with Cy", systemImage: "bubble.left.and.sparkles")
                            }
                            .buttonStyle(AgentPrimaryButtonStyle())
                            Button("Done") { dismiss() }
                                .buttonStyle(AgentSecondaryButtonStyle())
                        }
                    } else {
                        Picker("Capture type", selection: $kind) {
                            ForEach(CaptureKind.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if kind == .spark { sparkComposer } else { taskComposer }
                    }
                }
                .padding(AgentSpacing.x6)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .agentScreen()
            .task {
                if let plannedDate = appModel.quickCaptureTargetDate {
                    targetDate = plannedDate
                }
                if appModel.quickCaptureStartsWithTask {
                    appModel.quickCaptureStartsWithTask = false
                    kind = .task
                }
                if appModel.quickCaptureStartsWithIdeas {
                    appModel.quickCaptureStartsWithIdeas = false
                    await loadIdeas()
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .task, recorder.state.isActive { stopVoiceCapture() }
            }
            .onDisappear {
                speechTask?.cancel()
                Task { await recorder.stop() }
            }
        }
    }

    private var sparkComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                SectionRuleHeader(title: "Your idea")
                TextEditor(text: $sparkText)
                    .font(.agentBody)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(AgentSpacing.x3)
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if sparkText.isEmpty {
                            Text("What do you want to make?")
                                .font(.agentBody)
                                .foregroundStyle(Color.agentSecondary)
                                .padding(AgentSpacing.x4)
                                .allowsHitTesting(false)
                        }
                    }
                HStack {
                    Button {
                        toggleRecording()
                    } label: {
                        Label(
                            recorder.state.isActive ? recorder.state.actionTitle : "Record",
                            systemImage: recorder.state.isActive ? recorder.state.actionSystemImage : "mic"
                        )
                    }
                    .buttonStyle(AgentCompactSecondaryButtonStyle())
                    .accessibilityHint(
                        recorder.state.isActive
                            ? "Stops private, on-device voice capture."
                            : "Starts private, on-device voice capture. You can keep typing instead."
                    )
                    Spacer()
                    Text("On-device")
                        .font(.agentMono)
                        .foregroundStyle(Color.agentSecondary)
                }
                SpeechCaptureStatusView(state: recorder.state, context: "Idea")
            }

            Button("Save idea", systemImage: "arrow.down.circle") {
                if recorder.state.isActive { stopVoiceCapture() }
                savedBrief = appModel.createSpark(
                    text: sparkText,
                    source: usedVoiceTranscript ? .voiceTranscript : .text,
                    targetDate: appModel.quickCaptureTargetDate,
                    context: context
                )
                appModel.quickCaptureTargetDate = nil
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(sparkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                SectionRuleHeader(title: "Need an idea?")
                Text("Cy can suggest three directions based on your work.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                Button {
                    Task { await loadIdeas() }
                } label: {
                    Label(isFindingIdeas ? "Thinking…" : "Show three ideas", systemImage: "sparkles")
                }
                .buttonStyle(AgentSecondaryButtonStyle())
                .disabled(isFindingIdeas)
                ForEach(ideas) { idea in
                    IdeaDirectionRow(idea: idea) {
                        if recorder.state.isActive { stopVoiceCapture() }
                        savedBrief = appModel.createSpark(
                            text: idea.premise,
                            source: .cyDirection,
                            targetDate: appModel.quickCaptureTargetDate,
                            context: context
                        )
                        appModel.quickCaptureTargetDate = nil
                        savedBrief?.title = idea.title
                        savedBrief?.spokenHook = idea.opening
                        savedBrief?.assumptions = [idea.assumption]
                        try? context.save()
                    }
                }
            }
        }
    }

    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            AgentCaptureField(label: "Next action", placeholder: "e.g. Film the opening take", text: $taskTitle)
            Picker("Kind", selection: $taskKind) {
                ForEach(CreatorTaskKind.allCases) { kind in Label(kind.title, systemImage: kind.symbol).tag(kind) }
            }
            Toggle("Add a flexible target", isOn: $addTarget).tint(.actionAccent)
            if addTarget {
                DatePicker("Target", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
            }
            Button("Save task", systemImage: "checkmark") {
                if appModel.createTask(title: taskTitle, kind: taskKind, targetDate: addTarget ? targetDate : nil, context: context) != nil {
                    dismiss()
                }
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func loadIdeas() async {
        kind = .spark
        isFindingIdeas = true
        ideas = await appModel.findIdeas(context: context)
        isFindingIdeas = false
    }

    private func toggleRecording() {
        if recorder.state.isActive {
            stopVoiceCapture()
        } else {
            speechTask?.cancel()
            speechTask = Task {
                do {
                    try await recorder.start(initialTranscript: sparkText) { transcript in
                        sparkText = transcript
                        usedVoiceTranscript = true
                    }
                } catch is CancellationError {
                    // Expected when the creator cancels preparation or recording.
                } catch {
                    appModel.notice = .info(error.localizedDescription)
                }
            }
        }
    }

    private func stopVoiceCapture() {
        speechTask?.cancel()
        speechTask = Task { await recorder.stop() }
    }
}

private struct IdeaDirectionRow: View {
    let idea: IdeaDirection
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack {
                Text(idea.title).font(.agentHeadline)
                Spacer()
                Button("Choose") { select() }
                    .buttonStyle(AgentCompactSecondaryButtonStyle())
            }
            Text(idea.premise).font(.agentBody)
            Text("“\(idea.opening)”").font(.agentBody).italic().foregroundStyle(Color.agentSecondary)
            MetaLabel(idea.assumption)
        }
        .padding(.vertical, AgentSpacing.x4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
    }
}

private struct AgentCaptureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel(label)
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.agentBody)
                .lineLimit(2...5)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
        }
    }
}
