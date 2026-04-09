import SwiftUI

struct ContentCard<Content: View>: View {
    let isAI: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    init(isAI: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.isAI = isAI
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            if isAI {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.aiAccent)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.xs)
            }

            content()
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .strokeBorder(
                    colorScheme == .dark ? Color.borderDark : Color.borderLight,
                    lineWidth: 0.5
                )
        }
        .appShadow(AppShadow.card)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        ContentCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Morning Routine Reel")
                    .font(AppFont.headline())
                Text("Instagram Reel")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }

        ContentCard(isAI: true) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.aiAccent)
                    Text("AI Suggestion")
                        .font(AppFont.caption(.semibold))
                        .foregroundStyle(Color.brandBrown)
                }
                Text("Your education content is performing well. Consider a carousel this week.")
                    .font(AppFont.body())
            }
        }
    }
    .padding()
}
