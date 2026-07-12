import SwiftData
import SwiftUI

struct PillarsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query private var briefs: [CreativeBrief]
    @Query private var profiles: [CreatorProfile]
    @State private var showAdd = false
    @State private var editingPillar: Pillar?
    @State private var requestedCyProposals = false

    private var developedCount: Int { briefs.filter { $0.status != .spark && $0.status != .archived }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(kicker: "Content themes", title: "Your pillars", subtitle: "Use colors to spot themes across your week.")

                if pillars.isEmpty {
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
                        SectionRuleHeader(title: "Your pillars", trailing: "\(pillars.filter { !$0.isArchived }.count)")
                        ForEach(pillars.filter { !$0.isArchived }) { pillar in
                            EditorialRow {
                                HStack(spacing: AgentSpacing.x3) {
                                    Circle()
                                        .fill(Color(agentHex: pillar.colorHex))
                                        .frame(width: 14, height: 14)
                                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                        Text(pillar.name).font(.agentHeadline)
                                        if !pillar.detail.isEmpty {
                                            Text(pillar.detail).font(.agentBody).foregroundStyle(Color.agentSecondary)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        editingPillar = pillar
                                    } label: {
                                        Image(systemName: "paintpalette")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Change \(pillar.name) color")
                                }
                            }
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
        .sheet(item: $editingPillar) { pillar in
            PillarColorEditorView(pillar: pillar)
        }
    }

    private var proposalLimit: Int {
        AssistancePolicy(mode: profiles.first?.assistanceMode ?? .collaborate)
            .pillarProposalLimit(explicitlyRequested: requestedCyProposals)
    }
}

struct NewPillarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var detail = ""
    @State private var colorHex = PillarColorOption.sage.hex
    let onSave: (Pillar) -> Void

    init(onSave: @escaping (Pillar) -> Void = { _ in }) {
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pillar") {
                    TextField("Name", text: $name)
                    TextField("Short description", text: $detail, axis: .vertical)
                }
                Section("Color") {
                    PillarColorChooser(selectedHex: $colorHex)
                }
            }
            .navigationTitle("New pillar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let pillar = Pillar(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                            colorHex: colorHex
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

private struct PillarColorEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let pillar: Pillar
    @State private var colorHex: String

    init(pillar: Pillar) {
        self.pillar = pillar
        _colorHex = State(initialValue: pillar.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Color") {
                    PillarColorChooser(selectedHex: $colorHex)
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
                        pillar.colorHex = colorHex
                        try? context.save()
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                }
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
