import SwiftData
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ResumablePostEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var brief: CreativeBrief
    @Bindable var output: PlatformOutput
    @Query private var tasks: [CreatorTask]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query private var attachments: [CreatorAttachment]
    let onSpark: () -> Void
    let contextLabel: String?

    @State private var targetDate: Date
    @State private var hasTargetDate: Bool
    @State private var shouldPersistTargetDate: Bool
    @State private var showDatePicker = false
    @State private var scheduleAfterDatePicker = false
    @State private var didChooseDate = false
    @State private var showTaskComposer = false
    @State private var showPostCopy = false
    @State private var selectedMedia: [PhotosPickerItem] = []
    @State private var selectedMoodBoardMedia: [PhotosPickerItem] = []
    @State private var isImportingMedia = false
    @State private var isImportingMoodBoardMedia = false
    @State private var showCollaborationFileImporter = false
    @State private var confirmDeleteDraft = false
    @State private var isDeletingDraft = false
    @FocusState private var notesAreFocused: Bool

    init(
        brief: CreativeBrief,
        output: PlatformOutput,
        suggestedTargetDate: Date? = nil,
        contextLabel: String? = nil,
        onSpark: @escaping () -> Void
    ) {
        self.brief = brief
        self.output = output
        self.onSpark = onSpark
        self.contextLabel = contextLabel
        let briefID = brief.id
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
        _showPostCopy = State(initialValue: Self.hasPostCopy(output))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            HStack {
                MetaLabel(contextLabel ?? (isEditingFinalizedPost ? "Edit post" : "Draft post"))
                Spacer()
                if !isEditingFinalizedPost {
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

            TextField("Your post title…", text: $brief.title, axis: .vertical)
                .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                .tracking(-0.56)
                .lineLimit(1...3)

            VStack(spacing: 0) {
                Menu {
                    Button("No pillar") { brief.pillarID = nil }
                    ForEach(activePillars) { pillar in
                        Button {
                            brief.pillarID = pillar.id
                        } label: {
                            PillarMenuChoiceLabel(
                                title: pillar.name,
                                colorHex: pillar.resolvedColorHex(in: activePillars),
                                isSelected: brief.pillarID == pillar.id
                            )
                        }
                    }
                } label: {
                    PostDraftSetupRow(
                        label: "Pillar",
                        value: selectedPillar?.name ?? "Pick a pillar",
                        color: selectedPillar.map { Color(agentHex: $0.resolvedColorHex(in: activePillars)) }
                    )
                }

                Menu {
                    ForEach(activeDestinations) { destination in
                        Button(destination.name) { select(destination) }
                    }
                } label: {
                    PostDraftSetupRow(label: "Platform", value: selectedDestination?.name ?? output.platform.title)
                }

                Menu {
                    ForEach(activeFormats) { format in
                        Button(format.name) {
                            output.formatID = format.id
                            normalizeDuration(for: format)
                            syncLegacyPlatform()
                        }
                    }
                } label: {
                    PostDraftSetupRow(label: "Format", value: selectedFormat?.name ?? "Pick a format")
                }

                Button { editDueDate() } label: {
                    PostDraftSetupRow(
                        label: "Due",
                        value: targetDateLabel
                    )
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .top) { Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1) }

            if let contentFormat = selectedFormat?.kind.contentFormat {
                AgentDurationPicker(seconds: $output.durationSeconds, format: contentFormat)
            }

            postCopySection

            recurrenceSection

            collaborationSection

            moodBoardSection

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

            mediaSection

            if showPostCopy || Self.hasPostCopy(output) {
                DisclosureGroup(isExpanded: $showPostCopy) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        BriefField(label: "Opening", text: $output.openingAdjustment)
                        if selectedDestination?.builtInKind == .youtube {
                            BriefField(label: "Platform title", text: $output.titleOverride)
                        }
                        BriefField(label: "Call to action", text: $output.cta)
                        BriefField(label: "Edit notes", text: $output.editChanges)
                    }
                    .padding(.top, AgentSpacing.x4)
                } label: {
                    BriefDisclosureLabel(title: "More post details", detail: "Opening, CTA, edit notes")
                }
            }

            if output.status == .posted {
                PostEditorTextField(
                    label: "Post link",
                    text: $output.publishedURLString,
                    axis: .horizontal,
                    keyboardType: .URL,
                    textContentType: .URL
                )
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                SectionRuleHeader(title: "Tasks", trailing: "\(topLevelTasks.count)")
                ForEach(topLevelTasks) { task in
                    TaskRow(task: task, allTasks: tasks)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.agentText.opacity(0.08)).frame(height: 1)
                        }
                }
                AgentAddActionRow(title: "Add task") { showTaskComposer = true }
            }

            if !isEditingFinalizedPost {
                Button("Schedule post", action: requestSchedule)
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showDatePicker, onDismiss: finishDateSelection) {
            PostDraftDatePicker(
                date: $targetDate,
                includesTime: $output.includesTargetTime,
                title: scheduleAfterDatePicker ? "Schedule post" : "Post date",
                confirmationTitle: scheduleAfterDatePicker ? "Schedule" : "Use date"
            ) {
                applyTargetDate()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTaskComposer) {
            PostDraftTaskComposer(brief: brief, output: output, defaultDate: targetDate)
                .presentationDetents([.medium])
        }
        .toolbar {
            if isEditingFinalizedPost {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveDraft) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.white)
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
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete empty draft")
                    } else {
                        Menu {
                            Button("Make an idea", systemImage: "lightbulb") {
                                makeIdea()
                            }
                            Button("Save draft", systemImage: "square.and.arrow.down") {
                                saveDraft()
                            }
                            Button("Duplicate", systemImage: "square.on.square") {
                                duplicateDraft()
                            }
                            Button("Delete post", systemImage: "trash", role: .destructive) {
                                confirmDeleteDraft = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Draft options")
                    }
                }
            }
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDeleteDraft, titleVisibility: .visible) {
            Button("Delete post", role: .destructive, action: deleteDraft)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the draft and its linked tasks.")
        }
        .onDisappear {
            if !isDeletingDraft { persistChanges() }
        }
        .onChange(of: selectedMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMedia(items) }
        }
        .onChange(of: selectedMoodBoardMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMoodBoardMedia(items) }
        }
        .fileImporter(
            isPresented: $showCollaborationFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .rtf, .data],
            allowsMultipleSelection: true,
            onCompletion: importCollaborationFiles
        )
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
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
            SectionRuleHeader(title: "Post")
            PostEditorTextField(label: "Hook", text: $brief.spokenHook)
            PostEditorTextField(label: "Caption", text: $output.caption, minimumHeight: 112)
        }
    }

    private var collaborationSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Brand collaboration")

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
                        MetaLabel("Paid amount")
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
                        Image(systemName: "photo.on.rectangle.angled")
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
                    Image(systemName: "photo.on.rectangle.angled")
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
                context.insert(CreatorAttachment(
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
                ))
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
                context.insert(CreatorAttachment(
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
                ))
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
        dismiss()
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
        guard appModel.movePostDraftToIdeaBank(brief: brief, output: output, context: context) else { return }
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
        let cleanNotes = brief.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanNotes.isEmpty { brief.premise = cleanNotes }
        if brief.isBrandCollaboration,
           (brief.compensationType == .paid || brief.compensationType == .both),
           brief.compensationCurrencyCode.isEmpty {
            brief.compensationCurrencyCode = "USD"
        }
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

    private static func hasPostCopy(_ output: PlatformOutput) -> Bool {
        [output.caption, output.openingAdjustment, output.titleOverride, output.cta, output.editChanges]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
                Image(systemName: "trash")
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
                        Image(systemName: attachment.kind == .video ? "play.fill" : "doc.fill")
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
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.agentText)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Remove \(attachment.fileName)")

            if attachment.kind == .video {
                Image(systemName: "video.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.58), in: .capsule)
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

private struct PostDraftDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @Binding var includesTime: Bool
    let title: String
    let confirmationTitle: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)

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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Color.white)
                    .accessibilityLabel("Save task")
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            }
        }
        .agentScreen()
    }

    private func addTask() {
        let task = CreatorTask(
            briefID: brief.id,
            pillarID: brief.pillarID,
            platformOutputID: output.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .planning,
            lane: .production,
            priority: priority,
            targetDate: includeDate
                ? (includesTime ? date : Calendar.current.startOfDay(for: date))
                : nil,
            includesTargetTime: includeDate && includesTime
        )
        context.insert(task)
        try? context.save()
        appModel.queueCalendarSync(context: context)
        dismiss()
    }
}
