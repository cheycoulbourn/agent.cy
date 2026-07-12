import SwiftUI

struct SpeechCaptureStatusView: View {
    let state: SpeechCaptureState
    var context: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = state.presentation

        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            statusIndicator(for: presentation)
                .frame(width: 24, height: 24)
                .foregroundStyle(state.isRecording ? Color.cyAccent : Color.agentSecondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(presentation.title)
                    .font(.agentHeadline)
                Text(presentation.detail)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(state.isRecording ? Color.cyAccent : Color.agentBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle(for: presentation))
        .accessibilityValue(presentation.detail)
    }

    @ViewBuilder
    private func statusIndicator(for presentation: SpeechCapturePresentation) -> some View {
        if presentation.showsProgress && !reduceMotion {
            ProgressView()
                .controlSize(.small)
                .tint(.cyAccent)
        } else {
            Image(systemName: presentation.systemImage)
                .imageScale(.medium)
        }
    }

    private func accessibilityTitle(for presentation: SpeechCapturePresentation) -> String {
        guard let context, !context.isEmpty else { return presentation.title }
        return "\(context). \(presentation.title)"
    }
}
