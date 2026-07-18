import SwiftUI

struct CreationHubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showQuickCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    header

                    createActions
                    cyAction
                }
                .padding(.horizontal, AgentLayout.dashboardGutter)
                .padding(.bottom, AgentSpacing.x16)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .agentDashboardScreen()
        }
        .sheet(isPresented: $showQuickCapture) {
            QuickCaptureView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            ZStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.clear.interactive(), in: .circle)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
                    .accessibilityLabel("Close")
                    Spacer()
                }

                MetaLabel("Quick actions")
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text("Let’s make something.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                Text("Start small. You can shape it later.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.horizontal, AgentLayout.dashboardGutter)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x2)
    }

    private enum Destination { case idea, post, task, cyIdeas }

    private func openCapture(_ destination: Destination) {
        appModel.quickCaptureTargetDate = nil
        appModel.quickCapturePillarID = nil
        switch destination {
        case .idea: appModel.setQuickCaptureMode(.idea)
        case .post: appModel.setQuickCaptureMode(.post)
        case .task: appModel.setQuickCaptureMode(.task)
        case .cyIdeas: appModel.setQuickCaptureMode(.cyIdeas)
        }
        showQuickCapture = true
    }

    private var createActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MetaLabel("Create")
                .padding(.horizontal, AgentSpacing.x5)
                .padding(.top, AgentSpacing.x5)
                .padding(.bottom, AgentSpacing.x2)

            quickActionRow(
                title: "Idea",
                detail: "Save a thought to shape later.",
                showsDivider: true
            ) { openCapture(.idea) }

            quickActionRow(
                title: "Post",
                detail: "Choose the platform, format, and date.",
                showsDivider: true
            ) { openCapture(.post) }

            quickActionRow(
                title: "Task",
                detail: "Add one clear next step.",
                showsDivider: false
            ) { openCapture(.task) }
        }
        .padding(.bottom, AgentSpacing.x2)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
    }

    private var cyAction: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("With Cy")
                .foregroundStyle(Color.cyAccent)

            Button { openCapture(.cyIdeas) } label: {
                HStack(spacing: AgentSpacing.x4) {
                    CyAsterisk(color: .cyAccent, size: 22, strokeWidth: 1.7)
                        .frame(width: 26, height: 26)

                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("Find three ideas")
                            .font(.agentHeadline)
                        Text("Grounded in your pillars and saved work.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: AgentSpacing.x2)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.cyAccent)
                        .frame(width: 32, height: 32)
                }
                .foregroundStyle(Color.agentText)
                .padding(.horizontal, AgentSpacing.x5)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(Color.cyAccent.opacity(0.055), in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.cyAccent.opacity(0.2), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: AgentRadius.control))
            }
            .buttonStyle(QuickAddRowButtonStyle())
            .accessibilityHint("Creates three personalized ideas")
        }
    }

    private func quickActionRow(
        title: String,
        detail: String,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title).font(.agentHeadline)
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: AgentSpacing.x2)

                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 40, height: 40)
                    .glassEffect(.clear.interactive(), in: .circle)
                    .overlay {
                        Circle()
                            .stroke(Color.agentBorder, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x5)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)
                        .padding(.leading, AgentSpacing.x5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(QuickAddRowButtonStyle())
        .accessibilityHint(detail)
    }
}

private struct QuickAddRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
