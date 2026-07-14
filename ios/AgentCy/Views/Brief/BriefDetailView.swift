import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BriefDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var brief: CreativeBrief
    @Query private var outputs: [PlatformOutput]
    @Query private var tasks: [CreatorTask]
    @Query private var attachments: [CreatorAttachment]
    @Query private var subscriptions: [SubscriptionState]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @State private var showDevelopment = false
    @State private var showProposal = false
    @State private var showRevisionRequest = false
    @State private var showRevisionProposal = false
    @State private var confirmArchive = false
    @State private var showDetails = false
    @State private var showTasks = false
    @State private var showPlatforms = false
    @State private var showHistory = false
    @State private var showNewPillar = false
    @State private var showPillarPicker = false
    @State private var showFileImporter = false
    @FocusState private var focusedLongField: LongField?

    private enum LongField: Hashable {
        case premise
        case script
        case assumptions
    }

    private var contentFormat: ContentFormat {
        outputs.contains { $0.platform == .youtubeVideo } ? .longForm : .shortForm
    }

    private var resumablePostOutput: PlatformOutput? {
        outputs.first {
            PostDraftResumePolicy.shouldResume(
                briefStatus: brief.status,
                outputStatus: $0.status
            )
        }
    }

    init(brief: CreativeBrief) {
        self.brief = brief
        let id = brief.id
        _outputs = Query(filter: #Predicate<PlatformOutput> { $0.briefID == id }, sort: \PlatformOutput.createdAt)
        _tasks = Query(filter: #Predicate<CreatorTask> { $0.briefID == id }, sort: \CreatorTask.sortOrder)
        _attachments = Query(filter: #Predicate<CreatorAttachment> { $0.briefID == id }, sort: \CreatorAttachment.createdAt)
    }

    var body: some View {
        ScrollView {
            if let resumablePostOutput {
                ResumablePostEditorView(
                    brief: brief,
                    output: resumablePostOutput,
                    onSpark: { showDevelopment = true }
                )
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, 120)
            } else {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    StatusTag(status: brief.status)
                    TextField("Brief title", text: $brief.title)
                        .font(.agentBriefTitle)
                        .tracking(-0.4)
                        .agentSingleLineSubmit()
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        AgentInputHeader(title: "Premise", isEditing: focusedLongField == .premise) {
                            focusedLongField = nil
                        }
                        TextField("The core premise", text: $brief.premise, axis: .vertical)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(2...5)
                            .focused($focusedLongField, equals: .premise)
                    }
                }

                actionBlock

                if canRequestRevision {
                    Button {
                        showRevisionRequest = true
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            CyAsterisk(color: .onCyAccent, size: 13, strokeWidth: 1.4)
                            Text("Revise with Cy")
                                .font(.agentBody.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.onCyAccent)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.cyAccent, in: .rect(cornerRadius: AgentRadius.control))
                        .shadow(color: Color.cyAccent.opacity(0.18), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens a revision request. Your brief changes only after you accept it.")
                }

                if hasComposedContent {
                    essentialSection

                    DisclosureGroup(isExpanded: $showDetails) {
                        detailsSection
                            .padding(.top, AgentSpacing.x4)
                    } label: {
                        BriefDisclosureLabel(title: "Details", detail: "Audience, pillar, filming")
                    }

                    attachmentSection

                    taskSection

                    DisclosureGroup(isExpanded: $showPlatforms) {
                        outputSection
                            .padding(.top, AgentSpacing.x4)
                    } label: {
                        BriefDisclosureLabel(title: "Platforms", detail: platformSummary)
                    }

                    DisclosureGroup(isExpanded: $showHistory) {
                        lifecycleSection
                            .padding(.top, AgentSpacing.x3)
                    } label: {
                        BriefDisclosureLabel(title: "History", detail: brief.status.title)
                    }
                }

                if brief.status == .posted {
                    Button("Create a new idea from this", systemImage: "arrow.triangle.branch") {
                        if appModel.createRepurposedSpark(from: brief, context: context) != nil {
                            appModel.selectedTab = .ideaBank
                            appModel.notice = .info("A new idea is waiting in your Idea Bank.")
                        }
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())
                }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(resumablePostOutput == nil ? brief.title : "New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if resumablePostOutput == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if hasComposedContent {
                            Button("Ask Cy to revise", systemImage: "wand.and.stars") { showRevisionRequest = true }
                                .disabled(!appModel.allows(.revise, context: context))
                        }
                        Button("Archive", systemImage: "archivebox", role: .destructive) { confirmArchive = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $showDevelopment) {
            DevelopBriefView(brief: brief, output: resumablePostOutput ?? outputs.first)
        }
        .sheet(isPresented: $showProposal) {
            if let proposal = appModel.proposal(for: brief, context: context) {
                BriefProposalReviewView(brief: brief, initialProposal: proposal)
            }
        }
        .sheet(isPresented: $showRevisionRequest, onDismiss: {
            if appModel.revisionProposal(for: brief, context: context) != nil { showRevisionProposal = true }
        }) {
            BriefRevisionRequestView(brief: brief, freeRevisionsRemaining: freeRevisionsRemaining)
        }
        .sheet(isPresented: $showRevisionProposal) {
            if let revision = appModel.revisionProposal(for: brief, context: context) {
                BriefProposalReviewView(brief: brief, revisionProposal: revision)
            }
        }
        .sheet(isPresented: $showNewPillar) {
            NewPillarView { pillar in
                brief.pillarID = pillar.id
                brief.updatedAt = Date()
                try? context.save()
            }
        }
        .sheet(isPresented: $showPillarPicker) {
            PillarSelectionView(
                pillars: activePillars,
                selectedID: brief.pillarID
            ) { pillarID in
                brief.pillarID = pillarID
                brief.updatedAt = Date()
                try? context.save()
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Archive this brief?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) { appModel.archive(brief, context: context) }
        } message: {
            Text("Archive is always manual. You can still find this content in Your work.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .pdf, .plainText, .movie, .audio], allowsMultipleSelection: false) { result in
            importAttachment(result)
        }
        .onChange(of: manualDevelopmentFingerprint) { oldValue, newValue in
            guard oldValue != newValue, brief.status == .spark else { return }
            appModel.noteManualDevelopment(of: brief, context: context)
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    @ViewBuilder
    private var actionBlock: some View {
        if appModel.proposal(for: brief, context: context) != nil {
            CyCallout(heading: .madeThisForYou) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    Text("Your draft is ready to review.").font(.agentBody)
                    Button("Review draft", systemImage: "doc.text.magnifyingglass") { showProposal = true }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            }
        } else if appModel.revisionProposal(for: brief, context: context) != nil {
            CyCallout(heading: .madeThisForYou) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    Text("Your requested change is ready.").font(.agentBody)
                    Button("Review revision", systemImage: "doc.text.magnifyingglass") { showRevisionProposal = true }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            }
        } else { switch brief.status {
        case .spark:
            Button("Develop with Cy", systemImage: "sparkles") { showDevelopment = true }
                .buttonStyle(AgentCyPrimaryButtonStyle())
        case .developing:
            if hasComposedContent {
                CyCallout(heading: .thinksYouShould) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        Text("Read it once, edit anything, then mark it ready.").font(.agentBody)
                        Button("Approve brief", systemImage: "checkmark") { appModel.approve(brief: brief, context: context) }
                            .buttonStyle(AgentCompactPrimaryButtonStyle())
                    }
                }
            } else {
                Button("Continue with Cy", systemImage: "sparkles") { showDevelopment = true }
                    .buttonStyle(AgentCyPrimaryButtonStyle())
            }
        case .ready:
            BriefGuidanceRow(text: "Ready to film. Add it to your week when you want.")
        case .scheduled:
            BriefGuidanceRow(text: "Planned for your week. Move it anytime.")
        case .posted:
            BriefGuidanceRow(text: "\(postedCount) of \(outputs.count) platforms posted.")
        case .archived:
            Text("Archived and read-only.").font(.agentBody).foregroundStyle(Color.agentSecondary)
        } }
    }

    private var essentialSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Video")
            AgentDurationPicker(seconds: $brief.durationSeconds, format: contentFormat)
            BriefField(label: "Hook", text: $brief.spokenHook)
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                AgentInputHeader(title: "Script", isEditing: focusedLongField == .script) {
                    focusedLongField = nil
                }
                TextEditor(text: $brief.scriptBeatsText)
                    .font(.agentBody)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(AgentSpacing.x3)
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                    .focused($focusedLongField, equals: .script)
            }
            BriefField(label: "Ending", text: $brief.close)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            if activePillars.isEmpty {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Pillar")
                    Text("No pillars yet.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                    Button("Add pillar", systemImage: "plus") {
                        showNewPillar = true
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())
                    .accessibilityHint("Creates a pillar and assigns it to this brief")
                }
            } else {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Pillar")
                    Button {
                        showPillarPicker = true
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            if let selectedPillar {
                                Circle()
                                    .fill(Color(agentHex: selectedPillar.resolvedColorHex(in: activePillars)))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
                                Text(selectedPillar.name)
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentText)
                            } else {
                                Circle()
                                    .stroke(Color.agentBorder, lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                                Text("No pillar")
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pillar")
                    .accessibilityValue(selectedPillar?.name ?? "No pillar")
                    .accessibilityHint("Choose a pillar")
                }
            }
            BriefField(label: "Audience", text: $brief.audience)
            BriefField(label: "Goal", text: $brief.creativeGoal)
            BriefField(label: "Takeaway", text: $brief.takeaway)
            BriefField(label: "Notes", text: $brief.notes)
            BriefField(label: "On-screen text", text: $brief.firstFrameText)
            BriefField(label: "Call to action", text: $brief.ctaIntent)
            BriefField(label: "How to film", text: $brief.filmingGuidance)
            BriefField(label: "How to edit", text: $brief.editingGuidance)
            assumptionsSection
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Files", trailing: "\(attachments.count)")
            ForEach(attachments) { attachment in
                HStack {
                    Text(attachment.fileName).font(.agentBody).lineLimit(1)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file)).font(.agentMono).foregroundStyle(Color.agentSecondary)
                    Button(role: .destructive) { context.delete(attachment); try? context.save() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete \(attachment.fileName)")
                }
                .frame(minHeight: 44)
            }
            if brief.status != .archived {
                Button("Add file", systemImage: "paperclip") { showFileImporter = true }
                    .buttonStyle(AgentSecondaryButtonStyle())
            }
            Text("Files stay in your private app data and are never sent to Cy.")
                .font(.agentMono).foregroundStyle(Color.agentSecondary)
        }
    }

    private func importAttachment(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 25 * 1_024 * 1_024 else {
                appModel.notice = .info("Choose a file smaller than 25 MB.")
                return
            }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
            let kind: AttachmentKind = type.conforms(to: .image) ? .photo : (type.conforms(to: .movie) ? .video : (type.conforms(to: .pdf) ? .document : .other))
            context.insert(CreatorAttachment(
                ownerKind: .referenceFile,
                briefID: brief.id,
                fileName: url.lastPathComponent,
                kind: kind,
                uniformTypeIdentifier: type.identifier,
                byteCount: Int64(data.count),
                localRelativePath: "",
                cloudData: data,
                syncState: .synced
            ))
            try context.save()
        } catch {
            appModel.notice = .error("That file could not be added.")
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            ForEach(outputs) { output in
                PlatformOutputEditor(
                    brief: brief,
                    output: output,
                    canPlan: [.ready, .scheduled, .posted].contains(brief.status)
                )
            }
            if brief.status != .archived, !availablePublishingChoices.isEmpty {
                Menu {
                    ForEach(availablePublishingChoices, id: \.format.id) { choice in
                        Button("\(choice.destination.name) · \(choice.format.name)") {
                            _ = appModel.addPublishingOutput(to: brief, destination: choice.destination, format: choice.format, context: context)
                        }
                    }
                } label: {
                    Label("Add platform", systemImage: "plus")
                }
                .buttonStyle(AgentSecondaryButtonStyle())
                .accessibilityHint("Adds another editable platform version to this brief")
            }
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        if !topLevelTasks.isEmpty {
            DisclosureGroup(isExpanded: $showTasks) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(topLevelTasks) { task in
                        EditorialRow { TaskRow(task: task, allTasks: tasks) }
                    }
                }
                .padding(.top, AgentSpacing.x3)
            } label: {
                BriefDisclosureLabel(
                    title: "Tasks",
                    detail: "\(topLevelTasks.filter(\.isCompleted).count) of \(topLevelTasks.count) complete"
                )
            }
        }
    }

    private var assumptionsSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                AgentInputHeader(title: "Cy notes", isEditing: focusedLongField == .assumptions) {
                    focusedLongField = nil
                }
                Spacer()
                MetaLabel("Voice \(Int(brief.voiceConfidence * 100))%")
            }
            TextEditor(text: $brief.assumptionsText)
                .font(.agentBody)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(AgentSpacing.x3)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                .accessibilityLabel("Visible assumptions, one per line")
                .focused($focusedLongField, equals: .assumptions)
            Slider(value: $brief.voiceConfidence, in: 0...1, step: 0.01)
                .accessibilityLabel("Voice confidence")
                .accessibilityValue("\(Int(brief.voiceConfidence * 100)) percent")
            Text("Voice score reflects the examples Cy has learned from.")
                .font(.agentMono).foregroundStyle(Color.agentSecondary)
        }
        .disabled(brief.status == .archived)
    }

    private var lifecycleSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            ForEach(brief.lifecycleHistory.reversed()) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.status.title)
                        .font(.agentBody)
                    Spacer()
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.agentMono)
                        .foregroundStyle(Color.agentSecondary)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var hasComposedContent: Bool { !brief.spokenHook.isEmpty || !brief.scriptBeats.isEmpty }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var selectedPillar: Pillar? { activePillars.first { $0.id == brief.pillarID } }
    private var topLevelTasks: [CreatorTask] { tasks.filter { $0.parentTaskID == nil } }
    private var postedCount: Int { outputs.filter { $0.status == .posted }.count }
    private var availablePublishingChoices: [(destination: PublishingDestination, format: PublishingFormat)] {
        formats.compactMap { format in
            guard !format.isArchived,
                  let destination = destinations.first(where: { $0.id == format.destinationID && !$0.isArchived }),
                  !outputs.contains(where: { $0.destinationID == destination.id && $0.formatID == format.id }) else { return nil }
            return (destination, format)
        }
    }
    private var platformSummary: String {
        if outputs.isEmpty { return "None added" }
        return "\(outputs.count) added · \(postedCount) posted"
    }
    private var canRequestRevision: Bool {
        hasComposedContent &&
        brief.status != .archived &&
        appModel.proposal(for: brief, context: context) == nil &&
        appModel.revisionProposal(for: brief, context: context) == nil &&
        appModel.allows(.revise, context: context)
    }
    private var freeRevisionsRemaining: Int? {
        guard let state = subscriptions.first, state.access == .freeJourney else { return nil }
        return max(0, 3 - state.revisionRequestsUsed)
    }
    private var manualDevelopmentFingerprint: String {
        [
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
            brief.assumptionsText
        ].joined(separator: "\u{1F}") + "|\(brief.durationSeconds)"
    }
}

enum PostDraftResumePolicy {
    static func shouldResume(briefStatus: BriefStatus) -> Bool {
        briefStatus == .spark || briefStatus == .developing
    }

    static func shouldResume(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus
    ) -> Bool {
        if outputStatus == .posted { return false }
        return outputStatus == .draft || shouldResume(briefStatus: briefStatus)
    }

    static func outputStatus(briefStatus: BriefStatus, current: PlatformOutputStatus) -> PlatformOutputStatus {
        shouldResume(briefStatus: briefStatus, outputStatus: current) ? .draft : current
    }
}

private struct PillarSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let pillars: [Pillar]
    let selectedID: UUID?
    let onSelect: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    selectionRow(title: "No pillar", colorHex: nil, id: nil)
                    ForEach(pillars) { pillar in
                        selectionRow(title: pillar.name, colorHex: pillar.resolvedColorHex(in: pillars), id: pillar.id)
                    }
                }
                .padding(.horizontal, AgentSpacing.x6)
                .padding(.top, AgentSpacing.x4)
            }
            .navigationTitle("Choose a pillar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .agentScreen()
        }
    }

    private func selectionRow(title: String, colorHex: String?, id: UUID?) -> some View {
        Button {
            onSelect(id)
            dismiss()
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                if let colorHex {
                    Circle()
                        .fill(Color(agentHex: colorHex))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
                } else {
                    Circle()
                        .stroke(Color.agentBorder, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                }
                Text(title)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                Spacer()
                if selectedID == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                }
            }
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
        .accessibilityValue(selectedID == id ? "Selected" : "Not selected")
    }
}

struct BriefDisclosureLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.agentHeadline).foregroundStyle(Color.agentText)
            Spacer()
            Text(detail).font(.agentMono).foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 44)
    }
}

private struct BriefRevisionRequestView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let brief: CreativeBrief
    let freeRevisionsRemaining: Int?
    @State private var scope: BriefRevisionFieldWire = .wholeBrief
    @State private var instruction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Scope", selection: $scope) {
                        ForEach(BriefRevisionFieldWire.allCases) { field in Text(field.title).tag(field) }
                    }
                    AgentMultilineField(
                        label: "Change",
                        placeholder: "What should change?",
                        text: $instruction,
                        lineLimit: 3...8
                    )
                } header: {
                    Text("Focused instruction")
                } footer: {
                    Text("Cy will prepare an editable draft. Your brief changes only after you accept it.")
                }

                if let freeRevisionsRemaining {
                    Section("Free journey") {
                        LabeledContent("Scoped revisions remaining", value: "\(freeRevisionsRemaining)")
                    }
                }

                Button("Prepare revision", systemImage: "wand.and.stars") {
                    Task {
                        await appModel.requestRevision(for: brief, scope: scope, instruction: instruction, context: context)
                        if appModel.revisionProposal(for: brief, context: context) != nil { dismiss() }
                    }
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isWorking)
            }
            .scrollContentBackground(.hidden)
            .background(Color.agentCanvas)
            .navigationTitle("Ask Cy to revise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .agentKeyboardDismissal()
    }
}

private struct BriefProposalReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let brief: CreativeBrief
    @State private var proposal: BriefProposal
    @State private var confirmDiscard = false
    @State private var showDetails = false
    @State private var showCyNotes = false
    @State private var showPlatforms = false
    @State private var showTasks = false
    private let revisionProposal: BriefRevisionProposal?

    private var contentFormat: ContentFormat {
        proposal.variants.contains { $0.platform == .youtubeVideo } ? .longForm : .shortForm
    }

    init(brief: CreativeBrief, initialProposal: BriefProposal) {
        self.brief = brief
        revisionProposal = nil
        _proposal = State(initialValue: initialProposal)
    }

    init(brief: CreativeBrief, revisionProposal: BriefRevisionProposal) {
        self.brief = brief
        self.revisionProposal = revisionProposal
        _proposal = State(initialValue: revisionProposal.edited)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    EditorialHeader(
                        kicker: revisionProposal == nil ? "Draft" : "Revision",
                        title: revisionProposal == nil ? "Review your video." : "Review the changes.",
                        subtitle: "Edit anything. Nothing changes until you accept."
                    )
                    if let revisionProposal {
                        CyCallout(heading: .madeThisForYou) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                MetaLabel("Changed · \(revisionProposal.requestedScope.title)")
                                Text(revisionProposal.explanation).font(.agentBody)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AgentSpacing.x2) {
                                        ForEach(revisionProposal.changedFields) { field in
                                            Text(field.title)
                                                .font(.agentMono)
                                                .padding(.horizontal, AgentSpacing.x3)
                                                .frame(minHeight: 32)
                                                .background(Color.agentSurface)
                                                .clipShape(.capsule)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    BriefField(label: "Title", text: $proposal.draft.title)
                    AgentDurationPicker(seconds: $proposal.draft.durationSeconds, format: contentFormat)
                    BriefField(label: "Hook", text: $proposal.draft.spokenHook)
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Script")
                        ForEach(proposal.draft.scriptBeats.indices, id: \.self) { index in
                            AgentMultilineField(
                                label: "Beat \(index + 1)",
                                placeholder: "Write this part of the script",
                                text: $proposal.draft.scriptBeats[index],
                                lineLimit: 2...8
                            )
                        }
                    }
                    BriefField(label: "Ending", text: $proposal.draft.close)

                    DisclosureGroup(isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            BriefField(label: "What it is about", text: $proposal.draft.premise)
                            BriefField(label: "Audience", text: $proposal.draft.audience)
                            BriefField(label: "Goal", text: $proposal.draft.goal)
                            BriefField(label: "Takeaway", text: $proposal.draft.takeaway)
                            BriefField(label: "On-screen text", text: $proposal.draft.firstFrameText)
                            BriefField(label: "Call to action", text: $proposal.draft.ctaIntent)
                            BriefField(label: "How to film", text: $proposal.draft.filmingGuidance)
                            BriefField(label: "How to edit", text: $proposal.draft.editingGuidance)
                        }
                        .padding(.top, AgentSpacing.x4)
                    } label: {
                        BriefDisclosureLabel(title: "Details", detail: "Audience, filming, edit")
                    }

                    DisclosureGroup(isExpanded: $showCyNotes) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                            ForEach(proposal.draft.assumptions.indices, id: \.self) { index in
                                AgentMultilineField(
                                    label: "Note \(index + 1)",
                                    placeholder: "Edit Cy's note",
                                    text: $proposal.draft.assumptions[index]
                                )
                            }
                            LabeledContent("Voice match", value: "\(Int(proposal.draft.voiceConfidence * 100))%")
                            Slider(value: $proposal.draft.voiceConfidence, in: 0...1, step: 0.01)
                                .accessibilityLabel("Voice match")
                        }
                        .padding(.top, AgentSpacing.x4)
                    } label: {
                        BriefDisclosureLabel(title: "Cy notes", detail: "Voice \(Int(proposal.draft.voiceConfidence * 100))%")
                    }

                    if !proposal.variants.isEmpty {
                        DisclosureGroup(isExpanded: $showPlatforms) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                                ForEach(proposal.variants.indices, id: \.self) { index in
                                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                        Text(proposal.variants[index].platform.title).font(.agentHeadline)
                                        BriefField(label: "Caption", text: $proposal.variants[index].caption)
                                        BriefField(label: "Title", text: $proposal.variants[index].titleOverride)
                                        BriefField(label: "Opening", text: $proposal.variants[index].openingAdjustment)
                                        BriefField(label: "Call to action", text: $proposal.variants[index].cta)
                                        BriefField(label: "Edit", text: $proposal.variants[index].editChanges)
                                    }
                                }
                            }
                            .padding(.top, AgentSpacing.x4)
                        } label: {
                            BriefDisclosureLabel(title: "Platforms", detail: "\(proposal.variants.count)")
                        }
                    }

                    if !proposal.tasks.isEmpty {
                        DisclosureGroup(isExpanded: $showTasks) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                ForEach(proposal.tasks.indices, id: \.self) { index in
                                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                        TextField("Task", text: $proposal.tasks[index].title)
                                            .agentSingleLineSubmit()
                                            .font(.agentBody)
                                        Picker("Kind", selection: $proposal.tasks[index].kind) {
                                            ForEach(CreatorTaskKind.allCases) { Text($0.title).tag($0) }
                                        }
                                        AgentMultilineField(
                                            label: "Notes",
                                            placeholder: "Add task notes",
                                            text: $proposal.tasks[index].notes,
                                            lineLimit: 2...5
                                        )
                                        TextField("Minutes", value: estimatedMinutesBinding(index), format: .number)
                                            .agentSingleLineSubmit()
                                            .keyboardType(.numberPad)
                                        Toggle("Marks filming complete", isOn: recordingMilestoneBinding(index))
                                            .disabled(proposal.tasks[index].kind != .filming)
                                    }
                                    .padding(AgentSpacing.x4)
                                    .background(Color.agentSurface)
                                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                                }
                            }
                            .padding(.top, AgentSpacing.x4)
                        } label: {
                            BriefDisclosureLabel(title: "Tasks", detail: "\(proposal.tasks.count)")
                        }
                    }

                    Button(revisionProposal == nil ? "Use this draft" : "Use these changes", systemImage: "checkmark") {
                        if var revisionProposal {
                            revisionProposal.edited = proposal
                            appModel.acceptRevision(revisionProposal, for: brief, context: context)
                        } else {
                            appModel.acceptProposal(proposal, for: brief, context: context)
                        }
                        dismiss()
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    Button(revisionProposal == nil ? "Discard draft" : "Keep current brief", role: revisionProposal == nil ? .destructive : nil) { confirmDiscard = true }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(AgentSpacing.x6)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
            }
            .confirmationDialog("Discard this draft?", isPresented: $confirmDiscard) {
                if revisionProposal == nil {
                    Button("Discard", role: .destructive) { appModel.discardProposal(for: brief, context: context); dismiss() }
                } else {
                    Button("Keep current brief") { appModel.discardRevision(for: brief, context: context); dismiss() }
                }
            }
            .agentScreen()
        }
        .agentKeyboardDismissal()
    }

    private func estimatedMinutesBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { proposal.tasks[index].estimatedMinutes ?? 15 },
            set: { proposal.tasks[index].estimatedMinutes = max(5, min($0, 480)) }
        )
    }

    private func recordingMilestoneBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { proposal.tasks[index].isRecordingMilestone },
            set: { enabled in
                if enabled {
                    for taskIndex in proposal.tasks.indices { proposal.tasks[taskIndex].isRecordingMilestone = false }
                }
                proposal.tasks[index].isRecordingMilestone = enabled
            }
        )
    }
}

private struct StatusTag: View {
    let status: BriefStatus

    var body: some View {
        Text(status.title)
            .font(.agentMono)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Color.cyAccent)
            .accessibilityLabel(status.title)
    }
}

private struct BriefGuidanceRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            CyAsterisk(size: 12, strokeWidth: 1.3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                MetaLabel("Cy")
                    .foregroundStyle(Color.cyAccent)
                Text(text)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AgentSpacing.x3)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BriefField: View {
    let label: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    private var visiblePlaceholder: String {
        label.localizedCaseInsensitiveContains("note") ? "" : label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) { isFocused = false }
            TextField(visiblePlaceholder, text: $text, axis: .vertical)
                .font(.agentBody)
                .lineLimit(2...8)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).strokeBorder(Color.agentBorder, lineWidth: 1))
                .focused($isFocused)
        }
    }
}

private struct PlatformOutputEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let brief: CreativeBrief
    @Bindable var output: PlatformOutput
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    let canPlan: Bool
    @State private var targetDate = Date()
    @State private var confirmDelete = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                if !availableSocialAccounts.isEmpty {
                    Picker("Account", selection: $output.socialAccountID) {
                        Text("No account").tag(UUID?.none)
                        ForEach(availableSocialAccounts) { account in
                            Text(account.label).tag(Optional(account.id))
                        }
                    }
                }
                BriefField(label: "Caption", text: $output.caption)
                BriefField(label: "Opening adjustment", text: $output.openingAdjustment)
                if selectedDestination?.builtInKind == .youtube || output.platform == .youtubeShorts || output.platform == .youtubeVideo {
                    BriefField(label: "Title", text: $output.titleOverride)
                }
                BriefField(label: "CTA", text: $output.cta)
                BriefField(label: "Edit differences", text: $output.editChanges)
                if canPlan {
                    if output.targetDate == nil {
                        Button("Set a due date", systemImage: "calendar.badge.plus") {
                            targetDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            appModel.schedule(output: output, date: targetDate, context: context)
                        }
                        .buttonStyle(AgentCompactSecondaryButtonStyle())
                    } else {
                        DatePicker("Date and time", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: targetDate) { _, date in appModel.schedule(output: output, date: date, context: context) }
                        Button("Remove target") { appModel.schedule(output: output, date: nil, context: context) }
                    }
                    Button(output.status == .posted ? "Mark not posted" : "Mark posted", systemImage: output.status == .posted ? "arrow.uturn.backward" : "paperplane") {
                        appModel.togglePosted(output: output, context: context)
                    }
                    .buttonStyle(AgentCompactPrimaryButtonStyle(
                        background: output.status == .posted ? .agentSurface : .actionAccent,
                        foreground: output.status == .posted ? .agentText : .onAccent,
                        border: output.status == .posted ? .agentBorder : .clear
                    ))
                } else {
                    Text("Mark the brief ready before planning or posting.")
                        .font(.agentMono)
                        .foregroundStyle(Color.agentSecondary)
                }
                if brief.status != .archived {
                    Button("Delete platform", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                    .frame(minHeight: 44)
                }
            }
            .padding(.top, AgentSpacing.x4)
        } label: {
            HStack {
                Text(outputLabel).font(.agentHeadline)
                Spacer()
                MetaLabel(output.status.rawValue)
            }
        }
        .padding(.vertical, AgentSpacing.x4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        .onAppear { targetDate = output.targetDate ?? Date() }
        .confirmationDialog(
            "Delete \(outputLabel)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete platform", role: .destructive) {
                appModel.deletePlatformOutput(output, from: brief, context: context)
            }
        } message: {
            Text("This removes only this platform. Your brief stays intact.")
        }
    }

    private var selectedDestination: PublishingDestination? { destinations.first { $0.id == output.destinationID } }
    private var selectedFormat: PublishingFormat? { formats.first { $0.id == output.formatID } }
    private var availableSocialAccounts: [CreatorSocialAccount] {
        guard let destinationID = output.destinationID else { return [] }
        return socialAccounts.filter { $0.destinationID == destinationID && !$0.isArchived }
    }
    private var outputLabel: String {
        let base = if let destination = selectedDestination, let format = selectedFormat {
            "\(destination.name) · \(format.name)"
        } else {
            output.platform.title
        }
        return base
    }
}
