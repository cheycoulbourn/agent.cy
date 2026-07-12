import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \CreatorTask.createdAt) private var tasks: [CreatorTask]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }

    private var todayTasks: [CreatorTask] {
        let incomplete = tasks.filter { !$0.isCompleted && $0.parentTaskID == nil }
        let datedToday = incomplete.filter { task in
            task.targetDate.map(Calendar.current.isDateInToday) ?? false
        }
        return datedToday.isEmpty ? Array(incomplete.filter { $0.targetDate == nil }.prefix(3)) : datedToday
    }

    private var todayOutputs: [PlatformOutput] {
        outputs.filter { output in
            output.targetDate.map(Calendar.current.isDateInToday) == true &&
                activeBriefs.contains(where: { $0.id == output.briefID })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    title: greeting,
                    subtitle: "What are we posting today?"
                )

                if profiles.first?.onboardingCompleted == false {
                    firstJourneyCallout
                }

                focusSection
                goingLiveSection
                taskSection
                quickCaptureSection
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .agentScreen()
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Today's focus")

            if let output = todayOutputs.first, let brief = brief(for: output) {
                NavigationLink {
                    BriefDetailView(brief: brief)
                } label: {
                    focusCard(
                        kicker: output.status == .posted ? "Posted" : "Going live",
                        title: brief.title,
                        symbol: output.platform.symbol
                    )
                }
                .buttonStyle(.plain)
            } else if let brief = activeBriefs.first {
                NavigationLink {
                    BriefDetailView(brief: brief)
                } label: {
                    focusCard(kicker: brief.status.title, title: brief.title, symbol: brief.status.symbol)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openCapture(.idea)
                } label: {
                    focusCard(kicker: "Start small", title: "Capture one idea", symbol: "lightbulb")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var goingLiveSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Going live today", trailing: "\(todayOutputs.count)")
            if todayOutputs.isEmpty {
                Text("Nothing is set to post today.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x3)
            } else {
                ForEach(todayOutputs) { output in
                    if let brief = brief(for: output) {
                        NavigationLink {
                            BriefDetailView(brief: brief)
                        } label: {
                            EditorialRow {
                                HStack(spacing: AgentSpacing.x3) {
                                    Image(systemName: output.platform.symbol)
                                        .foregroundStyle(Color.actionAccent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                        Text(brief.title).font(.agentHeadline).foregroundStyle(Color.agentText)
                                        MetaLabel("\(output.platform.shortTitle) · \(output.status.rawValue)")
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

    @ViewBuilder
    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Today's tasks", trailing: "\(todayTasks.count)")
            if todayTasks.isEmpty {
                Text("No tasks need your attention today.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x3)
            } else {
                ForEach(todayTasks) { task in
                    EditorialRow {
                        HStack(spacing: AgentSpacing.x3) {
                            Button {
                                appModel.toggleTask(task, context: context)
                            } label: {
                                Image(systemName: "circle")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Complete \(task.title)")
                            NavigationLink {
                                TaskDetailView(task: task)
                            } label: {
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(task.title).font(.agentBody).foregroundStyle(Color.agentText)
                                    if let date = task.targetDate {
                                        Text(date, format: .dateTime.hour().minute())
                                            .font(.agentMono)
                                            .foregroundStyle(Color.agentSecondary)
                                    } else {
                                        MetaLabel(task.kind.title)
                                    }
                                    let steps = tasks.filter { $0.parentTaskID == task.id }
                                    if !steps.isEmpty {
                                        MetaLabel("\(steps.filter(\.isCompleted).count) of \(steps.count) steps")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Quick capture")
            HStack(spacing: AgentSpacing.x2) {
                TodayQuickAction(title: "Idea", symbol: "lightbulb") { openCapture(.idea) }
                TodayQuickAction(title: "Task", symbol: "checkmark.circle") { openCapture(.task) }
                TodayQuickAction(title: "Post", symbol: "calendar.badge.plus") { openCapture(.post) }
            }
        }
    }

    @ViewBuilder
    private var firstJourneyCallout: some View {
        if let brief = activeBriefs.first {
            CyCallout {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("Finish setup")
                    Text("Review your first brief.").font(.agentBody)
                    NavigationLink("Review brief") { BriefDetailView(brief: brief) }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            }
        }
    }

    private func focusCard(kicker: String, title: String, symbol: String) -> some View {
        HStack(spacing: AgentSpacing.x4) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                MetaLabel(kicker)
                Text(title).font(.agentHeadline).foregroundStyle(Color.agentText)
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(Color.agentSecondary)
        }
        .foregroundStyle(Color.agentText)
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Good \(timeOfDay)" : "Good \(timeOfDay), \(name)"
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? {
        activeBriefs.first { $0.id == output.briefID }
    }

    private func openCapture(_ kind: TodayCaptureKind) {
        appModel.quickCaptureTargetDate = nil
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureStartsWithIdeas = false
        appModel.quickCaptureStartsRecording = false
        appModel.quickCaptureStartsWithTask = kind == .task
        appModel.quickCaptureStartsWithPost = kind == .post
        appModel.presentedSheet = .quickCapture
    }
}

private enum TodayCaptureKind {
    case idea
    case task
    case post
}

private struct TodayQuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AgentSpacing.x2) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.agentSubtext)
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New \(title.lowercased())")
    }
}
