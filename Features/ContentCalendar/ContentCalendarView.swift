import SwiftUI
import SwiftData

struct ContentCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ContentItem.scheduledDate) private var contentItems: [ContentItem]
    @State private var selectedDate: Date = .now
    @State private var viewMode: CalendarViewMode = .week
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                viewModePicker
                calendarContent
            }
            .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(.brandBlack)
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                QuickCaptureView()
            }
        }
    }

    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue.capitalized).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch viewMode {
        case .week:
            weekView
        case .month:
            monthView
        }
    }

    private var weekView: some View {
        ScrollView {
            VStack(spacing: Spacing.sm) {
                // Week header
                HStack(spacing: Spacing.xs) {
                    ForEach(currentWeekDates, id: \.self) { date in
                        dayColumn(date: date)
                    }
                }
                .padding(.horizontal, Spacing.md)

                Divider()

                // Content for selected date
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(AppFont.headline())
                        .padding(.horizontal, Spacing.md)

                    let dayItems = contentItems.filter { item in
                        guard let date = item.scheduledDate else { return false }
                        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    }

                    if dayItems.isEmpty {
                        ContentCard(isAI: true) {
                            HStack {
                                SparkIcon(size: 14)
                                Text("No content planned. Want me to suggest something?")
                                    .font(AppFont.subhead())
                                    .foregroundStyle(.textSecondary)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    } else {
                        ForEach(dayItems) { item in
                            calendarItemCard(item)
                                .padding(.horizontal, Spacing.md)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    private var monthView: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(AppFont.title3())
                    .padding(.top, Spacing.sm)

                // Simple month grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: Spacing.xs) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                        Text(day)
                            .font(AppFont.caption(.medium))
                            .foregroundStyle(.textTertiary)
                    }

                    ForEach(monthDates, id: \.self) { date in
                        if let date {
                            monthDayCell(date: date)
                        } else {
                            Color.clear
                                .frame(height: 40)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    private func dayColumn(date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(date)
        let hasContent = contentItems.contains { item in
            guard let d = item.scheduledDate else { return false }
            return Calendar.current.isDate(d, inSameDayAs: date)
        }

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: Spacing.xxs) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(AppFont.caption())
                    .foregroundStyle(.textSecondary)
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.brandBlack : Color.clear)
                        .frame(width: 36, height: 36)
                    Text(date.formatted(.dateTime.day()))
                        .font(AppFont.subhead(isToday ? .bold : .regular))
                        .foregroundStyle(isSelected ? .white : (isToday ? .brandBlack : .textSecondary))
                }
                if hasContent {
                    Circle()
                        .fill(Color.brandPink)
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func monthDayCell(date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)

        return Button {
            selectedDate = date
            viewMode = .week
        } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day()))
                    .font(AppFont.subhead(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Color.brandBlack : Color.clear)
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .frame(height: 40)
    }

    private func calendarItemCard(_ item: ContentItem) -> some View {
        ContentCard {
            HStack {
                if let pillar = item.pillar {
                    PillarDot(color: pillar.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppFont.subhead(.medium))
                        .lineLimit(1)
                    HStack(spacing: Spacing.xxs) {
                        ForEach(item.platforms, id: \.self) { platform in
                            PlatformIcon(platform: platform, size: 16)
                        }
                        Text(item.format.displayName)
                            .font(AppFont.caption())
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                StatusBadge(status: item.status)
            }
        }
    }

    // MARK: - Date Helpers

    private var currentWeekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: today)
        let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 2), to: today)!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: selectedDate)!
        let firstDay = interval.start
        let firstWeekday = (calendar.component(.weekday, from: firstDay) + 5) % 7 // Monday = 0

        var dates: [Date?] = Array(repeating: nil, count: firstWeekday)
        var current = firstDay
        while current < interval.end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }
}

enum CalendarViewMode: String, CaseIterable {
    case week
    case month
}

#Preview {
    ContentCalendarView()
}
