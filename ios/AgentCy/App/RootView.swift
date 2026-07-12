import SwiftData
import SwiftUI

struct RootView: View {
    @Query private var profiles: [CreatorProfile]
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasProfile: Bool {
        !profiles.isEmpty
    }

    var body: some View {
        Group {
            if hasProfile {
                if appModel.requiresInstallationInvite && !appModel.hasInstallationCredential {
                    InstallationInviteGate()
                        .transition(.opacity)
                } else {
                    AppShellView()
                        .transition(.opacity)
                }
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hasProfile)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: appModel.hasInstallationCredential)
        .task {
            await appModel.refreshInstallationCredentialStatus()
        }
        .agentScreen()
    }
}

private struct InstallationInviteGate: View {
    @Environment(AppModel.self) private var appModel
    @State private var inviteCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: "Connect Cy",
                    title: "Enter your invite.",
                    subtitle: "Connect this iPhone to Cy. Your saved work stays here."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Invitation code")
                        TextField("Enter your pilot code", text: $inviteCode)
                            .font(.agentBody)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(AgentSpacing.x4)
                            .background(Color.agentSurface)
                            .clipShape(.rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                    }

                    Button {
                        Task { await appModel.redeemInstallationInvite(inviteCode) }
                    } label: {
                        Label("Connect Cy", systemImage: "key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(
                        appModel.isRedeemingInvite ||
                            inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6
                    )

                    if appModel.isRedeemingInvite {
                        ProgressView("Connecting…")
                            .font(.agentBody)
                    }

                    if let notice = appModel.notice {
                        Text(notice.message)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }

                CyCallout {
                    Text("Your invite is checked before any content is sent.")
                        .font(.agentBody)
                }
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x12)
            .padding(.bottom, AgentSpacing.x16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel(reminderService: PreviewReminderService()))
        .modelContainer(ModelContainerFactory.make(isStoredInMemoryOnly: true))
}
