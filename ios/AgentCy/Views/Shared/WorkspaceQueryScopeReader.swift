import SwiftData
import SwiftUI

/// Reconfigures child queries when selection, default ordering, or workspace
/// availability changes. No identity reset: drafts and navigation stay alive.
struct WorkspaceQueryScopeReader<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @ViewBuilder let content: (WorkspaceQueryScope) -> Content

    var body: some View {
        content(WorkspaceQueryScope(preferredID: appModel.activeWorkspaceID, workspaces: workspaces))
    }
}
