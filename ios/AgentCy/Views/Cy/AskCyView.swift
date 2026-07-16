import SwiftData
import SwiftUI
import UIKit

private struct CyPlateItem: Identifiable {
    let id: String
    let count: Int
    let title: String
}

struct AskCyView: View {
    private let bottomClearance: CGFloat
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ConversationThread.updatedAt, order: .reverse) private var allThreads: [ConversationThread]
    @Query(sort: \ConversationMessage.createdAt) private var allMessages: [ConversationMessage]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var allPillars: [Pillar]
    @Query private var profiles: [CreatorProfile]
    @Query private var subscriptions: [SubscriptionState]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var prompt = ""
    @State private var thread: ConversationThread?
    @State private var isSending = false
    @State private var pendingReviews: [MCPBridgeChangeRequest] = []
    @State private var reviewingRequest: MCPBridgeChangeRequest?
    @State private var reviewError: String?
    @State private var hasLoadedPendingReviews = false
    @State private var showReviewCompletion = false
    @State private var showConversationHistory = false
    @State private var showProUpsell = false
    @State private var showProAccessDetails = false
    @State private var remoteIsConnected = false
    @State private var sendTask: Task<Void, Never>?
    @State private var activeSendID: UUID?
    @State private var sentToPostMessageIDs: Set<UUID> = []
    @FocusState private var composerIsFocused: Bool

    private var threads: [ConversationThread] { scoped(allThreads) }
    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var tasks: [CreatorTask] { scoped(allTasks).filter { !$0.isSkipped } }
    private var pillars: [Pillar] { scoped(allPillars) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    init(bottomClearance: CGFloat = 0) {
        self.bottomClearance = bottomClearance
    }

    private var messages: [ConversationMessage] {
        guard let thread else { return [] }
        return allMessages.filter { $0.threadID == thread.id }
    }

    private var conversationThreads: [ConversationThread] {
        threads.filter { $0.briefID == nil && $0.contextKind == .none }
    }

    private var hasProAccess: Bool {
        guard let access = subscriptions.first?.access else { return false }
        return access == .trial || access == .paid || access == .comped
    }

    private var currentDraft: CreativeBrief? {
        briefs.first { $0.status == .spark || $0.status == .developing }
    }

    var body: some View {
        VStack(spacing: 0) {
            topRail
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, AgentSpacing.x2)

            remoteStatusRow
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.bottom, showsConversation && !messages.isEmpty ? AgentSpacing.x1 : AgentSpacing.x4)

            if showReviewCompletion {
                reviewCompletionContent
            } else if pendingReviews.isEmpty {
                conversationContent
            } else {
                pendingReviewContent
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsConversation { composer }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            loadThread()
            reloadPendingReviews()
            if let pending = appModel.pendingCyPrompt {
                prompt = pending
                appModel.pendingCyPrompt = nil
                composerIsFocused = true
            }
            await appModel.refreshAccess(context: context)
        }
        .task {
            while !Task.isCancelled {
                reloadPendingReviews()
                await reloadRemoteStatus()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onChange(of: appModel.pendingCyPrompt) { _, pending in
            guard let pending else { return }
            prompt = pending
            appModel.pendingCyPrompt = nil
            composerIsFocused = true
        }
        .sheet(item: $reviewingRequest) { request in
            NavigationStack {
                MCPBridgeRequestReviewView(
                    request: request,
                    approve: { reviewedRequest in
                        try MCPBridgeService.approve(reviewedRequest, context: context)
                        reloadPendingReviews()
                    },
                    decline: {
                        try MCPBridgeService.reject(request)
                        reloadPendingReviews()
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showConversationHistory) {
            CyConversationHistoryView(
                threads: conversationThreads,
                messages: allMessages,
                currentThreadID: thread?.id,
                openThread: openThreadFromHistory,
                deleteThread: deleteThreadFromHistory
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProUpsell) {
            NavigationStack {
                ScrollView {
                    CyProUpsellView(
                        message: "Upgrade to agent.cy Pro to start auto prompts with Cy.",
                        primaryAction: { showProAccessDetails = true },
                        secondaryAction: { showProUpsell = false }
                    )
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x4)
                    .padding(.bottom, AgentSpacing.x8)
                }
                .navigationTitle("Upgrade")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { showProUpsell = false }
                            .labelStyle(.iconOnly)
                    }
                }
                .navigationDestination(isPresented: $showProAccessDetails) {
                    AccessSettingsView()
                }
                .agentScreen()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("agent.cy", isPresented: Binding(
            get: { reviewError != nil },
            set: { if !$0 { reviewError = nil } }
        )) {
            Button("Close", role: .cancel) { reviewError = nil }
        } message: {
            Text(reviewError ?? "")
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private var conversationContent: some View {
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

    private var pendingReviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAsterisk(color: .cyAccent, size: 20, strokeWidth: 1.7)
                    MetaLabel("CY · FOR REVIEW")
                        .foregroundStyle(Color.cyAccent)
                }
                Text("I have something\nfor you.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                Text("Review each post before it changes your calendar.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.bottom, AgentSpacing.x6)

            SectionRuleHeader(
                title: "Waiting for review",
                trailing: "\(pendingReviews.count)"
            )
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.bottom, AgentSpacing.x2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentSpacing.x4) {
                ForEach(pendingReviews) { request in
                    Button {
                        reviewingRequest = request
                    } label: {
                        reviewCard(for: request)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the complete proposed post for approval")
                }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.bottom, bottomClearance + AgentSpacing.x8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var reviewCompletionContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAsterisk(color: .cyAccent, size: 20, strokeWidth: 1.7)
                    MetaLabel("CY · REVIEW COMPLETE")
                        .foregroundStyle(Color.cyAccent)
                }

                Text("All done\nfor now.")
                    .font(.agentDisplay)
                    .tracking(-0.64)

                Text("All done for now. Nothing else is waiting for review.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Back to Cy") {
                showReviewCompletion = false
            }
            .buttonStyle(AgentCyPrimaryButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x6)
        .padding(.bottom, bottomClearance + AgentSpacing.x8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topRail: some View {
        AgentPageRail(
            breadcrumb: "Agent (Cy)",
            profile: profiles.first,
            openSettings: { appModel.presentedSheet = .settings }
        ) {
            Menu {
                Button("New conversation") { startNewThread() }
                Button("Conversation history") { showConversationHistory = true }
                if thread != nil { Button("Move to history") { archiveThread() } }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var remoteStatusRow: some View {
        return HStack(spacing: AgentSpacing.x2) {
            Circle()
                .fill(remoteIsConnected ? Color.agentSuccess : Color.agentDestructive)
                .frame(width: 7, height: 7)
            MetaLabel("Remote status")
            Spacer(minLength: AgentSpacing.x2)
            Text(remoteIsConnected ? "Connected" : "Unavailable")
                .font(.agentMono)
                .foregroundStyle(remoteIsConnected ? Color.agentSuccess : Color.agentDestructive)
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remote status, \(remoteIsConnected ? "connected" : "unavailable")")
    }

    @MainActor
    private func reloadRemoteStatus() async {
        guard LocalCyPreferences.isEnabledAndConnected else {
            remoteIsConnected = false
            return
        }
        remoteIsConnected = await LocalCyAIClient.shared.isRemoteAvailable()
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            CyAsterisk(color: .cyAccent, size: 36, strokeWidth: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hey \(displayName),")
                    .font(.system(size: 32, weight: .regular))
                Text("what are we creating today?")
                    .font(.agentDisplay)
            }
            .tracking(-0.64)

            Button(action: useOnYourPlatePrompt) {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("On your plate")
                        .foregroundStyle(Color.cyAccent)

                    if !onYourPlateItems.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(onYourPlateItems.enumerated()), id: \.element.id) { index, item in
                                HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                                    Text("\(item.count)")
                                        .font(.agentMono)
                                        .foregroundStyle(Color.cyAccent)
                                        .frame(width: 24, alignment: .leading)
                                    Text(item.title)
                                        .font(.agentSubtext)
                                        .foregroundStyle(Color.agentText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, AgentSpacing.x2)
                                .overlay(alignment: .top) {
                                    if index > 0 {
                                        Rectangle().fill(Color.cyAccent.opacity(0.12)).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                        Text(onYourPlateSuggestion.display)
                            .font(.agentSubtext.weight(.medium))
                            .foregroundStyle(Color.agentText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.cyAccent)
                    }
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
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds Cy's suggested continuation to the composer")

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Start with")
                    .padding(.bottom, AgentSpacing.x1)

                ZStack {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        ForEach(Array(starterPrompts.enumerated()), id: \.offset) { _, quickPrompt in
                            starter(quickPrompt)
                        }
                    }
                    .blur(radius: hasProAccess ? 0 : 3.5)
                    .opacity(hasProAccess ? 1 : 0.52)
                    .allowsHitTesting(hasProAccess)

                    if !hasProAccess {
                        Button(action: openProAccess) {
                            Text("Upgrade to Pro to create with Cy")
                                .font(.agentSubtext.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.onCyAccent)
                                .padding(.horizontal, AgentSpacing.x4)
                                .padding(.vertical, AgentSpacing.x3)
                                .background(Color.cyAccent, in: .capsule)
                                .shadow(color: Color.cyAccent.opacity(0.28), radius: 14, y: 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens plan and access settings")
                    }
                }
            }
            .padding(.top, AgentSpacing.x4)
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
            assistantMessage(message, label: "Cy", showsAsterisk: true)
        case .claude:
            assistantMessage(message, label: "Claude · Imported", showsAsterisk: false)
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

    private func assistantMessage(
        _ message: ConversationMessage,
        label: String,
        showsAsterisk: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(spacing: AgentSpacing.x2) {
                if showsAsterisk {
                    CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                }
                MetaLabel(label)
            }

            Text(renderedMarkdown(message.text))
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

            if !message.chatSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    ForEach(Array(message.chatSuggestions.enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            prompt = suggestion.prompt
                            composerIsFocused = true
                        } label: {
                            HStack(spacing: AgentSpacing.x2) {
                                Text(suggestion.label)
                                    .font(.agentSubtext.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.agentText)
                            .padding(.horizontal, AgentSpacing.x3)
                            .frame(minHeight: 44)
                            .background(Color.agentSurface, in: .capsule)
                            .overlay { Capsule().stroke(Color.agentBorder, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 342, alignment: .leading)
            }

            if canSendResponseToPost(message) {
                Button {
                    sendResponseToPost(message)
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        CyAsterisk(color: .cyAccent, size: 13, strokeWidth: 1.4)
                        Text(sentToPostMessageIDs.contains(message.id) ? "Sent to post" : "Send to post")
                            .font(.agentSubtext.weight(.semibold))
                        Spacer(minLength: AgentSpacing.x2)
                        Image(systemName: sentToPostMessageIDs.contains(message.id) ? "checkmark" : "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.cyAccent)
                    .padding(.horizontal, AgentSpacing.x3)
                    .frame(maxWidth: 342, minHeight: 44)
                    .background(Color.cyAccent.opacity(0.07), in: .capsule)
                    .overlay { Capsule().stroke(Color.cyAccent.opacity(0.38), lineWidth: 1) }
                    .shadow(color: Color.cyAccent.opacity(0.10), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(sentToPostMessageIDs.contains(message.id))
                .accessibilityHint("Adds Cy's response to the referenced post notes and opens the post")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderedMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
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

                composerActionButton
            }
            .padding(6)
            .frame(minHeight: 56)
            .glassEffect(.clear, in: .capsule)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color(white: 0).opacity(0.12), radius: 14, y: 4)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.vertical, AgentSpacing.x2)
        .padding(.bottom, bottomClearance)
    }

    private var composerActionButton: some View {
        let isEnabled = isSending || canSend
        let foreground = isEnabled ? Color.onCyAccent : Color.agentSecondary
        let background = isEnabled ? Color.cyAccent : Color.agentSurface
        let border = isEnabled ? Color.cyAccent : Color.agentBorder
        return Button {
            if isSending {
                stopSending()
            } else {
                send()
            }
        } label: {
            Image(systemName: isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(background, in: .circle)
                .overlay { Circle().stroke(border, lineWidth: 1) }
                .shadow(
                    color: isEnabled ? Color.cyAccent.opacity(0.24) : Color.clear,
                    radius: 10,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(isSending ? "Stop Cy" : "Send")
    }

    private var displayName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "there" : name
    }

    private var onYourPlateItems: [CyPlateItem] {
        let now = Date()
        let activeBriefs = briefs.filter { $0.status != .archived }
        let activeBriefIDs = Set(activeBriefs.map(\.id))
        let latePostCount = Set(outputs.compactMap { output -> UUID? in
            guard activeBriefIDs.contains(output.briefID),
                  output.status != .posted,
                  isLate(output, now: now) else { return nil }
            return output.briefID
        }).count
        let unfinishedTaskCount = tasks.filter { task in
            guard !task.isCompleted, task.parentTaskID == nil else { return false }
            return task.briefID.map(activeBriefIDs.contains) ?? true
        }.count
        let unscheduledIdeaCount = activeBriefs.filter { brief in
            guard brief.status == .spark || brief.status == .developing else { return false }
            return !outputs.contains { $0.briefID == brief.id && $0.targetDate != nil }
        }.count

        var items: [CyPlateItem] = []
        if latePostCount > 0 {
            items.append(CyPlateItem(
                id: "late-posts",
                count: latePostCount,
                title: latePostCount == 1 ? "Post needs a new date" : "Posts need new dates"
            ))
        }
        if unfinishedTaskCount > 0 {
            items.append(CyPlateItem(
                id: "unfinished-tasks",
                count: unfinishedTaskCount,
                title: unfinishedTaskCount == 1 ? "Task is still open" : "Tasks are still open"
            ))
        }
        if unscheduledIdeaCount > 0 {
            items.append(CyPlateItem(
                id: "unscheduled-ideas",
                count: unscheduledIdeaCount,
                title: unscheduledIdeaCount == 1 ? "Idea is waiting to be scheduled" : "Ideas are waiting to be scheduled"
            ))
        }
        return items
    }

    private var onYourPlateSuggestion: (display: String, prompt: String) {
        let now = Date()
        let activeBriefs = briefs.filter { $0.status != .archived }
        let activeBriefIDs = Set(activeBriefs.map(\.id))

        let lateOutput = outputs
            .filter {
                activeBriefIDs.contains($0.briefID) &&
                    $0.status != .posted &&
                    isLate($0, now: now)
            }
            .sorted(by: {
                ($0.targetDate ?? .distantPast) < ($1.targetDate ?? .distantPast)
            })
            .first
        if let lateOutput,
           let lateBrief = activeBriefs.first(where: { $0.id == lateOutput.briefID }) {
            return (
                "The date for \(quotedPostTitle(lateBrief.title)) has passed. Want to choose a new one together?",
                "Help me reschedule \(quotedPostTitle(lateBrief.title))."
            )
        }

        let openTask = tasks
            .filter {
                !$0.isCompleted &&
                    $0.parentTaskID == nil &&
                    ($0.briefID.map(activeBriefIDs.contains) ?? true)
            }
            .sorted(by: {
                ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
            })
            .first
        if let openTask {
            return (
                "\(openTask.title) is still open. Want to decide the next step together?",
                "Help me decide the next step for \(openTask.title)."
            )
        }

        if let idea = activeBriefs.first(where: { brief in
            (brief.status == .spark || brief.status == .developing) &&
                !outputs.contains { $0.briefID == brief.id && $0.targetDate != nil }
        }) {
            return (
                "Let’s expand on some of these ideas",
                "Keep shaping \(quotedPostTitle(idea.title))."
            )
        }

        return (
            "Nothing needs your attention right now. Want to create something new?",
            "Help me choose what to make next."
        )
    }

    private func useOnYourPlatePrompt() {
        prompt = onYourPlateSuggestion.prompt
        composerIsFocused = true
    }

    private func isLate(_ output: PlatformOutput, now: Date) -> Bool {
        guard let targetDate = output.targetDate else { return false }
        if output.includesTargetTime { return targetDate < now }
        return Calendar.current.startOfDay(for: targetDate) < Calendar.current.startOfDay(for: now)
    }

    private var primaryStarter: String {
        currentDraft.map { "Keep shaping \(quotedPostTitle($0.title))" } ?? CreatorProfile.defaultCyQuickPrompts[0]
    }

    private var starterPrompts: [String] {
        profiles.first?.customCyQuickPrompts ?? [
            primaryStarter,
            CreatorProfile.defaultCyQuickPrompts[1]
        ]
    }

    private func quotedPostTitle(_ title: String) -> String {
        "“\(title.trimmingCharacters(in: .whitespacesAndNewlines))”"
    }

    private var composerPlaceholder: String { "Ask Cy anything" }

    private func openProAccess() {
        showProAccessDetails = false
        showProUpsell = true
    }

    private func reviewCard(for request: MCPBridgeChangeRequest) -> some View {
        let brief = linkedBrief(for: request)
        let output = linkedOutput(for: request)
        let pillar = linkedPillar(for: request, brief: brief)
        let accent = pillar.map {
            Color(agentHex: $0.resolvedColorHex(in: activePillars))
        } ?? Color.agentSecondary
        let platform = request.payload.platform
            .flatMap(CreatorPlatform.init(rawValue:))?.shortTitle
            ?? output?.platform.shortTitle
            ?? "Post"
        let date = request.payload.targetDate ?? output?.targetDate
        let metadata = date.map {
            "\(platform) · \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        } ?? platform

        return AgentPostCard(
            title: nonempty(request.payload.title) ?? brief?.title ?? request.summary,
            pillar: pillar?.name ?? "Unfiled",
            accent: accent,
            status: .ready,
            metadata: metadata,
            timeText: request.payload.includesTargetTime == false
                ? nil
                : date?.formatted(date: .omitted, time: .shortened),
            statusTextOverride: "To review"
        )
    }

    private var activePillars: [Pillar] { pillars.filter { !$0.isArchived } }

    private func linkedBrief(for request: MCPBridgeChangeRequest) -> CreativeBrief? {
        request.payload.postId.flatMap { id in briefs.first { $0.id == id } }
    }

    private func linkedOutput(for request: MCPBridgeChangeRequest) -> PlatformOutput? {
        if let outputID = request.payload.outputId,
           let output = outputs.first(where: { $0.id == outputID }) {
            return output
        }
        guard let postID = request.payload.postId else { return nil }
        return outputs.first { $0.briefID == postID }
    }

    private func linkedPillar(
        for request: MCPBridgeChangeRequest,
        brief: CreativeBrief?
    ) -> Pillar? {
        let pillarID = request.payload.pillarId ?? brief?.pillarID
        return pillarID.flatMap { id in activePillars.first { $0.id == id } }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func reloadPendingReviews() {
        guard MCPBridgePreferences.isConnected else {
            pendingReviews = []
            showReviewCompletion = false
            hasLoadedPendingReviews = true
            return
        }
        guard let requests = try? MCPBridgeService.pendingRequests() else {
            return
        }
        if hasLoadedPendingReviews, !pendingReviews.isEmpty, requests.isEmpty {
            showReviewCompletion = true
        } else if !requests.isEmpty {
            showReviewCompletion = false
        }
        pendingReviews = requests
        hasLoadedPendingReviews = true
    }

    private var showsConversation: Bool {
        pendingReviews.isEmpty && !showReviewCompletion
    }

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
        newThread.workspaceID = appModel.resolvedWorkspaceID(context: context)
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

    private func openThreadFromHistory(_ selectedThread: ConversationThread) {
        selectedThread.isArchived = false
        selectedThread.updatedAt = Date()
        thread = selectedThread
        try? context.save()
        showConversationHistory = false
    }

    private func deleteThreadFromHistory(_ selectedThread: ConversationThread) {
        let deletesCurrentThread = thread?.id == selectedThread.id
        if deletesCurrentThread {
            thread = nil
        }
        try? ConversationDeletionService.delete(
            selectedThread,
            messages: allMessages,
            context: context
        )
        if deletesCurrentThread {
            startNewThread()
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let thread else { return }
        let priorMessages = messages
        prompt = ""
        composerIsFocused = false
        let creatorMessage = ConversationMessage(threadID: thread.id, role: .creator, text: text)
        context.insert(creatorMessage)
        if thread.title == "Conversation" || thread.title == "Ask Cy" {
            thread.title = ConversationTitleFormatter.title(from: text)
        }
        thread.turnCount += 1
        thread.updatedAt = Date()
        try? context.save()

        let sendID = UUID()
        activeSendID = sendID
        isSending = true
        let conversation = Array((priorMessages + [creatorMessage]).suffix(24)).map {
            ConversationMessageWire(messageId: $0.id, role: $0.role == .creator ? .user : .assistant, content: $0.text)
        }
        let referencedBrief = referencedBrief(for: text)
        sendTask = Task {
            if let reply = await appModel.askCy(
                text,
                conversation: conversation,
                about: referencedBrief,
                context: context
            ) {
                guard !Task.isCancelled else { return }
                context.insert(ConversationMessage(
                    threadID: thread.id,
                    role: .cy,
                    text: reply.assistantMessage,
                    suggestions: reply.suggestions,
                    proposedAction: reply.proposedAction,
                    referencedBriefID: referencedBrief?.id
                ))
                thread.updatedAt = Date()
                try? context.save()
            }
            guard activeSendID == sendID else { return }
            activeSendID = nil
            sendTask = nil
            isSending = false
        }
    }

    private func stopSending() {
        activeSendID = nil
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    private func referencedBrief(for message: String) -> CreativeBrief? {
        let normalizedMessage = message.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let namedBrief = briefs.first { brief in
            let title = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3 else { return false }
            return normalizedMessage.contains(title.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ))
        }
        return namedBrief ?? currentDraft
    }

    private func canSendResponseToPost(_ message: ConversationMessage) -> Bool {
        guard !sentToPostMessageIDs.contains(message.id),
              message.referencedBriefID != nil else { return false }
        return message.proposedActionKind == .reviseBrief || message.proposedActionKind == .developSpark
    }

    private func sendResponseToPost(_ message: ConversationMessage) {
        guard let briefID = message.referencedBriefID,
              let brief = briefs.first(where: { $0.id == briefID }) else {
            appModel.notice = .error("That post could not be found.")
            return
        }

        let cleanResponse = String(renderedMarkdown(message.text).characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanResponse.isEmpty else { return }
        if brief.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            brief.notes = cleanResponse
        } else if !brief.notes.contains(cleanResponse) {
            brief.notes += "\n\n" + cleanResponse
        }
        brief.updatedAt = Date()
        do {
            try context.save()
            sentToPostMessageIDs.insert(message.id)
            appModel.notice = .info("Added to \(brief.title).")
            appModel.widgetBriefOpensEditor = true
            appModel.widgetBriefID = brief.id
            appModel.requestedPlanMode = .week
            appModel.selectedTab = .today
        } catch {
            appModel.notice = .error("That response could not be added to the post.")
        }
    }

}

private struct CyConversationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let threads: [ConversationThread]
    let messages: [ConversationMessage]
    let currentThreadID: UUID?
    let openThread: (ConversationThread) -> Void
    let deleteThread: (ConversationThread) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    EditorialHeader(
                        kicker: "Cy",
                        title: "Conversation history",
                        subtitle: "Your conversations stay with this account until you erase them."
                    )

                    if threads.isEmpty {
                        Text("No conversations yet.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                let threadMessages = messages.filter { $0.threadID == thread.id }
                                NavigationLink {
                                    CyConversationTranscriptView(
                                        title: displayTitle(for: thread, messages: threadMessages),
                                        thread: thread,
                                        messages: threadMessages,
                                        isCurrent: currentThreadID == thread.id,
                                        continueConversation: {
                                            openThread(thread)
                                            dismiss()
                                        },
                                        deleteConversation: { deleteThread(thread) }
                                    )
                                } label: {
                                    conversationRow(thread)
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .top) {
                                    if index > 0 {
                                        Rectangle().fill(Color.agentHairline).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, AgentSpacing.x12)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .agentScreen()
        }
    }

    private func conversationRow(_ thread: ConversationThread) -> some View {
        let threadMessages = messages.filter { $0.threadID == thread.id }
        let preview = threadMessages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No messages yet"
        let title = displayTitle(for: thread, messages: threadMessages)
        return VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Text(title.protectingWordBoundaries)
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .lineLimit(2)
                    .accessibilityLabel(title)
                Spacer()
                if currentThreadID == thread.id {
                    MetaLabel("Current")
                        .foregroundStyle(Color.cyAccent)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.agentSecondary)
            }

            Text(preview)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .lineLimit(2)

            MetaLabel(thread.updatedAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .contentShape(.rect)
    }

    private func displayTitle(
        for thread: ConversationThread,
        messages threadMessages: [ConversationMessage]
    ) -> String {
        ConversationTitleFormatter.resolvedTitle(
            savedTitle: thread.title,
            firstCreatorMessage: threadMessages.first(where: { $0.role == .creator })?.text
        )
    }
}

enum ConversationTitleFormatter {
    static let defaultMaximumLength = 72

    static func title(
        from text: String,
        maximumLength: Int = defaultMaximumLength
    ) -> String {
        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let firstWord = words.first else { return "New conversation" }
        guard maximumLength > 0 else { return firstWord }

        var result = ""
        for word in words {
            let candidate = result.isEmpty ? word : "\(result) \(word)"
            if candidate.count > maximumLength {
                // A single long word remains intact instead of being split.
                return result.isEmpty ? word : result
            }
            result = candidate
        }
        return result
    }

    static func resolvedTitle(
        savedTitle: String,
        firstCreatorMessage: String?
    ) -> String {
        let saved = savedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCreatorMessage else {
            return saved.isEmpty || saved == "Conversation" || saved == "Ask Cy"
                ? "New conversation"
                : saved
        }

        let normalizedMessage = firstCreatorMessage
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let generated = title(from: normalizedMessage)
        let savedIsPlaceholder = saved.isEmpty || saved == "Conversation" || saved == "Ask Cy"
        let savedWasCharacterTruncated = !saved.isEmpty
            && normalizedMessage.hasPrefix(saved)
            && saved.count < normalizedMessage.count

        return savedIsPlaceholder || savedWasCharacterTruncated ? generated : saved
    }
}

@MainActor
enum ConversationDeletionService {
    static func delete(
        _ thread: ConversationThread,
        messages: [ConversationMessage],
        context: ModelContext
    ) throws {
        messages
            .filter { $0.threadID == thread.id }
            .forEach { context.delete($0) }
        context.delete(thread)
        try context.save()
    }
}

private struct CyConversationTranscriptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    let title: String
    let thread: ConversationThread
    let messages: [ConversationMessage]
    let isCurrent: Bool
    let continueConversation: () -> Void
    let deleteConversation: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("Cy · Transcript")
                    Text(title.protectingWordBoundaries)
                        .font(.agentDisplay)
                        .tracking(-0.64)
                        .foregroundStyle(Color.agentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(title)
                    Text(transcriptMetadata)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if messages.isEmpty {
                    Text("No messages were saved in this conversation.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                } else {
                    transcriptDivider
                    ForEach(messages) { message in
                        transcriptMessage(message)
                    }
                }

                Button(isCurrent ? "Return to conversation" : "Continue conversation") {
                    continueConversation()
                }
                .buttonStyle(AgentCyPrimaryButtonStyle())
                .padding(.top, AgentSpacing.x4)
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x8)
            .padding(.bottom, AgentSpacing.x12)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete conversation", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.agentText)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Color.agentSurface)
                .accessibilityLabel("Conversation options")
            }
        }
        .confirmationDialog("Delete this conversation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete conversation", role: .destructive) {
                deleteConversation()
                dismiss()
            }
        } message: {
            Text("This permanently removes the conversation and its messages.")
        }
        .agentScreen()
    }

    private var transcriptMetadata: String {
        let count = messages.count
        let date = thread.updatedAt.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(date) · \(count) \(count == 1 ? "message" : "messages")"
    }

    private var transcriptDivider: some View {
        HStack(spacing: AgentSpacing.x3) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
            MetaLabel(thread.createdAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .fixedSize()
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
        .padding(.bottom, AgentSpacing.x2)
    }

    @ViewBuilder
    private func transcriptMessage(_ message: ConversationMessage) -> some View {
        switch message.role {
        case .creator:
            VStack(alignment: .trailing, spacing: AgentSpacing.x2) {
                MetaLabel("You")
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
        case .cy:
            assistantTranscriptMessage(label: "Cy", text: message.text, showsAsterisk: true)
        case .claude:
            assistantTranscriptMessage(label: "Claude · Imported", text: message.text, showsAsterisk: false)
        }
    }

    private func assistantTranscriptMessage(label: String, text: String, showsAsterisk: Bool) -> some View {
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
}

private extension String {
    /// Prevents SwiftUI from falling back to character wrapping inside ordinary
    /// words while leaving whitespace available as the line-break opportunity.
    var protectingWordBoundaries: String {
        let characters = Array(self)
        guard characters.count > 1 else { return self }

        var protected = ""
        for index in characters.indices {
            protected.append(characters[index])
            let nextIndex = characters.index(after: index)
            guard nextIndex < characters.endIndex,
                  !characters[index].isWhitespace,
                  !characters[nextIndex].isWhitespace else { continue }
            protected.append("\u{2060}")
        }
        return protected
    }
}
