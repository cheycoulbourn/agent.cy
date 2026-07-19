import SwiftData
import SwiftUI

struct AgendaPostIdeaPickerView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    let day: Date

    @State private var editorRoute: AgendaPostEditorRoute?

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var activePillarIDs: Set<UUID> { Set(activePillars.map(\.id)) }
    private var ideas: [CreativeBrief] {
        briefs.filter { brief in
            let isFiledHere = brief.pillarID.map(activePillarIDs.contains) ?? true
            return isFiledHere && (brief.status == .spark || brief.status == .developing)
        }
    }
    private var plannedDate: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    title: "Schedule a post.",
                    subtitle: "Start a new post for this day or choose a saved idea."
                )

                AgentInsetSurface {
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: startNewPost) {
                            HStack(spacing: AgentSpacing.x3) {
                                AgentIconView(.add, size: 16)
                                    .frame(width: 22, height: 22)

                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text("New post")
                                        .font(.paperInter(size: 19, weight: .semibold, relativeTo: .headline))
                                        .tracking(-0.3)
                                    Text("Open a clean post draft for this day.")
                                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                                        .foregroundStyle(Color.agentSecondary)
                                }

                                Spacer(minLength: AgentSpacing.x2)
                                AgentIconView(.arrowRight, size: 13)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens a new post editor for the selected day")

                        SectionRuleHeader(title: "Idea Bank", trailing: "\(ideas.count)")
                            .padding(.top, AgentSpacing.x4)

                        if ideas.isEmpty {
                            Text("No saved ideas yet. Start a new post above.")
                                .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                                .foregroundStyle(Color.agentSecondary)
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                        } else {
                            ForEach(Array(ideas.enumerated()), id: \.element.id) { index, brief in
                                Button {
                                    openIdea(brief)
                                } label: {
                                    AgendaIdeaBankRow(
                                        brief: brief,
                                        pillar: activePillars.first { $0.id == brief.pillarID },
                                        showsDivider: index < ideas.count - 1
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this idea in the post editor for the selected day")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, 130)
        }
        .navigationTitle("Schedule post")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editorRoute) { route in
            AgendaPostEditorDestination(route: route)
        }
        .agentScreen()
    }

    private func startNewPost() {
        editorRoute = .new(date: plannedDate)
    }

    private func openIdea(_ brief: CreativeBrief) {
        editorRoute = .idea(briefID: brief.id, suggestedDate: plannedDate)
    }
}

private enum AgendaPostEditorRoute: Hashable, Identifiable {
    case new(date: Date)
    case idea(briefID: UUID, suggestedDate: Date)

    var id: String {
        switch self {
        case .new(let date):
            "new-\(date.timeIntervalSinceReferenceDate)"
        case .idea(let briefID, let date):
            "idea-\(briefID.uuidString)-\(date.timeIntervalSinceReferenceDate)"
        }
    }
}

private struct AgendaPostEditorDestination: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var profiles: [CreatorProfile]
    @Query private var allBriefs: [CreativeBrief]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    let route: AgendaPostEditorRoute

    @State private var newBrief: CreativeBrief?
    @State private var newOutput: PlatformOutput?
    @State private var hasPreparedNewDraft = false
    @State private var creationFailed = false

    private var briefs: [CreativeBrief] {
        allBriefs.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    var body: some View {
        Group {
            switch route {
            case .idea(let briefID, let suggestedDate):
                if let brief = briefs.first(where: { $0.id == briefID }) {
                    IdeaPostDraftView(brief: brief, suggestedTargetDate: suggestedDate)
                } else {
                    unavailableState("Post not found. It may have been moved or deleted.")
                }
            case .new:
                if let newBrief, let newOutput {
                    ResumablePostEditorView(
                        brief: newBrief,
                        output: newOutput,
                        onSpark: {
                            appModel.notice = .info("Save this draft, then open Cy when you're ready to build it out.")
                        }
                    )
                } else if creationFailed {
                    unavailableState("This post draft could not be started.")
                } else {
                    ProgressView("Opening your draft…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            guard case .new(let date) = route, !hasPreparedNewDraft else { return }
            hasPreparedNewDraft = true
            await Task.yield()
            prepareNewDraft(for: date)
        }
        .agentScreen()
    }

    @ViewBuilder
    private func unavailableState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            Text(message)
                .font(.agentHeadline)
            Text("Go back and choose another idea.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        .padding(AgentLayout.pageMargin)
    }

    private func prepareNewDraft(for date: Date) {
        let platform = profiles.first?.selectedPlatforms.first ?? .instagramReels
        let catalog = PublishingCatalog.identifiers(for: platform)
        guard let draft = appModel.beginPostDraft(
            pillarID: nil,
            platform: platform,
            destinationID: catalog.destination,
            formatID: catalog.format,
            durationSeconds: platform.format.defaultDuration,
            targetDate: date,
            context: context
        ) else {
            creationFailed = true
            return
        }
        newBrief = draft.brief
        newOutput = draft.output
    }
}

private struct AgendaIdeaBankRow: View {
    let brief: CreativeBrief
    let pillar: Pillar?
    let showsDivider: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x3) {
            Circle()
                .fill(pillar.map { Color(agentHex: $0.colorHex) } ?? Color.agentSecondary)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(brief.title.isEmpty ? "Untitled idea" : brief.title)
                    .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                    .tracking(-0.25)
                    .lineLimit(2)

                HStack(spacing: AgentSpacing.x2) {
                    AgendaPickerMeta(pillar?.name ?? "No pillar")
                    Circle().fill(Color.agentSecondary).frame(width: 3, height: 3)
                    AgendaPickerMeta(brief.updatedAt.formatted(.relative(presentation: .named)))
                }
            }

            Spacer(minLength: AgentSpacing.x2)
            AgentIconView(.forward, size: 11)
                .foregroundStyle(Color.agentSecondary)
        }
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
        }
        .contentShape(.rect)
    }
}

private struct AgendaPickerMeta: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
            .tracking(1)
            .foregroundStyle(Color.agentSecondary)
            .lineLimit(1)
    }
}
