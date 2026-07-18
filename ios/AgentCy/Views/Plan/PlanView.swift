import SwiftData
import SwiftUI

enum PlanMode: Sendable {
    case week
}

struct PlanView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0
    @State private var isSearchingPosts = false

    var body: some View {
        VStack(spacing: 0) {
            header

            AgendaView(
                weekOffset: $weekOffset,
                selectedDay: $selectedDay,
                showsHeader: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.agentCanvas.ignoresSafeArea())
        .onChange(of: appModel.requestedPlanMode, initial: true) { _, requestedMode in
            guard let requestedMode else { return }
            if requestedMode == .week, appModel.widgetAgendaDay == nil {
                returnToCurrentWeek()
            }
            appModel.requestedPlanMode = nil
        }
        .sheet(isPresented: $isSearchingPosts) {
            AgendaPostSearchView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            HStack(alignment: .center, spacing: AgentSpacing.x1) {
                MetaLabel("Weekly agenda")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    isSearchingPosts = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search posts")

                ProfileSettingsButton(
                    identity: activeIdentity,
                    action: { appModel.presentedSheet = .settings }
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x2) {
                Button {
                    returnToCurrentWeek()
                } label: {
                    Text("Today")
                        .font(.system(size: 32, weight: .semibold, design: .default))
                        .foregroundStyle(Color.cyAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to this week")
                .accessibilityHint("Shows the week containing today")

                Text("is \(todayTitleDate).")
                    .font(.system(size: 32, weight: .regular, design: .default))
                    .foregroundStyle(Color.agentText)
            }
            .tracking(-0.64)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var todayTitleDate: String {
        Date().formatted(.dateTime.month(.wide).day().year())
    }

    private func returnToCurrentWeek() {
        let update = {
            selectedDay = Calendar.current.startOfDay(for: Date())
            weekOffset = 0
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.snappy(duration: 0.28), update)
        }
    }

}

private struct AgendaPostSearchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var allOutputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var query = ""

    private var briefs: [CreativeBrief] {
        allBriefs.filter {
            $0.status != .archived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var pillars: [Pillar] {
        allPillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var outputs: [PlatformOutput] {
        let briefIDs = Set(briefs.map(\.id))
        return allOutputs.filter {
            briefIDs.contains($0.briefID) && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var results: [(PlatformOutput, CreativeBrief)] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return outputs.compactMap { output in
            guard let brief = brief(for: output) else { return nil }
            if !cleanQuery.isEmpty, !searchText(for: output, brief: brief).localizedStandardContains(cleanQuery) {
                return nil
            }
            return (output, brief)
        }
        .sorted { lhs, rhs in
            let left = lhs.0.targetDate ?? lhs.1.updatedAt
            let right = rhs.0.targetDate ?? rhs.1.updatedAt
            return left > right
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    searchField

                    SectionRuleHeader(
                        title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "All posts"
                            : "Results",
                        trailing: "\(results.count)"
                    )

                    if results.isEmpty {
                        ContentUnavailableView(
                            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "No posts yet"
                                : "No posts found",
                            systemImage: "magnifyingglass",
                            description: Text(
                                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Posts you create will appear here."
                                    : "Try another title, pillar, platform, or phrase."
                            )
                        )
                        .frame(minHeight: 300)
                    } else {
                        ForEach(results, id: \.0.id) { output, brief in
                            resultCard(output: output, brief: brief)
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Search posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .agentScreen()
        }
    }

    private var searchField: some View {
        HStack(spacing: AgentSpacing.x3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.agentSecondary)
            TextField("Search posts", text: $query)
                .font(.agentBody)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 48)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 0.75)
        }
    }

    private func resultCard(output: PlatformOutput, brief: CreativeBrief) -> some View {
        let pillar = pillar(for: brief)
        let missed = FinalizedPostPresentation.isMissed(
            outputStatus: output.status,
            targetDate: output.targetDate
        )
        return AgentPostCard(
            title: postTitle(output: output, brief: brief),
            pillar: pillar?.name ?? "Unfiled",
            accent: pillar.map { Color(agentHex: $0.resolvedColorHex(in: pillars)) } ?? .agentSecondary,
            status: output.status,
            metadata: platformLabel(for: output),
            timeText: output.targetDate?.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
            statusTextOverride: missed ? "Missed" : nil,
            destination: AnyView(PostOutputDetailView(brief: brief, output: output))
        )
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? {
        briefs.first { $0.id == output.briefID }
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        brief.pillarID.flatMap { id in pillars.first { $0.id == id } }
    }

    private func platformLabel(for output: PlatformOutput) -> String {
        if let id = output.destinationID, let destination = destinations.first(where: { $0.id == id }) {
            return destination.name
        }
        if let id = output.formatID, let format = formats.first(where: { $0.id == id }) {
            return format.name
        }
        return output.platform.title
    }

    private func postTitle(output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private func searchText(for output: PlatformOutput, brief: CreativeBrief) -> String {
        [
            output.titleOverride,
            brief.title,
            brief.notes,
            brief.spokenHook,
            brief.scriptBeatsText,
            brief.ctaIntent,
            output.caption,
            output.cta,
            platformLabel(for: output),
            pillar(for: brief)?.name ?? ""
        ].joined(separator: " ")
    }
}

struct PlanHeader<Actions: View>: View {
    let breadcrumb: String
    let identity: ActiveCreatorIdentity
    let firstLine: String
    let secondLine: String
    let openSettings: () -> Void
    let showsBreadcrumb: Bool
    @ViewBuilder let actions: Actions

    init(
        breadcrumb: String,
        identity: ActiveCreatorIdentity,
        firstLine: String,
        secondLine: String,
        openSettings: @escaping () -> Void,
        showsBreadcrumb: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.breadcrumb = breadcrumb
        self.identity = identity
        self.firstLine = firstLine
        self.secondLine = secondLine
        self.openSettings = openSettings
        self.showsBreadcrumb = showsBreadcrumb
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .center, spacing: AgentSpacing.x1) {
                if showsBreadcrumb {
                    MetaLabel(breadcrumb)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                actions
                ProfileSettingsButton(identity: identity, action: openSettings)
            }
            .frame(height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(firstLine)
                    .font(.system(size: 32, weight: .regular, design: .default))
                Text(secondLine)
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)

        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PlanHeader where Actions == EmptyView {
    init(
        breadcrumb: String,
        identity: ActiveCreatorIdentity,
        firstLine: String,
        secondLine: String,
        openSettings: @escaping () -> Void
    ) {
        self.init(
            breadcrumb: breadcrumb,
            identity: identity,
            firstLine: firstLine,
            secondLine: secondLine,
            openSettings: openSettings,
            showsBreadcrumb: true,
            actions: { EmptyView() }
        )
    }
}
