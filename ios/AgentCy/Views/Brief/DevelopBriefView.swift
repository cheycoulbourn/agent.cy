import SwiftData
import SwiftUI

struct DevelopBriefView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let brief: CreativeBrief
    @Query(sort: \ConversationMessage.createdAt) private var allMessages: [ConversationMessage]
    @State private var thread: ConversationThread?
    @State private var answer = ""

    private var messages: [ConversationMessage] {
        guard let thread else { return [] }
        return allMessages.filter { $0.threadID == thread.id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AgentSpacing.x6) {
                            ForEach(messages) { message in
                                HStack(alignment: .top, spacing: AgentSpacing.x3) {
                                    MetaLabel(message.role == .cy ? "Cy" : "You").frame(width: 44, alignment: .leading)
                                    Text(message.text).font(.agentBody).textSelection(.enabled)
                                        .foregroundStyle(message.role == .cy ? Color.agentText : Color.agentSecondary)
                                }
                                .id(message.id)
                            }
                        }
                        .padding(AgentSpacing.x6)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            if reduceMotion {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            } else {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                VStack(spacing: AgentSpacing.x3) {
                    HStack(alignment: .bottom, spacing: AgentSpacing.x3) {
                        TextField("Your answer", text: $answer, axis: .vertical)
                            .font(.agentBody)
                            .lineLimit(1...5)
                            .padding(AgentSpacing.x3)
                            .background(Color.agentSurface)
                            .clipShape(.rect(cornerRadius: AgentRadius.control))
                            .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                        Button { send() } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(AgentIconPrimaryButtonStyle())
                            .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isWorking || (thread?.turnCount ?? 0) >= 8)
                            .accessibilityLabel("Send answer")
                    }
                    Button("Build the brief", systemImage: "wand.and.sparkles") {
                        Task { await appModel.compose(brief: brief, context: context); dismiss() }
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())
                    HStack {
                        MetaLabel("\(thread?.turnCount ?? 0) of 8")
                        Spacer()
                        if appModel.isWorking { ProgressView() }
                    }
                }
                .padding(AgentSpacing.x4)
                .background(Color.agentCanvas)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
            }
            .navigationTitle("Shape the idea")
            .navigationSubtitle(brief.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
            }
            .interactiveDismissDisabled(appModel.isWorking)
            .agentScreen()
            .onAppear { thread = appModel.developmentThread(for: brief, context: context) }
        }
    }

    private func send() {
        let text = answer
        answer = ""
        Task { await appModel.sendDialogueTurn(brief: brief, answer: text, context: context) }
    }
}
