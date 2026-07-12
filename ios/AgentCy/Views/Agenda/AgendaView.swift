import SwiftData
import SwiftUI

struct AgendaView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @State private var weekPlan: WeekPlan?

    private var plannableOutputs: [PlatformOutput] {
        let approvedBriefIDs = Set(briefs.filter { [.ready, .scheduled, .posted].contains($0.status) }.map(\.id))
        return outputs.filter { approvedBriefIDs.contains($0.briefID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: weekLabel,
                    title: "Plan your week.",
                    subtitle: "Set a simple routine and choose when to post."
                )

                if let weekPlan {
                    WeekRhythmEditor(plan: weekPlan) {
                        appModel.saveWeekToTemplate(weekPlan, context: context)
                    }
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    SectionRuleHeader(title: "Posts", trailing: "\(plannableOutputs.count)")
                    if plannableOutputs.isEmpty {
                        Text("Ready briefs will appear here.")
                            .font(.agentBody).foregroundStyle(Color.agentSecondary)
                    } else {
                        ForEach(plannableOutputs) { output in
                            if let brief = brief(for: output) {
                                AgendaOutputRow(output: output, brief: brief)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .agentScreen()
        .onAppear { weekPlan = appModel.ensureCurrentWeek(context: context) }
    }

    private var weekLabel: String {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        return interval?.start.formatted(.dateTime.month(.abbreviated).day()) ?? "This week"
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? {
        briefs.first(where: { $0.id == output.briefID })
    }
}

private struct WeekRhythmEditor: View {
    @Bindable var plan: WeekPlan
    let saveTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Weekly routine")
            TextEditor(text: $plan.rhythmEntriesText)
                .font(.agentBody)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 112)
                .padding(AgentSpacing.x3)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if plan.rhythmEntriesText.isEmpty {
                        Text("Monday: choose an idea\nWednesday: film\nFriday: post")
                            .font(.agentBody).foregroundStyle(Color.agentSecondary).padding(AgentSpacing.x4).allowsHitTesting(false)
                    }
                }
            HStack {
                Text("This week only").font(.agentMono).foregroundStyle(Color.agentSecondary)
                Spacer()
                Button("Save to template", action: saveTemplate)
                    .buttonStyle(AgentCompactSecondaryButtonStyle())
            }
        }
    }
}

private struct AgendaOutputRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let output: PlatformOutput
    let brief: CreativeBrief
    @State private var target = Date()
    @State private var confirmArchive = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack {
                Label(output.platform.shortTitle, systemImage: output.platform.symbol).font(.agentHeadline)
                Spacer()
                MetaLabel(output.status.rawValue)
            }
            Text(brief.title).font(.agentBody)
            if output.targetDate != nil {
                DatePicker("Flexible post-by", selection: $target, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: target) { _, date in appModel.schedule(output: output, date: date, context: context) }
                HStack {
                    Button("Remove target") { appModel.schedule(output: output, date: nil, context: context) }
                    Spacer()
                    Button(output.status == .posted ? "Unpost" : "Mark posted") { appModel.togglePosted(output: output, context: context) }
                }
                .font(.agentHeadline)
                if targetHasPassed {
                    Menu("Adjust this target", systemImage: "arrow.triangle.2.circlepath") {
                        Button("Move to tomorrow", systemImage: "calendar.badge.clock") {
                            appModel.replan(output: output, choice: .move, context: context)
                            target = output.targetDate ?? Date()
                        }
                        Button("Simplify the output", systemImage: "line.3.horizontal.decrease") {
                            appModel.replan(output: output, choice: .simplify, context: context)
                        }
                        Button("Pause this target", systemImage: "pause") {
                            appModel.replan(output: output, choice: .pause, context: context)
                            target = Date()
                        }
                        Button("Archive the master brief", systemImage: "archivebox", role: .destructive) {
                            confirmArchive = true
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityHint("Offers calm ways to adjust a posting target that has passed")
                }
            } else {
                Button("Choose a day", systemImage: "calendar.badge.plus") {
                    target = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    appModel.schedule(output: output, date: target, context: context)
                }
                .buttonStyle(AgentCompactSecondaryButtonStyle())
            }
        }
        .padding(.vertical, AgentSpacing.x4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        .onAppear { target = output.targetDate ?? Date() }
        .confirmationDialog("Archive \(brief.title)?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive master brief", role: .destructive) {
                appModel.replan(output: output, choice: .archive, context: context)
            }
        } message: {
            Text("Archive is manual. The brief and its history remain available in the Library.")
        }
    }

    private var targetHasPassed: Bool {
        guard let date = output.targetDate else { return false }
        return output.status != .posted && date < Date()
    }
}
