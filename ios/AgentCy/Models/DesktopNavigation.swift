import Foundation

enum DesktopNavigationDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case plan
    case feed
    case tasks
    case ideaBank
    case savedPosts
    case pillars
    case cy

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .plan: "Agenda"
        case .feed: "Feed"
        case .tasks: "Tasks"
        case .ideaBank: "Idea Bank"
        case .savedPosts: "Saved Posts"
        case .pillars: "Pillars"
        case .cy: "Cy"
        }
    }

    var icon: AgentIcon {
        switch self {
        case .home: .home
        case .plan: .calendar
        case .feed: .instagramCamera
        case .tasks: .tasks
        case .ideaBank: .ideas
        case .savedPosts: .link
        case .pillars: .pillars
        case .cy: .idea
        }
    }

    var appTab: AppTab? {
        switch self {
        case .home: .home
        case .plan: .today
        case .feed: nil
        case .tasks: .tasks
        case .ideaBank: .ideaBank
        case .savedPosts: nil
        case .pillars: .pillars
        case .cy: .cy
        }
    }
}

struct DesktopNavigationSection: Equatable, Sendable {
    let title: String
    let destinations: [DesktopNavigationDestination]
}

enum DesktopNavigationPolicy {
    static let defaultDestination: DesktopNavigationDestination = .plan

    static let sidebarSections: [DesktopNavigationSection] = [
        DesktopNavigationSection(
            title: "Plan",
            destinations: [.home, .plan, .feed, .tasks, .pillars]
        ),
        DesktopNavigationSection(
            title: "Library",
            destinations: [.ideaBank, .savedPosts]
        ),
    ]

    static func destination(for tab: AppTab) -> DesktopNavigationDestination {
        switch tab {
        case .home: .home
        case .today: .plan
        case .tasks: .tasks
        case .pillars: .pillars
        case .ideaBank: .ideaBank
        case .cy: .cy
        }
    }
}

struct DesktopLayoutMetrics: Equatable, Sendable {
    let leadingSidebarWidth: CGFloat
    let utilitySidebarWidth: CGFloat
    let contentMaximumWidth: CGFloat
    let contentHorizontalPadding: CGFloat

    var showsUtilitySidebar: Bool { utilitySidebarWidth > 0 }
}

struct DesktopSheetMetrics: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
}

enum DesktopLayoutPolicy {
    static let utilityRailBreakpoint: CGFloat = 1_280

    static func metrics(forWindowWidth width: CGFloat) -> DesktopLayoutMetrics {
        let showsUtilityRail = width >= utilityRailBreakpoint
        return DesktopLayoutMetrics(
            leadingSidebarWidth: showsUtilityRail ? 220 : 208,
            utilitySidebarWidth: showsUtilityRail ? 344 : 0,
            contentMaximumWidth: showsUtilityRail ? 1_040 : 960,
            contentHorizontalPadding: showsUtilityRail ? 32 : 24
        )
    }

    static func sheetMetrics(for sheet: AppSheet) -> DesktopSheetMetrics {
        switch sheet {
        case .creationHub:
            DesktopSheetMetrics(width: 780, height: 720)
        case .quickCapture:
            DesktopSheetMetrics(width: 760, height: 760)
        case .askCy:
            DesktopSheetMetrics(width: 900, height: 860)
        case .settings:
            DesktopSheetMetrics(width: 840, height: 780)
        }
    }
}

/// A compact, descending type scale for the desktop chrome and Control Center.
/// Page-level display typography remains shared with iPhone; these roles keep
/// the narrower desktop rails optically balanced without one-off font sizes.
enum DesktopTypographyScale {
    // One notch larger across the chrome: Catalyst's scaled-iPad rendering
    // shows these at ~77%, so the previous 13pt navigation read at ~10pt.
    static let utilityTitle: CGFloat = 17
    static let quickAction: CGFloat = 16
    static let navigation: CGFloat = 15
    static let utilityBody: CGFloat = 14
    static let utilityAction: CGFloat = 13
    static let utilityMetadata: CGFloat = 12
}

enum DesktopHomeWidgetColumnPolicy {
    static let columnCount = 1
}

enum DesktopUtilityWidget: String, CaseIterable, Identifiable, Sendable {
    case tasks
    case upcomingPosts
    case ideas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .upcomingPosts: "Upcoming Posts"
        case .ideas: "Idea Bank"
        }
    }

    var icon: AgentIcon {
        switch self {
        case .tasks: .tasks
        case .upcomingPosts: .calendar
        case .ideas: .idea
        }
    }
}

enum DesktopUtilityWidgetVisibilityPolicy {
    static func hiddenWidgets(from storageValue: String) -> Set<DesktopUtilityWidget> {
        Set(storageValue.split(separator: ",").compactMap { DesktopUtilityWidget(rawValue: String($0)) })
    }

    static func storageValue(for hiddenWidgets: Set<DesktopUtilityWidget>) -> String {
        DesktopUtilityWidget.allCases
            .filter(hiddenWidgets.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

enum DesktopUtilityWidgetOrderPolicy {
    static func orderedWidgets(from storageValue: String) -> [DesktopUtilityWidget] {
        let stored = storageValue
            .split(separator: ",")
            .compactMap { DesktopUtilityWidget(rawValue: String($0)) }
        let uniqueStored = stored.reduce(into: [DesktopUtilityWidget]()) { result, widget in
            guard !result.contains(widget) else { return }
            result.append(widget)
        }
        return uniqueStored + DesktopUtilityWidget.allCases.filter { !uniqueStored.contains($0) }
    }

    static func storageValue(for widgets: [DesktopUtilityWidget]) -> String {
        widgets.map(\.rawValue).joined(separator: ",")
    }
}

enum DesktopUtilityWidgetContentPolicy {
    static let ideaPreviewLimit = 3
}

enum DesktopUtilityTaskPolicy {
    static func includes(
        _ task: CreatorTask,
        archivedBriefIDs: Set<UUID>,
        activeWorkspaceID: UUID?,
        workspaces: [CreatorWorkspace],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let dueDate = task.targetDate,
              calendar.isDate(dueDate, inSameDayAs: referenceDate) else {
            return false
        }
        return task.parentTaskID == nil &&
            !task.isCompleted &&
            !task.isSkipped &&
            task.briefID.map { !archivedBriefIDs.contains($0) } != false &&
            WorkspaceScope.includes(
                task.workspaceID,
                activeWorkspaceID: activeWorkspaceID,
                workspaces: workspaces
            )
    }
}
