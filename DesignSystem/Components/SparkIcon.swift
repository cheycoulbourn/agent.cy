import SwiftUI

struct SparkIcon: View {
    var size: CGFloat = 20
    var isAnimating: Bool = false

    @State private var opacity: Double = 1.0

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Color.aiAccent)
            .opacity(opacity)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = 0.5
                }
            }
    }
}

struct SparkPulse: View {
    var size: CGFloat = 24

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.aiAccent.opacity(0.15))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(scale)
                .opacity(opacity)

            SparkIcon(size: size, isAnimating: true)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                scale = 1.3
                opacity = 0.2
            }
        }
    }
}

#Preview {
    VStack(spacing: Spacing.xxl) {
        SparkIcon()
        SparkIcon(size: 32, isAnimating: true)
        SparkPulse()
    }
}
