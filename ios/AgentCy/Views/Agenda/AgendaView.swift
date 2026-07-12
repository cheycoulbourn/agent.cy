import SwiftData
import SwiftUI

struct AgendaView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var appModelContext
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var tasks: [CreatorTask]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @State private var weekOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var planningDay: PlanningDay?

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchors: [Pillar] {
        activePillars.filter { $0.resolvedAnchor(in: activePillars).id == $0.id }
    }

    private var weekStart: Date {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: current) ?? current
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: weekRange,
                    title: weekOffset == 0 ? "Your week." : weekRangeTitle,
                    subtitle: "Plan your content for the week."
                )

                HStack {
                    Button {
                        moveWeek(by: -1)
                    } label: {
                        Label("Previous week", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)

                    Spacer()
                    Text(weekRange)
                        .font(.agentHeadline)
                        .accessibilityLabel("Week of \(weekRange)")
                    Spacer()

                    Button {
                        moveWeek(by: 1)
                    } label: {
                        Label("Next week", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }

                weekSection
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planningDay) { day in
            DayPlannerSheet(
                day: day.date,
                createNewPost: { beginNewPost(on: day.date) },
                createNewTask: { beginNewTask(on: day.date) }
            )
        }
        .agentScreen()
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Content plan", trailing: weekRange)

            HStack(spacing: AgentSpacing.x1) {
                ForEach(weekDays, id: \.self) { day in
                    let dayBriefs = plannedBriefs(on: day)
                    let dayPillars = assignedPillars(on: day)
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: AgentSpacing.x2) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.agentMono)
                            Text(day.formatted(.dateTime.day()))
                                .font(.agentHeadline)
                            HStack(spacing: 3) {
                                if !dayPillars.isEmpty {
                                    ForEach(dayPillars.prefix(3)) { pillar in
                                        Circle().fill(Color(agentHex: pillar.colorHex)).frame(width: 7, height: 7)
                                    }
                                }
                            }
                            .frame(height: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .foregroundStyle(isSelected(day) ? Color.onAccent : Color.agentText)
                        .background(isSelected(day) ? Color.actionAccent : Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .accessibilityValue(dayBriefs.isEmpty ? (dayPillars.isEmpty ? "Nothing planned" : "\(dayPillars.count) pillar themes assigned") : "\(dayBriefs.count) items planned")
                }
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    Text(selectedDayTitle).font(.agentTitle)

                    let themes = assignedPillars(on: selectedDay)
                    if !themes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AgentSpacing.x2) {
                                ForEach(themes) { pillar in
                                    Label {
                                        Text(pillar.name)
                                    } icon: {
                                        Circle().fill(Color(agentHex: pillar.colorHex)).frame(width: 10, height: 10)
                                    }
                                    .font(.agentMono)
                                    .padding(.horizontal, AgentSpacing.x3)
                                    .frame(minHeight: 36)
                                    .background(Color.agentCanvas, in: .capsule)
                                    .overlay(Capsule().stroke(Color.agentBorder, lineWidth: 1))
                                }
                            }
                        }
                        .accessibilityLabel("Pillars assigned to this day")
                    }

                    let selectedBriefs = plannedBriefs(on: selectedDay)
                    SectionRuleHeader(title: "Posts", trailing: "\(selectedBriefs.count)")
                    if selectedBriefs.isEmpty {
                        Text("No posts planned.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    } else {
                        ForEach(selectedBriefs) { brief in
                            NavigationLink {
                                BriefDetailView(brief: brief)
                            } label: {
                                HStack(spacing: AgentSpacing.x3) {
                                    Capsule().fill(color(for: brief)).frame(width: 5, height: 38)
                                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                        Text(brief.title).font(.agentHeadline).foregroundStyle(Color.agentText)
                                        Text(pillarName(for: brief) ?? brief.status.title)
                                            .font(.agentMono)
                                            .foregroundStyle(Color.agentSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.agentSecondary)
                                }
                                .frame(minHeight: 52)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    let selectedTasks = plannedTasks(on: selectedDay)
                    SectionRuleHeader(title: "Tasks", trailing: "\(selectedTasks.count)")
                    if selectedTasks.isEmpty {
                        Text("No production tasks planned.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    } else {
                        ForEach(selectedTasks) { task in
                            HStack(spacing: AgentSpacing.x2) {
                                Button {
                                    appModel.toggleTask(task, context: appModelContext)
                                } label: {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(task.isCompleted ? Color.agentSuccess : Color.agentSecondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    TaskDetailView(task: task)
                                } label: {
                                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                        Text(task.title)
                                            .font(.agentBody)
                                            .foregroundStyle(Color.agentText)
                                            .strikethrough(task.isCompleted)
                                        MetaLabel(task.kind.title)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(AgentSpacing.x4)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    planningDay = PlanningDay(date: selectedDay)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.agentText)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .background(Color.agentCanvas)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
                .accessibilityLabel("Add a post or task to \(selectedDayTitle)")
            }
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .clipShape(.rect(cornerRadius: AgentRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
        }
    }

    private var weekRange: String {
        guard let last = weekDays.last else { return "" }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var weekRangeTitle: String {
        weekOffset < 0 ? "A previous week." : "A week ahead."
    }

    private var selectedDayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) { return "Today" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: selectedDay)
    }

    private func plannedBriefs(on day: Date) -> [CreativeBrief] {
        let calendar = Calendar.current
        return activeBriefs.filter { brief in
            let outputDate = outputs
                .filter { $0.briefID == brief.id }
                .compactMap(\.targetDate)
                .sorted()
                .first
            guard let plannedDate = brief.agendaDate ?? outputDate else { return false }
            return calendar.isDate(plannedDate, inSameDayAs: day)
        }
    }

    private func plannedTasks(on day: Date) -> [CreatorTask] {
        tasks.filter { task in
            task.parentTaskID == nil &&
                task.targetDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true
        }
    }

    private func moveWeek(by amount: Int) {
        weekOffset += amount
        let currentWeekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
        if weekOffset == 0 {
            selectedDay = Calendar.current.startOfDay(for: Date())
        } else if let currentWeekStart,
                  let newStart = Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) {
            selectedDay = newStart
        }
    }

    private func pillarName(for brief: CreativeBrief) -> String? {
        guard let pillarID = brief.pillarID else { return nil }
        return pillars.first { $0.id == pillarID }?.name
    }

    private func color(for brief: CreativeBrief) -> Color {
        guard let pillarID = brief.pillarID,
              let pillar = pillars.first(where: { $0.id == pillarID }) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }

    private func assignedPillars(on day: Date) -> [Pillar] {
        guard let weekday = PillarWeekday(rawValue: Calendar.current.component(.weekday, from: day)) else { return [] }
        return anchors.filter { $0.assignedWeekdays.contains(weekday) }
    }

    private func beginNewPost(on day: Date) {
        planningDay = nil
        appModel.quickCaptureTargetDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        appModel.quickCapturePillarID = assignedPillars(on: day).first?.id
        appModel.quickCaptureStartsWithIdeas = false
        appModel.quickCaptureStartsWithTask = false
        appModel.quickCaptureStartsRecording = false
        appModel.quickCaptureStartsWithPost = true
        Task { @MainActor in
            await Task.yield()
            appModel.presentedSheet = .quickCapture
        }
    }

    private func beginNewTask(on day: Date) {
        planningDay = nil
        appModel.quickCaptureTargetDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureStartsWithIdeas = false
        appModel.quickCaptureStartsWithPost = false
        appModel.quickCaptureStartsRecording = false
        appModel.quickCaptureStartsWithTask = true
        Task { @MainActor in
            await Task.yield()
            appModel.presentedSheet = .quickCapture
        }
    }
}

private struct PlanningDay: Identifiable {
    let date: Date
    var id: Date { Calendar.current.startOfDay(for: date) }
}

private struct DayPlannerSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var tasks: [CreatorTask]
    let day: Date
    let createNewPost: () -> Void
    let createNewTask: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Create") {
                    Button("Create a new post", systemImage: "plus") {
                        dismiss()
                        createNewPost()
                    }
                    Button("Create a new task", systemImage: "checkmark.circle") {
                        dismiss()
                        createNewTask()
                    }
                }

                let datedOutputBriefIDs = Set(outputs.compactMap { output in
                    output.targetDate == nil ? nil : output.briefID
                })
                let available = briefs.filter { brief in
                    brief.status != .archived &&
                        brief.agendaDate == nil &&
                        !datedOutputBriefIDs.contains(brief.id)
                }
                if !available.isEmpty {
                    Section("Posts") {
                        ForEach(available) { brief in
                            Button {
                                if appModel.plan(brief, on: plannedDate, context: context) { dismiss() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(brief.title).foregroundStyle(Color.agentText)
                                        Text(brief.status.title).font(.caption).foregroundStyle(Color.agentSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                    }
                }

                let availableTasks = tasks.filter {
                    $0.parentTaskID == nil && $0.targetDate == nil
                }
                if !availableTasks.isEmpty {
                    Section("Tasks") {
                        ForEach(availableTasks) { task in
                            Button {
                                task.targetDate = plannedDate
                                do {
                                    try context.save()
                                    dismiss()
                                } catch {
                                    appModel.notice = .error("That task could not be added to this day.")
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(task.title).foregroundStyle(Color.agentText)
                                        Text(task.kind.title).font(.caption).foregroundStyle(Color.agentSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to \(day.formatted(.dateTime.weekday(.wide)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
    }

    private var plannedDate: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}
