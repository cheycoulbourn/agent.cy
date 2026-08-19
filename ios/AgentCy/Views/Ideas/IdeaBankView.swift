import SwiftData
import SwiftUI

enum IdeaBankFilter: Hashable {
    case all
    case unfiled
    case archived
    case pillar(UUID)
}

struct IdeaBankSelection: Equatable {
    let ideaIDs: Set<UUID>
    let savedPostIDs: Set<UUID>
}

enum IdeaBankRootStatePolicy {
    static func normalizedFilter(
        _ filter: IdeaBankFilter,
        activePillarIDs: Set<UUID>
    ) -> IdeaBankFilter {
        guard case .pillar(let pillarID) = filter else { return filter }
        return activePillarIDs.contains(pillarID) ? filter : .all
    }

    static func capturePillarID(
        for filter: IdeaBankFilter,
        activePillarIDs: Set<UUID>
    ) -> UUID? {
        guard case .pillar(let pillarID) = normalizedFilter(
            filter,
            activePillarIDs: activePillarIDs
        ) else { return nil }
        return pillarID
    }

    static func reconciledSelection(
        ideaIDs: Set<UUID>,
        savedPostIDs: Set<UUID>,
        visibleIdeaIDs: Set<UUID>,
        visibleSavedPostIDs: Set<UUID>
    ) -> IdeaBankSelection {
        IdeaBankSelection(
            ideaIDs: ideaIDs.intersection(visibleIdeaIDs),
            savedPostIDs: savedPostIDs.intersection(visibleSavedPostIDs)
        )
    }

    static func selectableSavedPostIDs(
        previewIDs: Set<UUID>,
        savedPostsAreVisible: Bool
    ) -> Set<UUID> {
        savedPostsAreVisible ? previewIDs : []
    }
}

enum IdeaBankRequestedRoute: Equatable {
    case none
    case idea(UUID)
    case missing
}

enum IdeaBankRequestedRoutePolicy {
    static func resolve(
        requestedID: UUID?,
        scopedBriefs: [CreativeBrief]
    ) -> IdeaBankRequestedRoute {
        guard let requestedID else { return .none }
        return scopedBriefs.contains(where: { $0.id == requestedID })
            ? .idea(requestedID)
            : .missing
    }
}

enum IdeaBankRootAccessibilityPolicy {
    static func shouldAnimateSelection(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func usesStackedSelectionActions(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func usesBoundedCancelAction(dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    static func ideaTitleLineLimit(dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }

    static func ideaMetadataLineLimit(dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 1
    }
}

struct IdeaBankRootProjection {
    let resolvedWorkspaceID: UUID?
    let scopedBriefs: [CreativeBrief]
    let activePillars: [Pillar]
    let pillarByID: [UUID: Pillar]
    let normalizedFilter: IdeaBankFilter
    let ideas: [CreativeBrief]
    let savedInspirations: [InspirationSource]
    let savedInspirationPreview: [InspirationSource]
}

enum IdeaBankRootProjectionPolicy {
    static func make(
        briefs: [CreativeBrief],
        inspirationSources: [InspirationSource],
        pillars: [Pillar],
        preferredWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace],
        search: String,
        selectedFilter: IdeaBankFilter
    ) -> IdeaBankRootProjection {
        let resolvedWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        )
        let scopedBriefs = unique(briefs.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: resolvedWorkspaceID,
                workspaces: workspaces
            )
        })
        let scopedPillars = unique(pillars.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: resolvedWorkspaceID,
                workspaces: workspaces
            )
        })
        let pillarByID = Dictionary(uniqueKeysWithValues: scopedPillars.map { ($0.id, $0) })
        let activePillars = PillarRootHierarchyPolicy.activePillars(from: scopedPillars)
        let activePillarIDs = Set(activePillars.map(\.id))
        let normalizedFilter = IdeaBankRootStatePolicy.normalizedFilter(
            selectedFilter,
            activePillarIDs: activePillarIDs
        )
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        let visibleIdeas = scopedBriefs.filter { brief in
            let matchesLifecycle = normalizedFilter == .archived
                ? brief.status == .archived
                : IdeaBankPlacementPolicy.includes(brief)
            guard matchesLifecycle,
                  !brief.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            let attachedPillar = brief.pillarID.flatMap { pillarByID[$0] }
            let matchesSearch = query.isEmpty
                || brief.title.localizedStandardContains(query)
                || brief.notes.localizedStandardContains(query)
                || attachedPillar?.name.localizedStandardContains(query) == true
            let matchesFilter: Bool = switch normalizedFilter {
            case .all, .archived:
                true
            case .unfiled:
                attachedPillar == nil
            case .pillar(let pillarID):
                brief.pillarID == pillarID
            }
            return matchesSearch && matchesFilter
        }

        let savedInspirations = unique(inspirationSources.filter { source in
            SavedPostsScopePolicy.includes(
                recordWorkspaceID: source.workspaceID,
                activeWorkspaceID: resolvedWorkspaceID
            ) && (
                query.isEmpty
                    || SavedPostPresentation.title(for: source).localizedStandardContains(query)
                    || source.pillarID.flatMap { pillarByID[$0] }?.name.localizedStandardContains(query) == true
            )
        })

        return IdeaBankRootProjection(
            resolvedWorkspaceID: resolvedWorkspaceID,
            scopedBriefs: scopedBriefs,
            activePillars: activePillars,
            pillarByID: pillarByID,
            normalizedFilter: normalizedFilter,
            ideas: visibleIdeas,
            savedInspirations: savedInspirations,
            savedInspirationPreview: SavedPostsPreviewPolicy.preview(savedInspirations)
        )
    }

    private static func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID == UUID {
        var seen: Set<UUID> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

struct IdeaBankView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \InspirationSource.updatedAt, order: .reverse) private var allInspirationSources: [InspirationSource]
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
    @State private var selectedSavedPostIDs: Set<UUID> = []
    @State private var confirmsSelectionDeletion = false
    @State private var showsSavedPostsLibrary = false
    @State private var showsLinkCapture = false
    @State private var pendingSavedPostDeletion: InspirationSource?
    @State private var confirmsSavedPostDeletion = false
    @State private var attemptedSavedPostThumbnailIDs: Set<UUID> = []
#if DEBUG
    @State private var didApplyPreviewFixture = false
#endif

    private var rootProjection: IdeaBankRootProjection {
        IdeaBankRootProjectionPolicy.make(
            briefs: allBriefs,
            inspirationSources: allInspirationSources,
            pillars: allPillars,
            preferredWorkspaceID: appModel.activeWorkspaceID,
            workspaces: workspaces,
            search: search,
            selectedFilter: selectedFilter
        )
    }

    var body: some View {
        let projection = rootProjection
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(projection: projection)
                        .reportAgentViewHeight()

                    AgentDashboardSurface(minimumHeight: AgentScrollableSurfacePolicy.minimumHeight(
                        viewportHeight: proxy.size.height,
                        headerHeight: headerHeight,
                        mobileAdjustment: 72
                    )) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                            searchField
                            #if !targetEnvironment(macCatalyst)
                            inspirationList(projection: projection)
                            #endif
                            if isSelecting {
                                selectionActions(projection: projection)
                            }
                            ideaList(projection: projection)
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
        .navigationDestination(isPresented: $showsSavedPostsLibrary) {
            SavedPostsLibraryView()
        }
        .sheet(isPresented: $showsLinkCapture) {
            SavedPostLinkCaptureView()
                .environment(appModel)
                .presentationDetents([.medium, .large])
                .agentSheetDragIndicator()
        }
        .confirmationDialog(
            deletionConfirmationTitle,
            isPresented: $confirmsSelectionDeletion,
            titleVisibility: .visible
        ) {
            Button(deletionActionTitle, role: .destructive, action: deleteSelectedItems)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Delete saved post?",
            isPresented: $confirmsSavedPostDeletion,
            titleVisibility: .visible,
            presenting: pendingSavedPostDeletion
        ) { source in
            Button("Delete saved post", role: .destructive) { deleteSavedPost(source) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The saved reference will be removed. Any idea you already created from it will stay in your Idea Bank.")
        }
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .onChange(of: selectionVisibilityKey(projection: projection)) { _, _ in
            reconcileSelection(projection: rootProjection)
        }
        .onAppear {
            applyPreviewFixtureIfNeeded()
            openRequestedIdeaIfNeeded()
        }
        .onChange(of: appModel.requestedIdeaID) { _, _ in
            openRequestedIdeaIfNeeded()
        }
        .onChange(of: projection.resolvedWorkspaceID) { _, _ in
            resetRetainedStateForWorkspaceChange()
        }
        .onChange(of: Set(projection.activePillars.map(\.id))) { _, _ in
            selectedFilter = rootProjection.normalizedFilter
        }
        .task(id: savedPostThumbnailHydrationKey(projection: projection)) {
            await hydrateMissingSavedPostThumbnails(projection: projection)
        }
        .agentDashboardScreen()
    }

    private func openRequestedIdeaIfNeeded() {
        let projection = rootProjection
        switch IdeaBankRequestedRoutePolicy.resolve(
            requestedID: appModel.requestedIdeaID,
            scopedBriefs: projection.scopedBriefs
        ) {
        case .none:
            return
        case .idea(let ideaID):
            appModel.requestedIdeaID = nil
            selectedIdea = projection.scopedBriefs.first { $0.id == ideaID }
        case .missing:
            appModel.requestedIdeaID = nil
            appModel.notice = .info("This idea is no longer available in this workspace.")
        }
    }

    private func applyPreviewFixtureIfNeeded() {
#if DEBUG
        guard !didApplyPreviewFixture else { return }
        didApplyPreviewFixture = true
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: "-agentCyPreviewIdeaBankState"),
              arguments.indices.contains(marker + 1) else { return }
        switch arguments[marker + 1] {
        case "archived":
            selectedFilter = .archived
        case "query":
            search = "No matching phrase"
        case "selection":
            isSelecting = true
            let projection = rootProjection
            selectedIdeaIDs = Set(projection.ideas.prefix(1).map(\.id))
            selectedSavedPostIDs = Set(projection.savedInspirationPreview.prefix(1).map(\.id))
        case "missing":
            appModel.requestedIdeaID = UUID()
        default:
            break
        }
        if arguments.contains("-agentCyPreviewIdeaBankFilter") {
            isFilterPresented = true
        }
#endif
    }

    private func header(projection: IdeaBankRootProjection) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: "Idea Bank",
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            ) {
                headerActions(projection: projection)
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

    private func headerActions(projection: IdeaBankRootProjection) -> some View {
        HStack(spacing: AgentSpacing.x1) {
            if isSelecting {
                if IdeaBankRootAccessibilityPolicy.usesBoundedCancelAction(
                    dynamicTypeSize: dynamicTypeSize
                ) {
                    Button(action: endSelection) {
                        AgentToolbarIconLabel(icon: .close, iconSize: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel selection")
                } else {
                    Button("Cancel", action: endSelection)
                        .font(.agentSubtext.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.plain)
                }
            } else {
                if projection.normalizedFilter != .archived,
                   !visibleSelectableIDs(projection: projection).isEmpty {
                    Button(action: beginSelection) {
                        AgentToolbarIconLabel(icon: .tasks, iconSize: 18)
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select items")
                        .accessibilityHint("Choose ideas or saved posts to manage")
                }
                filterMenu(projection: projection)
            }
        }
    }

    private func filterMenu(projection: IdeaBankRootProjection) -> some View {
        Button {
            isFilterPresented.toggle()
        } label: {
            AgentToolbarIconLabel(icon: .filter, iconSize: 18)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isFilterPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            filterPopover(projection: projection)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(24)
        }
        .accessibilityLabel("Filter ideas")
        .accessibilityValue(selectedFilterTitle(projection: projection))
    }

    private func filterPopover(projection: IdeaBankRootProjection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            filterChoice(title: "All ideas", filter: .all)
            filterChoice(title: "Unfiled", filter: .unfiled, isUnfiled: true)
            filterChoice(title: "Archived", filter: .archived)

            if !projection.activePillars.isEmpty {
                Divider()
                    .padding(.horizontal, AgentSpacing.x4)
                ForEach(projection.activePillars) { pillar in
                    filterChoice(
                        title: pillar.name,
                        filter: .pillar(pillar.id),
                        colorHex: pillar.resolvedColorHex(in: Array(projection.pillarByID.values))
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
            TextField("Search Idea Bank", text: $search)
                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .accessibilityLabel("Search ideas and saved posts")
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

    private func selectionActions(projection: IdeaBankRootProjection) -> some View {
        return Group {
            if IdeaBankRootAccessibilityPolicy.usesStackedSelectionActions(
                dynamicTypeSize: dynamicTypeSize
            ) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    selectionCountLabel
                    selectionButtons(projection: projection)
                }
            } else {
                HStack(spacing: AgentSpacing.x3) {
                    selectionCountLabel
                    Spacer(minLength: AgentSpacing.x2)
                    selectionButtons(projection: projection)
                }
            }
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

    private var selectionCountLabel: some View {
        Text("\(selectedItemCount) SELECTED")
            .font(.agentMetadata)
            .monospacedDigit()
            .foregroundStyle(Color.agentSecondary)
    }

    private func selectionButtons(projection: IdeaBankRootProjection) -> some View {
        HStack(spacing: AgentSpacing.x4) {
            Button(allVisibleItemsAreSelected(projection: projection) ? "Clear" : "Select all") {
                if allVisibleItemsAreSelected(projection: rootProjection) {
                    selectedIdeaIDs.removeAll()
                    selectedSavedPostIDs.removeAll()
                } else {
                    let current = rootProjection
                    selectedIdeaIDs = Set(current.ideas.map(\.id))
                    selectedSavedPostIDs = Set(selectableSavedPosts(projection: current).map(\.id))
                }
            }
            .font(.agentSubtext.weight(.semibold))
            .buttonStyle(.plain)

            Button("Delete", role: .destructive) {
                confirmsSelectionDeletion = true
            }
            .font(.agentSubtext.weight(.semibold))
            .buttonStyle(.plain)
            .disabled(selectedItemCount == 0)
        }
    }

    private func inspirationList(projection: IdeaBankRootProjection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Saved Posts", trailing: "\(projection.savedInspirations.count)")
            if !isSelecting {
                AgentBlockAddActionButton(title: "Save a post") {
                    showsLinkCapture = true
                }
                .padding(.top, AgentSpacing.x3)
                .padding(.bottom, projection.savedInspirationPreview.isEmpty ? 0 : AgentSpacing.x2)
            }
            ForEach(Array(projection.savedInspirationPreview.enumerated()), id: \.element.id) { index, source in
                SavedPostRow(
                    source: source,
                    pillarName: source.pillarID.flatMap { projection.pillarByID[$0] }?.name,
                    pillarColorHex: source.pillarID.flatMap { projection.pillarByID[$0] }?.resolvedColorHex(
                        in: Array(projection.pillarByID.values)
                    ),
                    showsDivider: index < projection.savedInspirationPreview.count - 1,
                    open: { appModel.openInspiration(source) },
                    openOriginal: { openOriginalPost(source) },
                    requestDeletion: { requestSavedPostDeletion(source) },
                    isSelecting: isSelecting,
                    isSelected: selectedSavedPostIDs.contains(source.id),
                    toggleSelection: { toggleSelection(for: source) }
                )
            }

            if !projection.savedInspirations.isEmpty {
                Button {
                    showsSavedPostsLibrary = true
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        Text("View all saved posts")
                            .font(.agentSubtext.weight(.semibold))
                        Spacer()
                        AgentIconView(.forward, size: 11)
                    }
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the complete Saved Posts bank")
            }
        }
    }

    private func openOriginalPost(_ source: InspirationSource) {
        guard let url = URL(string: source.canonicalURLString) else { return }
        openURL(url)
    }

    private func requestSavedPostDeletion(_ source: InspirationSource) {
        pendingSavedPostDeletion = source
        confirmsSavedPostDeletion = true
    }

    private func deleteSavedPost(_ source: InspirationSource) {
        do {
            try InspirationDeletionCoordinator.delete(source, context: context)
            appModel.notice = .info("Saved post deleted.")
        } catch {
            appModel.presentCreatorError(error, action: "This saved post")
        }
        pendingSavedPostDeletion = nil
    }

    private func savedPostThumbnailHydrationKey(projection: IdeaBankRootProjection) -> String {
        SavedPostThumbnailHydrationPolicy.taskKey(
            workspaceKey: projection.resolvedWorkspaceID?.uuidString ?? "legacy",
            missingSourceIDs: projection.savedInspirations.filter { $0.thumbnailData == nil }.map(\.id)
        )
    }

    @MainActor
    private func hydrateMissingSavedPostThumbnails(projection: IdeaBankRootProjection) async {
        for source in projection.savedInspirations where source.thumbnailData == nil {
            guard !Task.isCancelled,
                  attemptedSavedPostThumbnailIDs.insert(source.id).inserted
            else { continue }
            await SavedPostThumbnailHydrator().hydrate(source: source, context: context)
        }
    }

    @ViewBuilder
    private func ideaList(projection: IdeaBankRootProjection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Idea Bank", trailing: "\(projection.ideas.count)")

            if !isSelecting {
                AgentBlockAddActionButton(title: "Add idea") {
                    saveIdea(projection: projection)
                }
                .padding(.top, AgentSpacing.x3)
                .padding(.bottom, projection.ideas.isEmpty ? 0 : AgentSpacing.x2)
            }

            if projection.ideas.isEmpty {
                Text(emptyStateCopy(projection: projection))
                    .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            } else {
                ForEach(Array(projection.ideas.enumerated()), id: \.element.id) { index, brief in
                    Button {
                        if isSelecting {
                            toggleSelection(for: brief)
                        } else {
                            selectedIdea = brief
                        }
                    } label: {
                        HStack(spacing: AgentSpacing.x3) {
                            if isSelecting {
                                AgentSelectionIndicator(isSelected: selectedIdeaIDs.contains(brief.id))
                            }

                            IdeaBankRow(
                                brief: brief,
                                pillar: brief.pillarID.flatMap { projection.pillarByID[$0] },
                                showsDivider: index < projection.ideas.count - 1,
                                showsDisclosure: !isSelecting
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(brief.title)
                    .accessibilityValue(
                        isSelecting
                            ? (selectedIdeaIDs.contains(brief.id) ? "Selected" : "Not selected")
                            : IdeaBankRow.accessibilityMetadata(
                                brief: brief,
                                pillar: brief.pillarID.flatMap { projection.pillarByID[$0] }
                            )
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

    private func saveIdea(projection: IdeaBankRootProjection) {
        appModel.quickCapturePillarID = IdeaBankRootStatePolicy.capturePillarID(
            for: projection.normalizedFilter,
            activePillarIDs: Set(projection.activePillars.map(\.id))
        )
        appModel.setQuickCaptureMode(.idea)
        appModel.presentedSheet = .quickCapture
    }

    private func beginSelection() {
        selectedIdeaIDs.removeAll()
        selectedSavedPostIDs.removeAll()
        updateSelectionMode(true)
    }

    private func endSelection() {
        updateSelectionMode(false) {
            isSelecting = false
            selectedIdeaIDs.removeAll()
            selectedSavedPostIDs.removeAll()
        }
    }

    private func updateSelectionMode(
        _ selecting: Bool,
        updates: (() -> Void)? = nil
    ) {
        let action = {
            if let updates {
                updates()
            } else {
                isSelecting = selecting
            }
        }
        if IdeaBankRootAccessibilityPolicy.shouldAnimateSelection(reduceMotion: reduceMotion) {
            withAnimation(.snappy(duration: 0.2), action)
        } else {
            action()
        }
    }

    private func toggleSelection(for brief: CreativeBrief) {
        if selectedIdeaIDs.contains(brief.id) {
            selectedIdeaIDs.remove(brief.id)
        } else {
            selectedIdeaIDs.insert(brief.id)
        }
    }

    private func toggleSelection(for source: InspirationSource) {
        if selectedSavedPostIDs.contains(source.id) {
            selectedSavedPostIDs.remove(source.id)
        } else {
            selectedSavedPostIDs.insert(source.id)
        }
    }

    private func deleteSelectedItems() {
        let projection = rootProjection
        reconcileSelection(projection: projection)
        let selectedIdeas = projection.ideas.filter { selectedIdeaIDs.contains($0.id) }
        let selectedSavedPosts = selectableSavedPosts(projection: projection).filter {
            selectedSavedPostIDs.contains($0.id)
        }
        if let selectedIdea, selectedIdeaIDs.contains(selectedIdea.id) {
            self.selectedIdea = nil
        }
        let deleteIdeas = {
            selectedIdeas.forEach { _ = appModel.deleteDraft($0, context: context) }
        }
        if IdeaBankRootAccessibilityPolicy.shouldAnimateSelection(reduceMotion: reduceMotion) {
            withAnimation(.snappy(duration: 0.24), deleteIdeas)
        } else {
            deleteIdeas()
        }
        do {
            for source in selectedSavedPosts {
                try InspirationDeletionCoordinator.delete(source, context: context)
            }
        } catch {
            appModel.presentCreatorError(error, action: "The selected saved posts")
        }
        endSelection()
    }

    private func selectableSavedPosts(
        projection: IdeaBankRootProjection
    ) -> [InspirationSource] {
#if targetEnvironment(macCatalyst)
        let savedPostsAreVisible = false
#else
        let savedPostsAreVisible = true
#endif
        let selectableIDs = IdeaBankRootStatePolicy.selectableSavedPostIDs(
            previewIDs: Set(projection.savedInspirationPreview.map(\.id)),
            savedPostsAreVisible: savedPostsAreVisible
        )
        return projection.savedInspirationPreview.filter { selectableIDs.contains($0.id) }
    }

    private func visibleSelectableIDs(projection: IdeaBankRootProjection) -> Set<UUID> {
        Set(projection.ideas.map(\.id)).union(
            selectableSavedPosts(projection: projection).map(\.id)
        )
    }

    private var selectedItemCount: Int {
        selectedIdeaIDs.count + selectedSavedPostIDs.count
    }

    private func allVisibleItemsAreSelected(projection: IdeaBankRootProjection) -> Bool {
        let selectableSavedPosts = selectableSavedPosts(projection: projection)
        return !visibleSelectableIDs(projection: projection).isEmpty &&
            Set(projection.ideas.map(\.id)).isSubset(of: selectedIdeaIDs) &&
            Set(selectableSavedPosts.map(\.id)).isSubset(of: selectedSavedPostIDs)
    }

    private var deletionConfirmationTitle: String {
        if selectedItemCount == 1 {
            return selectedSavedPostIDs.isEmpty ? "Delete this idea?" : "Delete this saved post?"
        }
        return "Delete \(selectedItemCount) items?"
    }

    private var deletionActionTitle: String {
        if selectedItemCount == 1 {
            return selectedSavedPostIDs.isEmpty ? "Delete idea" : "Delete saved post"
        }
        return "Delete \(selectedItemCount) items"
    }

    private func selectedFilterTitle(projection: IdeaBankRootProjection) -> String {
        switch projection.normalizedFilter {
        case .all:
            return "All ideas"
        case .unfiled:
            return "Unfiled"
        case .archived:
            return "Archived"
        case .pillar(let pillarID):
            return projection.activePillars.first(where: { $0.id == pillarID })?.name ?? "All ideas"
        }
    }

    private func emptyStateCopy(projection: IdeaBankRootProjection) -> String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No ideas match this search."
        }
        switch projection.normalizedFilter {
        case .all:
            return "No ideas yet."
        case .unfiled:
            return "No unfiled ideas."
        case .archived:
            return "No archived work."
        case .pillar:
            return "No ideas saved under \(selectedFilterTitle(projection: projection))."
        }
    }

    private func selectionVisibilityKey(
        projection: IdeaBankRootProjection
    ) -> IdeaBankSelection {
        IdeaBankSelection(
            ideaIDs: Set(projection.ideas.map(\.id)),
            savedPostIDs: Set(selectableSavedPosts(projection: projection).map(\.id))
        )
    }

    private func reconcileSelection(projection: IdeaBankRootProjection) {
        let reconciled = IdeaBankRootStatePolicy.reconciledSelection(
            ideaIDs: selectedIdeaIDs,
            savedPostIDs: selectedSavedPostIDs,
            visibleIdeaIDs: Set(projection.ideas.map(\.id)),
            visibleSavedPostIDs: Set(selectableSavedPosts(projection: projection).map(\.id))
        )
        selectedIdeaIDs = reconciled.ideaIDs
        selectedSavedPostIDs = reconciled.savedPostIDs
    }

    private func resetRetainedStateForWorkspaceChange() {
        search = ""
        selectedFilter = .all
        selectedIdea = nil
        pendingSavedPostDeletion = nil
        confirmsSavedPostDeletion = false
        showsSavedPostsLibrary = false
        attemptedSavedPostThumbnailIDs.removeAll()
        endSelection()
    }
}

private struct IdeaBankRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    .lineLimit(IdeaBankRootAccessibilityPolicy.ideaTitleLineLimit(
                        dynamicTypeSize: dynamicTypeSize
                    ))
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
                        .lineLimit(IdeaBankRootAccessibilityPolicy.ideaMetadataLineLimit(
                            dynamicTypeSize: dynamicTypeSize
                        ))
                        .fixedSize(horizontal: false, vertical: true)
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
        Self.accessibilityMetadata(brief: brief, pillar: pillar)
    }

    static func accessibilityMetadata(brief: CreativeBrief, pillar: Pillar?) -> String {
        let pillarName = pillar?.name ?? "Unfiled"
        let relativeDate = brief.updatedAt.formatted(.relative(presentation: .named))
        if brief.status == .developing {
            return "\(pillarName) · In progress · \(relativeDate)"
        }
        return "\(pillarName) · \(relativeDate)"
    }
}
