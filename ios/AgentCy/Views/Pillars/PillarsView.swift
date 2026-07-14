import SwiftData
import SwiftUI

private enum PillarsRoute: Hashable {
    case pillar(UUID)
    case idea(UUID)
    case brief(UUID)
}

struct PillarsView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]
    @Query private var profiles: [CreatorProfile]
    @State private var headerHeight: CGFloat = 0
    @State private var showNewPillar = false
    @State private var newPillarParentID: UUID?

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
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

                    PillarPaperSurface(minimumHeight: max(0, proxy.size.height - headerHeight)) {
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
                IdeaPostDraftView(brief: brief)
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
                    BriefDetailView(brief: brief)
                }
            } else {
                unavailableDestination
            }
        }
    }

    private var unavailableDestination: some View {
        ContentUnavailableView(
            "This item is no longer available",
            systemImage: "tray"
        )
        .agentScreen()
    }

    private var paperHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            AgentPageRail(
                breadcrumb: "§ Pillars",
                profile: profiles.first,
                openSettings: { appModel.presentedSheet = .settings }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Your")
                    .font(.system(size: 32, weight: .regular, design: .default))
                Text("pillars.")
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, 58)
    }

    private func anchorHero(_ anchor: Pillar) -> some View {
        let metrics = PillarMetrics(
            pillar: anchor,
            includesBranches: true,
            pillars: activePillars,
            briefs: briefs,
            outputs: outputs
        )

        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: AgentSpacing.x2) {
                PaperPillarMeta("Anchor", weight: .semibold, tracking: 1.6)
                Circle().fill(Color.agentText).frame(width: 3, height: 3)
                PaperPillarMeta(daySummary(anchor.assignedWeekdays))
            }

            NavigationLink(value: PillarsRoute.pillar(anchor.id)) {
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(agentHex: anchor.colorHex))
                        .frame(width: 16, height: 16)
                    Text(anchor.name)
                        .font(.paperInter(size: 32, weight: .medium, relativeTo: .title))
                        .tracking(-0.96)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
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
                labels: ["Idea bank", "This week", "Posted"]
            )
            .padding(.vertical, AgentSpacing.x4)
            .overlay(alignment: .top) { PaperHairline() }
            .overlay(alignment: .bottom) { PaperHairline() }

        }
    }

    private func branchesSection(anchor: Pillar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AgentSpacing.x2) {
                PaperPillarMeta("Branches", weight: .semibold, tracking: 1.6)
                PaperHairline().frame(maxWidth: .infinity)
                PaperPillarMeta("Extensions of you", tracking: 1)
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

            PillarInlineAddAction(title: "Add a branch") {
                newPillarParentID = anchor.id
                showNewPillar = true
            }
        }
    }

    private var emptyAnchor: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            PaperPillarMeta("Anchor")
            Text("Start with the idea everything leads back to.")
                .font(.paperInter(size: 28, weight: .medium, relativeTo: .title))
                .tracking(-0.7)
            Text("Your anchor is the central focus. Branches support it without replacing it.")
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

private struct PillarInlineAddAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(Color.agentSecondary, style: StrokeStyle(lineWidth: 1.25, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.paperInter(size: 17, weight: .medium, relativeTo: .body))
                    .tracking(-0.25)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.agentText)
            .frame(minHeight: 66)
            .overlay(alignment: .bottom) { PaperHairline() }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct PillarBranchRow: View {
    let pillar: Pillar
    let metrics: PillarMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 10) {
                    Circle().fill(Color(agentHex: pillar.colorHex)).frame(width: 10, height: 10)
                    Text(pillar.name)
                        .font(.paperInter(size: 17, weight: .semibold, relativeTo: .headline))
                        .tracking(-0.25)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
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
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]
    @State private var selectedTab: ContentTab
    @State private var headerHeight: CGFloat = 0
    @State private var showEditor = false

    init(pillar: Pillar, initialTab: ContentTab = .ideas) {
        self.pillar = pillar
        _selectedTab = State(initialValue: initialTab)
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchor: Pillar { pillar.resolvedAnchor(in: activePillars) }
    private var isAnchor: Bool { pillar.id == anchor.id }
    private var branches: [Pillar] { activePillars.filter { $0.parentPillarID == pillar.id } }
    private var familyIDs: Set<UUID> { isAnchor ? Set([pillar.id] + branches.map(\.id)) : [pillar.id] }
    private var familyBriefs: [CreativeBrief] {
        briefs.filter { $0.pillarID.map(familyIDs.contains) == true && $0.status != .archived }
    }
    private var ideas: [CreativeBrief] {
        familyBriefs.filter { $0.status == .spark || $0.status == .developing }
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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader
                        .reportAgentViewHeight()

                    PillarPaperSurface(
                        minimumHeight: max(0, proxy.size.height - headerHeight),
                        topPadding: 28,
                        bottomPadding: 150,
                        gap: 28
                    ) {
                        VStack(alignment: .leading, spacing: 28) {
                            daysPicker
                            PillarStatsRow(
                                values: [ideas.count, scheduled.count, posted.count],
                                labels: ["Idea bank", "Scheduled", "Posted"]
                            )
                            contentTabs
                            contentList
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .sheet(isPresented: $showEditor) { PillarEditorView(pillar: pillar) }
        .agentDashboardScreen()
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        Image(systemName: "chevron.left")
                        Text("Pillars")
                    }
                    .font(.paperInter(size: 15, weight: .regular, relativeTo: .body))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { showEditor = true } label: {
                    Text("Edit")
                        .font(.paperInter(size: 15, weight: .semibold, relativeTo: .body))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(pillar.name)")
            }

            PaperPillarMeta(isAnchor ? "Anchor" : "Branch")

            HStack(spacing: 14) {
                Circle().fill(Color(agentHex: pillar.colorHex)).frame(width: 16, height: 16)
                Text(pillar.name)
                    .font(.paperInter(size: 32, weight: .medium, relativeTo: .title))
                    .tracking(-0.96)
            }
        }
        .foregroundStyle(Color.agentText)
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, 58)
    }

    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack {
                PaperPillarMeta("Days · Tap to toggle", weight: .semibold, tracking: 1.6)
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
        let selectedHex = pillar.colorHex
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
                    .font(.paperMono(size: 10, weight: .medium, relativeTo: .caption))
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
                                .font(.paperMono(size: 10, weight: .regular, relativeTo: .caption))
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
                            Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                        }
                        .frame(width: 18, height: 18)
                        Text("Capture an idea")
                            .font(.paperInter(size: 17, weight: .regular, relativeTo: .body))
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
        appModel.quickCaptureStartsWithPost = false
        appModel.quickCaptureStartsWithTask = false
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
        case .ideas: "Ideas captured for this pillar will appear here."
        case .scheduled: "Nothing is scheduled yet."
        case .posted: "Posted work will appear here."
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
            Image(systemName: "mic")
                .font(.system(size: 10, weight: .medium))
        case .repurposedBrief:
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .medium))
        case .text:
            Image(systemName: "tray")
                .font(.system(size: 10, weight: .medium))
        }
    }
    private var metadata: String {
        switch brief.source {
        case .voiceTranscript: "Voice note"
        case .cyDirection: "Spark · From Cy"
        case .repurposedBrief: "Spark · Repurposed"
        case .text: "Captured by shortcut"
        }
    }
}

struct NewPillarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @State private var name = ""
    @State private var colorHex = PillarColorOption.sage.hex
    @State private var parentPillarID: UUID?
    @State private var assignedWeekdays: Set<PillarWeekday> = []
    let onSave: (Pillar) -> Void

    init(parentPillarID: UUID? = nil, onSave: @escaping (Pillar) -> Void = { _ in }) {
        _parentPillarID = State(initialValue: parentPillarID)
        self.onSave = onSave
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchor: Pillar? { activePillars.first { $0.parentPillarID == nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section(parentPillarID == nil ? "Anchor" : "Branch") {
                    TextField("Name", text: $name)
                        .agentSingleLineSubmit()
                }
                Section("Color") { PillarColorChooser(selectedHex: $colorHex) }
                Section("Days") { WeekdayChooser(selection: $assignedWeekdays, accentHex: colorHex) }
            }
            .navigationTitle(parentPillarID == nil ? "New anchor" : "New branch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if parentPillarID == nil, let anchor { parentPillarID = anchor.id }
            }
        }
        .agentKeyboardDismissal()
    }

    private func save() {
        let parent = activePillars.first { $0.id == parentPillarID }
        let pillar = Pillar(
            parentPillarID: parent?.id,
            role: parent == nil ? .anchor : .supporting,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex,
            assignedWeekdays: assignedWeekdays
        )
        context.insert(pillar)
        try? context.save()
        onSave(pillar)
        dismiss()
    }
}

private struct PillarEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let pillar: Pillar
    @State private var name: String
    @State private var colorHex: String

    init(pillar: Pillar) {
        self.pillar = pillar
        _name = State(initialValue: pillar.name)
        _colorHex = State(initialValue: pillar.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pillar") { TextField("Name", text: $name).agentSingleLineSubmit() }
                Section("Color") { PillarColorChooser(selectedHex: $colorHex) }
            }
            .navigationTitle("Edit pillar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .agentKeyboardDismissal()
    }

    private func save() {
        pillar.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pillar.colorHex = colorHex
        try? context.save()
        dismiss()
    }
}

private struct PillarPaperSurface<Content: View>: View {
    let minimumHeight: CGFloat
    var topPadding: CGFloat = 32
    var bottomPadding: CGFloat = 140
    var gap: CGFloat = 40
    @ViewBuilder let content: Content

    init(
        minimumHeight: CGFloat,
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
            .clipShape(.rect(cornerRadius: 28))
            .shadow(color: Color.agentText.opacity(0.04), radius: 24, y: 2)
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
            .font(.paperMono(size: 10, weight: weight, relativeTo: .caption))
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
                        .font(.paperMono(size: 11, weight: .medium, relativeTo: .caption))
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
    @Binding var selectedHex: String

    var body: some View {
        HStack(spacing: AgentSpacing.x2) {
            ForEach(PillarColorOption.allCases) { option in
                Button { selectedHex = option.hex } label: {
                    Circle()
                        .fill(Color(agentHex: option.hex))
                        .frame(width: 32, height: 32)
                        .padding(AgentSpacing.x1)
                        .overlay { Circle().stroke(isSelected(option) ? Color.agentText : Color.clear, lineWidth: 2) }
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
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
    private func isSelected(_ option: PillarColorOption) -> Bool {
        selectedHex.caseInsensitiveCompare(option.hex) == .orderedSame
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
    var ideaCount: Int { familyBriefs.filter { $0.status == .spark || $0.status == .developing }.count }
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
    static func paperMono(size: CGFloat, weight: Font.Weight, relativeTo style: TextStyle) -> Font {
        let name = weight == .semibold ? "IBMPlexMono-Medm" : "IBMPlexMono-Regular"
        return .custom(name, size: size, relativeTo: style).weight(weight)
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
