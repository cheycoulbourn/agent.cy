import SwiftData
import SwiftUI

struct IdeaDraftForm: Equatable {
    var title: String
    var text: String
    var pillarID: UUID?

    init(title: String, text: String, pillarID: UUID?) {
        self.title = title
        self.text = text
        self.pillarID = pillarID
    }

    init(brief: CreativeBrief) {
        title = brief.title
        let notes = brief.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        text = notes.isEmpty ? brief.premise : brief.notes
        pillarID = brief.pillarID
    }
}

enum IdeaDraftRoutePolicy {
    enum Destination: Equatable {
        case editor
        case post
        case archived
    }

    static func destination(for status: BriefStatus) -> Destination {
        switch status {
        case .spark, .developing: .editor
        case .ready, .scheduled, .posted: .post
        case .archived: .archived
        }
    }
}

enum IdeaDraftPersistencePolicy {
    enum Error: Swift.Error, Equatable {
        case emptyTitle
        case notEditable
    }

    static func save(
        _ form: IdeaDraftForm,
        to brief: CreativeBrief,
        now: Date = Date(),
        persist: () throws -> Void
    ) throws {
        guard IdeaDraftRoutePolicy.destination(for: brief.status) == .editor else {
            throw Error.notEditable
        }
        let snapshot = Snapshot(brief: brief)
        do {
            try apply(form, to: brief, now: now)
            try persist()
        } catch {
            snapshot.restore(brief)
            throw error
        }
    }

    static func archive(
        _ form: IdeaDraftForm,
        brief: CreativeBrief,
        now: Date = Date(),
        persist: () throws -> Void
    ) throws {
        guard IdeaDraftRoutePolicy.destination(for: brief.status) == .editor else {
            throw Error.notEditable
        }
        let snapshot = Snapshot(brief: brief)
        do {
            try apply(form, to: brief, now: now)
            BriefLifecycle.archive(brief, now: now)
            try persist()
        } catch {
            snapshot.restore(brief)
            throw error
        }
    }

    private static func apply(_ form: IdeaDraftForm, to brief: CreativeBrief, now: Date) throws {
        let title = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Error.emptyTitle }
        let text = form.text.trimmingCharacters(in: .whitespacesAndNewlines)
        brief.title = title
        brief.notes = text
        brief.premise = text.isEmpty ? title : text
        brief.pillarID = form.pillarID
        brief.updatedAt = now
    }

    private struct Snapshot {
        let title: String
        let premise: String
        let notes: String
        let pillarID: UUID?
        let status: BriefStatus
        let updatedAt: Date
        let archivedAt: Date?
        let lifecycleHistoryText: String

        init(brief: CreativeBrief) {
            title = brief.title
            premise = brief.premise
            notes = brief.notes
            pillarID = brief.pillarID
            status = brief.status
            updatedAt = brief.updatedAt
            archivedAt = brief.archivedAt
            lifecycleHistoryText = brief.lifecycleHistoryText
        }

        func restore(_ brief: CreativeBrief) {
            brief.title = title
            brief.premise = premise
            brief.notes = notes
            brief.pillarID = pillarID
            brief.status = status
            brief.updatedAt = updatedAt
            brief.archivedAt = archivedAt
            brief.lifecycleHistoryText = lifecycleHistoryText
        }
    }
}

struct IdeaPostDraftView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let brief: CreativeBrief
    let preferredOutput: PlatformOutput?
    let suggestedTargetDate: Date?
    let isAlreadyInIdeaBank: Bool

    @State private var form: IdeaDraftForm
    @State private var availablePillars: [Pillar] = []
    @State private var existingOutput: PlatformOutput?
    @State private var plannedOutput: PlatformOutput?
    @State private var showPostEditor = false
    @State private var showDevelopment = false
    @State private var confirmsArchive = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case idea
    }

    init(
        brief: CreativeBrief,
        output: PlatformOutput? = nil,
        suggestedTargetDate: Date? = nil,
        isAlreadyInIdeaBank: Bool = false
    ) {
        self.brief = brief
        preferredOutput = output
        self.suggestedTargetDate = suggestedTargetDate
        self.isAlreadyInIdeaBank = isAlreadyInIdeaBank
        _form = State(initialValue: IdeaDraftForm(brief: brief))
        _existingOutput = State(initialValue: output?.briefID == brief.id ? output : nil)
    }

    var body: some View {
        Group {
            switch IdeaDraftRoutePolicy.destination(for: brief.status) {
            case .editor:
                editor
            case .post:
                postState
            case .archived:
                archivedState
            }
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
#if targetEnvironment(macCatalyst)
        .toolbar(.hidden, for: .navigationBar)
#else
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AgentToolbarIconButton(title: "Back", icon: .back, action: close)
            }
            if IdeaDraftRoutePolicy.destination(for: brief.status) == .editor {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Save idea", action: saveAndClose)
                            .disabled(!hasValidTitle)
                        Button("Archive idea", role: .destructive) {
                            confirmsArchive = true
                        }
                    } label: {
                        AgentToolbarIconLabel(icon: .more)
                    }
                    .accessibilityLabel("Idea options")
                }
            }
        }
#endif
        .task { loadSupportingData() }
        .sheet(isPresented: $showDevelopment) {
            DevelopBriefView(brief: brief, output: existingOutput)
                .agentDesktopWorkspaceModal()
        }
        .navigationDestination(isPresented: $showPostEditor) {
            if let plannedOutput {
                ResumablePostEditorView(
                    brief: brief,
                    output: plannedOutput,
                    suggestedTargetDate: suggestedTargetDate,
                    onSpark: { showDevelopment = true }
                )
            } else {
                unavailablePostState
            }
        }
        .confirmationDialog(
            "Archive this idea?",
            isPresented: $confirmsArchive,
            titleVisibility: .visible
        ) {
            Button("Archive idea", role: .destructive, action: archive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The idea leaves your active lists but stays in your archive.")
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: isAlreadyInIdeaBank ? "Idea Bank" : "Spark",
                    title: "Keep the thought clear.",
                    subtitle: "Edit the idea here. Build with Cy or turn it into a post only when you are ready."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    AgentInputHeader(title: "Title", isEditing: focusedField == .title) {
                        focusedField = nil
                    }
                    TextField("Name this idea", text: $form.title, axis: .vertical)
                        .font(.paperInter(size: 24, weight: .bold, relativeTo: .title2))
                        .lineLimit(1...3)
                        .padding(AgentSpacing.x4)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(hasValidTitle ? Color.agentBorder : Color.agentDestructive, lineWidth: 1)
                        }
                        .focused($focusedField, equals: .title)
                    if !hasValidTitle {
                        Text("Give the idea a title before saving or developing it.")
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentDestructive)
                    }
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    AgentInputHeader(title: "Idea", isEditing: focusedField == .idea) {
                        focusedField = nil
                    }
                    TextEditor(text: $form.text)
                        .font(.agentBody)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .padding(AgentSpacing.x4)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.panel)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                        .focused($focusedField, equals: .idea)
                }

                pillarPicker

                VStack(spacing: AgentSpacing.x3) {
                    Button(action: developWithCy) {
                        HStack(spacing: AgentSpacing.x2) {
                            CyAsterisk(color: .cyAccent, size: 16, strokeWidth: 1.5)
                            Text("Build with Cy")
                        }
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(!hasValidTitle)

                    Button(action: planPost) {
                        Text(suggestedTargetDate == nil ? "Turn into a post" : "Plan this post")
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())
                    .disabled(!hasValidTitle)
                }
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x4)
            .padding(.bottom, AgentSpacing.x8)
        }
        .scrollDismissesKeyboard(.interactively)
#if targetEnvironment(macCatalyst)
        .safeAreaInset(edge: .top, spacing: 0) {
            AgentDesktopDetailRail(title: "Idea", backAction: close) {
                Menu {
                    Button("Save idea", action: saveAndClose)
                        .disabled(!hasValidTitle)
                    Button("Archive idea", role: .destructive) {
                        confirmsArchive = true
                    }
                } label: {
                    AgentDesktopDetailIconLabel(icon: .more)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityLabel("Idea options")
            }
        }
#endif
    }

    private var pillarPicker: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Pillar")
            Menu {
                Button("No pillar") { form.pillarID = nil }
                ForEach(availablePillars) { pillar in
                    Button {
                        form.pillarID = pillar.id
                    } label: {
                        PillarMenuChoiceLabel(
                            title: pillar.name,
                            colorHex: pillar.resolvedColorHex(in: availablePillars),
                            isSelected: form.pillarID == pillar.id
                        )
                    }
                }
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    if let selectedPillar {
                        PillarColorMark(
                            color: Color(agentHex: selectedPillar.resolvedColorHex(in: availablePillars)),
                            diameter: AgentSpacing.x2
                        )
                    }
                    Text(selectedPillar?.name ?? "No pillar")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentText)
                    Spacer()
                    AgentIconView(.expand, size: 12)
                        .foregroundStyle(Color.agentSecondary)
                }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
            }
            .buttonStyle(AgentPressButtonStyle())
        }
    }

    private var postState: some View {
        VStack(spacing: AgentSpacing.x4) {
            AgentEmptyState(
                title: "This idea is now a post",
                message: "Open it from Plan or Agenda to continue its production workflow.",
                icon: .ideas
            )
            if existingOutput != nil {
                Button("Open post") {
                    plannedOutput = existingOutput
                    showPostEditor = true
                }
                .buttonStyle(AgentSecondaryButtonStyle())
                .padding(.horizontal, AgentLayout.pageMargin)
            }
        }
    }

    private var archivedState: some View {
        AgentEmptyState(
            title: "This idea is archived",
            message: "It stays in your archive and cannot be edited from this page.",
            icon: .archive
        )
    }

    private var unavailablePostState: some View {
        AgentEmptyState(
            title: "This post is unavailable",
            message: "It may have been moved or removed. Return to Plan and try again.",
            icon: .warning
        )
    }

    private var selectedPillar: Pillar? {
        availablePillars.first { $0.id == form.pillarID }
    }

    private var hasValidTitle: Bool {
        !form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        form != IdeaDraftForm(brief: brief)
    }

    private func loadSupportingData() {
        let destination = IdeaDraftRoutePolicy.destination(for: brief.status)
        guard destination != .archived else { return }
        do {
            if destination == .editor {
                let pillars = try context.fetch(FetchDescriptor<Pillar>(
                    sortBy: [SortDescriptor(\.createdAt)]
                ))
                let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
                availablePillars = pillars.filter {
                    !$0.isArchived && WorkspaceScope.includes(
                        $0.workspaceID,
                        activeWorkspaceID: brief.workspaceID ?? appModel.activeWorkspaceID,
                        workspaces: workspaces
                    )
                }
            }

            if existingOutput == nil {
                let briefID = brief.id
                existingOutput = try context.fetch(FetchDescriptor<PlatformOutput>(
                    predicate: #Predicate { $0.briefID == briefID },
                    sortBy: [SortDescriptor(\.createdAt)]
                )).first
            }
        } catch {
            appModel.notice = .error("This idea’s supporting details could not be loaded.")
        }
    }

    private func saveForm() -> Bool {
        do {
            try IdeaDraftPersistencePolicy.save(form, to: brief) {
                try context.save()
            }
            form = IdeaDraftForm(brief: brief)
            WidgetSnapshotService.refresh(context: context)
            return true
        } catch IdeaDraftPersistencePolicy.Error.emptyTitle {
            appModel.notice = .info("Give the idea a title before saving it.")
        } catch IdeaDraftPersistencePolicy.Error.notEditable {
            appModel.notice = .info("This idea has moved to another stage and can no longer be edited here.")
        } catch {
            appModel.notice = .error("That idea could not be saved. Your edits are still on this page.")
        }
        return false
    }

    private func saveAndClose() {
        guard saveForm() else { return }
        dismiss()
    }

    private func close() {
        guard IdeaDraftRoutePolicy.destination(for: brief.status) == .editor else {
            dismiss()
            return
        }
        guard !hasUnsavedChanges || saveForm() else { return }
        dismiss()
    }

    private func developWithCy() {
        guard saveForm() else { return }
        showDevelopment = true
    }

    private func planPost() {
        guard saveForm() else { return }
        guard appModel.allows(.schedule, context: context) else {
            appModel.notice = .info("Planning a post is not available with your current access. Your idea is still saved.")
            return
        }
        guard let output = existingOutput ?? appModel.ensurePostDraft(for: brief, context: context) else {
            return
        }
        existingOutput = output
        plannedOutput = output
        showPostEditor = true
    }

    private func archive() {
        do {
            try IdeaDraftPersistencePolicy.archive(form, brief: brief) {
                try context.save()
            }
            appModel.queueCalendarSync(context: context)
            WidgetSnapshotService.refresh(context: context)
            dismiss()
        } catch IdeaDraftPersistencePolicy.Error.emptyTitle {
            appModel.notice = .info("Give the idea a title before archiving it.")
        } catch {
            appModel.notice = .error("That idea could not be archived. Nothing was changed.")
        }
    }
}

#if DEBUG
enum IdeaDraftRuntimeFixture {
    static func requestsIdeaDraft(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-agentCyPreviewIdeaDraft")
    }
}
#endif
