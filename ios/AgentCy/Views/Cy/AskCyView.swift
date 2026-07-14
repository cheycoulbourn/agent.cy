import SwiftData
import SwiftUI
import UIKit

struct AskCyView: View {
    private let bottomClearance: CGFloat
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ConversationThread.updatedAt, order: .reverse) private var threads: [ConversationThread]
    @Query(sort: \ConversationMessage.createdAt) private var allMessages: [ConversationMessage]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query private var profiles: [CreatorProfile]
    @State private var prompt = ""
    @State private var thread: ConversationThread?
    @State private var isSending = false
    @FocusState private var composerIsFocused: Bool

    init(bottomClearance: CGFloat = 0) {
        self.bottomClearance = bottomClearance
    }

    private var messages: [ConversationMessage] {
        guard let thread else { return [] }
        return allMessages.filter { $0.threadID == thread.id }
    }

    private var currentDraft: CreativeBrief? {
        briefs.first { $0.status == .spark || $0.status == .developing }
    }

    var body: some View {
        VStack(spacing: 0) {
            topRail
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, messages.isEmpty ? AgentSpacing.x4 : AgentSpacing.x1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        if messages.isEmpty {
                            opening
                        } else {
                            conversationDivider
                            ForEach(Array(messages.enumerated()), id: \.element.id) { _, message in
                                messageView(message)
                                    .id(message.id)
                            }
                            if isSending { typingIndicator }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("ask-cy-bottom")
                    }
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x4)
                    .padding(.bottom, AgentSpacing.x4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _, _ in
                    revealLatestMessage(using: proxy)
                }
                .onChange(of: isSending) { _, sending in
                    guard sending else { return }
                    revealThinkingState(using: proxy)
                }
                .onChange(of: composerIsFocused) { _, isFocused in
                    guard isFocused else { return }
                    revealConversationEnd(using: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    revealConversationEnd(using: proxy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            loadThread()
            await appModel.refreshAccess(context: context)
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private var topRail: some View {
        AgentPageRail(
            breadcrumb: "Agent (Cy)",
            profile: profiles.first,
            openSettings: { appModel.presentedSheet = .settings }
        ) {
            Menu {
                Button("New conversation") { startNewThread() }
                if thread != nil { Button("Archive conversation") { archiveThread() } }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            CyAsterisk(color: .cyAccent, size: 36, strokeWidth: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hey \(displayName),")
                    .font(.system(size: 32, weight: .regular))
                Text("what are we building today?")
                    .font(.agentDisplay)
            }
            .tracking(-0.64)

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("On your plate")
                    .foregroundStyle(Color.cyAccent)
                Text(onYourPlateCopy)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyAccent.opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.cyAccent.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.cyAccent.opacity(0.08), radius: 18)

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Start with")
                    .padding(.bottom, AgentSpacing.x1)
                starter(primaryStarter)
                starter("Give me three ideas in my voice")
                starter("Turn a rough note into a post")
            }
            .padding(.top, 82)
        }
    }

    private func starter(_ title: String) -> some View {
        Button {
            prompt = title
            composerIsFocused = true
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                Text(title)
                    .font(.agentSubtext.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.agentSurface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var conversationDivider: some View {
        HStack(spacing: AgentSpacing.x3) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
            MetaLabel(messages.first?.createdAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()) ?? "Today")
                .fixedSize()
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
        .padding(.bottom, AgentSpacing.x2)
    }

    @ViewBuilder
    private func messageView(_ message: ConversationMessage) -> some View {
        switch message.role {
        case .cy:
            assistantMessage(label: "Cy", text: message.text, showsAsterisk: true)
        case .claude:
            assistantMessage(label: "Claude · Imported", text: message.text, showsAsterisk: false)
        case .creator:
            VStack(alignment: .trailing, spacing: AgentSpacing.x2) {
                Text(message.text)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentCanvas)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AgentSpacing.x4)
                    .padding(.vertical, AgentSpacing.x3)
                    .background(Color.agentText)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: 16,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 16
                        )
                    )
                    .frame(maxWidth: 280, alignment: .trailing)

            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func assistantMessage(label: String, text: String, showsAsterisk: Bool) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(spacing: AgentSpacing.x2) {
                if showsAsterisk {
                    CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                }
                MetaLabel(label)
            }

            Text(text)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AgentSpacing.x4)
                .padding(.vertical, 14)
                .background(Color.agentSurface)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 16
                    )
                )
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 16
                    )
                    .stroke(Color.agentBorder, lineWidth: 1)
                }
                .frame(maxWidth: 342, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typingIndicator: some View {
        HStack(spacing: AgentSpacing.x2) {
            CyThinkingMark()
            Text("Cy is thinking")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 44)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(alignment: .bottom, spacing: AgentSpacing.x2) {
                TextField(text: $prompt, axis: .vertical) {
                    Text(composerPlaceholder)
                        .foregroundStyle(Color.agentSecondary)
                }
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(1...4)
                    .focused($composerIsFocused)
                    .padding(.leading, AgentSpacing.x3)
                    .padding(.vertical, AgentSpacing.x3)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSend ? Color.onCyAccent : Color.agentSecondary)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Color.cyAccent : Color.agentSurface, in: .circle)
                        .overlay {
                            Circle()
                                .stroke(canSend ? Color.cyAccent : Color.agentBorder, lineWidth: 1)
                        }
                        .shadow(color: canSend ? Color.cyAccent.opacity(0.24) : .clear, radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(6)
            .frame(minHeight: 56)
            .glassEffect(.clear, in: .capsule)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 4)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.vertical, AgentSpacing.x2)
        .padding(.bottom, bottomClearance)
    }

    private var displayName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "there" : name
    }

    private var onYourPlateCopy: String {
        guard let currentDraft else {
            return "Bring me a rough idea. We’ll make the next move clear."
        }
        return "\(currentDraft.title) is still a draft. Want to shape the next step together?"
    }

    private var primaryStarter: String {
        currentDraft.map { "Keep shaping \($0.title)" } ?? "Help me choose what to make next"
    }

    private var composerPlaceholder: String { "Ask Cy anything" }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func revealLatestMessage(using proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        let anchor: UnitPoint = last.role == .cy ? .top : .bottom
        if reduceMotion {
            proxy.scrollTo(last.id, anchor: anchor)
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(last.id, anchor: anchor)
            }
        }
    }

    private func revealThinkingState(using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("ask-cy-bottom", anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("ask-cy-bottom", anchor: .bottom)
            }
        }
    }

    private func revealConversationEnd(using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("ask-cy-bottom", anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo("ask-cy-bottom", anchor: .bottom)
            }
        }
    }

    private func loadThread() {
        if let current = threads.first(where: { !$0.isArchived && $0.briefID == nil && $0.contextKind == .none }) {
            thread = current
        } else { startNewThread() }
    }

    private func startNewThread() {
        let newThread = ConversationThread(title: "Conversation")
        context.insert(newThread)
        try? context.save()
        thread = newThread
    }

    private func archiveThread() {
        thread?.isArchived = true
        thread?.updatedAt = Date()
        try? context.save()
        startNewThread()
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let thread else { return }
        let priorMessages = messages
        prompt = ""
        composerIsFocused = false
        let creatorMessage = ConversationMessage(threadID: thread.id, role: .creator, text: text)
        context.insert(creatorMessage)
        thread.turnCount += 1
        thread.updatedAt = Date()
        try? context.save()

        isSending = true
        let conversation = Array((priorMessages + [creatorMessage]).suffix(24)).map {
            ConversationMessageWire(messageId: $0.id, role: $0.role == .creator ? .user : .assistant, content: $0.text)
        }
        Task {
            if let reply = await appModel.askCy(text, conversation: conversation, context: context) {
                context.insert(ConversationMessage(threadID: thread.id, role: .cy, text: reply))
                thread.updatedAt = Date()
                try? context.save()
            }
            isSending = false
        }
    }

}
