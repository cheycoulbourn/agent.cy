import SwiftUI

struct AIConnectionsSettingsView: View {
    @AppStorage(AIConnectionMode.storageKey) private var selectedModeRaw = AIConnectionMode.cyIncluded.rawValue

    var body: some View {
        SettingsPageShell(
            kicker: "AI",
            title: "Cy connection",
            subtitle: "Cy is ready inside agent.cy."
        ) {
            AgentInsetSurface {
                HStack(alignment: .center, spacing: AgentSpacing.x4) {
                    ZStack {
                        Circle()
                            .fill(Color.cyAccent)
                            .frame(width: 48, height: 48)
                        CyAsterisk(color: .onCyAccent, size: 22, strokeWidth: 2)
                    }
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("Connected")
                            .font(.agentHeadline)
                        Text("Powered by Claude through agent.cy")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.agentSuccess)
                }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                SectionRuleHeader(title: "How it works")
                instruction(number: "1", text: "Ask Cy without leaving the app.")
                instruction(number: "2", text: "Only relevant context is sent for your request.")
                instruction(number: "3", text: "Your result returns directly to the conversation.")
            }

            Text("Your Claude consumer login and password are never requested or stored. AI access is handled securely by agent.cy.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            selectedModeRaw = AIConnectionMode.cyIncluded.rawValue
        }
    }

    private func instruction(number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
            Text(number)
                .font(.agentMono)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
