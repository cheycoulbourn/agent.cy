import SwiftData
import SwiftUI

struct AgendaView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @State private var weekScope: AgendaWeekScope = .thisWeek
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var planningDay: PlanningDay?
    @State private var weekPlan: WeekPlan?

    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }
    private var anchors: [Pillar] {
        activePillars.filter { $0.resolvedAnchor(in: activePillars).id == $0.id }
    }

    private var weekStart: Date {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return weekScope == .thisWeek ? current : (calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: weekRange,
                    title: weekScope == .thisWeek ? "Your week." : "Next week, a fresh slate.",
                    subtitle: "Plan content and production without locking yourself in."
                )

                Picker("Week", selection: $weekScope) {
                    ForEach(AgendaWeekScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                weekSection

                if let weekPlan {
                    WeekRhythmEditor(plan: weekPlan) {
                        appModel.saveWeekToTemplate(weekPlan, context: context)
                    }
                }

            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planningDay) { day in
            DayPlannerSheet(day: day.date) {
                beginNewPost(on: day.date)
            }
        }
        .agentScreen()
        .onAppear { loadWeek() }
        .onChange(of: weekScope) { _, _ in loadWeek() }
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
                                if !dayBriefs.isEmpty {
                                    ForEach(dayBriefs.prefix(3)) { brief in
                                        Circle().fill(color(for: brief)).frame(width: 7, height: 7)
                                    }
                                } else if !dayPillars.isEmpty {
                                    ForEach(dayPillars.prefix(3)) { pillar in
                                        Circle().fill(Color(agentHex: pillar.colorHex)).frame(width: 7, height: 7)
                                    }
                                } else {
                                    Circle().fill(Color.agentBorder).frame(width: 5, height: 5)
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

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack {
                    Text(selectedDayTitle).font(.agentHeadline)
                    Spacer()
                    Button("Add content", systemImage: "plus") {
                        planningDay = PlanningDay(date: selectedDay)
                    }
                    .buttonStyle(AgentCompactPrimaryButtonStyle())
                }

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
            }
            .padding(AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
        }
    }

    private var weekRange: String {
        guard let last = weekDays.last else { return "" }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day()))–\(last.formatted(.dateTime.month(.abbreviated).day()))"
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

    private func loadWeek() {
        selectedDay = weekScope == .thisWeek ? Calendar.current.startOfDay(for: Date()) : weekStart
        weekPlan = appModel.ensureWeek(startingAt: weekStart, context: context)
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
}

private enum AgendaWeekScope: String, CaseIterable, Identifiable {
    case thisWeek
    case nextWeek

    var id: String { rawValue }
    var title: String { self == .thisWeek ? "This week" : "Next week" }
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
                    Button("Create a new post", systemImage: "plus") {
                        dismiss()
                        createNew()
                    }
                }

                let available = briefs.filter { $0.status != .archived }
                if !available.isEmpty {
                    Section("Add existing work") {
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

private struct WeekRhythmEditor: View {
    @Bindable var plan: WeekPlan
    let saveTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Production rhythm")
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
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .padding(AgentSpacing.x4)
                            .allowsHitTesting(false)
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
