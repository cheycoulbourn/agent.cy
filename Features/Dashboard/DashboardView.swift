import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [CreatorProfile]
    @Query(
        filter: #Predicate<ContentItem> { $0.status == .scheduled || $0.status == .planned },
        sort: \ContentItem.scheduledDate
    ) private var upcomingContent: [ContentItem]
    @Query private var pillars: [ContentPillar]

    private var profile: CreatorProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    greetingSection
                    weekAtAGlance
                    pillarBalance
                    aiSuggestion
                    upcomingSection
                    ideaInboxPreview
                }
                .padding(.horizontal, Spacing.md)
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

    // MARK: - Sections

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(greetingText)
                .font(AppFont.title2())
                .foregroundStyle(colorScheme == .dark ? .textOnDark : .textPrimary)
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(AppFont.subhead())
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
    }

    private var weekAtAGlance: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("This Week")
                    .font(AppFont.headline())
                HStack(spacing: Spacing.xs) {
                    ForEach(weekDays, id: \.self) { day in
                        VStack(spacing: Spacing.xxs) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(AppFont.caption())
                                .foregroundStyle(.textSecondary)
                            Circle()
                                .fill(day.isToday ? Color.brandBlack : Color.borderLight)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text(day.formatted(.dateTime.day()))
                                        .font(AppFont.caption(.medium))
                                        .foregroundStyle(
                                            day.isToday
                                                ? (colorScheme == .dark ? .brandBlack : .white)
                                                : .textSecondary
                                        )
                                }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var pillarBalance: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Pillar Balance")
                        .font(AppFont.headline())
                    Spacer()
                    NavigationLink("Manage") {
                        PillarsView()
                    }
                    .font(AppFont.caption(.medium))
                    .foregroundStyle(.brandBrown)
                }

                if pillars.isEmpty {
                    Text("Set up your content pillars to track balance.")
                        .font(AppFont.subhead())
                        .foregroundStyle(.textSecondary)
                } else {
                    HStack(spacing: Spacing.sm) {
                        ForEach(pillars) { pillar in
                            HStack(spacing: Spacing.xxs) {
                                PillarDot(color: pillar.color)
                                Text(pillar.name)
                                    .font(AppFont.caption())
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var aiSuggestion: some View {
        ContentCard(isAI: true) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    SparkIcon(size: 14)
                    Text("Agent Cy")
                        .font(AppFont.caption(.semibold))
                        .foregroundStyle(.brandBrown)
                }
                Text("Start by setting up your content pillars and brand voice. I'll learn your style and help you plan content that's unmistakably you.")
                    .font(AppFont.body())

                AppButton("Set Up Brand Voice", style: .ai, icon: "sparkles") {
                    // Navigate to brand voice setup
                }
                .padding(.top, Spacing.xxs)
            }
        }
    }

    private var upcomingSection: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Upcoming Content")
                    .font(AppFont.headline())
                if upcomingContent.isEmpty {
                    Text("Nothing scheduled yet. Start capturing ideas!")
                        .font(AppFont.subhead())
                        .foregroundStyle(.textSecondary)
                } else {
                    ForEach(upcomingContent.prefix(3)) { item in
                        HStack {
                            if let pillar = item.pillar {
                                PillarDot(color: pillar.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(AppFont.subhead(.medium))
                                    .lineLimit(1)
                                if let date = item.scheduledDate {
                                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(AppFont.caption())
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                            Spacer()
                            StatusBadge(status: item.status)
                        }
                    }
                }
            }
        }
    }

    private var ideaInboxPreview: some View {
        ContentCard {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Idea Inbox")
                        .font(AppFont.headline())
                    Text("Capture and develop your ideas")
                        .font(AppFont.subhead())
                        .foregroundStyle(.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.textTertiary)
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
        let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 2), to: today)!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }
}

private extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}

#Preview {
    DashboardView()
}
