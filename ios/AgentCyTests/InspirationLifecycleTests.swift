import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class InspirationLifecycleTests: XCTestCase {
    func testContentResetDeletesOnlyActiveWorkspaceInspiration() throws {
        let previousWorkspaceID = CreatorWorkspacePreferences.activeWorkspaceID
        defer { CreatorWorkspacePreferences.activeWorkspaceID = previousWorkspaceID }

        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", onboardingCompleted: true)
        let active = CreatorWorkspace(profileID: profile.id, name: "Active", sortOrder: 0)
        let other = CreatorWorkspace(profileID: profile.id, name: "Other", sortOrder: 1)
        let deleted = InspirationSource(
            workspaceID: active.id,
            canonicalURLString: "https://www.instagram.com/reel/active/",
            platform: .instagram
        )
        let kept = InspirationSource(
            workspaceID: other.id,
            canonicalURLString: "https://www.instagram.com/reel/other/",
            platform: .instagram
        )
        context.insert(profile)
        context.insert(active)
        context.insert(other)
        context.insert(deleted)
        context.insert(kept)
        try context.save()
        CreatorWorkspacePreferences.activeWorkspaceID = active.id

        try ContentResetService().reset(context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<InspirationSource>()).map(\.id), [kept.id])
    }

    func testWorkspaceDeletionDeletesOnlySelectedWorkspaceInspiration() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", onboardingCompleted: true)
        let deletedWorkspace = CreatorWorkspace(profileID: profile.id, name: "Delete", sortOrder: 0)
        let keptWorkspace = CreatorWorkspace(profileID: profile.id, name: "Keep", sortOrder: 1)
        let deleted = InspirationSource(
            workspaceID: deletedWorkspace.id,
            canonicalURLString: "https://www.tiktok.com/@creator/video/1",
            platform: .tiktok
        )
        let kept = InspirationSource(
            workspaceID: keptWorkspace.id,
            canonicalURLString: "https://www.tiktok.com/@creator/video/2",
            platform: .tiktok
        )
        context.insert(profile)
        context.insert(deletedWorkspace)
        context.insert(keptWorkspace)
        context.insert(deleted)
        context.insert(kept)
        try context.save()

        try WorkspaceDeletionService.delete(workspaceID: deletedWorkspace.id, context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<InspirationSource>()).map(\.id), [kept.id])
    }

    func testPrivacyEraseDeletesPersistedAndQueuedInspiration() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(InspirationSource(
            canonicalURLString: "https://youtu.be/example",
            platform: .youtube
        ))
        try context.save()

        let queueRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("InspirationLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: queueRoot) }
        let queue = InspirationImportQueueStore(rootDirectoryURL: queueRoot, appliesFileProtection: false)
        try queue.enqueue(InspirationShareEnvelope(
            workspaceHintID: nil,
            canonicalURLString: "https://youtu.be/queued",
            platform: .youtube,
            creatorObservation: "Keep the pacing"
        ))
        let suiteName = "InspirationLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        InspirationWorkspaceHintStore.save(UUID(), defaults: defaults)

        try await SwiftDataLocalCreatorDataEraser(
            inspirationQueueStore: queue,
            inspirationWorkspaceDefaults: defaults
        ).eraseAll(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<InspirationSource>()).isEmpty)
        XCTAssertTrue(try queue.pending().isEmpty)
        XCTAssertNil(InspirationWorkspaceHintStore.load(defaults: defaults))
    }

    func testExportIncludesInspirationAndBriefProvenance() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.threads.net/@creator/post/example",
            platform: .threads,
            creatorObservation: "Use the visual reveal"
        )
        let brief = CreativeBrief(title: "My version", source: .sharedInspiration)
        brief.inspirationSourceID = source.id
        source.linkedBriefID = brief.id
        context.insert(source)
        context.insert(brief)
        try context.save()

        let archiveURL = try LocalExportService().makeArchive(context: context)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let archiveData = try Data(contentsOf: archiveURL)

        XCTAssertNotNil(archiveData.range(of: Data("inspirationSources".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data(source.canonicalURLString.utf8)))
        XCTAssertNotNil(archiveData.range(of: Data(source.id.uuidString.utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("\"schemaVersion\" : 19".utf8)))
    }

    func testDeletingSavedPostPreservesCreatedIdeaAndClearsProvenance() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/delete-reference/",
            platform: .instagram
        )
        let brief = CreativeBrief(title: "Keep this idea", source: .sharedInspiration)
        brief.inspirationSourceID = source.id
        source.linkedBriefID = brief.id
        context.insert(source)
        context.insert(brief)
        try context.save()

        try InspirationDeletionCoordinator.delete(source, context: context, assetStore: nil)

        XCTAssertTrue(try context.fetch(FetchDescriptor<InspirationSource>()).isEmpty)
        let remainingBrief = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        XCTAssertEqual(remainingBrief.id, brief.id)
        XCTAssertNil(remainingBrief.inspirationSourceID)
    }

    func testAppModelDeletesSavedPostAndPreservesCreatedIdea() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/delete-from-review/",
            platform: .instagram
        )
        let brief = CreativeBrief(title: "Keep this idea", source: .sharedInspiration)
        brief.inspirationSourceID = source.id
        source.linkedBriefID = brief.id
        context.insert(source)
        context.insert(brief)
        try context.save()

        let deleted = AppModel().deleteInspiration(source, context: context)

        XCTAssertTrue(deleted)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InspirationSource>()).isEmpty)
        let remainingBrief = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        XCTAssertEqual(remainingBrief.id, brief.id)
        XCTAssertNil(remainingBrief.inspirationSourceID)
    }

    func testPhoneIdeaBankSavedPostsPreviewIsLimitedToFive() {
        let sources = (0 ..< 7).map { index in
            InspirationSource(
                canonicalURLString: "https://example.com/post/\(index)",
                platform: .web
            )
        }

        let preview = SavedPostsPreviewPolicy.preview(sources)

        XCTAssertEqual(preview.count, 5)
        XCTAssertEqual(preview.map(\.id), Array(sources.prefix(5)).map(\.id))
    }

    func testSavedPostAnalysisActionMovesThroughToolbarStates() {
        XCTAssertEqual(
            InspirationReviewAnalysisAction.resolve(
                status: .pending,
                hasResult: false,
                hasLinkedBrief: false,
                isAnalyzing: false
            ),
            .analyze
        )
        XCTAssertEqual(
            InspirationReviewAnalysisAction.resolve(
                status: .failed,
                hasResult: false,
                hasLinkedBrief: false,
                isAnalyzing: false
            ),
            .retry
        )
        XCTAssertEqual(
            InspirationReviewAnalysisAction.resolve(
                status: .pending,
                hasResult: false,
                hasLinkedBrief: false,
                isAnalyzing: true
            ),
            .processing
        )
        XCTAssertEqual(
            InspirationReviewAnalysisAction.resolve(
                status: .ready,
                hasResult: true,
                hasLinkedBrief: false,
                isAnalyzing: false
            ),
            .hidden
        )
        XCTAssertEqual(
            InspirationReviewAnalysisAction.resolve(
                status: .converted,
                hasResult: false,
                hasLinkedBrief: true,
                isAnalyzing: false
            ),
            .hidden
        )
        XCTAssertNil(InspirationReviewAnalysisAction.analyze.title)
        XCTAssertNil(InspirationReviewAnalysisAction.retry.title)
    }

    func testSavedPostFailurePresentationExplainsTheRightRecovery() {
        let missingContent = InspirationReviewFailurePresentation.resolve(
            errorCode: "source_content_unavailable"
        )
        XCTAssertEqual(missingContent.title, "Cy needs the post content")
        XCTAssertEqual(
            missingContent.message,
            "The link is saved. Share the post again with its caption or video, then tap Cy above."
        )

        let temporaryFailure = InspirationReviewFailurePresentation.resolve(
            errorCode: "shape_failed"
        )
        XCTAssertEqual(temporaryFailure.title, "Cy couldn’t finish the analysis")
        XCTAssertEqual(
            temporaryFailure.message,
            "Your saved post is safe. Tap Cy above to try again."
        )
    }

    func testSavedPostUsesGeneratedTitleAndKeepsCreatorAttribution() throws {
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/example/",
            platform: .instagram
        )
        source.sourceTitle = "Julia Broome on Instagram"
        let result = InspirationShapeResultWire(
            sourceSummary: "The post explains how to organize recurring content into a series.",
            keyPoints: ["Group related posts around one repeatable audience promise."],
            interpretedMechanic: InspirationMechanicWire(
                hookPattern: "Name the planning problem",
                structurePattern: "Problem, system, example",
                payoffPattern: "A repeatable series plan"
            ),
            originalityGuardrails: ["Use a firsthand example."],
            idea: InspirationIdeaWire(
                title: "Why I am planning content in series",
                premise: "Show the creator's own shift from isolated posts to repeatable series.",
                audience: "Creators who struggle to plan consistently",
                takeaway: "A series makes planning and audience expectations clearer.",
                spokenHook: "I stopped planning every post from scratch.",
                firstFrameText: "PLAN A SERIES, NOT A ONE-OFF",
                filmingApproach: "Talking-head explanation with original examples.",
                recommendedFormat: "45-second vertical video",
                durationSeconds: 45
            ),
            suggestedPillarId: nil,
            assumptions: []
        )
        source.shapePayloadJSON = String(
            decoding: try JSONEncoder.agentCy.encode(result),
            as: UTF8.self
        )
        source.status = .ready

        XCTAssertEqual(
            SavedPostPresentation.title(for: source),
            "Why I am planning content in series"
        )
        XCTAssertEqual(
            SavedPostPresentation.metadata(for: source),
            "Julia Broome on Instagram · Idea ready"
        )
    }
}
