import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var profiles: [CreatorProfile]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \CreatorTask.createdAt) private var tasks: [CreatorTask]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var planningDay: PlanningDay?

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var nextTasks: [CreatorTask] { Array(tasks.filter { !$0.isCompleted }.prefix(2)) }
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    title: greeting,
                    subtitle: "What do you want to make this week?"
                )

                weekSection

                if activeBriefs.isEmpty {
                    emptyState
                } else {
                    if profiles.first?.onboardingCompleted == false { firstJourneyCallout }
                    taskSection
                    briefSection
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planningDay) { day in
            DayPlannerSheet(day: day.date) {
                beginNewContent(on: day.date)
            }
        }
        .agentScreen()
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "This week", trailing: weekRange)

            HStack(spacing: AgentSpacing.x1) {
                ForEach(weekDays, id: \.self) { day in
                    let dayBriefs = plannedBriefs(on: day)
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: AgentSpacing.x2) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.agentMono)
                            Text(day.formatted(.dateTime.day()))
                                .font(.agentHeadline)
                            HStack(spacing: 3) {
                                if dayBriefs.isEmpty {
                                    Circle().fill(Color.agentBorder).frame(width: 5, height: 5)
                                } else {
                                    ForEach(dayBriefs.prefix(3)) { brief in
                                        Circle()
                                            .fill(color(for: brief))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                            }
                            .frame(height: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDay) ? Color.onAccent : Color.agentText)
                        .background(
                            Calendar.current.isDate(day, inSameDayAs: selectedDay) ? Color.actionAccent : Color.agentSurface,
                            in: .rect(cornerRadius: AgentRadius.control)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .accessibilityValue(dayBriefs.isEmpty ? "Nothing planned" : "\(dayBriefs.count) items planned")
                }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack {
                    Text(selectedDayTitle).font(.agentHeadline)
                    Spacer()
                    Button("Add content", systemImage: "plus") {
                        planningDay = PlanningDay(date: selectedDay)
                    }
                    .buttonStyle(AgentCompactPrimaryButtonStyle())
                }

                let selectedBriefs = plannedBriefs(on: selectedDay)
                if selectedBriefs.isEmpty {
                    Text("Nothing planned yet.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                } else {
                    ForEach(selectedBriefs) { brief in
                        NavigationLink {
                            BriefDetailView(brief: brief)
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                Capsule()
                                    .fill(color(for: brief))
                                    .frame(width: 5, height: 38)
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
            }
            .padding(AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Start here")
            Text("Turn one idea into a video you can make.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
            Button("Create your first brief", systemImage: "plus") {
                appModel.presentedSheet = .quickCapture
            }
            .buttonStyle(AgentPrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var firstJourneyCallout: some View {
        if let brief = activeBriefs.first {
            CyCallout {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("Finish setup")
                    Text("Review your first brief.").font(.agentBody)
                    NavigationLink("Continue") { BriefDetailView(brief: brief) }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        if !nextTasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Up next")
                ForEach(nextTasks) { task in
                    EditorialRow {
                        HStack(spacing: AgentSpacing.x3) {
                            Button { appModel.toggleTask(task, context: context) } label: {
                                Image(systemName: "circle")
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Complete \(task.title)")
                            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                Text(task.title).font(.agentBody)
                                if let date = task.targetDate {
                                    Text(date, style: .relative).font(.agentMono).foregroundStyle(Color.agentSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var briefSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "In progress", trailing: "\(activeBriefs.count)")
            ForEach(activeBriefs.prefix(2)) { brief in
                NavigationLink {
                    BriefDetailView(brief: brief)
                } label: {
                    EditorialRow {
                        HStack(spacing: AgentSpacing.x3) {
                            Capsule().fill(color(for: brief)).frame(width: 5, height: 38)
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Good \(timeOfDay)" : "Good \(timeOfDay), \(name)"
    }

    private var weekRange: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.day()))"
    }

    private var selectedDayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) { return "Today" }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    private func plannedBriefs(on day: Date) -> [CreativeBrief] {
        let calendar = Calendar.current
        let taskIDs = tasks.compactMap { task -> UUID? in
            guard let date = task.targetDate,
                  calendar.isDate(date, inSameDayAs: day),
                  let briefID = task.briefID else { return nil }
            return briefID
        }
        let outputIDs = outputs.compactMap { output -> UUID? in
            guard let date = output.targetDate, calendar.isDate(date, inSameDayAs: day) else { return nil }
            return output.briefID
        }
        let plannedIDs = Set(taskIDs + outputIDs)
        return activeBriefs.filter { plannedIDs.contains($0.id) }
    }

    private func pillarName(for brief: CreativeBrief) -> String? {
        guard let pillarID = brief.pillarID else { return nil }
        return pillars.first(where: { $0.id == pillarID })?.name
    }

    private func color(for brief: CreativeBrief) -> Color {
        guard let pillarID = brief.pillarID,
              let pillar = pillars.first(where: { $0.id == pillarID }) else { return .agentSecondary }
        return Color(agentHex: pillar.colorHex)
    }

    private func beginNewContent(on day: Date) {
        planningDay = nil
        appModel.quickCaptureTargetDate = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
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
    let day: Date
    let createNew: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Create new content", systemImage: "plus") {
                        dismiss()
                        createNew()
                    }
                }

                let available = briefs.filter { $0.status != .archived }
                if !available.isEmpty {
                    Section("Or add something in progress") {
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
