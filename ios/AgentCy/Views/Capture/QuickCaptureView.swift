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

enum CyIdeaFailureMessagePolicy {
    private static let authoredRecoveryMessages: Set<String> = [
        "Cy is offline. Open Claude or Codex on your Mac, or open Access in Settings to use hosted Agent Cy.",
        "Finish your creator profile before asking Cy for ideas."
    ]

    static func creatorMessage(for message: String) -> String {
        if authoredRecoveryMessages.contains(message) {
            return message
        }

        let normalized = message.lowercased()
        // Credit and quota messages are actionable, while unrecognized
        // provider errors should not expose technical details to creators.
        if normalized.contains("credit") || normalized.contains("quota") {
            return message
        }
        if normalized.contains("ended before") || normalized.contains("complete result") {
            return "Cy’s response stopped early. Nothing was saved."
        }
        if normalized.contains("timed out") || normalized.contains("timeout") {
            return "Cy took too long to respond. Nothing was saved."
        }
        return "Cy couldn’t finish the request. Nothing was saved."
    }
}

struct CyProUpsellView: View {
    let message: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                Rectangle()
                    .fill(Color.agentBorder)
                    .frame(height: 1)

                HStack(alignment: .firstTextBaseline) {
                MetaLabel("agent.cy Pro")
                        .foregroundStyle(Color.cyAccent)
                    Spacer()
                    MetaLabel("From spark to ready")
                }
            }

            VStack(spacing: AgentSpacing.x6) {
                AgentCyDisc(diameter: 86) {
                    ZStack {
                        CyAsterisk(color: .cyAccent, size: 38, strokeWidth: 2.2)
                        Circle()
                            .fill(Color.cyAccent.opacity(0.8))
                            .frame(width: 5, height: 5)
                            .offset(y: -36)
                    }
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isRotating ? 360 : 0)))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 7).repeatForever(autoreverses: false),
                        value: isRotating
                    )
                }

                VStack(spacing: AgentSpacing.x2) {
                    Text("Your content team, built in.")
                        .font(.paperInter(size: 28, weight: .semibold, relativeTo: .title))
                        .tracking(-0.56)
                        .multilineTextAlignment(.center)

                    Text("Plan, write, schedule, and manage your content with Cy, without spending hours coordinating or thousands building an agency team.")
                        .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                        .foregroundStyle(Color.agentSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 310)
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("What agent.cy Pro adds")
                        .foregroundStyle(Color.cyAccent)
                    benefitRow("Strategy and ideas grounded in your goals, pillars, and work")
                    benefitRow("Content calendars, tasks, and weekly planning")
                    benefitRow("Hooks, captions, platform versions, and ongoing revisions")
                }
                .padding(AgentSpacing.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cyAccent.opacity(0.055), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyAccent.opacity(0.16), lineWidth: 1)
                }

                VStack(spacing: AgentSpacing.x3) {
                    Text("14 days free · then $8.99 a month")
                        .font(.paperMetadata(size: 11, weight: .medium, relativeTo: .caption))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.agentSecondary)

                    Button("Start 14-day trial", action: primaryAction)
                        .buttonStyle(AgentQuietAccentButtonStyle(size: .page))

                    Button("Not now", action: secondaryAction)
                        .font(.paperInter(size: 14, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Color.agentText)
                        .frame(minHeight: 40)
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
        .padding(.horizontal, AgentSpacing.x2)
        .padding(.top, AgentSpacing.x2)
        .accessibilityLabel(message)
        .onAppear { isRotating = true }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            CyAsterisk(color: .cyAccent, size: 12, strokeWidth: 1.2)
                .frame(width: 16, height: 18)
            Text(text)
                .font(.paperInter(size: 14, weight: .medium, relativeTo: .body))
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The idea composer's optional platform and format tags. A format only makes
/// sense under its platform, so the selection collapses whenever the platform
/// no longer supports it.
enum IdeaPlatformChoicePolicy {
    static func availableFormats(
        destinationID: UUID?,
        formats: [PublishingFormat]
    ) -> [PublishingFormat] {
        guard let destinationID else { return [] }
        return formats
            .filter { $0.destinationID == destinationID && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    static func normalizedSelection(
        destinationID: UUID?,
        formatID: UUID?,
        destinations: [PublishingDestination],
        formats: [PublishingFormat]
    ) -> (destinationID: UUID?, formatID: UUID?) {
        guard let destinationID,
              destinations.contains(where: { $0.id == destinationID && !$0.isArchived })
        else { return (nil, nil) }
        let formatID = availableFormats(destinationID: destinationID, formats: formats)
            .first { $0.id == formatID }?.id
        return (destinationID, formatID)
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

    private enum QuickTaskType {
        case post
        case focus
    }

#if targetEnvironment(macCatalyst)
    private enum DesktopInlinePicker: Hashable {
        case ideaPillar
        case ideaPlatform
        case ideaFormat
        case taskFocus
        case taskPillar
        case taskPriority
        case taskDue
        case taskRecurrence
    }
#endif

    private let onExit: (() -> Void)?

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var kind: CaptureKind = .spark
    @State private var ideaTitle = ""
    @State private var ideaNotes = ""
    @State private var ideaPillarID: UUID?
    @State private var ideaDestinationID: UUID?
    @State private var ideaFormatID: UUID?
    @State private var postTitle = ""
    @State private var postNotes = ""
    @State private var postPillarID: UUID?
    @State private var postDestinationID = PublishingCatalog.instagramID
    @State private var postFormatID = PublishingCatalog.instagramReelID
    @State private var postSocialAccountID: UUID?
    @State private var postDurationSeconds = ContentFormat.shortForm.defaultDuration
    @State private var postIncludesTime = false
    @State private var hasPostTargetDate = false
    @State private var taskTitle = ""
    @State private var taskNotes = ""
    @State private var taskPillarID: UUID?
    @State private var taskKind: CreatorTaskKind = .planning
    @State private var taskLane: TaskLane = .pillar
    @State private var taskPriority: TaskPriority = .none
    @State private var taskRecurrence: TaskRecurrenceFrequency = .none
    @State private var taskFocusAssignment: DailyFocusTaskAssignment?
    @State private var quickTaskType: QuickTaskType?
    @State private var showPostTaskCreation = false
    @State private var didSavePostTask = false
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
    @State private var quickPostDraft: QuickPostDraft?
    @State private var showPostDevelopment = false
    @State private var showAccess = false
    @State private var selectedDetent: PresentationDetent = .large
#if targetEnvironment(macCatalyst)
    @State private var desktopInlinePicker: DesktopInlinePicker?
#endif
    @FocusState private var focusedWritingField: WritingField?

    init(onExit: (() -> Void)? = nil) {
        self.onExit = onExit
    }

    private var pillars: [Pillar] {
        allPillars.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    private var socialAccounts: [CreatorSocialAccount] {
        allSocialAccounts.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private enum WritingField: Hashable {
        case ideaNotes
        case postNotes
        case taskNotes
    }

    var body: some View {
        Group {
            if onExit == nil {
                captureNavigation
                    .presentationDetents([.height(620), .large], selection: $selectedDetent)
                    .agentSheetDragIndicator()
            } else {
                captureNavigation
            }
        }
        .agentKeyboardDismissal()
    }

    private var captureNavigation: some View {
        NavigationStack {
            Group {
                if !showingCySuggestions, kind == .post, let quickPostDraft {
                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        captureKindRail
                            .padding(.horizontal, AgentLayout.pageMargin)
                            .padding(.top, AgentSpacing.x4)

                        ResumablePostEditorView(
                            brief: quickPostDraft.brief,
                            output: quickPostDraft.output,
                            contextLabel: "New post",
                            bottomActionClearance: AgentSpacing.x3,
                            showsEditorChrome: false,
                            onSpark: { showPostDevelopment = true }
                        )
                    }
                    .frame(maxWidth: AgentQuickAddLayout.desktopEditorWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                            if showingCySuggestions {
                                cySuggestionsContent
                            } else {
                                captureKindRail

                                switch kind {
                                case .spark: sparkComposer
                                case .post: postComposer
                                case .task:
                                    if quickTaskType == .focus {
                                        taskComposer
                                    } else {
                                        taskTypeChooser
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AgentLayout.pageMargin)
                        .padding(.top, AgentSpacing.x4)
                        .agentBottomNavigationClearance()
                        .frame(maxWidth: AgentQuickAddLayout.desktopContentWidth, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if onExit != nil {
                    embeddedToolbar
                }
            }
            .navigationTitle(onExit == nil ? navigationTitle : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(onExit == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if onExit == nil {
                        AgentToolbarIconButton(title: "Close", icon: .close) { closeCapture() }
                    } else {
                        AgentToolbarIconButton(title: "Back to Quick Add", icon: .back) { closeCapture() }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    if !showingCySuggestions,
                       kind == .spark || (kind == .task && quickTaskType == .focus) {
                        saveCaptureToolbarButton
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background(Color.agentCanvas.ignoresSafeArea())
            .foregroundStyle(Color.agentText)
            .task {
                if let plannedDate = appModel.quickCaptureTargetDate {
                    targetDate = plannedDate
                    hasPostTargetDate = true
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
                        quickTaskType = .focus
                    }
                    appModel.quickCaptureTaskLane = nil
                    if let focusAssignment = appModel.quickCaptureTaskFocus {
                        taskFocusAssignment = focusAssignment
                        quickTaskType = .focus
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
#if DEBUG
                if QuickCaptureIdeasRuntimeFixture.requestsLoadedIdeas() {
                    kind = .spark
                    isCySuggestionsMode = true
                    ideas = QuickCaptureIdeasRuntimeFixture.directions
                    ideaPhase = .loaded
                    selectedDetent = .large
                }
#endif
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .post { beginQuickPostDraft() }
                if newKind != .task { quickTaskType = nil }
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
                        .agentDesktopWorkspaceModal()
                }
            }
            .sheet(isPresented: $showAccess) {
                NavigationStack { AccessSettingsView() }
                    .presentationDetents([.large])
                    .agentDesktopWorkspaceModal()
            }
            .sheet(isPresented: $showTaskDueDatePicker) {
                CaptureTaskDueDateSheet(
                    date: $targetDate,
                    hasDueDate: $addTarget,
                    includesTime: $taskIncludesTime,
                    allowsRemoval: TaskDueDatePolicy.allowsRemoval(recurrence: taskRecurrence)
                )
                .presentationDetents([.large])
                .agentDesktopWorkspaceModal()
            }
            .sheet(isPresented: $showPostTaskCreation, onDismiss: {
                if didSavePostTask {
                    finishCapture()
                } else {
                    quickTaskType = nil
                }
            }) {
                PostTaskCreationFlow {
                    didSavePostTask = true
                }
                .presentationDetents([.large])
                .agentSheetDragIndicator()
                .agentDesktopWorkspaceModal()
            }
        }
    }

    private var embeddedToolbar: some View {
        HStack(spacing: AgentSpacing.x3) {
            AgentToolbarIconButton(title: "Back to Quick Add", icon: .back, action: closeCapture)

            Text(navigationTitle)
                .font(.agentHeadline)
                .foregroundStyle(Color.agentText)
                .lineLimit(1)

            Spacer(minLength: AgentSpacing.x4)

            if !showingCySuggestions,
               kind == .spark || (kind == .task && quickTaskType == .focus) {
                saveCaptureToolbarButton
            }
        }
        .padding(.horizontal, AgentSpacing.x5)
        .agentQuickAddHeaderSurface()
        .zIndex(1)
    }

    private var saveCaptureToolbarButton: some View {
        AgentToolbarIconButton(
            title: kind == .spark ? "Save idea" : "Save task",
            icon: .check,
            isEnabled: canSaveToolbarItem
        ) {
            if kind == .spark {
                saveIdea()
            } else {
                saveTask()
            }
        }
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
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            switch ideaPhase {
            case .upgradeRequired(let message):
                cyProUpsell(message: message)
            case .loading:
                suggestionsHeader(
                    title: "Finding ideas.",
                    subtitle: "Using your goals, pillars, and saved work.",
                    isLoading: true
                )
                CyIdeaLoadingStack()
            case .loaded:
                suggestionsHeader(
                    title: "Three ways in.",
                    subtitle: "Save what fits. Unsaved ideas disappear when you leave."
                )
                cyIdeaDirections
            case .unavailable(let message):
                cyUnavailableNotice(message: message)
            case .idle:
                EmptyView()
            }
        }
    }

    private func suggestionsHeader(
        title: String,
        subtitle: String,
        isLoading: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x2) {
                if isLoading {
                    CyThinkingMark(color: .cyAccent, size: 15)
                } else {
                    CyAsterisk(color: .cyAccent, size: 15, strokeWidth: 1.4)
                }
                MetaLabel("Cy · Ideas")
                    .foregroundStyle(Color.cyAccent)

                Spacer(minLength: AgentSpacing.x3)

                if !isLoading {
                    Button {
                        Task { await loadIdeas() }
                    } label: {
                        Text("Try again")
                            .font(.agentMetadata)
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.cyAccent)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Replaces these ideas with three new suggestions")
                }
            }

            Text(title)
                .font(.agentDisplay)
                .tracking(-0.6)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cyProUpsell(message: String) -> some View {
        CyProUpsellView(
            message: message,
            primaryAction: { showAccess = true },
            secondaryAction: closeCapture
        )
    }

    private func cyUnavailableNotice(message: String) -> some View {
        paperCyState(kicker: "Cy · paused") {
            VStack(spacing: AgentSpacing.x4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.agentText.opacity(0.3), lineWidth: 1.5)
                    AgentIconView(.warning, size: 19)
                        .foregroundStyle(Color.agentText)
                }
                .frame(width: 48, height: 48)

                Text("Couldn’t make those ideas")
                    .font(.paperInter(size: 20, weight: .semibold, relativeTo: .title3))
                    .tracking(-0.2)
                    .multilineTextAlignment(.center)

                Text(CyIdeaFailureMessagePolicy.creatorMessage(for: message))
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
                .buttonStyle(AgentPrimaryButtonStyle())

            Button(secondaryTitle, action: secondaryAction)
                .font(.paperInter(size: 14, weight: .medium, relativeTo: .body))
                .foregroundStyle(Color.agentText)
                .underline(true, color: Color.agentText)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
    }

    private var sparkComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            MetaLabel("New idea")

            TextField("Idea title", text: $ideaTitle, axis: .vertical)
                .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                .tracking(-0.56)
                .lineLimit(1...3)

            VStack(spacing: 0) {
#if targetEnvironment(macCatalyst)
                Button {
                    toggleDesktopPicker(.ideaPillar)
                } label: {
                    IdeaCaptureSetupRow(
                        label: "Pillar",
                        value: selectedIdeaPillar?.name ?? "No pillar",
                        color: selectedIdeaPillar.map {
                            Color(agentHex: $0.resolvedColorHex(in: activePillars))
                        },
                        trailingIcon: desktopInlinePicker == .ideaPillar ? .collapse : .expand
                    )
                }
                .buttonStyle(.plain)

                if desktopInlinePicker == .ideaPillar {
                    desktopChoicePanel {
                        desktopChoiceRow(
                            title: "No pillar",
                            isSelected: ideaPillarID == nil
                        ) {
                            ideaPillarID = nil
                            desktopInlinePicker = nil
                        }
                        ForEach(activePillars) { pillar in
                            desktopChoiceRow(
                                title: pillar.name,
                                color: Color(agentHex: pillar.resolvedColorHex(in: activePillars)),
                                isSelected: ideaPillarID == pillar.id
                            ) {
                                ideaPillarID = pillar.id
                                desktopInlinePicker = nil
                            }
                        }
                    }
                }
#else
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
                        value: selectedIdeaPillar?.name ?? "No pillar",
                        color: selectedIdeaPillar.map {
                            Color(agentHex: $0.resolvedColorHex(in: activePillars))
                        }
                    )
                }
#endif

#if targetEnvironment(macCatalyst)
                Button {
                    toggleDesktopPicker(.ideaPlatform)
                } label: {
                    IdeaCaptureSetupRow(
                        label: "Platform",
                        value: selectedIdeaDestination?.name ?? "No platform",
                        trailingIcon: desktopInlinePicker == .ideaPlatform ? .collapse : .expand
                    )
                }
                .buttonStyle(.plain)

                if desktopInlinePicker == .ideaPlatform {
                    desktopChoicePanel {
                        desktopChoiceRow(
                            title: "No platform",
                            isSelected: ideaDestinationID == nil
                        ) {
                            selectIdeaDestination(nil)
                            desktopInlinePicker = nil
                        }
                        ForEach(activeIdeaDestinations) { destination in
                            desktopChoiceRow(
                                title: destination.name,
                                isSelected: ideaDestinationID == destination.id
                            ) {
                                selectIdeaDestination(destination.id)
                                desktopInlinePicker = nil
                            }
                        }
                    }
                }

                if ideaDestinationID != nil {
                    Button {
                        toggleDesktopPicker(.ideaFormat)
                    } label: {
                        IdeaCaptureSetupRow(
                            label: "Format",
                            value: selectedIdeaFormat?.name ?? "No format",
                            trailingIcon: desktopInlinePicker == .ideaFormat ? .collapse : .expand
                        )
                    }
                    .buttonStyle(.plain)

                    if desktopInlinePicker == .ideaFormat {
                        desktopChoicePanel {
                            desktopChoiceRow(
                                title: "No format",
                                isSelected: ideaFormatID == nil
                            ) {
                                ideaFormatID = nil
                                desktopInlinePicker = nil
                            }
                            ForEach(ideaAvailableFormats) { format in
                                desktopChoiceRow(
                                    title: format.name,
                                    isSelected: ideaFormatID == format.id
                                ) {
                                    ideaFormatID = format.id
                                    desktopInlinePicker = nil
                                }
                            }
                        }
                    }
                }
#else
                Menu {
                    Button("No platform") { selectIdeaDestination(nil) }
                    ForEach(activeIdeaDestinations) { destination in
                        Button {
                            selectIdeaDestination(destination.id)
                        } label: {
                            Text(ideaDestinationID == destination.id ? "\(destination.name) ✓" : destination.name)
                        }
                    }
                } label: {
                    IdeaCaptureSetupRow(
                        label: "Platform",
                        value: selectedIdeaDestination?.name ?? "No platform"
                    )
                }

                if ideaDestinationID != nil {
                    Menu {
                        Button("No format") { ideaFormatID = nil }
                        ForEach(ideaAvailableFormats) { format in
                            Button {
                                ideaFormatID = format.id
                            } label: {
                                Text(ideaFormatID == format.id ? "\(format.name) ✓" : format.name)
                            }
                        }
                    } label: {
                        IdeaCaptureSetupRow(
                            label: "Format",
                            value: selectedIdeaFormat?.name ?? "No format"
                        )
                    }
                }
#endif
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
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                    .focused($focusedWritingField, equals: .ideaNotes)
            }
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var selectedIdeaPillar: Pillar? { activePillars.first { $0.id == ideaPillarID } }
    private var selectedTaskPillar: Pillar? { activePillars.first { $0.id == taskPillarID } }

    private var activeIdeaDestinations: [PublishingDestination] { destinations.filter { !$0.isArchived } }
    private var selectedIdeaDestination: PublishingDestination? {
        activeIdeaDestinations.first { $0.id == ideaDestinationID }
    }
    private var ideaAvailableFormats: [PublishingFormat] {
        IdeaPlatformChoicePolicy.availableFormats(destinationID: ideaDestinationID, formats: formats)
    }
    private var selectedIdeaFormat: PublishingFormat? {
        ideaAvailableFormats.first { $0.id == ideaFormatID }
    }

    private func selectIdeaDestination(_ destinationID: UUID?) {
        let selection = IdeaPlatformChoicePolicy.normalizedSelection(
            destinationID: destinationID,
            formatID: ideaFormatID,
            destinations: destinations,
            formats: formats
        )
        ideaDestinationID = selection.destinationID
        ideaFormatID = selection.formatID
    }

#if targetEnvironment(macCatalyst)
    private func toggleDesktopPicker(_ picker: DesktopInlinePicker) {
        desktopInlinePicker = desktopInlinePicker == picker ? nil : picker
    }

    private func desktopChoicePanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, AgentSpacing.x1)
        .background(Color.agentSelectionFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
    }

    private func desktopChoiceRow(
        title: String,
        color: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x3) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                Spacer(minLength: AgentSpacing.x3)
                if isSelected {
                    AgentIconView(.check, size: 12)
                        .foregroundStyle(Color.agentText)
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 42)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .agentHoverRow(cornerRadius: 0)
    }
#endif

    private var cyIdeaDirections: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                IdeaDirectionRow(
                    number: index + 1,
                    idea: idea,
                    suggestedPillarName: suggestedPillar(for: idea)?.name,
                    suggestedPillarColor: suggestedPillar(for: idea).map {
                        Color(agentHex: $0.resolvedColorHex(in: activePillars))
                    },
                    isSaved: savedGeneratedIdeaIDs.contains(idea.id)
                ) {
                    saveGeneratedIdea(idea)
                }
            }
        }
    }

    private var taskTypeChooser: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Task type")
                Text("What kind of task is this?")
                    .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                    .tracking(-0.56)
                Text("Choose where the task belongs before adding its details.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                taskTypeButton(
                    title: "Post task",
                    detail: "Connected to a scheduled post.",
                    icon: .calendar,
                    showsDivider: true
                ) {
                    quickTaskType = .post
                    didSavePostTask = false
                    showPostTaskCreation = true
                }

                taskTypeButton(
                    title: "Focus task",
                    detail: "Standalone or recurring work for a focus day.",
                    icon: .tasks,
                    showsDivider: false
                ) {
                    taskLane = .production
                    quickTaskType = .focus
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
        }
    }

    private func taskTypeButton(
        title: String,
        detail: String,
        icon: AgentIcon,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x4) {
                AgentIconView(icon, size: 18)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title)
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AgentIconView(.forward, size: 12)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(minHeight: 76)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }

    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            TextField("What's the task?", text: $taskTitle, axis: .vertical)
                .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                .tracking(-0.56)
                .lineLimit(1...3)

            VStack(spacing: 0) {
                if taskLane == .production {
                    if let taskFocusAssignment {
                        IdeaCaptureSetupRow(label: "Focus", value: taskFocusAssignment.title)
                    } else {
#if targetEnvironment(macCatalyst)
                        Button {
                            toggleDesktopPicker(.taskFocus)
                        } label: {
                            IdeaCaptureSetupRow(
                                label: "Focus",
                                value: taskKind.title,
                                trailingIcon: desktopInlinePicker == .taskFocus ? .collapse : .expand
                            )
                        }
                        .buttonStyle(.plain)
                        if desktopInlinePicker == .taskFocus {
                            desktopChoicePanel {
                                ForEach(CreatorTaskKind.allCases) { kind in
                                    desktopChoiceRow(
                                        title: kind.title,
                                        isSelected: taskKind == kind
                                    ) {
                                        taskKind = kind
                                        desktopInlinePicker = nil
                                    }
                                }
                            }
                        }
#else
                        Menu {
                            ForEach(CreatorTaskKind.allCases) { kind in
                                Button(kind.title) { taskKind = kind }
                            }
                        } label: {
                            IdeaCaptureSetupRow(label: "Focus", value: taskKind.title)
                        }
#endif
                    }
                } else {
#if targetEnvironment(macCatalyst)
                    Button {
                        toggleDesktopPicker(.taskPillar)
                    } label: {
                        IdeaCaptureSetupRow(
                            label: "Pillar",
                            value: selectedTaskPillar?.name ?? "No pillar",
                            color: selectedTaskPillar.map {
                                Color(agentHex: $0.resolvedColorHex(in: activePillars))
                            },
                            trailingIcon: desktopInlinePicker == .taskPillar ? .collapse : .expand
                        )
                    }
                    .buttonStyle(.plain)
                    if desktopInlinePicker == .taskPillar {
                        desktopChoicePanel {
                            desktopChoiceRow(
                                title: "No pillar",
                                isSelected: taskPillarID == nil
                            ) {
                                taskPillarID = nil
                                desktopInlinePicker = nil
                            }
                            ForEach(activePillars) { pillar in
                                desktopChoiceRow(
                                    title: pillar.name,
                                    color: Color(agentHex: pillar.resolvedColorHex(in: activePillars)),
                                    isSelected: taskPillarID == pillar.id
                                ) {
                                    taskPillarID = pillar.id
                                    desktopInlinePicker = nil
                                }
                            }
                        }
                    }
#else
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
                            value: selectedTaskPillar?.name ?? "No pillar",
                            color: selectedTaskPillar.map {
                                Color(agentHex: $0.resolvedColorHex(in: activePillars))
                            }
                        )
                    }
#endif
                }

#if targetEnvironment(macCatalyst)
                Button {
                    toggleDesktopPicker(.taskPriority)
                } label: {
                    IdeaCaptureSetupRow(
                        label: "Priority",
                        value: taskPriority.title,
                        trailingIcon: desktopInlinePicker == .taskPriority ? .collapse : .expand
                    )
                }
                .buttonStyle(.plain)
                if desktopInlinePicker == .taskPriority {
                    desktopChoicePanel {
                        ForEach(TaskPriority.selectableCases) { priority in
                            desktopChoiceRow(
                                title: priority.title,
                                isSelected: taskPriority == priority
                            ) {
                                taskPriority = priority
                                desktopInlinePicker = nil
                            }
                        }
                    }
                }
#else
                Menu {
                    ForEach(TaskPriority.selectableCases) { priority in
                        Button(priority.title) { taskPriority = priority }
                    }
                } label: {
                    IdeaCaptureSetupRow(label: "Priority", value: taskPriority.title)
                }
#endif

#if targetEnvironment(macCatalyst)
                Button {
                    toggleDesktopPicker(.taskDue)
                } label: {
                    IdeaCaptureSetupRow(
                        label: "Due",
                        value: taskDueDateLabel,
                        trailingIcon: desktopInlinePicker == .taskDue ? .collapse : .expand
                    )
                }
                .buttonStyle(.plain)
                if desktopInlinePicker == .taskDue {
                    desktopTaskDueEditor
                }
#else
                Button {
                    showTaskDueDatePicker = true
                } label: {
                    IdeaCaptureSetupRow(label: "Due", value: taskDueDateLabel)
                }
                .buttonStyle(.plain)
#endif

                if taskLane == .production {
#if targetEnvironment(macCatalyst)
                    Button {
                        toggleDesktopPicker(.taskRecurrence)
                    } label: {
                        IdeaCaptureSetupRow(
                            label: "Repeat",
                            value: taskRecurrence.title,
                            trailingIcon: desktopInlinePicker == .taskRecurrence ? .collapse : .expand
                        )
                    }
                    .buttonStyle(.plain)
                    if desktopInlinePicker == .taskRecurrence {
                        desktopChoicePanel {
                            ForEach(TaskRecurrenceFrequency.allCases) { recurrence in
                                desktopChoiceRow(
                                    title: recurrence.title,
                                    isSelected: taskRecurrence == recurrence
                                ) {
                                    taskRecurrence = recurrence
                                    desktopInlinePicker = nil
                                }
                            }
                        }
                    }
#else
                    Menu {
                        ForEach(TaskRecurrenceFrequency.allCases) { recurrence in
                            Button(recurrence.title) { taskRecurrence = recurrence }
                        }
                    } label: {
                        IdeaCaptureSetupRow(label: "Repeat", value: taskRecurrence.title)
                    }
#endif
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
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                    .focused($focusedWritingField, equals: .taskNotes)
            }

            DraftSubtaskComposer(subtasks: $draftSubtasks)
        }
        .onChange(of: taskRecurrence) { _, recurrence in
            if recurrence != .none { addTarget = true }
        }
        .onChange(of: taskLane) { _, lane in
            if lane != .production { taskRecurrence = .none }
        }
    }

#if targetEnvironment(macCatalyst)
    private var desktopTaskDueEditor: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            PillarCalendarDatePicker(
                date: $targetDate,
                pillarMarkers: [],
                cellHeight: 38,
                dayDiameter: 32
            )

            if taskIncludesTime {
                HStack(alignment: .top, spacing: AgentSpacing.x4) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel("Time")
                        Text(targetDate.formatted(date: .omitted, time: .shortened))
                            .font(.agentTitle)
                            .monospacedDigit()
                    }
                    Spacer(minLength: AgentSpacing.x4)
                    desktopTaskTimeAdjustment(
                        title: "Hour",
                        value: String(format: "%02d", Calendar.current.component(.hour, from: targetDate)),
                        component: .hour
                    )
                    desktopTaskTimeAdjustment(
                        title: "Minute",
                        value: String(format: "%02d", Calendar.current.component(.minute, from: targetDate)),
                        component: .minute
                    )
                }
            }

            HStack(spacing: AgentSpacing.x3) {
                Toggle("Include a time", isOn: $taskIncludesTime)
                    .font(.agentSubtext.weight(.semibold))
                    .tint(Color.actionAccent)

                Spacer(minLength: AgentSpacing.x3)

                Button("Remove") {
                    addTarget = false
                    taskIncludesTime = false
                    desktopInlinePicker = nil
                }
                .font(.agentSubtext)
                .foregroundStyle(Color.agentDestructive)
                .buttonStyle(.plain)

                Button("Set date") {
                    addTarget = true
                    desktopInlinePicker = nil
                }
                .buttonStyle(AgentQuietAccentButtonStyle(isFullWidth: false))
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSelectionFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
    }

    private func desktopTaskTimeAdjustment(
        title: String,
        value: String,
        component: Calendar.Component
    ) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            Button {
                adjustTaskTime(component, by: -1)
            } label: {
                Text("−")
                    .font(.agentSubtext.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(Color.agentSurface, in: .circle)
            .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))

            VStack(spacing: 1) {
                Text(value)
                    .font(.agentSubtext.weight(.semibold))
                    .monospacedDigit()
                Text(title)
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(minWidth: 42)

            Button {
                adjustTaskTime(component, by: 1)
            } label: {
                Text("+")
                    .font(.agentSubtext.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(Color.agentSurface, in: .circle)
            .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
        }
    }

    private func adjustTaskTime(_ component: Calendar.Component, by value: Int) {
        guard let adjustedDate = Calendar.current.date(byAdding: component, value: value, to: targetDate) else { return }
        targetDate = adjustedDate
    }
#endif

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
            finishCapture()
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

            DatePicker(
                "Scheduled",
                selection: Binding(
                    get: { targetDate },
                    set: { newDate in
                        targetDate = newDate
                        hasPostTargetDate = true
                    }
                ),
                displayedComponents: .date
            )

            if hasPostTargetDate {
                Toggle("Include a time", isOn: $postIncludesTime)
                    .font(.agentBody.weight(.semibold))
                    .tint(Color.actionAccent)

                if postIncludesTime {
                    DatePicker("Time", selection: $targetDate, displayedComponents: .hourAndMinute)
                }
            }

            Button {
                savePost(title: postTitle)
            } label: {
                AgentIconLabel(title: "Save post", icon: .check)
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
        if case .upgradeRequired = ideaPhase, showingCySuggestions { return "Upgrade" }
        if quickPostDraft != nil { return "New post" }
        return switch kind {
        case .spark: "New idea"
        case .post: "New post"
        case .task: quickTaskType == .focus ? "New focus task" : "New task"
        }
    }

    private var taskDueDateLabel: String {
        guard addTarget else { return "No due date" }
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
        case .post: "Choose the essentials. Build out the post when you need it."
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
            if requiresUpgrade { selectedDetent = .large }
        case .cancelled:
            ideaPhase = .idle
            isCySuggestionsMode = false
        }
    }

    private func closeCapture() {
        if showingCySuggestions {
            appModel.quickCaptureStartsWithIdeas = false
            appModel.quickCaptureTargetDate = nil
            finishCapture()
            return
        }
        updateSavedIdeaFromForm()
        preserveUnfinishedDrafts()
        finishCapture()
    }

    private func finishCapture() {
        if let onExit {
            onExit()
        } else {
            dismiss()
        }
    }

    private func saveIdea() {
        let title = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if savedBrief != nil {
            updateSavedIdeaFromForm()
            finishCapture()
            return
        }
        let notes = ideaNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let platformChoice = IdeaPlatformChoicePolicy.normalizedSelection(
            destinationID: ideaDestinationID,
            formatID: ideaFormatID,
            destinations: destinations,
            formats: formats
        )
        savedBrief = appModel.createSpark(
            text: notes.isEmpty ? title : notes,
            source: .text,
            title: title,
            notes: notes,
            pillarID: ideaPillarID,
            preferredDestinationID: platformChoice.destinationID,
            preferredFormatID: platformChoice.formatID,
            targetDate: appModel.quickCaptureTargetDate,
            context: context
        )
        didSaveIdea = savedBrief != nil
        if didSaveIdea {
            appModel.quickCaptureTargetDate = nil
            finishCapture()
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
        let platformChoice = IdeaPlatformChoicePolicy.normalizedSelection(
            destinationID: ideaDestinationID,
            formatID: ideaFormatID,
            destinations: destinations,
            formats: formats
        )
        savedBrief.title = title
        savedBrief.notes = notes
        savedBrief.premise = notes.isEmpty ? title : notes
        savedBrief.pillarID = ideaPillarID
        savedBrief.preferredDestinationID = platformChoice.destinationID
        savedBrief.preferredFormatID = platformChoice.formatID
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
            targetDate: hasPostTargetDate ? targetDate : nil,
            includesTargetTime: hasPostTargetDate && postIncludesTime,
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
            targetDate: hasPostTargetDate ? targetDate : nil,
            includesTargetTime: hasPostTargetDate && postIncludesTime,
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
                targetDate: hasPostTargetDate ? targetDate : nil,
                includesTargetTime: hasPostTargetDate && postIncludesTime,
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

struct DraftCaptureSubtask: Identifiable {
    let id = UUID()
    var title = ""
    var isCompleted = false
}

struct DraftSubtaskComposer: View {
    @Binding var subtasks: [DraftCaptureSubtask]
    @State private var isAddingSubtask = false
    @State private var newSubtaskTitle = ""
    @State private var newSubtaskFocused = false

    private var completedCount: Int {
        subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Subtasks")
                    .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                Spacer()
                MetaLabel("\(completedCount)")
            }

            ForEach($subtasks) { $subtask in
                DraftCaptureSubtaskRow(subtask: $subtask)
            }

            if isAddingSubtask {
                HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: AgentSpacing.x2) {
                    AgentTaskCheckboxPlaceholder()

                    PersistentSubmitTextField(
                        text: $newSubtaskTitle,
                        isFocused: $newSubtaskFocused,
                        placeholder: "Add a subtask"
                    ) {
                        confirmSubtaskAndContinue()
                    }
                    .frame(minHeight: 44)
                    .accessibilityHint("Press Return to save and add another subtask")
                }
                .padding(.vertical, AgentSpacing.x2)
            } else {
                AgentBlockAddActionButton(title: "Add sub-task") {
                    isAddingSubtask = true
                    Task { @MainActor in
                        await Task.yield()
                        newSubtaskFocused = true
                    }
                }
                .padding(.top, AgentSpacing.x2)
            }
        }
    }

    private func confirmSubtaskAndContinue() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var subtask = DraftCaptureSubtask()
        subtask.title = title
        subtasks.append(subtask)
        newSubtaskTitle = ""
        newSubtaskFocused = true
    }
}

struct DraftCaptureSubtaskRow: View {
    @Binding var subtask: DraftCaptureSubtask

    var body: some View {
        HStack(alignment: AgentTaskCheckboxMetrics.rowAlignment, spacing: AgentSpacing.x3) {
            AgentTaskCheckbox(
                isCompleted: subtask.isCompleted,
                color: Color.agentText,
                accessibilityLabel: subtask.isCompleted
                    ? "Mark subtask open"
                    : "Mark subtask complete"
            ) {
                subtask.isCompleted.toggle()
            }

            TextField("Subtask", text: $subtask.title, axis: .vertical)
                .font(.paperInter(size: 15, weight: .medium, relativeTo: .body))
                .lineLimit(1...3)
                .strikethrough(subtask.isCompleted)
        }
        .frame(minHeight: 48)
        .padding(.vertical, AgentSpacing.x1)
    }
}

struct CaptureTaskDueDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var date: Date
    @Binding private var hasDueDate: Bool
    @Binding private var includesTime: Bool
    private let allowsRemoval: Bool
    @State private var selectedDate: Date
    @State private var selectedIncludesTime: Bool

    init(
        date: Binding<Date>,
        hasDueDate: Binding<Bool>,
        includesTime: Binding<Bool>,
        allowsRemoval: Bool = true
    ) {
        _date = date
        _hasDueDate = hasDueDate
        _includesTime = includesTime
        self.allowsRemoval = allowsRemoval
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

                    PillarCalendarDatePicker(date: $selectedDate, pillarMarkers: [])
                        .frame(minHeight: 330)

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

                    if hasDueDate, allowsRemoval {
                        Button("Remove due date", role: .destructive) {
                            let cleared = CaptureTaskDueDatePolicy.removingDate(
                                from: CaptureTaskDueDateState(
                                    hasDueDate: hasDueDate,
                                    includesTime: includesTime
                                )
                            )
                            hasDueDate = cleared.hasDueDate
                            includesTime = cleared.includesTime
                            dismiss()
                        }
                        .font(.agentSubtext.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    } else if hasDueDate {
                        Text("Repeating tasks need a due date.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x12)
            }
            .navigationTitle("Due date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                        Button("Set date") {
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
    var trailingIcon: AgentIcon = .forward

    var body: some View {
        HStack(spacing: 14) {
            // Wide enough for the longest tracked label ("PLATFORM",
            // "PRIORITY") on device — 68 wrapped the final letter.
            MetaLabel(label)
                .frame(width: 92, alignment: .leading)
            HStack(spacing: AgentSpacing.x2) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .lineLimit(1)
            }
            Spacer(minLength: AgentSpacing.x2)
            AgentIconView(trailingIcon, size: 12)
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
    let suggestedPillarColor: Color?
    let isSaved: Bool
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x2) {
                if let suggestedPillarColor {
                    Circle()
                        .fill(suggestedPillarColor)
                        .frame(width: 7, height: 7)
                }
                MetaLabel(suggestedPillarName ?? "No pillar")
                    .foregroundStyle(Color.cyAccent)

                Spacer()
                MetaLabel("Idea \(number)")
                    .foregroundStyle(Color.agentSecondary)
            }

            Text(idea.title)
                .font(.paperInter(size: 18, weight: .semibold, relativeTo: .headline))
                .tracking(-0.2)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)

            Text(idea.premise)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("“\(idea.opening)”")
                .font(.paperInter(size: 14, weight: .medium, relativeTo: .body))
                .italic()
                .foregroundStyle(Color.agentText)
                .lineSpacing(2)
                .padding(AgentSpacing.x3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.cyAccent.opacity(colorScheme == .dark ? 0.09 : 0.045),
                    in: .rect(cornerRadius: 12)
                )

            Button(action: select) {
                HStack(spacing: 6) {
                    Text(isSaved ? "Saved to Idea Bank" : "Save idea")
                    AgentIconView(isSaved ? .check : .arrowRight)
                        .font(.agentInter(size: 11, weight: .semibold, relativeTo: .caption))
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.cyAccent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isSaved)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, AgentSpacing.x4)
        .background(
            Color.cyAccent.opacity(
                colorScheme == .dark ? (isSaved ? 0.14 : 0.10) : (isSaved ? 0.085 : 0.055)
            ),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    Color.cyAccent.opacity(
                        colorScheme == .dark ? (isSaved ? 0.48 : 0.32) : (isSaved ? 0.30 : 0.18)
                    ),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CyIdeaLoadingStack: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: AgentSpacing.x3) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    HStack {
                        Capsule()
                            .fill(Color.cyAccent.opacity(0.18))
                            .frame(width: CGFloat(70 + (index * 12)), height: 8)
                        Spacer()
                        Capsule()
                            .fill(Color.agentText.opacity(0.07))
                            .frame(width: 42, height: 8)
                    }

                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.agentText.opacity(0.10))
                        .frame(width: CGFloat(170 + (index * 18)), height: 18)

                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.agentText.opacity(0.07))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.agentText.opacity(0.07))
                            .frame(width: CGFloat(210 + (index * 16)), height: 10)
                    }

                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cyAccent.opacity(colorScheme == .dark ? 0.09 : 0.045))
                        .frame(height: 48)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, AgentSpacing.x4)
                .background(
                    Color.cyAccent.opacity(colorScheme == .dark ? 0.08 : 0.045),
                    in: .rect(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyAccent.opacity(colorScheme == .dark ? 0.24 : 0.14), lineWidth: 1)
                }
                .accessibilityLabel("Finding idea \(index + 1)")
            }
        }
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

#if DEBUG
/// Headless route for the acceptance capture of the Cy suggestions state.
///
/// `-agentCyPreviewSheet quickCapture` alone lands on the empty New idea form,
/// which carries none of the sites Task 6 touched. This flag drops the sheet
/// straight into `ideaPhase == .loaded` with three fixed directions, so the
/// `IdeaDirectionRow` cards (whose accent glow Task 6 deleted) are on record
/// without calling the live Cy service.
enum QuickCaptureIdeasRuntimeFixture {
    static func requestsLoadedIdeas(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-agentCyPreviewQuickCaptureIdeas")
    }

    /// Stable ids so a capture rerun produces the same three cards.
    static let directions: [IdeaDirection] = [
        IdeaDirection(
            id: UUID(uuidString: "3A1E0001-0000-4000-8000-000000000001")!,
            title: "The quiet week nobody posts about",
            premise: "Show the ordinary Tuesday behind the launch reel — the part your audience actually lives in.",
            opening: "Everyone films the launch. Nobody films the Tuesday before it.",
            assumption: "Your audience is tired of highlight reels and trusts process more than polish."
        ),
        IdeaDirection(
            id: UUID(uuidString: "3A1E0001-0000-4000-8000-000000000002")!,
            title: "One tool, three jobs",
            premise: "Take the tool you reach for most and show the two uses nobody expects from it.",
            opening: "You bought this for one thing. It quietly does three.",
            assumption: "Practical range beats novelty for the people already following you."
        ),
        IdeaDirection(
            id: UUID(uuidString: "3A1E0001-0000-4000-8000-000000000003")!,
            title: "The advice you stopped giving",
            premise: "Name a rule you used to repeat and explain what changed your mind about it.",
            opening: "I told people this for two years. I was wrong about half of it.",
            assumption: "Revising a public position reads as credibility, not as weakness."
        )
    ]
}
#endif
