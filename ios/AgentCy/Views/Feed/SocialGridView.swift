import SwiftData
import SwiftUI
import UIKit

enum SocialGridLayoutPolicy {
    /// Instagram profile previews use a 3:4 portrait crop.
    static let tileWidthToHeightRatio = 3.0 / 4.0
}

enum SocialGridFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case planned
    case live

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .planned: "Planned"
        case .live: "Live"
        }
    }

    func includes(_ status: PlatformOutputStatus) -> Bool {
        switch self {
        case .all: true
        case .planned: status == .scheduled
        case .live: status == .posted
        }
    }
}

struct SocialGridProjectionRecord: Equatable, Sendable {
    let outputID: UUID
    let status: PlatformOutputStatus
    let targetDate: Date?
    let postedAt: Date?
    let createdAt: Date
    let publishedURLString: String

    var effectiveDate: Date { postedAt ?? targetDate ?? createdAt }
}

enum SocialGridProjectionPolicy {
    static func includes(_ record: SocialGridProjectionRecord) -> Bool {
        switch record.status {
        case .scheduled:
            record.targetDate != nil
        case .posted:
            true
        case .draft, .ready:
            false
        }
    }

    static func orderedRecords(_ records: [SocialGridProjectionRecord]) -> [SocialGridProjectionRecord] {
        records
            .filter(includes)
            .sorted {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate > $1.effectiveDate }
                return $0.outputID.uuidString < $1.outputID.uuidString
            }
    }
}

struct SocialGridOrderState: Equatable, Sendable {
    private(set) var orderedIDs: [UUID]

    init(savedRawIDs: [String], defaultIDs: [UUID]) {
        let available = Set(defaultIDs)
        let saved = savedRawIDs.compactMap(UUID.init(uuidString:))
        let uniqueSaved = saved.reduce(into: [UUID]()) { result, id in
            guard available.contains(id), !result.contains(id) else { return }
            result.append(id)
        }
        let newlyAvailable = defaultIDs.filter { !uniqueSaved.contains($0) }
        orderedIDs = newlyAvailable + uniqueSaved
    }

    @discardableResult
    mutating func move(_ id: UUID, by offset: Int, within eligibleIDs: [UUID]) -> Bool {
        let eligibleSet = Set(eligibleIDs)
        var eligibleOrder = orderedIDs.filter { eligibleSet.contains($0) }
        guard let sourceIndex = eligibleOrder.firstIndex(of: id), !eligibleOrder.isEmpty else { return false }

        let destinationIndex = min(max(sourceIndex + offset, 0), eligibleOrder.count - 1)
        guard destinationIndex != sourceIndex else { return false }

        let moved = eligibleOrder.remove(at: sourceIndex)
        eligibleOrder.insert(moved, at: destinationIndex)
        var iterator = eligibleOrder.makeIterator()
        orderedIDs = orderedIDs.map { current in
            eligibleSet.contains(current) ? (iterator.next() ?? current) : current
        }
        return true
    }
}

struct SocialGridOrderPreferencesStore: Codable, Equatable, Sendable {
    var orderByWorkspace: [String: [String]] = [:]

    static func decode(_ value: String) -> Self? {
        guard !value.isEmpty,
              let data = value.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum SocialGridURLPolicy {
    static func instagramURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(),
              host == "instagram.com" || host.hasSuffix(".instagram.com")
        else { return nil }
        return url
    }

    static func title(from metadataTitle: String?) -> String {
        let firstLine = metadataTitle?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !firstLine.isEmpty else { return "Instagram post" }
        return String(firstLine.prefix(96))
    }
}

enum SocialGridTextPolicy {
    static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SocialGridThumbnailHydrationPolicy {
    static func taskKey(workspaceKey: String, linkedPostedOutputIDs: [UUID]) -> String {
        let outputKey = linkedPostedOutputIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(workspaceKey):\(outputKey)"
    }
}

private enum SocialGridSheet: String, Identifiable {
    case addLivePost

    var id: String { rawValue }
}

enum SocialGridPresentation: Equatable {
    case desktop
    case phone(bottomClearance: CGFloat)

    var isPhone: Bool {
        if case .phone = self { return true }
        return false
    }

    var bottomClearance: CGFloat {
        if case .phone(let bottomClearance) = self { return bottomClearance }
        return 0
    }

    var placesArrangeInProfileSummary: Bool { isPhone }
}

struct SocialGridView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorAttachment.createdAt) private var allAttachments: [CreatorAttachment]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreatorSocialAccount.createdAt) private var allSocialAccounts: [CreatorSocialAccount]
    @Query(sort: \PublishingDestination.sortOrder) private var allDestinations: [PublishingDestination]
    @State private var selectedFilter: SocialGridFilter = .all
    @State private var presentedSheet: SocialGridSheet?
    @State private var isArranging = false
    @State private var attemptedThumbnailOutputIDs: Set<UUID> = []
    @State private var isRefreshingFeed = false
    @State private var isHydratingThumbnails = false
    @AppStorage("agentcy.socialGridOrderByWorkspace") private var storedGridOrderPreferences = ""
    let presentation: SocialGridPresentation

    init(presentation: SocialGridPresentation = .desktop) {
        self.presentation = presentation
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: presentation.isPhone ? 80 : 120), spacing: 3),
            count: 3
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    pageRail
                    pageHeader
                    profileSummary
                    gridControls
                }
                .padding(.horizontal, presentation.isPhone ? AgentLayout.pageMargin : 0)

                if visibleItems.isEmpty {
                    emptyState
                        .padding(.horizontal, presentation.isPhone ? AgentLayout.pageMargin : 0)
                } else {
                    grid
                }
            }
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, AgentLayout.pageTopPadding)
            .padding(
                .bottom,
                max(AgentSpacing.x12, presentation.bottomClearance + AgentSpacing.x4)
            )
        }
        .scrollIndicators(.hidden)
        .background(Color.agentCanvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addLivePost:
                addLivePostSheet
            }
        }
        .task(id: thumbnailHydrationKey) {
            await hydrateMissingPublishedThumbnails()
        }
        .onChange(of: appModel.workspaceRevision) { _, _ in
            attemptedThumbnailOutputIDs = []
            isArranging = false
        }
    }

    @ViewBuilder
    private var pageRail: some View {
        if presentation.isPhone {
            HStack(alignment: .center, spacing: AgentSpacing.x1) {
                Button {
                    dismiss()
                } label: {
                    AgentIconView(.back, size: 18)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Plan")

                MetaLabel("Feed")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await refreshFeed() }
                } label: {
                    Group {
                        if isRefreshingFeed {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.agentText)
                        } else {
                            AgentIconView(.refresh, size: 16)
                                .foregroundStyle(Color.agentText)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingFeed)
                .accessibilityLabel(isRefreshingFeed ? "Refreshing feed" : "Refresh feed")
                .accessibilityHint("Loads newly synced posts and retries missing live post thumbnails")

                Button {
                    presentedSheet = .addLivePost
                } label: {
                    AgentIconView(.link, size: 16)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add live post")
                .accessibilityHint("Adds a published Instagram post to this grid")

                ProfileSettingsButton(
                    identity: activeIdentity,
                    action: { appModel.presentedSheet = .settings }
                )
            }
            .frame(height: 44)
        } else {
            AgentPageRail(
                breadcrumb: "Feed",
                identity: activeIdentity,
                openSettings: { appModel.presentedSheet = .settings }
            )
        }
    }

    @ViewBuilder
    private var pageHeader: some View {
        if presentation.isPhone {
            EditorialHeader(
                kicker: nil,
                title: "Your social grid.",
                subtitle: "See planned posts and linked live posts together before they land on your profile."
            )
        } else {
            HStack(alignment: .bottom, spacing: AgentSpacing.x6) {
                EditorialHeader(
                    kicker: nil,
                    title: "Your social grid.",
                    subtitle: "See planned posts and linked live posts together before they land on your profile."
                )

                Button {
                    presentedSheet = .addLivePost
                } label: {
                    AgentIconLabel(title: "Add live post", icon: .link, iconSize: 15)
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 42)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityHint("Adds a published Instagram post that was not planned in agent.cy")
            }
        }
    }

    private var profileSummary: some View {
        SocialGridProfileSummary(
            identity: activeIdentity,
            accountLabel: activeInstagramAccount.flatMap { SocialGridTextPolicy.nonempty($0.label) }
                ?? "Instagram preview",
            plannedCount: allItems.filter { $0.output.status == .scheduled }.count,
            liveCount: allItems.filter { $0.output.status == .posted }.count,
            mediaCount: allItems.filter { $0.attachment != nil }.count,
            isCompact: presentation.isPhone,
            showsArrange: presentation.placesArrangeInProfileSummary,
            isArranging: isArranging,
            canArrange: isArranging || visibleItems.count > 1,
            toggleArrangement: { isArranging.toggle() }
        )
    }

    private var gridControls: some View {
        HStack(spacing: AgentSpacing.x4) {
            Picker("Feed posts", selection: $selectedFilter) {
                ForEach(SocialGridFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: presentation.isPhone ? .infinity : 320)

            if !presentation.placesArrangeInProfileSummary {
                Spacer(minLength: AgentSpacing.x3)

                Button(isArranging ? "Done" : "Arrange") {
                    isArranging.toggle()
                }
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.actionAccent)
                .buttonStyle(.plain)
                .frame(minWidth: 72, minHeight: 40)
                .accessibilityHint(
                    isArranging
                        ? "Finishes arranging the social grid"
                        : "Shows controls to move posts earlier or later in the grid"
                )
            }
        }
    }

    @ViewBuilder
    private var addLivePostSheet: some View {
        let content = SocialGridAddLivePostView()
            .environment(appModel)
            .modelContext(modelContext)
            .background(Color.agentCanvas)
            .presentationBackground(Color.agentCanvas)

        if presentation.isPhone {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            content
                .frame(width: 560, height: 470)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                SocialGridTile(
                    item: item,
                    pillarColorHex: item.brief.pillarID.flatMap { pillarIndex[$0]?.colorHex },
                    isArranging: isArranging,
                    canMoveEarlier: index > 0,
                    canMoveLater: index < visibleItems.count - 1,
                    moveEarlier: { move(item.output.id, by: -1) },
                    moveLater: { move(item.output.id, by: 1) }
                )
            }
        }
        .background(Color.agentHairline)
        .overlay {
            Rectangle()
                .stroke(Color.agentHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Social grid")
    }

    private var emptyState: some View {
        VStack(spacing: AgentSpacing.x4) {
            AgentIconView(.instagramCamera, size: 26)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 48, height: 48)
                .background(Color.agentSurface, in: .circle)

            VStack(spacing: AgentSpacing.x2) {
                Text(selectedFilter == .all ? "Your grid is ready for its first post." : "No \(selectedFilter.title.lowercased()) posts yet.")
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                    .multilineTextAlignment(.center)
                Text("Add media to a scheduled Instagram post, or link something you already published.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Add live post") {
                presentedSheet = .addLivePost
            }
            .font(.agentSubtext.weight(.semibold))
            .foregroundStyle(Color.agentText)
            .buttonStyle(.plain)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(minHeight: 42)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.control)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(AgentSpacing.x8)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
        .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard, role: .structural)
    }

    private var activeWorkspaceID: UUID? {
        WorkspaceScope.activeWorkspaceID(preferredID: appModel.activeWorkspaceID, workspaces: workspaces)
    }

    private var workspaceStorageKey: String {
        activeWorkspaceID?.uuidString ?? "default"
    }

    private var scopedBriefs: [CreativeBrief] {
        allBriefs.filter {
            $0.status != .archived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var briefIndex: [UUID: CreativeBrief] {
        DuplicateSafeIndex.firstValues(scopedBriefs.map { ($0.id, $0) })
    }

    private var scopedOutputs: [PlatformOutput] {
        let briefIDs = Set(scopedBriefs.map(\.id))
        return allOutputs.filter {
            briefIDs.contains($0.briefID)
                && $0.platform == .instagramReels
                && WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
    }

    private var projectionRecords: [SocialGridProjectionRecord] {
        scopedOutputs.map {
            SocialGridProjectionRecord(
                outputID: $0.id,
                status: $0.status,
                targetDate: $0.targetDate,
                postedAt: $0.postedAt,
                createdAt: $0.createdAt,
                publishedURLString: $0.publishedURLString
            )
        }
    }

    private var defaultOutputIDs: [UUID] {
        SocialGridProjectionPolicy.orderedRecords(projectionRecords).map(\.outputID)
    }

    private var outputIndex: [UUID: PlatformOutput] {
        DuplicateSafeIndex.firstValues(scopedOutputs.map { ($0.id, $0) })
    }

    private var attachmentIndex: [UUID: CreatorAttachment] {
        let outputIDs = Set(defaultOutputIDs)
        let media = allAttachments
            .filter {
                $0.ownerKind == .postMedia
                    && $0.platformOutputID.map(outputIDs.contains) == true
            }
            .sorted {
                if $0.kind != $1.kind { return $0.kind == .photo }
                return $0.createdAt < $1.createdAt
            }
        return DuplicateSafeIndex.firstValues(
            media.compactMap { attachment in
                attachment.platformOutputID.map { ($0, attachment) }
            }
        )
    }

    private var orderState: SocialGridOrderState {
        let preferences = SocialGridOrderPreferencesStore.decode(storedGridOrderPreferences)
        return SocialGridOrderState(
            savedRawIDs: preferences?.orderByWorkspace[workspaceStorageKey] ?? [],
            defaultIDs: defaultOutputIDs
        )
    }

    private var allItems: [SocialGridDisplayItem] {
        orderState.orderedIDs.compactMap { outputID in
            guard let output = outputIndex[outputID],
                  let brief = briefIndex[output.briefID]
            else { return nil }
            return SocialGridDisplayItem(
                brief: brief,
                output: output,
                attachment: attachmentIndex[outputID]
            )
        }
    }

    private var visibleItems: [SocialGridDisplayItem] {
        allItems.filter { selectedFilter.includes($0.output.status) }
    }

    private var pillarIndex: [UUID: Pillar] {
        let activePillars = allPillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
        return DuplicateSafeIndex.firstValues(activePillars.map { ($0.id, $0) })
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var activeInstagramAccount: CreatorSocialAccount? {
        let instagramDestinationIDs = Set(
            allDestinations
                .filter { !$0.isArchived && $0.builtInKind == .instagram }
                .map(\.id)
        )
        return allSocialAccounts.first {
            !$0.isArchived
                && instagramDestinationIDs.contains($0.destinationID)
                && WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
    }

    private func move(_ outputID: UUID, by offset: Int) {
        var updatedState = orderState
        guard updatedState.move(outputID, by: offset, within: visibleItems.map(\.id)) else { return }

        var preferences = SocialGridOrderPreferencesStore.decode(storedGridOrderPreferences) ?? .init()
        preferences.orderByWorkspace[workspaceStorageKey] = updatedState.orderedIDs.map(\.uuidString)
        guard let encoded = preferences.encoded() else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            storedGridOrderPreferences = encoded
        }
    }

    private var thumbnailCandidates: [SocialGridDisplayItem] {
        allItems.filter {
            $0.output.status == .posted
                && $0.attachment == nil
                && SocialGridURLPolicy.instagramURL(from: $0.output.publishedURLString) != nil
                && !attemptedThumbnailOutputIDs.contains($0.output.id)
        }
    }

    private var thumbnailHydrationKey: String {
        SocialGridThumbnailHydrationPolicy.taskKey(
            workspaceKey: workspaceStorageKey,
            linkedPostedOutputIDs: allItems.compactMap { item in
                guard item.output.status == .posted,
                      SocialGridURLPolicy.instagramURL(from: item.output.publishedURLString) != nil
                else { return nil }
                return item.output.id
            }
        )
    }

    @MainActor
    private func refreshFeed() async {
        guard !isRefreshingFeed else { return }
        isRefreshingFeed = true
        defer { isRefreshingFeed = false }

        if modelContext.hasChanges {
            try? modelContext.save()
        }
        modelContext.processPendingChanges()

        // SwiftData receives CloudKit changes automatically. A fresh fetch after
        // a short yield makes any newly imported records visible immediately.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        _ = try? modelContext.fetch(FetchDescriptor<CreativeBrief>())
        _ = try? modelContext.fetch(FetchDescriptor<PlatformOutput>())
        _ = try? modelContext.fetch(FetchDescriptor<CreatorAttachment>())
        modelContext.processPendingChanges()

        while isHydratingThumbnails, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }
        attemptedThumbnailOutputIDs.removeAll()
        await hydrateMissingPublishedThumbnails()
    }

    @MainActor
    private func hydrateMissingPublishedThumbnails() async {
        guard !isHydratingThumbnails else { return }
        isHydratingThumbnails = true
        defer { isHydratingThumbnails = false }

        for item in thumbnailCandidates.prefix(8) {
            guard !Task.isCancelled,
                  attemptedThumbnailOutputIDs.insert(item.output.id).inserted,
                  let url = SocialGridURLPolicy.instagramURL(from: item.output.publishedURLString)
            else { continue }

            guard let metadata = try? await PostLinkMetadataService().fetch(url: url, platform: .instagram),
                  let thumbnailData = metadata.thumbnailData,
                  !allAttachments.contains(where: {
                      $0.ownerKind == .postMedia && $0.platformOutputID == item.output.id
                  })
            else { continue }

            let attachment = CreatorAttachment(
                ownerKind: .postMedia,
                briefID: item.brief.id,
                platformOutputID: item.output.id,
                fileName: "published-thumbnail-\(item.output.id.uuidString.prefix(8)).jpg",
                kind: .photo,
                uniformTypeIdentifier: "public.image",
                byteCount: Int64(thumbnailData.count),
                localRelativePath: "",
                cloudData: thumbnailData,
                syncState: .synced
            )
            attachment.workspaceID = item.output.workspaceID ?? item.brief.workspaceID ?? activeWorkspaceID
            modelContext.insert(attachment)
            try? modelContext.save()
        }
    }

}

private struct SocialGridDisplayItem: Identifiable {
    let brief: CreativeBrief
    let output: PlatformOutput
    let attachment: CreatorAttachment?

    var id: UUID { output.id }
}

private struct SocialGridProfileSummary: View {
    let identity: ActiveCreatorIdentity
    let accountLabel: String
    let plannedCount: Int
    let liveCount: Int
    let mediaCount: Int
    let isCompact: Bool
    let showsArrange: Bool
    let isArranging: Bool
    let canArrange: Bool
    let toggleArrangement: () -> Void

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    HStack(alignment: .top, spacing: AgentSpacing.x3) {
                        identityRow
                        Spacer(minLength: AgentSpacing.x3)
                        if showsArrange {
                            Button(isArranging ? "Done" : "Arrange", action: toggleArrangement)
                                .font(.agentSubtext.weight(.semibold))
                                .foregroundStyle(Color.actionAccent)
                                .buttonStyle(.plain)
                                .frame(minWidth: 72, minHeight: 40, alignment: .trailing)
                                .disabled(!canArrange)
                                .opacity(canArrange ? 1 : 0.42)
                                .accessibilityHint(
                                    isArranging
                                        ? "Finishes arranging the social grid"
                                        : "Shows controls to move posts earlier or later in the grid"
                                )
                        }
                    }

                    HStack(spacing: 0) {
                        SocialGridStat(value: plannedCount, label: "Planned", isCompact: true)
                        SocialGridStat(value: liveCount, label: "Live", isCompact: true)
                        SocialGridStat(value: mediaCount, label: "With media", isCompact: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: AgentSpacing.x4) {
                    identityRow
                    Spacer(minLength: AgentSpacing.x6)
                    SocialGridStat(value: plannedCount, label: "Planned")
                    SocialGridStat(value: liveCount, label: "Live")
                    SocialGridStat(value: mediaCount, label: "With media")
                }
            }
        }
        .padding(.horizontal, isCompact ? AgentSpacing.x4 : AgentSpacing.x5)
        .padding(.vertical, isCompact ? AgentSpacing.x4 : 0)
        .frame(minHeight: isCompact ? 116 : 88)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel, role: .structural)
    }

    private var identityRow: some View {
        HStack(spacing: AgentSpacing.x3) {
            CreatorAvatar(identity: identity, size: isCompact ? 44 : 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.greetingName)
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                Text(accountLabel)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SocialGridStat: View {
    let value: Int
    let label: String
    var isCompact = false

    var body: some View {
        VStack(alignment: isCompact ? .center : .trailing, spacing: 2) {
            Text(value, format: .number)
                .font(.agentHeadline)
                .monospacedDigit()
                .foregroundStyle(Color.agentText)
            Text(label)
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(
            minWidth: isCompact ? 0 : 70,
            maxWidth: isCompact ? .infinity : nil,
            alignment: isCompact ? .center : .trailing
        )
    }
}

private struct SocialGridTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: SocialGridDisplayItem
    let pillarColorHex: String?
    let isArranging: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void

    var body: some View {
        // The geometry reader owns the exact 3:4 cell. Constraining the composed
        // tile—not only the image—prevents portrait media from drawing outside
        // its LazyVGrid row.
        GeometryReader { proxy in
            ZStack {
                NavigationLink {
                    ScheduledPostDetailView(brief: item.brief, output: item.output)
                } label: {
                    tileVisual(size: proxy.size)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .buttonStyle(.plain)
                .disabled(isArranging)
                .accessibilityHidden(isArranging)
                .accessibilityLabel(accessibilityLabel)

                if isArranging {
                    Color.agentPureBlack.opacity(0.38)

                    HStack(spacing: AgentSpacing.x3) {
                        SocialGridMoveButton(
                            title: "Move earlier",
                            icon: .back,
                            isEnabled: canMoveEarlier,
                            action: moveEarlier
                        )
                        SocialGridMoveButton(
                            title: "Move later",
                            icon: .forward,
                            isEnabled: canMoveLater,
                            action: moveLater
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(SocialGridLayoutPolicy.tileWidthToHeightRatio, contentMode: .fit)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(
                    colorScheme == .dark
                        ? Color.agentPureWhite.opacity(0.10)
                        : Color.agentPureBlack.opacity(0.10),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func tileVisual(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let data = item.attachment?.cloudData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                placeholder
                    .frame(width: size.width, height: size.height)
            }

            HStack(spacing: AgentSpacing.x2) {
                AgentIconView(item.output.status == .posted ? .external : .calendar, size: 12)
                Text(statusLabel)
                    .font(.agentMetadata)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.agentPureWhite)
            .padding(.horizontal, AgentSpacing.x3)
            .frame(minHeight: 28)
            .background(Color.agentPureBlack.opacity(0.58), in: .capsule)
            .padding(AgentSpacing.x3)
            .zIndex(1)
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .clipped()
        .contentShape(.rect)
    }

    private var placeholder: some View {
        ZStack {
            Color(agentHex: pillarColorHex ?? "D8D4CA")
                .opacity(colorScheme == .dark ? 0.28 : 0.46)

            VStack(spacing: AgentSpacing.x3) {
                AgentIconView(item.attachment?.kind == .video ? .play : .image, size: 22)
                    .foregroundStyle(Color.agentText.opacity(0.72))
                Text(SocialGridTextPolicy.nonempty(item.brief.firstFrameText) ?? item.brief.title)
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, AgentSpacing.x4)
            }
        }
    }

    private var statusLabel: String {
        if item.output.status == .posted {
            return item.output.postedAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "Live"
        }
        return item.output.targetDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "Planned"
    }

    private var accessibilityLabel: String {
        "\(item.brief.title), \(item.output.status == .posted ? "live" : "planned"), \(statusLabel)"
    }
}

private struct SocialGridMoveButton: View {
    let title: String
    let icon: AgentIcon
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AgentIconView(icon, size: 14)
                .foregroundStyle(Color.agentPureWhite)
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .frame(width: 40, height: 40)
        .glassEffect(.clear.interactive(), in: .circle)
        .overlay {
            Circle()
                .stroke(Color.agentPureWhite.opacity(0.26), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.36)
        .accessibilityLabel(title)
    }
}

private struct SocialGridAddLivePostView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var allOutputs: [PlatformOutput]
    @State private var urlText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var urlIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add live post")
                    .font(.agentHeadline)
                Spacer()
                AgentToolbarIconButton(title: "Close", icon: .close) {
                    dismiss()
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x5)
            .padding(.bottom, AgentSpacing.x4)

            Rectangle().fill(Color.agentHairline).frame(height: 1)

            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                EditorialHeader(
                    kicker: "Already published",
                    title: "Bring it into your grid.",
                    subtitle: "Paste an Instagram post or Reel link. agent.cy will pull its available thumbnail and keep the original link attached."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Instagram link")
                    TextField("https://www.instagram.com/p/…", text: $urlText)
                        .font(.agentBody)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 52)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(errorMessage == nil ? Color.agentBorder : Color.agentDestructive, lineWidth: 1)
                        }
                        .focused($urlIsFocused)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentDestructive)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    Task { await addPost() }
                } label: {
                    HStack(spacing: AgentSpacing.x3) {
                        if isSaving { ProgressView().controlSize(.small) }
                        Text(isSaving ? "Adding post" : "Add to grid")
                    }
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.actionAccent, in: .rect(cornerRadius: AgentRadius.control))
                }
                .buttonStyle(AgentPressButtonStyle())
                .disabled(isSaving || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(AgentSpacing.x6)
        }
        .task {
            urlIsFocused = true
        }
    }

    @MainActor
    private func addPost() async {
        guard !isSaving else { return }
        guard let url = SocialGridURLPolicy.instagramURL(from: urlText) else {
            errorMessage = "Paste a valid Instagram post or Reel link."
            return
        }
        let workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) ?? appModel.resolvedWorkspaceID(context: modelContext)
        guard !allOutputs.contains(where: {
            $0.publishedURLString.trimmingCharacters(in: .whitespacesAndNewlines) == url.absoluteString
                && WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: workspaceID,
                    workspaces: workspaces
                )
        }) else {
            errorMessage = "That post is already in your grid."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let metadata = try? await PostLinkMetadataService().fetch(url: url, platform: .instagram)
        let now = Date()

        let brief = CreativeBrief(
            title: SocialGridURLPolicy.title(from: metadata?.title),
            source: .text,
            status: .posted,
            createdAt: now
        )
        brief.workspaceID = workspaceID
        brief.ideaBankPlacement = .post

        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            status: .posted,
            createdAt: now
        )
        output.workspaceID = workspaceID
        output.postedAt = now
        output.publishedURLString = url.absoluteString

        modelContext.insert(brief)
        modelContext.insert(output)

        if let thumbnailData = metadata?.thumbnailData {
            let attachment = CreatorAttachment(
                ownerKind: .postMedia,
                briefID: brief.id,
                platformOutputID: output.id,
                fileName: "published-thumbnail-\(output.id.uuidString.prefix(8)).jpg",
                kind: .photo,
                uniformTypeIdentifier: "public.image",
                byteCount: Int64(thumbnailData.count),
                localRelativePath: "",
                cloudData: thumbnailData,
                syncState: .synced
            )
            attachment.workspaceID = workspaceID
            modelContext.insert(attachment)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "This post could not be added. Try again."
        }
    }
}
