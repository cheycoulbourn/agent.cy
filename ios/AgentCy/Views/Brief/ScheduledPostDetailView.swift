import SwiftData
import SwiftUI
import QuickLook
import PhotosUI
import UniformTypeIdentifiers

struct PostOutputDetailView: View {
    let brief: CreativeBrief
    let output: PlatformOutput

    @ViewBuilder
    var body: some View {
        switch PostOutputDetailPolicy.destination(
            briefStatus: brief.status,
            outputStatus: output.status,
            targetDate: output.targetDate
        ) {
        case .draftEditor:
            IdeaPostDraftView(brief: brief, output: output)
        case .finalizedPost:
            ScheduledPostDetailView(brief: brief, output: output)
        }
    }
}

enum PostOutputDetailPolicy {
    enum Destination: Equatable {
        case draftEditor
        case finalizedPost
    }

    static func destination(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus,
        targetDate: Date?
    ) -> Destination {
        if PostDraftResumePolicy.shouldResume(
            briefStatus: briefStatus,
            outputStatus: outputStatus
        ) {
            return .draftEditor
        }
        if usesFinalizedView(outputStatus: outputStatus, targetDate: targetDate) {
            return .finalizedPost
        }
        return .draftEditor
    }

    static func usesFinalizedView(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?
    ) -> Bool {
        if outputStatus == .scheduled || outputStatus == .posted { return true }
        return outputStatus == .ready && targetDate != nil
    }
}

enum FinalizedPostPresentation {
    static func notes(_ briefNotes: String) -> String {
        briefNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isMissed(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        AgendaDayPresentation.isOverdue(
            targetDate: targetDate,
            status: outputStatus,
            now: now,
            calendar: calendar
        )
    }

    static func pageTitle(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if outputStatus == .posted { return "Posted" }
        return "Scheduled post"
    }

    static func statusTitle(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        switch outputStatus {
        case .draft: "DRAFT"
        case .ready: "READY"
        case .scheduled: "SCHEDULED"
        case .posted: "POSTED"
        }
    }
}

enum TaskLinkedPostPolicy {
    static func output(for task: CreatorTask, in outputs: [PlatformOutput]) -> PlatformOutput? {
        if let outputID = task.platformOutputID,
           let exactOutput = outputs.first(where: { $0.id == outputID }) {
            return exactOutput
        }
        guard let briefID = task.briefID else { return nil }
        return outputs
            .filter { $0.briefID == briefID }
            .sorted { lhs, rhs in
                let lhsRank = destinationRank(for: lhs)
                let rhsRank = destinationRank(for: rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    private static func destinationRank(for output: PlatformOutput) -> Int {
        if PostOutputDetailPolicy.usesFinalizedView(
            outputStatus: output.status,
            targetDate: output.targetDate
        ) { return 0 }
        if output.status == .draft { return 1 }
        return 2
    }
}

struct ScheduledPostDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var brief: CreativeBrief
    @Bindable var output: PlatformOutput
    @Query private var outputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query(sort: \ContentSeries.createdAt) private var allSeries: [ContentSeries]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var tasks: [CreatorTask]
    @Query private var attachments: [CreatorAttachment]
    @State private var showEditor = false
    @State private var isOpeningEditor = false
    @State private var showTaskComposer = false
    @State private var showRescheduler = false
    @State private var actualPostedDate = Date()
    @State private var showActualPostedDateConfirmation = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var selectedMoodBoardPreview: MoodBoardImagePreview?
    @State private var attachmentPreviewURL: URL?
    @State private var selectedPostMedia: [PhotosPickerItem] = []
    @State private var isImportingPostMedia = false
    @State private var showMediaManager = false
    @State private var mediaExportRequest: PostMediaExportRequest?
    @State private var markdownDocument: MarkdownFileDocument?
    @State private var showMarkdownExporter = false
    @State private var isKeyboardVisible = false
#if targetEnvironment(macCatalyst)
    @State private var showDesktopPostOptions = false
#endif

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

    private struct DisplayField: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    init(brief: CreativeBrief, output: PlatformOutput) {
        self.brief = brief
        self.output = output
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
    }

    var body: some View {
        Group {
            if showEditor {
                inlinePostEditor
            } else {
                postDetailContent
            }
        }
    }

    private var postDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                postHeader
                episodeSeriesAction
                mediaSpotlight
                if !voiceRecordings.isEmpty {
                    PostVoiceRecordingsSection(
                        recordings: voiceRecordings,
                        onDownload: requestMediaExport,
                        onDelete: deleteVoiceRecording,
                        onTitleChange: updateVoiceRecordingTitle,
                        onPlaybackError: { appModel.notice = .error($0) }
                    )
                }
                scheduleSurface
                postContent
                collaborationDetails
                moodBoardDetails
                publishedLink
                notesSection
                taskSection
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x6)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible {
                floatingPostingAction
            }
        }
#if targetEnvironment(macCatalyst)
        .safeAreaInset(edge: .top, spacing: 0) {
            desktopDetailRail
        }
#endif
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
#if targetEnvironment(macCatalyst)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#else
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    postOptionsMenuContent
                } label: {
                    AgentIconView(.more)
                        .foregroundStyle(Color.agentText)
                }
                .accessibilityLabel("Post options")
            }
        }
#endif
        .sheet(isPresented: $showTaskComposer) {
            PostDraftTaskComposer(
                brief: brief,
                output: output,
                defaultDate: output.targetDate ?? Date()
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRescheduler) {
            PostRescheduleSheet(output: output)
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
        .sheet(isPresented: $showMediaManager) {
            PostMediaManagerView(
                briefID: brief.id,
                workspaceID: brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context),
                output: output
            )
        }
        .fullScreenCover(item: $selectedMoodBoardPreview) { preview in
            MoodBoardImageViewer(preview: preview)
        }
        .quickLookPreview($attachmentPreviewURL)
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
        .onChange(of: selectedPostMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPostMedia(items) }
        }
        .onChange(of: attachmentPreviewURL) { oldValue, newValue in
            guard newValue == nil, let oldValue else { return }
            try? FileManager.default.removeItem(at: oldValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
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
        .alert("Archive this post?", isPresented: $confirmArchive) {
            Button("Archive", role: .destructive) {
                appModel.archive(brief, context: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can find it later under Archived in the Idea Bank.")
        }
        .alert(brief.seriesID == nil ? "Delete this post?" : "Delete this episode?", isPresented: $confirmDelete) {
            Button(brief.seriesID == nil ? "Delete post" : "Delete this episode", role: .destructive) {
                deletePost(scope: .thisPost)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(brief.seriesID == nil
                ? "This also removes the post's linked tasks."
                : "This removes only this episode and its linked tasks. The series and future empty slots stay in place.")
        }
        .onDisappear {
            // Pushing the editor makes this detail view disappear. Saving and
            // synchronizing the same post during that transition caused
            // SwiftUI's AttributeGraph to cycle until the watchdog killed the
            // app. The editor owns persistence while it is open; this view
            // only saves the published link when it is actually being left.
            if output.status == .posted, !showEditor { savePublishedLink() }
        }
        .agentScreen()
    }

#if targetEnvironment(macCatalyst)
    private var desktopDetailRail: some View {
        AgentDesktopDetailRail(title: pageTitle, backAction: dismiss.callAsFunction) {
            Button {
                showDesktopPostOptions.toggle()
            } label: {
                AgentDesktopDetailIconLabel(icon: .more)
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityLabel("Post options")
            .popover(isPresented: $showDesktopPostOptions, arrowEdge: .top) {
                desktopPostOptionsPopover
                    .frame(width: 230)
                    .padding(AgentSpacing.x2)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Color.agentSurface)
            }
        }
    }

    private var desktopPostOptionsPopover: some View {
        VStack(spacing: AgentSpacing.x1) {
            AgentDesktopMenuRow(title: "Edit post", icon: .pencil) {
                showDesktopPostOptions = false
                openPostEditor(afterDismissingDesktopMenu: true)
            }
            if let mediaMenuAttachment {
                AgentDesktopMenuRow(title: "Download media", icon: .download) {
                    showDesktopPostOptions = false
                    requestMediaExport(mediaMenuAttachment)
                }
            }
            AgentDesktopMenuDivider()
            AgentDesktopMenuRow(title: "Copy Markdown", icon: .copy) {
                showDesktopPostOptions = false
                copyMarkdown()
            }
            AgentDesktopMenuRow(title: "Export Markdown", icon: .upload) {
                showDesktopPostOptions = false
                exportMarkdown()
            }
            AgentDesktopMenuDivider()
            AgentDesktopMenuRow(title: "Archive", icon: .archive) {
                showDesktopPostOptions = false
                confirmArchive = true
            }
            AgentDesktopMenuRow(title: "Delete post", icon: .trash, isDestructive: true) {
                showDesktopPostOptions = false
                confirmDelete = true
            }
        }
    }
#endif

    @ViewBuilder
    private var postOptionsMenuContent: some View {
        Button {
            openPostEditor()
        } label: {
            AgentIconLabel(title: "Edit post", icon: .pencil)
        }
        if let mediaMenuAttachment {
            Button {
                requestMediaExport(mediaMenuAttachment)
            } label: {
                AgentIconLabel(title: "Download media", icon: .download)
            }
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
            confirmArchive = true
        } label: {
            AgentIconLabel(title: "Archive", icon: .archive)
        }
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            AgentIconLabel(title: "Delete post", icon: .trash)
        }
    }

    private var inlinePostEditor: some View {
        ResumablePostEditorView(
            brief: brief,
            output: output,
            bottomActionClearance: AgentSpacing.x3,
            closeAction: closePostEditor,
            onSpark: {}
        )
        .navigationTitle("Edit post")
        .navigationBarTitleDisplayMode(.inline)
#if !targetEnvironment(macCatalyst)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AgentToolbarIconButton(
                    title: "Back to post details",
                    icon: .back,
                    action: closePostEditor
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
#endif
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private func closePostEditor() {
        showEditor = false
    }

    private func openPostEditor(afterDismissingDesktopMenu: Bool = false) {
        guard !showEditor, !isOpeningEditor else { return }
        isOpeningEditor = true

        #if targetEnvironment(macCatalyst)
        if afterDismissingDesktopMenu {
            showDesktopPostOptions = false
        }
        #endif

        Task { @MainActor in
            // Both SwiftUI Menu on iPhone and the custom Catalyst popover need
            // to finish dismissing before the navigation stack changes. A
            // yield is not long enough for UIKit's dismissal transaction and
            // can leave the presentation graph cycling until the watchdog
            // terminates the app.
            try? await Task.sleep(for: .milliseconds(180))
            showEditor = true
            isOpeningEditor = false
        }
    }

    private var postHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(spacing: AgentSpacing.x2) {
                PillarColorMark(color: pillarColor, diameter: 7)
                Text(pillarName.uppercased())
                    .font(.agentMetadata)
                    .tracking(0.7)
                Spacer()
                Text(statusTitle)
                    .font(.agentMetadata)
                    .tracking(0.6)
                    .padding(.horizontal, AgentSpacing.x2)
                    .frame(minHeight: 24)
                    .background(statusBadgeBackground, in: .rect(cornerRadius: 6))
                    .foregroundStyle(statusBadgeForeground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(statusBadgeBorder, lineWidth: 1)
                    }
            }

            Text(displayTitle)
                .font(.paperInter(size: 32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.64)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var episodeSeriesAction: some View {
        if let selectedSeries {
            // A view-builder link matches how every other detail view in the
            // app is pushed, and works in any stack — the value-based link
            // needed a registered destination and popped straight back out of
            // stacks with typed paths.
            NavigationLink {
                SeriesDetailView(series: selectedSeries)
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel("Series")
                        Text(selectedSeries.name)
                            .font(.agentBody.weight(.medium))
                            .foregroundStyle(Color.agentText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: AgentSpacing.x3)

                    Text("Go to series")
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                        .fixedSize()
                    AgentIconView(.forward, size: 12)
                        .foregroundStyle(Color.agentSecondary)
                }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: AgentRadius.control))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full series schedule")
        }
    }

    private var scheduleSurface: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Posting details")
            detailRow(label: "Date", value: scheduleDateText)
            detailRow(label: "Platform", value: platformLabel, keepsValueOnOneLine: true)
            detailRow(label: "Duration", value: durationLabel)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x4)
        .background(pillarColor.opacity(0.10), in: .rect(cornerRadius: 12))
        .agentSurfaceChrome(
            cornerRadius: 12,
            borderColor: PillarVisualContrast.cardBorderColor(
                for: pillarColor,
                colorScheme: colorScheme
            )
        )
    }

    @ViewBuilder
    private var postContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Post copy")
            if contentFields.isEmpty {
                Text("No post copy has been added yet.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                ForEach(contentFields) { field in
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel(field.label)
                        Text(field.value)
                            .font(.agentBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, AgentSpacing.x4)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.agentHairline).frame(height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var collaborationDetails: some View {
        if brief.isBrandCollaboration {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                SectionRuleHeader(title: "Collaboration")
                detailRow(label: "Partner", value: brief.brandName.isEmpty ? "Not set" : brief.brandName)
                detailRow(label: "Type", value: compensationSummary)
                if brief.brandHasNetTerms {
                    detailRow(label: "Terms", value: "Net \(brief.brandNetTermsDays)")
                }
                if !brief.giftedProductDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(label: "Gifted", value: brief.giftedProductDescription)
                }
                ForEach(collaborationFiles) { attachment in
                    Button {
                        openAttachment(attachment)
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            Text(attachment.fileName)
                                .font(.agentBody)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))
                                .font(.agentMetadata)
                                .foregroundStyle(Color.agentSecondary)
                            AgentIconView(.forward, size: 13)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(attachment.fileName)")
                }
            }
        }
    }

    /// Mobile post media is the visual lead. Text-only posts intentionally have
    /// no placeholder so the title flows straight into posting details.
    @ViewBuilder
    private var mediaSpotlight: some View {
        if !postMedia.isEmpty {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                PostMediaSpotlight(
                    attachments: postMedia,
                    coverAttachmentID: output.coverAttachmentID,
                    onOpen: openPostMedia,
                    onDownload: requestMediaExport
                )

                PostMediaActionBar(
                    selection: $selectedPostMedia,
                    isImporting: isImportingPostMedia,
                    onEdit: { showMediaManager = true }
                )
            }
        }
    }

    @ViewBuilder
    private var moodBoardDetails: some View {
        if brief.moodBoardEnabled {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                SectionRuleHeader(title: "Mood board", trailing: moodBoardMedia.isEmpty ? nil : "\(moodBoardMedia.count) images")
                if !moodBoardMedia.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: AgentSpacing.x3) {
                            ForEach(moodBoardMedia) { attachment in
                                if let data = attachment.cloudData, let image = UIImage(data: data) {
                                    Button {
                                        selectedMoodBoardPreview = MoodBoardImagePreview(
                                            id: attachment.id,
                                            data: data,
                                            title: attachment.fileName
                                        )
                                    } label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 104, height: 118)
                                            .clipShape(.rect(cornerRadius: 14))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(Color.agentBorder, lineWidth: 1)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open mood board image")
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private var publishedLink: some View {
        if output.status == .posted {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                SectionRuleHeader(title: "Published link")
                TextField("", text: $output.publishedURLString)
                    .font(.agentBody)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 52)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                    .onSubmit { savePublishedLink() }
                if let publishedURL {
                    Link("Open published post", destination: publishedURL)
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !displayNotes.isEmpty {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                SectionRuleHeader(title: "Notes")
                Text(displayNotes)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(
                title: "Tasks",
                trailing: "\(completedTaskCount) of \(topLevelTasks.count) complete"
            )
            ForEach(topLevelTasks) { task in
                TaskRow(
                    task: task,
                    allTasks: tasks,
                    verticalInset: AgentSpacing.x2
                )
            }
            AgentBlockAddActionButton(title: "Add task") {
                showTaskComposer = true
            }
            .padding(.top, topLevelTasks.isEmpty ? AgentSpacing.x2 : AgentSpacing.x3)
        }
    }

    @ViewBuilder
    private var floatingPostingAction: some View {
        Group {
            switch bottomPostAction {
            case .schedule:
                floatingPostActionButton(
                    title: "Schedule post",
                    hint: "Chooses a scheduled date"
                ) {
                    showRescheduler = true
                }
            case .markPosted:
                floatingPostActionButton(
                    title: "Mark as posted",
                    hint: "Marks this scheduled post as posted",
                    action: requestPostingStatusChange
                )
            case .markPostedAndReschedule:
                HStack(spacing: AgentSpacing.x3) {
                    floatingPostActionButton(
                        title: "Mark posted",
                        hint: "Marks this late scheduled post as posted",
                        action: requestPostingStatusChange
                    )
                    floatingPostActionButton(
                        title: "Reschedule",
                        hint: "Chooses a new scheduled date"
                    ) {
                        showRescheduler = true
                    }
                }
            case .markNotPosted:
                floatingPostActionButton(
                    title: "Mark not posted",
                    hint: "Returns this post to its scheduled status",
                    action: requestPostingStatusChange
                )
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x2)
        .padding(.bottom, postActionBottomPadding)
        .frame(maxWidth: postActionMaximumWidth)
        .frame(maxWidth: .infinity)
    }

    private var postActionBottomPadding: CGFloat {
#if targetEnvironment(macCatalyst)
        AgentSpacing.x6
#else
        88
#endif
    }

    private var postActionMaximumWidth: CGFloat? {
#if targetEnvironment(macCatalyst)
        560
#else
        nil
#endif
    }

    private var bottomPostAction: PostBottomAction {
        PostBottomActionPolicy.action(
            outputStatus: output.status,
            scheduledDate: output.targetDate,
            includesScheduledTime: output.includesTargetTime
        )
    }

    private func floatingPostActionButton(
        title: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
#if targetEnvironment(macCatalyst)
        Button(action: action) {
            Text(title)
                .font(.agentSubtext.weight(.medium))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x5)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Color.agentPureWhite.opacity(colorScheme == .dark ? 0.18 : 0.94),
                in: .rect(cornerRadius: AgentActionButtonTheme.radius)
            )
            .glassEffect(
                .clear.interactive()
                    .tint(Color.agentPureWhite.opacity(colorScheme == .dark ? 0.08 : 0.20)),
                in: .rect(cornerRadius: AgentActionButtonTheme.radius)
            )
            .overlay {
                // A white stroke on a near-white control over a light canvas
                // read as no border at all on desktop. Dark mode keeps the
                // white edge; light mode uses the border token so the control
                // has a visible boundary.
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(
                        colorScheme == .dark
                            ? Color.agentPureWhite.opacity(0.24)
                            : Color.agentBorder,
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityHint(hint)
#else
        AgentPhonePostActionButton(
            title: title,
            accessibilityHint: hint,
            action: action
        )
#endif
    }

    private func requestPostingStatusChange() {
        guard output.status != .posted else {
            appModel.togglePosted(output: output, context: context)
            return
        }

        let now = Date()
        if PostedDatePolicy.needsActualDateConfirmation(scheduledDate: output.targetDate, now: now) {
            actualPostedDate = now
            showActualPostedDateConfirmation = true
        } else {
            markPosted(at: now)
        }
    }

    private func markPosted(at postedAt: Date) {
        guard PostedDatePolicy.isValid(postedAt) else {
            appModel.notice = .info("A live post cannot have a future posted date.")
            return
        }
        appModel.togglePosted(output: output, postedAt: postedAt, context: context)
    }

    private func detailRow(
        label: String,
        value: String,
        keepsValueOnOneLine: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
            MetaLabel(label)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.agentBody.weight(.medium))
                .lineLimit(keepsValueOnOneLine ? 1 : nil)
                .minimumScaleFactor(keepsValueOnOneLine ? 0.78 : 1)
                .allowsTightening(keepsValueOnOneLine)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var selectedSeries: ContentSeries? {
        guard let seriesID = brief.seriesID else { return nil }
        return allSeries.first {
            $0.id == seriesID &&
                WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: brief.workspaceID ?? appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
    }
    private var selectedPillar: Pillar? { activePillars.first { $0.id == brief.pillarID } }
    private var pillarName: String { selectedPillar?.name ?? "Unfiled" }
    private var pillarColor: Color {
        selectedPillar.map { Color(agentHex: $0.resolvedColorHex(in: activePillars)) } ?? .agentSecondary
    }
    private var selectedDestination: PublishingDestination? { destinations.first { $0.id == output.destinationID } }
    private var selectedFormat: PublishingFormat? { formats.first { $0.id == output.formatID } }
    private var topLevelTasks: [CreatorTask] { tasks.filter { $0.parentTaskID == nil } }
    private var collaborationFiles: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .collaborationFile && $0.platformOutputID == output.id }
    }
    private var moodBoardMedia: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .moodBoardMedia && $0.platformOutputID == output.id }
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
        attachment.displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        attachment.updatedAt = Date()
        do {
            try context.save()
            return true
        } catch {
            appModel.notice = .error("That recording title could not be saved.")
            return false
        }
    }
    private var postMediaPreviewKey: String {
        postMedia.map { "\($0.id.uuidString):\($0.previewData == nil ? 0 : 1)" }.joined(separator: "|")
    }
    private var publishedThumbnailHydrationKey: String {
        PublishedPostThumbnailPolicy.taskKey(output: output)
    }
    private var mediaMenuAttachment: CreatorAttachment? {
        let coverID = PostMediaPresentationPolicy.resolvedCoverID(
            preferredID: output.coverAttachmentID,
            mediaIDs: postMedia.map(\.id)
        )
        return postMedia.first { $0.id == coverID }
    }
    private var mediaExporterPresented: Binding<Bool> {
        Binding(
            get: { mediaExportRequest != nil },
            set: { if !$0 { mediaExportRequest = nil } }
        )
    }
    private var completedTaskCount: Int { topLevelTasks.filter(\.isCompleted).count }
    private var displayTitle: String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }
    private var displayNotes: String {
        FinalizedPostPresentation.notes(brief.notes)
    }
    private var isMissed: Bool {
        FinalizedPostPresentation.isMissed(
            outputStatus: output.status,
            targetDate: output.targetDate
        )
    }
    private var pageTitle: String {
        FinalizedPostPresentation.pageTitle(
            outputStatus: output.status,
            targetDate: output.targetDate
        )
    }
    private var statusTitle: String {
        FinalizedPostPresentation.statusTitle(
            outputStatus: output.status,
            targetDate: output.targetDate
        )
    }
    private var statusBadgeBackground: Color {
        return output.status == .posted ? .actionAccent : .clear
    }
    private var statusBadgeForeground: Color {
        if isMissed { return .agentDestructive }
        return output.status == .posted ? .onAccent : .agentText
    }
    private var statusBadgeBorder: Color {
        if output.status == .posted { return .clear }
        return isMissed ? .agentDestructive : Color.agentText.opacity(0.20)
    }
    private var scheduleDateText: String {
        guard let targetDate = output.targetDate else { return "Not set" }
        if output.includesTargetTime {
            return targetDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
        }
        return targetDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
    private var platformLabel: String {
        if let selectedDestination, let selectedFormat {
            return "\(selectedDestination.name) · \(selectedFormat.name)"
        }
        return output.platform.title
    }
    private var durationLabel: String {
        ContentDurationLabel.full(output.durationSeconds)
    }
    private var compensationSummary: String {
        switch brief.compensationType {
        case .paid:
            return paidAmountSummary
        case .gifted:
            return "Gifted"
        case .both:
            return "\(paidAmountSummary) + gifted"
        }
    }
    private var paidAmountSummary: String {
        guard let amount = brief.compensationAmount else { return "Paid" }
        return amount.formatted(.currency(code: brief.compensationCurrencyCode.isEmpty ? "USD" : brief.compensationCurrencyCode))
    }
    private var publishedURL: URL? { safeWebURL(from: output.publishedURLString) }
    private func safeWebURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }
    private func savePublishedLink() {
        brief.updatedAt = Date()
        try? context.save()
        appModel.queueCalendarSync(context: context)
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
    private func copyMarkdown() {
        savePublishedLink()
        UIPasteboard.general.string = postMarkdownDocument.text
        appModel.notice = .info("Markdown copied.")
    }
    private func exportMarkdown() {
        savePublishedLink()
        markdownDocument = postMarkdownDocument
        showMarkdownExporter = true
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

    @MainActor
    private func importPostMedia(_ items: [PhotosPickerItem]) async {
        isImportingPostMedia = true
        defer {
            isImportingPostMedia = false
            selectedPostMedia = []
        }
        let result = await PostMediaImportService.add(
            items: items,
            briefID: brief.id,
            output: output,
            workspaceID: brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context),
            context: context
        )
        if let notice = result.notice { appModel.notice = .info(notice) }
    }

    private func openPostMedia(_ attachment: CreatorAttachment) {
        if attachment.kind == .photo, let data = attachment.cloudData {
            selectedMoodBoardPreview = MoodBoardImagePreview(
                id: attachment.id,
                data: data,
                title: attachment.fileName
            )
        } else {
            openAttachment(attachment)
        }
    }

    private func requestMediaExport(_ attachment: CreatorAttachment) {
        let preferredFileName = PostVoiceRecordingPolicy.isVoiceRecording(attachment)
            ? VoiceRecordingExportNaming.fileName(
                title: attachment.displayTitle,
                recordedAt: attachment.createdAt,
                postTitle: displayTitle
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

    private func deleteVoiceRecording(_ attachment: CreatorAttachment) {
        context.delete(attachment)
        do {
            try context.save()
        } catch {
            appModel.notice = .error("That recording could not be deleted.")
        }
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

    private func openAttachment(_ attachment: CreatorAttachment) {
        guard let data = attachment.cloudData else {
            appModel.notice = .error("That attachment is not available on this device yet.")
            return
        }

        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("agent-cy-attachment-previews", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = URL(fileURLWithPath: attachment.fileName).lastPathComponent
            let safeName = fileName.isEmpty ? "attachment" : fileName
            let url = directory.appendingPathComponent("\(attachment.id.uuidString)-\(safeName)")
            try data.write(to: url, options: .atomic)
            attachmentPreviewURL = url
        } catch {
            appModel.notice = .error("That attachment could not be opened.")
        }
    }
    private func deletePost(scope: PostDeletionScope) {
        if appModel.deletePost(brief: brief, output: output, scope: scope, context: context) {
            dismiss()
        }
    }
    private var contentFields: [DisplayField] {
        var fields = CreatorPostCopyField.allCases.compactMap { field -> DisplayField? in
            let value = field.value(brief: brief, output: output)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : DisplayField(label: field.title, value: value)
        }
        let editNotes = output.editChanges.trimmingCharacters(in: .whitespacesAndNewlines)
        if !editNotes.isEmpty {
            fields.append(DisplayField(label: "Edit notes", value: editNotes))
        }
        return fields
    }
}

private struct MoodBoardImagePreview: Identifiable {
    let id: UUID
    let data: Data
    let title: String
}

private struct MoodBoardImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let preview: MoodBoardImagePreview

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.agentPureBlack.ignoresSafeArea()

            if let image = UIImage(data: preview.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(preview.title)
            }

            Button {
                dismiss()
            } label: {
                AgentIconView(.close, size: 16)
                    .foregroundStyle(Color.agentPureWhite)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(.top, AgentSpacing.x4)
            .padding(.trailing, AgentSpacing.x4)
            .accessibilityLabel("Close image")
        }
        .statusBarHidden()
    }
}
