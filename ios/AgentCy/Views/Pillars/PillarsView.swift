import SwiftData
import SwiftUI

private enum PillarsRoute: Hashable {
    case pillar(UUID)
    case idea(UUID)
    case brief(UUID)
}

struct PillarsView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var headerHeight: CGFloat = 0
    @State private var showNewPillar = false
    @State private var newPillarParentID: UUID?

    private var pillars: [Pillar] { scoped(allPillars) }
    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var canAddPillar: Bool {
        PillarCollectionPolicy.canCreate(activeCount: activePillars.count)
    }
    private var anchor: Pillar? {
        activePillars.first { $0.parentPillarID == nil && $0.role == .anchor }
            ?? activePillars.first { $0.parentPillarID == nil }
    }
    private var branches: [Pillar] {
        guard let anchor else { return [] }
        return activePillars.filter { $0.parentPillarID == anchor.id }
    }
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    paperHeader
                        .reportAgentViewHeight()

                    PillarPaperSurface(
                        minimumHeight: AgentScrollableSurfacePolicy.minimumHeight(
                            viewportHeight: proxy.size.height,
                            headerHeight: headerHeight
                        ),
                        bottomPadding: AgentScrollableSurfacePolicy.bottomPadding(mobile: 140)
                    ) {
                        if let anchor {
                            VStack(alignment: .leading, spacing: 48) {
                                anchorHero(anchor)
                                branchesSection(anchor: anchor)
                            }
                        } else {
                            emptyAnchor
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .sheet(isPresented: $showNewPillar) {
            NewPillarView(parentPillarID: newPillarParentID)
        }
        .navigationDestination(for: PillarsRoute.self) { route in
            destination(for: route)
        }
        .agentDashboardScreen()
    }

    @ViewBuilder
    private func destination(for route: PillarsRoute) -> some View {
        switch route {
        case .pillar(let id):
            if let pillar = activePillars.first(where: { $0.id == id }) {
                PillarDetailView(pillar: pillar, initialTab: .ideas)
            } else {
                unavailableDestination
            }
        case .idea(let id):
            if let brief = briefs.first(where: { $0.id == id }) {
                IdeaPostDraftView(brief: brief, isAlreadyInIdeaBank: true)
            } else {
                unavailableDestination
            }
        case .brief(let id):
            if let brief = briefs.first(where: { $0.id == id }) {
                if let output = outputs.first(where: {
                    $0.briefID == brief.id && PostOutputDetailPolicy.usesFinalizedView(
                        outputStatus: $0.status,
                        targetDate: $0.targetDate
                    )
                }) {
                    PostOutputDetailView(brief: brief, output: output)
                } else {
                    IdeaPostDraftView(brief: brief)
                }
            } else {
                unavailableDestination
            }
        }
    }

    private var unavailableDestination: some View {
        AgentEmptyState(
            title: "This item is no longer available",
            message: "It may have been moved or deleted.",
            icon: .ideas
        )
        .agentScreen()
    }

    private var paperHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            AgentPageRail(
                breadcrumb: "Pillars",
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("What do you want")
                    .font(.agentDisplayLead)
                Text("to be known for?")
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentLayout.pageTopPadding)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private func anchorHero(_ anchor: Pillar) -> some View {
        let metrics = PillarMetrics(
            pillar: anchor,
            includesBranches: false,
            pillars: activePillars,
            briefs: briefs,
            outputs: outputs
        )

        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: AgentSpacing.x2) {
                PaperPillarMeta("Anchor pillar", weight: .semibold, tracking: 1.6)
                Circle().fill(Color.agentText).frame(width: 3, height: 3)
                PaperPillarMeta(daySummary(anchor.assignedWeekdays))
            }

            NavigationLink(value: PillarsRoute.pillar(anchor.id)) {
                HStack(spacing: 14) {
                    PillarColorMark(color: Color(agentHex: anchor.colorHex), diameter: 16, lineWidth: 1)
                    Text(anchor.name)
                        .font(.paperInter(size: 32, weight: .medium, relativeTo: .title))
                        .tracking(-0.96)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AgentIconView(.forward, size: 14)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the anchor pillar")

            PillarStatsRow(
                values: [metrics.ideaCount, metrics.thisWeekCount, metrics.postedCount],
                labels: ["Ideas", "This week", "Posted"]
            )
            .padding(.vertical, AgentSpacing.x4)
            .overlay(alignment: .top) { PaperHairline() }
            .overlay(alignment: .bottom) { PaperHairline() }

        }
    }

    private func branchesSection(anchor: Pillar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AgentSpacing.x2) {
                PaperPillarMeta("Secondary pillars", weight: .semibold, tracking: 1.6)
                PaperHairline().frame(maxWidth: .infinity)
            }

            ForEach(branches) { branch in
                NavigationLink(value: PillarsRoute.pillar(branch.id)) {
                    PillarBranchRow(
                        pillar: branch,
                        metrics: PillarMetrics(
                            pillar: branch,
                            includesBranches: false,
                            pillars: activePillars,
                            briefs: briefs,
                            outputs: outputs
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            if canAddPillar {
                AgentBlockAddActionButton(title: "Add pillar") {
                    newPillarParentID = anchor.id
                    showNewPillar = true
                }
                .padding(.top, AgentSpacing.x3)
            }
        }
    }

    private var emptyAnchor: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            PaperPillarMeta("Anchor pillar")
            Text("Start with the pillar everything leads back to.")
                .font(.paperInter(size: 28, weight: .medium, relativeTo: .title))
                .tracking(-0.7)
            Text("Your anchor is the central pillar. Secondary pillars support it.")
                .font(.paperInter(size: 17, weight: .regular, relativeTo: .body))
                .foregroundStyle(Color.agentSecondary)
            Button("Create your anchor") {
                newPillarParentID = nil
                showNewPillar = true
            }
            .buttonStyle(AgentPrimaryButtonStyle())
        }
    }
}

private struct PillarBranchRow: View {
    let pillar: Pillar
    let metrics: PillarMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 10) {
                    PillarColorMark(color: Color(agentHex: pillar.colorHex), diameter: 10)
                    Text(pillar.name)
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        .tracking(-0.25)
                }
                Spacer()
                AgentIconView(.forward, size: 11)
            }

            HStack {
                HStack(spacing: AgentSpacing.x4) {
                    BranchMetric(value: metrics.ideaCount, label: "Ideas")
                    BranchMetric(value: metrics.thisWeekCount, label: "This week")
                }
                Spacer()
                PaperPillarMeta(daySummary(pillar.assignedWeekdays))
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline() }
    }
}

private struct BranchMetric: View {
    let value: Int
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(value)")
                .font(.paperInter(size: 13, weight: .semibold, relativeTo: .caption))
            PaperPillarMeta(label, tracking: 1)
        }
    }
}

struct PillarDetailView: View {
    enum ContentTab: String, CaseIterable, Identifiable {
        case ideas = "Ideas"
        case scheduled = "Scheduled"
        case posted = "Posted"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let pillar: Pillar
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var selectedTab: ContentTab
    @State private var headerHeight: CGFloat = 0
    @State private var isEditing = false
    @State private var draftName: String
    @State private var draftDetail: String
    @State private var draftColorHex: String
    @State private var confirmDelete = false

    private var pillars: [Pillar] { scoped(allPillars) }
    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks).filter { !$0.isSkipped } }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    init(pillar: Pillar, initialTab: ContentTab = .ideas) {
        self.pillar = pillar
        _selectedTab = State(initialValue: initialTab)
        _draftName = State(initialValue: pillar.name)
        _draftDetail = State(initialValue: pillar.detail)
        _draftColorHex = State(initialValue: pillar.colorHex)
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchor: Pillar { pillar.resolvedAnchor(in: activePillars) }
    private var isAnchor: Bool { pillar.id == anchor.id }
    private var branches: [Pillar] { activePillars.filter { $0.parentPillarID == pillar.id } }
    private var paletteHexes: [String] {
        profiles.first?.vibePalette?.pillarColorHexes ?? CreatorVibePalette.fallbackPillarColorHexes
    }
    private var familyBriefs: [CreativeBrief] {
        briefs.filter { $0.pillarID == pillar.id && $0.status != .archived }
    }
    private var ideas: [CreativeBrief] {
        familyBriefs.filter(IdeaBankPlacementPolicy.includes)
    }
    private var scheduled: [CreativeBrief] {
        familyBriefs.filter { brief in
            outputs.contains { $0.briefID == brief.id && $0.targetDate != nil && $0.status != .posted }
        }
    }
    private var posted: [CreativeBrief] {
        familyBriefs.filter { brief in
            brief.status == .posted || outputs.contains { $0.briefID == brief.id && $0.status == .posted }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
#if targetEnvironment(macCatalyst)
            desktopDetailRail
#endif

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        detailHeader
                            .reportAgentViewHeight()

                        PillarPaperSurface(
                            minimumHeight: AgentScrollableSurfacePolicy.minimumHeight(
                                viewportHeight: proxy.size.height,
                                headerHeight: headerHeight
                            ),
                            topPadding: 28,
                            bottomPadding: AgentScrollableSurfacePolicy.bottomPadding(mobile: 150),
                            gap: 28
                        ) {
                            VStack(alignment: .leading, spacing: 28) {
                                descriptionSection
                                if isEditing { colorSection }
                                daysPicker
                                PillarStatsRow(
                                    values: [ideas.count, scheduled.count, posted.count],
                                    labels: ["Ideas", "Scheduled", "Posted"]
                                )
                                contentTabs
                                contentList
                                if isEditing { deleteButton }
                            }
                        }
                        .padding(.horizontal, AgentLayout.dashboardGutter)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .confirmationDialog(deleteConfirmationTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(deleteConfirmationAction, role: .destructive) { deletePillar() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .agentDashboardScreen()
        .agentKeyboardDismissal()
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
#if !targetEnvironment(macCatalyst)
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        AgentIconView(.back)
                        Text("Pillars")
                    }
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                if isEditing {
                    Button("Cancel") { cancelEditing() }
                        .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)

                    Button(action: saveEdits) {
                        AgentIconView(.check, size: 15)
                            .foregroundStyle(Color.agentText)
                            .frame(width: 44, height: 44)
                            .background(Color.agentSurface, in: .circle)
                            .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSaveEdits)
                    .opacity(canSaveEdits ? 1 : 0.4)
                    .accessibilityLabel("Save pillar")
                } else {
                    Button { beginEditing() } label: {
                        Text("Edit")
                            .font(.paperInter(size: 15, weight: .semibold, relativeTo: .body))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(pillar.name)")
                }
            }
#endif

            PaperPillarMeta(isAnchor ? "Anchor pillar" : "Secondary pillar")

            HStack(spacing: 14) {
                PillarColorMark(color: Color(agentHex: displayedColorHex), diameter: 16, lineWidth: 1)
                if isEditing {
                    TextField("", text: $draftName)
                        .font(.paperInter(size: 32, weight: .medium, relativeTo: .title))
                        .tracking(-0.96)
                        .textFieldStyle(.plain)
                        .agentSingleLineSubmit()
                        .overlay(alignment: .bottom) { PaperHairline() }
                } else {
                    Text(pillar.name)
                        .font(.paperInter(size: 32, weight: .medium, relativeTo: .title))
                        .tracking(-0.96)
                }
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
    }

#if targetEnvironment(macCatalyst)
    private var desktopDetailRail: some View {
        AgentDesktopDetailRail(title: "Pillar", backAction: dismiss.callAsFunction) {
            HStack(spacing: AgentSpacing.x2) {
                if isEditing {
                    AgentDesktopDetailIconButton(title: "Cancel editing", icon: .close) {
                        cancelEditing()
                    }
                    AgentDesktopDetailIconButton(
                        title: "Save pillar",
                        icon: .check,
                        isEnabled: canSaveEdits,
                        action: saveEdits
                    )
                } else {
                    AgentDesktopDetailIconButton(title: "Edit \(pillar.name)", icon: .pencil) {
                        beginEditing()
                    }
                }
            }
        }
    }
#endif

    @ViewBuilder
    private var descriptionSection: some View {
        if isEditing || !pillar.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                PaperPillarMeta("Description", weight: .semibold, tracking: 1.6)
                if isEditing {
                    TextEditor(text: $draftDetail)
                        .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 112)
                        .padding(14)
                        .background(Color.agentCanvas, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                } else {
                    Text(pillar.detail)
                        .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            PaperPillarMeta("Color", weight: .semibold, tracking: 1.6)
            PillarColorChooser(paletteHexes: paletteHexes, selectedHex: $draftColorHex)
        }
    }

    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack {
                PaperPillarMeta("Days", weight: .semibold, tracking: 1.6)
                Spacer()
                PaperPillarMeta("\(pillar.assignedWeekdays.count) of 7")
            }

            HStack(spacing: 5) {
                ForEach(PillarWeekday.mondayFirst) { day in
                    detailDayButton(day)
                }
            }
        }
    }

    private func detailDayButton(_ day: PillarWeekday) -> some View {
        let selected = pillar.assignedWeekdays.contains(day)
        let otherPillar = activePillars.first { $0.id != pillar.id && $0.assignedWeekdays.contains(day) }
        let selectedHex = displayedColorHex
        let selectedForegroundHex = AgentChipContrast.foregroundHex(on: selectedHex)
        let otherPillarHex = otherPillar.map(\.colorHex)
        return Button {
            var days = pillar.assignedWeekdays
            if selected { days.remove(day) } else { days.insert(day) }
            pillar.assignedWeekdays = days
            try? context.save()
        } label: {
            VStack(spacing: AgentSpacing.x2) {
                Text(day.letter)
                    .font(.paperMetadata(size: 10, weight: .medium, relativeTo: .caption))
                Circle()
                    .fill(
                        selected
                            ? Color(agentHex: selectedForegroundHex)
                            : otherPillarHex.map { Color(agentHex: $0) } ?? Color.clear
                    )
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? Color(agentHex: selectedForegroundHex) : Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? Color(agentHex: selectedHex) : Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.control)
                    .stroke(selected ? Color.clear : Color.agentBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.title)
        .accessibilityValue(selected ? "Assigned to \(pillar.name)" : "Not assigned to \(pillar.name)")
    }

    private var contentTabs: some View {
        HStack(spacing: 0) {
            ForEach(ContentTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                        if tab != .posted {
                            Text("\(count(for: tab))")
                                .font(.paperMetadata(size: 10, weight: .regular, relativeTo: .caption))
                        }
                    }
                    .font(.paperInter(size: 14, weight: selectedTab == tab ? .semibold : .regular, relativeTo: .subheadline))
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(selectedTab == tab ? Color.agentSurface : Color.clear, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AgentSpacing.x1)
        .background(Color.agentText.opacity(0.05), in: .capsule)
    }

    @ViewBuilder
    private var contentList: some View {
        let items = briefs(for: selectedTab)
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { PaperHairline() }
            } else {
                ForEach(items) { brief in
                    PillarContentRow(
                        brief: brief,
                        tab: selectedTab
                    )
                }
            }

            if selectedTab == .ideas {
                Button(action: captureIdea) {
                    HStack(spacing: AgentSpacing.x3) {
                        ZStack {
                            Circle()
                                .stroke(Color.agentSecondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            AgentIconView(.add, size: 9)
                        }
                        .frame(width: 18, height: 18)
                        Text("Save an idea")
                            .font(.agentAddAction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 60)
                    .overlay(alignment: .top) { PaperHairline() }
                    .overlay(alignment: .bottom) { PaperHairline() }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func captureIdea() {
        appModel.quickCapturePillarID = pillar.id
        appModel.setQuickCaptureMode(.idea)
        appModel.presentedSheet = .quickCapture
    }

    private func count(for tab: ContentTab) -> Int { briefs(for: tab).count }
    private func briefs(for tab: ContentTab) -> [CreativeBrief] {
        switch tab {
        case .ideas: ideas
        case .scheduled: scheduled
        case .posted: posted
        }
    }
    private var emptyMessage: String {
        switch selectedTab {
        case .ideas: "No ideas yet."
        case .scheduled: "No scheduled posts."
        case .posted: "Nothing posted yet."
        }
    }

    private var deleteButton: some View {
        Button("Delete pillar", role: .destructive) { confirmDelete = true }
            .font(.paperInter(size: 15, weight: .semibold, relativeTo: .body))
            .foregroundStyle(Color.agentDestructive)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay {
                Capsule().stroke(Color.agentDestructive.opacity(0.5), lineWidth: 1)
            }
            .buttonStyle(.plain)
    }

    private var displayedColorHex: String { isEditing ? draftColorHex : pillar.colorHex }
    private var canSaveEdits: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var deleteConfirmationTitle: String {
        isAnchor && !branches.isEmpty
            ? "Delete \(pillar.name) and its branches?"
            : "Delete \(pillar.name)?"
    }
    private var deleteConfirmationAction: String {
        isAnchor && !branches.isEmpty ? "Delete pillar and branches" : "Delete pillar"
    }
    private var deleteConfirmationMessage: String {
        if isAnchor && !branches.isEmpty {
            return "These pillars will be removed. Their posts, ideas, and tasks will stay saved but become unfiled."
        }
        return "Posts, ideas, and tasks will stay saved but become unfiled."
    }

    private func beginEditing() {
        draftName = pillar.name
        draftDetail = pillar.detail
        draftColorHex = pillar.colorHex
        withAnimation(.snappy(duration: 0.2)) { isEditing = true }
    }

    private func cancelEditing() {
        draftName = pillar.name
        draftDetail = pillar.detail
        draftColorHex = pillar.colorHex
        withAnimation(.snappy(duration: 0.2)) { isEditing = false }
    }

    private func saveEdits() {
        guard canSaveEdits else { return }
        pillar.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        pillar.detail = draftDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        pillar.colorHex = draftColorHex
        do {
            try context.save()
            withAnimation(.snappy(duration: 0.2)) { isEditing = false }
        } catch {
            appModel.notice = .error("Couldn’t save this pillar. Try again.")
        }
    }

    private func deletePillar() {
        do {
            try PillarRemovalService.remove(
                pillar,
                pillars: pillars,
                briefs: briefs,
                tasks: tasks,
                context: context
            )
            dismiss()
        } catch {
            appModel.notice = .error("Couldn’t delete this pillar. Try again.")
        }
    }
}

private struct PillarContentRow: View {
    let brief: CreativeBrief
    let tab: PillarDetailView.ContentTab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: tab == .ideas ? PillarsRoute.idea(brief.id) : PillarsRoute.brief(brief.id)) {
                Text(brief.title)
                    .font(.paperInter(size: 17, weight: .regular, relativeTo: .body))
                    .tracking(-0.17)
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack {
                HStack(spacing: AgentSpacing.x2) {
                    metadataIcon
                        .frame(width: 12, height: 12)
                    PaperPillarMeta(metadata, tracking: 1)
                }
                Spacer()
                if tab == .ideas {
                    NavigationLink("New post →", value: PillarsRoute.idea(brief.id))
                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(Color.agentText)
                } else {
                    NavigationLink("Open →", value: PillarsRoute.brief(brief.id))
                        .font(.paperInter(size: 14, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(Color.agentText)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(minHeight: 85)
        .overlay(alignment: .top) { PaperHairline() }
    }

    @ViewBuilder
    private var metadataIcon: some View {
        switch brief.source {
        case .cyDirection:
            CyAsterisk(color: .cyAccent, size: 12, strokeWidth: 1.2)
        case .voiceTranscript:
            AgentIconView(.microphone, size: 10)
        case .repurposedBrief:
            AgentIconView(.branch, size: 10)
        case .sharedInspiration:
            AgentIconView(.link, size: 10)
        case .text:
            AgentIconView(.ideas, size: 10)
        }
    }
    private var metadata: String {
        switch brief.source {
        case .voiceTranscript: "Captured idea"
        case .cyDirection: "Spark · From Cy"
        case .repurposedBrief: "Spark · Repurposed"
        case .sharedInspiration: "Saved inspiration"
        case .text: "Captured by shortcut"
        }
    }
}

struct NewPillarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var name = ""
    @State private var colorHex = PillarColorOption.sage.hex
    @State private var parentPillarID: UUID?
    @State private var assignedWeekdays: Set<PillarWeekday> = []
    @State private var didApplyPaletteDefault = false
    let onSave: (Pillar) -> Void

    init(parentPillarID: UUID? = nil, onSave: @escaping (Pillar) -> Void = { _ in }) {
        _parentPillarID = State(initialValue: parentPillarID)
        self.onSave = onSave
    }

    private var pillars: [Pillar] {
        allPillars.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchor: Pillar? { activePillars.first { $0.parentPillarID == nil } }
    private var paletteHexes: [String] {
        profiles.first?.vibePalette?.pillarColorHexes ?? CreatorVibePalette.fallbackPillarColorHexes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(parentPillarID == nil ? "Anchor pillar" : "Secondary pillar") {
                    TextField("Name", text: $name)
                        .agentSingleLineSubmit()
                }
                Section("Color") { PillarColorChooser(paletteHexes: paletteHexes, selectedHex: $colorHex) }
                Section("Days") { WeekdayChooser(selection: $assignedWeekdays, accentHex: colorHex) }
            }
            .navigationTitle(parentPillarID == nil ? "New anchor" : "New pillar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !PillarCollectionPolicy.canCreate(activeCount: activePillars.count)
                        )
                }
            }
            .task {
                if parentPillarID == nil, let anchor { parentPillarID = anchor.id }
                guard !didApplyPaletteDefault, !paletteHexes.isEmpty else { return }
                colorHex = paletteHexes[activePillars.count % paletteHexes.count]
                didApplyPaletteDefault = true
            }
        }
        .agentKeyboardDismissal()
    }

    private func save() {
        guard PillarCollectionPolicy.canCreate(activeCount: activePillars.count) else {
            appModel.notice = .info("You can have up to six pillars.")
            dismiss()
            return
        }
        let parent = activePillars.first { $0.id == parentPillarID }
        let pillar = Pillar(
            parentPillarID: parent?.id,
            role: parent == nil ? .anchor : .supporting,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex,
            assignedWeekdays: assignedWeekdays
        )
        pillar.workspaceID = appModel.resolvedWorkspaceID(context: context)
        context.insert(pillar)
        try? context.save()
        onSave(pillar)
        dismiss()
    }
}

private struct PillarPaperSurface<Content: View>: View {
    let minimumHeight: CGFloat?
    var topPadding: CGFloat = 32
    var bottomPadding: CGFloat = 140
    var gap: CGFloat = 40
    @ViewBuilder let content: Content

    init(
        minimumHeight: CGFloat?,
        topPadding: CGFloat = 32,
        bottomPadding: CGFloat = 140,
        gap: CGFloat = 40,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumHeight = minimumHeight
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.gap = gap
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)
    }
}

private struct PillarStatsRow: View {
    let values: [Int]
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(alignment: .center, spacing: AgentSpacing.x1) {
                    Text("\(value)")
                        .font(.paperInter(size: 20, weight: .semibold, relativeTo: .headline))
                        .tracking(-0.4)
                    PaperPillarMeta(labels[index], tracking: 1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaperPillarMeta: View {
    let text: String
    let weight: Font.Weight
    let tracking: CGFloat

    init(_ text: String, weight: Font.Weight = .regular, tracking: CGFloat = 1.2) {
        self.text = text
        self.weight = weight
        self.tracking = tracking
    }

    var body: some View {
        Text(text.isEmpty ? "None" : text)
            .font(.paperMetadata(size: 10, weight: weight, relativeTo: .caption))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(Color.agentText)
            .lineLimit(1)
    }
}

private struct PaperHairline: View {
    var body: some View {
        Rectangle().fill(Color.agentText.opacity(0.12)).frame(height: 1)
    }
}

private struct WeekdayChooser: View {
    @Binding var selection: Set<PillarWeekday>
    var accentHex: String

    var body: some View {
        let foregroundHex = AgentChipContrast.foregroundHex(on: accentHex)
        HStack(spacing: AgentSpacing.x2) {
            ForEach(PillarWeekday.mondayFirst) { day in
                Button {
                    if selection.contains(day) { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.paperMetadata(size: 11, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(selection.contains(day) ? Color(agentHex: foregroundHex) : Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection.contains(day) ? Color(agentHex: accentHex) : Color.agentSurface, in: .circle)
                        .overlay { Circle().stroke(selection.contains(day) ? Color.clear : Color.agentBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.title)
                .accessibilityValue(selection.contains(day) ? "Selected" : "Not selected")
            }
        }
    }
}

private struct PillarColorChooser: View {
    let paletteHexes: [String]
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: AgentSpacing.x2) {
            ForEach(colors, id: \.self) { hex in
                Button { selectedHex = hex } label: {
                    Circle()
                        .fill(Color(agentHex: hex))
                        .frame(width: 32, height: 32)
                        .padding(AgentSpacing.x1)
                        .overlay {
                            Circle().stroke(Color.agentBorder, lineWidth: 0.75)
                        }
                        .overlay {
                            Circle().stroke(isSelected(hex) ? Color.agentText : Color.clear, lineWidth: 2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pillar color")
                .accessibilityValue(isSelected(hex) ? "Selected" : "Not selected")
            }
            ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(agentHex: selectedHex) },
            set: { selectedHex = $0.agentHexString }
        )
    }
    private var colors: [String] {
        paletteHexes.isEmpty ? CreatorVibePalette.fallbackPillarColorHexes : paletteHexes
    }
    private func isSelected(_ hex: String) -> Bool {
        selectedHex.caseInsensitiveCompare(hex) == .orderedSame
    }
}

private struct PillarMetrics {
    let pillar: Pillar
    let includesBranches: Bool
    let pillars: [Pillar]
    let briefs: [CreativeBrief]
    let outputs: [PlatformOutput]

    private var IDs: Set<UUID> {
        guard includesBranches else { return [pillar.id] }
        return Set([pillar.id] + pillars.filter { $0.parentPillarID == pillar.id }.map(\.id))
    }
    private var familyBriefs: [CreativeBrief] {
        briefs.filter { $0.pillarID.map(IDs.contains) == true && $0.status != .archived }
    }
    var ideaCount: Int { familyBriefs.filter(IdeaBankPlacementPolicy.includes).count }
    var postedCount: Int {
        familyBriefs.filter { brief in
            brief.status == .posted || outputs.contains { $0.briefID == brief.id && $0.status == .posted }
        }.count
    }
    var thisWeekCount: Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return familyBriefs.filter { brief in
            if let agendaDate = brief.agendaDate, interval.contains(agendaDate) { return true }
            return outputs.contains { output in
                output.briefID == brief.id && output.targetDate.map(interval.contains) == true
            }
        }.count
    }
}

private enum PillarColorOption: String, CaseIterable, Identifiable {
    case terracotta = "9B3A2E"
    case ochre = "B47724"
    case sage = "55705B"
    case blue = "416B85"
    case plum = "76506F"
    var id: String { rawValue }
    var hex: String { rawValue }
}

extension Font {
    static func paperInter(size: CGFloat, weight: Font.Weight, relativeTo style: TextStyle) -> Font {
        .custom("InterVariable", size: size, relativeTo: style).weight(weight)
    }
    static func paperMetadata(size: CGFloat, weight: Font.Weight, relativeTo style: TextStyle) -> Font {
        .custom("InterVariable", size: size, relativeTo: style).weight(weight)
    }
}

private extension Color {
    var agentHexString: String {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return PillarColorOption.sage.hex
        }
        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

private func daySummary(_ days: Set<PillarWeekday>) -> String {
    let values = PillarWeekday.mondayFirst.filter(days.contains).map(\.shortTitle)
    return values.isEmpty ? "No days" : values.joined(separator: " · ")
}
