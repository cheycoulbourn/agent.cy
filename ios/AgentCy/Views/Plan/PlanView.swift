import SwiftData
import SwiftUI

enum PlanMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PlanView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [CreatorProfile]
    @State private var mode: PlanMode = .day
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset = 0

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header

                ZStack {
                    TodayView(
                        day: selectedDay,
                        planMode: animatedMode,
                        showsHeader: false
                    )
                    .offset(x: mode == .day ? 0 : -proxy.size.width)
                    .allowsHitTesting(mode == .day)
                    .accessibilityHidden(mode != .day)

                    AgendaView(
                        planMode: animatedMode,
                        weekOffset: $weekOffset,
                        selectedDay: $selectedDay,
                        showsHeader: false
                    ) { day in
                        selectedDay = Calendar.current.startOfDay(for: day)
                        setMode(.day)
                    }
                    .offset(x: mode == .week ? 0 : proxy.size.width)
                    .allowsHitTesting(mode == .week)
                    .accessibilityHidden(mode != .week)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .simultaneousGesture(planSwipeGesture)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: mode)
        }
        .background(Color.agentCanvas.ignoresSafeArea())
        .onChange(of: appModel.requestedPlanMode, initial: true) { _, requestedMode in
            guard let requestedMode else { return }
            setMode(requestedMode)
            appModel.requestedPlanMode = nil
        }
        .onChange(of: appModel.widgetAgendaDay, initial: true) { _, day in
            guard let day else { return }
            selectedDay = Calendar.current.startOfDay(for: day)
            setMode(.day)
            appModel.widgetAgendaDay = nil
        }
    }

    private var header: some View {
        PlanHeader(
            mode: animatedMode,
            breadcrumb: headerDateSummary,
            profile: profiles.first,
            firstLine: "Hi \(displayName),",
            secondLine: "what are we creating this week?",
            openSettings: { appModel.presentedSheet = .settings }
        ) {
            HStack(spacing: AgentSpacing.x1) {
                navigationButton(symbol: "chevron.left", amount: -1)
                todayButton
                navigationButton(symbol: "chevron.right", amount: 1)
            }
        }
    }

    private var animatedMode: Binding<PlanMode> {
        Binding(
            get: { mode },
            set: { newMode in
                setMode(newMode)
            }
        )
    }

    private var planSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 52 else { return }
                if value.translation.width < 0, mode == .day {
                    setMode(.week)
                } else if value.translation.width > 0, mode == .week {
                    setMode(.day)
                }
            }
    }

    private func setMode(_ newMode: PlanMode) {
        guard newMode != mode else { return }
        if reduceMotion {
            mode = newMode
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                mode = newMode
            }
        }
    }

    private func navigationButton(symbol: String, amount: Int) -> some View {
        Button { movePlan(amount) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(navigationLabel(amount: amount))
    }

    private var todayButton: some View {
        Button(action: returnToToday) {
            Text("TODAY")
                .font(.agentMono)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .day ? "Return to today" : "Return to current week")
    }

    private var displayName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "there" : name
    }

    private var headerDateSummary: String {
        let date = mode == .day ? selectedDay : weekStart
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private var weekStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let current = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: current) ?? current
    }

    private func movePlan(_ amount: Int) {
        let update = {
            if mode == .day {
                selectedDay = Calendar.current.date(
                    byAdding: .day,
                    value: amount,
                    to: selectedDay
                ) ?? selectedDay
            } else {
                weekOffset += amount
                selectedDay = Calendar.current.date(
                    byAdding: .weekOfYear,
                    value: amount,
                    to: selectedDay
                ) ?? weekStart
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.snappy(duration: 0.28), update)
        }
    }

    private func returnToToday() {
        let update = {
            selectedDay = Calendar.current.startOfDay(for: Date())
            weekOffset = 0
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.snappy(duration: 0.28), update)
        }
    }

    private func navigationLabel(amount: Int) -> String {
        let direction = amount < 0 ? "Previous" : "Next"
        return "\(direction) \(mode == .day ? "day" : "week")"
    }
}

struct PlanHeader<Actions: View>: View {
    @Binding var mode: PlanMode
    let breadcrumb: String
    let profile: CreatorProfile?
    let firstLine: String
    let secondLine: String
    let openSettings: () -> Void
    @ViewBuilder let actions: Actions

    init(
        mode: Binding<PlanMode>,
        breadcrumb: String,
        profile: CreatorProfile?,
        firstLine: String,
        secondLine: String,
        openSettings: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        _mode = mode
        self.breadcrumb = breadcrumb
        self.profile = profile
        self.firstLine = firstLine
        self.secondLine = secondLine
        self.openSettings = openSettings
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            AgentPageRail(
                breadcrumb: breadcrumb,
                profile: profile,
                openSettings: openSettings,
                actions: { actions }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(firstLine)
                    .font(.system(size: 32, weight: .regular, design: .default))
                Text(secondLine)
                    .font(.agentDisplay)
            }
            .tracking(-0.64)
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)

            Picker("Plan view", selection: $mode) {
                ForEach(PlanMode.allCases) { planMode in
                    Text(planMode.title).tag(planMode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Switch between one day and the full week")
            .padding(.top, AgentSpacing.x2)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PlanHeader where Actions == EmptyView {
    init(
        mode: Binding<PlanMode>,
        breadcrumb: String,
        profile: CreatorProfile?,
        firstLine: String,
        secondLine: String,
        openSettings: @escaping () -> Void
    ) {
        self.init(
            mode: mode,
            breadcrumb: breadcrumb,
            profile: profile,
            firstLine: firstLine,
            secondLine: secondLine,
            openSettings: openSettings,
            actions: { EmptyView() }
        )
    }
}
