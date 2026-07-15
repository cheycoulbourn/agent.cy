import SwiftData
import SwiftUI

enum CyIdeaRequestPhase: Equatable {
    case idle
    case loading
    case loaded
    case upgradeRequired(message: String)
    case unavailable(message: String)

    static func failure(message: String, requiresUpgrade: Bool) -> Self {
        requiresUpgrade ? .upgradeRequired(message: message) : .unavailable(message: message)
    }
}

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
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @State private var kind: CaptureKind = .spark
    @State private var ideaTitle = ""
    @State private var ideaNotes = ""
    @State private var ideaPillarID: UUID?
    @State private var postTitle = ""
    @State private var postNotes = ""
    @State private var postPillarID: UUID?
    @State private var postDestinationID = PublishingCatalog.instagramID
    @State private var postFormatID = PublishingCatalog.instagramReelID
    @State private var postSocialAccountID: UUID?
    @State private var postDurationSeconds = ContentFormat.shortForm.defaultDuration
    @State private var postIncludesTime = false
    @State private var taskTitle = ""
    @State private var taskNotes = ""
    @State private var taskPillarID: UUID?
    @State private var taskKind: CreatorTaskKind = .planning
    @State private var taskLane: TaskLane = .pillar
    @State private var taskPriority: TaskPriority = .none
    @State private var taskRecurrence: TaskRecurrenceFrequency = .none
    @State private var taskFocusAssignment: DailyFocusTaskAssignment?
    @State private var draftSubtasks: [DraftCaptureSubtask] = []
    @State private var showTaskDueDatePicker = false
    @State private var addTarget = false
    @State private var taskIncludesTime = false
    @State private var targetDate = Date()
    @State private var ideas: [IdeaDirection] = []
    @State private var ideaPhase: CyIdeaRequestPhase = .idle
    @State private var isCySuggestionsMode = false
    @State private var savedGeneratedIdeaIDs: Set<UUID> = []
    @State private var savedBrief: CreativeBrief?
    @State private var didSaveIdea = false
    @State private var didSavePost = false
    @State private var didHandleDismissal = false
    @State private var isCyIdeaCardVisible = true
    @State private var quickPostDraft: QuickPostDraft?
    @State private var showPostDevelopment = false
    @State private var showAccess = false
    @State private var selectedDetent: PresentationDetent = .large
    @FocusState private var focusedWritingField: WritingField?

    private enum WritingField: Hashable {
        case ideaNotes
        case postNotes
        case taskNotes
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    if showingCySuggestions {
                        cySuggestionsContent
                    } else {
                        captureKindRail

                        if kind == .post, let quickPostDraft {
                            ResumablePostEditorView(
                                brief: quickPostDraft.brief,
                                output: quickPostDraft.output,
                                contextLabel: "New post",
                                onSpark: { showPostDevelopment = true }
                            )
                        } else {
                            switch kind {
                            case .spark: sparkComposer
                            case .post: postComposer
                            case .task: taskComposer
                            }
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { closeCapture() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !showingCySuggestions, kind == .spark || kind == .task {
                        Button {
                            if kind == .spark {
                                saveIdea()
                            } else {
                                saveTask()
                            }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(Color(red: 1, green: 1, blue: 1))
                        .disabled(!canSaveToolbarItem)
                        .opacity(canSaveToolbarItem ? 1 : 0.4)
                        .accessibilityLabel(kind == .spark ? "Save idea" : "Save task")
                    }
                }
            }
            .agentScreen()
            .task {
                if let plannedDate = appModel.quickCaptureTargetDate {
                    targetDate = plannedDate
                }
                if let suggestedPillarID = appModel.quickCapturePillarID,
                   pillars.contains(where: { $0.id == suggestedPillarID && !$0.isArchived }) {
                    ideaPillarID = suggestedPillarID
                    postPillarID = suggestedPillarID
                }
                appModel.quickCapturePillarID = nil
                if let preferredPlatform = profiles.first?.selectedPlatforms.first {
                    let ids = PublishingCatalog.identifiers(for: preferredPlatform)
                    postDestinationID = ids.destination
                    postFormatID = ids.format
                    postDurationSeconds = preferredPlatform.format.defaultDuration
                    postSocialAccountID = preferredAccountID
                }
                if appModel.quickCaptureStartsWithTask {
                    appModel.quickCaptureStartsWithTask = false
                    kind = .task
                    addTarget = appModel.quickCaptureTargetDate != nil
                    if let requestedLane = appModel.quickCaptureTaskLane {
                        taskLane = requestedLane
                    }
                    appModel.quickCaptureTaskLane = nil
                    if let focusAssignment = appModel.quickCaptureTaskFocus {
                        taskFocusAssignment = focusAssignment
                        taskLane = .production
                        taskKind = focusAssignment.taskKind
                        targetDate = focusAssignment.date
                        addTarget = true
                    }
                    appModel.quickCaptureTaskFocus = nil
                }
                if appModel.quickCaptureStartsWithPost {
                    appModel.quickCaptureStartsWithPost = false
                    kind = .post
                    beginQuickPostDraft()
                }
                if appModel.quickCaptureStartsWithIdeas {
                    appModel.quickCaptureStartsWithIdeas = false
                    await loadIdeas()
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .post { beginQuickPostDraft() }
                if newKind != .spark {
                    updateSavedIdeaFromForm()
                    savedBrief = nil
                }
            }
            .onDisappear {
                if !showingCySuggestions {
                    updateSavedIdeaFromForm()
                    finalizeQuickPostDraft()
                    preserveUnfinishedDrafts()
                }
            }
            .sheet(isPresented: $showPostDevelopment) {
                if let quickPostDraft {
                    DevelopBriefView(brief: quickPostDraft.brief, output: quickPostDraft.output)
                }
            }
            .sheet(isPresented: $showAccess) {
                NavigationStack { AccessSettingsView() }
                    .preferredColorScheme(appModel.appearancePreference.colorSchemeOverride)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showTaskDueDatePicker) {
                CaptureTaskDueDateSheet(
                    date: $targetDate,
                    hasDueDate: $addTarget,
                    includesTime: $taskIncludesTime
                )
                .preferredColorScheme(appModel.appearancePreference.colorSchemeOverride)
                .presentationDetents([.large])
            }
        }
        .presentationDetents([.height(620), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .agentKeyboardDismissal()
    }

    private var captureKindRail: some View {
        Picker("Capture type", selection: $kind) {
            ForEach(CaptureKind.allCases) { captureKind in
                Text(captureKind.rawValue).tag(captureKind)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Switch between idea, post, and task without losing your work")
    }

    private var showingCySuggestions: Bool {
        isCySuggestionsMode || appModel.quickCaptureStartsWithIdeas
    }

    private var isFindingIdeas: Bool {
        ideaPhase == .loading
    }

    @ViewBuilder
    private var cySuggestionsContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            switch ideaPhase {
            case .upgradeRequired(let message):
                cyProUpsell(message: message)
            case .loading:
                suggestionsHeader(title: "Finding ideas.")
                HStack(spacing: AgentSpacing.x3) {
                    CyThinkingMark(color: .cyAccent, size: 18)
                    Text("Shaping directions from your goals, pillars, and work…")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
                .padding(AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            case .loaded:
                suggestionsHeader(title: "Three ideas.")
                cyIdeaDirections
            case .unavailable(let message):
                cyUnavailableNotice(message: message)
            case .idle:
                EmptyView()
            }
        }
    }

    private func suggestionsHeader(title: String) -> some View {
        EditorialHeader(
            kicker: "Cy ideas",
            title: title,
            subtitle: "Save what fits. Unsaved suggestions disappear when you leave."
        )
    }

    private func cyProUpsell(message: String) -> some View {
        paperCyState(kicker: "Cy · free limit") {
            VStack(spacing: AgentSpacing.x4) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAsterisk(color: .agentSecondary, size: 12, strokeWidth: 1.2)
                    Text("Included Cy ideas used")
                        .font(.paperMono(size: 11, weight: .medium, relativeTo: .caption))
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                .foregroundStyle(Color.agentSecondary)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 36)
                .background(Color.agentText.opacity(0.035), in: .capsule)
                .overlay(Capsule().stroke(Color.agentText.opacity(0.08), lineWidth: 1))

                Text("Keep creating with Cy")
                    .font(.paperInter(size: 20, weight: .semibold, relativeTo: .title3))
                    .tracking(-0.2)
                    .multilineTextAlignment(.center)

                VStack(spacing: AgentSpacing.x2) {
                    Text("Cy Pro keeps personalized ideas, full briefs, and revisions available.")
                    Text("14 days free, then $8.99 a month.")
                }
                .font(.paperInter(size: 14, weight: .regular, relativeTo: .body))
                .foregroundStyle(Color.agentSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .accessibilityLabel(message)

                paperCyActions(
                    primaryTitle: "Upgrade to Pro",
                    primaryAction: { showAccess = true },
                    secondaryTitle: "Not now",
                    secondaryAction: closeCapture
                )
            }
        }
    }

    private func cyUnavailableNotice(message: String) -> some View {
        paperCyState(kicker: "Cy · paused") {
            VStack(spacing: AgentSpacing.x4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.agentText.opacity(0.3), lineWidth: 1.5)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.agentText)
                }
                .frame(width: 48, height: 48)

                Text("Couldn’t make those ideas")
                    .font(.paperInter(size: 20, weight: .semibold, relativeTo: .title3))
                    .tracking(-0.2)
                    .multilineTextAlignment(.center)

                Text(friendlyCyFailureMessage(message))
                    .font(.paperInter(size: 14, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 280)

                paperCyActions(
                    primaryTitle: "Generate again",
                    primaryAction: { Task { await loadIdeas() } },
                    secondaryTitle: "Close",
                    secondaryAction: closeCapture
                )
            }
        }
    }

    private func paperCyState<Content: View>(
        kicker: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MetaLabel(kicker)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 442, alignment: .topLeading)
        .padding(.horizontal, AgentSpacing.x2)
        .padding(.top, AgentSpacing.x2)
    }

    private func paperCyActions(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AgentSpacing.x3) {
            Button(primaryTitle, action: primaryAction)
                .font(.paperInter(size: 15, weight: .medium, relativeTo: .body))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, AgentSpacing.x6)
                .frame(minHeight: 46)
                .background(Color.actionAccent, in: .capsule)
                .buttonStyle(.plain)

            Button(secondaryTitle, action: secondaryAction)
                .font(.paperInter(size: 14, weight: .medium, relativeTo: .body))
                .foregroundStyle(Color.agentText)
                .underline(true, color: Color.agentText)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
    }

    private func friendlyCyFailureMessage(_ message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("ended before") || normalized.contains("complete result") {
            return "Cy’s response stopped early. Nothing was saved."
        }
        if normalized.contains("timed out") || normalized.contains("timeout") {
            return "Cy took too long to respond. Nothing was saved."
        }
        return "Cy couldn’t finish the request. Nothing was saved."
    }

    private var sparkComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            HStack {
                MetaLabel("New idea")
                Spacer()
                Button {
                    Task { await loadIdeas() }
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                        Text("Spark")
                    }
                    .font(.agentSubtext.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .foregroundStyle(Color.cyAccent)
                    .background(Color.cyAccent.opacity(0.06), in: .capsule)
                    .overlay(Capsule().stroke(Color.cyAccent.opacity(0.18), lineWidth: 1))
                    .shadow(color: Color.cyAccent.opacity(0.16), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Asks Cy for three ideas")
            }

            TextField("Your idea title…", text: $ideaTitle, axis: .vertical)
                .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                .tracking(-0.56)
                .lineLimit(1...3)

            VStack(spacing: 0) {
                Menu {
                    Button("No pillar") { ideaPillarID = nil }
                    ForEach(activePillars) { pillar in
                        Button {
                            ideaPillarID = pillar.id
                        } label: {
                            PillarMenuChoiceLabel(
                                title: pillar.name,
                                colorHex: pillar.resolvedColorHex(in: activePillars),
                                isSelected: ideaPillarID == pillar.id
                            )
                        }
                    }
                } label: {
                    IdeaCaptureSetupRow(
                        label: "Pillar",
                        value: selectedIdeaPillar?.name ?? "Pick a pillar",
                        color: selectedIdeaPillar.map {
                            Color(agentHex: $0.resolvedColorHex(in: activePillars))
                        }
                    )
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                AgentInputHeader(title: "Notes", isEditing: focusedWritingField == .ideaNotes) {
                    focusedWritingField = nil
                }
                TextEditor(text: $ideaNotes)
                    .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(16)
                    .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.agentText.opacity(0.16), lineWidth: 1)
                    }
                    .focused($focusedWritingField, equals: .ideaNotes)
            }
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var selectedIdeaPillar: Pillar? { activePillars.first { $0.id == ideaPillarID } }
    private var selectedTaskPillar: Pillar? { activePillars.first { $0.id == taskPillarID } }

    private var cyIdeaDirections: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                IdeaDirectionRow(
                    number: index + 1,
                    idea: idea,
                    suggestedPillarName: suggestedPillar(for: idea)?.name,
                    isSaved: savedGeneratedIdeaIDs.contains(idea.id)
                ) {
                    saveGeneratedIdea(idea)
                }
            }
        }
    }

    private var cyIdeaPrompt: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x2) {
                CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                MetaLabel(ideas.isEmpty ? "Cy suggests" : "From Cy")
                    .foregroundStyle(Color.cyAccent)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isCyIdeaCardVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.agentSecondary)
                .accessibilityLabel("Dismiss Cy suggestion")
                .padding(.trailing, -12)
                .padding(.vertical, -12)
            }

            Text(cyIdeaCardTitle)
                .font(.agentHeadline)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)

            Text(cyIdeaCardMessage)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AgentSpacing.x4) {
                if ideas.isEmpty {
                    Button {
                        Task { await loadIdeas() }
                    } label: {
                        HStack(spacing: AgentSpacing.x2) {
                            Text(isFindingIdeas ? "Finding ideas" : "Three ideas")
                            if isFindingIdeas {
                                CyThinkingMark(color: .onCyAccent, size: 14)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.onCyAccent)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 42)
                        .background(Color.cyAccent, in: .capsule)
                        .shadow(color: Color.cyAccent.opacity(0.2), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFindingIdeas)
                }

                Button(action: openIdeaBank) {
                    HStack(spacing: 6) {
                        Text("Idea Bank")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.agentSubtext.weight(.medium))
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 42)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyAccent.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: Color.cyAccent.opacity(0.08), radius: 14, y: 4)
    }

    private var cyIdeaCardTitle: String {
        if isFindingIdeas { return "I’m looking for your next angle." }
        return ideas.isEmpty ? "Let’s find a stronger starting point." : "Three directions, shaped for you."
    }

    private var cyIdeaCardMessage: String {
        if isFindingIdeas { return "I’m using your goals, pillars, and saved work. This should only take a moment."
        }
        return ideas.isEmpty
            ? "I can give you three distinct ideas grounded in the work you already care about."
            : "Save the ideas you want to keep. Unsaved directions disappear when you leave."
    }

    private func openIdeaBank() {
        appModel.presentedSheet = nil
        appModel.selectedTab = .ideaBank
    }

    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            MetaLabel("New task")

            TextField("What's the task?", text: $taskTitle, axis: .vertical)
                .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                .tracking(-0.56)
                .lineLimit(1...3)

            VStack(spacing: 0) {
                if taskLane == .production {
                    if let taskFocusAssignment {
                        IdeaCaptureSetupRow(label: "Focus", value: taskFocusAssignment.title)
                    } else {
                        Menu {
                            ForEach(CreatorTaskKind.allCases) { kind in
                                Button(kind.title) { taskKind = kind }
                            }
                        } label: {
                            IdeaCaptureSetupRow(label: "Focus", value: taskKind.title)
                        }
                    }
                } else {
                    Menu {
                        Button("No pillar") { taskPillarID = nil }
                        ForEach(activePillars) { pillar in
                            Button {
                                taskPillarID = pillar.id
                            } label: {
                                PillarMenuChoiceLabel(
                                    title: pillar.name,
                                    colorHex: pillar.resolvedColorHex(in: activePillars),
                                    isSelected: taskPillarID == pillar.id
                                )
                            }
                        }
                    } label: {
                        IdeaCaptureSetupRow(
                            label: "Pillar",
                            value: selectedTaskPillar?.name ?? "Pick a pillar",
                            color: selectedTaskPillar.map {
                                Color(agentHex: $0.resolvedColorHex(in: activePillars))
                            }
                        )
                    }
                }

                Menu {
                    ForEach(TaskPriority.selectableCases) { priority in
                        Button(priority.title) { taskPriority = priority }
                    }
                } label: {
                    IdeaCaptureSetupRow(label: "Priority", value: taskPriority.title)
                }

                Button {
                    showTaskDueDatePicker = true
                } label: {
                    IdeaCaptureSetupRow(label: "Due", value: taskDueDateLabel)
                }
                .buttonStyle(.plain)

                if taskLane == .production {
                    Menu {
                        ForEach(TaskRecurrenceFrequency.allCases) { recurrence in
                            Button(recurrence.title) { taskRecurrence = recurrence }
                        }
                    } label: {
                        IdeaCaptureSetupRow(label: "Repeat", value: taskRecurrence.title)
                    }
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                AgentInputHeader(title: "Notes", isEditing: focusedWritingField == .taskNotes) {
                    focusedWritingField = nil
                }
                TextEditor(text: $taskNotes)
                    .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 132)
                    .padding(16)
                    .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.agentText.opacity(0.16), lineWidth: 1)
                    }
                    .focused($focusedWritingField, equals: .taskNotes)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Subtasks")
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                    Spacer()
                    MetaLabel("\(draftSubtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)")
                }

                ForEach($draftSubtasks) { $subtask in
                    DraftCaptureSubtaskRow(subtask: $subtask)
                }

                Button {
                    draftSubtasks.append(DraftCaptureSubtask())
                } label: {
                    HStack(spacing: AgentSpacing.x3) {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.agentText.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3]))
                            .frame(width: 18, height: 18)
                        Text("Add subtask")
                            .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                        Spacer()
                    }
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: taskRecurrence) { _, recurrence in
            if recurrence != .none { addTarget = true }
        }
        .onChange(of: taskLane) { _, lane in
            if lane != .production { taskRecurrence = .none }
        }
    }

    private func saveTask() {
        if let task = appModel.createTask(
            title: taskTitle,
            kind: taskKind,
            lane: taskLane,
            priority: taskPriority,
            targetDate: addTarget ? targetDate : nil,
            includesTargetTime: addTarget && taskIncludesTime,
            focusAssignment: taskFocusAssignment,
            recurrence: taskRecurrence,
            context: context
        ) {
            task.pillarID = taskLane == .pillar ? taskPillarID : nil
            task.notes = taskNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            for draft in draftSubtasks {
                let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty,
                      let subtask = appModel.createSubtask(title: title, parent: task, context: context)
                else { continue }
                if draft.isCompleted {
                    subtask.isCompleted = true
                    subtask.completedAt = Date()
                }
            }
            try? context.save()
            appModel.quickCaptureTargetDate = nil
            dismiss()
        }
    }

    private func lockedTaskValue(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x4) {
            MetaLabel(label)
            Spacer()
            Text(value)
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }

    private var postComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            AgentCaptureField(label: "Title", placeholder: "What are you posting?", text: $postTitle)

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                AgentInputHeader(title: "Notes", isEditing: focusedWritingField == .postNotes) {
                    focusedWritingField = nil
                }
                TextField("", text: $postNotes, axis: .vertical)
                    .font(.agentBody)
                    .lineLimit(3...7)
                    .padding(AgentSpacing.x4)
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                    .focused($focusedWritingField, equals: .postNotes)
            }

            Picker("Pillar", selection: $postPillarID) {
                Text("No pillar").tag(UUID?.none)
                ForEach(pillars.filter { !$0.isArchived }) { pillar in
                    PillarMenuChoiceLabel(
                        title: pillar.name,
                        colorHex: pillar.resolvedColorHex(in: pillars),
                        isSelected: postPillarID == pillar.id
                    )
                    .tag(Optional(pillar.id))
                }
            }

            Picker("Destination", selection: $postDestinationID) {
                ForEach(destinations.filter { !$0.isArchived }) { destination in
                    Text(destination.name).tag(destination.id)
                }
            }

            Picker("Format", selection: $postFormatID) {
                ForEach(availableFormats) { format in Text(format.name).tag(format.id) }
            }

            if !availableSocialAccounts.isEmpty {
                Picker("Account", selection: $postSocialAccountID) {
                    Text("No account").tag(UUID?.none)
                    ForEach(availableSocialAccounts) { account in
                        Text(account.label).tag(Optional(account.id))
                    }
                }
            }

            if let contentFormat = selectedFormat?.kind.contentFormat {
                AgentDurationPicker(seconds: $postDurationSeconds, format: contentFormat)
            }

            DatePicker("Date", selection: $targetDate, displayedComponents: .date)

            Toggle("Include a time", isOn: $postIncludesTime)
                .font(.agentBody.weight(.semibold))
                .tint(Color.actionAccent)

            if postIncludesTime {
                DatePicker("Time", selection: $targetDate, displayedComponents: .hourAndMinute)
            }

            Button("Save post", systemImage: "checkmark") {
                savePost(title: postTitle)
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(postTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: postDestinationID) { _, _ in
            if let first = availableFormats.first { postFormatID = first.id }
            postSocialAccountID = preferredAccountID
        }
        .onChange(of: postFormatID) { _, _ in
            if let format = selectedFormat?.kind.contentFormat,
               !format.durationOptions.contains(postDurationSeconds) {
                postDurationSeconds = format.defaultDuration
            }
        }
    }

    private var availableFormats: [PublishingFormat] {
        formats.filter { $0.destinationID == postDestinationID && !$0.isArchived }
    }

    private var selectedFormat: PublishingFormat? {
        formats.first { $0.id == postFormatID }
    }

    private var availableSocialAccounts: [CreatorSocialAccount] {
        socialAccounts.filter { account in
            account.destinationID == postDestinationID &&
                !account.isArchived &&
                profiles.first.map { account.profileID == $0.id } != false
        }
    }

    private var preferredAccountID: UUID? {
        availableSocialAccounts.first(where: \.isPrimary)?.id ?? availableSocialAccounts.first?.id
    }

    private var navigationTitle: String {
        if quickPostDraft != nil { return "New Post" }
        return switch kind {
        case .spark: "New Idea"
        case .post: "New Post"
        case .task: "New Task"
        }
    }

    private var taskDueDateLabel: String {
        guard addTarget else { return "Set a date" }
        if taskIncludesTime {
            return targetDate.formatted(
                .dateTime
                    .weekday(.abbreviated)
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
            )
        }
        return targetDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
        if savedBrief != nil, kind == .spark { return "It’s in your Idea Bank. Keep editing here if you want." }
        return switch kind {
        case .spark: "Name it, add a note, and choose where it belongs."
        case .post: "Choose the essentials. Build the full brief when you need it."
        case .task: "Capture one clear next action."
        }
    }

    private func loadIdeas() async {
        kind = .spark
        isCySuggestionsMode = true
        selectedDetent = .height(620)
        savedGeneratedIdeaIDs = []
        ideas = []
        ideaPhase = .loading
        switch await appModel.findIdeaSuggestions(context: context) {
        case .success(let suggestions):
            ideas = suggestions
            ideaPhase = .loaded
            selectedDetent = .large
        case .unavailable(let message, let requiresUpgrade):
            ideaPhase = .failure(message: message, requiresUpgrade: requiresUpgrade)
        case .cancelled:
            ideaPhase = .idle
            isCySuggestionsMode = false
        }
    }

    private func closeCapture() {
        if showingCySuggestions {
            appModel.quickCaptureStartsWithIdeas = false
            appModel.quickCaptureTargetDate = nil
            dismiss()
            return
        }
        updateSavedIdeaFromForm()
        preserveUnfinishedDrafts()
        dismiss()
    }

    private func saveIdea() {
        let title = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if savedBrief != nil {
            updateSavedIdeaFromForm()
            dismiss()
            return
        }
        let notes = ideaNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        savedBrief = appModel.createSpark(
            text: notes.isEmpty ? title : notes,
            source: .text,
            title: title,
            notes: notes,
            pillarID: ideaPillarID,
            targetDate: appModel.quickCaptureTargetDate,
            context: context
        )
        didSaveIdea = savedBrief != nil
        if didSaveIdea {
            appModel.quickCaptureTargetDate = nil
            dismiss()
        }
    }

    private func saveGeneratedIdea(_ idea: IdeaDirection) {
        guard !savedGeneratedIdeaIDs.contains(idea.id) else { return }
        let pillar = suggestedPillar(for: idea)
        guard let savedIdea = appModel.createSpark(
            text: idea.premise,
            source: .cyDirection,
            title: idea.title,
            notes: idea.premise,
            pillarID: pillar?.id,
            targetDate: nil,
            context: context
        ) else { return }

        savedIdea.spokenHook = idea.opening
        savedIdea.assumptions = [idea.assumption]
        savedIdea.updatedAt = Date()
        savedGeneratedIdeaIDs.insert(idea.id)
        didSaveIdea = true
        try? context.save()
    }

    private func suggestedPillar(for idea: IdeaDirection) -> Pillar? {
        guard let pillarID = idea.suggestedPillarID else { return nil }
        return pillars.first { $0.id == pillarID && !$0.isArchived }
    }

    private func updateSavedIdeaFromForm() {
        guard let savedBrief else { return }
        let title = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let notes = ideaNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        savedBrief.title = title
        savedBrief.notes = notes
        savedBrief.premise = notes.isEmpty ? title : notes
        savedBrief.pillarID = ideaPillarID
        savedBrief.updatedAt = Date()
        try? context.save()
    }

    private func savePost(title: String) {
        savedBrief = appModel.createPost(
            title: title,
            notes: postNotes,
            pillarID: postPillarID,
            platform: selectedLegacyPlatform,
            destinationID: postDestinationID,
            formatID: postFormatID,
            socialAccountID: postSocialAccountID,
            durationSeconds: postDurationSeconds,
            targetDate: targetDate,
            includesTargetTime: postIncludesTime,
            context: context
        )
        didSavePost = savedBrief != nil
        if didSavePost { appModel.quickCaptureTargetDate = nil }
    }

    private func beginQuickPostDraft() {
        guard quickPostDraft == nil else { return }
        guard let draft = appModel.beginPostDraft(
            pillarID: postPillarID,
            platform: selectedLegacyPlatform,
            destinationID: postDestinationID,
            formatID: postFormatID,
            socialAccountID: postSocialAccountID,
            durationSeconds: postDurationSeconds,
            targetDate: targetDate,
            includesTargetTime: postIncludesTime,
            context: context
        ) else { return }

        quickPostDraft = QuickPostDraft(brief: draft.brief, output: draft.output)
        didSavePost = true
        appModel.quickCaptureTargetDate = nil
    }

    private func finalizeQuickPostDraft() {
        guard let draft = quickPostDraft else { return }

        let briefID = draft.brief.id
        let linkedTasks = (try? context.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.briefID == briefID }
        ))) ?? []
        let contentValues = [
            draft.brief.title,
            draft.brief.notes,
            draft.brief.premise,
            draft.output.caption,
            draft.output.openingAdjustment,
            draft.output.titleOverride,
            draft.output.cta,
            draft.output.editChanges,
        ]
        let hasText = contentValues.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard hasText || !linkedTasks.isEmpty else {
            context.delete(draft.output)
            context.delete(draft.brief)
            try? context.save()
            appModel.queueCalendarSync(context: context)
            return
        }

        if draft.brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.brief.title = CaptureDraftResolver.postTitle(
                title: "",
                notes: draft.brief.notes.isEmpty ? draft.brief.premise : draft.brief.notes
            ) ?? "Untitled post"
        }
        draft.output.status = .draft
        draft.brief.updatedAt = Date()
        try? context.save()
        appModel.queueCalendarSync(context: context)
    }

    private func preserveUnfinishedDrafts() {
        guard !didHandleDismissal else { return }
        didHandleDismissal = true

        if !didSaveIdea, let title = CaptureDraftResolver.ideaText(ideaTitle) {
            let notes = ideaNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            didSaveIdea = appModel.createSpark(
                text: notes.isEmpty ? title : notes,
                source: .text,
                title: title,
                notes: notes,
                pillarID: ideaPillarID,
                targetDate: appModel.quickCaptureTargetDate,
                context: context
            ) != nil
        }

        if !didSavePost,
           let draftTitle = CaptureDraftResolver.postTitle(title: postTitle, notes: postNotes) {
            didSavePost = appModel.createPost(
                title: draftTitle,
                notes: postNotes,
                pillarID: postPillarID,
                platform: selectedLegacyPlatform,
                destinationID: postDestinationID,
                formatID: postFormatID,
                socialAccountID: postSocialAccountID,
                durationSeconds: postDurationSeconds,
                targetDate: targetDate,
                includesTargetTime: postIncludesTime,
                context: context
            ) != nil
        }

        if didSaveIdea || didSavePost { appModel.quickCaptureTargetDate = nil }
    }

    private var selectedLegacyPlatform: CreatorPlatform {
        PublishingCatalog.legacyPlatform(destinationID: postDestinationID, formatID: postFormatID)
            ?? (selectedFormat?.kind == .longVideo ? .youtubeVideo : .instagramReels)
    }

    private var canSaveToolbarItem: Bool {
        switch kind {
        case .spark:
            !ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .task:
            !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .post:
            false
        }
    }
}

private struct QuickPostDraft {
    let brief: CreativeBrief
    let output: PlatformOutput
}

private struct DraftCaptureSubtask: Identifiable {
    let id = UUID()
    var title = ""
    var isCompleted = false
}

private struct DraftCaptureSubtaskRow: View {
    @Binding var subtask: DraftCaptureSubtask

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            Button {
                subtask.isCompleted.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 3)
                    .fill(subtask.isCompleted ? Color.agentText : Color.clear)
                    .frame(width: 18, height: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.agentText.opacity(subtask.isCompleted ? 0 : 0.3), lineWidth: 1)
                        if subtask.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.agentCanvas)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "Mark subtask open" : "Mark subtask complete")

            TextField("Subtask", text: $subtask.title, axis: .vertical)
                .font(.paperInter(size: 15, weight: .medium, relativeTo: .body))
                .lineLimit(1...3)
                .strikethrough(subtask.isCompleted)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
    }
}

private struct CaptureTaskDueDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var date: Date
    @Binding private var hasDueDate: Bool
    @Binding private var includesTime: Bool
    @State private var selectedDate: Date
    @State private var selectedIncludesTime: Bool

    init(date: Binding<Date>, hasDueDate: Binding<Bool>, includesTime: Binding<Bool>) {
        _date = date
        _hasDueDate = hasDueDate
        _includesTime = includesTime
        _selectedDate = State(initialValue: date.wrappedValue)
        _selectedIncludesTime = State(initialValue: includesTime.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Task due")
                        Text("Choose a date. Add a time only if it matters.")
                            .font(.agentHeadline)
                            .foregroundStyle(Color.agentText)
                    }

                    DatePicker(
                        "Date",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    VStack(spacing: 0) {
                        Toggle("Include a time", isOn: $selectedIncludesTime)
                            .font(.agentBody.weight(.semibold))
                            .tint(Color.actionAccent)
                            .frame(minHeight: 52)

                        if selectedIncludesTime {
                            Divider().overlay(Color.agentHairline)
                            HStack {
                                Text("Time").font(.agentBody)
                                Spacer()
                                DatePicker(
                                    "Time",
                                    selection: $selectedDate,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            .frame(minHeight: 52)
                        }
                    }

                    if hasDueDate {
                        Button("Remove due date", role: .destructive) {
                            hasDueDate = false
                            dismiss()
                        }
                        .font(.agentSubtext.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x12)
            }
            .navigationTitle("Due")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                        Button("Use date") {
                        date = selectedIncludesTime
                            ? selectedDate
                            : Calendar.current.startOfDay(for: selectedDate)
                        hasDueDate = true
                        includesTime = selectedIncludesTime
                        dismiss()
                    }
                }
            }
            .agentScreen()
        }
    }
}

enum CaptureDraftResolver {
    static func ideaText(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func postTitle(title: String, notes: String) -> String? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedTitle.isEmpty { return cleanedTitle }

        let cleanedNotes = notes
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !cleanedNotes.isEmpty else { return nil }
        let prefix = String(cleanedNotes.prefix(64))
        return cleanedNotes.count > prefix.count ? "\(prefix)…" : prefix
    }
}

private struct IdeaCaptureSetupRow: View {
    let label: String
    let value: String
    var color: Color?

    var body: some View {
        HStack(spacing: 14) {
            MetaLabel(label)
                .frame(width: 68, alignment: .leading)
            HStack(spacing: AgentSpacing.x2) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .lineLimit(1)
            }
            Spacer(minLength: AgentSpacing.x2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
        .contentShape(.rect)
    }
}

private struct IdeaDirectionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let number: Int
    let idea: IdeaDirection
    let suggestedPillarName: String?
    let isSaved: Bool
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack {
                MetaLabel("Direction \(number)")
                Spacer()
                if let suggestedPillarName {
                    MetaLabel(suggestedPillarName)
                        .foregroundStyle(Color.cyAccent)
                }
            }
            Text(idea.title)
                .font(.agentTitle)
                .foregroundStyle(Color.agentText)

            Text(idea.premise)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)

            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                Image(systemName: "quote.opening")
                    .font(.agentHeadline)
                    .foregroundStyle(Color.actionAccent)
                Text(idea.opening)
                    .font(.agentBody)
                    .italic()
                    .foregroundStyle(Color.agentText)
            }
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                MetaLabel("Why it fits")
                Text(idea.assumption)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }

            Button(isSaved ? "Saved to Idea Bank" : "Save idea", systemImage: isSaved ? "checkmark" : "plus") { select() }
                .buttonStyle(AgentSecondaryButtonStyle())
                .disabled(isSaved)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.panel)
                .stroke(Color.cyAccent.opacity(isSaved ? 0.82 : 0.48), lineWidth: isSaved ? 1.5 : 1)
        }
        .shadow(
            color: Color.cyAccent.opacity(colorScheme == .dark ? (isSaved ? 0.22 : 0.14) : (isSaved ? 0.16 : 0.1)),
            radius: isSaved ? 18 : 12,
            y: 4
        )
    }
}

private struct AgentCaptureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel(label)
            TextField(placeholder, text: $text)
                .font(.agentBody)
                .lineLimit(1)
                .agentSingleLineSubmit()
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
        }
    }
}
