import SwiftData
import SwiftUI
import UIKit

private enum PillarsRoute: Hashable {
    case pillar(UUID)
    case idea(UUID)
    case brief(UUID)
}

enum PillarEducationContent {
    static let anchorShareRange = 40...60
    static let popoverDefinition = "Pillars are the repeatable themes you want to be known for. Your anchor leads the mix, while secondary pillars keep it varied and balanced."
    static let anchorGuidance = "Plan 40–60% of your posts around your anchor. That is enough repetition to build recognition without making your content feel narrow."
}

enum PillarRootHierarchyPolicy {
    static let maximumBranchCount = PillarCollectionPolicy.maximumActiveCount - 1

    static func activePillars(from pillars: [Pillar]) -> [Pillar] {
        let ordered = pillars
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        var seen: Set<UUID> = []
        return ordered.filter { seen.insert($0.id).inserted }
    }

    static func anchor(in activePillars: [Pillar]) -> Pillar? {
        activePillars.first { $0.parentPillarID == nil && $0.role == .anchor }
            ?? activePillars.first { $0.parentPillarID == nil }
            ?? activePillars.first
    }

    static func branches(anchor: Pillar, activePillars: [Pillar]) -> [Pillar] {
        activePillars.filter { $0.id != anchor.id }
    }
}

struct PillarRootMetric: Equatable {
    let ideaCount: Int
    let thisWeekCount: Int
    let usagePercentage: Int
}

struct PillarRootProjection {
    let orderedPillarIDs: [UUID]
    let metricsByPillarID: [UUID: PillarRootMetric]
}

enum PillarRootProjectionPolicy {
    static func make(
        activePillars: [Pillar],
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PillarRootProjection {
        let active = PillarRootHierarchyPolicy.activePillars(from: activePillars)
        guard let anchor = PillarRootHierarchyPolicy.anchor(in: active) else {
            return PillarRootProjection(orderedPillarIDs: [], metricsByPillarID: [:])
        }
        let ordered = [anchor] + PillarRootHierarchyPolicy.branches(
            anchor: anchor,
            activePillars: active
        )
        let activeIDs = Set(ordered.map(\.id))
        let interval = PillarUsageSchedulePolicy.weekInterval(
            containing: now,
            calendar: calendar
        )
        let scheduledCounts = PillarUsageSchedulePolicy.scheduledBriefCountsByPillar(
            briefs: briefs,
            outputs: outputs,
            interval: interval
        )
        let weights = ordered.map { scheduledCounts[$0.id] ?? 0 }
        let percentages = PillarUsageSchedulePolicy.percentages(weights: weights)
        var ideaCounts: [UUID: Int] = [:]
        for brief in briefs where brief.status != .archived && IdeaBankPlacementPolicy.includes(brief) {
            guard let pillarID = brief.pillarID, activeIDs.contains(pillarID) else { continue }
            ideaCounts[pillarID, default: 0] += 1
        }

        var metrics: [UUID: PillarRootMetric] = [:]
        for (index, pillar) in ordered.enumerated() {
            metrics[pillar.id] = PillarRootMetric(
                ideaCount: ideaCounts[pillar.id] ?? 0,
                thisWeekCount: weights[index],
                usagePercentage: percentages[index]
            )
        }
        return PillarRootProjection(
            orderedPillarIDs: ordered.map(\.id),
            metricsByPillarID: metrics
        )
    }
}

enum PillarCreationPalettePolicy {
    static func defaultColor(
        palette: CreatorVibePalette?,
        activeCount: Int
    ) -> String {
        let colors = palette?.pillarColorHexes ?? CreatorVibePalette.fallbackPillarColorHexes
        guard !colors.isEmpty else { return "55705B" }
        return colors[max(0, activeCount) % colors.count]
    }
}

enum PillarRootAccessibilityPolicy {
    static func usesStackedStats(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func usesStackedBranchLayout(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func usesScrollableInfoPopover(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func usesStackedAnchorMetadata(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func usesExpandedWeekdayRows(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func branchLabel(
        name: String,
        ideaCount: Int,
        thisWeekCount: Int,
        usagePercentage: Int,
        daySummary: String
    ) -> String {
        let days = daySummary.replacingOccurrences(of: " · ", with: " and ")
        return "\(name), \(ideaCount) \(ideaCount == 1 ? "idea" : "ideas"), \(thisWeekCount) this week, \(usagePercentage) percent usage, \(days)"
    }

    static func branchCapacityLabel(branchCount: Int) -> String {
        "\(branchCount) of \(PillarRootHierarchyPolicy.maximumBranchCount) secondary pillars"
    }
}

struct NewPillarRequest: Identifiable {
    let id = UUID()
    let parentPillarID: UUID?
    let initialColorHex: String
}

struct PillarsView: View {
    var body: some View {
        WorkspaceQueryScopeReader { scope in
            PillarsContent(scope: scope)
        }
    }
}

private struct PillarsContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var headerHeight: CGFloat = 0
    @State private var newPillarRequest: NewPillarRequest?
    @State private var showPillarInfo = false
    @State private var showPillarGuide = false
    @State private var pillarGuideRequestRevision = 0
    @State private var pillarsNow = Date()
#if DEBUG
    @State private var didApplyPreviewFixture = false
#endif

    private var pillars: [Pillar] { scoped(allPillars) }
    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private var activePillars: [Pillar] {
        PillarRootHierarchyPolicy.activePillars(from: pillars)
    }
    private var canAddPillar: Bool {
        PillarCollectionPolicy.canCreate(activeCount: activePillars.count)
    }
    private var anchor: Pillar? {
        PillarRootHierarchyPolicy.anchor(in: activePillars)
    }
    private var branches: [Pillar] {
        guard let anchor else { return [] }
        return PillarRootHierarchyPolicy.branches(anchor: anchor, activePillars: activePillars)
    }
    private var rootProjection: PillarRootProjection {
        PillarRootProjectionPolicy.make(
            activePillars: activePillars,
            briefs: briefs,
            outputs: outputs,
            now: pillarsNow
        )
    }
    private var activeWorkspace: CreatorWorkspace? {
        guard let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) else { return nil }
        return workspaces.first { $0.id == activeID && !$0.isArchived }
    }
    private var selectedPalette: CreatorVibePalette? {
        if let palette = activeWorkspace?.vibePalette { return palette }
        guard let profileID = activeWorkspace?.profileID else { return profiles.first?.vibePalette }
        return profiles.first { $0.id == profileID }?.vibePalette
    }
    init(scope: WorkspaceQueryScope) {
        _allPillars = Query(filter: scope.pillars, sort: \Pillar.createdAt)
        _allBriefs = Query(filter: scope.briefs, sort: \CreativeBrief.updatedAt, order: .reverse)
        _allOutputs = Query(filter: scope.outputs, sort: \PlatformOutput.createdAt, order: .reverse)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    paperHeader
                        .reportAgentViewHeight()

#if targetEnvironment(macCatalyst)
                    Group {
                        if let anchor {
                            desktopPillarOverview(anchor: anchor)
                        } else {
                            DesktopPillarSurface {
                                emptyAnchor
                            }
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                    .padding(.bottom, AgentSpacing.x8)
#else
                    PillarPaperSurface(
                        minimumHeight: AgentScrollableSurfacePolicy.minimumHeight(
                            viewportHeight: proxy.size.height,
                            headerHeight: headerHeight
                        ),
                        bottomPadding: AgentScrollableSurfacePolicy.bottomPadding(mobile: 140)
                    ) {
                        if let anchor {
                            pillarOverview(anchor: anchor)
                        } else {
                            emptyAnchor
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
#endif
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .sheet(item: $newPillarRequest) { request in
            NewPillarView(
                parentPillarID: request.parentPillarID,
                initialColorHex: request.initialColorHex
            )
        }
        .navigationDestination(for: PillarsRoute.self) { route in
            destination(for: route)
        }
        .navigationDestination(isPresented: $showPillarGuide) {
            PillarGuideView(
                anchorName: anchor?.name,
                anchorColorHex: anchor?.resolvedColorHex(in: activePillars),
                secondaryColorHexes: branches.map { $0.resolvedColorHex(in: activePillars) }
            )
        }
        .onAppear {
            refreshPillarClock()
            applyPreviewFixtureIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPillarClock()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            refreshPillarClock()
        }
        .task(id: pillarGuideRequestRevision) {
            guard pillarGuideRequestRevision > 0 else { return }
            await Task.yield()
            guard !Task.isCancelled,
                  !showPillarInfo,
                  appModel.selectedTab == .pillars
            else { return }
            showPillarGuide = true
        }
        .agentDashboardScreen()
    }

    @ViewBuilder
    private func pillarOverview(anchor: Pillar) -> some View {
#if targetEnvironment(macCatalyst)
        desktopPillarOverview(anchor: anchor)
#else
        let projection = rootProjection
        VStack(alignment: .leading, spacing: AgentSpacing.x12) {
            PillarUsageSummary(entries: usageEntries(projection: projection))
            anchorHero(
                anchor,
                metrics: rootMetric(for: anchor, projection: projection)
            )
            branchesSection(anchor: anchor, projection: projection)
        }
#endif
    }

#if targetEnvironment(macCatalyst)
    private func desktopPillarOverview(anchor: Pillar) -> some View {
        let projection = rootProjection
        let entries = usageEntries(projection: projection)

        return VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            DesktopPillarSurface {
                DesktopPillarUsageOverview(entries: entries)
            }

            DesktopPillarSurface {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: AgentSpacing.x12) {
                        anchorHero(
                            anchor,
                            metrics: rootMetric(for: anchor, projection: projection)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Keep the anchor between 40–60% of scheduled posts so it stays recognizable without crowding out the rest of your range.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 280, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                        anchorHero(
                            anchor,
                            metrics: rootMetric(for: anchor, projection: projection)
                        )

                        Text("Keep the anchor between 40–60% of scheduled posts so it stays recognizable without crowding out the rest of your range.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            DesktopPillarSurface {
                desktopBranchesSection(anchor: anchor, projection: projection)
            }
        }
    }

    private func desktopBranchesSection(
        anchor: Pillar,
        projection: PillarRootProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    PaperPillarMeta("Secondary pillars", weight: .semibold, tracking: 1.6)
                    Text("Support the anchor with range.")
                        .font(.paperInter(size: 22, weight: .medium, relativeTo: .title3))
                        .tracking(-0.45)
                }

                Spacer(minLength: AgentSpacing.x4)

                Text("\(branches.count) of \(PillarRootHierarchyPolicy.maximumBranchCount)")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .accessibilityLabel(PillarRootAccessibilityPolicy.branchCapacityLabel(
                        branchCount: branches.count
                    ))
            }

            desktopBranchGrid(projection: projection, columnCount: 2)

            if canAddPillar {
                AgentBlockAddActionButton(title: "Add pillar") {
                    presentNewPillar(parentPillarID: anchor.id)
                }
            } else {
                Text("All five secondary pillar spots are in use.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
    }

    private func desktopBranchGrid(
        projection: PillarRootProjection,
        columnCount: Int
    ) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: AgentSpacing.x3),
                count: columnCount
            ),
            alignment: .leading,
            spacing: AgentSpacing.x3
        ) {
            ForEach(branches) { branch in
                NavigationLink(value: PillarsRoute.pillar(branch.id)) {
                    DesktopPillarBranchTile(
                        pillar: branch,
                        resolvedColorHex: branch.resolvedColorHex(in: activePillars),
                        metrics: rootMetric(for: branch, projection: projection)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
#endif

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
            ) {
                pillarInfoButton
            }

            HStack(alignment: .bottom, spacing: AgentSpacing.x4) {
#if targetEnvironment(macCatalyst)
                pillarHeaderTitle
#else
                pillarHeaderTitle
                .frame(maxWidth: .infinity, alignment: .leading)
#endif

#if targetEnvironment(macCatalyst)
                Spacer(minLength: 0)
#endif
            }
            .tracking(-0.64)
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentLayout.pageTopPadding)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
    }

    private var pillarHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("What do you want")
                .font(.agentDisplayLead)
            Text("to be known for?")
                .font(.agentDisplay)
        }
        .accessibilityElement(children: .combine)
    }

    private var pillarInfoButton: some View {
        Button { showPillarInfo = true } label: {
            AgentToolbarIconLabel(icon: .info)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $showPillarInfo,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            PillarInfoPopover {
                showPillarInfo = false
                pillarGuideRequestRevision &+= 1
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(24)
        }
        .accessibilityLabel("About pillars")
        .accessibilityHint("Shows a definition and a link to the pillar guide")
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private func anchorHero(_ anchor: Pillar, metrics: PillarRootMetric) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                if PillarRootAccessibilityPolicy.usesStackedAnchorMetadata(
                    dynamicTypeSize: dynamicTypeSize
                ) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        PaperPillarMeta("Anchor pillar", weight: .semibold, tracking: 1.6)
                        PaperPillarMeta(daySummary(anchor.assignedWeekdays))
                    }
                } else {
                    HStack(spacing: AgentSpacing.x2) {
                        PaperPillarMeta("Anchor pillar", weight: .semibold, tracking: 1.6)
                        Circle().fill(Color.agentText).frame(width: 3, height: 3)
                        PaperPillarMeta(daySummary(anchor.assignedWeekdays))
                    }
                }
            }

            NavigationLink(value: PillarsRoute.pillar(anchor.id)) {
                HStack(spacing: 14) {
                    PillarColorMark(
                        color: Color(agentHex: anchor.resolvedColorHex(in: activePillars)),
                        diameter: 16,
                        lineWidth: 1
                    )
                    Text(anchor.name)
                        .font(.paperInter(size: 32, weight: .medium, relativeTo: .title))
                        .tracking(-0.96)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AgentIconView(.forward, size: 14)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the anchor pillar")

            PillarStatsRow(
                values: ["\(metrics.ideaCount)", "\(metrics.thisWeekCount)", "\(metrics.usagePercentage)%"],
                labels: ["Ideas", "This week", "Usage"]
            )
            .padding(.vertical, AgentSpacing.x4)
            .overlay(alignment: .top) { PaperHairline() }
            .overlay(alignment: .bottom) { PaperHairline() }

        }
    }

    private func branchesSection(
        anchor: Pillar,
        projection: PillarRootProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AgentSpacing.x2) {
                PaperPillarMeta("Secondary pillars", weight: .semibold, tracking: 1.6)
                PaperHairline().frame(maxWidth: .infinity)
                PaperPillarMeta(
                    "\(branches.count) of \(PillarRootHierarchyPolicy.maximumBranchCount)",
                    color: .agentSecondary
                )
                .accessibilityLabel(PillarRootAccessibilityPolicy.branchCapacityLabel(
                    branchCount: branches.count
                ))
            }

            ForEach(branches) { branch in
                NavigationLink(value: PillarsRoute.pillar(branch.id)) {
                    PillarBranchRow(
                        pillar: branch,
                        resolvedColorHex: branch.resolvedColorHex(in: activePillars),
                        metrics: rootMetric(for: branch, projection: projection)
                    )
                }
                .buttonStyle(.plain)
            }

            if canAddPillar {
                AgentBlockAddActionButton(title: "Add pillar") {
                    presentNewPillar(parentPillarID: anchor.id)
                }
                .padding(.top, AgentSpacing.x3)
            } else {
                Text("All five secondary pillar spots are in use.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.top, AgentSpacing.x3)
            }
        }
    }

    private func usageEntries(projection: PillarRootProjection) -> [PillarUsageEntry] {
        let pillarByID = DuplicateSafeIndex.firstValues(activePillars.map { ($0.id, $0) })

        return projection.orderedPillarIDs.compactMap { pillarID in
            guard let pillar = pillarByID[pillarID],
                  let metrics = projection.metricsByPillarID[pillarID]
            else { return nil }
            return PillarUsageEntry(
                pillarID: pillar.id,
                name: pillar.name,
                colorHex: pillar.resolvedColorHex(in: activePillars),
                weight: metrics.thisWeekCount,
                percentage: metrics.usagePercentage
            )
        }
    }

    private func rootMetric(
        for pillar: Pillar,
        projection: PillarRootProjection
    ) -> PillarRootMetric {
        projection.metricsByPillarID[pillar.id] ?? PillarRootMetric(
            ideaCount: 0,
            thisWeekCount: 0,
            usagePercentage: 0
        )
    }

    private func refreshPillarClock() {
        pillarsNow = Date()
    }

    private func presentNewPillar(parentPillarID: UUID?) {
        newPillarRequest = NewPillarRequest(
            parentPillarID: parentPillarID,
            initialColorHex: PillarCreationPalettePolicy.defaultColor(
                palette: selectedPalette,
                activeCount: activePillars.count
            )
        )
    }

    private func applyPreviewFixtureIfNeeded() {
#if DEBUG
        guard !didApplyPreviewFixture else { return }
        didApplyPreviewFixture = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-agentCyPreviewPillarInfo") {
            showPillarInfo = true
        }
        if arguments.contains("-agentCyPreviewNewPillar") {
            presentNewPillar(parentPillarID: nil)
        }
#endif
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
                presentNewPillar(parentPillarID: nil)
            }
            .buttonStyle(AgentPrimaryButtonStyle())
        }
    }
}

private struct PillarInfoPopover: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let openGuide: () -> Void

    var body: some View {
        Group {
            if PillarRootAccessibilityPolicy.usesScrollableInfoPopover(
                dynamicTypeSize: dynamicTypeSize
            ) {
                ScrollView { content }
                    .frame(width: 320)
                    .frame(maxHeight: 480)
            } else {
                content
                    .frame(width: 320)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(spacing: AgentSpacing.x2) {
                AgentIconView(.info, size: 17)
                Text("About pillars")
                    .font(.agentHeadline)
            }
            .foregroundStyle(Color.agentText)

            Text(PillarEducationContent.popoverDefinition)
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Aim for 40–60% of planned posts to support your anchor.")
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openGuide) {
                HStack(spacing: AgentSpacing.x3) {
                    Text("Learn more about pillars")
                        .font(.agentSubtext.weight(.semibold))
                    Spacer(minLength: AgentSpacing.x3)
                    AgentIconView(.forward, size: 12)
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.agentHairline)
                    .frame(height: 1)
            }
            .accessibilityHint("Opens the pillar guide")
        }
        .padding(AgentSpacing.x5)
    }
}

private struct PillarGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var headerHeight: CGFloat = 0

    let anchorName: String?
    let anchorColorHex: String?
    let secondaryColorHexes: [String]

    var body: some View {
        VStack(spacing: 0) {
#if targetEnvironment(macCatalyst)
            AgentDesktopDetailRail(title: "Pillar guide", backAction: dismiss.callAsFunction) {
                EmptyView()
            }
#endif

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        guideHeader
                            .reportAgentViewHeight()

                        PillarPaperSurface(
                            minimumHeight: AgentScrollableSurfacePolicy.minimumHeight(
                                viewportHeight: proxy.size.height,
                                headerHeight: headerHeight
                            ),
                            topPadding: 28,
                            bottomPadding: AgentScrollableSurfacePolicy.bottomPadding(mobile: 140),
                            gap: AgentSpacing.x8
                        ) {
                            guideContent
                        }
                        .padding(.horizontal, AgentLayout.dashboardGutter)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .agentDashboardScreen()
    }

    private var guideHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
#if !targetEnvironment(macCatalyst)
            AgentToolbarIconButton(title: "Back to pillars", icon: .back) { dismiss() }
#endif

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Pillar guide")
                Text("Build a content system people recognize.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Use one clear anchor and a small set of secondary pillars to make planning easier, maintain consistency, and leave room for range.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)
    }

    @ViewBuilder
    private var guideContent: some View {
#if targetEnvironment(macCatalyst)
        HStack(alignment: .top, spacing: AgentSpacing.x8) {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                whatPillarsDo
                anchorBalance
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                secondaryPillars
                weeklyCheck
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
#else
        VStack(alignment: .leading, spacing: AgentSpacing.x12) {
            whatPillarsDo
            anchorBalance
            secondaryPillars
            weeklyCheck
        }
#endif
    }

    private var whatPillarsDo: some View {
        PillarGuideSection(title: "What pillars do") {
            Text("Pillars are the repeatable themes your content returns to. They organize your ideas, reduce the work of deciding what to make, and help people understand what they can expect from you.")
            Text("Without pillars, every post starts from zero. With them, new ideas can still feel connected to the body of work you are building.")
        }
    }

    private var anchorBalance: some View {
        PillarGuideSection(title: "Why the anchor is 40–60%") {
            PillarBalanceGraphic(
                anchorName: anchorLabel,
                anchorColor: anchorColor,
                secondaryColors: secondaryColors
            )

            Text(PillarEducationContent.anchorGuidance)

            PillarGuideRangeRow(
                range: "Below 40%",
                explanation: "Your main point of view can become difficult to recognize."
            )
            PillarGuideRangeRow(
                range: "40–60%",
                explanation: "The anchor stays recognizable while the rest of your content adds range."
            )
            PillarGuideRangeRow(
                range: "Above 60%",
                explanation: "The mix can start to feel repetitive or too narrow."
            )
        }
    }

    private var secondaryPillars: some View {
        PillarGuideSection(title: "How secondary pillars help") {
            Text("Secondary pillars support the anchor with adjacent expertise, personality, process, or lifestyle. Together, they fill the rest of the plan and keep your posting rhythm varied without making it feel random.")
            Text("They should add dimension to the anchor, not compete with it for the center of your work.")
                .font(.agentBody.weight(.semibold))
                .foregroundStyle(Color.agentText)
        }
    }

    private var weeklyCheck: some View {
        PillarGuideSection(title: "Check the plan each week") {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                PillarGuideStep(number: 1, text: "Choose the anchor idea you want the week to reinforce.")
                PillarGuideStep(number: 2, text: "Assign one primary pillar to every planned post.")
                PillarGuideStep(number: 3, text: "Keep the anchor between 40% and 60% of the plan.")
                PillarGuideStep(number: 4, text: "Use secondary pillars to complete the mix, then adjust next week instead of forcing filler content.")
            }
        }
    }

    private var anchorColor: Color {
        anchorColorHex.map { Color(agentHex: $0) } ?? Color.agentText
    }

    private var secondaryColors: [Color] {
        let colors = secondaryColorHexes.map { Color(agentHex: $0) }
        return colors.isEmpty ? [Color.agentSecondary.opacity(0.45)] : colors
    }

    private var anchorLabel: String {
        let trimmed = anchorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Anchor pillar" : trimmed
    }
}

private struct PillarGuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: title)
            content
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PillarBalanceGraphic: View {
    let anchorName: String
    let anchorColor: Color
    let secondaryColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            GeometryReader { proxy in
                let spacing: CGFloat = 3
                let segmentWidth = max(0, (proxy.size.width - spacing) / 2)

                HStack(spacing: spacing) {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 8, bottomLeading: 8, bottomTrailing: 3, topTrailing: 3)
                    )
                    .fill(anchorColor)
                    .frame(width: segmentWidth)

                    HStack(spacing: 2) {
                        ForEach(Array(secondaryColors.enumerated()), id: \.offset) { index, color in
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: index == 0 ? 3 : 2,
                                    bottomLeading: index == 0 ? 3 : 2,
                                    bottomTrailing: index == secondaryColors.count - 1 ? 8 : 2,
                                    topTrailing: index == secondaryColors.count - 1 ? 8 : 2
                                )
                            )
                            .fill(color)
                        }
                    }
                    .frame(width: segmentWidth)
                }
            }
            .frame(height: 20)

            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Text("\(anchorName) · 40–60%")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Secondary balance")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.agentMetadata)
            .foregroundStyle(Color.agentSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The anchor should make up 40 to 60 percent of planned posts. Secondary pillars share the remaining posts.")
    }
}

private struct PillarGuideRangeRow: View {
    let range: String
    let explanation: String

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x4) {
            Text(range)
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
                .frame(width: 84, alignment: .leading)
            Text(explanation)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AgentSpacing.x2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
    }
}

private struct PillarGuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            Text("\(number)")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentText)
                .frame(width: 24, height: 24)
                .background(Color.agentSelectionFill, in: .circle)
            Text(text)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PillarBranchRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pillar: Pillar
    let resolvedColorHex: String
    let metrics: PillarRootMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 10) {
                    PillarColorMark(color: Color(agentHex: resolvedColorHex), diameter: 10)
                    Text(pillar.name)
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        .tracking(-0.25)
                }
                Spacer()
                AgentIconView(.forward, size: 11)
            }

            if PillarRootAccessibilityPolicy.usesStackedBranchLayout(
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    HStack(spacing: AgentSpacing.x4) {
                        BranchMetric(value: metrics.ideaCount, label: "Ideas")
                        BranchMetric(value: metrics.thisWeekCount, label: "This week")
                    }
                    Text("\(daySummary(pillar.assignedWeekdays)) · \(metrics.usagePercentage)% usage")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    HStack(spacing: AgentSpacing.x4) {
                        BranchMetric(value: metrics.ideaCount, label: "Ideas")
                        BranchMetric(value: metrics.thisWeekCount, label: "This week")
                    }
                    Spacer()
                    PaperPillarMeta(
                        "\(daySummary(pillar.assignedWeekdays)) · \(metrics.usagePercentage)%",
                        color: .agentSecondary
                    )
                }
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PillarRootAccessibilityPolicy.branchLabel(
            name: pillar.name,
            ideaCount: metrics.ideaCount,
            thisWeekCount: metrics.thisWeekCount,
            usagePercentage: metrics.usagePercentage,
            daySummary: daySummary(pillar.assignedWeekdays)
        ))
        .accessibilityHint("Opens this pillar")
    }
}

#if targetEnvironment(macCatalyst)
private struct DesktopPillarSurface<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(AgentSpacing.x6)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.dashboard))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.dashboard)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
    }
}

private struct DesktopPillarUsageOverview: View {
    let entries: [PillarUsageEntry]

    private var scheduledPostCount: Int {
        entries.reduce(0) { $0 + $1.weight }
    }

    private var anchorPercentage: Int {
        entries.first?.percentage ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            HStack(alignment: .bottom, spacing: AgentSpacing.x6) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    PaperPillarMeta("This week's scheduled mix", weight: .semibold, tracking: 1.6)
                    Text(scheduledPostCount == 1 ? "1 post scheduled" : "\(scheduledPostCount) posts scheduled")
                        .font(.paperInter(size: 22, weight: .medium, relativeTo: .title3))
                        .tracking(-0.45)
                }

                Spacer(minLength: AgentSpacing.x4)

                VStack(alignment: .trailing, spacing: AgentSpacing.x1) {
                    PaperPillarMeta("Anchor share", color: .agentSecondary)
                    Text("\(anchorPercentage)%")
                        .font(.paperInter(size: 22, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(Color.agentText)
                }
            }

            PillarUsageSummary(entries: entries, title: nil)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: AgentSpacing.x4)],
                alignment: .leading,
                spacing: AgentSpacing.x2
            ) {
                ForEach(entries) { entry in
                    HStack(spacing: AgentSpacing.x2) {
                        Circle()
                            .fill(Color(agentHex: entry.colorHex))
                            .frame(width: 9, height: 9)
                        Text(entry.name)
                            .font(.agentSubtext)
                            .lineLimit(1)
                        Spacer(minLength: AgentSpacing.x2)
                        Text("\(entry.percentage)%")
                            .font(.agentSubtext.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.agentText)
                }
            }
        }
    }
}

private struct DesktopPillarBranchTile: View {
    let pillar: Pillar
    let resolvedColorHex: String
    let metrics: PillarRootMetric

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            HStack(spacing: AgentSpacing.x3) {
                PillarColorMark(color: Color(agentHex: resolvedColorHex), diameter: 10)
                Text(pillar.name)
                    .font(.paperInter(size: 18, weight: .semibold, relativeTo: .headline))
                    .tracking(-0.3)
                    .lineLimit(2)
                Spacer(minLength: AgentSpacing.x3)
                AgentIconView(.forward, size: 11)
                    .frame(width: 28, height: 28)
            }

            HStack(spacing: AgentSpacing.x5) {
                BranchMetric(value: metrics.ideaCount, label: "Ideas")
                BranchMetric(value: metrics.thisWeekCount, label: "Scheduled")
            }

            HStack(spacing: AgentSpacing.x3) {
                PaperPillarMeta(daySummary(pillar.assignedWeekdays), color: .agentSecondary)
                Spacer(minLength: AgentSpacing.x3)
                Text("\(metrics.usagePercentage)% of week")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentSecondary)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(Color.agentCanvas.opacity(0.72))
        .clipShape(.rect(cornerRadius: AgentRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.card)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this pillar")
    }
}
#endif

private struct BranchMetric: View {
    let value: Int
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(value)")
                .font(.paperInter(size: 13, weight: .semibold, relativeTo: .caption))
            PaperPillarMeta(label, tracking: 1, color: .agentSecondary)
        }
    }
}

private struct PillarUsageEntry: Identifiable {
    let pillarID: UUID
    let name: String
    let colorHex: String
    let weight: Int
    let percentage: Int

    var id: UUID { pillarID }
}

private struct PillarUsageSummary: View {
    let entries: [PillarUsageEntry]
    let title: String?

    init(entries: [PillarUsageEntry], title: String? = "This week's pillar usage") {
        self.entries = entries
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                MetaLabel(title)
            }

            GeometryReader { proxy in
                let widths = PillarUsageDistribution.segmentWidths(
                    weights: entries.map(\.weight),
                    totalWidth: proxy.size.width
                )

                if widths.isEmpty {
                    Capsule()
                        .fill(Color.agentHairline)
                } else {
                    HStack(spacing: 3) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: index == entries.startIndex ? 10 : 3,
                                    bottomLeading: index == entries.startIndex ? 10 : 3,
                                    bottomTrailing: index == entries.index(before: entries.endIndex) ? 10 : 3,
                                    topTrailing: index == entries.index(before: entries.endIndex) ? 10 : 3
                                )
                            )
                            .fill(Color(agentHex: entry.colorHex))
                            .frame(width: widths[index])
                        }
                    }
                }
            }
            .frame(height: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard entries.contains(where: { $0.percentage > 0 }) else {
            return "This week's pillar usage is not planned yet"
        }
        return entries
            .map { "\($0.name), \($0.percentage) percent" }
            .joined(separator: ", ")
    }
}

enum PillarUsageDistribution {
    static func percentages(weights: [Int]) -> [Int] {
        PillarUsageSchedulePolicy.percentages(weights: weights)
    }

    static func segmentWidths(
        weights: [Int],
        totalWidth: CGFloat,
        spacing: CGFloat = 3,
        minimumWidth: CGFloat = 4
    ) -> [CGFloat] {
        let normalized = weights.map { max(0, $0) }
        let total = normalized.reduce(0, +)
        guard total > 0, !normalized.isEmpty else { return [] }

        let available = max(0, totalWidth - spacing * CGFloat(normalized.count - 1))
        let reserved = min(available, minimumWidth * CGFloat(normalized.count))
        let minimumPerSegment = reserved / CGFloat(normalized.count)
        let distributable = max(0, available - reserved)
        return normalized.map { weight in
            minimumPerSegment + distributable * CGFloat(weight) / CGFloat(total)
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
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var selectedTab: ContentTab
    @State private var headerHeight: CGFloat = 0
    @State private var isEditing = false
    @State private var draftName: String
    @State private var draftDetail: String
    @State private var draftColorHex: String
    @State private var confirmDelete = false
    @State private var confirmMakeAnchor = false

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
        activeWorkspace?.vibePalette?.pillarColorHexes ?? CreatorVibePalette.fallbackPillarColorHexes
    }
    private var activeWorkspace: CreatorWorkspace? {
        guard let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) else { return nil }
        return workspaces.first { $0.id == activeID && !$0.isArchived }
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
                            pillarDetailSections
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
        .alert(makeAnchorConfirmationTitle, isPresented: $confirmMakeAnchor) {
            Button("Cancel", role: .cancel) {}
            Button("Make anchor") { makeAnchor() }
        } message: {
            Text(makeAnchorConfirmationMessage)
        }
        .agentDashboardScreen()
        .agentKeyboardDismissal()
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
#if !targetEnvironment(macCatalyst)
            HStack {
                AgentToolbarIconButton(title: "Back to pillars", icon: .back) { dismiss() }
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
            desktopPillarActions
        }
    }

    private var desktopPillarActions: some View {
        HStack(spacing: AgentSpacing.x2) {
            if isEditing {
                Button("Cancel", action: cancelEditing)
                    .buttonStyle(AgentDesktopQuietActionButtonStyle())

                Button(action: saveEdits) {
                    HStack(spacing: AgentSpacing.x2) {
                        AgentIconView(.check, size: 14)
                        Text("Save")
                    }
                }
                .buttonStyle(AgentDesktopQuietActionButtonStyle(isProminent: true))
                .disabled(!canSaveEdits)
                .accessibilityLabel("Save pillar")
            } else {
                Button(action: beginEditing) {
                    HStack(spacing: AgentSpacing.x2) {
                        AgentIconView(.pencil, size: 14)
                        Text("Edit")
                    }
                }
                .buttonStyle(AgentDesktopQuietActionButtonStyle())
                .accessibilityLabel("Edit \(pillar.name)")
            }
        }
    }
#endif

    @ViewBuilder
    private var pillarDetailSections: some View {
#if targetEnvironment(macCatalyst)
        HStack(alignment: .top, spacing: AgentSpacing.x8) {
            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                descriptionSection
                if isEditing { colorSection }
                daysPicker
                if !isAnchor { makeAnchorSection }
                PillarStatsRow(
                    values: ["\(ideas.count)", "\(scheduled.count)", "\(posted.count)"],
                    labels: ["Ideas", "Scheduled", "Posted"]
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                contentTabs
                contentList
                if isEditing { deleteButton }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
#else
        VStack(alignment: .leading, spacing: 28) {
            descriptionSection
            if isEditing { colorSection }
            daysPicker
            if !isAnchor { makeAnchorSection }
            PillarStatsRow(
                values: ["\(ideas.count)", "\(scheduled.count)", "\(posted.count)"],
                labels: ["Ideas", "Scheduled", "Posted"]
            )
            contentTabs
            contentList
            if isEditing { deleteButton }
        }
#endif
    }

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
                        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.panel))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.panel)
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

    private var makeAnchorSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            Button("Make anchor pillar") { confirmMakeAnchor = true }
                .font(.paperInter(size: 15, weight: .medium, relativeTo: .body))
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityHint("Makes this your anchor and changes the current anchor to a secondary pillar")

            Text("Posts, ideas, and history stay with their current pillars.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
            do {
                try context.save()
            } catch {
                appModel.notice = .error("Couldn’t update this pillar’s days. Try again.")
            }
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
                    .background(
                        selectedTab == tab ? Color.agentSurface : Color.clear,
                        in: .rect(cornerRadius: AgentRadius.control)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AgentSpacing.x1)
        .background(Color.agentText.opacity(0.05), in: .rect(cornerRadius: AgentRadius.control))
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
            .buttonStyle(AgentQuietDestructiveButtonStyle())
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
    private var makeAnchorConfirmationTitle: String {
        "Make \(pillar.name) the anchor?"
    }
    private var makeAnchorConfirmationMessage: String {
        "\(pillar.name) will become your anchor. \(anchor.name) will become a secondary pillar. Posts, ideas, and history will stay attached to their current pillars."
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

    private func makeAnchor() {
        guard PillarAnchorPromotionService.promote(pillar, pillars: pillars) else {
            appModel.notice = .error("Couldn’t make this the anchor pillar. Try again.")
            return
        }

        do {
            try context.save()
            WidgetSnapshotService.refresh(context: context, workspaceID: appModel.activeWorkspaceID)
            appModel.refreshInspirationShareCreatorSnapshot(context: context)
            appModel.notice = .info("\(pillar.name) is now your anchor pillar.")
        } catch {
            context.rollback()
            appModel.notice = .error("Couldn’t make this the anchor pillar. Try again.")
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
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var name = ""
    @State private var colorHex = PillarColorOption.sage.hex
    @State private var parentPillarID: UUID?
    @State private var assignedWeekdays: Set<PillarWeekday> = []
    @State private var didApplyPaletteDefault = false
    let onSave: (Pillar) -> Void

    init(
        parentPillarID: UUID? = nil,
        initialColorHex: String? = nil,
        onSave: @escaping (Pillar) -> Void = { _ in }
    ) {
        _parentPillarID = State(initialValue: parentPillarID)
        _colorHex = State(initialValue: initialColorHex ?? PillarColorOption.sage.hex)
        _didApplyPaletteDefault = State(initialValue: initialColorHex != nil)
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
        activeWorkspace?.vibePalette?.pillarColorHexes ?? CreatorVibePalette.fallbackPillarColorHexes
    }
    private var activeWorkspace: CreatorWorkspace? {
        guard let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) else { return nil }
        return workspaces.first { $0.id == activeID && !$0.isArchived }
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
                guard !didApplyPaletteDefault else { return }
                colorHex = PillarCreationPalettePolicy.defaultColor(
                    palette: activeWorkspace?.vibePalette,
                    activeCount: activePillars.count
                )
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
        do {
            try context.save()
        } catch {
            context.rollback()
            appModel.notice = .error("Couldn’t create this pillar. Try again.")
            return
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let values: [String]
    let labels: [String]

    var body: some View {
        Group {
            if PillarRootAccessibilityPolicy.usesStackedStats(
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(spacing: AgentSpacing.x3) {
                    metrics
                }
            } else {
                HStack(spacing: 0) {
                    metrics
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var metrics: some View {
        if values.count == labels.count {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(alignment: .center, spacing: AgentSpacing.x1) {
                    Text(value)
                        .font(.paperInter(size: 20, weight: .semibold, relativeTo: .headline))
                        .tracking(-0.4)
                    PaperPillarMeta(labels[index], tracking: 1, color: .agentSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(labels[index]), \(value)")
            }
        }
    }
}

private struct PaperPillarMeta: View {
    let text: String
    let weight: Font.Weight
    let tracking: CGFloat
    let color: Color

    init(
        _ text: String,
        weight: Font.Weight = .regular,
        tracking: CGFloat = 1.2,
        color: Color = .agentText
    ) {
        self.text = text
        self.weight = weight
        self.tracking = tracking
        self.color = color
    }

    var body: some View {
        Text(text.isEmpty ? "None" : text)
            .font(.paperMetadata(size: 10, weight: weight, relativeTo: .caption))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct PaperHairline: View {
    var body: some View {
        Rectangle().fill(Color.agentText.opacity(0.12)).frame(height: 1)
    }
}

private struct WeekdayChooser: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: Set<PillarWeekday>
    var accentHex: String

    var body: some View {
        Group {
            if PillarRootAccessibilityPolicy.usesExpandedWeekdayRows(
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(spacing: 0) {
                    ForEach(PillarWeekday.mondayFirst) { day in
                        Button { toggle(day) } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                Text(day.title)
                                    .font(.agentBody)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                AgentIconView(
                                    selection.contains(day) ? .checkboxSelected : .checkboxEmpty,
                                    size: 20
                                )
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(.rect)
                            .overlay(alignment: .bottom) {
                                if day != PillarWeekday.mondayFirst.last {
                                    Rectangle()
                                        .fill(Color.agentHairline)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.title)
                        .accessibilityValue(selection.contains(day) ? "Selected" : "Not selected")
                    }
                }
            } else {
                let foregroundHex = AgentChipContrast.foregroundHex(on: accentHex)
                HStack(spacing: AgentSpacing.x2) {
                    ForEach(PillarWeekday.mondayFirst) { day in
                        Button { toggle(day) } label: {
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
    }

    private func toggle(_ day: PillarWeekday) {
        if selection.contains(day) {
            selection.remove(day)
        } else {
            selection.insert(day)
        }
    }
}

private struct PillarColorChooser: View {
    let paletteHexes: [String]
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: AgentSpacing.x2) {
            ForEach(Array(colors.enumerated()), id: \.element) { index, hex in
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
                .accessibilityLabel("Pillar color \(index + 1) of \(colors.count)")
                .accessibilityValue("\(hex), \(isSelected(hex) ? "Selected" : "Not selected")")
            }
            ZStack {
                Circle()
                    .fill(Color(agentHex: selectedHex))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Circle().stroke(Color.agentBorder, lineWidth: 0.75)
                    }

                Image(systemName: "eyedropper")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(Color.agentText)
                    .symbolRenderingMode(.monochrome)

                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.02)
                    .frame(width: 44, height: 44)
                    .clipShape(.circle)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.circle)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Choose a custom pillar color")
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
