import SwiftUI

struct CreationHubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showQuickCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    AgentInsetSurface {
                        VStack(alignment: .leading, spacing: 0) {
                            MetaLabel("Make")
                                .padding(.bottom, AgentSpacing.x2)

                            actionRow(
                                "Start an idea",
                                detail: "Save a thought to shape later.",
                                symbol: "lightbulb"
                            ) { openCapture(.idea) }

                            actionRow(
                                "Plan a post",
                                detail: "Choose a platform, format, and day.",
                                symbol: "rectangle.and.pencil.and.ellipsis"
                            ) { openCapture(.post) }

                            actionRow(
                                "Add a task",
                                detail: "Give the work one clear next step.",
                                symbol: "checkmark.square"
                            ) { openCapture(.task) }

                            HStack(spacing: AgentSpacing.x2) {
                                MetaLabel("Agent (Cy)")
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                            }
                            .padding(.top, AgentSpacing.x8)
                            .padding(.bottom, AgentSpacing.x4)

                            Button { openCapture(.cyIdeas) } label: {
                                HStack(spacing: AgentSpacing.x4) {
                                    CyAsterisk(color: .cyAccent, size: 24, strokeWidth: 1.8)
                                        .frame(width: 28, height: 28)

                                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                        Text("Find ideas with Cy")
                                            .font(.agentHeadline)
                                        Text("Three directions grounded in your work.")
                                            .font(.agentSubtext)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                    }

                                    Spacer(minLength: AgentSpacing.x2)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.agentText)
                                .padding(.horizontal, AgentSpacing.x4)
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                .background(Color.cyAccent.opacity(0.06), in: .rect(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.cyAccent.opacity(0.18), lineWidth: 1)
                                }
                                .shadow(color: Color.cyAccent.opacity(0.08), radius: 18)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Creates three personalized directions")
                        }
                    }
                    .padding(.horizontal, AgentLayout.dashboardGutter)
                }
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
                Text("Capture it now. Shape it when you’re ready.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x8)
        .padding(.bottom, AgentSpacing.x8)
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

    private func actionRow(
        _ title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title).font(.agentHeadline)
                    Text(detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: AgentSpacing.x2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.agentSecondary)
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}
