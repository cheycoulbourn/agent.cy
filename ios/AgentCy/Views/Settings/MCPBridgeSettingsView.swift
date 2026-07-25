import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum MCPBridgeStarterPrompt {
    static let defaultValue = """
    Use the agent.cy MCP and call bridge_status first. You are my content planning partner, not an autopilot. Treat the active agent.cy account as the only creator workspace in scope.

    Start in Plan mode. Use the native question tool, such as request_user_input in Codex or AskUserQuestion in Claude Code. If no question tool is available, ask one focused question at a time. Do not create posts or tasks yet.

    First learn the creator: goals, audience, platforms and account, pillars, current ideas, creative capacity, posting rhythm, constraints, and what success means. Read relevant agent.cy context and project files. Confirm uncertain assumptions. Then present a specific content plan with reasoning and wait for explicit approval.

    Only after approval, queue changes through the agent.cy MCP write tools. For a new post with an approved date, call create_post_draft once with targetDate and includesTargetTime so creation and scheduling share one review. Use only the exact catalog format values shown by agent.cy, such as Reel, Story, Carousel, Feed post, Short video, Long video, Short, or Video. Never hide a posting date in notes and never queue a second schedule_post request for the same new post. Every queued post, idea, schedule, and task must remain reviewable in Cy before it changes the app. Never assume a queued request was approved.

    Keep learning over time. When I reveal a durable preference or correct you, summarize what you learned and propose the exact update for this project's AGENTS.md, CLAUDE.md, creator instructions, or a reusable skill. Explain the value, ask permission, and only write or update instructions after explicit approval. Adapt future questions and plans to approved creator knowledge instead of restarting discovery each time.
    """
}

struct MCPBridgeSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @State private var chooseFolder = false
    @State private var pendingRequests: [MCPBridgeChangeRequest] = []
    @State private var message: String?
    @State private var copiedSetup = false
    @State private var copiedProjectPrompt = false
    @State private var promptEditorExpanded = false
    @State private var refreshID = UUID()
    @State private var localCyEnabled = LocalCyPreferences.isEnabled
    @State private var localCyStatus: LocalCyRuntimeStatus?
    @AppStorage("agentcy.mcp.projectPrompt") private var projectPrompt = MCPBridgeStarterPrompt.defaultValue

    var body: some View {
        SettingsPageShell(
            kicker: "AI",
            title: "Claude & Codex",
            subtitle: "Plan with Claude or Codex, then review every change in Cy."
        ) {
            connectionCard
                .id(refreshID)

            if MCPBridgePreferences.isConnected {
                localCySection
                pendingSection
                demoSection
                syncSection
            } else {
                setupSection
            }

            useFromAnyProjectSection

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                SectionRuleHeader(title: "Privacy")
                Text("Creator content stays in the iCloud Drive folder you choose. The bridge runs on your computer, and every proposal waits for approval in Cy before it can update agent.cy.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(
            isPresented: $chooseFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let folder = try result.get().first else { return }
                try MCPBridgePreferences.connect(to: folder)
                try MCPBridgeService.sync(context: context)
                message = "Claude & Codex connected."
                reload()
            } catch {
                show(error, action: "The connection")
            }
        }
        .alert("agent.cy", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("Close", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear { reload() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                reload()
            }
        }
    }

    private var localCySection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Local Cy")
            AgentInsetSurface {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    HStack(alignment: .center, spacing: AgentSpacing.x3) {
                        ZStack {
                            Circle()
                                .fill(localCyStatus?.isRecentlyAvailable == true ? Color.cyAccent : Color.agentCanvas)
                                .frame(width: 42, height: 42)
                            CyAsterisk(
                                color: localCyStatus?.isRecentlyAvailable == true ? .onCyAccent : .agentText,
                                size: 19,
                                strokeWidth: 1.7
                            )
                        }
                        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                            Text(localCyStatus?.isRecentlyAvailable == true ? "Mac available" : "Mac not detected")
                                .font(.agentBody.weight(.semibold))
                            Text(localCyStatus?.message ?? "Run the Local Cy worker on your Mac to use your Claude subscription.")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: AgentSpacing.x2)
                        Toggle("", isOn: Binding(
                            get: { localCyEnabled },
                            set: { enabled in
                                localCyEnabled = enabled
                                LocalCyPreferences.isEnabled = enabled
                            }
                        ))
                        .labelsHidden()
                    }

                    Text("When enabled, Cy requests are handled by Claude on your Mac. Your Claude credentials never leave the computer, and Railway is not used for generation.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var useFromAnyProjectSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Use with Claude or Codex")

            Text("The bridge runs on your computer. Claude or Codex reads a limited snapshot from the iCloud Drive folder you chose, then sends proposals to Cy on your iPhone for review. Supported mobile apps can continue a connected computer session, but they do not host the bridge themselves.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AgentInsetSurface {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("WHAT HAPPENS WHERE")
                    bridgeLocation(title: "On your iPhone", detail: "Your posts, pillars, tasks, accounts, and approvals stay in agent.cy.")
                    bridgeLocation(title: "On your computer", detail: "Claude Code or Codex helps you plan and places review requests in the shared folder.")
                    bridgeLocation(title: "In iCloud Drive", detail: "A limited workspace snapshot and pending requests move between the two devices.")
                }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                instruction(number: "1", text: "Install the agent.cy bridge on your Mac or Windows computer. Keep the same iCloud Drive account active on your iPhone and computer.")
                instruction(number: "2", text: "In agent.cy, switch to the creator account you want to plan for and tap Sync now.")
                instruction(number: "3", text: "Open any project in Claude Code or Codex on that computer. Ask it to call bridge_status so you know the connection is working.")
                instruction(number: "4", text: "Switch the AI to Plan mode when that option is available, then paste the planning-partner prompt below.")
                instruction(number: "5", text: "Answer the creator questions. Review the proposed plan and explicitly approve it before the AI queues posts or tasks.")
                instruction(number: "6", text: "Open Cy on your iPhone. The Cy icon spins while proposals are waiting. Review, edit, approve, or deny each one.")
                instruction(number: "7", text: "Only approved proposals become real agent.cy content. Sync again before starting work for a different creator account.")
            }

            AgentInsetSurface {
                Text(projectPrompt)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                UIPasteboard.general.string = projectPrompt
                copiedProjectPrompt = true
            } label: {
                AgentIconLabel(
                    title: copiedProjectPrompt ? "Prompt copied" : "Copy starter prompt",
                    icon: copiedProjectPrompt ? .check : .copy
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AgentSecondaryButtonStyle())

            DisclosureGroup(isExpanded: $promptEditorExpanded) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    TextEditor(text: $projectPrompt)
                        .font(.agentSubtext)
                        .scrollContentBackground(.hidden)
                        .padding(AgentSpacing.x3)
                        .frame(minHeight: 260)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }

                    Button("Reset to the agent.cy prompt") {
                        projectPrompt = MCPBridgeStarterPrompt.defaultValue
                        copiedProjectPrompt = false
                    }
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                }
                .padding(.top, AgentSpacing.x3)
            } label: {
                Text("Customize this prompt")
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 44)
            }
            .tint(Color.agentText)
        }
    }

    private var connectionCard: some View {
        AgentInsetSurface {
            HStack(spacing: AgentSpacing.x4) {
                ZStack {
                    Circle()
                        .fill(MCPBridgePreferences.isConnected ? Color.cyAccent : Color.agentCanvas)
                        .frame(width: 48, height: 48)
                    AgentIconView(.terminal, size: 18)
                        .foregroundStyle(MCPBridgePreferences.isConnected ? Color.onCyAccent : Color.agentText)
                }
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(MCPBridgePreferences.isConnected ? "Connected" : "Not connected")
                        .font(.agentHeadline)
                    Text(MCPBridgePreferences.isConnected ? MCPBridgePreferences.folderName : "Choose the shared iCloud Drive folder")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if MCPBridgePreferences.isConnected {
                    AgentIconView(.check, size: 15)
                        .foregroundStyle(Color.agentSuccess)
                }
            }
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Connect")
            instruction(number: "1", text: "Download and open the guided installer for your computer.")
            Link("Download installer", destination: URL(string: "https://github.com/cheycoulbourn/agent.cy/releases/latest")!)
                .buttonStyle(AgentPrimaryButtonStyle())

            instruction(number: "2", text: "Let the installer find iCloud Drive, Claude Code, and Codex. It will register agentcy and test the connection.")
            instruction(number: "3", text: "In Files on this iPhone, choose the same agent.cy MCP folder.")
            Button {
                chooseFolder = true
            } label: {
                AgentIconLabel(title: "Choose MCP folder", icon: .folder)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AgentPrimaryButtonStyle())

            DisclosureGroup("Advanced developer setup") {
                Button {
                    UIPasteboard.general.string = "pnpm mcp:setup"
                    copiedSetup = true
                } label: {
                    AgentIconLabel(
                        title: copiedSetup ? "Setup command copied" : "Copy source setup command",
                        icon: copiedSetup ? .check : .copy
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AgentSecondaryButtonStyle())
                .padding(.top, AgentSpacing.x3)
            }
            .font(.agentBody.weight(.semibold))
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Waiting for approval", trailing: "\(pendingRequests.count)")
            if pendingRequests.isEmpty {
                Text("No proposals are waiting.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                AgentInsetSurface {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        HStack(spacing: AgentSpacing.x2) {
                            CyAsterisk(color: .cyAccent, size: 18, strokeWidth: 1.6)
                            MetaLabel("CY · FOR REVIEW")
                                .foregroundStyle(Color.cyAccent)
                        }
                        Text("\(pendingRequests.count) change\(pendingRequests.count == 1 ? "" : "s") waiting")
                            .font(.agentHeadline)
                        Text("Open Cy to review the complete posts before anything changes.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
                Button("Review in Cy") {
                    appModel.requestedSettingsPage = nil
                    appModel.presentedSheet = nil
                    appModel.selectedTab = .cy
                }
                .buttonStyle(AgentCyPrimaryButtonStyle())
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Workspace")
            if let date = MCPBridgePreferences.lastSyncAt {
                HStack {
                    Text("Last synced")
                        .font(.agentBody)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
            }
            Button {
                do {
                    try MCPBridgeService.sync(context: context)
                    message = "Workspace synced."
                    reload()
                } catch {
                    show(error, action: "Workspace sync")
                }
            } label: {
                AgentIconLabel(title: "Sync now", icon: .refresh)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AgentPrimaryButtonStyle())

            Button {
                chooseFolder = true
            } label: {
                Text("Choose a different folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AgentSecondaryButtonStyle())

            Button(role: .destructive) {
                MCPBridgePreferences.disconnect()
                pendingRequests = []
                refreshID = UUID()
            } label: {
                Text("Disconnect Claude & Codex")
                    .frame(maxWidth: .infinity)
            }
            .font(.agentBody)
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Try the review flow")
            Text("Send a complete sample post to Cy whenever you want to test reviewing, editing, approving, or denying an MCP proposal. Nothing is created until you approve it.")
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                do {
                    try MCPBridgeService.queueDemoDraft(context: context)
                    reload()
                    appModel.requestedSettingsPage = nil
                    appModel.presentedSheet = nil
                    appModel.selectedTab = .cy
                } catch {
                    show(error, action: "The test proposal")
                }
            } label: {
                Label {
                    Text("Send demo draft to Cy")
                } icon: {
                    CyAsterisk(color: .onCyAccent, size: 16)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AgentCyPrimaryButtonStyle())
        }
    }

    private func bridgeLocation(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            Text(title)
                .font(.agentBody.weight(.semibold))
                .foregroundStyle(Color.agentText)
            Text(detail)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func instruction(number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
            Text(number)
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reload() {
        guard let requests = try? MCPBridgeService.pendingRequests() else {
            return
        }
        pendingRequests = requests
        refreshID = UUID()
        Task {
            localCyStatus = try? await LocalCyAIClient.shared.runtimeStatus()
        }
    }

    private func show(_ error: Error, action: String) {
        message = CreatorFacingErrorMapper.presentation(for: error, action: action).message
    }

}

private struct MCPBridgeRequestReviewField: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

enum MCPReviewEditPolicy {
    static func allowsEditing(type: String) -> Bool {
        type == "createPostDraft" || type == "updatePost" || type == "schedulePost"
    }
}

enum MCPReviewPillarPresentation {
    static func label(type: String, pillarName: String) -> String {
        pillarName
    }

    static func metadata(type: String, fallback: String) -> String {
        type == "createIdea" ? "Idea" : fallback
    }
}

struct MCPBridgeRequestReviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Query private var briefs: [CreativeBrief]
    @Query private var outputs: [PlatformOutput]
    @Query private var formats: [PublishingFormat]
    @Query private var pillars: [Pillar]
    @Query private var tasks: [CreatorTask]
    @Query private var workspaces: [CreatorWorkspace]

    let request: MCPBridgeChangeRequest
    let approve: (MCPBridgeChangeRequest) throws -> Void
    let decline: () throws -> Void

    @State private var errorMessage: String?
    @State private var showEditor = false
    @State private var workingPayload: MCPBridgeRequestPayload

    init(
        request: MCPBridgeChangeRequest,
        approve: @escaping (MCPBridgeChangeRequest) throws -> Void,
        decline: @escaping () throws -> Void
    ) {
        self.request = request
        self.approve = approve
        self.decline = decline
        _workingPayload = State(initialValue: request.payload)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                postHeader
                if isPostReview {
                    postingDetails
                    postContent
                    linkedTasks
                } else {
                    genericChangeDetails
                }
                reviewActions
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .agentBottomNavigationClearance()
        }
        .scrollIndicators(.hidden)
        .background(Color.agentCanvas)
        .navigationTitle(isPostReview ? "Review post" : "Review change")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
            }
            .sharedBackgroundVisibility(.hidden)
            if canEditReview {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") { showEditor = true }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if request.type == "createPostDraft" {
                NavigationStack {
                    MCPCreatePostDraftReviewEditor(
                        payload: $workingPayload,
                        onSave: { showEditor = false }
                    )
                }
            } else if let editableBrief, let editableOutput {
                NavigationStack {
                    ResumablePostEditorView(
                        brief: editableBrief,
                        output: editableOutput,
                        contextLabel: "Edit before approval",
                        isReviewEditing: true,
                        bottomActionClearance: AgentSpacing.x3,
                        onSpark: {}
                    )
                    .taskNavigationDestinations()
                    .navigationTitle("Edit post")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            AgentToolbarIconButton(title: "Close", icon: .close) { showEditor = false }
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    .agentScreen()
                    .agentKeyboardDismissal()
                }
            }
        }
        .alert("agent.cy", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Close", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: linkedBrief?.id) {
            guard let linkedBrief,
                  MCPBridgeService.restorePremiseIfNotesWereCopied(linkedBrief) else { return }
            try? context.save()
        }
        .agentScreen()
    }

    private var postHeader: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(spacing: AgentSpacing.x2) {
                PillarColorMark(color: pillarColor, diameter: 7)
                Text(reviewPillarLabel.uppercased())
                    .font(.agentMetadata)
                    .tracking(0.7)
                    .lineLimit(1)
                Spacer()
                Text("TO REVIEW")
                    .font(.agentMetadata)
                    .tracking(0.6)
                    .padding(.horizontal, AgentSpacing.x2)
                    .frame(minHeight: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.agentText.opacity(0.20), lineWidth: 1)
                    }
            }

            Text(reviewTitle)
                .font(.paperInter(size: 32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.64)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)

            if let premise = proposedPremise {
                Text(premise)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var postingDetails: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Posting details")
            detailRow(label: "Date", value: proposedDateText)
            detailRow(label: "Platform", value: proposedPlatform)
            detailRow(label: "Format", value: proposedFormat)
            detailRow(label: "Duration", value: proposedDuration)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x4)
        .background(pillarColor.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    PillarVisualContrast.cardBorderColor(for: pillarColor, colorScheme: colorScheme),
                    lineWidth: 1
                )
        }
    }

    private var postContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: "Post")
            if postFields.isEmpty {
                Text("No post copy has been added yet.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                ForEach(postFields) { field in
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel(field.label.uppercased())
                        Text(field.value)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, AgentSpacing.x4)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.agentHairline).frame(height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linkedTasks: some View {
        if !postTasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Tasks", trailing: "\(postTasks.count)")
                ForEach(postTasks) { task in
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(task.title)
                            .font(.agentBody.weight(.semibold))
                        Text(taskMetadata(task))
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AgentSpacing.x3)
                }
            }
        }
    }

    private var genericChangeDetails: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            SectionRuleHeader(title: sectionTitle)
            ForEach(reviewFields) { field in
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel(field.label.uppercased())
                    Text(field.value)
                        .font(.agentBody)
                        .foregroundStyle(Color.agentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var reviewActions: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            Text(approvalExplanation)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(approvalActionTitle) { perform { try approve(approvalRequest) } }
                .buttonStyle(AgentCyPrimaryButtonStyle())
                .accessibilityHint(approvalExplanation)
            Button("Deny") { perform(decline) }
                .buttonStyle(AgentSecondaryButtonStyle())
        }
    }

    private var approvalActionTitle: String {
        switch request.type {
        case "createPostDraft":
            return payload.targetDate == nil ? "Approve draft" : "Approve & schedule"
        case "updatePost":
            return "Approve changes"
        case "schedulePost":
            return "Approve date"
        case "createIdea":
            return "Approve idea"
        case "addTask":
            return "Approve task"
        case "completeTask":
            return "Approve completion"
        default:
            return "Approve"
        }
    }

    private var approvalExplanation: String {
        switch request.type {
        case "createPostDraft" where payload.targetDate != nil:
            return "One approval creates the post and adds it to your calendar."
        case "createPostDraft":
            return "One approval saves this as a resumable draft."
        case "schedulePost":
            return "This changes the date of an existing post."
        default:
            return "Nothing changes until you approve it."
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x4) {
            MetaLabel(label)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.agentBody.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var linkedBrief: CreativeBrief? {
        payload.postId.flatMap { id in briefs.first { $0.id == id } }
    }

    private var linkedTask: CreatorTask? {
        payload.taskId.flatMap { id in tasks.first { $0.id == id } }
    }

    private var linkedOutput: PlatformOutput? {
        if let outputID = payload.outputId,
           let output = outputs.first(where: { $0.id == outputID }) {
            return output
        }
        guard let postID = payload.postId else { return nil }
        return outputs.first { $0.briefID == postID }
    }

    private var editableBrief: CreativeBrief? {
        MCPReviewEditPolicy.allowsEditing(type: request.type) ? linkedBrief : nil
    }

    private var editableOutput: PlatformOutput? {
        MCPReviewEditPolicy.allowsEditing(type: request.type) ? linkedOutput : nil
    }

    private var isPostReview: Bool {
        ["createPostDraft", "updatePost", "schedulePost"].contains(request.type)
    }

    private var activePillars: [Pillar] {
        pillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var selectedPillar: Pillar? {
        let pillarID = payload.pillarId ?? linkedBrief?.pillarID
        return pillarID.flatMap { id in activePillars.first { $0.id == id } }
    }

    private var pillarName: String { selectedPillar?.name ?? "Unfiled" }

    private var reviewPillarLabel: String {
        MCPReviewPillarPresentation.label(type: request.type, pillarName: pillarName)
    }

    private var pillarColor: Color {
        selectedPillar.map {
            Color(agentHex: $0.resolvedColorHex(in: activePillars))
        } ?? Color.agentSecondary
    }

    private var proposedPremise: String? {
        let value = nonempty(payload.premise) ?? nonempty(linkedBrief?.premise)
        guard value != nonempty(linkedBrief?.notes) else { return nil }
        return value
    }

    private var proposedDate: Date? {
        payload.targetDate ?? linkedOutput?.targetDate
    }

    private var proposedDateText: String {
        proposedDate.map(scheduleDate) ?? "Not set"
    }

    private var proposedPlatform: String {
        platformTitle(payload.platform) ?? linkedOutput?.platform.title ?? "Not set"
    }

    private var proposedFormat: String {
        nonempty(payload.format)
            ?? linkedOutput?.formatID.flatMap { id in formats.first { $0.id == id }?.name }
            ?? "Not set"
    }

    private var proposedDuration: String {
        let duration = linkedOutput?.durationSeconds ?? linkedBrief?.durationSeconds ?? 0
        guard duration > 0 else { return "Not set" }
        return ContentDurationLabel.full(duration)
    }

    private var postTasks: [CreatorTask] {
        guard let briefID = linkedBrief?.id else { return [] }
        return tasks
            .filter { $0.briefID == briefID && $0.parentTaskID == nil }
            .sorted { lhs, rhs in
                if lhs.targetDate != rhs.targetDate {
                    return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var postFields: [MCPBridgeRequestReviewField] {
        var fields: [MCPBridgeRequestReviewField] = []
        append("Hook", payload.hook ?? linkedBrief?.spokenHook, to: &fields)
        append("Script", linkedBrief?.scriptBeatsText, to: &fields)
        append("Caption", payload.caption ?? linkedOutput?.caption, to: &fields)
        append(
            "Call to action",
            nonempty(payload.callToAction)
                ?? nonempty(linkedOutput?.cta)
                ?? nonempty(linkedBrief?.ctaIntent),
            to: &fields
        )
        append("Notes", payload.notes ?? linkedBrief?.notes, to: &fields)
        return fields
    }

    private func taskMetadata(_ task: CreatorTask) -> String {
        var parts = [task.kind.title, task.priority.title]
        if let date = task.targetDate {
            parts.append(
                task.includesTargetTime
                    ? date.formatted(date: .abbreviated, time: .shortened)
                    : date.formatted(date: .abbreviated, time: .omitted)
            )
        }
        return parts.joined(separator: " · ").uppercased()
    }

    private var reviewTitle: String {
        nonempty(payload.title)
            ?? linkedBrief?.title
            ?? linkedTask?.title
            ?? request.summary
    }

    private var sectionTitle: String {
        switch request.type {
        case "createIdea": "PROPOSED IDEA"
        case "addTask", "completeTask": "PROPOSED TASK CHANGE"
        default: "PROPOSED POST"
        }
    }

    private var reviewFields: [MCPBridgeRequestReviewField] {
        var fields: [MCPBridgeRequestReviewField] = []
        let post = linkedBrief
        let output = linkedOutput
        let pillarID = payload.pillarId ?? post?.pillarID

        append("Pillar", pillarID.flatMap { id in pillars.first { $0.id == id }?.name }, to: &fields)

        switch request.type {
        case "createIdea":
            append("Notes", payload.notes, to: &fields)
        case "createPostDraft", "updatePost":
            append("Status", post?.status.title ?? "Draft", to: &fields)
            append("Platform", platformTitle(payload.platform) ?? output?.platform.title, to: &fields)
            append("Format", payload.format ?? output?.formatID.flatMap { id in formats.first { $0.id == id }?.name }, to: &fields)
            append("Premise", payload.premise ?? post?.premise, to: &fields)
            append("Hook", payload.hook ?? post?.spokenHook, to: &fields)
            append("Caption", payload.caption ?? output?.caption, to: &fields)
            append("Call to action", payload.callToAction ?? output?.cta ?? post?.ctaIntent, to: &fields)
            append("Details", payload.notes ?? post?.notes, to: &fields)
        case "schedulePost":
            append("Status", "Scheduled", to: &fields)
            append("Date", payload.targetDate.map(scheduleDate), to: &fields)
            append("Platform", output?.platform.title, to: &fields)
            append("Format", output?.formatID.flatMap { id in formats.first { $0.id == id }?.name }, to: &fields)
            append("Premise", post?.premise, to: &fields)
            append("Hook", post?.spokenHook, to: &fields)
            append("Caption", output?.caption, to: &fields)
            append("Call to action", output?.cta.isEmpty == false ? output?.cta : post?.ctaIntent, to: &fields)
            append("Details", post?.notes, to: &fields)
        case "addTask":
            append("Linked post", post?.title, to: &fields)
            append("Due", payload.targetDate.map(scheduleDate), to: &fields)
            append("Type", payload.kind?.replacingOccurrences(of: "_", with: " ").capitalized, to: &fields)
            append("Priority", payload.priority?.capitalized, to: &fields)
            append("Notes", payload.notes, to: &fields)
        case "completeTask":
            append("Linked post", linkedTask?.briefID.flatMap { id in briefs.first { $0.id == id }?.title }, to: &fields)
            append("Current status", linkedTask?.isCompleted == true ? "Completed" : "Open", to: &fields)
        default:
            append("Details", payload.notes, to: &fields)
        }
        return fields
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func append(_ label: String, _ value: String?, to fields: inout [MCPBridgeRequestReviewField]) {
        guard let value = nonempty(value) else { return }
        fields.append(.init(label: label, value: value))
    }

    private func platformTitle(_ rawValue: String?) -> String? {
        rawValue.flatMap(CreatorPlatform.init(rawValue:))?.title
    }

    private func scheduleDate(_ date: Date) -> String {
        if payload.includesTargetTime == false {
            return date.formatted(date: .long, time: .omitted)
        }
        return date.formatted(date: .long, time: .shortened)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            dismiss()
        } catch {
            errorMessage = CreatorFacingErrorMapper.presentation(for: error, action: "The proposal").message
        }
    }

    private var payload: MCPBridgeRequestPayload {
        request.type == "createPostDraft" ? workingPayload : request.payload
    }

    private var approvalRequest: MCPBridgeChangeRequest {
        request.replacingPayload(payload)
    }

    private var canEditReview: Bool {
        guard MCPReviewEditPolicy.allowsEditing(type: request.type) else { return false }
        if request.type == "createPostDraft" { return true }
        return editableBrief != nil && editableOutput != nil
    }
}

private struct MCPCreatePostDraftReviewEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Query private var allPillars: [Pillar]
    @Query private var workspaces: [CreatorWorkspace]

    @Binding var payload: MCPBridgeRequestPayload
    let onSave: () -> Void

    private var pillars: [Pillar] {
        allPillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var selectedPillar: Pillar? {
        payload.pillarId.flatMap { id in pillars.first { $0.id == id } }
    }

    private var selectedPlatform: CreatorPlatform {
        payload.platform.flatMap(CreatorPlatform.init(rawValue:)) ?? .instagramReels
    }

    private var formatChoices: [String] {
        switch selectedPlatform {
        case .instagramReels: ["Reel", "Carousel", "Feed post", "Story"]
        case .tiktok: ["Short video", "Long video"]
        case .youtubeShorts: ["Short"]
        case .youtubeVideo: ["Video"]
        }
    }

    private var selectedFormat: String {
        guard let format = payload.format, formatChoices.contains(format) else {
            return formatChoices[0]
        }
        return format
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("POST")
                    TextField("", text: textBinding(\.title), axis: .vertical)
                        .font(.paperInter(size: 28, weight: .bold, relativeTo: .title))
                        .tracking(-0.56)
                        .lineLimit(1...3)
                        .accessibilityLabel("Post title")
                }

                VStack(spacing: 0) {
                    Menu {
                        Button("No pillar") { payload.pillarId = nil }
                        ForEach(pillars) { pillar in
                            Button {
                                payload.pillarId = pillar.id
                            } label: {
                                PillarMenuChoiceLabel(
                                    title: pillar.name,
                                    colorHex: pillar.resolvedColorHex(in: pillars),
                                    isSelected: payload.pillarId == pillar.id
                                )
                            }
                        }
                    } label: {
                        editorRow(
                            label: "Pillar",
                            value: selectedPillar?.name ?? "No pillar",
                            color: selectedPillar.map { Color(agentHex: $0.resolvedColorHex(in: pillars)) }
                        )
                    }

                    Menu {
                        ForEach(CreatorPlatform.allCases) { platform in
                            Button(platform.title) {
                                payload.platform = platform.rawValue
                                payload.format = defaultFormat(for: platform)
                            }
                        }
                    } label: {
                        editorRow(label: "Platform", value: selectedPlatform.title)
                    }

                    Menu {
                        ForEach(formatChoices, id: \.self) { format in
                            Button(format) { payload.format = format }
                        }
                    } label: {
                        editorRow(label: "Format", value: selectedFormat)
                    }
                }
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Schedule this post", isOn: scheduledBinding)
                        .font(.agentBody.weight(.semibold))
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 54)

                    if payload.targetDate != nil {
                        Divider().padding(.horizontal, AgentSpacing.x4)
                        DatePicker("Date", selection: targetDateBinding, displayedComponents: .date)
                            .font(.agentBody)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 54)

                        Toggle("Include a time", isOn: includesTargetTimeBinding)
                            .font(.agentBody)
                            .padding(.horizontal, AgentSpacing.x4)
                            .frame(minHeight: 54)

                        if payload.includesTargetTime == true {
                            DatePicker("Time", selection: targetDateBinding, displayedComponents: .hourAndMinute)
                                .font(.agentBody)
                                .padding(.horizontal, AgentSpacing.x4)
                                .frame(minHeight: 54)
                        }
                    }
                }
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }

                reviewTextArea(label: "Premise", keyPath: \.premise, minHeight: 96)
                reviewTextArea(label: "Hook", keyPath: \.hook, minHeight: 96)
                reviewTextArea(label: "Caption", keyPath: \.caption, minHeight: 144)
                reviewTextArea(label: "Call to action", keyPath: \.callToAction, minHeight: 88)
                reviewTextArea(label: "Notes", keyPath: \.notes, minHeight: 112)
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .agentBottomNavigationClearance()
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Edit post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave() }
                    .disabled(textBinding(\.title).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private func editorRow(label: String, value: String, color: Color? = nil) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            MetaLabel(label)
            Spacer()
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(value)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
            AgentIconView(.forward)
                .font(.agentInter(size: 12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(Color.agentSecondary)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func reviewTextArea(
        label: String,
        keyPath: WritableKeyPath<MCPBridgeRequestPayload, String?>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            SectionRuleHeader(title: label)
            TextEditor(text: textBinding(keyPath))
                .font(.agentBody)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(AgentSpacing.x3)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .accessibilityLabel(label)
        }
    }

    private func textBinding(
        _ keyPath: WritableKeyPath<MCPBridgeRequestPayload, String?>
    ) -> Binding<String> {
        Binding(
            get: { payload[keyPath: keyPath] ?? "" },
            set: { payload[keyPath: keyPath] = $0 }
        )
    }

    private var scheduledBinding: Binding<Bool> {
        Binding(
            get: { payload.targetDate != nil },
            set: { isScheduled in
                payload.targetDate = isScheduled ? (payload.targetDate ?? Date()) : nil
                if !isScheduled { payload.includesTargetTime = false }
            }
        )
    }

    private var targetDateBinding: Binding<Date> {
        Binding(
            get: { payload.targetDate ?? Date() },
            set: { payload.targetDate = $0 }
        )
    }

    private var includesTargetTimeBinding: Binding<Bool> {
        Binding(
            get: { payload.includesTargetTime ?? false },
            set: { payload.includesTargetTime = $0 }
        )
    }

    private func defaultFormat(for platform: CreatorPlatform) -> String {
        switch platform {
        case .instagramReels: "Reel"
        case .tiktok: "Short video"
        case .youtubeShorts: "Short"
        case .youtubeVideo: "Video"
        }
    }
}
