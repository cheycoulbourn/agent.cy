import SwiftData
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum PostDraftSetupPicker: String, Identifiable {
    case pillar
    case platform
    case format

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pillar: "Choose a pillar"
        case .platform: "Choose a platform"
        case .format: "Choose a format"
        }
    }
}

struct ResumablePostEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var brief: CreativeBrief
    @Bindable var output: PlatformOutput
    @Query private var outputs: [PlatformOutput]
    @Query private var tasks: [CreatorTask]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var allSocialAccounts: [CreatorSocialAccount]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var profiles: [CreatorProfile]
    @Query private var attachments: [CreatorAttachment]
    let onSpark: () -> Void
    let contextLabel: String?
    let isReviewEditing: Bool
    let isAlreadyInIdeaBank: Bool
    let bottomActionClearance: CGFloat

    @State private var targetDate: Date
    @State private var hasTargetDate: Bool
    @State private var shouldPersistTargetDate: Bool
    @State private var showDatePicker = false
    @State private var scheduleAfterDatePicker = false
    @State private var didChooseDate = false
    @State private var showTaskComposer = false
    @State private var showMorePostDetails = false
    @State private var selectedMedia: [PhotosPickerItem] = []
    @State private var selectedMoodBoardMedia: [PhotosPickerItem] = []
    @State private var isImportingMedia = false
    @State private var isImportingMoodBoardMedia = false
    @State private var showCollaborationFileImporter = false
    @State private var confirmDeleteDraft = false
    @State private var confirmMoveToIdeaBank = false
    @State private var isDeletingDraft = false
    @State private var markdownDocument: MarkdownFileDocument?
    @State private var showMarkdownExporter = false
    @State private var pendingProposal: BriefProposal?
    @State private var activeSetupPicker: PostDraftSetupPicker?
    @State private var isKeyboardVisible = false
    @FocusState private var notesAreFocused: Bool

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

    init(
        brief: CreativeBrief,
        output: PlatformOutput,
        suggestedTargetDate: Date? = nil,
        contextLabel: String? = nil,
        isReviewEditing: Bool = false,
        isAlreadyInIdeaBank: Bool = false,
        bottomActionClearance: CGFloat = 88,
        onSpark: @escaping () -> Void
    ) {
        self.brief = brief
        self.output = output
        self.onSpark = onSpark
        self.contextLabel = contextLabel
        self.isReviewEditing = isReviewEditing
        self.isAlreadyInIdeaBank = isAlreadyInIdeaBank
        self.bottomActionClearance = bottomActionClearance
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
        let existingTargetDate = output.targetDate ?? brief.agendaDate
        _targetDate = State(initialValue: existingTargetDate ?? suggestedTargetDate ?? Date())
        _hasTargetDate = State(initialValue: existingTargetDate != nil || suggestedTargetDate != nil)
        _shouldPersistTargetDate = State(initialValue: existingTargetDate != nil)
        _showMorePostDetails = State(initialValue: Self.hasMorePostDetails(output))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                HStack {
                    MetaLabel(contextLabel ?? (isEditingFinalizedPost ? "Edit post" : "Draft post"))
                    Spacer()
                    if !isEditingFinalizedPost && !isReviewEditing {
                        Button(action: openSpark) {
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
                        .accessibilityHint("Opens Cy with this saved post as context")
                    }
                }

                TextField("Post title", text: $brief.title, axis: .vertical)
                    .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                    .tracking(-0.56)
                    .lineLimit(1...3)

                postSetupSection

                if let contentFormat = selectedFormat?.kind.contentFormat {
                    AgentDurationPicker(seconds: $output.durationSeconds, format: contentFormat)
                }

                postCopySection

                recurrenceSection

                if showsBrandDealsSection {
                    collaborationSection
                }

                if showsMoodBoardsSection {
                    moodBoardSection
                }

                notesSection

                mediaSection

                moreDetailsSection
                postedLinkSection
                tasksSection
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x4)
            .padding(.bottom, showsFloatingScheduleButton ? AgentSpacing.x6 : 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingScheduleButton
        }
        .sheet(isPresented: $showDatePicker, onDismiss: finishDateSelection) {
            PostDraftDatePicker(
                date: $targetDate,
                includesTime: $output.includesTargetTime,
                pillarMarkers: activePillars.flatMap { pillar in
                    pillar.resolvedWeekdays(in: activePillars).map { weekday in
                        PillarCalendarMarker(
                            weekday: weekday,
                            colorHex: pillar.resolvedColorHex(in: activePillars)
                        )
                    }
                },
                title: scheduleAfterDatePicker ? "Schedule post" : "Post date",
                confirmationTitle: scheduleAfterDatePicker ? "Schedule" : "Set date"
            ) {
                applyTargetDate()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeSetupPicker) { picker in
            postSetupPickerSheet(picker)
                .presentationDetents([.height(postSetupPickerHeight(for: picker))])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.agentCanvas)
        }
        .sheet(isPresented: $showTaskComposer) {
            PostDraftTaskComposer(brief: brief, output: output, defaultDate: targetDate)
                .presentationDetents([.medium])
        }
        .toolbar {
            if isEditingFinalizedPost || isReviewEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveDraft) {
                        AgentIconView(.check, size: 15)
                            .foregroundStyle(Color.agentPureBlack)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.agentPureWhite)
                    .disabled(brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    .accessibilityLabel("Save changes")
                }
            } else if canDeleteDraft {
                ToolbarItem(placement: .topBarTrailing) {
                    if canDeleteAsEmptyDraft {
                        Button(role: .destructive) {
                            confirmDeleteDraft = true
                        } label: {
                            AgentIconView(.trash)
                        }
                        .accessibilityLabel("Delete empty draft")
                    } else {
                        Menu {
                            if !isAlreadyInIdeaBank {
                                Button {
                                    confirmMoveToIdeaBank = true
                                } label: {
                                    AgentIconLabel(title: "Move to Idea Bank", icon: .idea)
                                }
                            }
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
                        } label: {
                            AgentIconView(.more)
                                .foregroundStyle(Color.agentText)
                        }
                        .accessibilityLabel("Draft options")
                    }
                }
            }
        }
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
        .onDisappear {
            if !isDeletingDraft { persistChanges() }
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
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }

    private var postSetupSection: some View {
        VStack(spacing: 0) {
            pillarMenu

            Button {
                presentSetupPicker(.platform)
            } label: {
                PostDraftSetupRow(label: "Platform", value: selectedDestination?.name ?? output.platform.title)
            }
            .buttonStyle(.plain)

            Button {
                presentSetupPicker(.format)
            } label: {
                PostDraftSetupRow(label: "Format", value: selectedFormat?.name ?? "Choose a format")
            }
            .buttonStyle(.plain)
            .disabled(output.destinationID == nil)
            .opacity(output.destinationID == nil ? 0.55 : 1)

            Button { editDueDate() } label: {
                PostDraftSetupRow(label: "Due", value: targetDateLabel)
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentInputHeader(title: "Notes", isEditing: notesAreFocused) {
                notesAreFocused = false
            }
            TextEditor(text: $brief.notes)
                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .padding(16)
                .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.agentText.opacity(0.16), lineWidth: 1)
                )
                .focused($notesAreFocused)
        }
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

    private var showsFloatingScheduleButton: Bool {
        !isEditingFinalizedPost && !isReviewEditing
    }

    @ViewBuilder
    private var floatingScheduleButton: some View {
        if showsFloatingScheduleButton {
            Button("Schedule post", action: requestSchedule)
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x2)
                .padding(.bottom, isKeyboardVisible ? AgentSpacing.x2 : bottomActionClearance)
                .shadow(color: Color.agentPureBlack.opacity(0.14), radius: 16, y: 7)
                .accessibilityHint("Sets a date and adds this post to the weekly agenda")
        }
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
        .buttonStyle(.plain)
    }

    private func performStableSetupSelection(_ update: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func presentSetupPicker(_ picker: PostDraftSetupPicker) {
        AgentKeyboard.dismiss()
        activeSetupPicker = picker
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
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .buttonStyle(.plain)
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
        }
        return min(560, max(220, CGFloat(optionCount * 55) + 112))
    }
    private var isEditingFinalizedPost: Bool {
        !PostDraftResumePolicy.shouldResume(
            briefStatus: brief.status,
            outputStatus: output.status
        )
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

    private var canDeleteDraft: Bool {
        [.spark, .developing].contains(brief.status) && output.status == .draft
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
        attachments.filter { $0.ownerKind == .postMedia && $0.platformOutputID == output.id }
    }

    private var collaborationFiles: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .collaborationFile && $0.platformOutputID == output.id }
    }

    private var moodBoardMedia: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .moodBoardMedia && $0.platformOutputID == output.id }
    }

    private var postCopySection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Post copy")
            ForEach(CreatorPostCopyField.allCases) { field in
                if field != .hook || showsHookSection {
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
        return (editorProfile?.showsBrandDealsInPostEditor ?? true) || hasExistingDeal
    }

    private var showsMoodBoardsSection: Bool {
        let hasExistingMoodBoard = brief.moodBoardEnabled || !moodBoardMedia.isEmpty
        return (editorProfile?.showsMoodBoardsInPostEditor ?? true) || hasExistingMoodBoard
    }

    private var collaborationSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Collaboration")

            Toggle("Brand collaboration", isOn: $brief.isBrandCollaboration)
                .font(.agentBody.weight(.semibold))
                .tint(Color.actionAccent)
                .frame(minHeight: 44)

            if brief.isBrandCollaboration {
                PostEditorTextField(label: "Brand or partner", text: $brief.brandName, axis: .horizontal)

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
                                .font(.agentMono)
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
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                }

                if brief.compensationType == .gifted || brief.compensationType == .both {
                    PostEditorTextField(label: "Gifted product", text: $brief.giftedProductDescription)
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    SectionRuleHeader(title: "Contract or brief", trailing: "\(collaborationFiles.count)")
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
        }
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

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Series & recurrence")

            VStack(spacing: 0) {
                TextField("Series name (optional)", text: $output.seriesName)
                    .font(.agentBody)
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 54)

                Divider().overlay(Color.agentHairline)

                Picker("Repeats", selection: Binding(
                    get: { output.recurrence },
                    set: { setRecurrence($0) }
                )) {
                    ForEach(PostRecurrenceFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 54)
            }
            .background(Color.agentSurface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }

            if output.recurrence == .weekly {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Repeat on")
                    HStack(spacing: AgentSpacing.x2) {
                        ForEach(PillarWeekday.mondayFirst) { weekday in
                            Button {
                                var selection = output.recurrenceWeekdays
                                if selection.contains(weekday) { selection.remove(weekday) }
                                else { selection.insert(weekday) }
                                output.recurrenceWeekdays = selection
                            } label: {
                                Text(weekday.letter)
                                    .font(.agentMono)
                                    .foregroundStyle(output.recurrenceWeekdays.contains(weekday) ? Color.onAccent : Color.agentText)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(
                                        output.recurrenceWeekdays.contains(weekday) ? Color.actionAccent : Color.agentSurface,
                                        in: .circle
                                    )
                                    .overlay {
                                        Circle().stroke(Color.agentBorder, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(weekday.title)
                            .accessibilityAddTraits(output.recurrenceWeekdays.contains(weekday) ? .isSelected : [])
                        }
                    }
                }
            } else if output.recurrence == .monthly {
                HStack {
                    Text("Repeat on day")
                        .font(.agentBody)
                    Spacer()
                    Picker("Day of month", selection: Binding(
                        get: { output.recurrenceMonthDay ?? Calendar.current.component(.day, from: targetDate) },
                        set: { output.recurrenceMonthDay = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 52)
                .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
            }

            if output.recurrence != .none {
                VStack(spacing: 0) {
                    Toggle("End date", isOn: recurrenceEndDateEnabled)
                        .font(.agentBody)
                        .tint(Color.actionAccent)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 54)

                    if output.recurrenceEndDate != nil {
                        Divider().overlay(Color.agentHairline)
                        DatePicker(
                            "Ends",
                            selection: recurrenceEndDateBinding,
                            in: Calendar.current.startOfDay(for: targetDate)...,
                            displayedComponents: .date
                        )
                        .font(.agentBody)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 54)
                    } else {
                        Divider().overlay(Color.agentHairline)
                        Text("No end date · schedules the next 12 posts")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, AgentSpacing.x4)
                    }
                }
                .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
            }
        }
    }

    private var mediaSection: some View {
        let importingMedia = isImportingMedia
        return VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Media", trailing: "\(postMedia.count)")

            if !postMedia.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: AgentSpacing.x3) {
                        ForEach(postMedia) { attachment in
                            PostMediaThumbnail(attachment: attachment) {
                                context.delete(attachment)
                                try? context.save()
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            PhotosPicker(
                selection: $selectedMedia,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                HStack(spacing: AgentSpacing.x3) {
                    AgentIconView(.image)
                    Text(importingMedia ? "Adding media" : "Add photos or videos")
                    Spacer()
                    if importingMedia { ProgressView().controlSize(.small) }
                }
                .font(.agentBody.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.agentSurface, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
            }
            .disabled(importingMedia)

            Text("Media stays with this post and is not sent to Cy unless you explicitly include it later.")
                .font(.agentMono)
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

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                guard data.count <= 45 * 1_024 * 1_024 else {
                    appModelNotice("Choose photos or videos smaller than 45 MB each.")
                    continue
                }
                let type = item.supportedContentTypes.first ?? .data
                let kind: AttachmentKind = type.conforms(to: .movie) ? .video : .photo
                let ext = type.preferredFilenameExtension ?? (kind == .video ? "mov" : "jpg")
                let attachment = CreatorAttachment(
                    ownerKind: .postMedia,
                    briefID: brief.id,
                    platformOutputID: output.id,
                    fileName: "media-\(UUID().uuidString.prefix(8)).\(ext)",
                    kind: kind,
                    uniformTypeIdentifier: type.identifier,
                    byteCount: Int64(data.count),
                    localRelativePath: "",
                    cloudData: data,
                    syncState: .synced
                )
                attachment.workspaceID = brief.workspaceID ?? appModel.resolvedWorkspaceID(context: context)
                context.insert(attachment)
            } catch {
                appModelNotice("One media item could not be added.")
            }
        }
        try? context.save()
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
        try? context.save()
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
            appModelNotice("That contract or brief could not be added.")
        }
    }

    private func deleteAttachment(_ attachment: CreatorAttachment) {
        context.delete(attachment)
        try? context.save()
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

    private func applyTargetDate() {
        targetDate = RecurringPostSchedule.normalizedTargetDate(
            targetDate,
            includesTime: output.includesTargetTime
        )
        hasTargetDate = true
        shouldPersistTargetDate = true
        didChooseDate = true
        appModel.schedule(output: output, date: targetDate, context: context)
        persistChanges()
    }

    private func editDueDate() {
        scheduleAfterDatePicker = false
        didChooseDate = false
        showDatePicker = true
    }

    private func requestSchedule() {
        guard appModel.allows(.schedule, context: context) else {
            appModelNotice("Scheduling is not available with your current access.")
            return
        }
        guard hasTargetDate else {
            scheduleAfterDatePicker = true
            didChooseDate = false
            showDatePicker = true
            return
        }
        schedulePost()
    }

    private func finishDateSelection() {
        let shouldSchedule = scheduleAfterDatePicker && didChooseDate
        scheduleAfterDatePicker = false
        didChooseDate = false
        if shouldSchedule { schedulePost() }
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

        persistChanges(commitSuggestedTargetDate: true)
        guard appModel.schedulePostSeries(output: output, date: targetDate, context: context) else { return }
        openWeeklyAgenda()
    }

    private func openWeeklyAgenda() {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            appModel.routeToWeeklyAgenda()
        }
    }

    private func openSpark() {
        persistChanges()
        onSpark()
    }

    private func saveDraft() {
        persistChanges(commitSuggestedTargetDate: true)
        dismiss()
    }

    private func makeIdea() {
        persistChanges()
        guard appModel.movePostToIdeaBank(brief: brief, output: output, context: context) else { return }
        dismiss()
    }

    private func duplicateDraft() {
        persistChanges()
        guard appModel.duplicatePostDraft(brief: brief, output: output, context: context) != nil else { return }
        appModel.notice = .info("Draft duplicated.")
    }

    private func deleteDraft() {
        isDeletingDraft = true
        if appModel.deleteDraft(brief, context: context) {
            dismiss()
        } else {
            isDeletingDraft = false
        }
    }

    private func persistChanges(commitSuggestedTargetDate: Bool = false) {
        PostDraftSavePolicy.prepare(brief)
        output.status = PostDraftResumePolicy.outputStatus(briefStatus: brief.status, current: output.status)
        if hasTargetDate {
            targetDate = RecurringPostSchedule.normalizedTargetDate(
                targetDate,
                includesTime: output.includesTargetTime
            )
        }
        let writesTargetDate = PostDraftTargetPersistencePolicy.shouldWriteTargetDate(
            hadPersistedTargetDate: shouldPersistTargetDate,
            explicitlyCommitted: commitSuggestedTargetDate
        )
        if writesTargetDate {
            shouldPersistTargetDate = true
            appModel.rescheduleLinkedTasks(
                for: output,
                from: output.targetDate,
                to: hasTargetDate ? targetDate : nil,
                context: context
            )
            output.targetDate = hasTargetDate ? targetDate : nil
            brief.agendaDate = hasTargetDate ? targetDate : nil
        }
        brief.durationSeconds = output.durationSeconds
        brief.updatedAt = Date()
        try? context.save()
        appModel.queueCalendarSync(context: context)
    }

    private func copyMarkdown() {
        persistChanges()
        UIPasteboard.general.string = postMarkdownDocument.text
        appModel.notice = .info("Markdown copied.")
    }

    private func exportMarkdown() {
        persistChanges()
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

    private var targetDateLabel: String {
        guard hasTargetDate else { return "Set a due date" }
        if output.includesTargetTime {
            return targetDate.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
            )
        }
        return targetDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var recurrenceEndDateEnabled: Binding<Bool> {
        Binding(
            get: { output.recurrenceEndDate != nil },
            set: { enabled in
                output.recurrenceEndDate = enabled ? defaultRecurrenceEndDate : nil
            }
        )
    }

    private var recurrenceEndDateBinding: Binding<Date> {
        Binding(
            get: { output.recurrenceEndDate ?? defaultRecurrenceEndDate },
            set: { output.recurrenceEndDate = $0 }
        )
    }

    private var defaultRecurrenceEndDate: Date {
        let calendar = Calendar.current
        switch output.recurrence {
        case .daily:
            return calendar.date(byAdding: .day, value: 30, to: targetDate) ?? targetDate
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 12, to: targetDate) ?? targetDate
        case .monthly:
            return calendar.date(byAdding: .month, value: 12, to: targetDate) ?? targetDate
        case .none:
            return targetDate
        }
    }

    private func setRecurrence(_ recurrence: PostRecurrenceFrequency) {
        output.recurrence = recurrence
        switch recurrence {
        case .weekly where output.recurrenceWeekdays.isEmpty:
            if let weekday = PillarWeekday(rawValue: Calendar.current.component(.weekday, from: targetDate)) {
                output.recurrenceWeekdays = [weekday]
            }
        case .monthly where output.recurrenceMonthDay == nil:
            output.recurrenceMonthDay = Calendar.current.component(.day, from: targetDate)
        case .none:
            output.recurrenceEndDate = nil
        default:
            break
        }
    }

    private static func hasMorePostDetails(_ output: PlatformOutput) -> Bool {
        [output.openingAdjustment, output.titleOverride, output.editChanges]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

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

private struct PostEditorTextField: View {
    let label: String
    @Binding var text: String
    var axis: Axis = .vertical
    var minimumHeight: CGFloat = 72
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) {
                isFocused = false
            }
            TextField("", text: $text, axis: axis)
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
                    .font(.agentMono)
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
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
            }
            .frame(width: 104, height: 118)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }

            Button(role: .destructive, action: onDelete) {
                AgentIconView(.close, size: 10)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(6)
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
            AgentIconView(.forward, size: 12)
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
        }
        .contentShape(.rect)
    }
}

private struct PostDraftDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @Binding var includesTime: Bool
    let pillarMarkers: [PillarCalendarMarker]
    let title: String
    let confirmationTitle: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    PillarCalendarDatePicker(
                        date: $date,
                        pillarMarkers: pillarMarkers
                    )
                    .frame(minHeight: 330)
                    .accessibilityLabel("Post date")

                    Text("Pillar days are marked by color.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)

                    VStack(spacing: 0) {
                        Toggle("Include a time", isOn: $includesTime)
                            .font(.agentHeadline)
                            .tint(Color.actionAccent)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 54)

                        if includesTime {
                            Divider().overlay(Color.agentHairline)
                            HStack {
                                Text("Time")
                                    .font(.agentBody)
                                Spacer()
                                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                            }
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 54)
                        }
                    }
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x8)
            }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmationTitle) { onSave(); dismiss() }
                    }
                }
        }
        .agentScreen()
        .agentKeyboardDismissal()
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
    private var calendar: Calendar = .current
    @State private var displayedMonth: Date

    init(
        date: Binding<Date>,
        pillarMarkers: [PillarCalendarMarker],
        calendar: Calendar = .current
    ) {
        _date = date
        self.pillarMarkers = pillarMarkers
        self.calendar = calendar
        _displayedMonth = State(initialValue: Self.firstDayOfMonth(for: date.wrappedValue, calendar: calendar))
    }

    var body: some View {
        VStack(spacing: AgentSpacing.x3) {
            monthHeader
            weekdayHeader

            LazyVGrid(columns: gridColumns, spacing: AgentSpacing.x1) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayButton(day)
                    } else {
                        Color.clear
                            .frame(height: 52)
                            .accessibilityHidden(true)
                    }
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
            .accessibilityLabel("Previous month")

            Button {
                moveMonth(by: 1)
            } label: {
                AgentIconView(.forward, size: 18)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
        .foregroundStyle(Color.agentText)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: gridColumns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.paperMono(size: 11, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: date)
        let isToday = calendar.isDateInToday(day)
        let colors = pillarMarkers.colorHexes(for: day, calendar: calendar)

        return Button {
            select(day)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.paperInter(size: 17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(isSelected ? Color.agentCanvas : Color.agentText)
                    .frame(width: 40, height: 40)
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
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: day, colorCount: colors.count, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AgentSpacing.x1), count: 7)
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
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else {
            return
        }
        displayedMonth = Self.firstDayOfMonth(for: month, calendar: calendar)
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
                    Button(action: addTask) {
                        AgentIconView(.check, size: 15)
                            .foregroundStyle(Color.agentPureBlack)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.agentPureWhite)
                    .accessibilityLabel("Save task")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            }
        }
        .agentScreen()
        .sheet(isPresented: $showDatePicker) {
            PostTaskDatePicker(date: $date)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        try? context.save()
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
