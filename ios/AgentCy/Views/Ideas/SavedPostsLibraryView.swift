import SwiftData
import SwiftUI
import UIKit

enum SavedPostsPreviewPolicy {
    static let limit = 5

    static func preview(_ sources: [InspirationSource]) -> [InspirationSource] {
        Array(sources.prefix(limit))
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
    let source: InspirationSource
    let pillarName: String?
    let pillarColorHex: String?
    let showsDivider: Bool
    let open: () -> Void
    let openOriginal: () -> Void
    let requestDeletion: () -> Void

    var body: some View {
        HStack(spacing: AgentSpacing.x2) {
            Button(action: open) {
                HStack(spacing: AgentSpacing.x3) {
                    thumbnail
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(SavedPostPresentation.title(for: source))
                            .font(.paperInter(size: 16, weight: .semibold, relativeTo: .headline))
                            .foregroundStyle(Color.agentText)
                            .lineLimit(2)
                        Text(SavedPostPresentation.metadata(for: source))
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentSecondary)
                            .textCase(.uppercase)
                            .lineLimit(1)
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
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open saved post")
            .accessibilityValue(SavedPostPresentation.title(for: source))

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
        .padding(.vertical, AgentSpacing.x3)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = source.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 72)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
        } else {
            AgentIconView(.link, size: 15)
                .foregroundStyle(Color.actionAccent)
                .frame(width: 58, height: 72)
                .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
        }
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
}
