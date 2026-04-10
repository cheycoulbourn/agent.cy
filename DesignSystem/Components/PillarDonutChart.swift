import SwiftUI

struct PillarDonutChart: View {
    let slices: [DonutSlice]
    var size: CGFloat = 120
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.borderLight.opacity(0.3), lineWidth: lineWidth)

            // Slices
            ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                Circle()
                    .trim(from: startAngle(for: index), to: endAngle(for: index))
                    .stroke(slice.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            // Center label
            VStack(spacing: 2) {
                Text("\(totalCount)")
                    .font(AppFont.title3(.bold))
                Text("posts")
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var totalCount: Int {
        slices.reduce(0) { $0 + $1.count }
    }

    private var totalValue: Double {
        let total = slices.reduce(0.0) { $0 + Double($1.count) }
        return total > 0 ? total : 1
    }

    private func startAngle(for index: Int) -> Double {
        let preceding = slices.prefix(index).reduce(0.0) { $0 + Double($1.count) }
        return preceding / totalValue
    }

    private func endAngle(for index: Int) -> Double {
        let preceding = slices.prefix(index + 1).reduce(0.0) { $0 + Double($1.count) }
        // Small gap between slices
        let gap = slices.count > 1 ? 0.008 : 0.0
        return max(startAngle(for: index), (preceding / totalValue) - gap)
    }
}

struct DonutSlice {
    let label: String
    let count: Int
    let target: Double
    let color: Color
}

#Preview {
    PillarDonutChart(slices: [
        DonutSlice(label: "Education", count: 5, target: 30, color: .blue),
        DonutSlice(label: "BTS", count: 3, target: 25, color: .purple),
        DonutSlice(label: "Promo", count: 4, target: 25, color: .orange),
        DonutSlice(label: "Trending", count: 2, target: 20, color: .pink),
    ])
}
