import SwiftData
import SwiftUI

struct AIConnectionsSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var subscriptions: [SubscriptionState]
    @State private var availability: CyAvailabilityState = .checking

    var body: some View {
        SettingsPageShell(
            kicker: "AI",
            title: "Cy connection",
            subtitle: "Check how Cy connects on this device."
        ) {
            AgentInsetSurface {
                HStack(alignment: .center, spacing: AgentSpacing.x4) {
                    AgentCyDisc(diameter: 48) {
                        CyAsterisk(color: .cyAccent, size: 22, strokeWidth: 2)
                    }
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(availability.label)
                            .font(.agentHeadline)
                        Text(availability.detail)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                    }
                    Spacer()
                    if availability.isAvailable {
                        AgentIconView(.check, size: 15)
                            .foregroundStyle(Color.agentSuccess)
                    }
                }
            }

            if availability == .unavailable {
                NavigationLink("Check hosted access") { AccessSettingsView() }
                    .buttonStyle(AgentPrimaryButtonStyle())
                NavigationLink("Connect Claude or Codex") { MCPBridgeSettingsView() }
                    .buttonStyle(AgentSecondaryButtonStyle())
            }

            Button("Check connection again") {
                Task { await refreshAvailability() }
            }
            .buttonStyle(AgentSecondaryButtonStyle())
            .disabled(availability == .checking)

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
        .task(id: scenePhase) {
            if scenePhase == .active { await refreshAvailability() }
        }
    }

    private func refreshAvailability() async {
        availability = .checking
        availability = await CyAvailabilityResolver.resolve(subscription: subscriptions.first)
    }

    private func instruction(number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
            Text(number)
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
