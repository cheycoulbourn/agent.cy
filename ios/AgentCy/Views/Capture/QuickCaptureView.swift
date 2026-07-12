import SwiftData
import SwiftUI

@MainActor
struct QuickCaptureView: View {
    private enum CaptureKind: String, CaseIterable, Identifiable {
        case spark = "Idea"
        case post = "Post"
        case task = "Task"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @State private var kind: CaptureKind = .spark
    @State private var sparkText = ""
    @State private var postTitle = ""
    @State private var postNotes = ""
    @State private var postPillarID: UUID?
    @State private var postPlatform: CreatorPlatform = .instagramReels
    @State private var postFirstTask = ""
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
                        title: headerTitle,
                        subtitle: headerSubtitle
                    )

                    if let savedBrief {
                        VStack(spacing: AgentSpacing.x4) {
                            NavigationLink {
                                BriefDetailView(brief: savedBrief)
                            } label: {
                                Label("Develop with Cy", systemImage: "bubble.left.and.sparkles")
                            }
                            .buttonStyle(AgentPrimaryButtonStyle())
                            Button("Keep for later") { dismiss() }
                                .buttonStyle(AgentSecondaryButtonStyle())
                        }
                    } else {
                        Picker("Capture type", selection: $kind) {
                            ForEach(CaptureKind.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        switch kind {
                        case .spark: sparkComposer
                        case .post: postComposer
                        case .task: taskComposer
                        }
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
                if let suggestedPillarID = appModel.quickCapturePillarID,
                   pillars.contains(where: { $0.id == suggestedPillarID && !$0.isArchived }) {
                    postPillarID = suggestedPillarID
                }
                appModel.quickCapturePillarID = nil
                if let preferredPlatform = profiles.first?.selectedPlatforms.first {
                    postPlatform = preferredPlatform
                }
                if appModel.quickCaptureStartsWithTask {
                    appModel.quickCaptureStartsWithTask = false
                    kind = .task
                }
                if appModel.quickCaptureStartsWithPost {
                    appModel.quickCaptureStartsWithPost = false
                    kind = .post
                }
                if appModel.quickCaptureStartsWithIdeas {
                    appModel.quickCaptureStartsWithIdeas = false
                    await loadIdeas()
                }
                if appModel.quickCaptureStartsRecording {
                    appModel.quickCaptureStartsRecording = false
                    kind = .spark
                    await Task.yield()
                    toggleRecording()
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind != .spark, recorder.state.isActive { stopVoiceCapture() }
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

    private var postComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            AgentCaptureField(label: "Title", placeholder: "What are you posting?", text: $postTitle)

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Notes")
                TextField("The angle, reminder, or rough direction", text: $postNotes, axis: .vertical)
                    .font(.agentBody)
                    .lineLimit(3...7)
                    .padding(AgentSpacing.x4)
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
            }

            Picker("Pillar", selection: $postPillarID) {
                Text("No pillar").tag(UUID?.none)
                ForEach(pillars.filter { !$0.isArchived }) { pillar in
                    Label {
                        Text(pillar.name)
                    } icon: {
                        Circle()
                            .fill(Color(agentHex: pillar.resolvedColorHex(in: pillars)))
                            .frame(width: 12, height: 12)
                    }
                        .tag(Optional(pillar.id))
                }
            }

            Picker("Platform", selection: $postPlatform) {
                ForEach(CreatorPlatform.allCases) { platform in
                    Label(platform.title, systemImage: platform.symbol).tag(platform)
                }
            }

            DatePicker("Post on", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])

            AgentCaptureField(
                label: "First task · optional",
                placeholder: "e.g. Draft the opening",
                text: $postFirstTask
            )

            Button("Save post", systemImage: "checkmark") {
                savedBrief = appModel.createPost(
                    title: postTitle,
                    notes: postNotes,
                    pillarID: postPillarID,
                    platform: postPlatform,
                    targetDate: targetDate,
                    firstTaskTitle: postFirstTask,
                    context: context
                )
                if savedBrief != nil { appModel.quickCaptureTargetDate = nil }
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(postTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var headerTitle: String {
        if savedBrief != nil { return kind == .post ? "Post saved." : "Idea saved." }
        return switch kind {
        case .spark: "Save an idea."
        case .post: "Plan a post."
        case .task: "Add a task."
        }
    }

    private var headerSubtitle: String {
        if savedBrief != nil { return "Keep it here or develop it with Cy." }
        return switch kind {
        case .spark: "Type it or say it. Shape it later."
        case .post: "Choose the essentials. Build the full brief when you need it."
        case .task: "Capture one clear next action."
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
