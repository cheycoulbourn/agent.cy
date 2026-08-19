import SwiftUI

enum AgentSwipeDeleteInteractionPolicy {
    static func isHorizontalIntent(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }

    static func blocksContent(
        isRevealed: Bool,
        isHorizontalDragActive: Bool,
        isReleaseSuppressed: Bool
    ) -> Bool {
        isRevealed || isHorizontalDragActive || isReleaseSuppressed
    }
}

/// A compact, interruptible swipe reveal for rows that live inside a ScrollView.
/// Native `swipeActions` only participate in `List`, while these creator flows
/// intentionally use the app's existing dashboard scroll surfaces.
struct AgentSwipeDeleteRow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var isRevealed = false
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDragActive = false
    @State private var isReleaseSuppressed = false
    @State private var releaseSuppressionTask: Task<Void, Never>?

    private let actionWidth: CGFloat = 64

    init(
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
#if targetEnvironment(macCatalyst)
        content
#else
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                isRevealed = false
                dragOffset = 0
                onDelete()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.agentDestructive)
                    AgentIconView(.trash, size: 17)
                        .foregroundStyle(Color.agentPureWhite)
                }
                .frame(width: 48, height: 48)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .contentShape(.circle)
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityLabel("Delete recording")

            content
                .disabled(blocksContentInteraction)
                .overlay {
                    if blocksContentInteraction {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: closeRevealedRow)
                    }
                }
                .offset(x: resolvedOffset)
                .simultaneousGesture(swipeGesture)
        }
        .clipShape(.rect(cornerRadius: AgentRadius.card))
        .accessibilityAction(named: "Delete recording", onDelete)
        .onDisappear {
            releaseSuppressionTask?.cancel()
        }
#endif
    }

#if !targetEnvironment(macCatalyst)
    private var blocksContentInteraction: Bool {
        AgentSwipeDeleteInteractionPolicy.blocksContent(
            isRevealed: isRevealed,
            isHorizontalDragActive: isHorizontalDragActive,
            isReleaseSuppressed: isReleaseSuppressed
        )
    }

    private var resolvedOffset: CGFloat {
        let restingOffset = isRevealed ? -actionWidth : 0
        return min(0, max(-actionWidth, restingOffset + dragOffset))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard AgentSwipeDeleteInteractionPolicy.isHorizontalIntent(value.translation) else { return }
                releaseSuppressionTask?.cancel()
                isHorizontalDragActive = true
                isReleaseSuppressed = true
                let restingOffset = isRevealed ? -actionWidth : 0
                let proposedOffset = min(0, max(-actionWidth, restingOffset + value.translation.width))
                dragOffset = proposedOffset - restingOffset
            }
            .onEnded { value in
                guard AgentSwipeDeleteInteractionPolicy.isHorizontalIntent(value.translation) else {
                    dragOffset = 0
                    isHorizontalDragActive = false
                    return
                }
                let restingOffset = isRevealed ? -actionWidth : 0
                let projectedOffset = min(
                    0,
                    max(-actionWidth, restingOffset + value.predictedEndTranslation.width)
                )
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    isRevealed = projectedOffset < -(actionWidth / 2)
                    dragOffset = 0
                }
                isHorizontalDragActive = false
                suppressContentActionsAfterRelease()
            }
    }

    private func closeRevealedRow() {
        guard isRevealed else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            isRevealed = false
            dragOffset = 0
        }
        suppressContentActionsAfterRelease()
    }

    private func suppressContentActionsAfterRelease() {
        releaseSuppressionTask?.cancel()
        isReleaseSuppressed = true
        releaseSuppressionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isReleaseSuppressed = false
        }
    }
#endif
}
