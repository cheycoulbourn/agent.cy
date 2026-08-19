import Foundation

/// The consistency card counts days of the week against a creator-set weekly
/// posting goal. Multiple posts on one day still count as one posted day —
/// the goal is a rhythm, not a volume target.
struct WeeklyConsistencySnapshot: Equatable {
    struct Day: Equatable, Identifiable {
        let symbol: String
        let date: Date
        let hasPost: Bool
        let isToday: Bool
        var id: Date { date }
    }

    enum GoalState: Equatable {
        case unset
        case below
        case met
    }

    let days: [Day]
    let postedDayCount: Int
    let goal: Int?
    let goalState: GoalState
}

enum WeeklyConsistencyPolicy {
    static let goalRange = 1...7

    static func clampedGoal(_ raw: Int) -> Int {
        min(max(raw, goalRange.lowerBound), goalRange.upperBound)
    }

    static func snapshot(
        postedDates: [Date],
        goal: Int?,
        weekStart: Date,
        calendar: Calendar,
        today: Date
    ) -> WeeklyConsistencySnapshot {
        let postedDays = Set(postedDates.map { calendar.startOfDay(for: $0) })
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekStart = calendar.startOfDay(for: weekStart)
        let days = (0..<7).compactMap { offset -> WeeklyConsistencySnapshot.Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: dayStart)
            return WeeklyConsistencySnapshot.Day(
                symbol: symbols[weekday - 1],
                date: dayStart,
                hasPost: postedDays.contains(dayStart),
                isToday: calendar.isDate(dayStart, inSameDayAs: today)
            )
        }
        let postedDayCount = days.filter(\.hasPost).count
        let goalState: WeeklyConsistencySnapshot.GoalState
        if let goal {
            goalState = postedDayCount >= clampedGoal(goal) ? .met : .below
        } else {
            goalState = .unset
        }
        return WeeklyConsistencySnapshot(
            days: days,
            postedDayCount: postedDayCount,
            goal: goal.map(clampedGoal),
            goalState: goalState
        )
    }

    /// Distinct posted days per week, oldest week first, current week last.
    static func weeklyPostedDayCounts(
        postedDates: [Date],
        weekCount: Int,
        currentWeekStart: Date,
        calendar: Calendar
    ) -> [Int] {
        // Posted days are start-of-day normalized, so the week boundaries
        // must be too — a mid-day week start would misfile boundary days.
        let currentWeekStart = calendar.startOfDay(for: currentWeekStart)
        let postedDays = Set(postedDates.map { calendar.startOfDay(for: $0) })
        return ((1 - weekCount)...0).compactMap { offset -> Int? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeekStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            return postedDays.filter { $0 >= start && $0 < end }.count
        }
    }

    /// Consecutive weeks meeting the goal, counted backward from the current
    /// week. The streak survives only while every week hits the goal.
    static func goalStreak(weeklyPostedDayCounts: [Int], goal: Int) -> Int {
        let target = clampedGoal(goal)
        return weeklyPostedDayCounts.reversed().prefix(while: { $0 >= target }).count
    }
}
