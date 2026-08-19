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

enum DesktopQuickAddPlacement: Equatable, Sendable {
    case leadingSidebar
    case utilitySidebar
}

enum DesktopLayoutPolicy {
    static let utilityRailBreakpoint: CGFloat = 1_280
    /// The roomy Cy post-development sheet is the canonical footprint for
    /// desktop Quick Actions and Settings. Keeping one size prevents modal
    /// flows from collapsing back into narrow phone-shaped cards.
    static let workspaceModalMetrics = DesktopSheetMetrics(width: 900, height: 860)

    static func metrics(forWindowWidth width: CGFloat) -> DesktopLayoutMetrics {
        let showsUtilityRail = width >= utilityRailBreakpoint
        return DesktopLayoutMetrics(
            leadingSidebarWidth: showsUtilityRail ? 220 : 208,
            utilitySidebarWidth: showsUtilityRail ? 344 : 0,
            contentMaximumWidth: showsUtilityRail ? 1_040 : 960,
            contentHorizontalPadding: showsUtilityRail ? 32 : 24
        )
    }

    /// The review workspace is a sidebar of post cards beside a detail pane.
    /// At the standard 900pt the cards truncate their pillar names, so the Cy
    /// sheet widens to this only while the workspace is open — chat keeps the
    /// standard footprint, where the extra width just reads as empty.
    static let cyReviewModalMetrics = DesktopSheetMetrics(width: 1_180, height: 860)

    /// Cy applies its own frame so it can resize between chat and review.
    static func sizesItself(_ sheet: AppSheet) -> Bool { sheet == .askCy }

    static func sheetMetrics(for _: AppSheet) -> DesktopSheetMetrics {
        workspaceModalMetrics
    }

    /// The Quick Add menu is a compact choice card sized to its five options;
    /// only the embedded capture flows need the canonical workspace footprint.
    static let creationHubMenuMetrics = DesktopSheetMetrics(width: 600, height: 560)

    static func creationHubMetrics(stage: DesktopCreationHubStage) -> DesktopSheetMetrics {
        switch stage {
        case .menu: creationHubMenuMetrics
        case .capture: workspaceModalMetrics
        }
    }

    static func quickAddPlacement(forWindowWidth width: CGFloat) -> DesktopQuickAddPlacement {
        width >= utilityRailBreakpoint ? .utilitySidebar : .leadingSidebar
    }
}

/// Which face the Quick Add overlay is showing: the choice menu, or one of
/// the embedded capture flows that replace it inside the same card.
enum DesktopCreationHubStage: Equatable, Sendable {
    case menu
    case capture
}

enum DesktopShellMotionPolicy {
    static func animatesUtilityRail(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

enum DesktopShellMCPReviewPolicy {
    static func shouldPresent(
        requestIDs: Set<UUID>,
        presentedRequestIDs: Set<UUID>,
        hasGlobalPresentation: Bool,
        hasLocalPresentation: Bool
    ) -> Bool {
        !hasGlobalPresentation &&
            !hasLocalPresentation &&
            !requestIDs.isEmpty &&
            !requestIDs.subtracting(presentedRequestIDs).isEmpty
    }
}

enum DesktopShellWorkspacePolicy {
    static func acceptsMCPResult(
        requestedWorkspaceID: UUID?,
        activeWorkspaceID: UUID?
    ) -> Bool {
        requestedWorkspaceID == activeWorkspaceID
    }
}

enum DesktopUtilityOutputPolicy {
    static func includes(
        briefStatus: BriefStatus,
        outputIsInActiveWorkspace: Bool,
        briefIsInActiveWorkspace: Bool
    ) -> Bool {
        briefStatus != .archived &&
            outputIsInActiveWorkspace &&
            briefIsInActiveWorkspace
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
    case pillarUsage
    case needsNewDate
    case cyNoticed
    case weekAtAGlance
    case consistency
    case recentlyPosted
    case draftsInProgress
    case brandCabinet
    case weeklyFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .upcomingPosts: "Upcoming Posts"
        case .ideas: "Idea Bank"
        case .pillarUsage: "Pillar Usage"
        case .needsNewDate: "Needs a New Date"
        case .cyNoticed: "Cy Noticed"
        case .weekAtAGlance: "Week at a Glance"
        case .consistency: "Consistency"
        case .recentlyPosted: "Recently Posted"
        case .draftsInProgress: "Drafts in Progress"
        case .brandCabinet: "Brand Cabinet"
        case .weeklyFocus: "Weekly Focus"
        }
    }

    var icon: AgentIcon? {
        switch self {
        case .tasks: .tasks
        case .upcomingPosts: .calendar
        case .ideas: .idea
        case .pillarUsage: .pillars
        case .needsNewDate: .calendar
        case .cyNoticed: nil
        case .weekAtAGlance: .calendar
        case .consistency: .checkCircle
        case .recentlyPosted: .verified
        case .draftsInProgress: .pencil
        case .brandCabinet: .business
        case .weeklyFocus: .sliders
        }
    }

    static let optionalWidgets: Set<DesktopUtilityWidget> = [
        .pillarUsage,
        .needsNewDate,
        .weekAtAGlance,
        .consistency,
        .recentlyPosted,
        .draftsInProgress,
        .brandCabinet,
        .weeklyFocus,
    ]
}

enum DesktopUtilityWidgetVisibilityPolicy {
    static func hiddenWidgets(from storageValue: String) -> Set<DesktopUtilityWidget> {
        let isCurrentFormat = storageValue.hasPrefix("v2:")
        let value = isCurrentFormat ? String(storageValue.dropFirst(3)) : storageValue
        let stored = Set(value.split(separator: ",").compactMap { DesktopUtilityWidget(rawValue: String($0)) })
        return isCurrentFormat ? stored : stored.union(DesktopUtilityWidget.optionalWidgets)
    }

    static func storageValue(for hiddenWidgets: Set<DesktopUtilityWidget>) -> String {
        "v2:" + DesktopUtilityWidget.allCases
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
    static let taskPreviewLimit = 3
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
