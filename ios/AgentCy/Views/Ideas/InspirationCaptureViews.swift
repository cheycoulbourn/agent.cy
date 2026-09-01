import SwiftData
import SwiftUI
import UIKit

private enum ManualIdeaFocusField: Hashable {
    case title
    case premise
    case spokenHook
    case takeaway
    case filmingApproach
}

private struct CyAnalysisToolbarMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isProcessing: Bool

    var body: some View {
        ZStack {
            CyAsterisk(color: .cyAccent, size: 15, strokeWidth: 1.8)
                .opacity(isProcessing ? 0 : 1)
                .scaleEffect(isProcessing ? 0.25 : 1)
                .blur(radius: isProcessing ? 4 : 0)

            CyThinkingMark(color: .cyAccent, size: 17)
                .opacity(isProcessing ? 1 : 0)
                .scaleEffect(isProcessing ? 1 : 0.25)
                .blur(radius: isProcessing ? 0 : 4)
        }
        .frame(width: 18, height: 18)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.3, bounce: 0),
            value: isProcessing
        )
    }
}

enum InspirationReviewAnalysisAction: Equatable {
    case analyze
    case retry
    case processing
    case hidden

    var title: String? {
        switch self {
        case .analyze: "Analyze with Cy"
        case .retry: "Try Cy again"
        case .processing: "Cy is analyzing"
        case .hidden: nil
        }
    }

    var detail: String? {
        switch self {
        case .analyze: "Turn this reference into an original direction."
        case .retry: "Run the analysis again without changing your saved reference."
        case .processing: "Your saved post is safe while Cy works."
        case .hidden: nil
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .analyze: "Analyze with Cy"
        case .retry: "Try analysis again with Cy"
        case .processing: "Cy is analyzing this post"
        case .hidden: ""
        }
    }

    static func resolve(
        status: InspirationStatus,
        hasResult: Bool,
        hasLinkedBrief: Bool,
        isAnalyzing: Bool
    ) -> InspirationReviewAnalysisAction {
        if hasResult || hasLinkedBrief || status == .converted { return .hidden }
        if isAnalyzing { return .processing }
        if status == .failed || status == .shaping || status == .ready { return .retry }
        return .analyze
    }
}

struct InspirationReviewFailurePresentation: Equatable {
    let title: String
    let message: String

    static func resolve(errorCode: String?) -> InspirationReviewFailurePresentation {
        if errorCode == "source_content_unavailable" {
            return InspirationReviewFailurePresentation(
                title: "Cy needs the post content",
                message: "The link is saved. Share the post again with its caption or video, then try Cy again."
            )
        }
        return InspirationReviewFailurePresentation(
            title: "Cy couldn’t finish the analysis",
            message: "Your saved post is safe. Try Cy again when you’re ready."
        )
    }
}

enum InspirationReviewUnsavedWorkPolicy {
    static func hasChanges(
        hasLinkedBrief: Bool,
        generatedDraftChanged: Bool,
        manualDraft: ManualInspirationIdeaDraft,
        manualDraftBaseline: ManualInspirationIdeaDraft
    ) -> Bool {
        guard !hasLinkedBrief else { return false }
        return generatedDraftChanged || manualDraft != manualDraftBaseline
    }
}

struct InspirationReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \InspirationSource.updatedAt, order: .reverse) private var sources: [InspirationSource]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    let sourceID: UUID
    @State private var draft: InspirationEditableIdea?
    @State private var isEditing = false
    @State private var isAnalyzing = false
    @State private var analysisRequestID: UUID?
    @State private var filmingSchedule: InspirationFilmingScheduleSelection?
    @State private var confirmsDeletion = false
    @State private var confirmsUnsavedClose = false
    @State private var isSavingChanges = false
    @State private var manualDraft = ManualInspirationIdeaDraft()
    @State private var draftBaseline: InspirationEditableIdea?
    @State private var manualDraftBaseline = ManualInspirationIdeaDraft()
    @State private var loadedSourceID: UUID?
    @FocusState private var manualFocus: ManualIdeaFocusField?

    private var source: InspirationSource? {
        sources.first {
            $0.id == sourceID && SavedPostsScopePolicy.includes(
                recordWorkspaceID: $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID
            )
        }
    }

    private var linkedBrief: CreativeBrief? {
        guard let source, let linkedBriefID = source.linkedBriefID else { return nil }
        return briefs.first {
            $0.id == linkedBriefID && $0.workspaceID == source.workspaceID
        }
    }

    private var result: InspirationShapeResultWire? {
        guard let source,
              !source.shapePayloadJSON.isEmpty,
              let data = source.shapePayloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder.agentCy.decode(InspirationShapeResultWire.self, from: data)
    }

    private var pillars: [Pillar] {
        guard let source else { return [] }
        return allPillars.filter { $0.workspaceID == source.workspaceID && !$0.isArchived }
    }

    private var selectedPillar: Pillar? {
        guard let pillarID = draft?.pillarID else { return nil }
        return pillars.first { $0.id == pillarID }
    }

    private var analysisAction: InspirationReviewAnalysisAction {
        guard let source else { return .hidden }
        return InspirationReviewAnalysisAction.resolve(
            status: source.status,
            hasResult: result != nil,
            hasLinkedBrief: linkedBrief != nil,
            isAnalyzing: isAnalyzing
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let source, let brief = linkedBrief, result == nil {
                    manualBriefContent(source: source, brief: brief)
                } else if let source, let result {
                    resultContent(source: source, result: result, brief: linkedBrief)
                } else if let source, source.status == .failed {
                    failureContent(source)
                } else if let source {
                    analysisContent(source)
                } else {
                    AgentEmptyState(
                        title: "Saved post unavailable",
                        message: "This post is no longer in agent.cy.",
                        icon: .link
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: requestClose)
                }
                if hasUnsavedChanges {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            saveChanges()
                        } label: {
                            // Saved Post save actions are always a checkmark only.
                            AgentIconView(.check, size: 16)
                                .frame(width: 24, height: 24)
                        }
                        .disabled(!canSaveChanges || isSavingChanges)
                        .accessibilityLabel("Save changes")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .agentSheetDragIndicator()
        .presentationBackground(Color.agentCanvas)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: source?.shapePayloadJSON)
        .task(id: analysisRequestID) {
            guard analysisRequestID != nil, let source else { return }
            await analyze(source)
        }
        .onChange(of: source?.shapePayloadJSON, initial: true) { _, _ in
            guard let result else { return }
            let latestDraft = InspirationEditableIdea(result: result)
            guard draft == nil || draft == draftBaseline else { return }
            draft = latestDraft
            draftBaseline = latestDraft
        }
        .onChange(of: source?.id, initial: true) { _, _ in
            guard let source, loadedSourceID != source.id else { return }
            let savedDraft = InspirationShapePersistenceCoordinator.manualDraft(for: source)
            manualDraft = savedDraft
            manualDraftBaseline = savedDraft
            loadedSourceID = source.id
        }
        .sheet(item: $filmingSchedule) { selection in
            InspirationFilmingScheduleView(source: selection.source, brief: selection.brief)
        }
        .confirmationDialog(
            "Delete saved post?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete saved post", role: .destructive) {
                guard let source else { return }
                deleteSavedPost(source)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved reference. Any post idea you created from it will stay in your Idea Bank.")
        }
        .alert("Save changes before closing?", isPresented: $confirmsUnsavedClose) {
            Button("Save changes") {
                saveChanges(dismissAfterSave: true)
            }
            .disabled(!canSaveChanges)
            Button("Discard changes", role: .destructive, action: dismiss.callAsFunction)
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your updates to this saved post have not been saved yet.")
        }
    }

    private var navigationTitle: String {
        if linkedBrief != nil { return "Saved to agent.cy" }
        if source?.saveMode == .originalOnly, result != nil { return "Saved post" }
        if result != nil { return "Review your post" }
        return isAnalyzing ? "Analyzing post" : "Save inspiration"
    }

    private func analysisContent(_ source: InspirationSource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                sourceActionGroup(source)

                manualIdeaCard(source)
                deleteSavedPostButton
            }
            .padding(AgentLayout.pageMargin)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.agentCanvas)
        .accessibilityElement(children: .contain)
    }

    private func failureContent(_ source: InspirationSource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                sourceActionGroup(source)
                failureCallout(source)
                manualIdeaCard(source)
                deleteSavedPostButton
            }
            .padding(AgentLayout.pageMargin)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.agentCanvas)
    }

    private func failureCallout(_ source: InspirationSource) -> some View {
        let presentation = InspirationReviewFailurePresentation.resolve(
            errorCode: source.lastErrorCode
        )
        return HStack(alignment: .top, spacing: AgentSpacing.x3) {
            CyAsterisk(color: .cyAccent, size: 15, strokeWidth: 1.8)
                .frame(width: 32, height: 32)
                .background(Color.cyAccent.opacity(0.08), in: .circle)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(presentation.title)
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                Text(presentation.message)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
        .accessibilityElement(children: .combine)
    }

    private func resultContent(
        source: InspirationSource,
        result: InspirationShapeResultWire,
        brief: CreativeBrief?
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                sourceActionGroup(source)

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    SectionRuleHeader(title: "From the post")
                    Text(result.sourceSummary)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentText)

                    Text("KEY POINTS")
                        .font(.agentMetadata)
                        .tracking(1.2)
                        .foregroundStyle(Color.agentSecondary)
                    ForEach(Array(result.keyPoints.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: AgentSpacing.x3) {
                            Text("\(index + 1)")
                                .font(.agentMetadata)
                                .foregroundStyle(Color.agentSecondary)
                                .frame(width: 18, height: 22)
                            Text(point)
                                .font(.agentBody)
                                .foregroundStyle(Color.agentText)
                        }
                    }

                    Divider()

                    if source.saveMode != .originalOnly || brief != nil {
                        CyCallout(heading: .suggestedForYou) {
                            if isEditing, brief == nil {
                                editableIdeaFields
                            } else if let draft {
                                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                    resultRow("Title", draft.title)
                                    pillarRow
                                    resultRow("Premise", draft.premise)
                                    resultRow("Spoken hook", draft.spokenHook)
                                    resultRow("Takeaway", draft.takeaway)
                                    resultRow("Film it", draft.filmingApproach)
                                }
                            }

                            if brief == nil {
                                Button {
                                    if isEditing {
                                        draft = draftBaseline
                                        isEditing = false
                                    } else {
                                        isEditing = true
                                    }
                                } label: {
                                    Text(isEditing ? "Cancel editing" : "Edit saved take")
                                }
                                .buttonStyle(AgentSecondaryButtonStyle())
                            }
                        }
                    }
                }
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel)

                if let brief {
                    Button("View post") {
                        appModel.openIdea(brief, developsPost: true, context: context)
                    }
                    .buttonStyle(AgentCyPrimaryButtonStyle())
                    .contentTransition(.opacity)

                    Button("Schedule filming") {
                        filmingSchedule = InspirationFilmingScheduleSelection(source: source, brief: brief)
                    }
                        .buttonStyle(AgentSecondaryButtonStyle())
                } else if source.saveMode != .originalOnly {
                    Button("Create post from this") {
                        saveIdea(source: source, result: result)
                    }
                    .buttonStyle(AgentCyPrimaryButtonStyle())
                    .disabled(draft?.isValid != true)
                    .contentTransition(.opacity)
                }

                if brief == nil, manualDraft.hasContent {
                    manualIdeaCard(source)
                }

                Button("Done", action: requestClose)
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)

                deleteSavedPostButton
            }
            .padding(AgentLayout.pageMargin)
        }
        .background(Color.agentCanvas)
    }

    private func sourceActionGroup(_ source: InspirationSource) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            sourceCard(source)
            if analysisAction != .hidden {
                analysisInlineControl(source)
            }
        }
    }

    private func analysisInlineControl(_ source: InspirationSource) -> some View {
        Button {
            guard analysisAction != .processing else { return }
            manualFocus = nil
            guard preserveManualDraftBeforeAnalysis(source) else { return }
            analysisRequestID = UUID()
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                CyAnalysisToolbarMark(isProcessing: analysisAction == .processing)
                    .frame(width: 36, height: 36)
                    .background(Color.cyAccent.opacity(0.10), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysisAction.title ?? "Analyze with Cy")
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                    if let detail = analysisAction.detail {
                        Text(detail)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if analysisAction != .processing {
                    AgentIconView(.arrowRight, size: 14)
                        .foregroundStyle(Color.cyAccent)
                }
            }
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.panel)
                .stroke(Color.cyAccent.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.cyAccent.opacity(0.08), radius: 14, y: 5)
        .disabled(analysisAction == .processing)
        .accessibilityLabel(analysisAction.accessibilityLabel)
    }

    private func manualIdeaCard(_ source: InspirationSource) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Create your own idea")
            Text("Use the post as your reference and write the direction yourself. Cy won’t analyze or rewrite anything here.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)

            manualEditableField(
                "Title",
                placeholder: "Give this idea a working title",
                text: manualDraftBinding(\.title, limit: 160),
                focus: .title,
                singleLine: true,
                limit: 160
            )
            manualPillarPicker
            manualEditableField(
                "Your take",
                placeholder: "What do you want to say about it?",
                text: manualDraftBinding(\.premise),
                focus: .premise
            )
            manualEditableField(
                "Hook",
                placeholder: "How could you open?",
                text: manualDraftBinding(\.spokenHook),
                focus: .spokenHook
            )
            manualEditableField(
                "Takeaway",
                placeholder: "What should people leave with?",
                text: manualDraftBinding(\.takeaway),
                focus: .takeaway
            )
            manualEditableField(
                "Film it",
                placeholder: "How do you want to capture it?",
                text: manualDraftBinding(\.filmingApproach),
                focus: .filmingApproach
            )

            Text("Only the title is required. You can keep developing everything in the post editor.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)

            Button("Create post from this idea") {
                manualFocus = nil
                _ = appModel.saveManualInspirationIdea(
                    source: source,
                    draft: manualDraft,
                    context: context
                )
            }
            .buttonStyle(AgentPrimaryButtonStyle())
            .disabled(!manualDraft.isValid)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
        .accessibilityElement(children: .contain)
        .disabled(isAnalyzing)
    }

    private func manualBriefContent(
        source: InspirationSource,
        brief: CreativeBrief
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                sourceActionGroup(source)

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    SectionRuleHeader(title: "Your idea")
                    resultRow("Title", brief.title)
                    if let pillar = pillars.first(where: { $0.id == brief.pillarID }) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                            Text("PILLAR")
                                .font(.agentMetadata)
                                .foregroundStyle(Color.agentSecondary)
                            HStack(spacing: AgentSpacing.x2) {
                                PillarColorMark(
                                    color: Color(agentHex: pillar.resolvedColorHex(in: pillars)),
                                    diameter: 12
                                )
                                Text(pillar.name)
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentText)
                            }
                        }
                    }
                    manualBriefRow("Your take", brief.premise)
                    manualBriefRow("Hook", brief.spokenHook)
                    manualBriefRow("Takeaway", brief.takeaway)
                    manualBriefRow("Film it", brief.filmingGuidance)
                }
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel)

                Button("View post") {
                    appModel.openIdea(brief, developsPost: true, context: context)
                }
                .buttonStyle(AgentPrimaryButtonStyle())

                Button("Schedule filming") {
                    filmingSchedule = InspirationFilmingScheduleSelection(source: source, brief: brief)
                }
                    .buttonStyle(AgentSecondaryButtonStyle())

                Button("Done", action: requestClose)
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)

                deleteSavedPostButton
            }
            .padding(AgentLayout.pageMargin)
        }
        .background(Color.agentCanvas)
    }

    private var deleteSavedPostButton: some View {
        Button(role: .destructive) {
            manualFocus = nil
            confirmsDeletion = true
        } label: {
            AgentIconLabel(title: "Delete saved post", icon: .trash)
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentDestructive)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isAnalyzing || isSavingChanges)
        .accessibilityHint("Removes the saved reference after confirmation")
    }

    private func deleteSavedPost(_ source: InspirationSource) {
        if appModel.deleteInspiration(source, context: context) {
            dismiss()
        }
    }

    @ViewBuilder
    private func manualBriefRow(_ label: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resultRow(label, value)
        }
    }

    private func manualEditableField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        focus: ManualIdeaFocusField,
        singleLine: Bool = false,
        limit: Int = 2_000
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                Spacer(minLength: AgentSpacing.x2)
                // The binding silently truncates at the limit; the counter is
                // the only signal, so it appears once the limit is near.
                if text.wrappedValue.count >= Int(Double(limit) * 0.8) {
                    Text("\(text.wrappedValue.count)/\(limit)")
                        .font(.agentMetadata)
                        .monospacedDigit()
                        .foregroundStyle(
                            text.wrappedValue.count >= limit ? Color.agentDestructive : Color.agentSecondary
                        )
                }
            }
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(singleLine ? 1...3 : 2...8)
                .font(.agentBody)
                .accessibilityLabel(label)
                .focused($manualFocus, equals: focus)
                .submitLabel(singleLine ? .next : .return)
                .onSubmit {
                    if focus == .title { manualFocus = .premise }
                }
        }
        .padding(AgentSpacing.x3)
        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

    private func manualDraftBinding(
        _ keyPath: WritableKeyPath<ManualInspirationIdeaDraft, String>,
        limit: Int = 2_000
    ) -> Binding<String> {
        Binding(
            get: { manualDraft[keyPath: keyPath] },
            set: { value in
                manualDraft[keyPath: keyPath] = String(value.prefix(limit))
            }
        )
    }

    private var selectedManualPillar: Pillar? {
        guard let pillarID = manualDraft.pillarID else { return nil }
        return pillars.first { $0.id == pillarID }
    }

    private var manualPillarPicker: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            Text("PILLAR")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
            Menu {
                Button("No pillar") { manualDraft.pillarID = nil }
                ForEach(pillars) { pillar in
                    Button { manualDraft.pillarID = pillar.id } label: {
                        PillarMenuChoiceLabel(
                            title: pillar.name,
                            colorHex: pillar.resolvedColorHex(in: pillars),
                            isSelected: manualDraft.pillarID == pillar.id
                        )
                    }
                }
            } label: {
                HStack(spacing: AgentSpacing.x2) {
                    if let selectedManualPillar {
                        PillarColorMark(
                            color: Color(agentHex: selectedManualPillar.resolvedColorHex(in: pillars)),
                            diameter: 12
                        )
                        Text(selectedManualPillar.name)
                    } else {
                        Text("No pillar")
                    }
                    Spacer()
                    AgentIconView(.expand, size: 14)
                        .foregroundStyle(Color.agentSecondary)
                }
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x3)
                .frame(minHeight: 46)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 0.75)
                }
            }
            .accessibilityLabel("Pillar")
            .accessibilityValue(selectedManualPillar?.name ?? "No pillar")
        }
    }

    private var editableIdeaFields: some View {
        Group {
            editableField("Title", text: draftBinding(\.title), singleLine: true)
            pillarPicker
            editableField("Premise", text: draftBinding(\.premise))
            editableField("Audience", text: draftBinding(\.audience))
            editableField("Spoken hook", text: draftBinding(\.spokenHook))
            editableField("First frame", text: draftBinding(\.firstFrameText))
            editableField("Takeaway", text: draftBinding(\.takeaway))
            editableField("Film it", text: draftBinding(\.filmingApproach))
        }
    }

    private func editableField(
        _ label: String,
        text: Binding<String>,
        singleLine: Bool = false,
        limit: Int = 2_000
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                Spacer(minLength: AgentSpacing.x2)
                if text.wrappedValue.count >= Int(Double(limit) * 0.8) {
                    Text("\(text.wrappedValue.count)/\(limit)")
                        .font(.agentMetadata)
                        .monospacedDigit()
                        .foregroundStyle(
                            text.wrappedValue.count >= limit ? Color.agentDestructive : Color.agentSecondary
                        )
                }
            }
            if singleLine {
                TextField(label, text: text, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.agentBody)
            } else {
                TextField(label, text: text, axis: .vertical)
                    .lineLimit(2...8)
                    .font(.agentBody)
            }
        }
        .padding(AgentSpacing.x3)
        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

    private func draftBinding(_ keyPath: WritableKeyPath<InspirationEditableIdea, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var current = draft else { return }
                current[keyPath: keyPath] = String(value.prefix(2_000))
                draft = current
            }
        )
    }

    private var pillarPicker: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            Text("PILLAR")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
            Menu {
                Button("No pillar") { updateDraftPillar(nil) }
                ForEach(pillars) { pillar in
                    Button { updateDraftPillar(pillar.id) } label: {
                        PillarMenuChoiceLabel(
                            title: pillar.name,
                            colorHex: pillar.resolvedColorHex(in: pillars),
                            isSelected: draft?.pillarID == pillar.id
                        )
                    }
                }
            } label: {
                HStack(spacing: AgentSpacing.x2) {
                    if let selectedPillar {
                        PillarColorMark(
                            color: Color(agentHex: selectedPillar.resolvedColorHex(in: pillars)),
                            diameter: 12
                        )
                        Text(selectedPillar.name)
                    } else {
                        Text("No pillar")
                    }
                    Spacer()
                    AgentIconView(.expand, size: 14)
                        .foregroundStyle(Color.agentSecondary)
                }
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x3)
                .frame(minHeight: 46)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 0.75)
                }
            }
            .accessibilityLabel("Pillar")
            .accessibilityValue(selectedPillar?.name ?? "No pillar")
        }
    }

    @ViewBuilder
    private var pillarRow: some View {
        if let selectedPillar {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text("PILLAR")
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                HStack(spacing: AgentSpacing.x2) {
                    PillarColorMark(
                        color: Color(agentHex: selectedPillar.resolvedColorHex(in: pillars)),
                        diameter: 12
                    )
                    Text(selectedPillar.name)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentText)
                }
            }
        }
    }

    private func sourceCard(_ source: InspirationSource) -> some View {
        Button {
            if let url = URL(string: source.canonicalURLString) { openURL(url) }
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                thumbnail(source)
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(source.sourceTitle.isEmpty ? platformTitle(source.platform) : source.sourceTitle)
                        .font(.agentHeadline)
                        .foregroundStyle(Color.agentText)
                        .lineLimit(2)
                    Text("\(platformTitle(source.platform)) · Open original post")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AgentIconView(.external, size: 14)
                    .foregroundStyle(Color.agentSecondary)
            }
            .padding(AgentSpacing.x3)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open original post in \(platformTitle(source.platform))")
    }

    @ViewBuilder
    private func thumbnail(_ source: InspirationSource) -> some View {
        if let data = source.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 84)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 0.75)
                }
        } else {
            AgentIconView(.link, size: 18)
                .foregroundStyle(Color.actionAccent)
                .frame(width: 68, height: 84)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 0.75)
                }
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            Text(label.uppercased())
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
            Text(value)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
        }
    }

    private func analyze(_ source: InspirationSource) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        _ = await appModel.analyzeInspiration(source, context: context)
    }

    private var hasUnsavedChanges: Bool {
        InspirationReviewUnsavedWorkPolicy.hasChanges(
            hasLinkedBrief: linkedBrief != nil,
            generatedDraftChanged: result != nil && draft != draftBaseline,
            manualDraft: manualDraft,
            manualDraftBaseline: manualDraftBaseline
        )
    }

    private var canSaveChanges: Bool {
        if result != nil {
            return draft?.isValid == true
        }
        return true
    }

    private func requestClose() {
        manualFocus = nil
        if hasUnsavedChanges {
            confirmsUnsavedClose = true
        } else {
            dismiss()
        }
    }

    private func saveChanges(dismissAfterSave: Bool = false) {
        guard let source, hasUnsavedChanges, canSaveChanges else { return }
        manualFocus = nil
        isSavingChanges = true
        var didSave = false

        var didSaveAllChanges = true

        if let result, let draft, draft != draftBaseline,
           let savedResult = appModel.saveInspirationEdits(
               source: source,
               result: result,
               draft: draft,
               context: context
           ) {
            let savedDraft = InspirationEditableIdea(result: savedResult)
            self.draft = savedDraft
            draftBaseline = savedDraft
            isEditing = false
            didSave = true
        } else if result != nil, draft != draftBaseline {
            didSaveAllChanges = false
        }

        if manualDraft != manualDraftBaseline,
           let savedDraft = appModel.saveManualInspirationDraft(
                      source: source,
                      draft: manualDraft,
                      context: context
           ) {
            manualDraft = savedDraft
            manualDraftBaseline = savedDraft
            didSave = true
        } else if manualDraft != manualDraftBaseline {
            didSaveAllChanges = false
        }

        isSavingChanges = false
        if didSave, didSaveAllChanges, dismissAfterSave {
            dismiss()
        }
    }

    private func preserveManualDraftBeforeAnalysis(_ source: InspirationSource) -> Bool {
        guard manualDraft != manualDraftBaseline else { return true }
        guard let savedDraft = appModel.saveManualInspirationDraft(
            source: source,
            draft: manualDraft,
            context: context
        ) else { return false }
        manualDraft = savedDraft
        manualDraftBaseline = savedDraft
        return true
    }

    private func saveIdea(source: InspirationSource, result: InspirationShapeResultWire) {
        guard let draft else { return }
        _ = appModel.saveInspirationIdea(
            source: source,
            result: result,
            draft: draft,
            context: context
        )
    }

    private func updateDraftPillar(_ pillarID: UUID?) {
        guard var current = draft else { return }
        current.pillarID = pillarID
        draft = current
    }

    private func platformTitle(_ platform: InspirationPlatform) -> String {
        switch platform {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .threads: "Threads"
        case .web: "Web"
        }
    }
}

private struct InspirationFilmingScheduleSelection: Identifiable {
    let source: InspirationSource
    let brief: CreativeBrief

    var id: UUID { brief.id }
}

private struct InspirationFilmingScheduleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let source: InspirationSource
    let brief: CreativeBrief
    @State private var date: Date
    @State private var includesTime: Bool

    init(source: InspirationSource, brief: CreativeBrief) {
        self.source = source
        self.brief = brief
        _date = State(initialValue: brief.workDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        _includesTime = State(initialValue: brief.includesWorkTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filming date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Add a time", isOn: $includesTime)
                    if includesTime {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Button("Add to schedule") {
                        if appModel.scheduleInspirationFilming(
                            source: source,
                            brief: brief,
                            date: date,
                            includesTime: includesTime,
                            context: context
                        ) {
                            dismiss()
                        }
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.agentCanvas)
            .navigationTitle("Schedule filming")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .agentSheetDragIndicator()
    }
}
