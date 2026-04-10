import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [CreatorProfile]
    @Query private var allContent: [ContentItem]
    @Query private var pillars: [ContentPillar]
    @Query private var inspirations: [Inspiration]
    @Query private var brandDeals: [BrandDeal]

    private var profile: CreatorProfile? { profiles.first }

    private var thisWeekContent: [ContentItem] {
        let calendar = Calendar.current
        let now = Date.now
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else {
            return []
        }
        return allContent.filter { item in
            guard let date = item.scheduledDate else { return false }
            return date >= startOfWeek && date < endOfWeek
        }
    }

    private var upcomingContent: [ContentItem] {
        allContent
            .filter { ($0.status == .scheduled || $0.status == .planned) && ($0.scheduledDate ?? .distantPast) >= Date.now }
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
    }

    private var activeDeals: [BrandDeal] {
        brandDeals.filter { [.pitched, .negotiating, .contracted, .inProgress].contains($0.status) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    greetingSection
                    quickStatsRow
                    weekAtAGlance
                    quickActions
                    aiSuggestionCard
                    pillarBalanceCard
                    upcomingContentCard
                    brandDealsCard
                    ideaInboxCard
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xxl)
            }
            .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.brandBrown)
                    }
                }
            }
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(greetingText)
                    .font(AppFont.title2())
                    .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(AppFont.subhead())
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            SparkPulse(size: 18)
        }
    }

    // MARK: - Quick Stats

    private var quickStatsRow: some View {
        HStack(spacing: Spacing.sm) {
            statCard(value: "\(thisWeekContent.count)", label: "This Week", icon: "calendar", color: .brandBrown)
            statCard(value: "\(inspirations.count)", label: "Ideas", icon: "lightbulb", color: .warning)
            statCard(value: "\(activeDeals.count)", label: "Deals", icon: "dollarsign.circle", color: .success)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(AppFont.title3(.bold))
                .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
            Text(label)
                .font(AppFont.caption())
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
        }
        .appShadow(AppShadow.subtle)
    }

    // MARK: - Week at a Glance

    private var weekAtAGlance: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("This Week")
                        .font(AppFont.headline())
                        .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                    Spacer()
                    NavigationLink {
                        ContentCalendarView()
                    } label: {
                        Text("See All")
                            .font(AppFont.caption(.medium))
                            .foregroundStyle(Color.brandBrown)
                    }
                }
                HStack(spacing: Spacing.xs) {
                    ForEach(weekDays, id: \.self) { day in
                        let dayItems = contentForDay(day)
                        VStack(spacing: Spacing.xxs) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(AppFont.caption())
                                .foregroundStyle(Color.textSecondary)

                            ZStack {
                                Circle()
                                    .fill(Calendar.current.isDateInToday(day)
                                        ? Color.brandBlack
                                        : (colorScheme == .dark ? Color.borderDark : Color.bgLight))
                                    .frame(width: 36, height: 36)

                                if Calendar.current.isDateInToday(day) {
                                    Circle()
                                        .strokeBorder(Color.brandPink, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                }

                                Text(day.formatted(.dateTime.day()))
                                    .font(AppFont.caption(.medium))
                                    .foregroundStyle(
                                        Calendar.current.isDateInToday(day)
                                            ? Color.white
                                            : (colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                                    )
                            }

                            HStack(spacing: 2) {
                                if dayItems.isEmpty {
                                    Circle().fill(Color.clear).frame(width: 5, height: 5)
                                } else {
                                    ForEach(Array(dayItems.prefix(3).enumerated()), id: \.offset) { _, item in
                                        Circle()
                                            .fill(item.pillar?.color ?? Color.textTertiary)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                            }
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                actionChip("Plan My Week", icon: "calendar.badge.plus", color: .brandBrown)
                actionChip("Write Caption", icon: "text.cursor", color: .brandPink)
                actionChip("Content Ideas", icon: "lightbulb.fill", color: .warning)
                actionChip("Trend Check", icon: "chart.line.uptrend.xyaxis", color: .success)
            }
            .padding(.horizontal, 1)
        }
    }

    private func actionChip(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
            Text(title)
                .font(AppFont.caption(.medium))
                .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
        }
        .appShadow(AppShadow.subtle)
    }

    // MARK: - AI Suggestion

    private var aiSuggestionCard: some View {
        ContentCard(isAI: true) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    SparkIcon(size: 14)
                    Text("Agent Cy")
                        .font(AppFont.caption(.semibold))
                        .foregroundStyle(Color.brandBrown)
                }

                Text(aiSuggestionText)
                    .font(AppFont.body())
                    .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)

                if !(profile?.onboardingCompleted ?? false) {
                    AppButton("Set Up Brand Voice", style: .ai, icon: "sparkles") {}
                        .padding(.top, Spacing.xxs)
                }
            }
        }
    }

    // MARK: - Pillar Balance

    private var pillarBalanceCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Pillar Balance")
                        .font(AppFont.headline())
                        .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                    Spacer()
                    NavigationLink("Manage") { PillarsView() }
                        .font(AppFont.caption(.medium))
                        .foregroundStyle(Color.brandBrown)
                }

                if pillars.isEmpty {
                    Text("Set up your content pillars to track balance.")
                        .font(AppFont.subhead())
                        .foregroundStyle(Color.textSecondary)
                } else {
                    HStack(spacing: Spacing.lg) {
                        PillarDonutChart(
                            slices: pillars.map { pillar in
                                DonutSlice(
                                    label: pillar.name,
                                    count: pillar.contentItems.count,
                                    target: pillar.targetPercentage,
                                    color: pillar.color
                                )
                            },
                            size: 100,
                            lineWidth: 12
                        )

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(pillars) { pillar in
                                HStack(spacing: Spacing.xs) {
                                    PillarDot(color: pillar.color)
                                    Text(pillar.name)
                                        .font(AppFont.caption(.medium))
                                        .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                                    Spacer()
                                    Text(pillarPercentage(for: pillar))
                                        .font(AppFont.caption())
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let warning = pillarWarning {
                        HStack(spacing: Spacing.xxs) {
                            SparkIcon(size: 12)
                            Text(warning)
                                .font(AppFont.caption())
                                .foregroundStyle(Color.brandBrown)
                        }
                        .padding(.top, Spacing.xxs)
                    }
                }
            }
        }
    }

    // MARK: - Upcoming Content

    private var upcomingContentCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Upcoming")
                        .font(AppFont.headline())
                        .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                    Spacer()
                    NavigationLink {
                        ContentCalendarView()
                    } label: {
                        Text("Calendar")
                            .font(AppFont.caption(.medium))
                            .foregroundStyle(Color.brandBrown)
                    }
                }

                if upcomingContent.isEmpty {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                        Text("Nothing scheduled yet")
                            .font(AppFont.subhead())
                            .foregroundStyle(Color.textSecondary)
                        Text("Start capturing ideas and plan your week!")
                            .font(AppFont.caption())
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                } else {
                    ForEach(Array(upcomingContent.prefix(4).enumerated()), id: \.element.persistentModelID) { index, item in
                        HStack(spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.pillar?.color ?? Color.textTertiary)
                                .frame(width: 3, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(AppFont.subhead(.medium))
                                    .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: Spacing.xxs) {
                                    if let date = item.scheduledDate {
                                        Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
                                            .font(AppFont.caption())
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    if !item.platforms.isEmpty {
                                        Text("·").foregroundStyle(Color.textTertiary)
                                        HStack(spacing: 2) {
                                            ForEach(item.platforms.prefix(2), id: \.self) { platform in
                                                Image(systemName: platform.systemIcon)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }

                            Spacer()
                            StatusBadge(status: item.status)
                        }

                        if index < min(upcomingContent.count, 4) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Brand Deals

    @ViewBuilder
    private var brandDealsCard: some View {
        if !activeDeals.isEmpty {
            ContentCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Active Deals")
                            .font(AppFont.headline())
                            .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                        Spacer()
                        Text("\(activeDeals.count)")
                            .font(AppFont.caption(.semibold))
                            .foregroundStyle(Color.success)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxxs)
                            .background(Color.success.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    ForEach(activeDeals.prefix(3)) { deal in
                        HStack(spacing: Spacing.sm) {
                            Circle()
                                .fill(Color.brandBeige)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(String(deal.brandName.prefix(1)).uppercased())
                                        .font(AppFont.caption(.semibold))
                                        .foregroundStyle(Color.brandBrown)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(deal.brandName)
                                    .font(AppFont.subhead(.medium))
                                    .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                                    .lineLimit(1)
                                Text(deal.status.displayName)
                                    .font(AppFont.caption())
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer()

                            if let amount = deal.paymentAmount {
                                Text("$\(NSDecimalNumber(decimal: amount).intValue)")
                                    .font(AppFont.subhead(.semibold))
                                    .foregroundStyle(Color.success)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Idea Inbox

    private var ideaInboxCard: some View {
        ContentCard {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text("Idea Inbox")
                            .font(AppFont.headline())
                            .foregroundStyle(colorScheme == .dark ? Color.textOnDark : Color.textPrimary)
                        if !inspirations.isEmpty {
                            Text("\(inspirations.count)")
                                .font(AppFont.caption(.semibold))
                                .foregroundStyle(Color.brandBrown)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxxs)
                                .background(Color.brandBrown.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(inspirations.isEmpty
                         ? "Capture ideas from anywhere with the Share Extension"
                         : "\(inspirations.count) ideas saved")
                        .font(AppFont.subhead())
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = profile?.displayName ?? "Creator"
        switch hour {
        case 5..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = weekday == 1 ? -6 : -(weekday - 2)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func contentForDay(_ day: Date) -> [ContentItem] {
        let calendar = Calendar.current
        return allContent.filter { item in
            guard let date = item.scheduledDate else { return false }
            return calendar.isDate(date, inSameDayAs: day)
        }
    }

    private var aiSuggestionText: String {
        if !(profile?.onboardingCompleted ?? false) {
            return "Start by setting up your content pillars and brand voice. I'll learn your style and help you plan content that's unmistakably you."
        }
        if thisWeekContent.isEmpty {
            return "You don't have anything planned this week yet. Want me to suggest some content ideas based on your pillars?"
        }
        let target = profile?.weeklyPostTarget ?? 3
        if thisWeekContent.count < target {
            return "You have \(thisWeekContent.count) of \(target) posts planned this week. Want me to help fill the gaps?"
        }
        return "You're on track this week! Keep the momentum going."
    }

    private func pillarPercentage(for pillar: ContentPillar) -> String {
        let total = pillars.reduce(0) { $0 + $1.contentItems.count }
        guard total > 0 else { return "\(Int(pillar.targetPercentage))% target" }
        let actual = Int(Double(pillar.contentItems.count) / Double(total) * 100)
        return "\(actual)% / \(Int(pillar.targetPercentage))%"
    }

    private var pillarWarning: String? {
        let total = pillars.reduce(0) { $0 + $1.contentItems.count }
        guard total >= 3 else { return nil }
        for pillar in pillars {
            let actual = Double(pillar.contentItems.count) / Double(total) * 100
            let diff = actual - pillar.targetPercentage
            if diff > 15 { return "You're heavy on \(pillar.name) — consider diversifying this week." }
            if diff < -15 { return "You haven't posted much \(pillar.name) content lately." }
        }
        return nil
    }
}

#Preview {
    DashboardView()
}
