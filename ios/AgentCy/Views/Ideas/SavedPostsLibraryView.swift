import SwiftData
import SwiftUI
import UIKit

enum SavedPostsPreviewPolicy {
    static let limit = 5

    static func preview(_ sources: [InspirationSource]) -> [InspirationSource] {
        Array(sources.prefix(limit))
    }
}

enum SavedPostRowAccessibilityPolicy {
    static func titleLineLimit(dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }

    static func metadataLineLimit(dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 1
    }
}

enum SavedPostPresentation {
    static func title(for source: InspirationSource) -> String {
        if source.saveMode != .originalOnly,
           let data = source.shapePayloadJSON.data(using: .utf8),
           let result = try? JSONDecoder.agentCy.decode(InspirationShapeResultWire.self, from: data) {
            let suggestion = result.idea.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !suggestion.isEmpty { return suggestion }
        }
        let title = source.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let caption = source.sourceCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty { return caption }
        let observation = source.creatorObservation.trimmingCharacters(in: .whitespacesAndNewlines)
        return observation.isEmpty ? "Saved \(platformName(source.platform)) post" : observation
    }

    static func metadata(for source: InspirationSource) -> String {
        let state = if source.saveMode == .originalOnly && !source.shapePayloadJSON.isEmpty {
            "Original saved"
        } else { switch source.status {
        case .pending: "Waiting to analyze"
        case .shaping: "Analyzing"
        case .ready: "Idea ready"
        case .failed: "Analysis needs attention"
        case .converted: "Idea created"
        } }
        let platform = platformName(source.platform)
        let attribution = source.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attribution.isEmpty,
              attribution.localizedCaseInsensitiveCompare(platform) != .orderedSame else {
            return "\(platform) · \(state)"
        }
        if attribution.localizedCaseInsensitiveContains(platform) {
            return "\(attribution) · \(state)"
        }
        return "\(attribution) · \(platform) · \(state)"
    }

    private static func platformName(_ platform: InspirationPlatform) -> String {
        switch platform {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .threads: "Threads"
        case .web: "Web"
        }
    }
}

struct SavedPostRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: InspirationSource
    let pillarName: String?
    let pillarColorHex: String?
    let showsDivider: Bool
    let open: () -> Void
    let openOriginal: () -> Void
    let requestDeletion: () -> Void
    var isSelecting = false
    var isSelected = false
    var toggleSelection: () -> Void = {}

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            if isSelecting {
                Button(action: toggleSelection) {
                    HStack(spacing: AgentSpacing.x3) {
                        AgentSelectionIndicator(isSelected: isSelected)
                        rowContent
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .agentHoverRow(cornerRadius: AgentRadius.control, bleed: AgentSpacing.x1)
                .accessibilityLabel(SavedPostPresentation.title(for: source))
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Toggles this saved post’s selection")
            } else {
                Button(action: open) {
                    rowContent
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .agentHoverRow(cornerRadius: AgentRadius.control, bleed: AgentSpacing.x1)
                .accessibilityLabel(SavedPostPresentation.title(for: source))
                .accessibilityValue(SavedPostPresentation.metadata(for: source))
                .accessibilityHint("Opens this saved post")

                Menu {
                    Button(action: openOriginal) {
                        AgentIconLabel(title: "Open original post", icon: .external)
                    }
                    Button(role: .destructive, action: requestDeletion) {
                        AgentIconLabel(title: "Delete saved post", icon: .trash)
                    }
                } label: {
                    AgentIconView(.more, size: 17)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Saved post actions")
            }
        }
        .padding(.vertical, AgentSpacing.x3)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: AgentSpacing.x3) {
            thumbnail
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(SavedPostPresentation.title(for: source))
                    .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.agentText)
                    .lineLimit(SavedPostRowAccessibilityPolicy.titleLineLimit(
                        dynamicTypeSize: dynamicTypeSize
                    ))
                Text(SavedPostPresentation.metadata(for: source))
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .textCase(.uppercase)
                    .lineLimit(SavedPostRowAccessibilityPolicy.metadataLineLimit(
                        dynamicTypeSize: dynamicTypeSize
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                if let pillarName, let pillarColorHex {
                    HStack(spacing: AgentSpacing.x2) {
                        PillarColorMark(color: Color(agentHex: pillarColorHex), diameter: 9)
                        Text(pillarName)
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = source.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
        } else {
            AgentIconView(.link, size: 15)
                .foregroundStyle(Color.actionAccent)
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        }
    }

    private var thumbnailWidth: CGFloat {
#if targetEnvironment(macCatalyst)
        72
#else
        58
#endif
    }

    private var thumbnailHeight: CGFloat {
#if targetEnvironment(macCatalyst)
        90
#else
        72
#endif
    }
}

struct SavedPostsLibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \InspirationSource.updatedAt, order: .reverse) private var allSources: [InspirationSource]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var search = ""
    @State private var pendingDeletion: InspirationSource?
    @State private var confirmsDeletion = false
    @State private var attemptedThumbnailSourceIDs: Set<UUID> = []
    @State private var showsLinkCapture = false

    private var sources: [InspirationSource] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return allSources.filter { source in
            let isVisible = SavedPostsScopePolicy.includes(
                recordWorkspaceID: source.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID
            )
            let pillar = pillar(for: source)
            return isVisible && (
                query.isEmpty ||
                    SavedPostPresentation.title(for: source).localizedStandardContains(query) ||
                    pillar?.name.localizedStandardContains(query) == true
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                #if targetEnvironment(macCatalyst)
                AgentPageRail(
                    breadcrumb: "Saved Posts",
                    identity: activeIdentity,
                    openSettings: { appModel.presentedSheet = .settings }
                )
                EditorialHeader(
                    kicker: "Library",
                    title: "Saved Posts",
                    subtitle: "Every reference saved from your phone or desktop, across your account."
                )
                #endif
                searchField
                SectionRuleHeader(title: "Saved Posts", trailing: "\(sources.count)")
                AgentBlockAddActionButton(title: "Save a post") {
                    showsLinkCapture = true
                }
                if sources.isEmpty {
                    AgentEmptyState(
                        title: search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "No saved posts yet"
                            : "No matching saved posts",
                        message: search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Posts you send to agent.cy will stay here for reference."
                            : "Try another title, platform, or pillar.",
                        icon: .link
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                            SavedPostRow(
                                source: source,
                                pillarName: pillar(for: source)?.name,
                                pillarColorHex: pillar(for: source)?.resolvedColorHex(in: allPillars),
                                showsDivider: index < sources.count - 1,
                                open: { appModel.openInspiration(source) },
                                openOriginal: { openOriginal(source) },
                                requestDeletion: { requestDeletion(source) }
                            )
                        }
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
                }
            }
            .padding(AgentLayout.pageMargin)
            #if targetEnvironment(macCatalyst)
            .padding(.top, AgentLayout.pageTopPadding)
            #endif
        }
        .background(Color.agentCanvas)
        #if targetEnvironment(macCatalyst)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationTitle("Saved Posts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .confirmationDialog(
            "Delete saved post?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { source in
            Button("Delete saved post", role: .destructive) { delete(source) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The saved reference will be removed. Any idea you already created from it will stay in your Idea Bank.")
        }
        .task(id: thumbnailHydrationKey) {
            await hydrateMissingThumbnails()
        }
        .sheet(isPresented: $showsLinkCapture) {
            SavedPostLinkCaptureView()
                .environment(appModel)
                .presentationDetents([.medium, .large])
                .agentSheetDragIndicator()
        }
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var searchField: some View {
        HStack(spacing: AgentSpacing.x3) {
            AgentIconView(.search, size: 15)
                .foregroundStyle(Color.agentSecondary)
            TextField("Search saved posts or pillars", text: $search)
                .font(.paperInter(size: 16, weight: .regular, relativeTo: .body))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 48)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

    private func pillar(for source: InspirationSource) -> Pillar? {
        guard let pillarID = source.pillarID else { return nil }
        return allPillars.first { $0.id == pillarID && $0.workspaceID == source.workspaceID }
    }

    private func openOriginal(_ source: InspirationSource) {
        guard let url = URL(string: source.canonicalURLString) else { return }
        openURL(url)
    }

    private func requestDeletion(_ source: InspirationSource) {
        pendingDeletion = source
        confirmsDeletion = true
    }

    private func delete(_ source: InspirationSource) {
        do {
            try InspirationDeletionCoordinator.delete(source, context: context)
            appModel.notice = .info("Saved post deleted.")
        } catch {
            appModel.presentCreatorError(error, action: "This saved post")
        }
        pendingDeletion = nil
    }

    private var thumbnailHydrationKey: String {
        SavedPostThumbnailHydrationPolicy.taskKey(
            workspaceKey: appModel.activeWorkspaceID?.uuidString ?? "legacy",
            missingSourceIDs: sources.filter { $0.thumbnailData == nil }.map(\.id)
        )
    }

    @MainActor
    private func hydrateMissingThumbnails() async {
        for source in sources where source.thumbnailData == nil {
            guard !Task.isCancelled,
                  attemptedThumbnailSourceIDs.insert(source.id).inserted
            else { continue }
            await SavedPostThumbnailHydrator().hydrate(source: source, context: context)
        }
    }
}

/// In-app "Save a post": a pasted link goes through the same canonicalization
/// as a shared one, and a link already saved to this account reopens the
/// existing reference instead of duplicating it.
enum SavedPostLinkCapturePolicy {
    enum Outcome: Equatable {
        case invalid
        case duplicate(existingID: UUID)
        case save(canonicalURLString: String, platform: InspirationPlatform)
    }

    static func outcome(
        rawLink: String,
        workspaceID: UUID?,
        existing sources: [InspirationSource]
    ) -> Outcome {
        var candidate = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.lowercased().hasPrefix("http://") {
            candidate = "https://" + candidate.dropFirst("http://".count)
        }
        guard let url = try? InspirationLinkCanonicalizer.canonicalize(candidate) else {
            return .invalid
        }
        if let existing = sources.first(where: {
            $0.workspaceID == workspaceID && $0.canonicalURLString == url.absoluteString
        }) {
            return .duplicate(existingID: existing.id)
        }
        return .save(
            canonicalURLString: url.absoluteString,
            platform: InspirationLinkCanonicalizer.platform(for: url)
        )
    }
}

struct SavedPostLinkCaptureView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \InspirationSource.updatedAt, order: .reverse) private var allSources: [InspirationSource]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var urlText = ""
    @State private var errorMessage: String?
    @FocusState private var linkIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Save a post")
                    .font(.agentHeadline)
                Spacer()
                Button(action: { dismiss() }) {
                    AgentIconView(.close, size: 16)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 40, height: 40)
                        .background(Color.agentSurface, in: .circle)
                        .overlay {
                            Circle()
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, AgentSpacing.x5)
            .agentQuickAddHeaderSurface()

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    Text("Paste an Instagram, TikTok, or YouTube link. agent.cy keeps it in Saved Posts and pulls any available thumbnail.")
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
                            .focused($linkIsFocused)
                            .onSubmit(save)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.agentMetadata)
                                .foregroundStyle(Color.agentDestructive)
                        }
                    }
                }
                .padding(AgentSpacing.x6)
                .frame(maxWidth: AgentQuickAddLayout.desktopContentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Color.agentHairline).frame(height: 1)

            HStack(spacing: AgentSpacing.x3) {
#if targetEnvironment(macCatalyst)
                Button("Cancel") { dismiss() }
                    .buttonStyle(AgentCompactSecondaryButtonStyle())
                Spacer(minLength: AgentSpacing.x4)
#endif
                Button(action: save) {
                    Text("Save post")
                }
                .buttonStyle(AgentPrimaryButtonStyle())
#if targetEnvironment(macCatalyst)
                .frame(width: 190)
#endif
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.vertical, AgentSpacing.x4)
        }
        .background(Color.agentCanvas)
#if targetEnvironment(macCatalyst)
        .frame(minWidth: 560, idealWidth: 620, maxWidth: 720, minHeight: 360, idealHeight: 400)
#endif
        .task {
            linkIsFocused = true
        }
    }

    private func save() {
        let workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        )
        switch SavedPostLinkCapturePolicy.outcome(
            rawLink: urlText,
            workspaceID: workspaceID,
            existing: allSources
        ) {
        case .invalid:
            errorMessage = "Paste a valid Instagram, TikTok, or YouTube link."
        case .duplicate(let existingID):
            dismiss()
            if let existing = allSources.first(where: { $0.id == existingID }) {
                appModel.notice = .info("Already saved — opening it.")
                appModel.openInspiration(existing)
            }
        case .save(let canonicalURLString, let platform):
            let source = InspirationSource(
                workspaceID: workspaceID,
                canonicalURLString: canonicalURLString,
                platform: platform
            )
            context.insert(source)
            do {
                try context.save()
                appModel.notice = .info("Post saved.")
                dismiss()
            } catch {
                context.delete(source)
                appModel.presentCreatorError(error, action: "Saving this post")
            }
        }
    }
}
