import SwiftData
import SwiftUI

private enum IdeaBankFilter: Hashable {
    case all
    case unfiled
    case archived
    case pillar(UUID)
}

struct IdeaBankView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var headerHeight: CGFloat = 0
    @State private var search = ""
    @State private var selectedFilter: IdeaBankFilter = .all
    @State private var isFilterPresented = false
    @State private var selectedIdea: CreativeBrief?

    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var pillars: [Pillar] { scoped(allPillars) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var ideas: [CreativeBrief] {
        briefs.filter { brief in
            let isIdea = brief.status == .spark || brief.status == .developing
            let matchesLifecycle = selectedFilter == .archived
                ? brief.status == .archived
                : isIdea
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matchesLifecycle, !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let matchesSearch = query.isEmpty
                || brief.title.localizedStandardContains(query)
                || brief.notes.localizedStandardContains(query)
                || pillar(for: brief)?.name.localizedStandardContains(query) == true
            return matchesSearch && matchesSelectedFilter(brief)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .reportAgentViewHeight()

                    AgentDashboardSurface(minimumHeight: max(0, proxy.size.height - headerHeight + 72)) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                            searchField
                            ideaList
                            saveIdeaButton
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedIdea) { brief in
            IdeaPostDraftView(brief: brief)
        }
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .agentDashboardScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: "Idea Bank",
                profile: profiles.first,
                openSettings: { appModel.presentedSheet = .settings }
            ) {
                filterMenu
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your")
                        .font(.system(size: 32, weight: .regular, design: .default))
                    Text("ideas.")
                        .font(.agentDisplay)
                }
                .tracking(-0.64)
                Text("Keep the thoughts worth returning to.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x8)
    }

    private var filterMenu: some View {
        Button {
            isFilterPresented.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.agentText)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isFilterPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            filterPopover
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(24)
        }
        .accessibilityLabel("Filter ideas")
        .accessibilityValue(selectedFilterTitle)
    }

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterChoice(title: "All ideas", filter: .all)
            filterChoice(title: "Unfiled", filter: .unfiled, isUnfiled: true)
            filterChoice(title: "Archived", filter: .archived)

            if !activePillars.isEmpty {
                Divider()
                    .padding(.horizontal, AgentSpacing.x4)
                ForEach(activePillars) { pillar in
                    filterChoice(
                        title: pillar.name,
                        filter: .pillar(pillar.id),
                        colorHex: pillar.resolvedColorHex(in: pillars)
                    )
                }
            }
        }
        .padding(.vertical, AgentSpacing.x2)
        .frame(width: 244)
    }

    private func filterChoice(
        title: String,
        filter: IdeaBankFilter,
        colorHex: String? = nil,
        isUnfiled: Bool = false
    ) -> some View {
        Button {
            selectedFilter = filter
            isFilterPresented = false
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                Group {
                    if let colorHex {
                        Circle()
                            .fill(Color(agentHex: colorHex))
                    } else if isUnfiled {
                        Circle()
                            .stroke(Color.agentSecondary, lineWidth: 1.25)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .frame(width: 14, height: 14)

                Text(title)
                    .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if selectedFilter == filter {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.agentText)
                }
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: AgentSpacing.x3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.agentSecondary)
            TextField("Search ideas", text: $search)
                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 48)
        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var ideaList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Idea Bank", trailing: "\(ideas.count)")

            if ideas.isEmpty {
                Text(emptyStateCopy)
                    .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            } else {
                ForEach(Array(ideas.enumerated()), id: \.element.id) { index, brief in
                    Button {
                        selectedIdea = brief
                    } label: {
                        IdeaBankRow(
                            brief: brief,
                            pillar: pillar(for: brief),
                            showsDivider: index < ideas.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this idea where you left off")
                }
            }
        }
    }

    private var saveIdeaButton: some View {
        Button(action: saveIdea) {
            HStack(spacing: AgentSpacing.x3) {
                Circle()
                    .stroke(Color.agentSecondary, style: StrokeStyle(lineWidth: 1.25, dash: [2, 2]))
                    .frame(width: 18, height: 18)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .medium))
                    }
                Text("Save an idea")
                    .font(.agentAddAction)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.agentText)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func saveIdea() {
        appModel.quickCapturePillarID = nil
        appModel.setQuickCaptureMode(.idea)
        appModel.presentedSheet = .quickCapture
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        guard let pillarID = brief.pillarID else { return nil }
        return activePillars.first { $0.id == pillarID }
    }

    private func matchesSelectedFilter(_ brief: CreativeBrief) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .unfiled:
            return pillar(for: brief) == nil
        case .archived:
            return true
        case .pillar(let pillarID):
            return brief.pillarID == pillarID
        }
    }

    private var selectedFilterTitle: String {
        switch selectedFilter {
        case .all:
            return "All ideas"
        case .unfiled:
            return "Unfiled"
        case .archived:
            return "Archived"
        case .pillar(let pillarID):
            return activePillars.first(where: { $0.id == pillarID })?.name ?? "Pillar"
        }
    }

    private var emptyStateCopy: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No ideas match this search."
        }
        switch selectedFilter {
        case .all:
            return "No ideas yet."
        case .unfiled:
            return "No unfiled ideas."
        case .archived:
            return "No archived work."
        case .pillar:
            return "No ideas saved under \(selectedFilterTitle)."
        }
    }
}

private struct IdeaBankRow: View {
    let brief: CreativeBrief
    let pillar: Pillar?
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            Text(brief.title)
                .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                .tracking(-0.2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AgentSpacing.x2) {
                Circle()
                    .fill(pillar.map { Color(agentHex: $0.colorHex) } ?? Color.clear)
                    .overlay {
                        if pillar == nil {
                            Circle().stroke(Color.agentSecondary, lineWidth: 1)
                        }
                    }
                    .frame(width: 7, height: 7)

                Text(metadata)
                    .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)

                Spacer(minLength: AgentSpacing.x3)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.vertical, AgentSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
        }
        .contentShape(.rect)
    }

    private var metadata: String {
        let pillarName = pillar?.name ?? "Unfiled"
        let relativeDate = brief.updatedAt.formatted(.relative(presentation: .named))
        return "\(pillarName) · \(relativeDate)"
    }
}
