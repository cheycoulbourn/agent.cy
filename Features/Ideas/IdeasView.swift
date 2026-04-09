import SwiftUI
import SwiftData

struct IdeasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Inspiration.createdAt, order: .reverse) private var inspirations: [Inspiration]
    @State private var selectedFilter: InspirationSourceType?
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    filterBar
                    inspirationList
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
            .navigationTitle("Ideas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(.brandBlack)
                }
            }
            .sheet(isPresented: $showCapture) {
                QuickCaptureView()
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                FilterChip(title: "All", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                ForEach(InspirationSourceType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.displayName,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = type
                    }
                }
            }
        }
        .padding(.top, Spacing.xs)
    }

    private var inspirationList: some View {
        LazyVStack(spacing: Spacing.sm) {
            let filtered = selectedFilter == nil
                ? inspirations
                : inspirations.filter { $0.sourceType == selectedFilter }

            if filtered.isEmpty {
                emptyState
            } else {
                ForEach(filtered) { item in
                    InspirationCard(inspiration: item)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "lightbulb")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandBeige)
            Text("No ideas yet")
                .font(AppFont.title3())
            Text("Capture ideas from anywhere — text, photos, links, or voice memos.")
                .font(AppFont.subhead())
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
            AppButton("Capture an Idea", style: .primary, icon: "plus") {
                showCapture = true
            }
            .frame(width: 200)
        }
        .padding(.vertical, Spacing.xxxl)
    }
}

// MARK: - Supporting Views

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption(.medium))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .foregroundStyle(isSelected ? .white : .textSecondary)
                .background(isSelected ? Color.brandBlack : Color.clear)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : (colorScheme == .dark ? Color.borderDark : Color.borderLight),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

struct InspirationCard: View {
    let inspiration: Inspiration

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: inspiration.sourceType.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.brandBrown)
                    Text(inspiration.sourceType.displayName)
                        .font(AppFont.caption(.medium))
                        .foregroundStyle(.brandBrown)
                    Spacer()
                    Text(inspiration.createdAt, style: .relative)
                        .font(AppFont.caption())
                        .foregroundStyle(.textTertiary)
                }

                if let title = inspiration.title {
                    Text(title)
                        .font(AppFont.headline())
                        .lineLimit(2)
                }

                if let notes = inspiration.notes, !notes.isEmpty {
                    Text(notes)
                        .font(AppFont.subhead())
                        .foregroundStyle(.textSecondary)
                        .lineLimit(3)
                }

                if let pillar = inspiration.pillar {
                    PillarBadge(name: pillar.name, color: pillar.color)
                }

                AppButton("Develop with AI", style: .ai, icon: "sparkles") {
                    // Navigate to AI development
                }
            }
        }
    }
}

#Preview {
    IdeasView()
}
