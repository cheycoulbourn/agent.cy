import SwiftData
import SwiftUI

struct AgendaPostIdeaPickerProjection {
    let ideas: [CreativeBrief]
    let activePillarByID: [UUID: Pillar]

    static func make(
        briefs: [CreativeBrief],
        pillars: [Pillar],
        preferredWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace],
        query: String
    ) -> AgendaPostIdeaPickerProjection {
        let resolvedWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        )
        let defaultWorkspaceID = WorkspaceScope.defaultWorkspace(in: workspaces)?.id
        let includesWorkspace: (UUID?) -> Bool = { recordWorkspaceID in
            guard let resolvedWorkspaceID else { return recordWorkspaceID == nil }
            if let recordWorkspaceID { return recordWorkspaceID == resolvedWorkspaceID }
            return defaultWorkspaceID == resolvedWorkspaceID
        }

        let scopedPillars = pillars.filter { includesWorkspace($0.workspaceID) }
        let activePillarByID = DuplicateSafeIndex.firstValues(
            scopedPillars.filter { !$0.isArchived }.map { ($0.id, $0) }
        )
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ideas = briefs.filter { brief in
            guard includesWorkspace(brief.workspaceID),
                  IdeaBankPlacementPolicy.includes(brief) else {
                return false
            }
            guard !cleanQuery.isEmpty else { return true }
            let searchText = [
                brief.title,
                brief.premise,
                brief.notes,
                brief.spokenHook,
                brief.scriptBeatsText,
                brief.ctaIntent,
                brief.pillarID.flatMap { activePillarByID[$0]?.name } ?? ""
            ].joined(separator: " ")
            return searchText.localizedStandardContains(cleanQuery)
        }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        return AgendaPostIdeaPickerProjection(
            ideas: ideas,
            activePillarByID: activePillarByID
        )
    }
}

enum AgendaPostIdeaPickerDatePolicy {
    static func plannedDate(
        for day: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}

struct AgendaPostIdeaPickerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    let day: Date

    @State private var editorRoute: AgendaPostEditorRoute?
    @State private var query = ""
    @State private var didApplyPreviewEditorRoute = false

    private var plannedDate: Date {
        AgendaPostIdeaPickerDatePolicy.plannedDate(for: day)
    }

    var body: some View {
        let projection = AgendaPostIdeaPickerProjection.make(
            briefs: allBriefs,
            pillars: allPillars,
            preferredWorkspaceID: appModel.activeWorkspaceID,
            workspaces: workspaces,
            query: query
        )
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(spacing: 0) {
#if targetEnvironment(macCatalyst)
            desktopNavigationHeader
#endif

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        title: "Schedule a post.",
                        subtitle: "Start a new post for this day or choose a saved idea."
                    )

                    AgentInsetSurface(role: .structural) {
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

                            ideaSearchField
                                .padding(.top, AgentSpacing.x4)

                            SectionRuleHeader(
                                title: cleanQuery.isEmpty ? "Idea Bank" : "Results",
                                trailing: "\(projection.ideas.count)"
                            )
                                .padding(.top, AgentSpacing.x4)

                            if projection.ideas.isEmpty {
                                Text(cleanQuery.isEmpty
                                    ? "No saved ideas yet. Start a new post above."
                                    : "No ideas found. Try another title, pillar, or phrase.")
                                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                                    .foregroundStyle(Color.agentSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                            } else {
                                ForEach(projection.ideas) { brief in
                                    Button {
                                        openIdea(brief)
                                    } label: {
                                        AgendaIdeaBankRow(
                                            brief: brief,
                                            pillar: brief.pillarID.flatMap { projection.activePillarByID[$0] },
                                            showsDivider: brief.id != projection.ideas.last?.id
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
                .agentBottomNavigationClearance(additional: AgentSpacing.x3)
            }
        }
#if targetEnvironment(macCatalyst)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
#else
        .navigationTitle("Schedule post")
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationDestination(item: $editorRoute) { route in
            AgendaPostEditorDestination(route: route)
        }
        .agentScreen()
        #if DEBUG
        .task {
            guard !didApplyPreviewEditorRoute else { return }
            didApplyPreviewEditorRoute = true
            switch PreviewAgendaRuntimeFixture.schedulePostEditorRoute() {
            case .newPost:
                startNewPost()
            case .firstIdea:
                if let idea = projection.ideas.first { openIdea(idea) }
            case nil:
                break
            }
        }
        #endif
    }

    private var ideaSearchField: some View {
        HStack(spacing: AgentSpacing.x3) {
            AgentIconView(.search, size: 15)
                .foregroundStyle(Color.agentSecondary)
            TextField("Search saved ideas", text: $query)
                .font(.agentBody)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    AgentIconView(.close)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear idea search")
            }
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 48)
        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

#if targetEnvironment(macCatalyst)
    private var desktopNavigationHeader: some View {
        AgentDesktopDetailRail(title: "Schedule post", backAction: dismiss.callAsFunction) {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }
#endif

    private func startNewPost() {
        let platform = profiles.first?.selectedPlatforms.first ?? .instagramReels
        let catalog = PublishingCatalog.identifiers(for: platform)
        guard let draft = appModel.beginPostDraft(
            pillarID: nil,
            platform: platform,
            destinationID: catalog.destination,
            formatID: catalog.format,
            durationSeconds: platform.format.defaultDuration,
            targetDate: plannedDate,
            context: context
        ) else { return }

        editorRoute = .draft(
            briefID: draft.brief.id,
            outputID: draft.output.id
        )
    }

    private func openIdea(_ brief: CreativeBrief) {
        editorRoute = .idea(briefID: brief.id, suggestedDate: plannedDate)
    }
}

private enum AgendaPostEditorRoute: Hashable, Identifiable {
    case draft(briefID: UUID, outputID: UUID)
    case idea(briefID: UUID, suggestedDate: Date)

    var id: String {
        switch self {
        case .draft(let briefID, let outputID):
            "draft-\(briefID.uuidString)-\(outputID.uuidString)"
        case .idea(let briefID, let date):
            "idea-\(briefID.uuidString)-\(date.timeIntervalSinceReferenceDate)"
        }
    }
}

private struct AgendaPostEditorDestination: View {
    @Environment(AppModel.self) private var appModel
    @Query private var allBriefs: [CreativeBrief]
    @Query private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    let route: AgendaPostEditorRoute

    private var briefs: [CreativeBrief] {
        allBriefs.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    private var outputs: [PlatformOutput] {
        allOutputs.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    var body: some View {
        Group {
            switch route {
            case .idea(let briefID, let suggestedDate):
                if let brief = briefs.first(where: { $0.id == briefID }) {
                    IdeaPostDraftView(
                        brief: brief,
                        suggestedTargetDate: suggestedDate,
                        isAlreadyInIdeaBank: true
                    )
                } else {
                    unavailableState("Post not found. It may have been moved or deleted.")
                }
            case .draft(let briefID, let outputID):
                if let newBrief = briefs.first(where: { $0.id == briefID }),
                   let newOutput = outputs.first(where: { $0.id == outputID }) {
                    ResumablePostEditorView(
                        brief: newBrief,
                        output: newOutput,
                        onSpark: {
                            appModel.notice = .info("Save this draft, then open Cy when you're ready to build it out.")
                        }
                    )
                } else {
                    unavailableState("This post draft could not be opened.")
                }
            }
        }
        .navigationTitle("New post")
        .navigationBarTitleDisplayMode(.inline)
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
            .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
            .tracking(1)
            .foregroundStyle(Color.agentSecondary)
            .lineLimit(1)
    }
}
