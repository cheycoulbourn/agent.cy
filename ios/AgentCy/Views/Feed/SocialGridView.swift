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

struct LivePostLinkDescriptor: Equatable {
    let url: URL
    let sourcePlatform: InspirationPlatform
    let creatorPlatform: CreatorPlatform
    let destinationID: UUID
    let formatID: UUID
    let fallbackTitle: String
}

enum LivePostLinkScope: Equatable {
    /// Agenda and the Creation Hub record live posts for every platform.
    case allPlatforms
    /// The Feed grid previews Instagram only; links it can never show are
    /// rejected honestly instead of saving invisible records.
    case instagramOnly

    func allows(_ descriptor: LivePostLinkDescriptor) -> Bool {
        switch self {
        case .allPlatforms: true
        case .instagramOnly: descriptor.sourcePlatform == .instagram
        }
    }

    var prompt: String {
        switch self {
        case .allPlatforms:
            "Paste an Instagram, TikTok, or YouTube link, then choose when it went live. agent.cy will place it on the right day and pull any available thumbnail."
        case .instagramOnly:
            "Paste an Instagram link, then choose when it went live. agent.cy will place it on this grid and pull any available thumbnail."
        }
    }

    var invalidLinkMessage: String {
        switch self {
        case .allPlatforms: "Paste a valid Instagram, TikTok, or YouTube link."
        case .instagramOnly: "Paste a valid Instagram link."
        }
    }

    var rejectionMessage: String {
        "This grid previews Instagram only. Add TikTok or YouTube posts from the Agenda or the create menu."
    }
}

enum LivePostURLPolicy {
    static func descriptor(from rawValue: String) -> LivePostLinkDescriptor? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        // The canonicalizer accepts https only; pasted http links stay valid.
        if candidate.lowercased().hasPrefix("http://") {
            candidate = "https://" + candidate.dropFirst("http://".count)
        }
        guard let url = try? InspirationLinkCanonicalizer.canonicalize(candidate) else { return nil }

        switch InspirationLinkCanonicalizer.platform(for: url) {
        case .instagram:
            return LivePostLinkDescriptor(
                url: url,
                sourcePlatform: .instagram,
                creatorPlatform: .instagramReels,
                destinationID: PublishingCatalog.instagramID,
                formatID: PublishingCatalog.instagramReelID,
                fallbackTitle: "Instagram post"
            )
        case .tiktok:
            return LivePostLinkDescriptor(
                url: url,
                sourcePlatform: .tiktok,
                creatorPlatform: .tiktok,
                destinationID: PublishingCatalog.tiktokID,
                formatID: PublishingCatalog.tiktokShortID,
                fallbackTitle: "TikTok post"
            )
        case .youtube:
            return LivePostLinkDescriptor(
                url: url,
                sourcePlatform: .youtube,
                creatorPlatform: .youtubeVideo,
                destinationID: PublishingCatalog.youtubeID,
                formatID: PublishingCatalog.youtubeVideoID,
                fallbackTitle: "YouTube post"
            )
        case .threads, .web:
            return nil
        }
    }

    static func defaultPostedAt(for suggestedDay: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let suggested = calendar.date(
            bySettingHour: components.hour ?? 12,
            minute: components.minute ?? 0,
            second: 0,
            of: suggestedDay
        ) ?? suggestedDay
        return min(suggested, now)
    }
}

enum LivePostDuplicatePolicy {
    static func containsDuplicate(
        url: URL,
        outputs: [PlatformOutput],
        workspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> Bool {
        let canonicalURL = url.absoluteString
        return outputs.contains { output in
            canonicalURLString(output.publishedURLString) == canonicalURL &&
                WorkspaceScope.includes(
                    output.workspaceID,
                    activeWorkspaceID: workspaceID,
                    workspaces: workspaces
                )
        }
    }

    private static func canonicalURLString(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if candidate.lowercased().hasPrefix("http://") {
            candidate = "https://" + candidate.dropFirst("http://".count)
        }
        return try? InspirationLinkCanonicalizer.canonicalize(candidate).absoluteString
    }
}

enum LivePostPersistenceError: Error {
    case duplicate
}

@MainActor
enum LivePostPersistenceService {
    struct Result {
        let brief: CreativeBrief
        let output: PlatformOutput
    }

    static func save(
        descriptor: LivePostLinkDescriptor,
        metadata: PostLinkMetadata?,
        postedAt: Date,
        workspaceID: UUID?,
        workspaces: [CreatorWorkspace],
        context: ModelContext
    ) throws -> Result {
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        guard !LivePostDuplicatePolicy.containsDuplicate(
            url: descriptor.url,
            outputs: outputs,
            workspaceID: workspaceID,
            workspaces: workspaces
        ) else {
            throw LivePostPersistenceError.duplicate
        }

        let accounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>(
            sortBy: [SortDescriptor(\CreatorSocialAccount.sortOrder)]
        ))
        let scopedAccounts = accounts.filter {
            $0.destinationID == descriptor.destinationID &&
                WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: workspaceID,
                    workspaces: workspaces
                ) && !$0.isArchived
        }
        let accountID = scopedAccounts.first(where: \.isPrimary)?.id ?? scopedAccounts.first?.id
        let now = Date()
        let brief = CreativeBrief(
            title: metadataTitle(metadata?.title, fallback: descriptor.fallbackTitle),
            source: .text,
            status: .posted,
            createdAt: now
        )
        brief.workspaceID = workspaceID
        brief.ideaBankPlacement = .post
        brief.agendaDate = postedAt

        let output = PlatformOutput(
            briefID: brief.id,
            platform: descriptor.creatorPlatform,
            destinationID: descriptor.destinationID,
            formatID: descriptor.formatID,
            socialAccountID: accountID,
            status: .posted,
            createdAt: now
        )
        output.workspaceID = workspaceID
        output.targetDate = postedAt
        output.includesTargetTime = true
        output.postedAt = postedAt
        output.publishedURLString = descriptor.url.absoluteString
        context.insert(brief)
        context.insert(output)

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
            output.coverAttachmentID = attachment.id
            context.insert(attachment)
        }

        do {
            try context.save()
            return Result(brief: brief, output: output)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func metadataTitle(_ value: String?, fallback: String) -> String {
        let title = SocialGridURLPolicy.title(from: value)
        return title == "Instagram post" ? fallback : title
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
    @State private var attemptedThumbnailOutputIDs: Set<UUID> = []
    @State private var isRefreshingFeed = false
    @State private var isHydratingThumbnails = false
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
        }
    }

    @ViewBuilder
    private var pageRail: some View {
        if presentation.isPhone {
            HStack(alignment: .center, spacing: AgentSpacing.x2) {
                AgentToolbarIconButton(title: "Back to Plan", icon: .back, action: dismiss.callAsFunction)

                Spacer(minLength: AgentSpacing.x4)

                HStack(spacing: AgentSpacing.x2) {
                    AgentToolbarIconButton(title: "Add live post", icon: .link) {
                        presentedSheet = .addLivePost
                    }
                    .accessibilityHint("Adds a published Instagram post to this grid")

                    Button {
                        Task { await refreshFeed() }
                    } label: {
                        AgentToolbarIconContainer {
                            if isRefreshingFeed {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.agentText)
                            } else {
                                AgentIconView(.refresh, size: AgentToolbarIconMetrics.glyph)
                                    .foregroundStyle(Color.agentText)
                            }
                        }
                    }
                    .buttonStyle(AgentPressButtonStyle())
                    .disabled(isRefreshingFeed)
                    .accessibilityLabel(isRefreshingFeed ? "Refreshing feed" : "Refresh feed")
                    .accessibilityHint("Loads newly synced posts and retries missing live post thumbnails")

                    ProfileSettingsButton(
                        identity: activeIdentity,
                        action: { appModel.presentedSheet = .settings }
                    )
                }
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
            isCompact: presentation.isPhone
        )
    }

    private var gridControls: some View {
        Picker("Feed posts", selection: $selectedFilter) {
            ForEach(SocialGridFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: presentation.isPhone ? .infinity : 320)
    }

    @ViewBuilder
    private var addLivePostSheet: some View {
        let content = AddLivePostView(linkScope: .instagramOnly)
            .environment(appModel)
            .modelContext(modelContext)
            .background(Color.agentCanvas)
            .presentationBackground(Color.agentCanvas)

        if presentation.isPhone {
            content
                .presentationDetents([.large])
                .agentSheetDragIndicator()
        } else {
            content
                .frame(width: 660, height: 720)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
            ForEach(visibleItems) { item in
                SocialGridTile(
                    item: item,
                    pillarColorHex: item.brief.pillarID.flatMap { pillarIndex[$0]?.colorHex }
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
        let mediaByOutputID = Dictionary(grouping: media) { $0.platformOutputID! }
        return defaultOutputIDs.reduce(into: [:]) { result, outputID in
            guard let candidates = mediaByOutputID[outputID],
                  let output = outputIndex[outputID]
            else { return }
            let coverID = PostMediaPresentationPolicy.resolvedCoverID(
                preferredID: output.coverAttachmentID,
                mediaIDs: candidates.map(\.id)
            )
            result[outputID] = candidates.first { $0.id == coverID }
        }
    }

    private var allItems: [SocialGridDisplayItem] {
        defaultOutputIDs.compactMap { outputID in
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
                  SocialGridURLPolicy.instagramURL(from: item.output.publishedURLString) != nil
            else { continue }

            await PublishedPostThumbnailHydrator().hydrate(
                brief: item.brief,
                output: item.output,
                context: modelContext
            )
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

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    identityRow

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

    var body: some View {
        // The geometry reader owns the exact 3:4 cell. Constraining the composed
        // tile—not only the image—prevents portrait media from drawing outside
        // its LazyVGrid row.
        GeometryReader { proxy in
            NavigationLink {
                ScheduledPostDetailView(brief: item.brief, output: item.output)
            } label: {
                tileVisual(size: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
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
            if let data = item.attachment?.previewData ?? item.attachment?.cloudData,
               let image = UIImage(data: data) {
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

struct AddLivePostView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let onDismiss: (() -> Void)?
    private let linkScope: LivePostLinkScope
    @State private var urlText = ""
    @State private var postedAt: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var urlIsFocused: Bool

    init(
        suggestedPostedAt: Date = Date(),
        linkScope: LivePostLinkScope = .allPlatforms,
        onDismiss: (() -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
        self.linkScope = linkScope
        _postedAt = State(initialValue: LivePostURLPolicy.defaultPostedAt(for: suggestedPostedAt))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add live post")
                    .font(.agentHeadline)
                Spacer()
                AgentToolbarIconButton(title: "Close", icon: .close, action: close)
            }
            .padding(.horizontal, AgentSpacing.x5)
            .agentQuickAddHeaderSurface()

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    Text(linkScope.prompt)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Post link")
                        TextField("https://…", text: $urlText)
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

                    publishedDateEditor
                }
                .padding(AgentSpacing.x6)
                .frame(maxWidth: AgentQuickAddLayout.desktopContentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .disabled(isSaving)

            Rectangle().fill(Color.agentHairline).frame(height: 1)

            HStack(spacing: AgentSpacing.x3) {
#if targetEnvironment(macCatalyst)
                Button("Cancel", action: close)
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .frame(minWidth: 100, minHeight: 44)
                    .buttonStyle(.plain)
                    .background(Color.agentSurface, in: .capsule)
                    .overlay(Capsule().stroke(Color.agentBorder, lineWidth: 1))
                Spacer(minLength: AgentSpacing.x4)
#endif
                Button {
                    addPost()
                } label: {
                    HStack(spacing: AgentSpacing.x3) {
                        if isSaving { ProgressView().controlSize(.small) }
                        Text(isSaving ? "Saving post" : "Save live post")
                    }
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(isSaving)
#if targetEnvironment(macCatalyst)
                .frame(width: 190)
#endif
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.vertical, AgentSpacing.x4)
        }
        .background(Color.agentCanvas)
#if targetEnvironment(macCatalyst)
        .frame(minWidth: 640, idealWidth: 680, maxWidth: 780, minHeight: 580, idealHeight: 680)
#endif
        .task {
            urlIsFocused = true
        }
    }

    @ViewBuilder
    private var publishedDateEditor: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Published")
                Spacer()
                Text(postedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .monospacedDigit()
            }

#if targetEnvironment(macCatalyst)
            HStack(alignment: .top, spacing: AgentSpacing.x5) {
                PillarCalendarDatePicker(
                    date: $postedAt,
                    pillarMarkers: [],
                    maximumDate: Date(),
                    cellHeight: 38,
                    dayDiameter: 32
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("Time")
                    Text(postedAt.formatted(date: .omitted, time: .shortened))
                        .font(.agentTitle)
                        .monospacedDigit()

                    timeAdjustment(
                        title: "Hour",
                        value: String(format: "%02d", Calendar.current.component(.hour, from: postedAt))
                    ) {
                        adjustTime(.hour, by: -1)
                    } increment: {
                        adjustTime(.hour, by: 1)
                    }

                    timeAdjustment(
                        title: "Minute",
                        value: String(format: "%02d", Calendar.current.component(.minute, from: postedAt))
                    ) {
                        adjustTime(.minute, by: -1)
                    } increment: {
                        adjustTime(.minute, by: 1)
                    }

                    Text("Use the time the post became public.")
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 180, alignment: .leading)
                .padding(.top, AgentSpacing.x1)
            }
#else
            DatePicker(
                "Published date",
                selection: $postedAt,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.graphical)

            HStack {
                MetaLabel("Time")
                Spacer()
                DatePicker(
                    "Published time",
                    selection: $postedAt,
                    in: ...Date(),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }
            .frame(minHeight: 44)
#endif
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.panel)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

#if targetEnvironment(macCatalyst)
    private func timeAdjustment(
        title: String,
        value: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            Text(title)
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
            Spacer(minLength: AgentSpacing.x2)
            Button(action: decrement) {
                Text("−")
                    .font(.agentHeadline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(Color.agentCanvas, in: .circle)
            .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))

            Text(value)
                .font(.agentSubtext.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 38)

            Button(action: increment) {
                Text("+")
                    .font(.agentHeadline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(Color.agentCanvas, in: .circle)
            .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
        }
        .frame(minHeight: 40)
    }

    private func adjustTime(_ component: Calendar.Component, by value: Int) {
        guard let adjusted = Calendar.current.date(byAdding: component, value: value, to: postedAt) else { return }
        postedAt = min(adjusted, Date())
    }
#endif

    @MainActor
    private func addPost() {
        guard !isSaving else { return }
        guard let descriptor = LivePostURLPolicy.descriptor(from: urlText) else {
            errorMessage = linkScope.invalidLinkMessage
            urlIsFocused = true
            return
        }
        guard linkScope.allows(descriptor) else {
            errorMessage = linkScope.rejectionMessage
            urlIsFocused = true
            return
        }
        let submittedPostedAt = postedAt
        guard PostedDatePolicy.isValid(submittedPostedAt) else {
            errorMessage = "A live post cannot have a future posted date."
            return
        }
        var currentWorkspaces: [CreatorWorkspace]
        do {
            currentWorkspaces = try modelContext.fetch(FetchDescriptor<CreatorWorkspace>(
                sortBy: [SortDescriptor(\CreatorWorkspace.sortOrder)]
            ))
        } catch {
            errorMessage = "This post could not be added. Try again."
            return
        }
        var workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: currentWorkspaces
        )
        if workspaceID == nil {
            workspaceID = appModel.resolvedWorkspaceID(context: modelContext)
            do {
                currentWorkspaces = try modelContext.fetch(FetchDescriptor<CreatorWorkspace>(
                    sortBy: [SortDescriptor(\CreatorWorkspace.sortOrder)]
                ))
            } catch {
                errorMessage = "This post could not be added. Try again."
                return
            }
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let result = try LivePostPersistenceService.save(
                descriptor: descriptor,
                metadata: nil,
                postedAt: submittedPostedAt,
                workspaceID: workspaceID,
                workspaces: currentWorkspaces,
                context: modelContext
            )
            Task { @MainActor in
                await Task.yield()
                WidgetSnapshotService.refresh(context: modelContext, workspaceID: workspaceID)
                if await PublishedPostThumbnailHydrator().hydrate(
                    brief: result.brief,
                    output: result.output,
                    context: modelContext
                ) != nil {
                    WidgetSnapshotService.refresh(context: modelContext, workspaceID: workspaceID)
                }
            }
            finishClose()
        } catch LivePostPersistenceError.duplicate {
            errorMessage = "That live post is already saved."
        } catch {
            errorMessage = "This post could not be added. Try again."
        }
    }

    private func close() {
        finishClose()
    }

    private func finishClose() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

}
