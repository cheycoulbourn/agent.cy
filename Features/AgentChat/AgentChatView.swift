import SwiftUI
import SwiftData

struct AgentChatView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [CreatorProfile]
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false

    private let aiService: AIServiceProtocol = MockAIService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                quickActions
                inputBar
            }
            .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
            .navigationTitle("Agent Cy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messages = []
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                    }
                    .tint(.brandBrown)
                }
            }
            .onAppear {
                if messages.isEmpty {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "Hey! I'm Agent Cy, your creative partner. Tell me about what you're working on, or use the quick actions below to get started."
                    ))
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if isThinking {
                        HStack(spacing: Spacing.xs) {
                            SparkPulse(size: 16)
                            Text("Thinking...")
                                .font(AppFont.subhead())
                                .foregroundStyle(.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.md)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                QuickActionChip(title: "Plan My Week", icon: "calendar") {
                    sendMessage("Help me plan my content for this week")
                }
                QuickActionChip(title: "Write Caption", icon: "text.quote") {
                    sendMessage("Help me write a caption")
                }
                QuickActionChip(title: "Content Ideas", icon: "lightbulb") {
                    sendMessage("Give me 5 content ideas for this week")
                }
                QuickActionChip(title: "Trend Check", icon: "chart.line.uptrend.xyaxis") {
                    sendMessage("What's trending in my niche right now?")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Ask Agent Cy anything...", text: $inputText, axis: .vertical)
                .font(AppFont.body())
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(colorScheme == .dark ? Color.cardDark : Color.cardLight)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.pill)
                        .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                }
                .lineLimit(1...5)

            Button {
                sendMessage(inputText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.isEmpty ? Color.brandBeige : Color.brandBlack)
            }
            .disabled(inputText.isEmpty || isThinking)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(colorScheme == .dark ? Color.bgDark : Color.bgLight)
    }

    private func sendMessage(_ text: String) {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isThinking = true

        Task {
            do {
                let context = buildCreatorContext()
                let response = try await aiService.chat(messages, context: context)
                messages.append(response)
            } catch {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: "Something went wrong. Let's try that again."
                ))
            }
            isThinking = false
        }
    }

    private func buildCreatorContext() -> CreatorContext {
        let profile = profiles.first
        return CreatorContext(
            displayName: profile?.displayName ?? "Creator",
            niche: profile?.niche ?? "",
            voiceAdjectives: profile?.voiceAdjectives ?? [],
            voiceDescription: profile?.voiceDescription,
            pillarNames: profile?.pillars.map(\.name) ?? [],
            recentContentTitles: [],
            platforms: profile?.platformAccounts.map(\.platform) ?? [],
            goals: profile?.primaryGoal.rawValue ?? ""
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
                if message.role == .assistant {
                    HStack(spacing: Spacing.xxs) {
                        SparkIcon(size: 12)
                        Text("Agent Cy")
                            .font(AppFont.caption(.medium))
                            .foregroundStyle(.brandBrown)
                    }
                }

                Text(message.content)
                    .font(AppFont.body())
                    .padding(Spacing.sm)
                    .background(
                        message.role == .user
                            ? Color.brandBlack
                            : (colorScheme == .dark ? Color.cardDark : Color.cardLight)
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    .overlay {
                        if message.role == .assistant {
                            RoundedRectangle(cornerRadius: CornerRadius.large)
                                .strokeBorder(colorScheme == .dark ? Color.borderDark : Color.borderLight, lineWidth: 0.5)
                        }
                    }
            }
            .padding(.horizontal, Spacing.md)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Quick Action Chip

struct QuickActionChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AppFont.caption(.medium))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .foregroundStyle(colorScheme == .dark ? .textOnDark : .textPrimary)
            .background(Color.brandPink.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AgentChatView()
}
