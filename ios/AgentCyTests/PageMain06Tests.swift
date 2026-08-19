import SwiftUI
import XCTest
@testable import AgentCy

@MainActor
final class PageMain06Tests: XCTestCase {

    // DEFECT-MAIN-06-01: a thread bound to another workspace must never
    // survive a workspace switch as Cy's active conversation.
    func testWorkspaceSwitchDropsThreadBoundToAnotherWorkspace() {
        let profileID = UUID()
        let alpha = CreatorWorkspace(profileID: profileID, name: "@alpha", sortOrder: 0)
        let beta = CreatorWorkspace(profileID: profileID, name: "@beta", sortOrder: 1)

        let alphaThread = ConversationThread(title: "Alpha conversation")
        alphaThread.workspaceID = alpha.id
        let betaThread = ConversationThread(title: "Beta conversation")
        betaThread.workspaceID = beta.id

        let resolved = CyConversationScopePolicy.resolvedThread(
            current: alphaThread,
            threads: [alphaThread, betaThread],
            activeWorkspaceID: beta.id,
            workspaces: [alpha, beta]
        )

        XCTAssertEqual(resolved?.id, betaThread.id)
    }

    func testWorkspaceSwitchWithNoScopedThreadRequiresANewThread() {
        let profileID = UUID()
        let alpha = CreatorWorkspace(profileID: profileID, name: "@alpha", sortOrder: 0)
        let beta = CreatorWorkspace(profileID: profileID, name: "@beta", sortOrder: 1)

        let alphaThread = ConversationThread(title: "Alpha conversation")
        alphaThread.workspaceID = alpha.id

        let resolved = CyConversationScopePolicy.resolvedThread(
            current: alphaThread,
            threads: [alphaThread],
            activeWorkspaceID: beta.id,
            workspaces: [alpha, beta]
        )

        XCTAssertNil(resolved)
    }

    func testCurrentThreadInActiveScopeIsRetained() {
        let profileID = UUID()
        let alpha = CreatorWorkspace(profileID: profileID, name: "@alpha", sortOrder: 0)
        let beta = CreatorWorkspace(profileID: profileID, name: "@beta", sortOrder: 1)

        let current = ConversationThread(title: "Alpha conversation")
        current.workspaceID = alpha.id
        let older = ConversationThread(title: "Older alpha conversation")
        older.workspaceID = alpha.id

        let resolved = CyConversationScopePolicy.resolvedThread(
            current: current,
            threads: [current, older],
            activeWorkspaceID: alpha.id,
            workspaces: [alpha, beta]
        )

        XCTAssertEqual(resolved?.id, current.id)
    }

    // The bootstrap thread carries the default workspace's scope; it belongs
    // to the default workspace only, never to a later-added active workspace.
    func testLegacyNilWorkspaceThreadStaysWithDefaultWorkspaceOnly() {
        let profileID = UUID()
        let defaultWorkspace = CreatorWorkspace(profileID: profileID, name: "Default", sortOrder: 0)
        let beta = CreatorWorkspace(profileID: profileID, name: "@beta", sortOrder: 1)

        let legacyThread = ConversationThread(title: "Legacy conversation")
        legacyThread.workspaceID = nil

        let resolvedForBeta = CyConversationScopePolicy.resolvedThread(
            current: legacyThread,
            threads: [legacyThread],
            activeWorkspaceID: beta.id,
            workspaces: [defaultWorkspace, beta]
        )
        XCTAssertNil(resolvedForBeta)

        let resolvedForDefault = CyConversationScopePolicy.resolvedThread(
            current: legacyThread,
            threads: [legacyThread],
            activeWorkspaceID: defaultWorkspace.id,
            workspaces: [defaultWorkspace, beta]
        )
        XCTAssertEqual(resolvedForDefault?.id, legacyThread.id)
    }

    func testReResolutionSkipsArchivedBriefAndContextThreads() {
        let profileID = UUID()
        let alpha = CreatorWorkspace(profileID: profileID, name: "@alpha", sortOrder: 0)
        let beta = CreatorWorkspace(profileID: profileID, name: "@beta", sortOrder: 1)

        let stale = ConversationThread(title: "Alpha conversation")
        stale.workspaceID = alpha.id

        let archived = ConversationThread(title: "Archived")
        archived.workspaceID = beta.id
        archived.isArchived = true

        let briefBound = ConversationThread(briefID: UUID(), title: "Brief-bound")
        briefBound.workspaceID = beta.id

        let contextBound = ConversationThread(contextKind: .day, title: "Context-bound")
        contextBound.workspaceID = beta.id

        let open = ConversationThread(title: "Open beta conversation")
        open.workspaceID = beta.id

        let resolved = CyConversationScopePolicy.resolvedThread(
            current: stale,
            threads: [stale, archived, briefBound, contextBound, open],
            activeWorkspaceID: beta.id,
            workspaces: [alpha, beta]
        )

        XCTAssertEqual(resolved?.id, open.id)
    }

    // DEFECT-MAIN-06-02: at accessibility text sizes the inline rail truncates
    // the availability label to "Unav…"; the rail must stack so the status
    // stays readable for large-text readers.
    func testTopRailStacksAvailabilityAtAccessibilitySizes() {
        XCTAssertTrue(CyTopRailPresentationPolicy.stacksAvailability(for: .accessibility1))
        XCTAssertTrue(CyTopRailPresentationPolicy.stacksAvailability(for: .accessibility5))
        XCTAssertFalse(CyTopRailPresentationPolicy.stacksAvailability(for: .large))
        XCTAssertFalse(CyTopRailPresentationPolicy.stacksAvailability(for: .xxxLarge))
    }

    func testArchivedCurrentThreadIsNotRetainedEvenInScope() {
        let profileID = UUID()
        let alpha = CreatorWorkspace(profileID: profileID, name: "@alpha", sortOrder: 0)

        let current = ConversationThread(title: "Alpha conversation")
        current.workspaceID = alpha.id
        current.isArchived = true

        let resolved = CyConversationScopePolicy.resolvedThread(
            current: current,
            threads: [current],
            activeWorkspaceID: alpha.id,
            workspaces: [alpha]
        )

        XCTAssertNil(resolved)
    }
}
