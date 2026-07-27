import SwiftData
import SwiftUI
import QuickLook

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
        return isMissed(
            outputStatus: outputStatus,
            targetDate: targetDate,
            now: now,
            calendar: calendar
        ) ? "Missed post" : "Scheduled post"
    }

    static func statusTitle(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if outputStatus == .posted { return "POSTED" }
        return isMissed(
            outputStatus: outputStatus,
            targetDate: targetDate,
            now: now,
            calendar: calendar
        ) ? "MISSED" : "SCHEDULED"
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
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var tasks: [CreatorTask]
    @Query private var attachments: [CreatorAttachment]
    @State private var showEditor = false
    @State private var showTaskComposer = false
    @State private var showRescheduler = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var selectedMoodBoardPreview: MoodBoardImagePreview?
    @State private var attachmentPreviewURL: URL?
    @State private var markdownDocument: MarkdownFileDocument?
    @State private var showMarkdownExporter = false
    @State private var isKeyboardVisible = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                postHeader
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
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditor = true
                    } label: {
                        AgentIconLabel(title: "Edit post", icon: .pencil)
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
                } label: {
                    AgentIconView(.more)
                        .foregroundStyle(Color.agentText)
                }
                .accessibilityLabel("Post options")
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                ResumablePostEditorView(
                    brief: brief,
                    output: output,
                    bottomActionClearance: AgentSpacing.x3,
                    onSpark: {}
                )
                .taskNavigationDestinations()
                .navigationTitle("Edit post")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        AgentToolbarIconButton(title: "Close", icon: .close) { showEditor = false }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .agentScreen()
                .agentKeyboardDismissal()
            }
        }
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
        .alert("Archive this post?", isPresented: $confirmArchive) {
            Button("Archive", role: .destructive) {
                appModel.archive(brief, context: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can find it later under Archived in the Idea Bank.")
        }
        .alert("Delete this post?", isPresented: $confirmDelete) {
            if PostSeriesDeletionPolicy.isPartOfSeries(output) {
                Button("Delete this post", role: .destructive) {
                    deletePost(scope: .thisPost)
                }
                Button("Delete this and future posts", role: .destructive) {
                    deletePost(scope: .thisAndFuture)
                }
            } else {
                Button("Delete post", role: .destructive) {
                    deletePost(scope: .thisPost)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(PostSeriesDeletionPolicy.isPartOfSeries(output)
                ? "Past posts stay in place. Linked tasks for every deleted post are also removed."
                : "This also removes the post's linked tasks.")
        }
        .onDisappear {
            if output.status == .posted { savePublishedLink() }
        }
        .agentScreen()
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

    private var scheduleSurface: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Posting details")
            detailRow(label: "Date", value: scheduleDateText)
            detailRow(label: "Platform", value: platformLabel, keepsValueOnOneLine: true)
            detailRow(label: "Duration", value: durationLabel)
            if isMissed {
                AgentInlinePostAction(title: "Reschedule", isAlert: true) {
                    showRescheduler = true
                }
                .padding(.top, AgentSpacing.x2)
            }
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
        Button(output.status == .posted ? "Mark not posted" : "Mark as posted") {
            appModel.togglePosted(output: output, context: context)
        }
        .buttonStyle(AgentPrimaryButtonStyle())
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x2)
        .padding(.bottom, 88)
        .shadow(color: Color.agentPureBlack.opacity(0.14), radius: 16, y: 7)
        .accessibilityHint(
            output.status == .posted
                ? "Returns this post to its scheduled status"
                : "Marks this scheduled post as posted"
        )
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
        if isMissed { return .agentDestructive }
        return output.status == .posted ? .actionAccent : .clear
    }
    private var statusBadgeForeground: Color {
        if isMissed { return .onCyAccent }
        return output.status == .posted ? .onAccent : .agentText
    }
    private var statusBadgeBorder: Color {
        isMissed || output.status == .posted ? .clear : Color.agentText.opacity(0.20)
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
