import SwiftData
import SwiftUI

struct DevelopBriefView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let brief: CreativeBrief
    let output: PlatformOutput?
    @Query(sort: \ConversationMessage.createdAt) private var allMessages: [ConversationMessage]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @State private var thread: ConversationThread?
    @State private var answer = ""
    @State private var postProposal: BriefProposal?
    @FocusState private var answerIsFocused: Bool

    init(brief: CreativeBrief, output: PlatformOutput? = nil) {
        self.brief = brief
        self.output = output
    }

    private var messages: [ConversationMessage] {
        guard let thread else { return [] }
        return allMessages.filter { $0.threadID == thread.id }
    }

    private var selectedPillar: Pillar? {
        pillars.first { $0.id == brief.pillarID && !$0.isArchived }
    }

    private var selectedDestination: PublishingDestination? {
        guard let destinationID = output?.destinationID else { return nil }
        return destinations.first { $0.id == destinationID }
    }

    private var selectedFormat: PublishingFormat? {
        guard let formatID = output?.formatID else { return nil }
        return formats.first { $0.id == formatID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topRail
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x4)
                    .padding(.bottom, AgentSpacing.x2)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AgentSpacing.x6) {
                            opening

                            if messages.isEmpty {
                                emptyConversationPrompt
                            } else {
                                conversationDivider
                                ForEach(messages) { message in
                                    messageView(message)
                                        .id(message.id)
                                }
                            }

                            if appModel.isWorking { typingIndicator }
                            Color.clear
                                .frame(height: 1)
                                .id("post-spark-bottom")
                        }
                        .padding(.horizontal, AgentLayout.pageMargin)
                        .padding(.top, AgentSpacing.x4)
                        .padding(.bottom, AgentSpacing.x8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.last?.id) { previousID, _ in
                        // Setting the development thread hydrates its existing messages.
                        // Keep the opening greeting visible on launch and only follow
                        // messages that arrive after the conversation is already loaded.
                        guard previousID != nil else { return }
                        revealLatestMessage(using: proxy)
                    }
                    .onChange(of: appModel.isWorking) { _, working in
                        guard working else { return }
                        revealThinkingState(using: proxy)
                    }
                    .onChange(of: answerIsFocused) { _, isFocused in
                        guard isFocused else { return }
                        revealConversationEnd(using: proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        revealConversationEnd(using: proxy)
                    }
                }

                composer
            }
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(appModel.isWorking)
            .agentScreen()
            .onAppear {
                thread = appModel.developmentThread(for: brief, context: context)
                postProposal = appModel.proposal(for: brief, context: context)
            }
            .sheet(item: $postProposal) { proposal in
                PostProposalReviewView(brief: brief, initialProposal: proposal)
            }
        }
        .agentKeyboardDismissal()
    }

    private var topRail: some View {
        HStack(spacing: AgentSpacing.x2) {
            Button { dismiss() } label: {
                AgentIconView(.close, size: 16)
                    .frame(width: 44, height: 44)
                    .background(Color.agentSurface, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Build with Cy")

            MetaLabel("Cy · Post")
            Spacer()
        }
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            CyAsterisk(color: .cyAccent, size: 36, strokeWidth: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Build out")
                    .font(.system(size: 32, weight: .regular))
                Text(brief.title.isEmpty ? "this post." : "\(brief.title).")
                    .font(.agentDisplay)
                    .lineLimit(3)
                    .minimumScaleFactor(0.76)
            }
            .tracking(-0.64)

            postContextCard
            starterSection
        }
    }

    private var postContextCard: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("Post details")
                .foregroundStyle(Color.cyAccent)

            if !postNotes.isEmpty {
                Text(postNotes)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tell Cy what you want to shape or improve.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }

            if !contextMetadata.isEmpty {
                Text(contextMetadata.joined(separator: " · "))
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(2)
            }
        }
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyAccent.opacity(0.07), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyAccent.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.cyAccent.opacity(0.10), radius: 18, y: 5)
    }

    private var starterSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Try asking")
            ForEach(starters, id: \.self) { starter in
                Button { send(starter) } label: {
                    HStack(spacing: AgentSpacing.x3) {
                        Text(starter)
                            .font(.agentSubtext.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        AgentIconView(.external, size: 11)
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
                .disabled(appModel.isWorking || (thread?.turnCount ?? 0) >= 8)
            }
        }
    }

    private var emptyConversationPrompt: some View {
        Text("Choose a prompt above or ask Cy exactly what you want to explore about this post.")
            .font(.agentSubtext)
            .foregroundStyle(Color.agentSecondary)
    }

    private var conversationDivider: some View {
        HStack(spacing: AgentSpacing.x3) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
            MetaLabel("Post conversation")
                .fixedSize()
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
        .padding(.top, AgentSpacing.x3)
    }

    @ViewBuilder
    private func messageView(_ message: ConversationMessage) -> some View {
        if message.role == .cy {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                    MetaLabel("Cy")
                }
                Text(message.text)
                    .font(.agentSubtext)
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
        } else {
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
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: AgentSpacing.x2) {
            CyThinkingMark()
            Text("Cy is thinking about this post")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 44)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            ZStack(alignment: .bottomTrailing) {
                TextField(text: $answer, axis: .vertical) {
                    Text("Ask about this post")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary.opacity(0.62))
                }
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .lineLimit(1...4)
                .focused($answerIsFocused)
                .padding(.leading, AgentSpacing.x4)
                .padding(.trailing, AgentSpacing.x12 + AgentSpacing.x3)
                .padding(.vertical, AgentSpacing.x3)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)

                Button { send() } label: {
                    AgentIconView(.arrowUp, size: 16)
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
                .accessibilityLabel("Send to Cy")
                .padding(6)
            }
            .frame(minHeight: 56)
            .glassEffect(.clear, in: .rect(cornerRadius: AgentRadius.floating))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.floating)
                    .stroke(Color.agentPureWhite.opacity(0.14), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }

            HStack {
                MetaLabel("\(thread?.turnCount ?? 0) of 8 turns")
                Spacer()
                Button("Compose post") { composePost() }
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.cyAccent)
                    .disabled(appModel.isWorking)
                if answerIsFocused {
                    Button { answerIsFocused = false } label: {
                        AgentIconView(.keyboardDown)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide keyboard")
                }
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.vertical, AgentSpacing.x2)
    }

    private var postNotes: String {
        let notes = brief.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? brief.premise.trimmingCharacters(in: .whitespacesAndNewlines) : notes
    }

    private var contextMetadata: [String] {
        var values: [String] = []
        if let selectedPillar { values.append(selectedPillar.name) }
        if let selectedDestination { values.append(selectedDestination.name) }
        else if let output { values.append(output.platform.title) }
        if let selectedFormat { values.append(selectedFormat.name) }
        if let output { values.append("\(output.durationSeconds) sec") }
        if let date = output?.targetDate ?? brief.agendaDate {
            values.append(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        }
        return values
    }

    private var postContext: String? {
        guard output != nil else { return nil }
        let metadata = contextMetadata.joined(separator: ", ")
        return [
            "Post title: \(brief.title)",
            postNotes.isEmpty ? nil : "Post notes: \(postNotes)",
            metadata.isEmpty ? nil : "Post setup: \(metadata)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private var starters: [String] {
        [
            "Give me three stronger angles for this post",
            "Write five hooks in my style",
            "Turn these notes into a clear post structure"
        ]
    }

    private var canSend: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appModel.isWorking
            && (thread?.turnCount ?? 0) < 8
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
        revealConversationEnd(using: proxy)
    }

    private func revealConversationEnd(using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("post-spark-bottom", anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("post-spark-bottom", anchor: .bottom)
            }
        }
    }

    private func send(_ suggestedPrompt: String? = nil) {
        let text = suggestedPrompt ?? answer
        answer = ""
        answerIsFocused = false
        Task {
            await appModel.sendDialogueTurn(
                brief: brief,
                answer: text,
                postContext: postContext,
                context: context
            )
        }
    }

    private func composePost() {
        answerIsFocused = false
        Task {
            await appModel.compose(brief: brief, context: context)
            postProposal = appModel.proposal(for: brief, context: context)
        }
    }
}
