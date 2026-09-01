import SwiftData
import SwiftUI

/// Desktop review workspace for queued MCP changes.
///
/// Replaces the three-stage series wizard (`MCPSeriesReviewFlow`) on desktop.
/// The wizard hid the roster behind stage transitions, so the series and its
/// episodes were never visible at the same time. Here the queue stays in a
/// persistent sidebar and the detail pane swaps, so nothing is hidden behind a
/// step and any item is one click away.
struct MCPDesktopReviewView: View {
    private enum Selection: Hashable {
        case series(UUID)
        case episode(UUID)
        case idea(UUID)
        case other(UUID)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingSeries: [ContentSeries]
    @Query private var allPillars: [Pillar]

    let requests: [MCPBridgeChangeRequest]
    /// Returns to the conversation. The workspace renders inside Cy's own
    /// surface rather than a second sheet, so this is a back action, not a
    /// modal dismissal.
    var onClose: (() -> Void)?
    let onQueueChanged: () -> Void

    @State private var bundles: [MCPSeriesReviewBundle] = []
    @State private var ideas: [MCPBridgeChangeRequest] = []
    /// Episodes whose series is already approved, so no pending series bundle
    /// exists to hold them. Without this they disappear from the queue entirely.
    @State private var looseEpisodes: [MCPBridgeChangeRequest] = []
    /// Every proposal that is not a series, episode, or idea — post drafts,
    /// schedule changes, tasks, partners. Without this bucket they were counted
    /// by Cy but never listed here, so they looked lost.
    @State private var otherRequests: [MCPBridgeChangeRequest] = []
    @State private var taskRequests: [MCPBridgeChangeRequest] = []
    @State private var selection: Selection?
    @State private var editingPayload: MCPBridgeRequestPayload?
    @State private var editingEpisodeID: UUID?
    // Never inserted into the model context, so an abandoned edit cannot leave
    // a phantom post behind.
    @State private var scratchBrief: CreativeBrief?
    @State private var scratchOutput: PlatformOutput?
    @State private var denyTarget: MCPSeriesReviewBundle?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let scratchBrief, let scratchOutput {
                // The editor takes over this same surface. It used to be a
                // sheet on top of a sheet, which left no obvious way back.
                editorSurface(brief: scratchBrief, output: scratchOutput)
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Color.agentHairline)
                    HStack(spacing: 0) {
                        sidebar
                            .frame(width: 332)
                            .background(Color.agentSurface)
                        Divider().overlay(Color.agentHairline)
                        detail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.agentCanvas)
                    }
                }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: requests.map(\.id)) { _, _ in rebuild() }
        .confirmationDialog(
            denyTitle,
            isPresented: Binding(
                get: { denyTarget != nil },
                set: { if !$0 { denyTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(denyConfirmLabel, role: .destructive) {
                if let target = denyTarget { denyBundle(target) }
            }
            Button("Keep reviewing", role: .cancel) { denyTarget = nil }
        } message: {
            Text("This rejects the series and every episode queued under it. It cannot be undone from here.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The post editor rendered in place with this view's own Back/Save header.
    /// The editor's built-in rail is suppressed so only one header shows.
    private func editorSurface(brief: CreativeBrief, output: PlatformOutput) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { clearScratch() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.footnote.weight(.semibold))
                        Text("Back")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.agentText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to review")

                Spacer()

                Button("Save") { commitEdit() }
                    .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.agentSurface)

            Divider().overlay(Color.agentHairline)

            ResumablePostEditorView(
                brief: brief,
                output: output,
                contextLabel: "Edit before approval",
                isReviewEditing: true,
                bottomActionClearance: AgentSpacing.x3,
                showsEditorChrome: false,
                onSpark: {}
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.semibold))
                    Text("Back to Cy")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.agentText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Cy")

            Spacer()

            Text(totalPending == 1 ? "1 proposal" : "\(totalPending) proposals")
                .font(.footnote)
                .foregroundStyle(Color.agentSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.agentSurface)
    }

    private var totalPending: Int {
        bundles.count + allEpisodes.count + ideas.count + otherRequests.count + taskRequests.count
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                sidebarSection(
                    title: "Series",
                    count: bundles.count,
                    isEmpty: bundles.isEmpty,
                    emptyLabel: "No series waiting"
                ) {
                    ForEach(bundles) { bundle in
                        sidebarRow(
                            title: seriesName(bundle),
                            subtitle: bundle.episodes.isEmpty
                                ? "No episodes yet"
                                : "\(bundle.episodes.count) episode\(bundle.episodes.count == 1 ? "" : "s")",
                            isSelected: selection == .series(bundle.id)
                        ) {
                            selection = .series(bundle.id)
                        }
                    }
                }

                sidebarSection(
                    title: "Episodes",
                    count: allEpisodes.count,
                    isEmpty: allEpisodes.isEmpty,
                    emptyLabel: "No episodes waiting"
                ) {
                    ForEach(allEpisodes, id: \.id) { episode in
                        cardRow(episode, isSelected: selection == .episode(episode.id)) {
                            selection = .episode(episode.id)
                        }
                    }
                }

                sidebarSection(
                    title: "Posts",
                    count: otherRequests.count,
                    isEmpty: otherRequests.isEmpty,
                    emptyLabel: "No posts waiting"
                ) {
                    ForEach(otherRequests, id: \.id) { request in
                        cardRow(request, isSelected: selection == .other(request.id)) {
                            selection = .other(request.id)
                        }
                    }
                }

                sidebarSection(
                    title: "Tasks",
                    count: taskRequests.count,
                    isEmpty: taskRequests.isEmpty,
                    emptyLabel: "No tasks waiting"
                ) {
                    ForEach(taskRequests, id: \.id) { request in
                        cardRow(request, isSelected: selection == .other(request.id)) {
                            selection = .other(request.id)
                        }
                    }
                }

                sidebarSection(
                    title: "Ideas",
                    count: ideas.count,
                    isEmpty: ideas.isEmpty,
                    emptyLabel: "No ideas waiting"
                ) {
                    ForEach(ideas, id: \.id) { idea in
                        cardRow(idea, isSelected: selection == .idea(idea.id)) {
                            selection = .idea(idea.id)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(
        title: String,
        count: Int,
        isEmpty: Bool,
        emptyLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.agentSecondary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.agentSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(count) waiting")

            if isEmpty {
                Text(emptyLabel)
                    .font(.footnote)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, 6)
            } else {
                content()
            }
        }
    }

    /// Mirrors the phone's review card so a proposal reads the same on both
    /// platforms and matches the agenda's post cards.
    private func cardRow(
        _ request: MCPBridgeChangeRequest,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let pillar = pillarFor(request)
        let accent = pillar.map { Color(agentHex: $0.resolvedColorHex(in: activePillars)) }
            ?? Color.agentSecondary
        let platform = request.payload.platform
            .flatMap(CreatorPlatform.init(rawValue:))?.shortTitle
            ?? readableType(request.type)
        let date = request.payload.targetDate
        let metadata = date.map {
            "\(platform) · \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        } ?? platform

        return Button(action: action) {
            AgentPostCard(
                title: request.payload.title ?? request.payload.name ?? "Untitled proposal",
                pillar: pillar?.name ?? "Unfiled",
                accent: accent,
                status: .ready,
                metadata: metadata,
                timeText: request.payload.includesTargetTime == false
                    ? nil
                    : date?.formatted(date: .omitted, time: .shortened),
                statusTextOverride: "To review"
            )
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.agentSelectionFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var activePillars: [Pillar] { allPillars.filter { !$0.isArchived } }

    /// Episodes inherit their series' pillar.
    private func pillarFor(_ request: MCPBridgeChangeRequest) -> Pillar? {
        let seriesPillarID = request.payload.seriesId.flatMap { id in
            existingSeries.first(where: { $0.id == id })?.pillarID
        }
        let pillarID = request.payload.pillarId ?? seriesPillarID
        return pillarID.flatMap { id in activePillars.first { $0.id == id } }
    }

    private func sidebarRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.agentText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.agentSelectionFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .series(let id):
            if let bundle = bundles.first(where: { $0.id == id }) {
                seriesDetail(bundle)
            } else {
                placeholder("That series is no longer in the queue.")
            }
        case .episode(let id):
            if let episode = allEpisodes.first(where: { $0.id == id }) {
                episodeDetail(episode)
            } else {
                placeholder("That episode is no longer in the queue.")
            }
        case .other(let id):
            if let request = (otherRequests + taskRequests).first(where: { $0.id == id }) {
                otherDetail(request)
            } else {
                placeholder("That proposal is no longer in the queue.")
            }
        case .idea(let id):
            if let idea = ideas.first(where: { $0.id == id }) {
                ideaDetail(idea)
            } else {
                placeholder("That idea is no longer in the queue.")
            }
        case nil:
            placeholder("Select something on the left to review it.")
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.agentSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func seriesDetail(_ bundle: MCPSeriesReviewBundle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(seriesName(bundle))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                    Text(seriesSummary(bundle))
                        .font(.footnote)
                        .foregroundStyle(Color.agentSecondary)
                }

                // Actions sit above the roster: the decision applies to
                // everything listed below it.
                HStack(spacing: 12) {
                    Button(approveLabel(bundle)) { approveBundle(bundle) }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                        .fixedSize(horizontal: true, vertical: false)

                    Button(role: .destructive) {
                        denyTarget = bundle
                    } label: {
                        Text(denyLabel(bundle))
                    }
                    .buttonStyle(AgentQuietDestructiveButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()
                }

                Divider().overlay(Color.agentHairline)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Episodes in this approval")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.agentText)

                    if bundle.episodes.isEmpty {
                        Text("No episodes are queued under this series. Approving ships the series on its own.")
                            .font(.footnote)
                            .foregroundStyle(Color.agentSecondary)
                    } else {
                        ForEach(bundle.episodes, id: \.id) { episode in
                            Button {
                                selection = .episode(episode.id)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(episode.payload.title ?? "Untitled episode")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.agentText)
                                        Text(episodeSubtitle(episode))
                                            .font(.caption)
                                            .foregroundStyle(Color.agentSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.agentSecondary)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.agentSurface)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this episode to edit or remove it")
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func episodeDetail(_ episode: MCPBridgeChangeRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.payload.title ?? "Untitled episode")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                    Text(episodeSubtitle(episode))
                        .font(.footnote)
                        .foregroundStyle(Color.agentSecondary)
                }

                HStack(spacing: 12) {
                    Button("Edit episode") { beginEdit(episode) }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                        .fixedSize(horizontal: true, vertical: false)

                    // An episode whose series is already approved has no bundle
                    // to ride along with, so it needs its own approve action.
                    if isLoose(episode) {
                        Button("Approve episode") { approveSingle(episode) }
                            .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Button(role: .destructive) {
                        removeEpisode(episode)
                    } label: {
                        Text(isLoose(episode) ? "Deny episode" : "Remove from approval")
                    }
                    .buttonStyle(AgentQuietDestructiveButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()
                }

                Text(isLoose(episode)
                     ? "This episode's series is already approved, so it is approved on its own."
                     : "Edits are kept here and ship when you approve the series. Removing takes it out of this approval.")
                    .font(.footnote)
                    .foregroundStyle(Color.agentSecondary)

                Divider().overlay(Color.agentHairline)

                VStack(alignment: .leading, spacing: 14) {
                    field("Hook", episode.payload.hook)
                    field("Premise", episode.payload.premise)
                    field("Notes", episode.payload.notes)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func otherDetail(_ request: MCPBridgeChangeRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.payload.title ?? request.payload.name ?? "Untitled proposal")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                    Text(readableType(request.type))
                        .font(.footnote)
                        .foregroundStyle(Color.agentSecondary)
                }

                // Equal halves: approving and denying carry the same weight.
                HStack(spacing: 12) {
                    Button("Approve") { approveSingle(request) }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                        .frame(maxWidth: .infinity)

                    Button(role: .destructive) { rejectSingle(request) } label: {
                        Text("Deny")
                    }
                    .buttonStyle(AgentQuietDestructiveButtonStyle())
                    .frame(maxWidth: .infinity)
                }

                Divider().overlay(Color.agentHairline)

                VStack(alignment: .leading, spacing: 14) {
                    field("Hook", request.payload.hook)
                    field("Premise", request.payload.premise)
                    field("Caption", request.payload.caption)
                    field("Call to action", request.payload.callToAction)
                    field("Notes", request.payload.notes)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readableType(_ type: String) -> String {
        switch type {
        case "createPostDraft": "Post draft"
        case "updatePost": "Post update"
        case "schedulePost": "Schedule"
        case "reschedulePost": "Reschedule"
        case "markPostPosted": "Mark posted"
        case "addTask": "Task"
        case "completeTask": "Task completion"
        case "createBrandPartner", "updateBrandPartner": "Brand partner"
        case "makeAnchorPillar": "Anchor pillar"
        default: "Proposal"
        }
    }

    private func ideaDetail(_ idea: MCPBridgeChangeRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(idea.payload.title ?? "Untitled idea")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.agentText)

                HStack(spacing: 12) {
                    Button("Approve idea") { approveSingle(idea) }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                        .fixedSize(horizontal: true, vertical: false)

                    Button(role: .destructive) {
                        rejectSingle(idea)
                    } label: {
                        Text("Deny idea")
                    }
                    .buttonStyle(AgentQuietDestructiveButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()
                }

                Divider().overlay(Color.agentHairline)
                field("Notes", idea.payload.notes)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.agentSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Derived values

    private func isLoose(_ episode: MCPBridgeChangeRequest) -> Bool {
        looseEpisodes.contains { $0.id == episode.id }
    }

    private var allEpisodes: [MCPBridgeChangeRequest] {
        bundles.flatMap(\.episodes) + looseEpisodes
    }

    private var editingPayloadBinding: Binding<MCPBridgeRequestPayload>? {
        guard editingPayload != nil else { return nil }
        return Binding(
            get: { editingPayload ?? MCPBridgeRequestPayload() },
            set: { editingPayload = $0 }
        )
    }

    private var denyTitle: String {
        guard let denyTarget else { return "Deny this series?" }
        return "Deny \(seriesName(denyTarget))?"
    }

    private var denyConfirmLabel: String {
        guard let denyTarget, !denyTarget.episodes.isEmpty else { return "Deny series" }
        return "Deny series and \(denyTarget.episodes.count) episode\(denyTarget.episodes.count == 1 ? "" : "s")"
    }

    private func seriesName(_ bundle: MCPSeriesReviewBundle) -> String {
        bundle.series.payload.name ?? bundle.series.payload.title ?? "Untitled series"
    }

    private func seriesSummary(_ bundle: MCPSeriesReviewBundle) -> String {
        let count = bundle.episodes.count
        if count == 0 { return "Series · no episodes queued" }
        return "Series · \(count) episode\(count == 1 ? "" : "s") ship with this approval"
    }

    private func approveLabel(_ bundle: MCPSeriesReviewBundle) -> String {
        bundle.episodes.isEmpty
            ? "Approve series"
            : "Approve series + \(bundle.episodes.count) episode\(bundle.episodes.count == 1 ? "" : "s")"
    }

    private func denyLabel(_ bundle: MCPSeriesReviewBundle) -> String {
        bundle.episodes.isEmpty ? "Deny series" : "Deny all"
    }

    /// Name of the series this episode belongs to, whether that series is
    /// still queued or already approved.
    private func seriesName(for episode: MCPBridgeChangeRequest) -> String? {
        guard let seriesID = episode.payload.seriesId else { return nil }
        if let queued = bundles.first(where: { $0.series.payload.seriesId == seriesID }) {
            return seriesName(queued)
        }
        return existingSeries.first(where: { $0.id == seriesID })?.name
    }

    private func episodeSubtitle(_ episode: MCPBridgeChangeRequest) -> String {
        var parts: [String] = []
        if let name = seriesName(for: episode) { parts.append(name) }
        if let number = episode.payload.episodeNumber { parts.append("Episode \(number)") }
        if let date = episode.payload.targetDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.isEmpty ? "Episode" : parts.joined(separator: " · ")
    }

    // MARK: - Queue mutation

    private func rebuild() {
        let seriesRequests = requests.filter { $0.type == "createSeries" }
        let episodeRequests = requests.filter { $0.type == "createSeriesEpisode" }
        bundles = seriesRequests.map { series in
            let seriesID = series.payload.seriesId ?? series.id
            return MCPSeriesReviewBundle(
                series: series,
                episodes: episodeRequests.filter { $0.payload.seriesId == seriesID }
            )
        }
        let bundledIDs = Set(bundles.flatMap { $0.episodes.map(\.id) })
        looseEpisodes = episodeRequests.filter { !bundledIDs.contains($0.id) }
        ideas = requests.filter { $0.type == "createIdea" }
        let handled: Set<String> = ["createSeries", "createSeriesEpisode", "createIdea"]
        let taskTypes: Set<String> = ["addTask", "completeTask"]
        taskRequests = requests.filter { taskTypes.contains($0.type) }
        otherRequests = requests.filter { !handled.contains($0.type) && !taskTypes.contains($0.type) }
    }

    private func beginEdit(_ episode: MCPBridgeChangeRequest) {
        editingEpisodeID = episode.id
        editingPayload = episode.payload

        let brief = CreativeBrief(
            title: episode.payload.title ?? "Untitled episode",
            premise: episode.payload.premise ?? ""
        )
        brief.spokenHook = episode.payload.hook ?? ""
        brief.notes = episode.payload.notes ?? ""
        brief.seriesID = episode.payload.seriesId
        brief.pillarID = episode.payload.seriesId.flatMap { id in
            existingSeries.first(where: { $0.id == id })?.pillarID
        }

        let platform = episode.payload.platform.flatMap(CreatorPlatform.init(rawValue:)) ?? .instagramReels
        let output = PlatformOutput(briefID: brief.id, platform: platform)
        output.targetDate = episode.payload.targetDate

        scratchBrief = brief
        scratchOutput = output
    }

    private func clearScratch() {
        scratchBrief = nil
        scratchOutput = nil
        editingPayload = nil
        editingEpisodeID = nil
    }

    /// Keeps the edited payload in the bundle so it ships on approval.
    private func commitEdit() {
        guard let id = editingEpisodeID, var payload = editingPayload else { return }
        if let brief = scratchBrief {
            payload.title = brief.title
            payload.premise = brief.premise
            payload.hook = brief.spokenHook
            payload.notes = brief.notes
        }
        if let output = scratchOutput {
            payload.targetDate = output.targetDate
            payload.platform = output.platform.rawValue
        }
        for index in bundles.indices {
            guard let episodeIndex = bundles[index].episodes.firstIndex(where: { $0.id == id }) else {
                continue
            }
            // `payload` is a `let` on the request, so carry the edit into a
            // replacement that keeps the original envelope intact.
            let original = bundles[index].episodes[episodeIndex]
            bundles[index].episodes[episodeIndex] = MCPBridgeChangeRequest(
                schemaVersion: original.schemaVersion,
                id: original.id,
                createdAt: original.createdAt,
                source: original.source,
                workspaceId: original.workspaceId,
                externalPlan: original.externalPlan,
                type: original.type,
                payload: payload
            )
        }
        if let looseIndex = looseEpisodes.firstIndex(where: { $0.id == id }) {
            let original = looseEpisodes[looseIndex]
            looseEpisodes[looseIndex] = MCPBridgeChangeRequest(
                schemaVersion: original.schemaVersion,
                id: original.id,
                createdAt: original.createdAt,
                source: original.source,
                workspaceId: original.workspaceId,
                externalPlan: original.externalPlan,
                type: original.type,
                payload: payload
            )
        }
        clearScratch()
    }

    private func removeEpisode(_ episode: MCPBridgeChangeRequest) {
        do {
            try MCPBridgeService.reject(episode, decisionNote: "Removed during desktop review.")
            for index in bundles.indices {
                bundles[index].episodes.removeAll { $0.id == episode.id }
            }
            looseEpisodes.removeAll { $0.id == episode.id }
            selection = bundles.first(where: { bundle in
                bundle.series.payload.seriesId == episode.payload.seriesId
            }).map { .series($0.id) }
            onQueueChanged()
        } catch {
            present(error, action: "That episode")
        }
    }

    private func approveBundle(_ bundle: MCPSeriesReviewBundle) {
        do {
            try MCPBridgeService.approve(bundle.requests, context: context)
            bundles.removeAll { $0.id == bundle.id }
            selection = nil
            onQueueChanged()
        } catch {
            present(error, action: "The series")
        }
    }

    private func denyBundle(_ bundle: MCPSeriesReviewBundle) {
        do {
            for request in bundle.requests {
                try MCPBridgeService.reject(request, decisionNote: "Denied during desktop review.")
            }
            bundles.removeAll { $0.id == bundle.id }
            selection = nil
            denyTarget = nil
            onQueueChanged()
        } catch {
            present(error, action: "The series")
        }
    }

    private func approveSingle(_ request: MCPBridgeChangeRequest) {
        do {
            try MCPBridgeService.approve([request], context: context)
            ideas.removeAll { $0.id == request.id }
            looseEpisodes.removeAll { $0.id == request.id }
            otherRequests.removeAll { $0.id == request.id }
            taskRequests.removeAll { $0.id == request.id }
            taskRequests.removeAll { $0.id == request.id }
            selection = nil
            onQueueChanged()
        } catch {
            present(error, action: "That idea")
        }
    }

    private func rejectSingle(_ request: MCPBridgeChangeRequest) {
        do {
            try MCPBridgeService.reject(request, decisionNote: "Denied during desktop review.")
            ideas.removeAll { $0.id == request.id }
            otherRequests.removeAll { $0.id == request.id }
            selection = nil
            onQueueChanged()
        } catch {
            present(error, action: "That idea")
        }
    }

    private func present(_ error: Error, action: String) {
        errorMessage = CreatorFacingErrorMapper.presentation(for: error, action: action).message
    }
}

