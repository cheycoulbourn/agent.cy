import Foundation
import SwiftData

/// Database equivalent of WorkspaceScope.includes. Resolve ownership once per
/// query update, including the default workspace's legacy unowned records.
struct WorkspaceQueryScope: Equatable, Sendable {
    let workspaceID: UUID?
    let includesUnowned: Bool

    init(preferredID: UUID?, workspaces: [CreatorWorkspace]) {
        workspaceID = WorkspaceScope.activeWorkspaceID(preferredID: preferredID, workspaces: workspaces)
        includesUnowned = workspaceID == nil || WorkspaceScope.defaultWorkspace(in: workspaces)?.id == workspaceID
    }

    // Concrete model predicates keep SwiftData key paths tied to stored fields.
    var briefs: Predicate<CreativeBrief> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<CreativeBrief> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var outputs: Predicate<PlatformOutput> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<PlatformOutput> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var tasks: Predicate<CreatorTask> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<CreatorTask> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var pillars: Predicate<Pillar> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<Pillar> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var series: Predicate<ContentSeries> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<ContentSeries> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var episodeSlots: Predicate<SeriesEpisodeSlot> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<SeriesEpisodeSlot> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var focusTemplates: Predicate<DailyFocusTemplateEntry> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<DailyFocusTemplateEntry> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var focusOverrides: Predicate<DailyFocusOverride> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<DailyFocusOverride> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var brandPartners: Predicate<BrandPartner> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<BrandPartner> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    var threads: Predicate<ConversationThread> {
        let selectedID = workspaceID
        let includeLegacy = includesUnowned
        return #Predicate<ConversationThread> {
            ($0.workspaceID == selectedID && selectedID != nil) ||
                (includeLegacy && $0.workspaceID == nil)
        }
    }

    /// Saved references require established ownership, unlike legacy drafts.
    var savedPosts: Predicate<InspirationSource> {
        let selectedID = workspaceID
        return #Predicate<InspirationSource> {
            selectedID != nil && $0.workspaceID == selectedID
        }
    }
}
