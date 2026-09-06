import SwiftData
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PostDraftSetupPicker: String, Identifiable {
    case pillar
    case platform
    case format
    case status
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pillar: "Choose a pillar"
        case .platform: "Choose a platform"
        case .format: "Choose a format"
        case .status: "Choose a status"
        case .series: "Choose a series"
        }
    }
}

private enum PostWorkflowStatus: String, CaseIterable, Identifiable {
    case idea
    case draft
    case inProgress
    case scheduled
    case posted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idea: "Idea"
        case .draft: "Draft"
        case .inProgress: "In progress"
        case .scheduled: "Scheduled"
        case .posted: "Posted"
        }
    }
}

enum PostDatePlanningStep: String, CaseIterable, Identifiable {
    case work
    case schedule

    var id: String { rawValue }
}

private enum PostDatePlanningIntent: Equatable {
    case edit
    case markInProgress
    case schedule

    var requiredStep: PostDatePlanningStep? {
        switch self {
        case .edit: nil
        case .markInProgress: .work
        case .schedule: .schedule
        }
    }
}

struct PostDatePlanDraft {
    let workDate: Date
    let hasWorkDate: Bool
    let includesWorkTime: Bool
    let scheduledDate: Date
    let hasScheduledDate: Bool
    let includesScheduledTime: Bool
}

struct ResumablePostEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var brief: CreativeBrief
    @Bindable var output: PlatformOutput
    @Query private var outputs: [PlatformOutput]
    @Query private var tasks: [CreatorTask]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query(sort: \BrandPartner.name) private var allBrandPartners: [BrandPartner]
    @Query(sort: \ContentSeries.createdAt) private var allSeries: [ContentSeries]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var profiles: [CreatorProfile]
    @Query private var attachments: [CreatorAttachment]
    let onSpark: () -> Void
    let contextLabel: String?
    let isReviewEditing: Bool
    let bottomActionClearance: CGFloat
    let closeAction: (() -> Void)?
    /// Hosts that draw their own header (the Quick Add card) suppress the
    /// editor's chrome — the desktop rail and the phone toolbar actions — so
    /// back/title/spark/delete never appear inside quick add (creator
    /// direction 2026-08-19).
    let showsEditorChrome: Bool
    let externalSaveCoordinator: PostEditorSaveCoordinator?

    @State private var targetDate: Date
    @State private var hasTargetDate: Bool
    @State private var shouldPersistTargetDate: Bool
    @State private var showDatePicker = false
    @State private var workDate: Date
    @State private var hasWorkDate: Bool
    @State private var datePlanningStep: PostDatePlanningStep = .work
    @State private var datePlanningIntent: PostDatePlanningIntent = .edit
    @State private var didSaveDatePlan = false
    @State private var actualPostedDate = Date()
    @State private var showActualPostedDateConfirmation = false
    @State private var showTaskComposer = false
    @State private var showMorePostDetails = false
    @State private var selectedMedia: [PhotosPickerItem] = []
    @State private var selectedMoodBoardMedia: [PhotosPickerItem] = []
    @State private var isImportingMedia = false
    @State private var isImportingMoodBoardMedia = false
    @State private var showMediaManager = false
    @State private var mediaExportRequest: PostMediaExportRequest?
    @State private var showCollaborationFileImporter = false
    @State private var showBrandPartnerPicker = false
    @State private var confirmDeleteDraft = false
    @State private var confirmMoveToIdeaBank = false
    @State private var isDeletingDraft = false
    @State private var didMoveToIdeaBank = false
    @State private var markdownDocument: MarkdownFileDocument?
    @State private var showMarkdownExporter = false
    @State private var pendingProposal: BriefProposal?
    @State private var activeSetupPicker: PostDraftSetupPicker?
    @State private var isAddingCustomStatus = false
    @State private var customStatusDraft = ""
    @State private var customStatusPendingDeletion: String?
    @State private var confirmDeleteCustomStatus = false
    @State private var seriesEnabled: Bool
    @State private var isAddingSeries = false
    @State private var showSeriesPlanner = false
    @State private var showSeriesDetail = false
    @State private var showEpisodeScheduledConfirmation = false
    @State private var newSeriesName = ""
    @State private var isKeyboardVisible = false
    @State private var draftNotes: String
    @State private var externalSaveError: String?
    @State private var showSparkDevelopment = false
    @State private var suppressExitPersistence = false
    @State private var textCommitCoordinator = PostEditorTextCommitCoordinator()
#if !targetEnvironment(macCatalyst)
    @State private var voiceRecorderBrief: CreativeBrief?
#endif
#if targetEnvironment(macCatalyst)
    @State private var showDesktopDraftOptions = false
#endif
    @FocusState private var customStatusFieldFocused: Bool
    @FocusState private var newSeriesNameFieldFocused: Bool
    private var pillars: [Pillar] {
        allPillars.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: brief.workspaceID ?? appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    private var socialAccounts: [CreatorSocialAccount] {
        allSocialAccounts.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: brief.workspaceID ?? appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    private var seriesRecords: [ContentSeries] {
        allSeries.filter {
            $0.state != .archived &&
                WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: brief.workspaceID ?? appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
    }
    private var selectedSeries: ContentSeries? {
        guard let seriesID = brief.seriesID else { return nil }
        return seriesRecords.first(where: { $0.id == seriesID })
    }

    init(
        brief: CreativeBrief,
        output: PlatformOutput,
        suggestedTargetDate: Date? = nil,
        contextLabel: String? = nil,
        isReviewEditing: Bool = false,
        bottomActionClearance: CGFloat = 88,
        closeAction: (() -> Void)? = nil,
        showsEditorChrome: Bool = true,
        externalSaveCoordinator: PostEditorSaveCoordinator? = nil,
        onSpark: @escaping () -> Void
    ) {
        self.brief = brief
        self.output = output
        self.onSpark = onSpark
        self.contextLabel = contextLabel
        self.isReviewEditing = isReviewEditing
        self.bottomActionClearance = bottomActionClearance
        self.closeAction = closeAction
        self.showsEditorChrome = showsEditorChrome
        self.externalSaveCoordinator = externalSaveCoordinator
        let briefID = brief.id
        _outputs = Query(
            filter: #Predicate<PlatformOutput> { $0.briefID == briefID },
            sort: \PlatformOutput.createdAt
        )
        _tasks = Query(
            filter: #Predicate<CreatorTask> { $0.briefID == briefID },
            sort: \CreatorTask.sortOrder
        )
        _attachments = Query(
            filter: #Predicate<CreatorAttachment> { $0.briefID == briefID },
            sort: \CreatorAttachment.createdAt
        )
        if let workspaceID = brief.workspaceID {
            _allPillars = Query(
                filter: #Predicate<Pillar> {
                    $0.workspaceID == workspaceID || $0.workspaceID == nil
                },
                sort: \Pillar.createdAt
            )
            _allSocialAccounts = Query(
                filter: #Predicate<CreatorSocialAccount> {
                    $0.workspaceID == workspaceID || $0.workspaceID == nil
                },
                sort: \CreatorSocialAccount.sortOrder
            )
            _allSeries = Query(
                filter: #Predicate<ContentSeries> {
                    $0.workspaceID == workspaceID || $0.workspaceID == nil
                },
                sort: \ContentSeries.createdAt
            )
            _allBrandPartners = Query(
                filter: #Predicate<BrandPartner> {
                    $0.workspaceID == workspaceID || $0.workspaceID == nil
                },
                sort: \BrandPartner.name
            )
        }
        let existingTargetDate = output.targetDate ?? brief.agendaDate
        _targetDate = State(initialValue: existingTargetDate ?? suggestedTargetDate ?? Date())
        _hasTargetDate = State(initialValue: existingTargetDate != nil || suggestedTargetDate != nil)
        _shouldPersistTargetDate = State(initialValue: existingTargetDate != nil)
        let legacyWorkDate = brief.status == .developing ? existingTargetDate : nil
        let existingWorkDate = brief.workDate ?? legacyWorkDate
        _workDate = State(initialValue: existingWorkDate ?? Date())
        _hasWorkDate = State(initialValue: existingWorkDate != nil)
        _showMorePostDetails = State(initialValue: Self.hasMorePostDetails(output))
        _draftNotes = State(initialValue: brief.notes)
        _seriesEnabled = State(initialValue: brief.seriesID != nil)
    }

    var body: some View {
        editorImportExportContainer
            .environment(textCommitCoordinator)
            .onAppear {
                externalSaveCoordinator?.save = {
                    let saved = persistChanges()
                    externalSaveError = saved ? nil : appModel.notice?.message
                    return saved
                }
            }
            .onDisappear { externalSaveCoordinator?.save = nil }
    }

    private var editorScrollContainer: some View {
        ScrollView {
            editorPageSurface
        }
        .scrollDismissesKeyboard(.interactively)
#if targetEnvironment(macCatalyst)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(Color.agentCanvas)
        // A hardware keyboard never covers the window, but Catalyst still
        // reports keyboard frames for floating input panels (dictation
        // utilities included). The automatic avoidance inset those add can
        // linger and let the editor scroll far past its own content.
        .ignoresSafeArea(.keyboard)
#endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingScheduleButton
        }
#if targetEnvironment(macCatalyst)
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsEditorChrome {
                desktopDetailRail
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#endif
        .toolbar {
#if !targetEnvironment(macCatalyst)
            ToolbarItem(placement: .topBarLeading) {
                if showsEditorChrome {
                    AgentToolbarIconButton(title: "Back", icon: .back, action: requestCloseEditor)
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                if showsEditorChrome {
                    HStack(spacing: AgentSpacing.x1) {
                        compactSparkToolbarButton
                        navigationToolbarActionControl
                    }
                }
            }
            .sharedBackgroundVisibility(.hidden)
#endif
        }
        .navigationBarBackButtonHidden(showsEditorChrome)
    }

    private var editorSheetContainer: some View {
        editorScrollContainer
            .sheet(isPresented: $showDatePicker, onDismiss: finishDateSelection) {
                targetDatePickerSheet
            }
            .sheet(isPresented: $showActualPostedDateConfirmation) {
#if targetEnvironment(macCatalyst)
                ActualPostedDatePicker(
                    postedAt: $actualPostedDate,
                    onSave: markPosted
                )
                .presentationSizing(.fitted)
                .presentationCornerRadius(AgentRadius.floating)
                .presentationBackground(Color.agentCanvas)
#else
                ActualPostedDatePicker(
                    postedAt: $actualPostedDate,
                    onSave: markPosted
                )
                .agentSheetDragIndicator()
#endif
            }
#if !targetEnvironment(macCatalyst)
            .sheet(item: $activeSetupPicker, onDismiss: finishSetupPickerPresentation) { picker in
                ScrollView {
                    postSetupPickerSheet(picker)
                }
                .presentationDetents([.height(postSetupPickerHeight(for: picker)), .large])
                .agentSheetDragIndicator()
                .presentationBackground(Color.agentCanvas)
            }
            .sheet(item: $voiceRecorderBrief) { selectedBrief in
                VoiceSparkView(autoLinkBrief: selectedBrief)
            }
#endif
            .sheet(isPresented: $showTaskComposer) {
                PostDraftTaskComposer(brief: brief, output: output, defaultDate: defaultTaskDate)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSparkDevelopment) {
                DevelopBriefView(brief: brief, output: output)
                    .agentDesktopWorkspaceModal()
            }
            .sheet(isPresented: $showSeriesPlanner) {
                if let selectedSeries {
                    AddFutureEpisodesView(
                        series: selectedSeries,
                        suggestedStartDate: SeriesEpisodePlanner.nextEpisodeDate(
                            after: targetDate,
                            series: selectedSeries
                        )
                    )
                }
            }
            .sheet(isPresented: $showSeriesDetail) {
                if let selectedSeries {
                    SeriesDetailView(series: selectedSeries)
                }
            }
            .sheet(isPresented: $showMediaManager) {
                mediaManagerSheet
            }
    }

    private var editorAlertContainer: some View {
        editorSheetContainer
        .alert("Delete this post?", isPresented: $confirmDeleteDraft) {
            Button("Delete post", role: .destructive, action: deleteDraft)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the draft and its linked tasks.")
        }
        .alert("Move this post to Idea Bank?", isPresented: $confirmMoveToIdeaBank) {
            Button("Move to Idea Bank", action: makeIdea)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its title, notes, and pillar stay with the idea. Its schedule and linked post tasks are removed.")
        }
        .alert("Delete custom status?", isPresented: $confirmDeleteCustomStatus) {
            Button("Delete status", role: .destructive, action: deletePendingCustomStatus)
            Button("Cancel", role: .cancel) {
                customStatusPendingDeletion = nil
            }
        } message: {
            Text("Posts using this status return to In progress. Their dates and content stay unchanged.")
        }
        .alert("Episode scheduled", isPresented: $showEpisodeScheduledConfirmation) {
            if selectedSeries != nil {
                Button("Add Future Episodes") {
                    showSeriesPlanner = true
                }
            }
            Button("Done") {
                openWeeklyAgenda()
            }
        } message: {
            Text("This episode is scheduled for \(targetDate.formatted(.dateTime.month(.abbreviated).day())). Future episode dates are only added when you choose Add Future Episodes.")
        }
    }

    private var editorLifecycleContainer: some View {
        editorAlertContainer
        .onDisappear {
            if PostDraftExitPersistencePolicy.shouldPersist(
                isDeleting: isDeletingDraft,
                didMoveToIdeaBank: didMoveToIdeaBank,
                didPersistBeforeExit: suppressExitPersistence
            ) {
                _ = persistChanges()
            }
        }
        .onAppear {
            pendingProposal = appModel.proposal(for: brief, context: context)
        }
        .sheet(item: $pendingProposal) { proposal in
            PostProposalReviewView(brief: brief, initialProposal: proposal)
        }
        .onChange(of: selectedMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMedia(items) }
        }
        .onChange(of: selectedMoodBoardMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMoodBoardMedia(items) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = false }
        }
    }

    private var editorImportExportContainer: some View {
        editorLifecycleContainer
        .fileImporter(
            isPresented: $showCollaborationFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .rtf, .data],
            allowsMultipleSelection: true,
            onCompletion: importCollaborationFiles
        )
        .fileExporter(
            isPresented: $showMarkdownExporter,
            document: markdownDocument,
            contentType: .agentMarkdown,
            defaultFilename: PostMarkdownExporter.defaultFileName(for: brief),
            onCompletion: handleMarkdownExport
        )
        .fileExporter(
            isPresented: mediaExporterPresented,
            document: mediaExportRequest?.document,
            contentType: mediaExportRequest?.contentType ?? .data,
            defaultFilename: mediaExportRequest?.fileName ?? "post-media",
            onCompletion: handleMediaExport
        )
        .task(id: postMediaPreviewKey) {
            await PostMediaPreviewBackfillService.populateMissingPreviews(
                for: postMedia,
                context: context
            )
        }
        .task(id: publishedThumbnailHydrationKey) {
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await PublishedPostThumbnailHydrator().hydrate(
                brief: brief,
                output: output,
                context: context
            )
        }
    }

    @ViewBuilder
    private var editorPageSurface: some View {
#if targetEnvironment(macCatalyst)
        editorContent
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.vertical, AgentSpacing.x8)
            .background(
                Color.agentSurface,
                in: .rect(cornerRadius: AgentRadius.dashboard)
            )
            .agentSurfaceChrome(
                cornerRadius: AgentRadius.dashboard,
                role: .structural
            )
            .padding(.horizontal, AgentLayout.dashboardGutter)
            .padding(.top, AgentSpacing.x2)
            .padding(.bottom, AgentSpacing.x8)
            .overlay(alignment: .bottom) {
                // SwiftUI's reported Catalyst scroll geometry can include a
                // phantom keyboard-avoidance region. This anchor clamps the
                // underlying UIScrollView against the form's rendered end.
                CatalystEditorScrollEndAnchor()
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
#else
        editorContent
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, editorTopPadding)
            .padding(.bottom, showsScheduleAction ? AgentSpacing.x6 : 80)
#endif
    }

#if targetEnvironment(macCatalyst)
    private var desktopDetailRail: some View {
        AgentDesktopDetailRail(title: "Edit post", backAction: requestCloseEditor) {
            HStack(spacing: AgentSpacing.x2) {
                compactSparkToolbarButton
                desktopEditorActionControl
                    .frame(width: 44, height: 44)
            }
        }
    }
#endif

    private var editorTopPadding: CGFloat {
#if targetEnvironment(macCatalyst)
        AgentSpacing.x6
#else
        AgentSpacing.x4
#endif
    }

    @ViewBuilder
    private var navigationToolbarActionControl: some View {
        if isEditingFinalizedPost || isReviewEditing {
            AgentToolbarIconButton(
                title: "Save changes",
                icon: .check,
                isEnabled: !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: saveDraft
            )
        } else if canManageDraft {
            if canDeleteAsEmptyDraft {
                Button(role: .destructive) {
                    confirmDeleteDraft = true
                } label: {
                    compactNeutralToolbarLabel(icon: .trash, foreground: .agentDestructive)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityLabel("Delete empty draft")
            } else {
                Menu {
                    draftOptionsMenuContent
                } label: {
                    compactNeutralToolbarLabel(icon: .more)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Draft options")
            }
        }
    }

    private func compactNeutralToolbarLabel(
        icon: AgentIcon,
        foreground: Color = .agentText
    ) -> some View {
        AgentToolbarIconLabel(icon: icon, foreground: foreground)
    }

    @ViewBuilder
    private var compactSparkToolbarButton: some View {
        if !isEditingFinalizedPost && !isReviewEditing {
            Button(action: openSpark) {
                AgentToolbarIconContainer {
                    CyAsterisk(color: .cyAccent, size: 16, strokeWidth: 1.5)
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityLabel("Spark this post")
            .accessibilityHint("Opens Cy with this saved post as context")
        }
    }

#if targetEnvironment(macCatalyst)
    @ViewBuilder
    private var desktopEditorActionControl: some View {
        if isEditingFinalizedPost || isReviewEditing {
            AgentDesktopDetailIconButton(
                title: "Save changes",
                icon: .check,
                isEnabled: !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: saveDraft
            )
        } else if canManageDraft {
            if canDeleteAsEmptyDraft {
                AgentDesktopDetailIconButton(
                    title: "Delete empty draft",
                    icon: .trash,
                    foreground: .agentDestructive,
                    role: .destructive
                ) {
                    confirmDeleteDraft = true
                }
            } else {
                Button {
                    showDesktopDraftOptions.toggle()
                } label: {
                    AgentDesktopDetailIconLabel(icon: .more)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityLabel("Draft options")
                .popover(isPresented: $showDesktopDraftOptions, arrowEdge: .top) {
                    desktopDraftOptionsPopover
                        .frame(width: 260)
                        .padding(AgentSpacing.x2)
                        .presentationCompactAdaptation(.popover)
                        .presentationBackground(Color.agentSurface)
                }
            }
        }
    }

    private var desktopDraftOptionsPopover: some View {
        VStack(spacing: AgentSpacing.x1) {
            AgentDesktopMenuRow(title: "Save draft", icon: .download) {
                showDesktopDraftOptions = false
                saveDraft()
            }
            AgentDesktopMenuRow(title: "Duplicate post", icon: .duplicate) {
                showDesktopDraftOptions = false
                duplicateDraft()
            }
            AgentDesktopMenuDivider()
            AgentDesktopMenuRow(title: "Copy Markdown", icon: .copy) {
                showDesktopDraftOptions = false
                copyMarkdown()
            }
            AgentDesktopMenuRow(title: "Export Markdown", icon: .upload) {
                showDesktopDraftOptions = false
                exportMarkdown()
            }
            AgentDesktopMenuDivider()
            AgentDesktopMenuRow(title: "Delete post", icon: .trash, isDestructive: true) {
                showDesktopDraftOptions = false
                confirmDeleteDraft = true
            }
        }
    }
#endif

    @ViewBuilder
    private var draftOptionsMenuContent: some View {
        Button {
            saveDraft()
        } label: {
            AgentIconLabel(title: "Save draft", icon: .download)
        }
        Button {
            duplicateDraft()
        } label: {
            AgentIconLabel(title: "Duplicate post", icon: .duplicate)
        }
        Divider()
        Button {
            copyMarkdown()
        } label: {
            AgentIconLabel(title: "Copy Markdown", icon: .copy)
        }
        Button {
            exportMarkdown()
        } label: {
            AgentIconLabel(title: "Export Markdown", icon: .upload)
        }
        Divider()
        Button(role: .destructive) {
            confirmDeleteDraft = true
        } label: {
            AgentIconLabel(title: "Delete post", icon: .trash)
        }
    }

    private var isPendingEpisodeReview: Bool { isReviewEditing && externalSaveCoordinator != nil }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            editorHeading
            if let externalSaveError {
                Text(externalSaveError)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentDestructive)
            }
            BufferedPostTitleField(text: $brief.title)
            postSetupSection

#if targetEnvironment(macCatalyst)
            if let activeSetupPicker {
                postSetupPickerSheet(activeSetupPicker)
                    .background(Color.agentSelectionFill, in: .rect(cornerRadius: AgentRadius.dashboard))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.dashboard)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
            }
#endif

            if !isPendingEpisodeReview {
                if let contentFormat = selectedFormat?.kind.contentFormat {
                    AgentDurationPicker(seconds: $output.durationSeconds, format: contentFormat)
                }

                mediaSection
#if targetEnvironment(macCatalyst)
                if !voiceRecordings.isEmpty {
                    PostVoiceRecordingsSection(
                        recordings: voiceRecordings,
                        onDownload: requestMediaExport,
                        onDelete: deleteAttachment,
                        onTitleChange: updateVoiceRecordingTitle,
                        onPlaybackError: { appModel.notice = .error($0) }
                    )
                }
#else
                PostVoiceRecordingsSection(
                    recordings: voiceRecordings,
                    onAdd: { voiceRecorderBrief = brief },
                    onDownload: requestMediaExport,
                    onDelete: deleteAttachment,
                    onTitleChange: updateVoiceRecordingTitle,
                    onPlaybackError: { appModel.notice = .error($0) }
                )
#endif
            }
            postCopySection
            if isPendingEpisodeReview {
                Text("Add scripts, media, and tasks after you approve this episode.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                seriesSection

                if showsBrandDealsSection {
                    collaborationSection
                }

                if showsMoodBoardsSection {
                    moodBoardSection
                }

            }
            notesSection
            if !isPendingEpisodeReview {
                moreDetailsSection
                postedLinkSection
                tasksSection
            }
        }
        // Catalyst proposes an effectively unbounded vertical size to the
        // single ScrollView child. Keep the form at the sum of its sections
        // so the document ends with Tasks instead of an empty trailing page.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var editorHeading: some View {
#if targetEnvironment(macCatalyst)
        HStack {
            if showsScheduleAction {
                desktopPostActions
                    .frame(maxWidth: .infinity)
                    .disabled(brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
#else
        HStack {
            MetaLabel(contextLabel ?? editorContextLabel)
            Spacer()
        }
#endif
    }

#if targetEnvironment(macCatalyst)
    @ViewBuilder
    private var desktopPostActions: some View {
        switch bottomPostAction {
        case .schedule:
            desktopPostActionButton(
                title: scheduleActionTitle,
                isPrimary: true,
                hint: scheduleActionHint,
                action: performScheduleAction
            )
        case .markPosted:
            desktopPostActionButton(
                title: "Mark as posted",
                isPrimary: true,
                hint: "Marks this scheduled post as posted",
                action: requestPosted
            )
        case .markPostedAndReschedule:
            HStack(spacing: AgentSpacing.x2) {
                desktopPostActionButton(
                    title: "Mark posted",
                    isPrimary: true,
                    hint: "Marks this late scheduled post as posted",
                    action: requestPosted
                )
                desktopPostActionButton(
                    title: "Reschedule",
                    isPrimary: false,
                    hint: "Chooses a new scheduled date",
                    action: requestSchedule
                )
            }
        case .markNotPosted:
            EmptyView()
        }
    }

    private func desktopPostActionButton(
        title: String,
        isPrimary: Bool,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.agentSubtext.weight(.medium))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .background(
                    Color.agentPureWhite.opacity(colorScheme == .dark ? 0.14 : 0.96),
                    in: .rect(cornerRadius: AgentRadius.control)
                )
                .glassEffect(
                    .clear.interactive()
                        .tint(Color.agentPureWhite.opacity(colorScheme == .dark ? 0.06 : 0.12)),
                    in: .rect(cornerRadius: AgentRadius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(
                            desktopPostActionBorder(isPrimary: isPrimary),
                            lineWidth: isPrimary ? 1.25 : 0.9
                        )
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint(hint)
    }

    private func desktopPostActionBorder(isPrimary: Bool) -> Color {
        if colorScheme == .dark {
            return Color.agentPureWhite.opacity(isPrimary ? 0.34 : 0.22)
        }
        return Color.agentPureBlack.opacity(isPrimary ? 0.30 : 0.18)
    }
#endif

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }

    private var pillarCalendarMarkers: [PillarCalendarMarker] {
        activePillars.flatMap { pillar in
            pillar.resolvedWeekdays(in: activePillars).map { weekday in
                PillarCalendarMarker(
                    weekday: weekday,
                    colorHex: pillar.resolvedColorHex(in: activePillars)
                )
            }
        }
    }

    private var targetDatePickerSheet: some View {
        PostDatesPicker(
            scheduledDate: targetDate,
            hasScheduledDate: hasTargetDate,
            includesScheduledTime: output.includesTargetTime,
            workDate: workDate,
            hasWorkDate: hasWorkDate,
            includesWorkTime: brief.includesWorkTime,
            pillarMarkers: pillarCalendarMarkers,
            initialStep: datePlanningStep,
            requiredStep: datePlanningIntent.requiredStep,
            confirmationTitle: datePlanningIntent == .schedule ? "Schedule post" : "Save planning dates",
            isRescheduling: datePlanningIntent == .schedule && bottomPostAction == .markPostedAndReschedule,
            onSave: applyDatePlan
        )
        .presentationDetents([.large])
        .agentDesktopWorkspaceModal()
        .agentSheetDragIndicator()
    }

    private var postSetupSection: some View {
        VStack(spacing: 0) {
            pillarMenu

            Button {
                presentSetupPicker(.platform)
            } label: {
                PostDraftSetupRow(label: "Platform", value: selectedDestination?.name ?? output.platform.title)
            }
            .buttonStyle(AgentPressButtonStyle())

            Button {
                presentSetupPicker(.format)
            } label: {
                PostDraftSetupRow(label: "Format", value: selectedFormat?.name ?? "Choose a format")
            }
            .buttonStyle(AgentPressButtonStyle())
            .disabled(output.destinationID == nil)
            .opacity(output.destinationID == nil ? 0.55 : 1)

            if !isPendingEpisodeReview {
                Button {
                    presentSetupPicker(.status)
                } label: {
                    PostDraftSetupRow(label: "Status", value: displayedWorkflowStatus)
                }
                .buttonStyle(AgentPressButtonStyle())

            }
            if workflowStatus != .idea || isPendingEpisodeReview {
                Button { editPostDate(.work) } label: {
                    PostDraftSetupRow(
                        label: "Work on",
                        value: workDateLabel,
                        indicator: isWorkDateLate ? "Late" : nil
                    )
                }
                .buttonStyle(AgentPressButtonStyle())

                Button { editPostDate(.schedule) } label: {
                    PostDraftSetupRow(
                        label: "Scheduled",
                        value: targetDateLabel
                    )
                }
                .buttonStyle(AgentPressButtonStyle())
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
    }

    private var notesSection: some View {
        BufferedPostNotesEditor(text: $draftNotes)
    }

    @ViewBuilder
    private var moreDetailsSection: some View {
        if showMorePostDetails || Self.hasMorePostDetails(output) {
            DisclosureGroup(isExpanded: $showMorePostDetails) {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    BriefField(label: "Opening", text: $output.openingAdjustment)
                    if selectedDestination?.builtInKind == .youtube {
                        BriefField(label: "Platform title", text: $output.titleOverride)
                    }
                    BriefField(label: "Edit notes", text: $output.editChanges)
                }
                .padding(.top, AgentSpacing.x4)
            } label: {
                BriefDisclosureLabel(title: "More post details", detail: "Opening, edit notes")
            }
        }
    }

    @ViewBuilder
    private var postedLinkSection: some View {
        if output.status == .posted {
            PostEditorTextField(
                label: "Post link",
                text: $output.publishedURLString,
                axis: .horizontal,
                keyboardType: .URL,
                textContentType: .URL
            )
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Tasks", trailing: "\(topLevelTasks.count)")
            ForEach(topLevelTasks) { task in
                TaskRow(task: task, allTasks: tasks)
            }
            AgentBlockAddActionButton(title: "Add task") { showTaskComposer = true }
        }
    }

    private var showsScheduleAction: Bool {
        !isEditingFinalizedPost && !isReviewEditing
    }

    private var bottomPostAction: PostBottomAction {
        PostBottomActionPolicy.action(
            outputStatus: output.status,
            scheduledDate: hasTargetDate ? targetDate : nil,
            includesScheduledTime: output.includesTargetTime,
            hasPersistedScheduledDate: shouldPersistTargetDate
        )
    }

    private var scheduleActionTitle: String {
        PostScheduleActionPresentation.title(
            suggestedDate: hasTargetDate ? targetDate : nil,
            hasPersistedScheduledDate: shouldPersistTargetDate
        )
    }

    private var scheduleActionHint: String {
        if PostScheduleActionPresentation.shouldScheduleImmediately(
            suggestedDate: hasTargetDate ? targetDate : nil,
            hasPersistedScheduledDate: shouldPersistTargetDate
        ) {
            return "Schedules this post for \(targetDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))"
        }
        return "Sets a date and adds this post to the weekly agenda"
    }

    private func performScheduleAction() {
        if PostScheduleActionPresentation.shouldScheduleImmediately(
            suggestedDate: hasTargetDate ? targetDate : nil,
            hasPersistedScheduledDate: shouldPersistTargetDate
        ) {
            schedulePost()
        } else {
            requestSchedule()
        }
    }

    @ViewBuilder
    private var floatingScheduleButton: some View {
#if !targetEnvironment(macCatalyst)
        if showsScheduleAction {
            Group {
                switch bottomPostAction {
                case .schedule:
                    floatingPostActionButton(
                        title: scheduleActionTitle,
                        hint: scheduleActionHint,
                        action: performScheduleAction
                    )
                case .markPosted:
                    floatingPostActionButton(
                        title: "Mark as posted",
                        hint: "Marks this scheduled post as posted",
                        action: requestPosted
                    )
                case .markPostedAndReschedule:
                    HStack(spacing: AgentSpacing.x3) {
                        floatingPostActionButton(
                            title: "Mark posted",
                            hint: "Marks this late scheduled post as posted",
                            action: requestPosted
                        )
                        floatingPostActionButton(
                            title: "Reschedule",
                            hint: "Chooses a new scheduled date",
                            action: requestSchedule
                        )
                    }
                case .markNotPosted:
                    EmptyView()
                }
            }
            .disabled(brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x2)
            .padding(.bottom, isKeyboardVisible ? AgentSpacing.x2 : bottomActionClearance)
        }
#endif
    }

    private func floatingPostActionButton(
        title: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        AgentPhonePostActionButton(
            title: title,
            accessibilityHint: hint,
            action: action
        )
    }

    private var pillarMenu: some View {
        Button {
            presentSetupPicker(.pillar)
        } label: {
            PostDraftSetupRow(
                label: "Pillar",
                value: selectedPillar?.name ?? "No pillar",
                color: selectedPillar.map { pillar in
                    Color(agentHex: pillar.resolvedColorHex(in: activePillars))
                }
            )
        }
        .buttonStyle(AgentPressButtonStyle())
    }

    private func performStableSetupSelection(_ update: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func presentSetupPicker(_ picker: PostDraftSetupPicker) {
        AgentKeyboard.dismiss()
        if picker != .status {
            isAddingCustomStatus = false
            customStatusDraft = ""
        }
        if picker != .series {
            isAddingSeries = false
            newSeriesName = ""
        }
        activeSetupPicker = picker
    }

    private func finishSetupPickerPresentation() {
        isAddingCustomStatus = false
        customStatusDraft = ""
        isAddingSeries = false
        newSeriesName = ""
        if seriesEnabled, brief.seriesID == nil {
            seriesEnabled = false
        }
    }

    private func chooseSetupOption(_ update: () -> Void) {
        performStableSetupSelection(update)
        activeSetupPicker = nil
    }

    @ViewBuilder
    private func postSetupPickerSheet(_ picker: PostDraftSetupPicker) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .center) {
                Text(picker.title)
                    .font(.agentTitle)
                    .foregroundStyle(Color.agentText)

                Spacer()

                Button("Close") {
                    isAddingCustomStatus = false
                    activeSetupPicker = nil
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                switch picker {
                case .pillar:
                    setupPickerChoice(title: "No pillar", isSelected: brief.pillarID == nil) {
                        brief.pillarID = nil
                    }

                    ForEach(Array(activePillars.enumerated()), id: \.element.id) { index, pillar in
                        setupPickerDivider()
                        setupPickerChoice(
                            title: pillar.name,
                            color: Color(agentHex: pillar.resolvedColorHex(in: activePillars)),
                            isSelected: brief.pillarID == pillar.id
                        ) {
                            brief.pillarID = pillar.id
                        }
                    }

                case .platform:
                    if activeDestinations.isEmpty {
                        setupPickerEmptyState("No platforms are available.")
                    } else {
                        ForEach(Array(activeDestinations.enumerated()), id: \.element.id) { index, destination in
                            if index > 0 { setupPickerDivider() }
                            setupPickerChoice(
                                title: destination.name,
                                isSelected: output.destinationID == destination.id
                            ) {
                                select(destination)
                            }
                        }
                    }

                case .format:
                    if activeFormats.isEmpty {
                        setupPickerEmptyState("No formats are available for this platform.")
                    } else {
                        ForEach(Array(activeFormats.enumerated()), id: \.element.id) { index, format in
                            if index > 0 { setupPickerDivider() }
                            setupPickerChoice(
                                title: format.name,
                                isSelected: output.formatID == format.id
                            ) {
                                output.formatID = format.id
                                normalizeDuration(for: format)
                                syncLegacyPlatform()
                            }
                        }
                    }

                case .status:
                    if isAddingCustomStatus {
                        customStatusComposer
                    } else {
                        ForEach(Array(PostWorkflowStatus.allCases.enumerated()), id: \.element.id) { index, status in
                            if index > 0 { setupPickerDivider() }
                            workflowStatusPickerChoice(status)
                        }

                        ForEach(customStatusOptions, id: \.self) { status in
                            setupPickerDivider()
                            customStatusPickerChoice(status)
                        }

                        setupPickerDivider()
                        Button {
                            customStatusDraft = ""
                            isAddingCustomStatus = true
                            customStatusFieldFocused = true
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                Text("+")
                                    .font(.agentHeadline)
                                Text("Add custom status")
                                    .font(.agentBody)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }

                case .series:
                    if isAddingSeries {
                        seriesComposer
                    } else {
                        ForEach(Array(seriesRecords.enumerated()), id: \.element.id) { index, series in
                            if index > 0 { setupPickerDivider() }
                            setupPickerChoice(
                                title: series.name,
                                isSelected: brief.seriesID == series.id
                            ) {
                                assignSeries(series)
                            }
                        }

                        if !seriesRecords.isEmpty {
                            setupPickerDivider()
                        }
                        Button {
                            newSeriesName = ""
                            isAddingSeries = true
                            newSeriesNameFieldFocused = true
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                Text("+")
                                    .font(.agentHeadline)
                                Text("Create new series")
                                    .font(.agentBody)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func setupPickerChoice(
        title: String,
        color: Color? = nil,
        isSelected: Bool,
        update: @escaping () -> Void
    ) -> some View {
        Button {
            chooseSetupOption(update)
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                }

                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    AgentIconView(.check, size: 13)
                        .foregroundStyle(Color.agentText)
                }
            }
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
    }

    private func workflowStatusPickerChoice(_ status: PostWorkflowStatus) -> some View {
        Button {
            activeSetupPicker = nil
            Task { @MainActor in
                await Task.yield()
                applyWorkflowStatus(status)
            }
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                Text(status.title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if workflowStatus == status && brief.resolvedCustomStatusLabel == nil {
                    AgentIconView(.check, size: 13)
                        .foregroundStyle(Color.agentText)
                }
            }
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
    }

    private func customStatusPickerChoice(_ status: String) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            Button {
                applyCustomStatus(status)
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    Text(status)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if brief.resolvedCustomStatusLabel?.localizedCaseInsensitiveCompare(status) == .orderedSame {
                        AgentIconView(.check, size: 13)
                            .foregroundStyle(Color.agentText)
                    }
                }
                .frame(minHeight: 54)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                activeSetupPicker = nil
                Task { @MainActor in
                    await Task.yield()
                    customStatusPendingDeletion = status
                    confirmDeleteCustomStatus = true
                }
            } label: {
                AgentIconView(.trash, size: 15)
                    .foregroundStyle(Color.agentDestructive)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(status) status")
        }
        .frame(minHeight: 54)
    }

    private func deletePendingCustomStatus() {
        guard let status = customStatusPendingDeletion else { return }
        customStatusPendingDeletion = nil
        _ = appModel.deleteCustomPostStatus(status, context: context)
    }

    private var customStatusComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            Text("Name this stage")
                .font(.agentHeadline)
                .foregroundStyle(Color.agentText)

            TextField("", text: $customStatusDraft)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($customStatusFieldFocused)
                .onSubmit { applyCustomStatus(customStatusDraft) }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 52)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentHairline, lineWidth: 1)
                }

            Button("Add status") {
                applyCustomStatus(customStatusDraft)
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(CustomPostStatusPolicy.normalized(customStatusDraft) == nil)
        }
        .padding(.vertical, AgentSpacing.x4)
    }

    private var seriesComposer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            Text("Name this series")
                .font(.agentHeadline)
                .foregroundStyle(Color.agentText)

            Text("A series keeps related episodes together without copying their content.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)

            TextField("", text: $newSeriesName)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($newSeriesNameFieldFocused)
                .onSubmit(createSeries)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 52)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentHairline, lineWidth: 1)
                }

            Button("Create series", action: createSeries)
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.vertical, AgentSpacing.x4)
    }

    private func setupPickerDivider() -> some View {
        Rectangle()
            .fill(Color.agentHairline)
            .frame(height: 1)
    }

    private func setupPickerEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.agentBody)
            .foregroundStyle(Color.agentSecondary)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    private func postSetupPickerHeight(for picker: PostDraftSetupPicker) -> CGFloat {
        let optionCount: Int
        switch picker {
        case .pillar: optionCount = activePillars.count + 1
        case .platform: optionCount = max(activeDestinations.count, 1)
        case .format: optionCount = max(activeFormats.count, 1)
        case .status:
            if isAddingCustomStatus { return 300 }
            optionCount = PostWorkflowStatus.allCases.count + customStatusOptions.count + 1
        case .series:
            if isAddingSeries { return 330 }
            optionCount = seriesRecords.count + 1
        }
        return min(560, max(220, CGFloat(optionCount * 55) + 112))
    }
    private var isEditingFinalizedPost: Bool {
        !PostDraftResumePolicy.shouldResume(
            briefStatus: brief.status,
            outputStatus: output.status
        )
    }
    private var editorContextLabel: String {
        if isEditingFinalizedPost { return "Edit post" }
        switch workflowStatus {
        case .idea: return "Idea"
        case .inProgress: return brief.resolvedCustomStatusLabel ?? "In progress"
        case .draft: return "Draft post"
        case .scheduled, .posted: return "Edit post"
        }
    }

    private var workflowStatus: PostWorkflowStatus {
        if output.status == .posted || brief.status == .posted { return .posted }
        if output.status == .scheduled || brief.status == .scheduled { return .scheduled }
        if brief.status == .developing { return .inProgress }
        if IdeaBankPlacementPolicy.includes(brief) { return .idea }
        return .draft
    }
    private var displayedWorkflowStatus: String {
        CustomPostStatusPolicy.displayLabel(
            briefStatus: brief.status,
            outputStatus: output.status,
            customStatus: brief.customStatusLabel,
            ideaBankPlacement: brief.ideaBankPlacement
        )
    }
    private var activeWorkspace: CreatorWorkspace? {
        let preferredID = brief.workspaceID ?? appModel.activeWorkspaceID
        let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredID,
            workspaces: workspaces
        )
        return workspaces.first { $0.id == activeID && !$0.isArchived }
    }
    private var customStatusOptions: [String] {
        var values = activeWorkspace?.customPostStatuses ?? []
        if let current = brief.resolvedCustomStatusLabel,
           !values.contains(where: { $0.localizedCaseInsensitiveCompare(current) == .orderedSame }) {
            values.append(current)
        }
        return values
    }
    private var selectedPillar: Pillar? { activePillars.first { $0.id == brief.pillarID } }
    private var activeDestinations: [PublishingDestination] { destinations.filter { !$0.isArchived } }
    private var selectedDestination: PublishingDestination? { destinations.first { $0.id == output.destinationID } }
    private var activeFormats: [PublishingFormat] {
        formats.filter { $0.destinationID == output.destinationID && !$0.isArchived }
    }
    private var selectedFormat: PublishingFormat? { formats.first { $0.id == output.formatID } }
    private var availableSocialAccounts: [CreatorSocialAccount] {
        guard let destinationID = output.destinationID else { return [] }
        return socialAccounts.filter { $0.destinationID == destinationID && !$0.isArchived }
    }
    private var topLevelTasks: [CreatorTask] {
        tasks.filter { $0.parentTaskID == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var canManageDraft: Bool {
        !isEditingFinalizedPost && !isReviewEditing
    }

    private var canDeleteAsEmptyDraft: Bool {
        EmptyPostDraftDeletionPolicy.shouldOfferDirectDelete(
            brief: brief,
            output: output,
            taskCount: tasks.count,
            attachmentCount: attachments.count
        )
    }

    private var postMedia: [CreatorAttachment] {
        attachments
            .filter { $0.ownerKind == .postMedia && $0.platformOutputID == output.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var voiceRecordings: [CreatorAttachment] {
        PostVoiceRecordingPolicy.recordings(from: attachments, briefID: brief.id)
    }

    @discardableResult
    private func updateVoiceRecordingTitle(_ attachment: CreatorAttachment, title: String) -> Bool {
        let previousTitle = attachment.displayTitle
        let previousUpdatedAt = attachment.updatedAt
        attachment.displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        attachment.updatedAt = Date()
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            attachment.displayTitle = previousTitle
            attachment.updatedAt = previousUpdatedAt
            appModel.notice = .error("That recording title could not be saved.")
            return false
        }
    }

    private var mediaManagerSheet: some View {
        PostMediaManagerView(
            briefID: brief.id,
            workspaceID: mediaWorkspaceID,
            output: output
        )
    }

    private var mediaWorkspaceID: UUID? {
        brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context)
    }

    private var postMediaPreviewKey: String {
        postMedia.map { "\($0.id.uuidString):\($0.previewData == nil ? 0 : 1)" }.joined(separator: "|")
    }

    private var publishedThumbnailHydrationKey: String {
        PublishedPostThumbnailPolicy.taskKey(output: output)
    }

    private var mediaExporterPresented: Binding<Bool> {
        Binding(
            get: { mediaExportRequest != nil },
            set: { if !$0 { mediaExportRequest = nil } }
        )
    }

    private var collaborationFiles: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .collaborationFile && $0.platformOutputID == output.id }
    }

    private var moodBoardMedia: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .moodBoardMedia && $0.platformOutputID == output.id }
    }

    private var postCopySection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            ForEach(CreatorPostCopyField.allCases) { field in
                if (field != .hook || showsHookSection) && (!isPendingEpisodeReview || field != .script) {
                    PostEditorTextField(
                        label: field.editorTitle,
                        text: postCopyBinding(for: field),
                        minimumHeight: field.minimumEditorHeight
                    )
                }
            }
        }
    }

    private func postCopyBinding(for field: CreatorPostCopyField) -> Binding<String> {
        switch field {
        case .hook:
            $brief.spokenHook
        case .script:
            $brief.scriptBeatsText
        case .caption:
            $output.caption
        case .callToAction:
            Binding(
                get: { output.cta.isEmpty ? brief.ctaIntent : output.cta },
                set: { value in
                    output.cta = value
                    brief.ctaIntent = value
                }
            )
        }
    }

    private var editorProfile: CreatorProfile? { profiles.first }

    private var showsHookSection: Bool {
        (editorProfile?.showsHookInPostEditor ?? true)
            || !brief.spokenHook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsBrandDealsSection: Bool {
        let hasExistingDeal = brief.isBrandCollaboration
            || !brief.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || brief.compensationAmount != nil
            || !brief.giftedProductDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !collaborationFiles.isEmpty
        return (editorProfile?.showsBrandDealsInPostEditor ?? false) || hasExistingDeal
    }

    private var showsMoodBoardsSection: Bool {
        let hasExistingMoodBoard = brief.moodBoardEnabled || !moodBoardMedia.isEmpty
        return (editorProfile?.showsMoodBoardsInPostEditor ?? true) || hasExistingMoodBoard
    }

    private var collaborationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("Collaboration")
                        .font(.agentBody.weight(.semibold))
                    Text(brief.isBrandCollaboration ? collaborationSummary : "Not a brand collaboration")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Brand collaboration", isOn: $brief.isBrandCollaboration)
                    .labelsHidden()
                    .tint(Color.actionAccent)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 64)

            if brief.isBrandCollaboration {
                Rectangle().fill(Color.agentHairline).frame(height: 1)

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    Button {
                        showBrandPartnerPicker = true
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            MetaLabel("Partner")
                            Spacer()
                            if let partner = selectedBrandPartner {
                                BrandPartnerAvatar(partner: partner, size: 30)
                                Text(partner.name)
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentText)
                                    .lineLimit(1)
                            } else {
                                Text(brief.brandName.isEmpty ? "Choose partner" : brief.brandName)
                                    .font(.agentBody)
                                    .foregroundStyle(brief.brandName.isEmpty ? Color.agentSecondary : Color.agentText)
                                    .lineLimit(1)
                            }
                            AgentIconView(.forward, size: 12)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .frame(minHeight: 52)
                        .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Compensation")
                        Picker("Compensation", selection: $brief.compensationTypeRaw) {
                            ForEach(CompensationType.allCases) { type in
                                Text(type.title).tag(type.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if brief.compensationType == .paid || brief.compensationType == .both {
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            MetaLabel("Amount")
                            HStack(spacing: AgentSpacing.x3) {
                                Text("$")
                                    .font(.agentBody.weight(.medium))
                                TextField("", value: $brief.compensationAmount, format: .number.precision(.fractionLength(0...2)))
                                    .font(.agentBody)
                                    .keyboardType(.decimalPad)
                                Text("USD")
                                    .font(.agentMetadata)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 52)
                            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                        }

                        VStack(spacing: 0) {
                            Toggle("Net terms", isOn: $brief.brandHasNetTerms)
                                .font(.agentBody)
                                .tint(Color.actionAccent)
                                .padding(.horizontal, AgentSpacing.x4)
                                .frame(minHeight: 52)
                            if brief.brandHasNetTerms {
                                Divider().overlay(Color.agentHairline)
                                HStack {
                                    Text("Payment due")
                                        .font(.agentBody)
                                    Spacer()
                                    Picker("Payment due", selection: $brief.brandNetTermsDays) {
                                        ForEach([15, 30, 45, 60, 90], id: \.self) { days in
                                            Text("Net \(days)").tag(days)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .padding(.horizontal, AgentSpacing.x4)
                                .frame(minHeight: 52)
                            }
                        }
                        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                    }

                    if brief.compensationType == .gifted || brief.compensationType == .both {
                        PostEditorTextField(label: "Gifted product", text: $brief.giftedProductDescription)
                    }

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        HStack {
                            MetaLabel("Contract or brief")
                            Spacer()
                            if !collaborationFiles.isEmpty {
                                Text(collaborationFiles.count, format: .number)
                                    .font(.agentMetadata)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                        }
                        ForEach(collaborationFiles) { attachment in
                            PostAttachmentRow(attachment: attachment) {
                                deleteAttachment(attachment)
                            }
                        }
                        AgentAddActionRow(title: "Add contract or brief") {
                            showCollaborationFileImporter = true
                        }
                    }
                }
                .padding(AgentSpacing.x4)
            }
        }
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.card)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
        .sheet(isPresented: $showBrandPartnerPicker) {
            BrandPartnerPickerView(selectedPartnerID: brief.brandPartnerID) { partner in
                let previousPartnerID = brief.brandPartnerID
                let previousBrandName = brief.brandName
                let wasBrandCollaboration = brief.isBrandCollaboration
                let previousUpdatedAt = brief.updatedAt
                brief.brandPartnerID = partner.id
                brief.brandName = partner.name
                brief.isBrandCollaboration = true
                brief.updatedAt = Date()
                do {
                    try context.save()
                } catch {
                    context.rollback()
                    brief.brandPartnerID = previousPartnerID
                    brief.brandName = previousBrandName
                    brief.isBrandCollaboration = wasBrandCollaboration
                    brief.updatedAt = previousUpdatedAt
                    appModelNotice("That brand partner could not be saved.")
                }
            }
        }
    }

    private var selectedBrandPartner: BrandPartner? {
        guard let id = brief.brandPartnerID else { return nil }
        return allBrandPartners.first { $0.id == id }
    }

    private var collaborationSummary: String {
        let partner = brief.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        return partner.isEmpty ? "Add partner and deal details" : partner
    }

    private var moodBoardSection: some View {
        let importingMoodBoardMedia = isImportingMoodBoardMedia
        return VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Mood board")

            Toggle("Add a mood board", isOn: $brief.moodBoardEnabled)
                .font(.agentBody.weight(.semibold))
                .tint(Color.actionAccent)
                .frame(minHeight: 44)

            if brief.moodBoardEnabled {
                if !moodBoardMedia.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: AgentSpacing.x3) {
                            ForEach(moodBoardMedia) { attachment in
                                PostMediaThumbnail(attachment: attachment) {
                                    deleteAttachment(attachment)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                PhotosPicker(
                    selection: $selectedMoodBoardMedia,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    HStack(spacing: AgentSpacing.x3) {
                        AgentIconView(.image)
                        Text(importingMoodBoardMedia ? "Adding images" : "Add mood board images")
                        Spacer()
                        if importingMoodBoardMedia { ProgressView().controlSize(.small) }
                    }
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                }
                .disabled(importingMoodBoardMedia)
            }
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("Series")
                        .font(.agentBody.weight(.semibold))
                    Text(seriesEnabled ? seriesSelectionLabel : "Not part of a series")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Part of a series", isOn: Binding(
                    get: { seriesEnabled },
                    set: { enabled in
                        seriesEnabled = enabled
                        if enabled {
                            isAddingSeries = seriesRecords.isEmpty
                            presentSetupPicker(.series)
                        } else {
                            detachFromSeries()
                        }
                    }
                ))
                .labelsHidden()
                .tint(Color.actionAccent)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 64)

            if seriesEnabled {
                Rectangle().fill(Color.agentHairline).frame(height: 1)

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    Button {
                        isAddingSeries = seriesRecords.isEmpty
                        presentSetupPicker(.series)
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            AgentIconView(.branch, size: 14)
                                .foregroundStyle(Color.agentSecondary)
                            Text(seriesSelectionLabel)
                                .font(.agentBody.weight(.medium))
                                .foregroundStyle(selectedSeries == nil ? Color.agentSecondary : Color.agentText)
                                .lineLimit(1)
                            Spacer()
                            AgentIconView(.forward, size: 12)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)
                        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Choose series")
                    .accessibilityValue(seriesSelectionLabel)

                    if selectedSeries != nil {
                        PostEditorTextField(
                            label: "Episode name",
                            text: $brief.episodeLabel,
                            axis: .horizontal,
                            minimumHeight: 52
                        )

                        PostEditorTextField(
                            label: "Episode number",
                            text: Binding(
                                get: { brief.episodeNumber.map(String.init) ?? "" },
                                set: { brief.episodeNumber = Int($0.filter(\.isNumber)) }
                            ),
                            axis: .horizontal,
                            minimumHeight: 52,
                            keyboardType: .numberPad
                        )

                        Button {
                            showSeriesPlanner = true
                        } label: {
                            HStack(spacing: AgentSpacing.x2) {
                                AgentIconView(.calendar, size: 13)
                                Text("Add Future Episodes")
                            }
                        }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))

                        Button {
                            showSeriesDetail = true
                        } label: {
                            HStack(spacing: AgentSpacing.x2) {
                                AgentIconView(.forward, size: 13)
                                Text("Go to series")
                            }
                        }
                        .buttonStyle(AgentQuietSecondaryButtonStyle())
                    }
                }
                .padding(AgentSpacing.x4)
            }
        }
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.card)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    private var seriesSelectionLabel: String {
        if let selectedSeries {
            return selectedSeries.name
        }
        return brief.seriesID == nil ? "Choose a series" : "Series unavailable"
    }

    private var mediaSection: some View {
        let importingMedia = isImportingMedia
        return VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            if postMedia.isEmpty {
                PostMediaEmptyAddButton(
                    selection: $selectedMedia,
                    isImporting: importingMedia
                )
            } else {
                PostMediaSpotlight(
                    attachments: postMedia,
                    coverAttachmentID: output.coverAttachmentID,
                    onOpen: { _ in showMediaManager = true },
                    onDownload: requestMediaExport
                )

                PostMediaActionBar(
                    selection: $selectedMedia,
                    isImporting: importingMedia,
                    onEdit: { showMediaManager = true }
                )
            }

            Text("Media stays with this post and is not sent to Cy unless you explicitly include it later.")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
        }
    }

    @MainActor
    private func importMedia(_ items: [PhotosPickerItem]) async {
        isImportingMedia = true
        defer {
            isImportingMedia = false
            selectedMedia = []
        }

        let result = await PostMediaImportService.add(
            items: items,
            briefID: brief.id,
            output: output,
            workspaceID: brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context),
            context: context
        )
        if let notice = result.notice { appModelNotice(notice) }
    }

    @MainActor
    private func importMoodBoardMedia(_ items: [PhotosPickerItem]) async {
        isImportingMoodBoardMedia = true
        defer {
            isImportingMoodBoardMedia = false
            selectedMoodBoardMedia = []
        }

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                guard data.count <= 25 * 1_024 * 1_024 else {
                    appModelNotice("Choose mood board images smaller than 25 MB each.")
                    continue
                }
                let type = item.supportedContentTypes.first ?? .image
                let ext = type.preferredFilenameExtension ?? "jpg"
                let attachment = CreatorAttachment(
                    ownerKind: .moodBoardMedia,
                    briefID: brief.id,
                    platformOutputID: output.id,
                    fileName: "mood-board-\(UUID().uuidString.prefix(8)).\(ext)",
                    kind: .photo,
                    uniformTypeIdentifier: type.identifier,
                    byteCount: Int64(data.count),
                    localRelativePath: "",
                    cloudData: data,
                    syncState: .synced
                )
                attachment.workspaceID = brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context)
                context.insert(attachment)
            } catch {
                appModelNotice("One mood board image could not be added.")
            }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            appModelNotice("Those mood board images could not be saved.")
        }
    }

    private func importCollaborationFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= 25 * 1_024 * 1_024 else {
                    appModelNotice("Choose contract or brief files smaller than 25 MB each.")
                    continue
                }
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
                let kind: AttachmentKind = type.conforms(to: .image) ? .photo : .document
                let attachment = CreatorAttachment(
                    ownerKind: .collaborationFile,
                    briefID: brief.id,
                    platformOutputID: output.id,
                    fileName: url.lastPathComponent,
                    kind: kind,
                    uniformTypeIdentifier: type.identifier,
                    byteCount: Int64(data.count),
                    localRelativePath: "",
                    cloudData: data,
                    syncState: .synced
                )
                attachment.workspaceID = brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context)
                context.insert(attachment)
            }
            try context.save()
        } catch {
            context.rollback()
            appModelNotice("That contract or brief could not be added.")
        }
    }

    private func deleteAttachment(_ attachment: CreatorAttachment) {
        context.delete(attachment)
        do {
            try context.save()
        } catch {
            context.rollback()
            appModelNotice("That attachment could not be removed.")
        }
    }

    private func appModelNotice(_ message: String) {
        appModel.notice = .info(message)
    }

    private func select(_ destination: PublishingDestination) {
        output.destinationID = destination.id
        let destinationFormats = formats
            .filter { $0.destinationID == destination.id && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
        if let first = destinationFormats.first {
            output.formatID = first.id
            normalizeDuration(for: first)
        }
        output.socialAccountID = availableSocialAccounts.first(where: \.isPrimary)?.id
            ?? availableSocialAccounts.first?.id
        syncLegacyPlatform()
    }

    private func normalizeDuration(for format: PublishingFormat) {
        guard let contentFormat = format.kind.contentFormat else { return }
        if !contentFormat.durationOptions.contains(output.durationSeconds) {
            output.durationSeconds = contentFormat.defaultDuration
        }
    }

    private func syncLegacyPlatform() {
        guard let destinationID = output.destinationID,
              let formatID = output.formatID,
              let platform = PublishingCatalog.legacyPlatform(destinationID: destinationID, formatID: formatID) else { return }
        output.platform = platform
    }

    private func applyDatePlan(_ draft: PostDatePlanDraft) {
        let normalizedWorkDate = draft.hasWorkDate
            ? RecurringPostSchedule.normalizedTargetDate(
                draft.workDate,
                includesTime: draft.includesWorkTime
            )
            : nil
        let normalizedScheduledDate = draft.hasScheduledDate
            ? RecurringPostSchedule.normalizedTargetDate(
                draft.scheduledDate,
                includesTime: draft.includesScheduledTime
            )
            : nil

        guard appModel.updatePostPlanDates(
            brief: brief,
            output: output,
            workDate: normalizedWorkDate,
            includesWorkTime: draft.includesWorkTime,
            scheduledDate: normalizedScheduledDate,
            includesScheduledTime: draft.includesScheduledTime,
            context: context
        ) else { return }

        workDate = normalizedWorkDate ?? draft.workDate
        hasWorkDate = normalizedWorkDate != nil
        brief.includesWorkTime = draft.hasWorkDate && draft.includesWorkTime
        targetDate = normalizedScheduledDate ?? draft.scheduledDate
        hasTargetDate = normalizedScheduledDate != nil
        output.includesTargetTime = draft.hasScheduledDate && draft.includesScheduledTime
        shouldPersistTargetDate = true
        didSaveDatePlan = true
    }

    private func editPostDate(_ step: PostDatePlanningStep) {
        datePlanningIntent = .edit
        datePlanningStep = step
        didSaveDatePlan = false
        showDatePicker = true
    }

    private func requestInProgress() {
        guard appModel.allows(.schedule, context: context) else {
            appModelNotice("Adding work to the agenda is not available with your current access.")
            return
        }
        datePlanningIntent = .markInProgress
        datePlanningStep = .work
        didSaveDatePlan = false
        showDatePicker = true
    }

    private func requestSchedule() {
        guard appModel.allows(.schedule, context: context) else {
            appModelNotice("Scheduling is not available with your current access.")
            return
        }
        datePlanningIntent = .schedule
        datePlanningStep = .schedule
        didSaveDatePlan = false
        showDatePicker = true
    }

    private func finishDateSelection() {
        let savedPlan = didSaveDatePlan
        let intent = datePlanningIntent
        didSaveDatePlan = false
        datePlanningIntent = .edit
        guard savedPlan else { return }

        switch intent {
        case .edit:
            break
        case .markInProgress:
            if hasWorkDate { markInProgress() }
        case .schedule:
            if hasTargetDate { schedulePost() }
        }
    }

    private func applyWorkflowStatus(_ status: PostWorkflowStatus) {
        guard status != workflowStatus || brief.resolvedCustomStatusLabel != nil else { return }

        switch status {
        case .idea:
            confirmMoveToIdeaBank = true
        case .draft:
            guard persistChanges(commitSuggestedTargetDate: true) else { return }
            _ = appModel.markPostDraft(brief: brief, output: output, context: context)
        case .inProgress:
            requestInProgress()
        case .scheduled:
            requestSchedule()
        case .posted:
            requestPosted()
        }
    }

    private func applyCustomStatus(_ rawValue: String) {
        guard let status = CustomPostStatusPolicy.normalized(rawValue),
              appModel.applyCustomPostStatus(
                status,
                to: brief,
                output: output,
                context: context
              ) else { return }

        customStatusFieldFocused = false
        customStatusDraft = ""
        isAddingCustomStatus = false
        activeSetupPicker = nil
    }

    private func requestPosted() {
        guard appModel.allows(.updatePosting, context: context),
              appModel.allows(.schedule, context: context) else {
            appModelNotice("Updating posting status is not available with your current access.")
            return
        }
        let now = Date()
        if PostedDatePolicy.needsActualDateConfirmation(
            scheduledDate: hasTargetDate ? targetDate : nil,
            now: now
        ) {
            actualPostedDate = now
            showActualPostedDateConfirmation = true
            return
        }
        markPosted(at: now)
    }

    private func markPosted(at postedAt: Date) {
        let cleanTitle = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            appModelNotice("Name the post before marking it Posted.")
            return
        }
        guard PostedDatePolicy.isValid(postedAt) else {
            appModelNotice("A live post cannot have a future posted date.")
            return
        }

        if !hasTargetDate {
            targetDate = postedAt
            hasTargetDate = true
            shouldPersistTargetDate = true
            output.includesTargetTime = true
        }

        guard persistChanges(commitSuggestedTargetDate: true) else { return }
        if output.status != .scheduled {
            guard appModel.scheduleSinglePost(output: output, date: targetDate, context: context) else { return }
        }
        appModel.togglePosted(output: output, postedAt: postedAt, context: context)
        if output.status == .posted { openWeeklyAgenda() }
    }

    private func markInProgress() {
        let cleanTitle = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            appModelNotice("Name the post before adding it to your agenda.")
            return
        }
        guard hasWorkDate else {
            requestInProgress()
            return
        }
        guard persistChanges() else { return }
        guard appModel.markPostInProgress(
            brief: brief,
            output: output,
            date: workDate,
            context: context
        ) else { return }
        openWeeklyAgenda()
    }

    private func schedulePost() {
        let cleanTitle = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            appModelNotice("Name the post before scheduling it.")
            return
        }
        guard hasTargetDate else {
            requestSchedule()
            return
        }

        guard persistChanges(commitSuggestedTargetDate: true) else { return }
        guard appModel.scheduleSinglePost(output: output, date: targetDate, context: context) else { return }
        if brief.seriesID != nil {
            showEpisodeScheduledConfirmation = true
        } else {
            openWeeklyAgenda()
        }
    }

    private func openWeeklyAgenda() {
        suppressExitPersistence = true
        closeEditor()
        Task { @MainActor in
            await Task.yield()
            appModel.routeToWeeklyAgenda()
        }
    }

    private func openSpark() {
        guard persistChanges() else { return }
        showSparkDevelopment = true
    }

    private func saveDraft() {
        guard persistChanges(commitSuggestedTargetDate: true) else { return }
        suppressExitPersistence = true
        closeEditor()
    }

    private func makeIdea() {
        guard persistChanges() else { return }
        guard appModel.movePostToIdeaBank(brief: brief, output: output, context: context) else { return }
        hasTargetDate = false
        shouldPersistTargetDate = false
        output.includesTargetTime = false
        hasWorkDate = false
        didMoveToIdeaBank = true
        closeEditor()
    }

    private func duplicateDraft() {
        guard persistChanges() else { return }
        guard appModel.duplicatePostDraft(brief: brief, output: output, context: context) != nil else { return }
        appModel.notice = .info("Draft duplicated.")
    }

    private func deleteDraft() {
        isDeletingDraft = true
        if appModel.deleteDraft(brief, context: context) {
            closeEditor()
        } else {
            isDeletingDraft = false
        }
    }

    private func closeEditor() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }

    private func requestCloseEditor() {
        guard persistChanges() else { return }
        suppressExitPersistence = true
        closeEditor()
    }

    @discardableResult
    private func persistChanges(commitSuggestedTargetDate: Bool = false) -> Bool {
        let storedState = try? PostDraftEditorStoredState.load(
            briefID: brief.id,
            outputID: output.id,
            context: context
        )
        textCommitCoordinator.commitAll()
        let writesTargetDate = PostDraftTargetPersistencePolicy.shouldWriteTargetDate(
            hadPersistedTargetDate: shouldPersistTargetDate,
            explicitlyCommitted: commitSuggestedTargetDate
        )
        do {
            targetDate = try PostDraftEditorPersistencePolicy.save(
                brief: brief,
                output: output,
                outputs: outputs,
                notes: draftNotes,
                hasWorkDate: hasWorkDate,
                workDate: workDate,
                hasTargetDate: hasTargetDate,
                targetDate: targetDate,
                writesTargetDate: writesTargetDate,
                rescheduleLinkedTasks: { previousDate, newDate in
                    appModel.rescheduleLinkedTasks(
                        for: output,
                        from: previousDate,
                        to: newDate,
                        context: context
                    )
                },
                persist: { try context.save() },
                rollback: {
                    context.rollback()
                    storedState?.restore(
                        brief: brief,
                        output: output,
                        tasks: tasks
                    )
                }
            )
        } catch PostDraftEditorPersistencePolicy.Error.emptyTitle {
            appModel.notice = .info("Name the post before saving it.")
            return false
        } catch {
            appModel.notice = .error("That post could not be saved. Your previous saved version is still intact.")
            return false
        }
        if writesTargetDate {
            shouldPersistTargetDate = true
        }
        appModel.queueCalendarSync(context: context)
        return true
    }

    private func copyMarkdown() {
        guard persistChanges() else { return }
        UIPasteboard.general.string = postMarkdownDocument.text
        appModel.notice = .info("Markdown copied.")
    }

    private func exportMarkdown() {
        guard persistChanges() else { return }
        markdownDocument = postMarkdownDocument
        showMarkdownExporter = true
    }

    private var postMarkdownDocument: MarkdownFileDocument {
        PostMarkdownExporter.makeDocument(
            brief: brief,
            outputs: outputs,
            tasks: tasks,
            pillar: selectedPillar,
            destinations: destinations,
            formats: formats,
            socialAccounts: socialAccounts,
            attachments: attachments
        )
    }

    private func handleMarkdownExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            appModel.notice = .info("Markdown saved to Files.")
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                appModel.notice = .error("That Markdown file could not be saved.")
            }
        }
    }

    private func requestMediaExport(_ attachment: CreatorAttachment) {
        let preferredFileName = PostVoiceRecordingPolicy.isVoiceRecording(attachment)
            ? VoiceRecordingExportNaming.fileName(
                title: attachment.displayTitle,
                recordedAt: attachment.createdAt,
                postTitle: brief.title
            )
            : nil
        guard let request = PostMediaExportRequest(
            attachment: attachment,
            preferredFileName: preferredFileName
        ) else {
            appModel.notice = .error("That original is not available on this device yet.")
            return
        }
        mediaExportRequest = request
    }

    private func handleMediaExport(_ result: Result<URL, Error>) {
        defer { mediaExportRequest = nil }
        switch result {
        case .success:
            appModel.notice = .info("Full-resolution media saved to Files.")
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                appModel.notice = .error("That media file could not be saved.")
            }
        }
    }

    private var targetDateLabel: String {
        guard hasTargetDate else { return "Not scheduled" }
        if output.includesTargetTime {
            return targetDate.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
            )
        }
        return targetDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var workDateLabel: String {
        guard hasWorkDate else { return "Not planned" }
        if brief.includesWorkTime {
            return workDate.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
            )
        }
        return workDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var isWorkDateLate: Bool {
        PostWorkDateStatusPolicy.isLate(
            workDate: hasWorkDate ? workDate : nil,
            briefStatus: brief.status,
            outputStatus: output.status
        )
    }

    private var showsWorkDate: Bool {
        workflowStatus == .draft ||
            workflowStatus == .inProgress ||
            brief.resolvedCustomStatusLabel != nil
    }

    private var defaultTaskDate: Date {
        if showsWorkDate, hasWorkDate {
            return workDate
        }
        return targetDate
    }

    @discardableResult
    private func assignSeries(_ series: ContentSeries) -> Bool {
        let previousSeriesID = brief.seriesID
        let previousSeriesName = output.seriesName
        let previousUpdatedAt = brief.updatedAt
        let wasSeriesEnabled = seriesEnabled
        brief.seriesID = series.id
        output.seriesName = series.name
        brief.updatedAt = Date()
        seriesEnabled = true
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            brief.seriesID = previousSeriesID
            output.seriesName = previousSeriesName
            brief.updatedAt = previousUpdatedAt
            seriesEnabled = wasSeriesEnabled
            appModelNotice("That series could not be assigned.")
            return false
        }
    }

    private func detachFromSeries() {
        let previousSeriesID = brief.seriesID
        let previousEpisodeNumber = brief.episodeNumber
        let previousEpisodeLabel = brief.episodeLabel
        let previousSeriesName = output.seriesName
        let previousUpdatedAt = brief.updatedAt
        brief.seriesID = nil
        brief.episodeNumber = nil
        brief.episodeLabel = ""
        output.seriesName = ""
        brief.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            brief.seriesID = previousSeriesID
            brief.episodeNumber = previousEpisodeNumber
            brief.episodeLabel = previousEpisodeLabel
            output.seriesName = previousSeriesName
            brief.updatedAt = previousUpdatedAt
            appModelNotice("That post could not be removed from its series.")
        }
    }

    private func createSeries() {
        let name = newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let series = ContentSeries(
            workspaceID: brief.workspaceID ?? appModel.activeWorkspaceID,
            name: name,
            pillarID: brief.pillarID,
            platform: output.platform,
            destinationID: output.destinationID,
            formatID: output.formatID,
            socialAccountID: output.socialAccountID,
            durationSeconds: output.durationSeconds
        )
        context.insert(series)
        guard assignSeries(series) else { return }
        newSeriesName = ""
        isAddingSeries = false
        activeSetupPicker = nil
    }

    private static func hasMorePostDetails(_ output: PlatformOutput) -> Bool {
        [output.openingAdjustment, output.titleOverride, output.editChanges]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private struct SeriesDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var series: ContentSeries

    @State private var name: String
    @State private var frequency: PostRecurrenceFrequency
    @State private var weekdays: Set<PillarWeekday>
    @State private var monthDay: Int
    @State private var firstDate: Date
    @State private var includesTime: Bool
    @State private var usesEndDate: Bool
    @State private var endDate: Date
    @State private var notice: String?

    init(series: ContentSeries, suggestedFirstDate: Date) {
        self.series = series
        let firstDate = series.cadenceStartDate ?? suggestedFirstDate
        let initialFrequency = series.cadence == .none ? PostRecurrenceFrequency.weekly : series.cadence
        let initialEnd = series.cadenceEndDate
            ?? Calendar.current.date(byAdding: .month, value: 3, to: firstDate)
            ?? firstDate
        let firstWeekday = PillarWeekday(
            rawValue: Calendar.current.component(.weekday, from: firstDate)
        )
        _name = State(initialValue: series.name)
        _frequency = State(initialValue: initialFrequency)
        _weekdays = State(initialValue: series.cadenceWeekdays.isEmpty
            ? Set(firstWeekday.map { [$0] } ?? [])
            : series.cadenceWeekdays)
        _monthDay = State(initialValue: series.cadenceMonthDay ?? Calendar.current.component(.day, from: firstDate))
        _firstDate = State(initialValue: firstDate)
        _includesTime = State(initialValue: series.cadenceIncludesTime)
        _usesEndDate = State(initialValue: series.cadenceEndDate != nil)
        _endDate = State(initialValue: initialEnd)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (frequency != .weekly || !weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Series planner")
                        Text("Edit series details")
                            .font(.agentTitle)
                        Text("Set the recurring plan. Existing episode posts keep their current dates.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    }

                    VStack(spacing: 0) {
                        TextField("Series name", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 52)

                        Divider().overlay(Color.agentHairline)

                        Picker("Cadence", selection: $frequency) {
                            ForEach(PostRecurrenceFrequency.allCases.filter { $0 != .none }) { cadence in
                                Text(cadence.title).tag(cadence)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)

                        Divider().overlay(Color.agentHairline)

                        Toggle("Include a time", isOn: $includesTime)
                            .tint(Color.actionAccent)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 52)

                        Divider().overlay(Color.agentHairline)

                        DatePicker(
                            "First episode",
                            selection: $firstDate,
                            displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
                        )
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)
                    }
                    .font(.agentBody)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }

                    if frequency == .weekly {
                        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                            MetaLabel("Repeat on")
                            HStack(spacing: AgentSpacing.x2) {
                                ForEach(PillarWeekday.mondayFirst) { weekday in
                                    Button {
                                        if weekdays.contains(weekday) { weekdays.remove(weekday) }
                                        else { weekdays.insert(weekday) }
                                    } label: {
                                        Text(weekday.letter)
                                            .font(.agentMetadata)
                                            .foregroundStyle(weekdays.contains(weekday) ? Color.onAccent : Color.agentText)
                                            .frame(maxWidth: .infinity, minHeight: 42)
                                            .background(
                                                weekdays.contains(weekday) ? Color.actionAccent : Color.agentSurface,
                                                in: .circle
                                            )
                                            .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else if frequency == .monthly {
                        HStack {
                            Text("Day of month")
                            Spacer()
                            Picker("Day of month", selection: $monthDay) {
                                ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                        .font(.agentBody)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                    }

                    VStack(spacing: 0) {
                        Toggle("End date", isOn: $usesEndDate)
                            .tint(Color.actionAccent)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 52)

                        if usesEndDate {
                            Divider().overlay(Color.agentHairline)
                            DatePicker(
                                "Ends",
                                selection: $endDate,
                                in: Calendar.current.startOfDay(for: firstDate)...,
                                displayedComponents: .date
                            )
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 52)
                        }
                    }
                    .font(.agentBody)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }

                    if let notice {
                        Text(notice)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentDestructive)
                    }

                    Button("Save Series Details", action: save)
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                        .disabled(!canSave)
                }
                .padding(AgentLayout.pageMargin)
            }
            .background(Color.agentCanvas)
            .navigationTitle("Edit Series Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: firstDate) { _, newDate in
                guard usesEndDate,
                      Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: newDate) else {
                    return
                }
                endDate = Calendar.current.date(byAdding: .month, value: 1, to: newDate) ?? newDate
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let previousName = series.name
        let previousCadence = series.cadence
        let previousStartDate = series.cadenceStartDate
        let previousWeekdays = series.cadenceWeekdays
        let previousMonthDay = series.cadenceMonthDay
        let previousEndDate = series.cadenceEndDate
        let previouslyIncludedTime = series.cadenceIncludesTime
        let previousUpdatedAt = series.updatedAt
        series.name = trimmedName
        series.cadence = frequency
        series.cadenceStartDate = RecurringPostSchedule.normalizedTargetDate(
            firstDate,
            includesTime: includesTime
        )
        series.cadenceWeekdays = frequency == .weekly ? weekdays : []
        series.cadenceMonthDay = frequency == .monthly ? monthDay : nil
        series.cadenceEndDate = usesEndDate ? Calendar.current.startOfDay(for: endDate) : nil
        series.cadenceIncludesTime = includesTime
        series.updatedAt = Date()
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            series.name = previousName
            series.cadence = previousCadence
            series.cadenceStartDate = previousStartDate
            series.cadenceWeekdays = previousWeekdays
            series.cadenceMonthDay = previousMonthDay
            series.cadenceEndDate = previousEndDate
            series.cadenceIncludesTime = previouslyIncludedTime
            series.updatedAt = previousUpdatedAt
            notice = "The series details could not be saved. Your existing plan is unchanged."
        }
    }
}

private struct AddFutureEpisodesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var series: ContentSeries

    @State private var firstDate: Date
    @State private var plannedCount = 6
    @State private var notice: String?

    init(series: ContentSeries, suggestedStartDate: Date) {
        self.series = series
        _firstDate = State(initialValue: suggestedStartDate)
    }

    private var frequency: PostRecurrenceFrequency {
        series.cadence == .none ? .weekly : series.cadence
    }

    private var preview: [Date] {
        if let endDate = series.cadenceEndDate,
           Calendar.current.startOfDay(for: firstDate) > Calendar.current.startOfDay(for: endDate) {
            return []
        }
        return SeriesEpisodePlanner.previewDates(
            startingAt: firstDate,
            frequency: frequency,
            weekdays: series.cadenceWeekdays,
            monthDay: series.cadenceMonthDay,
            endDate: series.cadenceEndDate,
            count: plannedCount
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Upcoming episodes")
                        Text(series.name)
                            .font(.agentTitle)
                        Text("Add empty episode dates using this series schedule. No post is created until you choose an episode.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    }

                    VStack(spacing: 0) {
                        detailRow("Repeats", value: repeatDescription)
                        Divider().overlay(Color.agentHairline)
                        detailRow(
                            "Ends",
                            value: series.cadenceEndDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "No end date"
                        )
                    }
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }

                    VStack(spacing: 0) {
                        DatePicker(
                            "Next episode",
                            selection: $firstDate,
                            displayedComponents: series.cadenceIncludesTime ? [.date, .hourAndMinute] : [.date]
                        )
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)

                        Divider().overlay(Color.agentHairline)

                        Stepper("Add \(plannedCount) episodes", value: $plannedCount, in: 1...24)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 52)
                    }
                    .font(.agentBody)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionRuleHeader(title: "New episode dates", trailing: "\(preview.count)")
                        if preview.isEmpty {
                            Text("Extend the series end date before adding more episodes.")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                                .padding(.vertical, AgentSpacing.x4)
                        } else {
                            ForEach(Array(preview.enumerated()), id: \.offset) { index, date in
                                HStack {
                                    Text("Episode \(index + 1)")
                                        .font(.agentBody.weight(.semibold))
                                    Spacer()
                                    Text(date.formatted(
                                        series.cadenceIncludesTime
                                            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
                                            : .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                                    ))
                                    .font(.agentSubtext)
                                    .foregroundStyle(Color.agentSecondary)
                                }
                                .padding(.vertical, AgentSpacing.x3)
                                if index < preview.count - 1 {
                                    Divider().overlay(Color.agentHairline)
                                }
                            }
                        }
                    }

                    if let notice {
                        Text(notice)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    }

                    Button(action: addEpisodes) {
                        Text("Add \(preview.count) Future Episode\(preview.count == 1 ? "" : "s")")
                    }
                    .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                    .disabled(preview.isEmpty)
                }
                .padding(AgentLayout.pageMargin)
            }
            .background(Color.agentCanvas)
            .navigationTitle("Add Future Episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var repeatDescription: String {
        switch frequency {
        case .none:
            return "Does not repeat"
        case .daily:
            return "Daily"
        case .weekly:
            let days = PillarWeekday.mondayFirst
                .filter { series.cadenceWeekdays.contains($0) }
                .map(\.title)
            return days.isEmpty ? "Weekly" : "Weekly on \(days.joined(separator: ", "))"
        case .monthly:
            return "Monthly on day \(series.cadenceMonthDay ?? Calendar.current.component(.day, from: firstDate))"
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(spacing: AgentSpacing.x4) {
            Text(label)
                .font(.agentBody)
            Spacer(minLength: AgentSpacing.x3)
            Text(value)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 52)
    }

    private func addEpisodes() {
        do {
            let created = try SeriesEpisodePlanner.plan(
                series: series,
                dates: preview,
                includesTime: series.cadenceIncludesTime,
                context: context
            )
            notice = created.isEmpty
                ? "Those episode dates are already in Upcoming Episodes."
                : "\(created.count) future episode\(created.count == 1 ? "" : "s") added."
        } catch {
            notice = "Future episodes could not be added. Your existing plan is unchanged."
        }
    }
}

struct SeriesDetailView: View {
    private enum EpisodeGroup {
        case draft
        case scheduled
        case posted
    }

    private struct EpisodeItem: Identifiable {
        let brief: CreativeBrief
        let output: PlatformOutput?
        let group: EpisodeGroup
        let date: Date?

        var id: UUID { brief.id }

        var supportingText: String? {
            let trimmedLabel = brief.episodeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = brief.episodeNumber, !trimmedLabel.isEmpty {
                return "Episode \(number) · \(trimmedLabel)"
            }
            if let number = brief.episodeNumber {
                return "Episode \(number)"
            }
            return trimmedLabel.isEmpty ? nil : trimmedLabel
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var series: ContentSeries
    @Query(sort: \SeriesEpisodeSlot.plannedDate) private var allSlots: [SeriesEpisodeSlot]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query private var allOutputs: [PlatformOutput]
    @State private var showSeriesDetails = false
    @State private var showAddFutureEpisodes = false
    @State private var selectedSlot: SeriesEpisodeSlot?
    @State private var editingEpisodeBrief: CreativeBrief?
    @State private var confirmRemoveFutureSlots = false
    @State private var confirmArchive = false

    init(series: ContentSeries) {
        self.series = series
        let seriesID = series.id
        _allSlots = Query(
            filter: #Predicate<SeriesEpisodeSlot> { $0.seriesID == seriesID },
            sort: \SeriesEpisodeSlot.plannedDate
        )
        _allBriefs = Query(
            filter: #Predicate<CreativeBrief> { $0.seriesID == seriesID },
            sort: \CreativeBrief.updatedAt,
            order: .reverse
        )
        if let workspaceID = series.workspaceID {
            _allOutputs = Query(
                filter: #Predicate<PlatformOutput> {
                    $0.workspaceID == workspaceID || $0.workspaceID == nil
                }
            )
        }
    }

    private var slots: [SeriesEpisodeSlot] {
        allSlots.filter { $0.seriesID == series.id && $0.workspaceID == series.workspaceID }
    }
    private var episodes: [CreativeBrief] {
        allBriefs.filter { $0.seriesID == series.id && $0.workspaceID == series.workspaceID }
    }

    private var openSlots: [SeriesEpisodeSlot] {
        slots
            .filter { $0.status == .open }
            .sorted { $0.plannedDate < $1.plannedDate }
    }

    private var episodeItems: [EpisodeItem] {
        episodes.map { brief in
            let output = allOutputs.first(where: { $0.briefID == brief.id })
            let group: EpisodeGroup
            switch output?.status {
            case .posted:
                group = .posted
            case .scheduled:
                group = .scheduled
            default:
                group = .draft
            }
            return EpisodeItem(
                brief: brief,
                output: output,
                group: group,
                date: output?.postedAt ?? output?.targetDate ?? brief.workDate
            )
        }
        .sorted {
            switch ($0.date, $1.date) {
            case let (.some(lhs), .some(rhs)): lhs < rhs
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): $0.brief.updatedAt > $1.brief.updatedAt
            }
        }
    }

    private var futureOpenSlotCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return openSlots.filter { $0.plannedDate >= today }.count
    }

    private var summaryText: String {
        let episodeText = "\(episodes.count) episode\(episodes.count == 1 ? "" : "s")"
        guard !openSlots.isEmpty else { return episodeText }
        return "\(episodeText) · \(openSlots.count) date\(openSlots.count == 1 ? "" : "s") to fill"
    }

    private var firstEpisodeDate: Date {
        ([series.cadenceStartDate] + slots.map { Optional($0.plannedDate) } + episodeItems.map(\.date))
            .compactMap { $0 }
            .min() ?? Date()
    }

    private var nextEpisodeDate: Date {
        let latestDate = (slots.map(\.plannedDate) + episodeItems.compactMap(\.date)).max()
            ?? series.cadenceStartDate
            ?? Date()
        return SeriesEpisodePlanner.nextEpisodeDate(after: latestDate, series: series)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        MetaLabel("\(series.state.title) series")
                        Text(series.name)
                            .font(.agentTitle)
                            .foregroundStyle(Color.agentText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(summaryText)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    }

                    Button {
                        showSeriesDetails = true
                    } label: {
                        HStack(spacing: AgentSpacing.x2) {
                            AgentIconView(.pencil, size: 13)
                            Text("Edit Series Details")
                        }
                    }
                    .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        slotSection(
                            title: "Upcoming episodes",
                            slots: openSlots,
                            emptyMessage: "No episode dates are waiting to be filled."
                        )
                        AgentBlockAddActionButton(title: "Add Future Episodes") {
                            showAddFutureEpisodes = true
                        }
                    }
                    episodeSection(
                        "Draft episodes",
                        items: episodeItems.filter { $0.group == .draft },
                        emptyMessage: "No draft episodes."
                    )
                    episodeSection(
                        "Scheduled episodes",
                        items: episodeItems.filter { $0.group == .scheduled },
                        emptyMessage: "No episodes are scheduled."
                    )
                    episodeSection(
                        "Posted episodes",
                        items: episodeItems.filter { $0.group == .posted },
                        emptyMessage: "Nothing has been posted yet."
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        SectionRuleHeader(title: "Series settings")

                        managementAction(
                            title: series.state == .paused ? "Resume series" : "Pause series",
                            detail: series.state == .paused
                                ? "Make this series active again."
                                : "Keep every episode and stop planning new ones."
                        ) {
                            let previousState = series.state
                            series.state = series.state == .paused ? .active : .paused
                            do {
                                try context.save()
                            } catch {
                                context.rollback()
                                series.state = previousState
                                appModel.notice = .error("That series status could not be saved.")
                            }
                        }

                        Divider().overlay(Color.agentHairline)

                        managementAction(
                            title: "Remove future empty slots",
                            detail: futureOpenSlotCount == 0
                                ? "There are no future empty slots."
                                : "Keep every episode and remove \(futureOpenSlotCount) unfilled date\(futureOpenSlotCount == 1 ? "" : "s").",
                            isDestructive: true,
                            isEnabled: futureOpenSlotCount > 0
                        ) {
                            confirmRemoveFutureSlots = true
                        }

                        Divider().overlay(Color.agentHairline)

                        managementAction(
                            title: "Archive series",
                            detail: "Hide the series and keep its episodes.",
                            isDestructive: true
                        ) {
                            confirmArchive = true
                        }
                    }
                    .padding(AgentSpacing.x5)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: .card)
                }
                .padding(AgentLayout.pageMargin)
            }
            .background(Color.agentCanvas)
            .navigationTitle("Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) {
                        dismiss()
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showSeriesDetails) {
                SeriesDetailsEditorView(
                    series: series,
                    suggestedFirstDate: firstEpisodeDate
                )
            }
            .sheet(isPresented: $showAddFutureEpisodes) {
                AddFutureEpisodesView(
                    series: series,
                    suggestedStartDate: nextEpisodeDate
                )
            }
            .sheet(item: $selectedSlot) { slot in
                EpisodeSlotActionsView(slot: slot) { result in
                    editingEpisodeBrief = result.brief
                }
            }
            .navigationDestination(item: $editingEpisodeBrief) { brief in
                if let output = allOutputs.first(where: { $0.briefID == brief.id }) {
                    ResumablePostEditorView(
                        brief: brief,
                        output: output,
                        contextLabel: "Series episode",
                        onSpark: {}
                    )
                    .navigationTitle("Plan Episode")
                    .navigationBarTitleDisplayMode(.inline)
                    .agentScreen()
                    .agentKeyboardDismissal()
                } else {
                    IdeaPostDraftView(brief: brief)
                }
            }
            .alert("Remove future empty slots?", isPresented: $confirmRemoveFutureSlots) {
                Button("Remove slots", role: .destructive) {
                    let today = Calendar.current.startOfDay(for: Date())
                    slots
                        .filter { $0.status == .open && $0.plannedDate >= today }
                        .forEach(context.delete)
                    do {
                        try context.save()
                    } catch {
                        context.rollback()
                        appModel.notice = .error("Those future episode slots could not be removed.")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Existing episodes stay in place. Only future slots that have not become posts are removed.")
            }
            .alert("Archive this series?", isPresented: $confirmArchive) {
                Button("Archive series", role: .destructive) {
                    let previousState = series.state
                    series.state = .archived
                    do {
                        try context.save()
                        dismiss()
                    } catch {
                        context.rollback()
                        series.state = previousState
                        appModel.notice = .error("That series could not be archived.")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The series will be hidden. Its existing episodes will stay available.")
            }
        }
    }

    private func slotSection(
        title: String,
        slots: [SeriesEpisodeSlot],
        emptyMessage: String
    ) -> some View {
        sectionCard(title: title, count: slots.count) {
            if slots.isEmpty {
                emptySection(message: emptyMessage)
            } else {
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    Button {
                        selectedSlot = slot
                    } label: {
                        episodeRow(
                            title: "Episode needed",
                            supportingText: slot.includesTime ? "Time selected" : nil,
                            date: slot.plannedDate,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    if index < slots.count - 1 {
                        Divider().overlay(Color.agentHairline)
                    }
                }
            }
        }
    }

    private func episodeSection(
        _ title: String,
        items: [EpisodeItem],
        emptyMessage: String
    ) -> some View {
        sectionCard(title: title, count: items.count) {
            if items.isEmpty {
                emptySection(message: emptyMessage)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if let output = item.output {
                        NavigationLink {
                            PostOutputDetailView(brief: item.brief, output: output)
                        } label: {
                            episodeRow(
                                title: item.brief.title,
                                supportingText: item.supportingText,
                                date: item.date,
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        episodeRow(
                            title: item.brief.title,
                            supportingText: item.supportingText,
                            date: item.date,
                            showsChevron: false
                        )
                    }

                    if index < items.count - 1 {
                        Divider().overlay(Color.agentHairline)
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: title, trailing: "\(count)")
            content()
        }
        .padding(AgentSpacing.x5)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: .card)
    }

    private func emptySection(message: String) -> some View {
        Text(message)
            .font(.agentSubtext)
            .foregroundStyle(Color.agentSecondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.top, AgentSpacing.x2)
    }

    private func episodeRow(
        title: String,
        supportingText: String?,
        date: Date?,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: AgentSpacing.x3) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(title)
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let supportingText {
                    Text(supportingText)
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AgentSpacing.x3)

            VStack(alignment: .trailing, spacing: AgentSpacing.x2) {
                Text(date.map {
                    $0.formatted(.dateTime.month(.abbreviated).day())
                } ?? "No date")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .monospacedDigit()

                if showsChevron {
                    AgentIconView(.forward, size: 12)
                        .foregroundStyle(Color.agentSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(.rect)
    }

    private func managementAction(
        title: String,
        detail: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title)
                        .font(.agentBody.weight(.semibold))
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: AgentSpacing.x3)

                AgentIconView(.forward, size: 12)
                    .foregroundStyle(isDestructive ? Color.agentDestructive : Color.agentSecondary)
            }
            .foregroundStyle(isDestructive ? Color.agentDestructive : Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

#if targetEnvironment(macCatalyst)
/// Catalyst can append a stale keyboard-avoidance region below SwiftUI's real
/// scroll content. SwiftUI scroll-position writes are ignored while Page Down,
/// a wheel, or momentum owns the gesture, so clamp the backing UIScrollView at
/// the actual bottom marker instead.
private struct CatalystEditorScrollEndAnchor: UIViewRepresentable {
    @MainActor
    final class Coordinator: NSObject {
        weak var marker: UIView?
        weak var scrollView: UIScrollView?
        var contentOffsetObservation: NSKeyValueObservation?
        var isClamping = false
        var attachmentScheduled = false

        func connect(marker: UIView) {
            self.marker = marker
            attachToContainingScrollViewIfNeeded()
        }

        private func attachToContainingScrollViewIfNeeded() {
            guard let marker else { return }

            var ancestor = marker.superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }

            guard let containingScrollView = ancestor as? UIScrollView else {
                guard !attachmentScheduled else { return }
                attachmentScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.attachmentScheduled = false
                    self?.attachToContainingScrollViewIfNeeded()
                }
                return
            }

            guard scrollView !== containingScrollView else {
                clampIfNeeded()
                return
            }

            contentOffsetObservation = nil
            scrollView = containingScrollView
            contentOffsetObservation = containingScrollView.observe(
                \.contentOffset,
                options: [.new]
            ) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.clampIfNeeded()
                }
            }
            clampIfNeeded()
        }

        func clampIfNeeded() {
            guard !isClamping,
                  let marker,
                  let scrollView,
                  marker.window != nil,
                  scrollView.window != nil,
                  scrollView.bounds.height > 0
            else { return }

            // Calculate the document-space end from window coordinates so the
            // value stays correct before, during, and after an overscroll.
            let markerBottomInWindow = marker.convert(
                CGPoint(x: marker.bounds.midX, y: marker.bounds.maxY),
                to: nil
            ).y
            let viewportTopInWindow = scrollView.convert(
                CGPoint(x: scrollView.bounds.minX, y: scrollView.bounds.minY),
                to: nil
            ).y
            let documentEnd = scrollView.contentOffset.y
                + markerBottomInWindow
                - viewportTopInWindow
            guard documentEnd.isFinite else { return }

            let minimumOffset = -scrollView.adjustedContentInset.top
            let maximumOffset = max(
                minimumOffset,
                documentEnd - scrollView.bounds.height
            )
            guard scrollView.contentOffset.y > maximumOffset + 0.5 else { return }

            isClamping = true
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: maximumOffset),
                animated: false
            )
            isClamping = false
        }
    }

    final class MarkerView: UIView {
        var onLayout: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onLayout?(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MarkerView {
        let marker = MarkerView(frame: .zero)
        marker.isUserInteractionEnabled = false
        marker.backgroundColor = .clear
        marker.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.connect(marker: view)
        }
        return marker
    }

    func updateUIView(_ marker: MarkerView, context: Context) {
        context.coordinator.connect(marker: marker)
    }
}
#endif

enum PostDraftSavePolicy {
    static func prepare(_ brief: CreativeBrief) {
        if brief.isBrandCollaboration,
           (brief.compensationType == .paid || brief.compensationType == .both),
           brief.compensationCurrencyCode.isEmpty {
            brief.compensationCurrencyCode = "USD"
        }
    }
}

enum PostDraftTargetPersistencePolicy {
    static func shouldWriteTargetDate(
        hadPersistedTargetDate: Bool,
        explicitlyCommitted: Bool
    ) -> Bool {
        hadPersistedTargetDate || explicitlyCommitted
    }
}

@MainActor
struct PostDraftEditorStoredState {
    private struct BriefState {
        let workspaceID: UUID?
        let title: String
        let premise: String
        let notes: String
        let scriptEnabled: Bool
        let audience: String
        let creativeGoal: String
        let takeaway: String
        let durationSeconds: Int
        let spokenHook: String
        let firstFrameText: String
        let scriptBeatsText: String
        let close: String
        let ctaIntent: String
        let filmingGuidance: String
        let editingGuidance: String
        let assumptionsText: String
        let voiceConfidence: Double
        let readyBriefPayloadJSON: String
        let lifecycleHistoryText: String
        let sourceRaw: String
        let statusRaw: String
        let customStatusLabel: String?
        let ideaBankPlacementRaw: String?
        let pillarID: UUID?
        let preferredDestinationID: UUID?
        let preferredFormatID: UUID?
        let seriesID: UUID?
        let inspirationSourceID: UUID?
        let episodeNumber: Int?
        let episodeLabel: String
        let brandPartnerID: UUID?
        let isBrandCollaboration: Bool
        let brandName: String
        let compensationTypeRaw: String
        let compensationAmount: Double?
        let compensationCurrencyCode: String
        let brandHasNetTerms: Bool
        let brandNetTermsDays: Int
        let giftedProductDescription: String
        let giftedEstimatedValue: Double?
        let promoCode: String
        let promoLinkString: String
        let moodBoardEnabled: Bool
        let moodBoardURLString: String
        let workDate: Date?
        let includesWorkTime: Bool
        let agendaDate: Date?
        let updatedAt: Date

        init(_ brief: CreativeBrief) {
            workspaceID = brief.workspaceID
            title = brief.title
            premise = brief.premise
            notes = brief.notes
            scriptEnabled = brief.scriptEnabled
            audience = brief.audience
            creativeGoal = brief.creativeGoal
            takeaway = brief.takeaway
            durationSeconds = brief.durationSeconds
            spokenHook = brief.spokenHook
            firstFrameText = brief.firstFrameText
            scriptBeatsText = brief.scriptBeatsText
            close = brief.close
            ctaIntent = brief.ctaIntent
            filmingGuidance = brief.filmingGuidance
            editingGuidance = brief.editingGuidance
            assumptionsText = brief.assumptionsText
            voiceConfidence = brief.voiceConfidence
            readyBriefPayloadJSON = brief.readyBriefPayloadJSON
            lifecycleHistoryText = brief.lifecycleHistoryText
            sourceRaw = brief.sourceRaw
            statusRaw = brief.statusRaw
            customStatusLabel = brief.customStatusLabel
            ideaBankPlacementRaw = brief.ideaBankPlacementRaw
            pillarID = brief.pillarID
            preferredDestinationID = brief.preferredDestinationID
            preferredFormatID = brief.preferredFormatID
            seriesID = brief.seriesID
            inspirationSourceID = brief.inspirationSourceID
            episodeNumber = brief.episodeNumber
            episodeLabel = brief.episodeLabel
            brandPartnerID = brief.brandPartnerID
            isBrandCollaboration = brief.isBrandCollaboration
            brandName = brief.brandName
            compensationTypeRaw = brief.compensationTypeRaw
            compensationAmount = brief.compensationAmount
            compensationCurrencyCode = brief.compensationCurrencyCode
            brandHasNetTerms = brief.brandHasNetTerms
            brandNetTermsDays = brief.brandNetTermsDays
            giftedProductDescription = brief.giftedProductDescription
            giftedEstimatedValue = brief.giftedEstimatedValue
            promoCode = brief.promoCode
            promoLinkString = brief.promoLinkString
            moodBoardEnabled = brief.moodBoardEnabled
            moodBoardURLString = brief.moodBoardURLString
            workDate = brief.workDate
            includesWorkTime = brief.includesWorkTime
            agendaDate = brief.agendaDate
            updatedAt = brief.updatedAt
        }

        func restore(_ brief: CreativeBrief) {
            brief.workspaceID = workspaceID
            brief.title = title
            brief.premise = premise
            brief.notes = notes
            brief.scriptEnabled = scriptEnabled
            brief.audience = audience
            brief.creativeGoal = creativeGoal
            brief.takeaway = takeaway
            brief.durationSeconds = durationSeconds
            brief.spokenHook = spokenHook
            brief.firstFrameText = firstFrameText
            brief.scriptBeatsText = scriptBeatsText
            brief.close = close
            brief.ctaIntent = ctaIntent
            brief.filmingGuidance = filmingGuidance
            brief.editingGuidance = editingGuidance
            brief.assumptionsText = assumptionsText
            brief.voiceConfidence = voiceConfidence
            brief.readyBriefPayloadJSON = readyBriefPayloadJSON
            brief.lifecycleHistoryText = lifecycleHistoryText
            brief.sourceRaw = sourceRaw
            brief.statusRaw = statusRaw
            brief.customStatusLabel = customStatusLabel
            brief.ideaBankPlacementRaw = ideaBankPlacementRaw
            brief.pillarID = pillarID
            brief.preferredDestinationID = preferredDestinationID
            brief.preferredFormatID = preferredFormatID
            brief.seriesID = seriesID
            brief.inspirationSourceID = inspirationSourceID
            brief.episodeNumber = episodeNumber
            brief.episodeLabel = episodeLabel
            brief.brandPartnerID = brandPartnerID
            brief.isBrandCollaboration = isBrandCollaboration
            brief.brandName = brandName
            brief.compensationTypeRaw = compensationTypeRaw
            brief.compensationAmount = compensationAmount
            brief.compensationCurrencyCode = compensationCurrencyCode
            brief.brandHasNetTerms = brandHasNetTerms
            brief.brandNetTermsDays = brandNetTermsDays
            brief.giftedProductDescription = giftedProductDescription
            brief.giftedEstimatedValue = giftedEstimatedValue
            brief.promoCode = promoCode
            brief.promoLinkString = promoLinkString
            brief.moodBoardEnabled = moodBoardEnabled
            brief.moodBoardURLString = moodBoardURLString
            brief.workDate = workDate
            brief.includesWorkTime = includesWorkTime
            brief.agendaDate = agendaDate
            brief.updatedAt = updatedAt
        }
    }

    private struct OutputState {
        let workspaceID: UUID?
        let platformRaw: String
        let destinationID: UUID?
        let formatID: UUID?
        let socialAccountID: UUID?
        let durationSeconds: Int
        let caption: String
        let openingAdjustment: String
        let titleOverride: String
        let cta: String
        let editChanges: String
        let statusRaw: String
        let targetDate: Date?
        let postedAt: Date?
        let seriesName: String
        let recurrenceRaw: String
        let recurrenceWeekdaysRaw: String
        let recurrenceMonthDay: Int?
        let recurrenceEndDate: Date?
        let includesTargetTime: Bool
        let seriesRootOutputID: UUID?
        let coverAttachmentID: UUID?
        let publishedURLString: String

        init(_ output: PlatformOutput) {
            workspaceID = output.workspaceID
            platformRaw = output.platformRaw
            destinationID = output.destinationID
            formatID = output.formatID
            socialAccountID = output.socialAccountID
            durationSeconds = output.durationSeconds
            caption = output.caption
            openingAdjustment = output.openingAdjustment
            titleOverride = output.titleOverride
            cta = output.cta
            editChanges = output.editChanges
            statusRaw = output.statusRaw
            targetDate = output.targetDate
            postedAt = output.postedAt
            seriesName = output.seriesName
            recurrenceRaw = output.recurrenceRaw
            recurrenceWeekdaysRaw = output.recurrenceWeekdaysRaw
            recurrenceMonthDay = output.recurrenceMonthDay
            recurrenceEndDate = output.recurrenceEndDate
            includesTargetTime = output.includesTargetTime
            seriesRootOutputID = output.seriesRootOutputID
            coverAttachmentID = output.coverAttachmentID
            publishedURLString = output.publishedURLString
        }

        func restore(_ output: PlatformOutput) {
            output.workspaceID = workspaceID
            output.platformRaw = platformRaw
            output.destinationID = destinationID
            output.formatID = formatID
            output.socialAccountID = socialAccountID
            output.durationSeconds = durationSeconds
            output.caption = caption
            output.openingAdjustment = openingAdjustment
            output.titleOverride = titleOverride
            output.cta = cta
            output.editChanges = editChanges
            output.statusRaw = statusRaw
            output.targetDate = targetDate
            output.postedAt = postedAt
            output.seriesName = seriesName
            output.recurrenceRaw = recurrenceRaw
            output.recurrenceWeekdaysRaw = recurrenceWeekdaysRaw
            output.recurrenceMonthDay = recurrenceMonthDay
            output.recurrenceEndDate = recurrenceEndDate
            output.includesTargetTime = includesTargetTime
            output.seriesRootOutputID = seriesRootOutputID
            output.coverAttachmentID = coverAttachmentID
            output.publishedURLString = publishedURLString
        }
    }

    private struct TaskState {
        let id: UUID
        let targetDate: Date?
        let includesTargetTime: Bool
        let dailyFocusDate: Date?

        init(_ task: CreatorTask) {
            id = task.id
            targetDate = task.targetDate
            includesTargetTime = task.includesTargetTime
            dailyFocusDate = task.dailyFocusDate
        }

        func restore(_ task: CreatorTask) {
            task.targetDate = targetDate
            task.includesTargetTime = includesTargetTime
            task.dailyFocusDate = dailyFocusDate
        }
    }

    private let brief: BriefState
    private let output: OutputState
    private let tasks: [UUID: TaskState]

    static func load(
        briefID: UUID,
        outputID: UUID,
        context: ModelContext
    ) throws -> Self {
        let reader = ModelContext(context.container)
        guard let storedBrief = try reader.fetch(FetchDescriptor<CreativeBrief>(
            predicate: #Predicate { $0.id == briefID }
        )).first,
        let storedOutput = try reader.fetch(FetchDescriptor<PlatformOutput>(
            predicate: #Predicate { $0.id == outputID }
        )).first else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let storedTasks = try reader.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.briefID == briefID }
        ))
        return Self(
            brief: BriefState(storedBrief),
            output: OutputState(storedOutput),
            tasks: Dictionary(uniqueKeysWithValues: storedTasks.map { ($0.id, TaskState($0)) })
        )
    }

    private init(
        brief: BriefState,
        output: OutputState,
        tasks: [UUID: TaskState]
    ) {
        self.brief = brief
        self.output = output
        self.tasks = tasks
    }

    func restore(
        brief: CreativeBrief,
        output: PlatformOutput,
        tasks currentTasks: [CreatorTask]
    ) {
        self.brief.restore(brief)
        self.output.restore(output)
        for task in currentTasks {
            tasks[task.id]?.restore(task)
        }
    }
}

@MainActor
enum PostDraftEditorPersistencePolicy {
    enum Error: Swift.Error, Equatable {
        case emptyTitle
    }

    @discardableResult
    static func save(
        brief: CreativeBrief,
        output: PlatformOutput,
        outputs: [PlatformOutput],
        notes: String,
        hasWorkDate: Bool,
        workDate: Date,
        hasTargetDate: Bool,
        targetDate: Date,
        writesTargetDate: Bool,
        now: Date = Date(),
        rescheduleLinkedTasks: (_ previousDate: Date?, _ newDate: Date?) -> Void,
        persist: () throws -> Void,
        rollback: () -> Void
    ) throws -> Date {
        let cleanTitle = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            rollback()
            throw Error.emptyTitle
        }

        let normalizedTargetDate = hasTargetDate
            ? RecurringPostSchedule.normalizedTargetDate(
                targetDate,
                includesTime: output.includesTargetTime
            )
            : targetDate
        let normalizedWorkDate = hasWorkDate
            ? RecurringPostSchedule.normalizedTargetDate(
                workDate,
                includesTime: brief.includesWorkTime
            )
            : nil

        brief.title = cleanTitle
        brief.notes = notes
        brief.workDate = normalizedWorkDate
        PostDraftSavePolicy.prepare(brief)
        if writesTargetDate {
            let previousDate = output.targetDate
            let nextDate = hasTargetDate ? normalizedTargetDate : nil
            rescheduleLinkedTasks(previousDate, nextDate)
            output.targetDate = nextDate
            brief.agendaDate = outputs.compactMap(\.targetDate).min()
        }
        brief.durationSeconds = output.durationSeconds
        brief.updatedAt = now

        do {
            try persist()
            return normalizedTargetDate
        } catch {
            rollback()
            throw error
        }
    }
}

enum PostDraftExitPersistencePolicy {
    static func shouldPersist(
        isDeleting: Bool,
        didMoveToIdeaBank: Bool,
        didPersistBeforeExit: Bool = false
    ) -> Bool {
        !isDeleting && !didMoveToIdeaBank && !didPersistBeforeExit
    }
}

enum EmptyPostDraftDeletionPolicy {
    static func shouldOfferDirectDelete(
        brief: CreativeBrief,
        output: PlatformOutput,
        taskCount: Int,
        attachmentCount: Int
    ) -> Bool {
        guard [.spark, .developing].contains(brief.status), output.status == .draft else { return false }
        guard taskCount == 0, attachmentCount == 0 else { return false }
        guard output.recurrence == .none else { return false }
        guard !brief.isBrandCollaboration,
              brief.compensationAmount == nil,
              brief.giftedEstimatedValue == nil,
              !brief.moodBoardEnabled else { return false }

        let textValues = [
            brief.title,
            brief.premise,
            brief.notes,
            brief.audience,
            brief.creativeGoal,
            brief.takeaway,
            brief.spokenHook,
            brief.firstFrameText,
            brief.scriptBeatsText,
            brief.close,
            brief.ctaIntent,
            brief.filmingGuidance,
            brief.editingGuidance,
            brief.assumptionsText,
            brief.readyBriefPayloadJSON,
            brief.brandName,
            brief.giftedProductDescription,
            brief.promoCode,
            brief.promoLinkString,
            output.caption,
            output.openingAdjustment,
            output.titleOverride,
            output.cta,
            output.editChanges,
            output.publishedURLString,
            output.seriesName
        ]

        return textValues.allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

@MainActor
@Observable
final class PostEditorSaveCoordinator {
    var save: (() -> Bool)?

    func commit() -> Bool { save?() ?? false }
}

@MainActor
@Observable
final class PostEditorTextCommitCoordinator {
    private struct PendingValue {
        var value: String
        let write: (String) -> Void
    }

    @ObservationIgnored private var pending: [String: PendingValue] = [:]

    func update(key: String, value: String, write: @escaping (String) -> Void) {
        pending[key] = PendingValue(value: value, write: write)
    }

    func remove(key: String) {
        pending.removeValue(forKey: key)
    }

    func commitAll() {
        for pendingValue in pending.values {
            pendingValue.write(pendingValue.value)
        }
    }
}

private struct PostEditorTextField: View {
    @Environment(PostEditorTextCommitCoordinator.self) private var commitCoordinator
    let label: String
    @Binding var text: String
    @State private var draftText: String
    var axis: Axis = .vertical
    var minimumHeight: CGFloat = 72
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    @FocusState private var isFocused: Bool

    init(
        label: String,
        text: Binding<String>,
        axis: Axis = .vertical,
        minimumHeight: CGFloat = 72,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil
    ) {
        self.label = label
        _text = text
        _draftText = State(initialValue: text.wrappedValue)
        self.axis = axis
        self.minimumHeight = minimumHeight
        self.keyboardType = keyboardType
        self.textContentType = textContentType
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) {
                isFocused = false
            }
            TextField("", text: $draftText, axis: axis)
                .font(.agentBody)
                .lineLimit(axis == .vertical ? 2...8 : 1...1)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(keyboardType == .URL ? .never : .sentences)
                .autocorrectionDisabled(keyboardType == .URL)
                .padding(AgentSpacing.x4)
                .frame(minHeight: axis == .vertical ? minimumHeight : 52, alignment: .topLeading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .focused($isFocused)
        }
        .onAppear {
            registerDraft(draftText)
        }
        .onChange(of: draftText) { _, newValue in
            registerDraft(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commitDraft() }
        }
        .onChange(of: text) { _, newValue in
            guard !isFocused, newValue != draftText else { return }
            draftText = newValue
        }
        .onDisappear {
            commitDraft()
            commitCoordinator.remove(key: label)
        }
    }

    private func registerDraft(_ value: String) {
        commitCoordinator.update(key: label, value: value) { text = $0 }
    }

    private func commitDraft() {
        guard text != draftText else { return }
        text = draftText
    }
}

private struct BufferedPostTitleField: View {
    @Environment(PostEditorTextCommitCoordinator.self) private var commitCoordinator
    @Binding var text: String
    @State private var draftText: String
    @FocusState private var isFocused: Bool

    init(text: Binding<String>) {
        _text = text
        _draftText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField("Post title", text: $draftText, axis: .vertical)
            .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
            .tracking(-0.56)
            .lineLimit(1...3)
            .focused($isFocused)
            .onAppear {
                registerDraft(draftText)
            }
            .onChange(of: draftText) { _, newValue in
                registerDraft(newValue)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commitDraft() }
            }
            .onChange(of: text) { _, newValue in
                guard !isFocused, newValue != draftText else { return }
                draftText = newValue
            }
            .onDisappear {
                commitDraft()
                commitCoordinator.remove(key: "post-title")
            }
    }

    private func registerDraft(_ value: String) {
        commitCoordinator.update(key: "post-title", value: value) { text = $0 }
    }

    private func commitDraft() {
        guard text != draftText else { return }
        text = draftText
    }
}

private struct BufferedPostNotesEditor: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentInputHeader(title: "Notes", isEditing: isFocused) {
                isFocused = false
            }
            TextEditor(text: $text)
                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                .scrollContentBackground(.hidden)
                // TextEditor has an unbounded ideal height inside a vertical
                // ScrollView on Catalyst. A minimum alone lets it inflate the
                // editor's document far beyond the visible notes field.
                .frame(height: 160)
                .padding(16)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.panel)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .focused($isFocused)
        }
    }
}

private struct PostAttachmentRow: View {
    let attachment: CreatorAttachment
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(attachment.fileName)
                    .font(.agentBody)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                AgentIconView(.trash)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(attachment.fileName)")
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
    }
}

private struct PostMediaThumbnail: View {
    let attachment: CreatorAttachment
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if attachment.kind == .photo,
                   let data = attachment.cloudData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.agentCanvas
                        AgentIconView(attachment.kind == .video ? .play : .copy)
                            .font(.agentInter(size: 24, weight: .medium, relativeTo: .title3))
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
            }
            .frame(width: 104, height: 118)
            .clipShape(.rect(cornerRadius: AgentRadius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.panel)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }

            Button(role: .destructive, action: onDelete) {
                AgentIconView(.close, size: 10)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.fileName)")

            if attachment.kind == .video {
                AgentIconView(.video, size: 11)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.agentPureBlack.opacity(0.58), in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 104, height: 118)
    }
}

private struct PostDraftSetupRow: View {
    let label: String
    let value: String
    var color: Color?
    var indicator: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            MetaLabel(label)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)
            HStack(spacing: AgentSpacing.x2) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .layoutPriority(1)
                if let indicator {
                    Text(indicator.uppercased())
                        .font(.agentMetadata)
                        .tracking(0.5)
                        .foregroundStyle(Color.agentDestructive)
                        .padding(.horizontal, AgentSpacing.x2)
                        .frame(minHeight: 22)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.agentDestructive, lineWidth: 1)
                        }
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if showsChevron {
                AgentIconView(.forward, size: 12)
                    .fixedSize()
            }
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
        .contentShape(.rect)
    }
}

struct PostDatesPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scheduledDate: Date
    @State private var hasScheduledDate: Bool
    @State private var includesScheduledTime: Bool
    @State private var workDate: Date
    @State private var hasWorkDate: Bool
    @State private var includesWorkTime: Bool
    let activeStep: PostDatePlanningStep
    let pillarMarkers: [PillarCalendarMarker]
    let requiredStep: PostDatePlanningStep?
    let confirmationTitle: String
    let isRescheduling: Bool
    let onSave: (PostDatePlanDraft) -> Void

    init(
        scheduledDate: Date,
        hasScheduledDate: Bool,
        includesScheduledTime: Bool,
        workDate: Date,
        hasWorkDate: Bool,
        includesWorkTime: Bool,
        pillarMarkers: [PillarCalendarMarker],
        initialStep: PostDatePlanningStep,
        requiredStep: PostDatePlanningStep?,
        confirmationTitle: String,
        isRescheduling: Bool = false,
        onSave: @escaping (PostDatePlanDraft) -> Void
    ) {
        _scheduledDate = State(initialValue: isRescheduling ? max(scheduledDate, Date()) : scheduledDate)
        _hasScheduledDate = State(initialValue: hasScheduledDate)
        _includesScheduledTime = State(initialValue: includesScheduledTime)
        _workDate = State(initialValue: workDate)
        _hasWorkDate = State(initialValue: hasWorkDate)
        _includesWorkTime = State(initialValue: includesWorkTime)
        self.activeStep = initialStep
        self.pillarMarkers = pillarMarkers
        self.requiredStep = requiredStep
        self.confirmationTitle = confirmationTitle
        self.isRescheduling = isRescheduling
        self.onSave = onSave
    }

    var body: some View {
#if targetEnvironment(macCatalyst)
        if isRescheduling {
            desktopRescheduleBody
        } else {
            standardBody
        }
#else
        standardBody
#endif
    }

    private var standardBody: some View {
        NavigationStack {
            ScrollView {
                planningLayout
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x5)
                    .padding(.bottom, AgentSpacing.x8)
            }
            .navigationTitle("Plan this post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .confirmationAction) {
                    AgentToolbarIconButton(
                        title: confirmationTitle,
                        icon: .check,
                        isEnabled: canSave
                    ) {
                        saveAndDismiss()
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

#if targetEnvironment(macCatalyst)
    private var desktopRescheduleBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: AgentSpacing.x3) {
                Text("Reschedule post")
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    AgentIconView(.close, size: 14)
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
            .padding(.leading, AgentSpacing.x5)
            .padding(.trailing, AgentSpacing.x3)
            .padding(.top, AgentSpacing.x3)

            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                Text("Choose a new scheduled date.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)

                PillarCalendarDatePicker(
                    date: $scheduledDate,
                    pillarMarkers: pillarMarkers,
                    minimumDate: Date(),
                    cellHeight: 38,
                    dayDiameter: 28
                )
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.card)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }

                dateTimeControls(
                    includesTime: $includesScheduledTime,
                    date: $scheduledDate
                )
            }
            .padding(.horizontal, AgentSpacing.x5)
            .padding(.top, AgentSpacing.x2)
            .padding(.bottom, AgentSpacing.x5)

            Divider().overlay(Color.agentHairline)

            HStack(spacing: AgentSpacing.x3) {
                Button("Cancel") { dismiss() }
                    .font(.agentSubtext.weight(.medium))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 92)
                    .frame(minHeight: 44)
                    .contentShape(.rect(cornerRadius: AgentRadius.card))
                    .buttonStyle(.plain)

                Button(action: saveAndDismiss) {
                    Text("Save new date")
                        .font(.agentSubtext.weight(.medium))
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.card)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(AgentSpacing.x4)
        }
        .frame(width: 500)
        .background(Color.agentCanvas)
        .agentScreen()
        .presentationSizing(.fitted)
        .presentationCornerRadius(AgentRadius.floating)
        .presentationBackground(Color.agentCanvas)
    }
#endif

    private func saveAndDismiss() {
        onSave(
            PostDatePlanDraft(
                workDate: workDate,
                hasWorkDate: hasWorkDate,
                includesWorkTime: includesWorkTime,
                scheduledDate: scheduledDate,
                hasScheduledDate: hasScheduledDate,
                includesScheduledTime: includesScheduledTime
            )
        )
        dismiss()
    }

    private var planningLayout: some View {
        activeCalendar
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    private var activeCalendar: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            Text(activeQuestion)
                .font(.agentHeadline)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(activeDateToggleLabel, isOn: activeDateEnabledBinding)
                .font(.agentBody.weight(.semibold))
                .tint(Color.actionAccent)
                .frame(minHeight: 44)

            if activeDateIsSet {
                PillarCalendarDatePicker(
                    date: activeDateBinding,
                    pillarMarkers: activeStep == .schedule ? pillarMarkers : []
                )
                .frame(minHeight: 330)
                .accessibilityLabel(activeStep == .work ? "Work date" : "Scheduled date")
            }

            if activeStep == .schedule && hasScheduledDate {
                Text("Pillar days are marked by color.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }

            if activeDateIsSet {
                dateTimeControls(
                    includesTime: activeIncludesTimeBinding,
                    date: activeDateBinding
                )
            }

            if !datesAreValid {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    Text("The scheduled date needs to be on or after the work date.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentDestructive)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Move work date to the scheduled day") {
                        workDate = scheduledDate
                        hasWorkDate = true
                    }
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .buttonStyle(.plain)
                }
            } else if let requiredMessage {
                Text(requiredMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AgentSpacing.x5)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.panel)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    private var activeQuestion: String {
        activeStep == .work
            ? "When do you want to work on this post?"
            : "When should this post be scheduled?"
    }

    private var activeDateToggleLabel: String {
        activeStep == .work ? "Include work date" : "Include scheduled date"
    }

    private var activeDateEnabledBinding: Binding<Bool> {
        switch activeStep {
        case .work:
            Binding(
                get: { hasWorkDate },
                set: { isEnabled in
                    hasWorkDate = isEnabled
                    if !isEnabled { includesWorkTime = false }
                }
            )
        case .schedule:
            Binding(
                get: { hasScheduledDate },
                set: { isEnabled in
                    hasScheduledDate = isEnabled
                    if !isEnabled { includesScheduledTime = false }
                }
            )
        }
    }

    private var activeDateIsSet: Bool {
        activeStep == .work ? hasWorkDate : hasScheduledDate
    }

    private var activeDateBinding: Binding<Date> {
        switch activeStep {
        case .work:
            Binding(
                get: { workDate },
                set: { newDate in
                    workDate = newDate
                    hasWorkDate = true
                }
            )
        case .schedule:
            Binding(
                get: { scheduledDate },
                set: { newDate in
                    scheduledDate = newDate
                    hasScheduledDate = true
                }
            )
        }
    }

    private var activeIncludesTimeBinding: Binding<Bool> {
        switch activeStep {
        case .work: $includesWorkTime
        case .schedule: $includesScheduledTime
        }
    }

    private var datesAreValid: Bool {
        PostDatePlanPolicy.isChronologicallyValid(
            workDate: hasWorkDate ? workDate : nil,
            scheduledDate: hasScheduledDate ? scheduledDate : nil
        )
    }

    private var requiredMessage: String? {
        switch requiredStep {
        case .work where !hasWorkDate:
            "Choose when you want to work on this post to continue."
        case .schedule where !hasScheduledDate:
            "Choose when this post should be scheduled to continue."
        default:
            nil
        }
    }

    private var canSave: Bool {
        datesAreValid && requiredMessage == nil
    }

    private func dateTimeControls(
        includesTime: Binding<Bool>,
        date: Binding<Date>
    ) -> some View {
        VStack(spacing: 0) {
            Toggle("Include a time", isOn: includesTime)
                .font(.agentHeadline)
                .tint(Color.actionAccent)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 54)

            if includesTime.wrappedValue {
                Divider().overlay(Color.agentHairline)
                HStack {
                    Text("Time")
                        .font(.agentBody)
                    Spacer()
                    DatePicker("Time", selection: date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 54)
            }
        }
        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }
}

enum ActualPostedDateSheetMode: Equatable {
    case compact
    case expanded
}

enum ActualPostedDateSheetPolicy {
    static let compactHeight: CGFloat = 320

    static func mode(showsCalendar: Bool) -> ActualPostedDateSheetMode {
        showsCalendar ? .expanded : .compact
    }
}

struct ActualPostedDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var postedAt: Date
    let onSave: (Date) -> Void
    @State private var showsCalendar = false
    @State private var selectedDetent: PresentationDetent = .height(ActualPostedDateSheetPolicy.compactHeight)

    var body: some View {
#if targetEnvironment(macCatalyst)
        pickerContent
#else
        pickerContent
            .presentationDetents(
                [.height(ActualPostedDateSheetPolicy.compactHeight), .large],
                selection: $selectedDetent
            )
            .presentationContentInteraction(.scrolls)
            .presentationCornerRadius(AgentRadius.floating)
            .presentationBackground(Color.agentCanvas)
#endif
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("Actual posted date")
                        .font(.agentTitle)
                        .foregroundStyle(Color.agentText)

                    Text("Confirm when this post went live.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AgentToolbarIconButton(title: "Cancel", icon: .close) {
                    dismiss()
                }
            }
            .padding(.horizontal, AgentSpacing.x5)
            .padding(.top, AgentSpacing.x3)
            .padding(.bottom, AgentSpacing.x4)

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    VStack(spacing: 0) {
                        postedDateButton

                        Divider()
                            .overlay(Color.agentHairline)
                            .padding(.leading, AgentSpacing.x4)

                        postedTimeField
                    }
                    .background(
                        Color.agentSurface,
                        in: .rect(cornerRadius: AgentRadius.card)
                    )
                    .agentSurfaceChrome(
                        cornerRadius: AgentRadius.card,
                        role: .structural
                    )

                    if showsCalendar {
                        PillarCalendarDatePicker(
                            date: $postedAt,
                            pillarMarkers: [],
                            maximumDate: Date(),
                            cellHeight: 38,
                            dayDiameter: 28
                        )
                        .padding(AgentSpacing.x4)
                        .background(
                            Color.agentSurface,
                            in: .rect(cornerRadius: AgentRadius.card)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.card)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, AgentSpacing.x5)
                .padding(.bottom, AgentSpacing.x4)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Button {
                onSave(postedAt)
                dismiss()
            } label: {
                Text("Mark posted")
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(!PostedDatePolicy.isValid(postedAt))
            .padding(.horizontal, AgentSpacing.x5)
            .padding(.bottom, AgentSpacing.x4)
        }
        .frame(width: dialogWidth, height: dialogHeight)
        .background(Color.agentCanvas)
        .agentScreen()
    }

    private var postedDateButton: some View {
        Button {
            toggleCalendar()
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text("DATE")
                        .font(.agentMetadata)
                        .tracking(1.4)
                        .foregroundStyle(Color.agentSecondary)

                    Text(postedAt.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.agentBody.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.agentText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                AgentIconView(showsCalendar ? .collapse : .expand, size: 13)
                    .foregroundStyle(Color.agentSecondary)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityLabel("Posted date, \(postedAt.formatted(date: .complete, time: .omitted))")
        .accessibilityHint(showsCalendar ? "Hides the calendar" : "Shows the calendar")
    }

    private func toggleCalendar() {
        showsCalendar.toggle()
#if !targetEnvironment(macCatalyst)
        selectedDetent = switch ActualPostedDateSheetPolicy.mode(showsCalendar: showsCalendar) {
        case .compact: .height(ActualPostedDateSheetPolicy.compactHeight)
        case .expanded: .large
        }
#endif
    }

    private var postedTimeField: some View {
        HStack(spacing: AgentSpacing.x3) {
            Text("TIME")
                .font(.agentMetadata)
                .tracking(1.4)
                .foregroundStyle(Color.agentSecondary)

            Spacer(minLength: 0)

            DatePicker(
                "Time",
                selection: $postedAt,
                in: ...Date(),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .font(.agentBody.weight(.medium))
            .monospacedDigit()
            .tint(Color.actionAccent)
            .accessibilityLabel("Posted time")
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private var dialogWidth: CGFloat? {
#if targetEnvironment(macCatalyst)
        500
#else
        nil
#endif
    }

    private var dialogHeight: CGFloat? {
#if targetEnvironment(macCatalyst)
        360
#else
        nil
#endif
    }
}

struct PillarCalendarMarker: Equatable {
    let weekday: PillarWeekday
    let colorHex: String
}

extension Array where Element == PillarCalendarMarker {
    func colorHexes(for date: Date, calendar: Calendar = .current) -> [String] {
        guard let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: date)) else {
            return []
        }

        return filter { $0.weekday == weekday }
            .map(\.colorHex)
            .reduce(into: [String]()) { unique, color in
                guard !unique.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) else {
                    return
                }
                unique.append(color)
            }
    }
}

/// Draw the month ourselves so pillar assignments are part of every date cell.
/// `UICalendarView` can silently discard custom decorations after selection or
/// month updates, which made otherwise-valid pillar assignments disappear.
struct PillarCalendarDatePicker: View {
    @Binding var date: Date
    let pillarMarkers: [PillarCalendarMarker]
    let minimumDate: Date?
    let maximumDate: Date?
    let cellHeight: CGFloat
    let dayDiameter: CGFloat
    private var calendar: Calendar = .current
    @State private var displayedMonth: Date

    init(
        date: Binding<Date>,
        pillarMarkers: [PillarCalendarMarker],
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        cellHeight: CGFloat = 52,
        dayDiameter: CGFloat = 40,
        calendar: Calendar = .current
    ) {
        _date = date
        self.pillarMarkers = pillarMarkers
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.cellHeight = cellHeight
        self.dayDiameter = dayDiameter
        self.calendar = calendar
        _displayedMonth = State(initialValue: Self.firstDayOfMonth(for: date.wrappedValue, calendar: calendar))
    }

    var body: some View {
        VStack(spacing: AgentSpacing.x3) {
            monthHeader
            weekdayHeader

            VStack(spacing: AgentSpacing.x1) {
                ForEach(0..<monthRowCount, id: \.self) { row in
                    monthRow(row)
                }
            }
        }
        .onChange(of: date) { _, newDate in
            guard !calendar.isDate(newDate, equalTo: displayedMonth, toGranularity: .month) else {
                return
            }
            displayedMonth = Self.firstDayOfMonth(for: newDate, calendar: calendar)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: AgentSpacing.x3) {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))

            Spacer()

            Button {
                moveMonth(by: -1)
            } label: {
                AgentIconView(.back, size: 18)
                    .frame(width: 44, height: 44)
            }
            .disabled(!canMoveMonth(by: -1))
            .opacity(canMoveMonth(by: -1) ? 1 : 0.32)
            .accessibilityLabel("Previous month")

            Button {
                moveMonth(by: 1)
            } label: {
                AgentIconView(.forward, size: 18)
                    .frame(width: 44, height: 44)
            }
            .disabled(!canMoveMonth(by: 1))
            .opacity(canMoveMonth(by: 1) ? 1 : 0.32)
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Color.agentText)
    }

    private var weekdayHeader: some View {
        HStack(spacing: AgentSpacing.x1) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.paperMetadata(size: 11, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: date)
        let isToday = calendar.isDateInToday(day)
        let isBeforeMinimum = minimumDate.map { day < calendar.startOfDay(for: $0) } ?? false
        let isAfterMaximum = maximumDate.map { day > endOfDay(for: $0) } ?? false
        let isDisabled = isBeforeMinimum || isAfterMaximum
        let colors = pillarMarkers.colorHexes(for: day, calendar: calendar)

        return Button {
            select(day)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.paperInter(size: 17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(
                        isDisabled
                            ? Color.agentSecondary.opacity(0.35)
                            : (isSelected ? Color.agentCanvas : Color.agentText)
                    )
                    .frame(width: dayDiameter, height: dayDiameter)
                    .background(isSelected ? Color.agentText : Color.clear, in: .circle)
                    .overlay {
                        if isToday {
                            Circle()
                                .stroke(Color.actionAccent, lineWidth: 1.5)
                                .padding(1)
                        }
                    }

                HStack(spacing: 3) {
                    ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, colorHex in
                        Circle()
                            .fill(Color(agentHex: colorHex))
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle()
                                    .stroke(Color.agentText.opacity(0.18), lineWidth: 0.5)
                            }
                    }
                }
                .frame(height: 7)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel(for: day, colorCount: colors.count, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var monthRowCount: Int {
        (monthCells.count + 6) / 7
    }

    private func monthRow(_ row: Int) -> some View {
        HStack(spacing: AgentSpacing.x1) {
            ForEach(0..<7, id: \.self) { column in
                let index = row * 7 + column
                if index < monthCells.count, let day = monthCells[index] {
                    dayButton(day)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: cellHeight)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        var symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        symbols = Array(symbols[firstIndex...] + symbols[..<firstIndex])
        return symbols.map { $0.uppercased() }
    }

    private var monthCells: [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: displayedMonth)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leadingCount)

        cells.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
        }.map(Optional.some))

        let trailingCount = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array<Date?>(repeating: nil, count: trailingCount))
        return cells
    }

    private func moveMonth(by value: Int) {
        guard canMoveMonth(by: value) else { return }
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else {
            return
        }
        displayedMonth = Self.firstDayOfMonth(for: month, calendar: calendar)
    }

    private func canMoveMonth(by value: Int) -> Bool {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else {
            return false
        }
        let candidate = Self.firstDayOfMonth(for: month, calendar: calendar)

        if let minimumDate,
           candidate < Self.firstDayOfMonth(for: minimumDate, calendar: calendar) {
            return false
        }
        if let maximumDate,
           candidate > Self.firstDayOfMonth(for: maximumDate, calendar: calendar) {
            return false
        }
        return true
    }

    private func endOfDay(for value: Date) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: value) ?? value
    }

    private func select(_ selectedDay: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        var combined = calendar.dateComponents([.era, .year, .month, .day], from: selectedDay)
        combined.hour = time.hour
        combined.minute = time.minute
        combined.second = time.second
        date = calendar.date(from: combined) ?? selectedDay
    }

    private func accessibilityLabel(for day: Date, colorCount: Int, isToday: Bool) -> String {
        let dateLabel = day.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : "")
        guard colorCount > 0 else { return dateLabel }
        let assignment = colorCount == 1 ? "one pillar" : "\(colorCount) pillars"
        return "\(dateLabel), assigned to \(assignment)"
    }

    private static func firstDayOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

struct PostDraftTaskComposer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let brief: CreativeBrief
    let output: PlatformOutput
    let defaultDate: Date
    @State private var title = ""
    @State private var priority: TaskPriority = .none
    @State private var includeDate = true
    @State private var includesTime = false
    @State private var date: Date
    @State private var showDatePicker = false

    init(brief: CreativeBrief, output: PlatformOutput, defaultDate: Date) {
        self.brief = brief
        self.output = output
        self.defaultDate = defaultDate
        _date = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What's the task?", text: $title)
                    .agentSingleLineSubmit()
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.selectableCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                Toggle("Set a due date", isOn: $includeDate)
                if includeDate {
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            Text("Date")
                            Spacer()
                            Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Toggle("Include a time", isOn: $includesTime)
                    if includesTime {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("Add task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AgentToolbarSaveButton(
                        title: "Save task",
                        isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: addTask
                    )
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .agentScreen()
        .sheet(isPresented: $showDatePicker) {
            PostTaskDatePicker(date: $date)
                .presentationDetents([.large])
                .agentSheetDragIndicator()
        }
    }

    private func addTask() {
        let requestedDate = includeDate
            ? (includesTime ? date : Calendar.current.startOfDay(for: date))
            : nil
        let resolvedDate = PostTaskReschedulePolicy.resolvedDueDate(
            requestedDate: requestedDate,
            includesTime: includeDate && includesTime,
            briefID: brief.id,
            outputID: output.id,
            workDate: brief.workDate,
            outputs: [output]
        )
        let task = CreatorTask(
            briefID: brief.id,
            pillarID: brief.pillarID,
            platformOutputID: output.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .planning,
            lane: .production,
            priority: priority,
            targetDate: resolvedDate,
            includesTargetTime: includeDate && includesTime
        )
        task.workspaceID = brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context)
        context.insert(task)
        do {
            try context.save()
        } catch {
            context.rollback()
            appModel.notice = .error("Couldn’t save this task. Try again.")
            return
        }
        appModel.queueCalendarSync(context: context)
        dismiss()
    }
}

private struct PostTaskDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    PillarCalendarDatePicker(date: $date, pillarMarkers: [])
                        .frame(minHeight: 330)
                        .accessibilityLabel("Task due date")
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x8)
            }
            .navigationTitle("Due date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use date") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .agentScreen()
    }
}

#if DEBUG
enum PostEditorRuntimeFixture {
    static func requestsPostEditor(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-agentCyPreviewPostEditor")
    }

    /// Opens the editor's "spark" sheet (`DevelopBriefView`) directly, so the
    /// post-editor-spark-development surface can be captured without driving
    /// the editor's toolbar.
    static func requestsSparkDevelopment(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-agentCyPreviewSparkDevelopment")
    }
}
#endif
