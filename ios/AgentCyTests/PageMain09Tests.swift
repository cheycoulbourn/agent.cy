import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageMain09Tests: XCTestCase {

    // Field report 2026-08-19 (verified against the creator's live store):
    // post notifications delivered for one account were invisible in the
    // Activity sheet while another account was active — counted nowhere the
    // user could reach. Activity is the one cross-account surface: it must
    // include every account's records, and rows from a non-active account
    // must carry that account's name.
    func testActivityScopeIncludesEveryAccountsRecords() {
        let profileID = UUID()
        let cheyWithLove = CreatorWorkspace(profileID: profileID, name: "@fromcheywithlove", sortOrder: 0)
        let skipMatrix = CreatorWorkspace(profileID: profileID, name: "SkipMatrix", sortOrder: 1)
        let workspaces = [cheyWithLove, skipMatrix]

        XCTAssertTrue(NotificationActivityScopePolicy.includes(
            recordWorkspaceID: cheyWithLove.id,
            activeWorkspaceID: skipMatrix.id,
            workspaces: workspaces
        ), "Another account's record must stay visible in Activity")
        XCTAssertTrue(NotificationActivityScopePolicy.includes(
            recordWorkspaceID: nil,
            activeWorkspaceID: skipMatrix.id,
            workspaces: workspaces
        ), "Legacy unowned records stay visible")
        XCTAssertFalse(NotificationActivityScopePolicy.includes(
            recordWorkspaceID: UUID(),
            activeWorkspaceID: skipMatrix.id,
            workspaces: workspaces
        ), "Records of deleted workspaces must not ghost into Activity")
    }

    func testActivityRowLabelsOnlyForeignAccounts() {
        let profileID = UUID()
        let active = CreatorWorkspace(profileID: profileID, name: "SkipMatrix", sortOrder: 0)
        let other = CreatorWorkspace(profileID: profileID, name: "@fromcheywithlove", sortOrder: 1)
        let workspaces = [active, other]

        XCTAssertNil(NotificationActivityScopePolicy.accountLabel(
            recordWorkspaceID: active.id,
            activeWorkspaceID: active.id,
            workspaces: workspaces
        ), "Active-account rows need no label")
        XCTAssertEqual(NotificationActivityScopePolicy.accountLabel(
            recordWorkspaceID: other.id,
            activeWorkspaceID: active.id,
            workspaces: workspaces
        ), "@fromcheywithlove", "Foreign rows carry their account name")
        XCTAssertNil(NotificationActivityScopePolicy.accountLabel(
            recordWorkspaceID: nil,
            activeWorkspaceID: active.id,
            workspaces: workspaces
        ), "Legacy unowned records stay unlabeled")
    }

    // Creator report 2026-08-19: post notifications seemed missing from the
    // All view. The All content filter must include every record kind; the
    // narrowed filters partition posts and tasks.
    func testAllContentFilterIncludesPostAndTaskRecords() {
        let postRecord = AgentActivityRecord(
            notificationID: "test-post",
            workspaceID: nil,
            kind: .scheduledPost,
            availableAt: Date(),
            title: "Post reminder",
            body: "",
            reason: "test",
            priority: 1,
            briefID: UUID(),
            route: .day
        )
        let taskRecord = AgentActivityRecord(
            notificationID: "test-task",
            workspaceID: nil,
            kind: .timedTask,
            availableAt: Date(),
            title: "Task reminder",
            body: "",
            reason: "test",
            priority: 1,
            taskID: UUID(),
            route: .task
        )

        XCTAssertTrue(NotificationActivityContentFilter.all.includes(postRecord))
        XCTAssertTrue(NotificationActivityContentFilter.all.includes(taskRecord))
        XCTAssertTrue(NotificationActivityContentFilter.posts.includes(postRecord))
        XCTAssertFalse(NotificationActivityContentFilter.posts.includes(taskRecord))
        XCTAssertTrue(NotificationActivityContentFilter.tasks.includes(taskRecord))
        XCTAssertFalse(NotificationActivityContentFilter.tasks.includes(postRecord))
    }

    // Creator request 2026-08-19: a "Clear all" option for notifications.
    // Clearing hides a record without deleting it — deletion cannot work here
    // because reconcile re-seeds any notification whose live condition still
    // holds. A cleared record only returns when a genuinely new occurrence
    // resets its state.
    func testClearedRecordsLeaveTheActivityList() {
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        XCTAssertTrue(AgentActivityPresentationPolicy.isVisible(
            availableAt: past, archivedAt: nil, clearedAt: nil, now: now
        ))
        XCTAssertFalse(AgentActivityPresentationPolicy.isVisible(
            availableAt: past, archivedAt: nil, clearedAt: now, now: now
        ), "Cleared records must leave the list")
    }

    func testClearAllClearsAndReadsEveryGivenRecord() throws {
        let container = try ModelContainer(
            for: AgentActivityRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let unread = AgentActivityRecord(
            notificationID: "clear-unread",
            workspaceID: nil,
            kind: .scheduledPost,
            availableAt: Date().addingTimeInterval(-60),
            title: "Post reminder",
            body: "",
            reason: "test",
            priority: 1,
            route: .day
        )
        let read = AgentActivityRecord(
            notificationID: "clear-read",
            workspaceID: nil,
            kind: .timedTask,
            availableAt: Date().addingTimeInterval(-60),
            title: "Task reminder",
            body: "",
            reason: "test",
            priority: 1,
            route: .task
        )
        read.readAt = Date().addingTimeInterval(-30)
        context.insert(unread)
        context.insert(read)

        try AgentActivityCenterService.clearAll([unread, read], context: context)

        XCTAssertNotNil(unread.clearedAt)
        XCTAssertNotNil(unread.readAt, "Clearing also reads, so the badge empties")
        XCTAssertNotNil(read.clearedAt)
        XCTAssertNotNil(read.readAt)
    }
}
