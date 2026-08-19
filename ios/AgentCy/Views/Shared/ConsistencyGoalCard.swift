import SwiftUI

/// Shared body of the Consistency card on the phone Home dashboard and the
/// desktop utility rail. The host provides the card chrome; this view owns
/// the goal states: unset prompt, below-goal progress, and goal-met health.
struct ConsistencyGoalCard: View {
    let snapshot: WeeklyConsistencySnapshot
    /// One flag per trailing week (oldest first, current week last): whether
    /// that week met the goal. Rendered as the card's signature week bars —
    /// day-level detail belongs to Week at a glance, not here.
    let weeklyGoalMet: [Bool]
    let streak: Int
    let onEditGoal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Consistency")
                Spacer()
                if snapshot.goalState == .met {
                    goalMetChip
                } else if let goal = snapshot.goal {
                    Text("Goal \(goal)/wk")
                        .font(.agentMetadata)
                        .tracking(0.7)
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            switch snapshot.goalState {
            case .unset:
                unsetPrompt
            case .below, .met:
                weekBars
                statusLine
                if streak > 0 {
                    Text(streak == 1 ? "1 week on your goal" : "\(streak) weeks on your goal")
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                }
            }
        }
        .foregroundStyle(Color.agentText)
    }

    // The empty state previews the card's own week bars, quiet until a goal
    // gives them a score to keep.
    private var unsetPrompt: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            weekBars

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text("Set a weekly posting goal")
                    .font(.agentBody.weight(.semibold))
                Text("Pick your days per week — each bar fills when a week hits the goal.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onEditGoal) {
                Text("Set goal")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .padding(.horizontal, AgentSpacing.x5)
                    .frame(minHeight: 44)
                    .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityHint("Sets how many days a week you aim to post")
        }
    }

    private var weekBars: some View {
        HStack(spacing: 6) {
            ForEach(Array(weeklyGoalMet.enumerated()), id: \.offset) { index, met in
                Capsule()
                    .fill(met ? Color.agentSuccess : Color.agentHairline)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(weekBarLabel(at: index))
                    .accessibilityValue(met ? "Goal met" : "Goal not met")
            }
        }
        .frame(height: 5)
        .padding(.vertical, AgentSpacing.x1)
    }

    private func weekBarLabel(at index: Int) -> String {
        let weeksAgo = weeklyGoalMet.count - 1 - index
        return weeksAgo == 0 ? "This week" : "\(weeksAgo) weeks ago"
    }

    private var statusLine: some View {
        Group {
            if let goal = snapshot.goal {
                if snapshot.goalState == .met {
                    Text("\(snapshot.postedDayCount) of \(goal) days — goal met")
                        .font(.agentBody.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.agentSuccess)
                } else {
                    Text("\(snapshot.postedDayCount) of \(goal) days this week")
                        .font(.agentBody.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(remainingDaysCanStillMeetGoal ? Color.agentText : Color.agentPriorityHigh)
                }
            }
        }
    }

    private var goalMetChip: some View {
        HStack(spacing: AgentSpacing.x1) {
            CyAsterisk(color: .agentSuccess, size: 11, strokeWidth: 1.3)
            Text("Goal met")
                .font(.agentMetadata)
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.agentSuccess)
        }
        .padding(.horizontal, AgentSpacing.x2)
        .frame(minHeight: 22)
        .background(Color.agentSuccess.opacity(0.1), in: .capsule)
    }

    /// Days left this week (today included) plus days already posted still
    /// reaching the goal keeps the tone neutral; once the goal is out of
    /// reach for the week, the count turns to the warning color.
    private var remainingDaysCanStillMeetGoal: Bool {
        guard let goal = snapshot.goal,
              let todayIndex = snapshot.days.firstIndex(where: \.isToday) else { return true }
        let remainingDays = snapshot.days[todayIndex...].filter { !$0.hasPost }.count
        return snapshot.postedDayCount + remainingDays >= goal
    }
}

/// Goal picker presented from the consistency card and onboarding. One row of
/// day-count choices; saving clamps to 1–7.
struct ConsistencyGoalEditorView: View {
    let currentGoal: Int?
    let onSave: (Int) -> Void
    let onRemove: (() -> Void)?
    let onClose: () -> Void

    @State private var selection: Int

    init(
        currentGoal: Int?,
        onSave: @escaping (Int) -> Void,
        onRemove: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.currentGoal = currentGoal
        self.onSave = onSave
        self.onRemove = onRemove
        self.onClose = onClose
        _selection = State(initialValue: currentGoal ?? 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            HStack(alignment: .top) {
                Text("Weekly posting goal")
                    .font(.agentHeadline)
                Spacer(minLength: AgentSpacing.x4)
                AgentToolbarIconButton(title: "Close", icon: .close, action: onClose)
            }

            Text("How many days a week do you want to post? Multiple posts on one day count as one day.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AgentSpacing.x2) {
                ForEach(Array(WeeklyConsistencyPolicy.goalRange), id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        Text("\(value)")
                            .font(.agentBody.weight(selection == value ? .semibold : .regular))
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selection == value ? Color.agentSelectionFill : Color.agentCanvas,
                                in: .rect(cornerRadius: AgentRadius.control)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(
                                        selection == value ? Color.agentText.opacity(0.4) : Color.agentBorder,
                                        lineWidth: 1
                                    )
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())
                    .accessibilityLabel("\(value) days a week")
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }

            HStack(spacing: AgentSpacing.x3) {
                Button("Save goal") {
                    onSave(WeeklyConsistencyPolicy.clampedGoal(selection))
                }
                .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))

                if currentGoal != nil, let onRemove {
                    Button("Remove", role: .destructive, action: onRemove)
                        .buttonStyle(AgentQuietDestructiveButtonStyle())
                }
            }
        }
        .padding(AgentSpacing.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.agentCanvas.ignoresSafeArea())
    }
}
