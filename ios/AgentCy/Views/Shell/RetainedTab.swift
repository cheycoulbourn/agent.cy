import SwiftUI

extension EnvironmentValues {
    @Entry var agentTabIsActive = true
}

/// Builds a tab on first selection, then preserves its navigation and draft state.
/// Hidden tabs can suspend periodic work through `agentTabIsActive`.
struct RetainedTab<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: () -> Content
    @State private var hasBeenSelected = false

    var body: some View {
        Group {
            if isSelected || hasBeenSelected {
                content()
                    .environment(\.agentTabIsActive, isSelected)
            }
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
        .zIndex(isSelected ? 1 : 0)
        .onChange(of: isSelected, initial: true) { _, selected in
            if selected { hasBeenSelected = true }
        }
        .transaction { $0.animation = nil }
    }
}
