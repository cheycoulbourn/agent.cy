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
    @Environment(\.modelContext) private var context
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var headerHeight: CGFloat = 0
    @State private var search = ""
    @State private var selectedFilter: IdeaBankFilter = .all
    @State private var isFilterPresented = false
    @State private var selectedIdea: CreativeBrief?
    @State private var isSelecting = false
    @State private var selectedIdeaIDs: Set<UUID> = []
    @State private var confirmsSelectionDeletion = false

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
            let matchesLifecycle = selectedFilter == .archived
                ? brief.status == .archived
                : IdeaBankPlacementPolicy.includes(brief)
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
                            if isSelecting {
                                selectionActions
                            }
                            ideaList
                            if !isSelecting {
                                saveIdeaButton
                            }
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedIdea) { brief in
            IdeaPostDraftView(brief: brief, isAlreadyInIdeaBank: true)
        }
        .confirmationDialog(
            deletionConfirmationTitle,
            isPresented: $confirmsSelectionDeletion,
            titleVisibility: .visible
        ) {
            Button(deletionActionTitle, role: .destructive, action: deleteSelectedIdeas)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .onChange(of: Set(ideas.map(\.id))) { _, visibleIdeaIDs in
            selectedIdeaIDs.formIntersection(visibleIdeaIDs)
        }
        .agentDashboardScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: "Idea Bank",
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            ) {
                headerActions
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What’s on")
                        .font(.agentDisplayLead)
                    Text("your mind?")
                        .font(.agentDisplay)
                }
                .tracking(-0.64)
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var headerActions: some View {
        HStack(spacing: 0) {
            if isSelecting {
                Button("Cancel", action: endSelection)
                    .font(.agentSubtext.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.plain)
            } else {
                if !ideas.isEmpty, selectedFilter != .archived {
                    Button(action: beginSelection) {
                        AgentIconView(.tasks, size: 18)
                            .foregroundStyle(Color.agentText)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle().inset(by: -2))
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select ideas")
                        .accessibilityHint("Choose one or more ideas to manage")
                }
                filterMenu
            }
        }
        .padding(.trailing, isSelecting ? AgentSpacing.x2 : AgentSpacing.x1)
    }

    private var filterMenu: some View {
        Button {
            isFilterPresented.toggle()
        } label: {
            AgentIconView(.filter, size: 18)
                .foregroundStyle(Color.agentText)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle().inset(by: -2))
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
                        PillarColorMark(color: Color(agentHex: colorHex), diameter: 12)
                    } else if isUnfiled {
                        Circle()
                            .stroke(Color.agentSecondary, lineWidth: 1.25)
                    } else {
                        AgentIconView(.pillars, size: 12)
                    }
                }
                .frame(width: 14, height: 14)

                Text(title)
                    .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if selectedFilter == filter {
                    AgentIconView(.check, size: 13)
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
            AgentIconView(.search, size: 15)
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

    private var selectionActions: some View {
        HStack(spacing: AgentSpacing.x3) {
            Text("\(selectedIdeaIDs.count) SELECTED")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)

            Spacer(minLength: AgentSpacing.x2)

            Button(allVisibleIdeasAreSelected ? "Clear" : "Select all") {
                if allVisibleIdeasAreSelected {
                    selectedIdeaIDs.removeAll()
                } else {
                    selectedIdeaIDs = Set(ideas.map(\.id))
                }
            }
            .font(.agentSubtext.weight(.semibold))
            .buttonStyle(.plain)

            Button("Delete", role: .destructive) {
                confirmsSelectionDeletion = true
            }
            .font(.agentSubtext.weight(.semibold))
            .buttonStyle(.plain)
            .disabled(selectedIdeaIDs.isEmpty)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, AgentSpacing.x3)
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
                        if isSelecting {
                            toggleSelection(for: brief)
                        } else {
                            selectedIdea = brief
                        }
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            if isSelecting {
                                selectionIndicator(isSelected: selectedIdeaIDs.contains(brief.id))
                            }

                            IdeaBankRow(
                                brief: brief,
                                pillar: pillar(for: brief),
                                showsDivider: index < ideas.count - 1,
                                showsDisclosure: !isSelecting
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(brief.title)
                    .accessibilityValue(
                        isSelecting
                            ? (selectedIdeaIDs.contains(brief.id) ? "Selected" : "Not selected")
                            : ""
                    )
                    .accessibilityHint(
                        isSelecting
                            ? "Toggles this idea's selection"
                            : "Opens this idea where you left off"
                    )
                }
            }
        }
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Circle()
            .fill(isSelected ? Color.agentText : Color.clear)
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.agentText : Color.agentBorder, lineWidth: 1.25)
            }
            .overlay {
                if isSelected {
                    AgentIconView(.check, size: 9)
                        .foregroundStyle(Color.agentSurface)
                }
            }
            .frame(width: 20, height: 20)
            .frame(width: 28, height: 44)
            .accessibilityHidden(true)
    }

    private var saveIdeaButton: some View {
        AgentBlockAddActionButton(title: "Save idea", action: saveIdea)
    }

    private func saveIdea() {
        appModel.quickCapturePillarID = selectedFilter.pillarID
        appModel.setQuickCaptureMode(.idea)
        appModel.presentedSheet = .quickCapture
    }

    private func beginSelection() {
        selectedIdeaIDs.removeAll()
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = true
        }
    }

    private func endSelection() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selectedIdeaIDs.removeAll()
        }
    }

    private func toggleSelection(for brief: CreativeBrief) {
        if selectedIdeaIDs.contains(brief.id) {
            selectedIdeaIDs.remove(brief.id)
        } else {
            selectedIdeaIDs.insert(brief.id)
        }
    }

    private func deleteSelectedIdeas() {
        let selectedIdeas = ideas.filter { selectedIdeaIDs.contains($0.id) }
        if let selectedIdea, selectedIdeaIDs.contains(selectedIdea.id) {
            self.selectedIdea = nil
        }
        withAnimation(.snappy(duration: 0.24)) {
            selectedIdeas.forEach { _ = appModel.deleteDraft($0, context: context) }
        }
        endSelection()
    }

    private var allVisibleIdeasAreSelected: Bool {
        !ideas.isEmpty && Set(ideas.map(\.id)).isSubset(of: selectedIdeaIDs)
    }

    private var deletionConfirmationTitle: String {
        let count = selectedIdeaIDs.count
        return count == 1 ? "Delete this idea?" : "Delete \(count) ideas?"
    }

    private var deletionActionTitle: String {
        let count = selectedIdeaIDs.count
        return count == 1 ? "Delete idea" : "Delete \(count) ideas"
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

private extension IdeaBankFilter {
    var pillarID: UUID? {
        guard case .pillar(let pillarID) = self else { return nil }
        return pillarID
    }
}

private struct IdeaBankRow: View {
    let brief: CreativeBrief
    let pillar: Pillar?
    let showsDivider: Bool
    let showsDisclosure: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x3) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text(brief.title)
                    .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AgentSpacing.x2) {
                    if let pillar {
                        PillarColorMark(
                            color: Color(agentHex: pillar.colorHex),
                            diameter: 7,
                            lineWidth: 0.75
                        )
                    } else {
                        Circle()
                            .stroke(Color.agentSecondary, lineWidth: 1)
                            .frame(width: 7, height: 7)
                    }

                    Text(metadata)
                        .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDisclosure {
                AgentIconView(.forward, size: 11)
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 20, alignment: .trailing)
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
        if brief.status == .developing {
            return "\(pillarName) · In progress · \(relativeDate)"
        }
        return "\(pillarName) · \(relativeDate)"
    }
}
