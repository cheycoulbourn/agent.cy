import SwiftData
import SwiftUI

private struct DevelopBriefRequest: Identifiable {
    enum Action {
        case dialogue(answer: String, postContext: String?)
        case compose
    }

    let id = UUID()
    let action: Action
}

struct DevelopBriefView: View {
    @State private var didAcceptReview = false
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let brief: CreativeBrief
    let output: PlatformOutput?
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @State private var thread: ConversationThread?
    @State private var messages: [ConversationMessage] = []
    @State private var answer = ""
    @State private var postProposal: BriefProposal?
    @State private var hasPendingReview = false
    @State private var confirmsArchive = false
    @State private var request: DevelopBriefRequest?
    @FocusState private var answerIsFocused: Bool

    init(brief: CreativeBrief, output: PlatformOutput? = nil) {
        self.brief = brief
        self.output = output
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
                        // Plain VStack for the same reason as Ask Cy: the
                        // 8-turn conversation is small, and lazy row
                        // re-measurement snaps the bottom-edge bounce.
                        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
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

                            if isRequestPending { typingIndicator }
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
                    .onChange(of: isRequestPending) { _, working in
                        guard working else { return }
                        revealThinkingState(using: proxy)
                    }
                    .onChange(of: answerIsFocused) { _, isFocused in
                        guard isFocused else { return }
                        revealConversationEnd(using: proxy)
                    }
                }

                composer
            }
            .toolbar(.hidden, for: .navigationBar)
            .agentScreen()
            .onAppear {
                thread = appModel.developmentThread(for: brief, context: context)
                reloadMessages()
                postProposal = appModel.proposal(for: brief, context: context)
                hasPendingReview = postProposal != nil
            }
            .task(id: request?.id) {
                guard let request else { return }
                await perform(request)
                guard !Task.isCancelled, self.request?.id == request.id else { return }
                self.request = nil
            }
            .sheet(item: $postProposal, onDismiss: {
                hasPendingReview = appModel.proposal(for: brief, context: context) != nil
                if didAcceptReview { dismiss() }
            }) { proposal in
                PostProposalReviewView(brief: brief, initialProposal: proposal) {
                    didAcceptReview = true
                }
            }
        }
        .agentKeyboardDismissal()
    }

    private var topRail: some View {
        HStack(spacing: AgentSpacing.x2) {
            AgentToolbarIconButton(title: "Close Build with Cy", icon: .close) {
                request = nil
                dismiss()
            }

            MetaLabel("Cy · Post")
            Spacer()

            if !messages.isEmpty {
                Menu {
                    Button("Archive conversation") {
                        confirmsArchive = true
                    }
                } label: {
                    AgentIconView(.more, size: 16)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .accessibilityLabel("Conversation options")
                .disabled(isRequestPending)
                .confirmationDialog(
                    "Archive this conversation?",
                    isPresented: $confirmsArchive,
                    titleVisibility: .visible
                ) {
                    Button("Archive conversation") { archiveConversation() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Cy starts fresh for this post. The archived chat stays in your history.")
                }
            }
        }
    }

    private func archiveConversation() {
        guard !isRequestPending else { return }
        appModel.archiveDevelopmentThread(for: brief, context: context)
        thread = appModel.developmentThread(for: brief, context: context)
        reloadMessages()
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            CyAsterisk(color: .cyAccent, size: 36, strokeWidth: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Build out")
                    .font(.agentDisplayLead)
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
                .foregroundStyle(Color.cyAccentText)

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
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(2)
            }
        }
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyAccent.opacity(0.07), in: .rect(cornerRadius: 16))
        .agentSurfaceChrome(
            cornerRadius: 16,
            borderColor: Color.cyAccent.opacity(0.22)
        )
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
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(AgentPressButtonStyle())
                .disabled(isRequestPending || (thread?.turnCount ?? 0) >= 8)
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
            // Mirrors the Ask Cy conversation: rendered markdown in the
            // Cy-tinted card at full width, instead of raw asterisks in a
            // narrow gray bubble.
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                    MetaLabel("Cy")
                }
                CyMarkdownResponseView(source: message.text)
                    .textSelection(.enabled)
                    .padding(AgentSpacing.x4)
                    .background(Color.cyAccent.opacity(0.045), in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.cyAccent.opacity(0.16), lineWidth: 0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(message.text)
                .font(.agentBody)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cy is thinking about this post")
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
                    AgentQuietAccentIconLabel(icon: .arrowUp, isActive: canSend)
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
                    .monospacedDigit()
                Spacer()
                Button { composePost() } label: {
                    Text(hasPendingReview ? "Continue review" : "Compose post")
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.cyAccentText)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isRequestPending)
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
            && !isRequestPending
            && (thread?.turnCount ?? 0) < 8
    }

    private var isRequestPending: Bool {
        request != nil || appModel.isWorking
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
        let text = (suggestedPrompt ?? answer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        answer = ""
        answerIsFocused = false
        request = DevelopBriefRequest(
            action: .dialogue(answer: text, postContext: postContext)
        )
    }

    private func composePost() {
        answerIsFocused = false
        if let pending = appModel.proposal(for: brief, context: context) {
            postProposal = pending
            return
        }
        request = DevelopBriefRequest(action: .compose)
    }

    private func perform(_ request: DevelopBriefRequest) async {
        switch request.action {
        case .dialogue(let answer, let postContext):
            let succeeded = await appModel.sendDialogueTurn(
                brief: brief,
                answer: answer,
                postContext: postContext,
                context: context
            )
            guard !Task.isCancelled else { return }
            reloadMessages()
            if !succeeded, self.answer.isEmpty {
                self.answer = answer
            }
        case .compose:
            let succeeded = await appModel.compose(brief: brief, context: context)
            guard succeeded, !Task.isCancelled else { return }
            postProposal = appModel.proposal(for: brief, context: context)
        }
    }

    private func reloadMessages() {
        messages = thread.map { appModel.messages(for: $0, context: context) } ?? []
    }
}
