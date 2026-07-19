import SwiftUI

struct CaptureIdeaShortcutSettingsView: View {
    var body: some View {
        SettingsPageShell(
            kicker: "Shortcuts & widgets",
            title: "Idea capture & widgets",
            subtitle: "Capture an idea in the Idea Bank and keep your day visible from your Home Screen."
        ) {
            shortcutCard

            VStack(alignment: .leading, spacing: 0) {
                MetaLabel("What happens")
                    .padding(.bottom, AgentSpacing.x3)
                instructionRow(
                    number: "01",
                    title: "Say or type the idea",
                    detail: "The shortcut asks for the thought you want to keep."
                )
                instructionRow(
                    number: "02",
                    title: "Choose a pillar",
                    detail: "Pick one of your current pillars, or leave it unfiled."
                )
                instructionRow(
                    number: "03",
                    title: "Find it in the Idea Bank",
                    detail: "agent.cy saves a new idea without opening the app."
                )
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                MetaLabel("Set up Double Tap")

                setupStep(number: "1", text: "Tap Create shortcut below, then tap Add Action.")
                setupStep(number: "2", text: "Search for Capture Idea and choose the agent.cy action.")
                setupStep(number: "3", text: "Keep Idea and Pillar set to Ask Each Time, name it Capture Idea, then tap Done.")
                setupStep(number: "4", text: "Open Settings → Accessibility → Touch → Back Tap.")
                setupStep(number: "5", text: "Choose Double Tap, then select Capture Idea under Shortcuts.")

                Link(destination: URL(string: "shortcuts://create-shortcut")!) {
                    Text("Create shortcut")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AgentSecondaryButtonStyle())
                .accessibilityHint("Opens a new shortcut in the Shortcuts app.")

                Text("Apple requires the final Back Tap choice to be made in Settings. agent.cy cannot switch it on for you.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }

            widgetInstructions
        }
    }

    private var widgetInstructions: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Add widgets")
                Text("Keep your focus, next post, ideas, or quick capture within reach.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                setupStep(number: "1", text: "Open agent.cy once so your latest work is ready for widgets.")
                setupStep(number: "2", text: "Touch and hold an empty area of your Home Screen until the apps begin to jiggle.")
                setupStep(number: "3", text: "Tap Edit in the top-left corner, then tap Add Widget.")
                setupStep(number: "4", text: "Search for agent.cy and tap it in the widget gallery.")
                setupStep(number: "5", text: "Swipe through the available widgets and sizes, then tap Add Widget.")
                setupStep(number: "6", text: "Drag the widget where you want it, then tap Done.")
            }

            Text("Tip: Touch and hold a widget later to move it, remove it, or choose a different size.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .padding(.top, AgentSpacing.x1)
        }
        .padding(.top, AgentSpacing.x4)
    }

    private var shortcutCard: some View {
        HStack(spacing: AgentSpacing.x4) {
            ZStack {
                RoundedRectangle(cornerRadius: AgentRadius.control)
                    .fill(Color.actionAccent)
                    .frame(width: 60, height: 60)
                AgentIconView(.idea, size: 24)
                    .foregroundStyle(Color.agentPureWhite)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text("Idea capture")
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                Text("IDEA + PILLAR · SAVES PRIVATELY")
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentCanvas)
        .clipShape(.rect(cornerRadius: AgentRadius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.panel)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    private func instructionRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.x4) {
            Text(number)
                .font(.agentMono)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(title)
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                Text(detail)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AgentSpacing.x4)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
    }

    private func setupStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            Text(number)
                .font(.agentMono)
                .foregroundStyle(Color.agentText)
                .frame(width: 26, height: 26)
                .background(Color.agentCanvas, in: Circle())
                .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
            Text(text)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
