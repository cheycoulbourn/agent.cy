import SwiftData
import SwiftUI

struct TodayView: View {
    let day: Date
    @Binding var planMode: PlanMode
    let showsHeader: Bool
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \CreatorTask.createdAt) private var tasks: [CreatorTask]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query private var pillars: [Pillar]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query private var focusTemplates: [DailyFocusTemplateEntry]
    @Query private var focusOverrides: [DailyFocusOverride]
    @State private var headerHeight: CGFloat = 0

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }

    init(day: Date, planMode: Binding<PlanMode>, showsHeader: Bool = true) {
        self.day = Calendar.current.startOfDay(for: day)
        _planMode = planMode
        self.showsHeader = showsHeader
    }

    private var todayTasks: [CreatorTask] {
        tasks
            .filter {
                !$0.isCompleted &&
                    $0.parentTaskID == nil &&
                    ($0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false)
            }
            .sorted(by: taskSort)
    }

    private var todayOutputs: [PlatformOutput] {
        outputs.filter { output in
            output.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true &&
                activeBriefs.contains(where: { $0.id == output.briefID })
        }
        .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private var draftedOutputs: [PlatformOutput] {
        todayOutputs.filter { output in
            TodayOutputPresentation.section(
                outputStatus: output.status,
                briefStatus: brief(for: output)?.status
            ) == .drafted
        }
    }

    private var goingLiveOutputs: [PlatformOutput] {
        todayOutputs.filter { output in
            TodayOutputPresentation.section(
                outputStatus: output.status,
                briefStatus: brief(for: output)?.status
            ) == .goingLive
        }
    }

    private var resolvedFocus: ResolvedDailyFocus? {
        DailyFocusResolver.resolve(date: day, templates: focusTemplates, overrides: focusOverrides)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsHeader {
                        header
                            .reportAgentViewHeight()
                    }
                    AgentDashboardSurface(
                        minimumHeight: max(0, proxy.size.height - (showsHeader ? headerHeight : 0))
                    ) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                            focusSection
                            postSections
                            taskSection
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .agentDashboardScreen()
    }

    private var header: some View {
        PlanHeader(
            mode: $planMode,
            breadcrumb: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
            profile: profiles.first,
            firstLine: "Hi \(displayName),",
            secondLine: dayTitle,
            openSettings: { appModel.presentedSheet = .settings }
        )
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            MetaLabel("\(day.formatted(.dateTime.weekday(.wide)))'s Focus")
            NavigationLink {
                DailyFocusDetailView(date: day)
            } label: {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    if let focus = resolvedFocus {
                        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                            Text(focus.title).font(.agentTitle)
                            Text("DAY \(weekdayPosition) OF 7").font(.agentMono)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                        }
                        if !focus.note.isEmpty {
                            Text(focus.note).font(.agentBody)
                        }
                        HStack(spacing: AgentSpacing.x4) {
                            if let duration = focus.durationMinutes {
                                MetaLabel("\(duration) min")
                            }
                            if let time = focus.time {
                                MetaLabel(time.formatted(date: .omitted, time: .shortened))
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Rest").font(.agentTitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                        }
                        Text("No focus is assigned today.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AgentSpacing.x4)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens today's focus details")
        }
    }

    private var postSections: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            if !goingLiveOutputs.isEmpty {
                postOutputSection(title: "Scheduled", outputs: goingLiveOutputs, displayAsDraft: false)
            }

            if !draftedOutputs.isEmpty {
                postOutputSection(title: "Drafted", outputs: draftedOutputs, displayAsDraft: true)
            }

            if goingLiveOutputs.isEmpty, draftedOutputs.isEmpty {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    sectionHeading(Calendar.current.isDateInToday(day) ? "Posts today" : "Posts", count: 0, unit: "post")
                    Text("Nothing is planned for this day.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            AgentAddActionRow(title: "Schedule post", action: addPostForToday)
                .accessibilityHint("Creates a post scheduled for this day")
            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    planMode = .week
                }
            } label: {
                HStack {
                    Text("View week").font(.agentSubtext.weight(.medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.agentText)
                .padding(.top, AgentSpacing.x3)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
            }
            .buttonStyle(.plain)
        }
    }

    private func postOutputSection(
        title: String,
        outputs: [PlatformOutput],
        displayAsDraft: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            sectionHeading(title, count: outputs.count, unit: "post")
            ForEach(outputs) { output in
                if let brief = brief(for: output) {
                    NavigationLink { PostOutputDetailView(brief: brief, output: output) } label: {
                        AgentPostCard(
                            title: outputTitle(output, brief: brief),
                            pillar: pillar(for: brief)?.name ?? "Unfiled",
                            accent: pillar(for: brief).map { Color(agentHex: $0.colorHex) } ?? .agentSecondary,
                            status: displayAsDraft ? .draft : output.status,
                            metadata: outputLabel(output),
                            timeText: output.includesTargetTime
                                ? output.targetDate?.formatted(date: .omitted, time: .shortened)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            sectionHeading(Calendar.current.isDateInToday(day) ? "Today's tasks" : "Tasks", count: todayTasks.count, unit: "task")
            if todayTasks.isEmpty {
                Text("No tasks are scheduled for this day.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                ForEach(Array(todayTasks.prefix(4))) { task in
                    TaskRow(task: task, allTasks: tasks)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.agentHairline)
                                .frame(height: 1)
                        }
                }
            }
            AgentAddActionRow(title: "Add task", action: addTaskForToday)
                .accessibilityHint("Creates a task scheduled for this day")
            Button {
                appModel.selectedTab = .tasks
            } label: {
                HStack {
                    Text("See all tasks").font(.agentSubtext.weight(.medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.agentText)
                .padding(.top, AgentSpacing.x3)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentHairline).frame(height: 1) }
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeading(_ title: String, count: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MetaLabel(title)
            Spacer()
            Text("\(count) \(count == 1 ? unit : unit + "s")".uppercased()).font(.agentMono)
        }
    }

    private var displayName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "there" : name
    }

    private var weekdayPosition: Int {
        let raw = Calendar.current.component(.weekday, from: day)
        return raw == 1 ? 7 : raw - 1
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(day) {
            return "what are we creating today?"
        }
        return "here's your \(day.formatted(.dateTime.weekday(.wide)))."
    }

    private func taskSort(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        if lhs.priority == .urgent, rhs.priority != .urgent { return true }
        if rhs.priority == .urgent, lhs.priority != .urgent { return false }
        return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
    }

    private func addTaskForToday() {
        appModel.quickCaptureTargetDate = day
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureTaskFocus = nil
        appModel.quickCaptureStartsWithTask = true
        appModel.quickCaptureStartsWithPost = false
        appModel.quickCaptureStartsWithIdeas = false
        appModel.presentedSheet = .quickCapture
    }

    private func addPostForToday() {
        appModel.quickCaptureTargetDate = day
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureStartsWithTask = false
        appModel.quickCaptureStartsWithPost = true
        appModel.quickCaptureStartsWithIdeas = false
        appModel.presentedSheet = .quickCapture
    }

    private func brief(for output: PlatformOutput) -> CreativeBrief? { activeBriefs.first { $0.id == output.briefID } }
    private func pillar(for brief: CreativeBrief) -> Pillar? { brief.pillarID.flatMap { id in pillars.first { $0.id == id } } }
    private func outputTitle(_ output: PlatformOutput, brief: CreativeBrief) -> String {
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }
    private func outputLabel(_ output: PlatformOutput) -> String {
        guard let destinationID = output.destinationID,
              let destination = destinations.first(where: { $0.id == destinationID }) else { return output.platform.title }
        let format = output.formatID.flatMap { id in formats.first { $0.id == id } }
        return [destination.name, format?.name].compactMap { $0 }.joined(separator: " · ")
    }
}

enum TodayOutputSection: Equatable {
    case drafted
    case goingLive
}

enum TodayOutputPresentation {
    static func section(
        outputStatus: PlatformOutputStatus,
        briefStatus: BriefStatus?
    ) -> TodayOutputSection {
        if outputStatus == .draft || briefStatus == .spark || briefStatus == .developing {
            return .drafted
        }
        return .goingLive
    }
}
