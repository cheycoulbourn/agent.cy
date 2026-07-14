import SwiftData
import SwiftUI

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
        case .brief:
            BriefDetailView(brief: brief)
        }
    }
}

enum PostOutputDetailPolicy {
    enum Destination: Equatable {
        case draftEditor
        case finalizedPost
        case brief
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
        return .brief
    }

    static func usesFinalizedView(
        outputStatus: PlatformOutputStatus,
        targetDate: Date?
    ) -> Bool {
        if outputStatus == .scheduled || outputStatus == .posted { return true }
        return outputStatus == .ready && targetDate != nil
    }
}

struct ScheduledPostDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var brief: CreativeBrief
    @Bindable var output: PlatformOutput
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query private var tasks: [CreatorTask]
    @State private var showEditor = false
    @State private var confirmArchive = false

    private struct DisplayField: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    init(brief: CreativeBrief, output: PlatformOutput) {
        self.brief = brief
        self.output = output
        let briefID = brief.id
        _tasks = Query(
            filter: #Predicate<CreatorTask> { $0.briefID == briefID },
            sort: \CreatorTask.sortOrder
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                postHeader
                scheduleSurface
                postContent
                taskSection
                postingAction
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(output.status == .posted ? "Posted post" : "Scheduled post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") {
                        showEditor = true
                    }
                    Button(
                        output.status == .posted ? "Mark not posted" : "Mark posted",
                        systemImage: output.status == .posted ? "arrow.uturn.backward" : "checkmark"
                    ) {
                        appModel.togglePosted(output: output, context: context)
                    }
                    Divider()
                    Button("Archive", systemImage: "archivebox", role: .destructive) {
                        confirmArchive = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Post options")
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                ScrollView {
                    ResumablePostEditorView(brief: brief, output: output, onSpark: {})
                        .taskNavigationDestinations()
                        .padding(.horizontal, AgentLayout.pageMargin)
                        .padding(.top, AgentSpacing.x4)
                        .padding(.bottom, 80)
                }
                .navigationTitle("Edit post")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { showEditor = false }
                            .labelStyle(.iconOnly)
                    }
                }
                .agentScreen()
                .agentKeyboardDismissal()
            }
        }
        .confirmationDialog("Archive this post?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                appModel.archive(brief, context: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still find it in Your work.")
        }
        .agentScreen()
    }

    private var postHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(spacing: AgentSpacing.x2) {
                Circle()
                    .fill(pillarColor)
                    .frame(width: 7, height: 7)
                Text(pillarName.uppercased())
                    .font(.agentMono)
                    .tracking(0.7)
                Spacer()
                Text(statusTitle)
                    .font(.agentMono)
                    .tracking(0.6)
                    .padding(.horizontal, AgentSpacing.x2)
                    .frame(minHeight: 24)
                    .background(output.status == .posted ? Color.actionAccent : Color.clear, in: .rect(cornerRadius: 6))
                    .foregroundStyle(output.status == .posted ? Color.onAccent : Color.agentText)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(output.status == .posted ? Color.clear : Color.agentText.opacity(0.20), lineWidth: 1)
                    }
            }

            Text(displayTitle)
                .font(.paperInter(size: 32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.64)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.isEmpty {
                Text(summary)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scheduleSurface: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Posting details")
            detailRow(label: "Date", value: scheduleDateText)
            detailRow(label: "Platform", value: platformLabel)
            detailRow(label: "Duration", value: durationLabel)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x4)
        .background(pillarColor.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var postContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Post")
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
    private var taskSection: some View {
        if !topLevelTasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(
                    title: "Tasks",
                    trailing: "\(completedTaskCount) of \(topLevelTasks.count) complete"
                )
                ForEach(topLevelTasks) { task in
                    TaskRow(task: task, allTasks: tasks)
                        .padding(.vertical, AgentSpacing.x2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.agentHairline).frame(height: 1)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var postingAction: some View {
        if output.status == .posted {
            Button("Mark not posted") {
                appModel.togglePosted(output: output, context: context)
            }
            .buttonStyle(AgentSecondaryButtonStyle())
        } else {
            Button("Mark posted") {
                appModel.togglePosted(output: output, context: context)
            }
            .buttonStyle(AgentPrimaryButtonStyle())
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x4) {
            MetaLabel(label)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.agentBody.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
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
    private var completedTaskCount: Int { topLevelTasks.filter(\.isCompleted).count }
    private var displayTitle: String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }
    private var summary: String {
        let notes = brief.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { return notes }
        return brief.premise.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var statusTitle: String { output.status == .posted ? "POSTED" : "SCHEDULED" }
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
        let duration = output.durationSeconds
        return duration < 120 ? "\(duration) seconds" : "\(duration / 60) minutes"
    }
    private var contentFields: [DisplayField] {
        [
            ("Hook", brief.spokenHook),
            ("Caption", output.caption),
            ("Script", brief.scriptBeatsText),
            ("Ending", brief.close),
            ("Call to action", output.cta.isEmpty ? brief.ctaIntent : output.cta),
            ("Edit notes", output.editChanges)
        ].compactMap { label, rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : DisplayField(label: label, value: value)
        }
    }
}
