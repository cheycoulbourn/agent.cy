import SwiftData
import SwiftUI

enum MCPReviewLayoutPolicy {
    static func usesSplitView(availableWidth: CGFloat) -> Bool {
        availableWidth >= 900
    }
}

struct MCPReviewRefreshableScrollView<Content: View>: View {
    let showsIndicators: Bool
    let refresh: () async -> Void
    private let content: Content

    init(
        showsIndicators: Bool = true,
        refresh: @escaping () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.refresh = refresh
        self.content = content()
    }

    var body: some View {
        ScrollView(showsIndicators: showsIndicators) {
            content
        }
        .refreshable {
            await refresh()
        }
    }
}

private struct CyPlateItem: Identifiable {
    let id: String
    let count: Int
    let title: String
}

private enum CyAvailabilityState: Equatable {
    case localBridge
    case hosted
    case unavailable

    var label: String {
        switch self {
        case .localBridge: "Local bridge"
        case .hosted: "Hosted Cy"
        case .unavailable: "Unavailable"
        }
    }

    var isAvailable: Bool {
        self != .unavailable
    }
}

enum CyChatActionPolicy {
    static func visibleSuggestions(
        _ suggestions: [ChatSuggestionWire],
        hasPostAction: Bool
    ) -> [ChatSuggestionWire] {
        guard hasPostAction else { return suggestions }
        return suggestions.filter { suggestion in
            !duplicatesPostAction(suggestion)
        }
    }

    private static func duplicatesPostAction(_ suggestion: ChatSuggestionWire) -> Bool {
        let text = "\(suggestion.label) \(suggestion.prompt)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return text.contains("create this post")
            || text.contains("create post")
            || text.contains("send to post")
            || text.contains("add to post")
    }
}

enum CyTopRailPresentationPolicy {
    /// At accessibility sizes the inline rail truncates the availability
    /// label; the status must stack under the kicker to stay readable.
    static func stacksAvailability(for size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}

enum CyConversationScopePolicy {
    /// Cy may only display and write into a conversation owned by the active
    /// workspace. Returns the current thread when it still qualifies, the
    /// newest open in-scope conversation otherwise, or nil when the caller
    /// must create a fresh thread for this workspace.
    static func resolvedThread(
        current: ConversationThread?,
        threads: [ConversationThread],
        activeWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> ConversationThread? {
        func qualifies(_ thread: ConversationThread) -> Bool {
            !thread.isArchived &&
                thread.briefID == nil &&
                thread.contextKind == .none &&
                WorkspaceScope.includes(
                    thread.workspaceID,
                    activeWorkspaceID: activeWorkspaceID,
                    workspaces: workspaces
                )
        }
        if let current, qualifies(current) { return current }
        return threads.first(where: qualifies)
    }
}

enum CyBriefReferencePolicy {
    static func explicitlyReferencedBrief(
        in message: String,
        briefs: [CreativeBrief]
    ) -> CreativeBrief? {
        let normalizedMessage = normalized(message)
        return briefs.first { brief in
            let title = brief.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3 else { return false }
            return normalizedMessage.contains(normalized(title))
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}

enum CyPostCreationPolicy {
    static func canCreate(
        actionKind: ChatProposedActionKindWire?,
        referencedBriefID: UUID?,
        alreadyCreated: Bool
    ) -> Bool {
        guard !alreadyCreated else { return false }
        switch actionKind {
        case .developSpark:
            return true
        case .reviseBrief:
            return referencedBriefID != nil
        default:
            return false
        }
    }

    static func shouldCopySource(actionKind: ChatProposedActionKindWire?) -> Bool {
        actionKind == .reviseBrief
    }
}

enum CyReferencedTitleCopy {
    static func quoted(_ rawTitle: String) -> String {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = "Untitled"
        }

        let quotePairs: [(opening: Character, closing: Character)] = [
            ("\"", "\""),
            ("“", "”"),
            ("‘", "’")
        ]
        if let first = title.first,
           let last = title.last,
           quotePairs.contains(where: { $0.opening == first && $0.closing == last }),
           title.count >= 2 {
            title.removeFirst()
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return "“\(title)”"
    }
}

enum CyPostSchedulingPolicy {
    static func nextSuggestedDate(
        assignedWeekdays: Set<PillarWeekday>,
        from date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard !assignedWeekdays.isEmpty else { return nil }
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start),
                  let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: candidate)),
                  assignedWeekdays.contains(weekday) else { continue }
            return candidate
        }
        return nil
    }
}

private struct CyPostDraftRoute: Identifiable {
    let brief: CreativeBrief
    let output: PlatformOutput
    let suggestedTargetDate: Date?

    var id: UUID { brief.id }
}

enum CyTaskAttentionPolicy {
    static func visibleOpenTasks(
        tasks: [CreatorTask],
        activeBriefIDs: Set<UUID>,
        outputs: [PlatformOutput],
        briefs: [CreativeBrief],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CreatorTask] {
        tasks.filter { task in
            guard !task.isCompleted,
                  !task.isSkipped,
                  task.parentTaskID == nil
            else { return false }

            let linkedOutput = task.platformOutputID.flatMap { outputID in
                outputs.first { $0.id == outputID }
            }
            if let linkedBriefID = task.briefID ?? linkedOutput?.briefID,
               !activeBriefIDs.contains(linkedBriefID) {
                return false
            }

            return TaskListVisibilityPolicy.includes(
                collection: TaskCollectionPolicy.collection(
                    briefID: task.briefID,
                    platformOutputID: task.platformOutputID
                ),
                focusTaskTemplateID: task.focusTaskTemplateID,
                recurrence: task.recurrence,
                recurrenceRootTaskID: task.recurrenceRootTaskID,
                targetDate: visibilityDate(for: task, outputs: outputs, briefs: briefs),
                now: now,
                calendar: calendar
            )
        }
    }

    static func isPastDue(
        _ task: CreatorTask,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !task.isCompleted, let targetDate = task.targetDate else { return false }
        return calendar.startOfDay(for: targetDate) < calendar.startOfDay(for: now)
    }

    private static func visibilityDate(
        for task: CreatorTask,
        outputs: [PlatformOutput],
        briefs: [CreativeBrief]
    ) -> Date? {
        if let targetDate = task.targetDate { return targetDate }
        if let dailyFocusDate = task.dailyFocusDate { return dailyFocusDate }
        if let outputID = task.platformOutputID,
           let targetDate = outputs.first(where: { $0.id == outputID })?.targetDate {
            return targetDate
        }
        if let briefID = task.briefID {
            if let targetDate = outputs
                .filter({ $0.briefID == briefID })
                .compactMap(\.targetDate)
                .min() {
                return targetDate
            }
            return briefs.first(where: { $0.id == briefID })?.agendaDate
        }
        return nil
    }
}

struct CyMarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case paragraph
        case bullet
        case numbered(marker: String)
        case quote
    }

    let id: Int
    let kind: Kind
    let text: String
}

enum CyMarkdownParser {
    static func blocks(from source: String) -> [CyMarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let readable = insertBreaksBeforeInlineLabels(in: normalized)
        let lines = readable.components(separatedBy: "\n")
        var result: [CyMarkdownBlock] = []
        var paragraphLines: [String] = []

        func append(_ kind: CyMarkdownBlock.Kind, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result.append(CyMarkdownBlock(id: result.count, kind: kind, text: trimmed))
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            append(.paragraph, paragraphLines.joined(separator: " "))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = heading(in: line) {
                flushParagraph()
                append(.heading(level: heading.level), heading.text)
            } else if let bullet = prefixedText(in: line, prefixes: ["- ", "* ", "• "]) {
                flushParagraph()
                append(.bullet, bullet)
            } else if let numbered = numberedText(in: line) ?? emphasizedNumberedText(in: line) {
                flushParagraph()
                append(.numbered(marker: numbered.marker), numbered.text)
            } else if line.hasPrefix("> ") {
                flushParagraph()
                append(.quote, String(line.dropFirst(2)))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()
        return result
    }

    private static func insertBreaksBeforeInlineLabels(in source: String) -> String {
        // Models occasionally return valid inline Markdown without paragraph
        // breaks. Promote bold labels ending in a colon into separate blocks so
        // a useful response never becomes one dense wall of text on iPhone.
        let pattern = #"(?<!^)(?<!\n)\s+(\*\*[^*\n]{1,80}:\*\*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "\n\n$1"
        )
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let markers = line.prefix { $0 == "#" }
        guard !markers.isEmpty, markers.count <= 3 else { return nil }
        let remainder = line.dropFirst(markers.count)
        guard remainder.first == " " else { return nil }
        return (markers.count, String(remainder.dropFirst()))
    }

    private static func prefixedText(in line: String, prefixes: [String]) -> String? {
        guard let prefix = prefixes.first(where: line.hasPrefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func numberedText(in line: String) -> (marker: String, text: String)? {
        guard let separator = line.firstIndex(of: ".") else { return nil }
        let marker = line[..<separator]
        guard !marker.isEmpty, marker.allSatisfy(\.isNumber) else { return nil }
        let textStart = line.index(after: separator)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }
        return (String(marker), String(line[line.index(after: textStart)...]))
    }

    private static func emphasizedNumberedText(in line: String) -> (marker: String, text: String)? {
        // Some providers occasionally put the opening bold marker before the
        // list number (`**2. Title`) instead of after it (`2. **Title**`).
        // Recover the list structure and move a matching closing marker back
        // around the title. If there is no match, prefer clean readable text
        // over exposing raw Markdown punctuation.
        guard line.hasPrefix("**"),
              let numbered = numberedText(in: String(line.dropFirst(2))) else {
            return nil
        }

        var text = numbered.text
        if !text.hasPrefix("**"), text.contains("**") {
            text = "**" + text
        } else if !text.contains("**") {
            text = emphasizeLeadingQuotedTitle(in: text)
        }
        return (numbered.marker, CyInlineMarkdownSanitizer.readable(text))
    }

    private static func emphasizeLeadingQuotedTitle(in text: String) -> String {
        guard let openingQuote = text.first,
              openingQuote == "\"" || openingQuote == "“" else {
            return text
        }
        let closingQuote: Character = openingQuote == "“" ? "”" : "\""
        let afterOpening = text.index(after: text.startIndex)
        guard let quoteEnd = text[afterOpening...].firstIndex(of: closingQuote) else {
            return text
        }

        var titleEnd = text.index(after: quoteEnd)
        var scan = titleEnd
        while scan < text.endIndex, text[scan].isWhitespace {
            scan = text.index(after: scan)
        }
        if scan < text.endIndex,
           text[scan] == "(",
           let closingParenthesis = text[scan...].firstIndex(of: ")") {
            titleEnd = text.index(after: closingParenthesis)
        }

        return "**\(text[..<titleEnd])**\(text[titleEnd...])"
    }
}

enum CyInlineMarkdownSanitizer {
    static func readable(_ source: String) -> String {
        var result = source
        for delimiter in ["**", "__"] where occurrenceCount(of: delimiter, in: result) % 2 != 0 {
            result = result.replacingOccurrences(of: delimiter, with: "")
        }
        return result
    }

    private static func occurrenceCount(of delimiter: String, in source: String) -> Int {
        source.components(separatedBy: delimiter).count - 1
    }
}

struct CyMarkdownResponseView: View {
    let source: String

    private var blocks: [CyMarkdownBlock] {
        CyMarkdownParser.blocks(from: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: CyMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.text))
                .font(level == 1 ? .agentTitle : .agentHeadline)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, block.id == 0 ? 0 : AgentSpacing.x1)
        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Circle()
                    .fill(Color.cyAccent)  // design-review-allow: accent-mark -- markdown bullet
                    .frame(width: 5, height: 5)
                Text(inlineMarkdown(block.text))
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .numbered(let marker):
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                Text(marker)
                    .font(.agentMetadata)
                    .foregroundStyle(Color.cyAccent)
                    .frame(width: 18, alignment: .leading)
                Text(inlineMarkdown(block.text))
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .quote:
            Text(inlineMarkdown(block.text))
                .font(.agentBody)
                .italic()
                .foregroundStyle(Color.agentSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, AgentSpacing.x3)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.cyAccent)  // design-review-allow: accent-mark -- blockquote rule
                        .frame(width: 2)
                }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let readableText = CyInlineMarkdownSanitizer.readable(text)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: readableText, options: options))
            ?? AttributedString(readableText)
    }
}

private enum BatchReviewDecision: String, Identifiable {
    case approveAll
    case deny

    var id: String { rawValue }
}

struct AskCyView: View {
    private let bottomClearance: CGFloat
    private let showsCloseButton: Bool
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \ConversationThread.updatedAt, order: .reverse) private var allThreads: [ConversationThread]
    @Query(sort: \ConversationMessage.createdAt) private var allMessages: [ConversationMessage]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query private var allOutputs: [PlatformOutput]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var allPillars: [Pillar]
    @Query private var allSeriesRecords: [ContentSeries]
    @Query private var profiles: [CreatorProfile]
    @Query private var subscriptions: [SubscriptionState]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var prompt = ""
    @State private var thread: ConversationThread?
    @State private var isSending = false
    @State private var pendingReviews: [MCPBridgeChangeRequest] = []
    @State private var reviewingRequest: MCPBridgeChangeRequest?
    @State private var reviewingSeries: MCPSeriesReviewBundle?
    @State private var isSelectingReviews = false
    @State private var selectedReviewIDs: Set<UUID> = []
    @State private var isBatchReviewing = false
    @State private var batchDecisionToConfirm: BatchReviewDecision?
    @State private var reviewError: String?
    @State private var hasLoadedPendingReviews = false
    @State private var isRefreshingReviews = false
    @State private var lastReviewRefreshAt: Date?
    @State private var desktopSelectedReviewID: UUID?
    @State private var showsDesktopReviewWorkspace = false
    @State private var showReviewCompletion = false
    @State private var showConversationHistory = false
    @State private var showProUpsell = false
    @State private var showProAccessDetails = false
    @State private var cyAvailability: CyAvailabilityState = .unavailable
    @State private var sendTask: Task<Void, Never>?
    @State private var activeSendID: UUID?
    @State private var activeSendThreadID: UUID?
    @State private var sentToPostMessageIDs: Set<UUID> = []
    @State private var postDraftToOpen: CyPostDraftRoute?
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

    init(bottomClearance: CGFloat = 0, showsCloseButton: Bool = false) {
        self.bottomClearance = bottomClearance
        self.showsCloseButton = showsCloseButton
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

    private func refreshPendingReviews() async {
        guard !isRefreshingReviews else { return }
        guard MCPBridgePreferences.isConnected else {
            clearPendingReviews()
            return
        }
        isRefreshingReviews = true
        defer { isRefreshingReviews = false }
        let requests = await Task.detached(priority: .utility) {
            try? await MCPBridgeService.refreshPendingRequests()
        }.value
        guard let requests else { return }
        applyPendingReviews(requests)
        lastReviewRefreshAt = Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            topRail
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, AgentSpacing.x4)

            // The header and the content below it were separated only by a
            // fill change, which reads as one surface. A hairline gives the
            // two sections a real boundary.
            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            if showReviewCompletion {
                reviewCompletionContent
            } else if showsDesktopReviewWorkspace {
                // Rendered inside Cy's own surface: stacking a second sheet on
                // top of this modal left no clear way back out.
                MCPDesktopReviewView(
                    requests: pendingReviews,
                    onClose: { showsDesktopReviewWorkspace = false },
                    onQueueChanged: { Task { await refreshPendingReviews() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pendingReviews.isEmpty {
                conversationContent
            } else {
                // Desktop keeps the conversation. A queue used to replace the
                // whole feed, so Cy was unusable until every item was cleared.
                // Reviews are opened deliberately from the banner instead.
                #if targetEnvironment(macCatalyst)
                conversationContent
                #else
                pendingReviewContent
                #endif
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                #if targetEnvironment(macCatalyst)
                if !pendingReviews.isEmpty, !showReviewCompletion, !showsDesktopReviewWorkspace {
                    desktopReviewBanner
                }
                #endif
                if showsConversation { composer }
            }
        }

        .toolbar(.hidden, for: .navigationBar)
        #if targetEnvironment(macCatalyst)
        // Only the review workspace needs the wider footprint; chat keeps the
        // standard one so the extra width does not read as empty space.
        //
        // Same shape as the creation hub: the content lays out once at its
        // target size with animation suppressed, and the cheap outer frame
        // animates over it. Animating the content frame relayouts the whole
        // sidebar and detail pane every frame, which is what stuttered.
        .frame(width: desktopModalWidth, height: DesktopLayoutPolicy.workspaceModalMetrics.height)
        .transaction { $0.animation = nil }
        .frame(width: desktopModalWidth, height: DesktopLayoutPolicy.workspaceModalMetrics.height)
        .animation(
            reduceMotion ? nil : AgentModalResize.animation,
            value: showsDesktopReviewWorkspace
        )
        #endif
        .task {
            loadThread()
            await refreshPendingReviews()
            if let pending = appModel.pendingCyPrompt {
                prompt = pending
                appModel.pendingCyPrompt = nil
                composerIsFocused = true
            }
            await appModel.refreshAccess(context: context)
        }
        .task {
            while !Task.isCancelled {
                // The bridge folder can live in iCloud Drive; reading it on
                // the main thread stutters an in-flight scroll, so the poll
                // fetches off-main and only applies results that changed.
                if MCPBridgePreferences.isConnected {
                    await refreshPendingReviews()
                } else {
                    clearPendingReviews()
                }
                await reloadCyAvailability()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onChange(of: appModel.pendingCyPrompt) { _, pending in
            guard let pending else { return }
            prompt = pending
            appModel.pendingCyPrompt = nil
            composerIsFocused = true
        }
        .onChange(of: appModel.activeWorkspaceID) { _, _ in
            // Conversations stay with their account: a workspace switch must
            // re-resolve the thread or the transcript, sends, and the
            // workspace-scoped history contradict each other.
            loadThread()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCyMCPInboxChanged)) { _ in
            Task { await refreshPendingReviews() }
        }
        .sheet(item: $reviewingRequest) { request in
            NavigationStack {
                MCPBridgeRequestReviewView(
                    request: request,
                    approve: { reviewedRequest in
                        try MCPBridgeService.approve(reviewedRequest, context: context)
                        Task { await refreshPendingReviews() }
                    },
                    decline: { declinedRequest, note in
                        try MCPBridgeService.reject(declinedRequest, decisionNote: note)
                        Task { await refreshPendingReviews() }
                    }
                )
            }
            .presentationDetents([.large])
            .agentSheetDragIndicator()
        }
        .sheet(item: $reviewingSeries) { bundle in
            NavigationStack {
                MCPSeriesReviewFlow(bundle: bundle) {
                    Task { await refreshPendingReviews() }
                }
            }
            .presentationDetents([.large])
            .agentSheetDragIndicator()
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
            .agentSheetDragIndicator()
        }
        .sheet(item: $postDraftToOpen) { route in
            NavigationStack {
                ResumablePostEditorView(
                    brief: route.brief,
                    output: route.output,
                    suggestedTargetDate: route.suggestedTargetDate,
                    contextLabel: "New post",
                    bottomActionClearance: AgentSpacing.x3,
                    onSpark: {}
                )
                .navigationTitle("New post")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        AgentToolbarIconButton(title: "Close", icon: .close) {
                            postDraftToOpen = nil
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .agentScreen()
                .agentKeyboardDismissal()
            }
            .presentationDetents([.large])
            .agentSheetDragIndicator()
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
                        AgentToolbarIconButton(title: "Close", icon: .close) { showProUpsell = false }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .navigationDestination(isPresented: $showProAccessDetails) {
                    AccessSettingsView()
                }
                .agentScreen()
            }
            .presentationDetents([.large])
            .agentSheetDragIndicator()
        }
        .alert("agent.cy", isPresented: Binding(
            get: { reviewError != nil },
            set: { if !$0 { reviewError = nil } }
        )) {
            Button("Close", role: .cancel) { reviewError = nil }
        } message: {
            Text(reviewError ?? "")
        }
        .alert(item: $batchDecisionToConfirm) { decision in
            switch decision {
            case .approveAll:
                Alert(
                    title: Text(batchApproveConfirmationTitle),
                    message: Text("Every selected proposal will be added to your app."),
                    primaryButton: .default(Text("Approve all"), action: approveSelectedReviews),
                    secondaryButton: .cancel(Text("Cancel"))
                )
            case .deny:
                Alert(
                    title: Text(batchDenyConfirmationTitle),
                    message: Text("Series episodes move to Needs revision with their context intact. Other proposals are declined without changing your app."),
                    primaryButton: .destructive(Text(batchDenyActionTitle), action: denySelectedReviews),
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
        }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private var conversationContent: some View {
        ScrollViewReader { proxy in
            MCPReviewRefreshableScrollView(refresh: refreshPendingReviews) {
                // A plain VStack: conversations are small, and LazyVStack's
                // deferred row measurement makes the bottom-edge bounce snap
                // when content height re-estimates mid-rubber-band.
                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    if cyAvailability == .unavailable {
                        cyUnavailableCard
                    }
                    if messages.isEmpty {
                        opening
                    } else {
                        conversationDivider
                        ForEach(messages) { message in
                            messageView(message)
                                .id(message.id)
                        }
                        // The reply lands in the thread that sent it; after a
                        // workspace switch mid-send the indicator must not
                        // promise a reply to an unrelated thread.
                        if isSending, activeSendThreadID == thread?.id { typingIndicator }
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
            .onChange(of: messages.last?.id) { previousID, _ in
                // Loading the thread on open hydrates its existing messages;
                // only follow messages that arrive after the conversation is
                // already on screen, or the sheet jerks mid-presentation.
                guard previousID != nil else { return }
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
        }
    }

    private var pendingReviewContent: some View {
        GeometryReader { proxy in
            #if targetEnvironment(macCatalyst)
            if MCPReviewLayoutPolicy.usesSplitView(availableWidth: proxy.size.width) {
                desktopPendingReviewContent
            } else {
                compactPendingReviewContent
            }
            #else
            compactPendingReviewContent
            #endif
        }
    }

    private var compactPendingReviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAnimatedLogo(size: 20, strokeWidth: 1.7)
                    MetaLabel("CY · FOR REVIEW")
                        .foregroundStyle(Color.cyAccent)
                }
                Text("I have something\nfor you.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                Text("Review, edit, approve, or deny each proposal. A dated post is created and scheduled with one approval.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, AgentSpacing.x6)
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.bottom, AgentSpacing.x6)

            pendingReviewHeader
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.bottom, AgentSpacing.x2)

            if isSelectingReviews {
                batchReviewActions
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.bottom, AgentSpacing.x3)
            }

            MCPReviewRefreshableScrollView(
                showsIndicators: false,
                refresh: refreshPendingReviews
            ) {
                LazyVStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    ForEach(pendingReviews) { request in
                        HStack(alignment: .top, spacing: AgentSpacing.x2) {
                            if isSelectingReviews {
                                Button {
                                    toggleReviewSelection(request.id)
                                } label: {
                                    AgentIconView(selectedReviewIDs.contains(request.id)
                                        ? .checkCircle
                                        : .radioEmpty)
                                        .font(.agentInter(size: 20, weight: .medium, relativeTo: .body))
                                        .foregroundStyle(selectedReviewIDs.contains(request.id)
                                            ? Color.cyAccent
                                            : Color.agentSecondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    selectedReviewIDs.contains(request.id)
                                        ? "Deselect \(request.summary)"
                                        : "Select \(request.summary)"
                                )
                            }

                            Button {
                                if let bundle = seriesBundle(for: request) {
                                    reviewingSeries = bundle
                                } else {
                                    reviewingRequest = request
                                }
                            } label: {
                                reviewCard(for: request)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the complete proposal for approval")
                            .disabled(isBatchReviewing)
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.bottom, bottomClearance + AgentSpacing.x8)
            }
        }
    }

    #if targetEnvironment(macCatalyst)
    private var desktopPendingReviewContent: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x2) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel("REVIEW INBOX")
                            .foregroundStyle(Color.cyAccent)
                        Text("\(pendingReviews.count) waiting")
                            .font(.agentTitle)
                    }
                    Spacer()
                    AgentToolbarIconButton(
                        title: isRefreshingReviews ? "Checking for proposals" : "Refresh",
                        icon: .refresh,
                        isEnabled: !isRefreshingReviews
                    ) {
                        Task { await refreshPendingReviews() }
                    }
                    // Declarative spin: the four-second poll flips
                    // isRefreshingReviews around every check, and restarting a
                    // repeatForever animation on each flip kept the render loop
                    // busy the whole time Cy was open.
                    .rotationEffect(.degrees(isRefreshingReviews ? 360 : 0))
                    .animation(
                        isRefreshingReviews
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .none,
                        value: isRefreshingReviews
                    )
                }
                .padding(.horizontal, AgentSpacing.x5)
                .padding(.vertical, AgentSpacing.x4)

                if let lastReviewRefreshAt {
                    Text("Last checked \(lastReviewRefreshAt, style: .relative)")
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                        .padding(.horizontal, AgentSpacing.x5)
                        .padding(.bottom, AgentSpacing.x3)
                }

                Rectangle().fill(Color.agentBorder).frame(height: 1)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        ForEach(pendingReviews) { request in
                            Button {
                                desktopSelectedReviewID = request.id
                            } label: {
                                reviewCard(for: request)
                                    .padding(AgentSpacing.x1)
                                    .background(
                                        desktopSelectedReviewID == request.id
                                            ? Color.cyAccent.opacity(0.08)
                                            : Color.clear,
                                        in: .rect(cornerRadius: AgentRadius.card)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AgentSpacing.x4)
                }
                .refreshable { await refreshPendingReviews() }
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            .background(Color.agentSurface)

            Rectangle().fill(Color.agentBorder).frame(width: 1)

            desktopReviewDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.agentCanvas)
        }
        .onAppear {
            if desktopSelectedReviewID == nil {
                desktopSelectedReviewID = pendingReviews.first?.id
            }
        }
        .onChange(of: pendingReviews.map(\.id)) { _, ids in
            if desktopSelectedReviewID.map({ !ids.contains($0) }) != false {
                desktopSelectedReviewID = ids.first
            }
        }
    }

    @ViewBuilder
    private var desktopReviewDetail: some View {
        if let request = pendingReviews.first(where: { $0.id == desktopSelectedReviewID }) {
            if let bundle = seriesBundle(for: request) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                        MetaLabel("SERIES PACKAGE")
                            .foregroundStyle(Color.cyAccent)
                        Text(bundle.series.summary)
                            .font(.agentDisplay)
                        Text("\(bundle.episodes.count) episodes are attached. Open the package to inspect, edit, approve, or deny every item.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                        Button("Review series and episodes") {
                            reviewingSeries = bundle
                        }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))

                        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                            SectionRuleHeader(title: "Episodes")
                            ForEach(bundle.episodes) { episode in
                                Button {
                                    reviewingRequest = episode
                                } label: {
                                    reviewCard(for: episode)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(AgentSpacing.x8)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                NavigationStack {
                    MCPBridgeRequestReviewView(
                        request: request,
                        showsCloseButton: false,
                        approve: { reviewedRequest in
                            try MCPBridgeService.approve(reviewedRequest, context: context)
                            Task { await refreshPendingReviews() }
                        },
                        decline: { declinedRequest, note in
                            try MCPBridgeService.reject(declinedRequest, decisionNote: note)
                            Task { await refreshPendingReviews() }
                        }
                    )
                }
            }
        } else {
            VStack(spacing: AgentSpacing.x3) {
                AgentIconView(.branch, size: 24)
                    .foregroundStyle(Color.agentSecondary)
                Text("Choose a proposal")
                    .font(.agentTitle)
                Text("Select an item in the review inbox to inspect it here.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif

    private var pendingReviewHeader: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x2) {
            MetaLabel("Waiting for review")
            Spacer()
            if pendingReviews.count > 1 {
                Button(action: toggleReviewSelectionMode) {
                    HStack(spacing: AgentSpacing.x2) {
                        Text(isSelectingReviews ? "DONE" : "SELECT")
                            .font(.paperInter(size: 11, weight: .bold, relativeTo: .caption))
                            .tracking(0.35)
                        Rectangle()
                            .fill(Color.agentBorder)
                            .frame(width: 1, height: 12)
                        Text("\(pendingReviews.count)")
                            .font(.agentMetadata)
                    }
                    .foregroundStyle(isSelectingReviews ? Color.cyAccent : Color.agentSecondary)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelectingReviews ? "Finish selecting proposals" : "Select proposals")
            } else {
                Text("\(pendingReviews.count)")
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        // Padding comes before the overlay so the rule sits at the bottom of the
        // padded frame, giving the label room instead of hugging it.
        .padding(.bottom, AgentSpacing.x3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.agentBorder).frame(height: 1)
        }
    }

    private var batchReviewActions: some View {
        HStack(spacing: AgentSpacing.x2) {
            Button(allReviewsSelected ? "Clear all" : "Select all", action: toggleAllReviewSelections)
                .buttonStyle(ReviewBatchButtonStyle())
                .disabled(isBatchReviewing)

            Button("Approve") {
                if allReviewsSelected {
                    batchDecisionToConfirm = .approveAll
                } else {
                    approveSelectedReviews()
                }
            }
            .buttonStyle(ReviewBatchButtonStyle(foreground: .cyAccent))
            .disabled(isBatchReviewing || selectedReviewIDs.isEmpty)

            Button("Deny", role: .destructive) {
                batchDecisionToConfirm = .deny
            }
            .buttonStyle(ReviewBatchButtonStyle(foreground: .agentDestructive))
            .disabled(isBatchReviewing || selectedReviewIDs.isEmpty)
        }
        .frame(maxWidth: .infinity)
    }

    private var reviewCompletionContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x2) {
                    CyAnimatedLogo(size: 20, strokeWidth: 1.7)
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
            .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .padding(.top, AgentSpacing.x6)
        .padding(.bottom, bottomClearance + AgentSpacing.x8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topRail: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x1) {
            Group {
                if CyTopRailPresentationPolicy.stacksAvailability(for: dynamicTypeSize) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel("Agent (Cy)")
                        availabilityStatus
                    }
                } else {
                    HStack(spacing: AgentSpacing.x2) {
                        MetaLabel("Agent (Cy)")

                        Text("|")
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentBorder)
                            .accessibilityHidden(true)

                        availabilityStatus
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Agent Cy, \(cyAvailability.label)")

            Menu {
                Button("New conversation") { startNewThread() }
                Button("Conversation history") { showConversationHistory = true }
                if thread != nil { Button("Move to history") { archiveThread() } }
            } label: {
                AgentIconView(.more)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 44, height: 44)
            }

            #if targetEnvironment(macCatalyst)
            if showsCloseButton {
                AgentToolbarIconButton(
                    title: "Close Cy",
                    icon: .close,
                    action: dismiss.callAsFunction
                )
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Press Escape to close")
            } else {
                ProfileSettingsButton(
                    identity: activeIdentity,
                    action: { appModel.presentedSheet = .settings }
                )
            }
            #else
            ProfileSettingsButton(
                identity: activeIdentity,
                action: { appModel.presentedSheet = .settings }
            )
            #endif
        }
        .frame(minHeight: 44)
    }

    private var availabilityStatus: some View {
        HStack(spacing: AgentSpacing.x2) {
            Circle()
                .fill(cyAvailability.isAvailable ? Color.agentSuccess : Color.agentDestructive)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(cyAvailability.label)
                .font(.agentMetadata)
                .foregroundStyle(cyAvailability.isAvailable ? Color.agentSuccess : Color.agentDestructive)
                .lineLimit(CyTopRailPresentationPolicy.stacksAvailability(for: dynamicTypeSize) ? 2 : 1)
        }
    }

    @MainActor
    private func reloadCyAvailability() async {
        let resolved = await resolveCyAvailability()
        // An unchanged poll result must not touch @State: the write re-runs
        // this body, which kills any in-flight scroll bounce mid-animation.
        if cyAvailability != resolved {
            cyAvailability = resolved
        }
    }

    private func resolveCyAvailability() async -> CyAvailabilityState {
        if await LocalCyAIClient.shared.isAvailable() {
            return .localBridge
        }

        guard AccessPolicy.allows(.askCy, state: subscriptions.first) else {
            return .unavailable
        }

        do {
            guard let identity = try await DeviceOnlyKeychainCredentialStore.shared.load(),
                  !identity.credential.isEmpty,
                  identity.credentialExpiresAt.map({ $0 > Date() }) ?? true else {
                return .unavailable
            }
            return .hosted
        } catch {
            return .unavailable
        }
    }

    private var cyUnavailableCard: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("CY IS OFFLINE")
                .foregroundStyle(Color.agentDestructive)

            Text("Connect Claude or Codex on your Mac, or turn on hosted Agent Cy.")
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appModel.presentedSheet = .settings
            } label: {
                HStack(spacing: AgentSpacing.x2) {
                    Text("Open settings")
                        .font(.agentAddAction)
                    Spacer()
                    AgentIconView(.forward)
                }
                .foregroundStyle(Color.agentText)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: 14))
        .agentSurfaceChrome(cornerRadius: 14)
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            CyAnimatedLogo()
                .frame(width: 44, height: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hey \(activeIdentity.greetingName),")
                    .font(.agentDisplayLead)
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
                                        .font(.agentMetadata)
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
                        AgentIconView(.forward, size: 11)
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
                                .multilineTextAlignment(.center)
                        }
                        .buttonStyle(AgentQuietAccentButtonStyle(isFullWidth: false))
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
                AgentIconView(.forward, size: 11)
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .agentSurfaceChrome(cornerRadius: AgentRadius.panel, borderColor: Color.agentBorder)
        }
        .buttonStyle(AgentPressButtonStyle())
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

            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func assistantMessage(
        _ message: ConversationMessage,
        label: String,
        showsAsterisk: Bool
    ) -> some View {
        let hasPostAction = canSendResponseToPost(message)
        let visibleSuggestions = CyChatActionPolicy.visibleSuggestions(
            message.chatSuggestions,
            hasPostAction: hasPostAction
        )
        return VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(spacing: AgentSpacing.x2) {
                if showsAsterisk {
                    CyAsterisk(color: .cyAccent, size: 14, strokeWidth: 1.4)
                }
                MetaLabel(label)
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

            if !visibleSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    MetaLabel("Continue with")
                        .foregroundStyle(Color.agentSecondary)
                        .padding(.horizontal, AgentSpacing.x3)
                        .padding(.vertical, AgentSpacing.x2)

                    ForEach(Array(visibleSuggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            prompt = suggestion.prompt
                            composerIsFocused = true
                        } label: {
                            HStack(spacing: AgentSpacing.x2) {
                                Text(suggestion.label)
                                    .font(.agentBody.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                AgentIconView(.external, size: 11)
                            }
                            .foregroundStyle(Color.agentText)
                            .padding(.horizontal, AgentSpacing.x3)
                            .frame(minHeight: 48)
                            .contentShape(.rect)
                        }
                        .buttonStyle(AgentPressButtonStyle())
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.agentHairline)
                                    .frame(height: 1)
                                    .padding(.horizontal, AgentSpacing.x3)
                            }
                        }
                    }
                }
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel, borderColor: Color.agentBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let taskProposal = proposedTask(for: message) {
                let wasAdded = taskWasAdded(from: message)
                Button {
                    addProposedTask(taskProposal, from: message)
                } label: {
                    HStack(alignment: .center, spacing: AgentSpacing.x3) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                            MetaLabel(wasAdded ? "TASK ADDED" : "PROPOSED TASK")
                                .foregroundStyle(Color.cyAccent)
                            Text(taskProposal.title)
                                .font(.agentBody.weight(.semibold))
                                .foregroundStyle(Color.agentText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(taskProposal.kind.title)
                                .font(.agentMetadata)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        AgentQuietAccentIconLabel(
                            icon: wasAdded ? .check : .add,
                            isActive: !wasAdded,
                            diameter: 36,
                            glyph: 14
                        )
                    }
                    .padding(.horizontal, AgentSpacing.x3)
                    .padding(.vertical, AgentSpacing.x3)
                    .background(Color.cyAccent.opacity(0.07), in: .rect(cornerRadius: AgentRadius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.panel)
                            .stroke(Color.cyAccent.opacity(0.32), lineWidth: 0.75)
                    }
                }
                .buttonStyle(.plain)
                .disabled(wasAdded)
                .accessibilityLabel(wasAdded ? "Task added" : "Add task, \(taskProposal.title)")
                .accessibilityHint("Adds Cy's proposed task to your task list")
            }

            if hasPostAction {
                Button {
                    sendResponseToPost(message)
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        CyAsterisk(color: .cyAccentText, size: 13, strokeWidth: 1.4)
                        Text(sentToPostMessageIDs.contains(message.id) ? "Post created" : "Create this post")
                        Spacer(minLength: AgentSpacing.x2)
                        AgentIconView(sentToPostMessageIDs.contains(message.id) ? .check : .arrowRight)
                            .font(.agentInter(size: 12, weight: .semibold, relativeTo: .caption))
                    }
                }
                .buttonStyle(AgentQuietAccentButtonStyle())
                .disabled(sentToPostMessageIDs.contains(message.id))
                .accessibilityHint("Creates a new post from Cy's response and opens its editor")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plainText(from markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let rendered = (try? AttributedString(markdown: markdown, options: options))
            ?? AttributedString(markdown)
        return String(rendered.characters)
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
            ZStack(alignment: .bottomTrailing) {
                Group {
                    #if targetEnvironment(macCatalyst)
                    TextField("", text: $prompt)
                        .submitLabel(.send)
                        .onSubmit(send)
                    #else
                    TextField("", text: $prompt, axis: .vertical)
                        .lineLimit(1...4)
                    #endif
                }
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .focused($composerIsFocused)
                .accessibilityLabel("Ask Cy anything")
                .accessibilityIdentifier("cy-composer-input")
                .padding(.leading, AgentSpacing.x4)
                .padding(.trailing, AgentSpacing.x12 + AgentSpacing.x3)
                .padding(.vertical, AgentSpacing.x2)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                .overlay(alignment: .leading) {
                    if prompt.isEmpty {
                        Text(composerPlaceholder)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .padding(.leading, AgentSpacing.x4)
                            .allowsHitTesting(false)
                    }
                }

                composerActionButton
                    .padding(6)
            }
            .frame(minHeight: 56)
            .glassEffect(.clear, in: .rect(cornerRadius: AgentRadius.floating))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.floating)
                    .stroke(Color.agentPureWhite.opacity(0.14), lineWidth: 0.5)
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
        return Button {
            if isSending {
                stopSending()
            } else {
                send()
            }
        } label: {
            AgentQuietAccentIconLabel(
                icon: isSending ? .stop : .arrowUp,
                isActive: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(isSending ? "Stop Cy" : "Send")
#if targetEnvironment(macCatalyst)
        .help(isSending ? "Stop Cy" : "Send (Return)")
#endif
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var activeWorkspace: CreatorWorkspace? {
        guard let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) else { return nil }
        return workspaces.first { $0.id == activeID && !$0.isArchived }
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
        let visibleOpenTasks = CyTaskAttentionPolicy.visibleOpenTasks(
            tasks: tasks,
            activeBriefIDs: activeBriefIDs,
            outputs: outputs,
            briefs: activeBriefs,
            now: now
        )
        let pastDueTaskCount = visibleOpenTasks.filter {
            CyTaskAttentionPolicy.isPastDue($0, now: now)
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
        if pastDueTaskCount > 0 {
            items.append(CyPlateItem(
                id: "past-due-tasks",
                count: pastDueTaskCount,
                title: pastDueTaskCount == 1 ? "Task is past due" : "Tasks are past due"
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
            let referencedTitle = CyReferencedTitleCopy.quoted(lateBrief.title)
            return (
                "The date for \(referencedTitle) has passed. Want to choose a new one together?",
                "Help me reschedule \(referencedTitle)."
            )
        }

        let openTask = CyTaskAttentionPolicy.visibleOpenTasks(
            tasks: tasks,
            activeBriefIDs: activeBriefIDs,
            outputs: outputs,
            briefs: activeBriefs,
            now: now
        )
            .filter { CyTaskAttentionPolicy.isPastDue($0, now: now) }
            .sorted(by: {
                return ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
            })
            .first
        if let openTask {
            let referencedTitle = CyReferencedTitleCopy.quoted(openTask.title)
            return (
                "\(referencedTitle) is past due. Want to decide what to do with it?",
                "Help me complete, move, or skip \(referencedTitle)."
            )
        }

        if let idea = activeBriefs.first(where: { brief in
            (brief.status == .spark || brief.status == .developing) &&
                !outputs.contains { $0.briefID == brief.id && $0.targetDate != nil }
        }) {
            return (
                "Let’s expand on some of these ideas",
                "Keep shaping \(CyReferencedTitleCopy.quoted(idea.title))."
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
        currentDraft.map { "Keep shaping \(CyReferencedTitleCopy.quoted($0.title))" } ?? CreatorProfile.defaultCyQuickPrompts[0]
    }

    private var starterPrompts: [String] {
        activeWorkspace?.customCyQuickPrompts ?? [
            primaryStarter,
            CreatorProfile.defaultCyQuickPrompts[1]
        ]
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
        let platformFallback = request.payload.platform
            .flatMap(CreatorPlatform.init(rawValue:))?.shortTitle
            ?? output?.platform.shortTitle
            ?? "Post"
        let platform = MCPReviewPillarPresentation.metadata(
            type: request.type,
            fallback: platformFallback
        )
        let date = request.payload.targetDate ?? output?.targetDate
        let metadata = date.map {
            "\(platform) · \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        } ?? platform

        return AgentPostCard(
            title: nonempty(request.payload.title) ?? brief?.title ?? request.summary,
            pillar: MCPReviewPillarPresentation.label(
                type: request.type,
                pillarName: pillar?.name ?? "Unfiled"
            ),
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
        // An episode carries no pillar of its own; it inherits the one on its
        // series. Without this the review cards all read "Unfiled".
        let seriesPillarID = request.payload.seriesId.flatMap { id in
            allSeriesRecords.first(where: { $0.id == id })?.pillarID
        }
        let pillarID = request.payload.pillarId ?? brief?.pillarID ?? seriesPillarID
        return pillarID.flatMap { id in activePillars.first { $0.id == id } }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private var selectedReviews: [MCPBridgeChangeRequest] {
        pendingReviews.filter { selectedReviewIDs.contains($0.id) }
    }

    private var allReviewsSelected: Bool {
        pendingReviews.count > 1 && selectedReviewIDs == Set(pendingReviews.map(\.id))
    }

    private var batchApproveConfirmationTitle: String {
        "Approve all \(selectedReviews.count) submissions?"
    }

    private var batchDenyActionTitle: String {
        allReviewsSelected ? "Deny all" : "Deny selected"
    }

    private var batchDenyConfirmationTitle: String {
        let count = selectedReviews.count
        return allReviewsSelected
            ? "Deny all \(count) submissions?"
            : "Deny \(count) submission\(count == 1 ? "" : "s")?"
    }

    private func toggleReviewSelectionMode() {
        isSelectingReviews.toggle()
        if !isSelectingReviews {
            selectedReviewIDs.removeAll()
        }
    }

    private func toggleAllReviewSelections() {
        if allReviewsSelected {
            selectedReviewIDs.removeAll()
        } else {
            selectedReviewIDs = Set(pendingReviews.map(\.id))
        }
    }

    private func toggleReviewSelection(_ id: UUID) {
        if selectedReviewIDs.contains(id) {
            selectedReviewIDs.remove(id)
        } else {
            selectedReviewIDs.insert(id)
        }
    }

    private func approveSelectedReviews() {
        let requests = selectedReviews
        guard !requests.isEmpty else { return }
        isBatchReviewing = true
        defer {
            isBatchReviewing = false
            reloadPendingReviews()
        }

        do {
            try MCPBridgeService.approve(requests, context: context)
            selectedReviewIDs.subtract(requests.map(\.id))
        } catch {
            reviewError = CreatorFacingErrorMapper.presentation(
                for: error,
                action: "The selected proposals"
            ).message
        }
    }

    private func denySelectedReviews() {
        let requests = selectedReviews
        guard !requests.isEmpty else { return }
        isBatchReviewing = true
        defer {
            isBatchReviewing = false
            reloadPendingReviews()
        }

        do {
            for request in requests {
                try MCPBridgeService.reject(request)
                selectedReviewIDs.remove(request.id)
            }
        } catch {
            reviewError = CreatorFacingErrorMapper.presentation(
                for: error,
                action: "The selected proposals"
            ).message
        }
    }

    private func seriesBundle(for request: MCPBridgeChangeRequest) -> MCPSeriesReviewBundle? {
        guard ["createSeries", "createSeriesEpisode"].contains(request.type),
              let seriesID = request.payload.seriesId,
              let seriesRequest = pendingReviews.first(where: {
                  $0.type == "createSeries" && $0.payload.seriesId == seriesID
              }) else {
            return nil
        }
        let episodes = pendingReviews.filter {
            $0.type == "createSeriesEpisode" && $0.payload.seriesId == seriesID
        }
        return MCPSeriesReviewBundle(series: seriesRequest, episodes: episodes)
    }

    private func reloadPendingReviews() {
        guard MCPBridgePreferences.isConnected else {
            clearPendingReviews()
            return
        }
        guard let requests = try? MCPBridgeService.pendingRequests() else {
            return
        }
        applyPendingReviews(requests)
    }

    private func clearPendingReviews() {
        pendingReviews = []
        isSelectingReviews = false
        selectedReviewIDs.removeAll()
        showReviewCompletion = false
        hasLoadedPendingReviews = true
    }

    private func applyPendingReviews(_ requests: [MCPBridgeChangeRequest]) {
        // An unchanged poll result must not touch @State: every write re-runs
        // this body mid-scroll, and the poll fires every four seconds.
        if hasLoadedPendingReviews, requests == pendingReviews { return }
        if hasLoadedPendingReviews, !pendingReviews.isEmpty, requests.isEmpty {
            showReviewCompletion = true
        } else if !requests.isEmpty {
            showReviewCompletion = false
        }
        pendingReviews = requests
        selectedReviewIDs.formIntersection(Set(requests.map(\.id)))
        if requests.count <= 1 {
            isSelectingReviews = false
            selectedReviewIDs.removeAll()
        }
        hasLoadedPendingReviews = true
    }

    #if targetEnvironment(macCatalyst)
    private var desktopModalWidth: CGFloat {
        showsDesktopReviewWorkspace
            ? DesktopLayoutPolicy.cyReviewModalMetrics.width
            : DesktopLayoutPolicy.workspaceModalMetrics.width
    }
    #endif

    private var showsConversation: Bool {
        #if targetEnvironment(macCatalyst)
        // The queue never takes the composer away on desktop, but the review
        // workspace is a full surface of its own.
        return !showReviewCompletion && !showsDesktopReviewWorkspace
        #else
        return pendingReviews.isEmpty && !showReviewCompletion
        #endif
    }

    /// Opt-in entry to the review workspace. Replaces the old behaviour where a
    /// pending queue forced the review surface open over the conversation.
    private var desktopReviewBanner: some View {
        HStack(spacing: AgentSpacing.x3) {
            Text(pendingReviews.count == 1
                 ? "1 proposal is waiting for review"
                 : "\(pendingReviews.count) proposals are waiting for review")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
            Spacer()
            Button("Open review") { showsDesktopReviewWorkspace = true }
                .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
        }
        .padding(.horizontal, AgentSpacing.x5)
        .padding(.vertical, AgentSpacing.x3)
        .background(Color.agentSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.agentHairline).frame(height: 1)
        }
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
        if let resolved = CyConversationScopePolicy.resolvedThread(
            current: thread,
            threads: threads,
            activeWorkspaceID: appModel.activeWorkspaceID,
            workspaces: workspaces
        ) {
            thread = resolved
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
        // The Catalyst composer's Return submit bypasses the send/stop
        // button, so a repeat submit must not race the in-flight task.
        guard !isSending else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // A send must never write into another workspace's conversation,
        // even if a switch happened since the thread was resolved.
        loadThread()
        guard let thread else { return }
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
        activeSendThreadID = thread.id
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
            activeSendThreadID = nil
            sendTask = nil
            isSending = false
        }
    }

    private func stopSending() {
        activeSendID = nil
        activeSendThreadID = nil
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    private func referencedBrief(for message: String) -> CreativeBrief? {
        CyBriefReferencePolicy.explicitlyReferencedBrief(in: message, briefs: briefs)
    }

    private func canSendResponseToPost(_ message: ConversationMessage) -> Bool {
        CyPostCreationPolicy.canCreate(
            actionKind: message.proposedActionKind,
            referencedBriefID: message.referencedBriefID,
            alreadyCreated: sentToPostMessageIDs.contains(message.id)
        )
    }

    private func proposedTask(for message: ConversationMessage) -> ChatTaskProposalWire? {
        guard message.proposedActionKind == .createTask else { return nil }
        return message.proposedAction?.task
    }

    private func taskWasAdded(from message: ConversationMessage) -> Bool {
        tasks.contains { $0.sourceConversationMessageID == message.id }
    }

    private func addProposedTask(
        _ proposal: ChatTaskProposalWire,
        from message: ConversationMessage
    ) {
        guard !taskWasAdded(from: message) else { return }
        let linkedBrief: CreativeBrief?
        if let postID = proposal.postId {
            guard let post = briefs.first(where: { $0.id == postID && $0.status != .archived }) else {
                appModel.notice = .error("That post could not be found. The task was not added.")
                return
            }
            linkedBrief = post
        } else {
            linkedBrief = nil
        }
        let linkedOutput = linkedBrief.flatMap { brief in
            outputs.first { $0.briefID == brief.id }
        }
        guard let task = appModel.createTask(
            title: proposal.title,
            kind: proposal.kind,
            lane: linkedBrief == nil ? .pillar : .production,
            priority: proposal.priority,
            targetDate: proposal.targetDate,
            includesTargetTime: proposal.includesTargetTime,
            briefID: linkedBrief?.id,
            pillarID: linkedBrief?.pillarID,
            platformOutputID: linkedOutput?.id,
            sourceConversationMessageID: message.id,
            context: context
        ) else { return }
        task.notes = message.proposedActionSummary
        try? context.save()
        appModel.notice = .info("Task added.")
    }

    private func sendResponseToPost(_ message: ConversationMessage) {
        let shouldCopySource = CyPostCreationPolicy.shouldCopySource(
            actionKind: message.proposedActionKind
        )
        let sourceBrief = shouldCopySource
            ? message.referencedBriefID.flatMap { sourceBriefID in
                briefs.first(where: { $0.id == sourceBriefID })
            }
            : nil
        if shouldCopySource, sourceBrief == nil {
            appModel.notice = .error("The source post could not be found.")
            return
        }

        let cleanResponse = plainText(from: message.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanResponse.isEmpty else { return }
        let pillarID = sourceBrief?.pillarID
        guard let draft = appModel.createPostDraftFromCyResponse(
            cleanResponse,
            suggestedTitle: sourceBrief?.title,
            sourceBrief: sourceBrief,
            pillarID: pillarID,
            context: context
        ) else { return }

        let assignedWeekdays = pillarID
            .flatMap { id in activePillars.first(where: { $0.id == id }) }
            .map { $0.resolvedWeekdays(in: activePillars) }
            ?? []
        let suggestedTargetDate = CyPostSchedulingPolicy.nextSuggestedDate(
            assignedWeekdays: assignedWeekdays
        )

        sentToPostMessageIDs.insert(message.id)
        postDraftToOpen = CyPostDraftRoute(
            brief: draft.brief,
            output: draft.output,
            suggestedTargetDate: suggestedTargetDate
        )
    }

}

private struct ReviewBatchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var foreground: Color = .agentText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSubtext.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color.agentCanvas, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
            .opacity(isEnabled
                ? AgentButtonPressFeedback.value(
                    resting: 1.0,
                    pressed: 0.7,
                    isPressed: configuration.isPressed
                )
                : 0.38)
            .frame(minHeight: 44)
            .contentShape(.rect)
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
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
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
                AgentIconView(.forward, size: 11)
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
                .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
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
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        AgentIconLabel(title: "Delete conversation", icon: .trash)
                    }
                } label: {
                    AgentToolbarIconLabel(icon: .more)
                }
                .accessibilityLabel("Conversation options")
            }
            .sharedBackgroundVisibility(.hidden)
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
