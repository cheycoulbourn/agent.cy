import SwiftData
import SwiftUI

private enum NotificationActivityFilter: String, CaseIterable, Identifiable {
    case all
    case unread

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum NotificationActivityScopePolicy {
    /// Activity is the app's one cross-account surface: iOS delivers
    /// notifications regardless of which account is open, so the sheet
    /// includes every non-archived account's records. Records owned by a
    /// deleted workspace stay hidden.
    static func includes(
        recordWorkspaceID: UUID?,
        activeWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> Bool {
        guard let recordWorkspaceID else { return true }
        return workspaces.contains { $0.id == recordWorkspaceID && !$0.isArchived }
    }

    /// The account name shown on rows that belong to a non-active account;
    /// nil for the active account and for legacy unowned records.
    static func accountLabel(
        recordWorkspaceID: UUID?,
        activeWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> String? {
        guard let recordWorkspaceID,
              let resolvedActive = WorkspaceScope.activeWorkspaceID(
                  preferredID: activeWorkspaceID,
                  workspaces: workspaces
              ),
              recordWorkspaceID != resolvedActive,
              let workspace = workspaces.first(where: { $0.id == recordWorkspaceID && !$0.isArchived })
        else { return nil }
        return workspace.name
    }
}

enum NotificationActivityContentFilter: String, CaseIterable, Identifiable {
    case all
    case posts
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All activity"
        case .posts: "Posts"
        case .tasks: "Tasks"
        }
    }

    func includes(_ record: AgentActivityRecord) -> Bool {
        switch self {
        case .all:
            true
        case .posts:
            record.taskID == nil && (record.briefID != nil || record.outputID != nil)
        case .tasks:
            record.taskID != nil
        }
    }
}

struct NotificationActivityCenterView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \AgentActivityRecord.availableAt, order: .reverse) private var allRecords: [AgentActivityRecord]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var filter: NotificationActivityFilter = .all
    @State private var contentFilter: NotificationActivityContentFilter = .all
#if targetEnvironment(macCatalyst)
    @State private var showsDesktopContentFilter = false
#endif

    let preferredWorkspaceID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    filterRail

                    if displayedRecords.isEmpty {
                        emptyState
                    } else {
                        if !needsAttentionRecords.isEmpty {
                            activitySection(title: "Needs attention", records: needsAttentionRecords)
                        }
                        if !earlierRecords.isEmpty {
                            activitySection(title: "Earlier", records: earlierRecords)
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x12)
            }
            .scrollIndicators(.hidden)
            .background(Color.agentCanvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        ZStack {
            MetaLabel("Activity")

            HStack {
                AgentToolbarIconButton(title: "Close Activity", icon: .close) {
                    dismiss()
                }

                Spacer()

                HStack(spacing: AgentSpacing.x1) {
#if targetEnvironment(macCatalyst)
                    Button {
                        showsDesktopContentFilter.toggle()
                    } label: {
                        AgentToolbarIconLabel(icon: .filter)
                            // An engaged content filter silently narrows every
                            // tab; the dot keeps that state visible.
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(Color.cyAccent)  // design-review-allow: accent-mark -- filter-engaged dot
                                    .frame(width: 7, height: 7)
                                    .opacity(contentFilter == .all ? 0 : 1)
                            }
                    }
                    .buttonStyle(AgentPressButtonStyle())
                    .popover(isPresented: $showsDesktopContentFilter, arrowEdge: .top) {
                        desktopContentFilterPopover
                            .frame(width: 230)
                            .padding(AgentSpacing.x2)
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(Color.agentSurface)
                    }
                    .accessibilityLabel("Filter activity")
                    .accessibilityValue(contentFilter.title)
                    .accessibilityHint("Filters activity by posts or tasks")
#else
                    Menu {
                        Picker("Activity type", selection: $contentFilter) {
                            ForEach(NotificationActivityContentFilter.allCases) { option in
                                Text(option.title)
                                    .tag(option)
                            }
                        }
                    } label: {
                        AgentToolbarIconLabel(icon: .filter)
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(Color.cyAccent)  // design-review-allow: accent-mark -- filter-engaged dot
                                    .frame(width: 7, height: 7)
                                    .opacity(contentFilter == .all ? 0 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter activity")
                    .accessibilityValue(contentFilter.title)
                    .accessibilityHint("Filters activity by posts or tasks")
#endif

                    Menu {
                        Button("Mark all read", action: markAllRead)
                            .disabled(unreadRecords.isEmpty)
                        Button("Clear all", action: clearAll)
                            .disabled(contentFilteredRecords.isEmpty)
                    } label: {
                        AgentToolbarIconLabel(icon: .more)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Activity options")
                }
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .frame(minHeight: 64)
        .background(Color.agentCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)
        }
    }

#if targetEnvironment(macCatalyst)
    private var desktopContentFilterPopover: some View {
        VStack(spacing: AgentSpacing.x1) {
            desktopContentFilterRow(.all, icon: .filter)
            desktopContentFilterRow(.posts, icon: .calendar)
            desktopContentFilterRow(.tasks, icon: .tasks)
        }
    }

    private func desktopContentFilterRow(
        _ option: NotificationActivityContentFilter,
        icon: AgentIcon
    ) -> some View {
        AgentDesktopMenuRow(
            title: option.title,
            icon: icon,
            isSelected: contentFilter == option
        ) {
            contentFilter = option
            showsDesktopContentFilter = false
        }
    }
#endif

    private var filterRail: some View {
        HStack(spacing: AgentSpacing.x6) {
            ForEach(NotificationActivityFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        Text(option.title)
                        Text("\(option == .all ? contentFilteredRecords.count : unreadRecords.count)")
                            .foregroundStyle(Color.agentSecondary)
                            .monospacedDigit()
                    }
                    .font(.agentSubtext.weight(filter == option ? .semibold : .medium))
                    .foregroundStyle(Color.agentText)
                    .padding(.bottom, AgentSpacing.x2)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(filter == option ? Color.agentText : Color.clear)
                            .frame(height: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }

            Spacer()
        }
    }

    private func activitySection(
        title: String,
        records: [AgentActivityRecord]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MetaLabel(title)
                .padding(.bottom, AgentSpacing.x2)

            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                activityRow(record)

                if index < records.count - 1 {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(height: 1)
                        .padding(.leading, AgentSpacing.x5)
                }
            }
        }
    }

    private func activityRow(_ record: AgentActivityRecord) -> some View {
        Button {
            open(record)
        } label: {
            HStack(alignment: .top, spacing: AgentSpacing.x3) {
                Circle()
                    .fill(record.readAt == nil ? Color.cyAccent : Color.clear)  // design-review-allow: accent-mark -- unread dot
                    .frame(width: 7, height: 7)
                    .padding(.top, 7)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                        // One title size for every notification: unread and
                        // category may change the weight, never the size.
                        Text(record.title)
                            .font(.agentBody.weight(record.readAt == nil ? .semibold : .medium))
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(activityTime(record.availableAt))
                            .font(.agentMetadata.monospacedDigit())
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(1)
                    }

                    if !record.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(record.body)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: AgentSpacing.x2) {
                        if let account = NotificationActivityScopePolicy.accountLabel(
                            recordWorkspaceID: record.workspaceID,
                            activeWorkspaceID: activeWorkspaceID,
                            workspaces: workspaces
                        ) {
                            Text(account)
                                .font(.agentMetadata.weight(.semibold))
                                .foregroundStyle(Color.cyAccent)
                                .lineLimit(1)
                        }
                        Text(record.reason)
                            .font(.agentMetadata)
                            .foregroundStyle(record.resolvedAt == nil ? Color.agentSecondary : Color.agentText)
                        if record.resolvedAt != nil {
                            Text("Resolved")
                                .font(.agentMetadata.weight(.semibold))
                                .foregroundStyle(Color.agentSecondary)
                        }
                        Spacer(minLength: AgentSpacing.x2)
                        AgentIconView(.forward, size: 12)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
            }
            .padding(.vertical, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .contextMenu {
            Button(record.readAt == nil ? "Mark read" : "Mark unread") {
                toggleRead(record)
            }
            Button("Archive", role: .destructive) {
                archive(record)
            }
        }
        .accessibilityLabel("\(record.readAt == nil ? "Unread. " : "")\(record.title). \(record.body)")
        .accessibilityHint("Opens the related work")
    }

    private var emptyState: some View {
        VStack(spacing: AgentSpacing.x3) {
            AgentIconView(.bell, size: 22)
                .foregroundStyle(Color.agentSecondary)
            Text(emptyStateTitle)
                .font(.agentTitle)
            Text(emptyStateMessage)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.horizontal, AgentSpacing.x8)
    }

    private var activeWorkspaceID: UUID? {
        WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        )
    }

    private var visibleRecords: [AgentActivityRecord] {
        let now = Date()
        return allRecords.filter { record in
            NotificationActivityScopePolicy.includes(
                recordWorkspaceID: record.workspaceID,
                activeWorkspaceID: activeWorkspaceID,
                workspaces: workspaces
            ) && AgentActivityPresentationPolicy.isVisible(
                availableAt: record.availableAt,
                archivedAt: record.archivedAt,
                clearedAt: record.clearedAt,
                now: now
            )
        }
    }

    private var unreadRecords: [AgentActivityRecord] {
        contentFilteredRecords.filter { $0.readAt == nil }
    }

    private var displayedRecords: [AgentActivityRecord] {
        filter == .unread ? unreadRecords : contentFilteredRecords
    }

    private var contentFilteredRecords: [AgentActivityRecord] {
        visibleRecords.filter(contentFilter.includes)
    }

    private var emptyStateTitle: String {
        if filter == .unread { return "Nothing unread" }
        switch contentFilter {
        case .all: return "You’re caught up"
        case .posts: return "No post activity"
        case .tasks: return "No task activity"
        }
    }

    private var emptyStateMessage: String {
        if filter == .unread {
            return "New reminders will remain in Activity after you clear the iPhone alert."
        }
        switch contentFilter {
        case .all:
            return "Tasks, late work, and posting reminders that need attention will stay here."
        case .posts:
            return "Overdue work dates and posts that still need to be marked posted will appear here."
        case .tasks:
            return "Tasks that need your attention will appear here."
        }
    }

    private var needsAttentionRecords: [AgentActivityRecord] {
        displayedRecords.filter {
            AgentActivityPresentationPolicy.needsAttention(
                kind: $0.kind,
                readAt: $0.readAt,
                resolvedAt: $0.resolvedAt
            )
        }
        .sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.availableAt > $1.availableAt
        }
    }

    private var earlierRecords: [AgentActivityRecord] {
        let attentionIDs = Set(needsAttentionRecords.map(\.id))
        return displayedRecords.filter { !attentionIDs.contains($0.id) }
            .sorted { $0.availableAt > $1.availableAt }
    }

    private func open(_ record: AgentActivityRecord) {
        do {
            try AgentActivityCenterService.markRead(record, context: context)
            // A record from another account routes into that account: switch
            // first so the destination exists in the shell it lands in.
            if let recordWorkspaceID = record.workspaceID,
               recordWorkspaceID != WorkspaceScope.activeWorkspaceID(
                   preferredID: activeWorkspaceID,
                   workspaces: workspaces
               ),
               workspaces.contains(where: { $0.id == recordWorkspaceID && !$0.isArchived }) {
                appModel.switchWorkspace(to: recordWorkspaceID, context: context)
            }
            let route = record.route
            dismiss()
            Task { @MainActor in
                await Task.yield()
                AgentNotificationRouteStore.put(route)
            }
        } catch {
            appModel.notice = .error("That activity could not be opened. Try again.")
        }
    }

    private func toggleRead(_ record: AgentActivityRecord) {
        do {
            if record.readAt == nil {
                try AgentActivityCenterService.markRead(record, context: context)
            } else {
                try AgentActivityCenterService.markUnread(record, context: context)
            }
        } catch {
            appModel.notice = .error("That activity could not be updated.")
        }
    }

    private func markAllRead() {
        do {
            try AgentActivityCenterService.markAllRead(contentFilteredRecords, context: context)
        } catch {
            appModel.notice = .error("Activity could not be marked read.")
        }
    }

    private func archive(_ record: AgentActivityRecord) {
        do {
            try AgentActivityCenterService.archive(record, context: context)
        } catch {
            appModel.notice = .error("That activity could not be archived.")
        }
    }

    private func clearAll() {
        do {
            try AgentActivityCenterService.clearAll(contentFilteredRecords, context: context)
        } catch {
            appModel.notice = .error("Activity could not be cleared.")
        }
    }

    private func activityTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
