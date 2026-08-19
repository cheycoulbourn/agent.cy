#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private struct CreatorSessionLiveTimerText: View {
    let state: CreatorSessionAttributes.ContentState
    let font: Font

    var body: some View {
        Group {
            if state.isPaused {
                Text(Self.clockText(seconds: state.remainingSeconds))
            } else {
                Text(timerInterval: Date()...max(Date(), state.endDate), countsDown: true)
            }
        }
        .font(font.monospacedDigit())
    }

    private static func clockText(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        return String(format: "%02d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

/// The Creator Session's system-surface identity. WidgetKit caps Live Activity
/// animations at two seconds and suppresses them on Always-On displays, so the
/// asterisk makes one slow partial turn when session state changes instead of
/// promising an unsupported continuous animation.
private struct CreatorSessionLiveCyBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let size: CGFloat
    let state: CreatorSessionAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: AgentColorPalette.cy.uiColor))

            ZStack {
                ForEach([0.0, 45.0, 90.0, 135.0], id: \.self) { angle in
                    Capsule()
                        .fill(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                        .frame(width: max(1.5, size * 0.07), height: size * 0.52)
                        .rotationEffect(.degrees(angle))
                }
            }
            .rotationEffect(.degrees(motionAngle))
            .animation(
                reduceMotion || isLuminanceReduced ? nil : .linear(duration: 2),
                value: motionAngle
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Creator Session")
    }

    private var motionAngle: Double {
        let phaseStep: Int = switch state.phase {
        case .focus: 0
        case .shortBreak: 1
        case .longBreak: 2
        }
        let stateStep = ((max(1, state.currentRound) - 1) * 4)
            + phaseStep
            + (state.isPaused ? 1 : 0)
            + (state.isFinished ? 2 : 0)
        return Double(stateStep) * 45
    }
}

private struct CreatorSessionLiveStopIcon: View {
    var body: some View {
        Image("agent-icon-stop")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}

struct CreatorSessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CreatorSessionAttributes.self) { context in
            HStack(spacing: 14) {
                CreatorSessionLiveCyBadge(size: 42, state: context.state)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.mode.title.uppercased())
                        .font(.widgetMetadata(size: 9))
                        .tracking(0.8)
                        .foregroundStyle(Color(uiColor: AgentColorPalette.secondaryDark.uiColor))
                    Text(context.attributes.linkedPostTitle ?? context.attributes.title)
                        .font(.widgetInter(size: 15, weight: .semibold))
                        .foregroundStyle(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                CreatorSessionLiveTimerText(
                    state: context.state,
                    font: .widgetInter(size: 20, weight: .bold)
                )
                    .foregroundStyle(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                    .minimumScaleFactor(0.84)

                Button(intent: EndCreatorSessionIntent(sessionID: context.attributes.sessionID)) {
                    CreatorSessionLiveStopIcon()
                        .frame(width: 12, height: 12)
                        .frame(width: 34, height: 34)
                        .background(
                            Color(uiColor: AgentColorPalette.inkDark.uiColor).opacity(0.10),
                            in: .circle
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color(uiColor: AgentColorPalette.inkDark.uiColor).opacity(0.24),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .tint(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                .accessibilityLabel("End Creator Session")
            }
            .padding(.horizontal, 16)
            .activityBackgroundTint(Color(uiColor: AgentColorPalette.surfaceDark.uiColor))
            .activitySystemActionForegroundColor(Color(uiColor: AgentColorPalette.inkDark.uiColor))
            .widgetURL(AgentCyDeepLink.creatorSession.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        CreatorSessionLiveCyBadge(size: 22, state: context.state)
                        Text(context.attributes.mode.title)
                    }
                        .font(.widgetInter(size: 12, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CreatorSessionLiveTimerText(
                        state: context.state,
                        font: .widgetInter(size: 12, weight: .semibold)
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.linkedPostTitle ?? context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Button(intent: EndCreatorSessionIntent(sessionID: context.attributes.sessionID)) {
                            HStack(spacing: 5) {
                                CreatorSessionLiveStopIcon()
                                    .frame(width: 11, height: 11)
                                Text("End")
                            }
                                .font(.widgetInter(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                CreatorSessionLiveCyBadge(size: 18, state: context.state)
            } compactTrailing: {
                CreatorSessionLiveTimerText(
                    state: context.state,
                    font: .widgetInter(size: 10, weight: .medium)
                )
                    .frame(width: 42)
            } minimal: {
                CreatorSessionLiveCyBadge(size: 20, state: context.state)
            }
            .widgetURL(AgentCyDeepLink.creatorSession.url)
            .keylineTint(Color(uiColor: AgentColorPalette.cyTextDark.uiColor))
        }
    }
}
#endif
