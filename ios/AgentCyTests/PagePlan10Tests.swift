import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PagePlan10Tests: XCTestCase {
    func testAddLivePostPreviewRequiresExplicitLaunchArgument() {
        XCTAssertTrue(PlanRuntimeFixture.requestsAddLivePost(
            arguments: ["agent.cy", "-agentCyPreviewAddLivePost"]
        ))
        XCTAssertFalse(PlanRuntimeFixture.requestsAddLivePost(
            arguments: ["agent.cy", "-agentCyPreviewData"]
        ))
    }

    func testCanonicalDuplicateDetectionIsWorkspaceScoped() throws {
        let profileID = UUID()
        let active = CreatorWorkspace(profileID: profileID, name: "Active")
        let other = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let descriptor = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.instagram.com/p/example/"
        ))
        let sameWorkspace = PlatformOutput(
            briefID: UUID(),
            platform: .instagramReels,
            status: .posted
        )
        sameWorkspace.workspaceID = active.id
        sameWorkspace.publishedURLString =
            "http://www.instagram.com/p/example/?utm_source=share#caption"
        let anotherWorkspace = PlatformOutput(
            briefID: UUID(),
            platform: .instagramReels,
            status: .posted
        )
        anotherWorkspace.workspaceID = other.id
        anotherWorkspace.publishedURLString = descriptor.url.absoluteString

        XCTAssertTrue(LivePostDuplicatePolicy.containsDuplicate(
            url: descriptor.url,
            outputs: [sameWorkspace],
            workspaceID: active.id,
            workspaces: [active, other]
        ))
        XCTAssertFalse(LivePostDuplicatePolicy.containsDuplicate(
            url: descriptor.url,
            outputs: [anotherWorkspace],
            workspaceID: active.id,
            workspaces: [active, other]
        ))
    }

    func testSavingLivePostUsesScopedPrimaryAccountAndCanonicalFields() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let workspace = CreatorWorkspace(profileID: profileID, name: "Main")
        let otherWorkspace = CreatorWorkspace(profileID: profileID, name: "Other", sortOrder: 1)
        let secondary = CreatorSocialAccount(
            profileID: profileID,
            destinationID: PublishingCatalog.instagramID,
            label: "@secondary",
            profileURLString: "https://instagram.com/secondary",
            sortOrder: 0
        )
        secondary.workspaceID = workspace.id
        let primary = CreatorSocialAccount(
            profileID: profileID,
            destinationID: PublishingCatalog.instagramID,
            label: "@primary",
            profileURLString: "https://instagram.com/primary",
            isPrimary: true,
            sortOrder: 1
        )
        primary.workspaceID = workspace.id
        let wrongWorkspacePrimary = CreatorSocialAccount(
            profileID: profileID,
            destinationID: PublishingCatalog.instagramID,
            label: "@wrong",
            profileURLString: "https://instagram.com/wrong",
            isPrimary: true
        )
        wrongWorkspacePrimary.workspaceID = otherWorkspace.id
        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(secondary)
        context.insert(primary)
        context.insert(wrongWorkspacePrimary)
        try context.save()

        let descriptor = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "instagram.com/reel/episode-one/?utm_medium=share"
        ))
        let postedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try LivePostPersistenceService.save(
            descriptor: descriptor,
            metadata: nil,
            postedAt: postedAt,
            workspaceID: workspace.id,
            workspaces: [workspace, otherWorkspace],
            context: context
        )

        XCTAssertEqual(result.brief.status, .posted)
        XCTAssertEqual(result.brief.ideaBankPlacement, .post)
        XCTAssertEqual(result.brief.agendaDate, postedAt)
        XCTAssertEqual(result.output.status, .posted)
        XCTAssertEqual(result.output.targetDate, postedAt)
        XCTAssertEqual(result.output.postedAt, postedAt)
        XCTAssertTrue(result.output.includesTargetTime)
        XCTAssertEqual(result.output.recurrence, .none)
        XCTAssertNil(result.output.seriesRootOutputID)
        XCTAssertEqual(result.output.publishedURLString, descriptor.url.absoluteString)
        XCTAssertEqual(result.output.socialAccountID, primary.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlatformOutput>()).count, 1)
    }

    func testLateDuplicateRecheckDoesNotInsertASecondPost() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let workspace = CreatorWorkspace(profileID: profileID, name: "Main")
        let existingBrief = CreativeBrief(title: "Already saved", status: .posted)
        existingBrief.workspaceID = workspace.id
        let existingOutput = PlatformOutput(
            briefID: existingBrief.id,
            platform: .instagramReels,
            status: .posted
        )
        existingOutput.workspaceID = workspace.id
        existingOutput.publishedURLString =
            "https://www.instagram.com/p/already-saved/?utm_source=copy"
        context.insert(workspace)
        context.insert(existingBrief)
        context.insert(existingOutput)
        try context.save()
        let descriptor = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.instagram.com/p/already-saved/"
        ))

        XCTAssertThrowsError(try LivePostPersistenceService.save(
            descriptor: descriptor,
            metadata: nil,
            postedAt: Date(timeIntervalSince1970: 1_800_000_000),
            workspaceID: workspace.id,
            workspaces: [workspace],
            context: context
        )) { error in
            guard case LivePostPersistenceError.duplicate = error else {
                return XCTFail("Expected duplicate error, received \(error)")
            }
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlatformOutput>()).count, 1)
    }

    func testSuggestedFutureDayDefaultsToNowWithoutMovingPastDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = calendar.date(byAdding: .day, value: -2, to: now)!
        let future = calendar.date(byAdding: .day, value: 2, to: now)!

        XCTAssertEqual(
            LivePostURLPolicy.defaultPostedAt(for: future, now: now, calendar: calendar),
            now
        )
        XCTAssertTrue(calendar.isDate(
            LivePostURLPolicy.defaultPostedAt(for: past, now: now, calendar: calendar),
            inSameDayAs: past
        ))
    }
}
