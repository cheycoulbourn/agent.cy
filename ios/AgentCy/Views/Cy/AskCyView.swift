import SwiftData
import SwiftUI

private struct ChatLine: Identifiable {
    let id = UUID()
    let role: ConversationRole
    let text: String
}

struct AskCyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var prompt = ""
    @State private var lines: [ChatLine] = [
        ChatLine(role: .cy, text: "What are you working through?")
    ]
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            ForEach(lines) { line in
                                HStack(alignment: .top, spacing: AgentSpacing.x3) {
                                    MetaLabel(line.role == .cy ? "Cy" : "You")
                                        .frame(width: 44, alignment: .leading)
                                    Text(line.text)
                                        .font(.agentBody)
                                        .foregroundStyle(line.role == .cy ? Color.agentText : Color.agentSecondary)
                                        .textSelection(.enabled)
                                }
                                .id(line.id)
                            }
                        }
                        .padding(AgentSpacing.x6)
                    }
                    .onChange(of: lines.count) { _, _ in
                        if let last = lines.last {
                            if reduceMotion {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            } else {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: AgentSpacing.x3) {
                    TextField("Ask Cy", text: $prompt, axis: .vertical)
                        .font(.agentBody)
                        .lineLimit(1...5)
                        .padding(AgentSpacing.x3)
                        .background(Color.agentSurface)
                        .clipShape(.rect(cornerRadius: AgentRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(AgentIconPrimaryButtonStyle())
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .accessibilityLabel("Send")
                }
                .padding(AgentSpacing.x4)
                .background(Color.agentCanvas)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
            }
            .navigationTitle("Ask Cy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .agentScreen()
        }
    }

    private func send() {
        let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        prompt = ""
        lines.append(ChatLine(role: .creator, text: message))
        isSending = true
        Task {
            let conversation = lines.dropFirst().suffix(24).map { line in
                ConversationMessageWire(
                    messageId: line.id,
                    role: line.role == .creator ? .user : .assistant,
                    content: line.text
                )
            }
            if let reply = await appModel.askCy(message, conversation: Array(conversation), context: context) {
                lines.append(ChatLine(role: .cy, text: reply))
            }
            isSending = false
        }
    }
}
