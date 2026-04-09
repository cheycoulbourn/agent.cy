import SwiftUI

struct PillarBadge: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(AppFont.caption(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxxs)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct PillarDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: Spacing.xs) {
        PillarBadge(name: "Education", color: .blue)
        PillarBadge(name: "BTS", color: .purple)
        PillarBadge(name: "Promo", color: .orange)
    }
}
