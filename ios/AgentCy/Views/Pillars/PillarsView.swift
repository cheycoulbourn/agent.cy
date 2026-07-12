import SwiftData
import SwiftUI

struct PillarsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query private var briefs: [CreativeBrief]
    @Query private var profiles: [CreatorProfile]
    @State private var showAdd = false
    @State private var requestedCyProposals = false

    private var developedCount: Int { briefs.filter { $0.status != .spark && $0.status != .archived }.count }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchors: [Pillar] {
        activePillars.filter { $0.resolvedAnchor(in: activePillars).id == $0.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(kicker: "Content themes", title: "Your pillars", subtitle: "Use colors to spot themes across your week.")

                if activePillars.isEmpty {
                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        SectionRuleHeader(title: "No pillars yet")
                        Text(developedCount < 3 ? "Make three briefs and Cy can suggest themes." : "Cy found a few possible themes.")
                            .font(.agentBody).foregroundStyle(Color.agentSecondary)
                        ProgressView(value: Double(min(developedCount, 3)), total: 3) {
                            MetaLabel("\(developedCount) of 3 briefs")
                        }
                        .tint(.actionAccent)
                        if developedCount >= 3 && proposalLimit == 0 {
                            Button("Suggest pillars", systemImage: "sparkles") { requestedCyProposals = true }
                                .buttonStyle(AgentSecondaryButtonStyle())
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionRuleHeader(title: "Your pillars", trailing: "\(anchors.count) anchors")
                        ForEach(anchors) { pillar in
                            NavigationLink {
                                PillarDetailView(pillar: pillar)
                            } label: {
                                PillarRow(pillar: pillar, allPillars: activePillars)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let proposals = Array(appModel.proposedPillars(context: context).prefix(proposalLimit))
                if !proposals.isEmpty && pillars.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionRuleHeader(title: "Suggestions")
                        ForEach(proposals) { proposal in
                            EditorialRow {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(proposal.name).font(.agentHeadline)
                                        Text(proposal.detail).font(.agentBody).foregroundStyle(Color.agentSecondary)
                                    }
                                    Spacer()
                                    Button("Add pillar") { appModel.acceptPillar(proposal, context: context) }
                                        .buttonStyle(AgentCompactSecondaryButtonStyle())
                                }
                            }
                        }
                    }
                }

                Button("Add pillar", systemImage: "plus") { showAdd = true }
                    .buttonStyle(AgentSecondaryButtonStyle())
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Pillars")
        .navigationBarTitleDisplayMode(.inline)
        .agentScreen()
        .sheet(isPresented: $showAdd) { NewPillarView() }
    }

    private var proposalLimit: Int {
        AssistancePolicy(mode: profiles.first?.assistanceMode ?? .collaborate)
            .pillarProposalLimit(explicitlyRequested: requestedCyProposals)
    }
}

struct NewPillarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @State private var name = ""
    @State private var detail = ""
    @State private var colorHex = PillarColorOption.sage.hex
    @State private var parentPillarID: UUID?
    @State private var assignedWeekdays: Set<PillarWeekday> = []
    let onSave: (Pillar) -> Void

    init(parentPillarID: UUID? = nil, onSave: @escaping (Pillar) -> Void = { _ in }) {
        _parentPillarID = State(initialValue: parentPillarID)
        self.onSave = onSave
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchors: [Pillar] {
        activePillars.filter { $0.resolvedAnchor(in: activePillars).id == $0.id }
    }
    private var selectedParent: Pillar? { anchors.first { $0.id == parentPillarID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pillar") {
                    TextField("Name", text: $name)
                    TextField("Short description", text: $detail, axis: .vertical)
                    Picker("Type", selection: $parentPillarID) {
                        Text("Anchor pillar").tag(UUID?.none)
                        ForEach(anchors) { pillar in
                            Text("Branch of \(pillar.name)").tag(Optional(pillar.id))
                        }
                    }
                }
                if let selectedParent {
                    Section("Inherited from \(selectedParent.name)") {
                        PillarInheritancePreview(pillar: selectedParent, allPillars: activePillars)
                    }
                } else {
                    Section("Color") {
                        PillarColorChooser(selectedHex: $colorHex)
                    }
                    Section("Preferred days") {
                        WeekdayChooser(selection: $assignedWeekdays)
                    }
                }
            }
            .navigationTitle("New pillar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let pillar = Pillar(
                            parentPillarID: parentPillarID,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                            colorHex: selectedParent?.resolvedColorHex(in: activePillars) ?? colorHex,
                            assignedWeekdays: selectedParent?.resolvedWeekdays(in: activePillars) ?? assignedWeekdays
                        )
                        context.insert(pillar)
                        try? context.save()
                        onSave(pillar)
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct PillarRow: View {
    let pillar: Pillar
    let allPillars: [Pillar]

    private var branches: [Pillar] {
        allPillars.filter { $0.parentPillarID == pillar.id && !$0.isArchived }
    }

    var body: some View {
        EditorialRow {
            HStack(spacing: AgentSpacing.x3) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(agentHex: pillar.resolvedColorHex(in: allPillars)))
                    .frame(width: 8, height: 48)
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(pillar.name).font(.agentHeadline).foregroundStyle(Color.agentText)
                    if !pillar.detail.isEmpty {
                        Text(pillar.detail).font(.agentBody).foregroundStyle(Color.agentSecondary).lineLimit(2)
                    }
                    HStack(spacing: AgentSpacing.x2) {
                        if !branches.isEmpty { MetaLabel("\(branches.count) branches") }
                        if !pillar.resolvedWeekdays(in: allPillars).isEmpty {
                            MetaLabel(pillar.resolvedWeekdays(in: allPillars).sorted { $0.rawValue < $1.rawValue }.map(\.shortTitle).joined(separator: " · "))
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.agentSecondary)
            }
        }
    }
}

struct PillarDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let pillar: Pillar
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]
    @State private var showEditor = false
    @State private var showNewBranch = false
    @State private var confirmArchive = false

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchor: Pillar { pillar.resolvedAnchor(in: activePillars) }
    private var isAnchor: Bool { anchor.id == pillar.id }
    private var branches: [Pillar] { activePillars.filter { $0.parentPillarID == pillar.id } }
    private var familyIDs: Set<UUID> { isAnchor ? Set([pillar.id] + branches.map(\.id)) : [pillar.id] }
    private var familyBriefs: [CreativeBrief] {
        briefs.filter { brief in brief.pillarID.map(familyIDs.contains) == true && brief.status != .archived }
    }
    private var ideas: [CreativeBrief] { familyBriefs.filter { $0.status == .spark || $0.status == .developing } }
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
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                HStack(alignment: .top, spacing: AgentSpacing.x4) {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .fill(Color(agentHex: pillar.resolvedColorHex(in: activePillars)))
                        .frame(width: 18, height: 72)
                    EditorialHeader(
                        kicker: isAnchor ? "Anchor pillar" : "Branch of \(anchor.name)",
                        title: pillar.name,
                        subtitle: pillar.detail.isEmpty ? nil : pillar.detail
                    )
                }

                PillarInheritancePreview(pillar: pillar, allPillars: activePillars)

                if isAnchor {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionRuleHeader(title: "Branches", trailing: "\(branches.count)")
                        ForEach(branches) { branch in
                            NavigationLink {
                                PillarDetailView(pillar: branch)
                            } label: {
                                EditorialRow {
                                    HStack {
                                        Text(branch.name).font(.agentHeadline).foregroundStyle(Color.agentText)
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Color.agentSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Add a branch", systemImage: "arrow.triangle.branch") { showNewBranch = true }
                            .buttonStyle(AgentSecondaryButtonStyle())
                            .padding(.top, AgentSpacing.x3)
                    }
                }

                PillarBriefSection(title: "Idea bank", briefs: ideas)
                PillarBriefSection(title: "Scheduled", briefs: scheduled)

                VStack(alignment: .leading, spacing: 0) {
                    SectionRuleHeader(title: "Posted", trailing: "\(posted.count)")
                    if posted.isEmpty {
                        Text("Posted work will appear here.").font(.agentBody).foregroundStyle(Color.agentSecondary).padding(.vertical, AgentSpacing.x3)
                    } else {
                        ForEach(posted) { brief in
                            EditorialRow {
                                HStack(spacing: AgentSpacing.x3) {
                                    NavigationLink {
                                        BriefDetailView(brief: brief)
                                    } label: {
                                        Text(brief.title).font(.agentHeadline).foregroundStyle(Color.agentText)
                                    }
                                    Spacer()
                                    Button {
                                        if appModel.createRepurposedSpark(from: brief, context: context) != nil {
                                            appModel.selectedTab = .spark
                                            appModel.notice = .info("A new idea is waiting in Your work.")
                                        }
                                    } label: {
                                        Image(systemName: "arrow.triangle.branch").frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Create a new idea from \(brief.title)")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle(pillar.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit pillar", systemImage: "slider.horizontal.3") { showEditor = true }
                    Button("Archive pillar", systemImage: "archivebox", role: .destructive) { confirmArchive = true }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $showEditor) { PillarEditorView(pillar: pillar) }
        .sheet(isPresented: $showNewBranch) { NewPillarView(parentPillarID: pillar.id) }
        .confirmationDialog("Archive \(pillar.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive pillar", role: .destructive) {
                pillar.isArchived = true
                try? context.save()
            }
        } message: {
            Text("Its content stays available. Any branches remain valid as standalone pillars.")
        }
        .agentScreen()
    }
}

private struct PillarBriefSection: View {
    let title: String
    let briefs: [CreativeBrief]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: title, trailing: "\(briefs.count)")
            if briefs.isEmpty {
                Text(title == "Idea bank" ? "Ideas filed here will appear here." : "Nothing scheduled yet.")
                    .font(.agentBody).foregroundStyle(Color.agentSecondary).padding(.vertical, AgentSpacing.x3)
            } else {
                ForEach(briefs) { brief in
                    NavigationLink {
                        BriefDetailView(brief: brief)
                    } label: {
                        EditorialRow {
                            HStack {
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(brief.title).font(.agentHeadline).foregroundStyle(Color.agentText)
                                    MetaLabel(brief.status.title)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.agentSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PillarEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    let pillar: Pillar
    @State private var name: String
    @State private var detail: String
    @State private var colorHex: String
    @State private var assignedWeekdays: Set<PillarWeekday>

    init(pillar: Pillar) {
        self.pillar = pillar
        _name = State(initialValue: pillar.name)
        _detail = State(initialValue: pillar.detail)
        _colorHex = State(initialValue: pillar.colorHex)
        _assignedWeekdays = State(initialValue: pillar.assignedWeekdays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pillar") {
                    TextField("Name", text: $name)
                    TextField("Short description", text: $detail, axis: .vertical)
                }
                if let parent = parent {
                    Section("Inherited from \(parent.name)") {
                        PillarInheritancePreview(pillar: parent, allPillars: activePillars)
                    }
                } else {
                    Section("Color") { PillarColorChooser(selectedHex: $colorHex) }
                    Section("Preferred days") { WeekdayChooser(selection: $assignedWeekdays) }
                }
            }
            .navigationTitle(pillar.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        pillar.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        pillar.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        if parent == nil {
                            pillar.colorHex = colorHex
                            pillar.assignedWeekdays = assignedWeekdays
                        }
                        try? context.save()
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var parent: Pillar? {
        guard let parentID = pillar.parentPillarID else { return nil }
        return activePillars.first { $0.id == parentID }
    }
}

private struct PillarInheritancePreview: View {
    let pillar: Pillar
    let allPillars: [Pillar]

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            Circle().fill(Color(agentHex: pillar.resolvedColorHex(in: allPillars))).frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(pillar.resolvedAnchor(in: allPillars).name).font(.agentHeadline)
                Text(daySummary).font(.agentMono).foregroundStyle(Color.agentSecondary)
            }
        }
        .frame(minHeight: 44)
    }

    private var daySummary: String {
        let days = pillar.resolvedWeekdays(in: allPillars)
        return days.isEmpty ? "No preferred days" : days.sorted { $0.rawValue < $1.rawValue }.map(\.shortTitle).joined(separator: " · ")
    }
}

private struct WeekdayChooser: View {
    @Binding var selection: Set<PillarWeekday>

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            ForEach(PillarWeekday.mondayFirst) { day in
                Toggle(day.title, isOn: Binding(
                    get: { selection.contains(day) },
                    set: { enabled in
                        if enabled { selection.insert(day) } else { selection.remove(day) }
                    }
                ))
                .tint(.actionAccent)
            }
        }
    }
}

private struct PillarColorChooser: View {
    @Binding var selectedHex: String
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            LazyVGrid(columns: columns, spacing: AgentSpacing.x2) {
                ForEach(PillarColorOption.allCases) { option in
                    Button {
                        selectedHex = option.hex
                    } label: {
                        HStack(spacing: AgentSpacing.x2) {
                            Circle()
                                .fill(Color(agentHex: option.hex))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
                            Text(option.name)
                                .font(.agentBody)
                                .foregroundStyle(Color.agentText)
                            Spacer(minLength: 0)
                            if isSelected(option) {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.agentText)
                            }
                        }
                        .padding(.horizontal, AgentSpacing.x3)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(isSelected(option) ? Color.actionAccent : Color.agentBorder, lineWidth: isSelected(option) ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isSelected(option) ? "Selected" : "Not selected")
                }
            }

            ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                .font(.agentBody)
                .frame(minHeight: 48)
                .accessibilityHint("Opens the full color picker")
        }
        .padding(.vertical, AgentSpacing.x1)
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

private enum PillarColorOption: String, CaseIterable, Identifiable {
    case terracotta = "9B3A2E"
    case ochre = "B47724"
    case sage = "55705B"
    case blue = "416B85"
    case plum = "76506F"

    var id: String { rawValue }
    var hex: String { rawValue }

    var name: String {
        switch self {
        case .terracotta: "Terracotta"
        case .ochre: "Ochre"
        case .sage: "Sage"
        case .blue: "Blue"
        case .plum: "Plum"
        }
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
