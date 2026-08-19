import SwiftUI

/// Keeps a running Creator Session visible after its editor is dismissed.
/// The shared record remains the source of truth so reopening the session and
/// the Live Activity always return to the same interval.
struct ActiveCreatorSessionFloatingTimer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isEnabled: Bool
    let onOpen: () -> Void

    @State private var session: ActiveCreatorSessionRecord?
    @State private var now = Date()

    var body: some View {
        Group {
            if isEnabled, let session {
                Button(action: onOpen) {
                    HStack(spacing: AgentSpacing.x3) {
                        CyAsterisk(color: .cyAccent, size: 18, strokeWidth: 1.8)
                            .frame(width: 26, height: 26)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.phase.title.uppercased())
                                .font(.agentMetadata.weight(.semibold))
                                .tracking(1)
                                .foregroundStyle(Color.agentSecondary)
                            Text(session.linkedPostTitle ?? session.displayTitle)
                                .font(.agentSubtext.weight(.semibold))
                                .foregroundStyle(Color.agentText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: AgentSpacing.x2)

                        Text(clockText(session.remainingSeconds(at: now)))
                            .font(.agentHeadline.monospacedDigit())
                            .foregroundStyle(Color.agentText)
                            .contentTransition(.numericText(countsDown: true))

                        Circle()
                            .trim(from: 0, to: max(0.02, session.progress(at: now)))
                            .stroke(accent(for: session), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 18, height: 18)
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 56)
#if targetEnvironment(macCatalyst)
                    .background(Color.agentSurface, in: .capsule)
                    .overlay {
                        Capsule()
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
#else
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .overlay {
                        Capsule()
                            .stroke(Color.agentPureWhite.opacity(0.22), lineWidth: 0.5)
                    }
#endif
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityLabel("Open active Creator Session, \(clockText(session.remainingSeconds(at: now))) remaining")
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
#if targetEnvironment(macCatalyst)
        .frame(width: 360)
#else
        .frame(maxWidth: 340)
#endif
        .task(id: isEnabled) {
            guard isEnabled else { return }
            while !Task.isCancelled {
                now = Date()
                if let stored = CreatorSessionRecordStore.load() {
                    if !stored.isPaused, stored.remainingSeconds(at: now) == 0 {
                        session = await CreatorSessionActivityController.advance(stored, now: now)
                    } else {
                        session = stored
                    }
                } else {
                    session = nil
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session?.sessionID)
    }

    private func accent(for session: ActiveCreatorSessionRecord) -> Color {
        Color(agentHex: session.accentColorHex ?? "895A38")
    }

    private func clockText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let remainingSeconds = safe % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
