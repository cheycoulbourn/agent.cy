import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class InspirationImportTests: XCTestCase {
    func testOriginalOnlyEnvelopeImportsAnalysisWithoutSavingTheRemix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillarID = UUID()
        let result = Self.makeResult(pillarID: pillarID)
        let resultData = try JSONEncoder.agentCy.encode(result)
        let resultJSON = try XCTUnwrap(String(data: resultData, encoding: .utf8))
        let envelope = InspirationShareEnvelope(
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: nil,
            canonicalURLString: "https://www.instagram.com/reel/READY/",
            platform: .instagram,
            sourceCaption: "A grounded source caption.",
            sourceTitle: "Mari Movie on Instagram",
            sourceCreatorName: "Mari Movie",
            sourceCreatorHandle: "mariimovie",
            sourceTranscript: "The complete spoken explanation.",
            visualObservations: ["Video format: talking-head delivery."],
            analyzedInputs: ["caption", "audioTranscript", "videoFrames"],
            sourceDurationSeconds: 37,
            shapeResultJSON: resultJSON,
            saveMode: .originalOnly
        )
        try queue.enqueue(envelope)

        _ = try InspirationImportCoordinator(queueStore: queue).importPending(
            context: context,
            preferredWorkspaceID: nil
        )

        let source = try XCTUnwrap(context.fetch(FetchDescriptor<InspirationSource>()).first)
        XCTAssertEqual(source.status, .ready)
        XCTAssertEqual(source.saveMode, .originalOnly)
        XCTAssertEqual(source.sourceTitle, "Mari Movie on Instagram")
        XCTAssertEqual(source.sourceTranscript, "The complete spoken explanation.")
        XCTAssertEqual(source.analyzedInputs, [.audioTranscript, .caption, .videoFrames])
        XCTAssertEqual(source.pillarID, pillarID)
        XCTAssertEqual(source.shapePayloadJSON, resultJSON)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
    }

    func testRemixEnvelopeImportsAReadyPostIdea() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let importID = UUID()
        let result = Self.makeResult(pillarID: nil)
        let resultData = try JSONEncoder.agentCy.encode(result)
        let resultJSON = try XCTUnwrap(String(data: resultData, encoding: .utf8))
        let envelope = InspirationShareEnvelope(
            id: importID,
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: nil,
            canonicalURLString: "https://www.instagram.com/reel/REMIX/",
            platform: .instagram,
            sourceCaption: "A grounded source caption.",
            sourceTitle: "Creator on Instagram",
            analyzedInputs: ["caption"],
            shapeResultJSON: resultJSON,
            saveMode: .withRemix
        )
        try queue.enqueue(envelope)

        let importResult = try InspirationImportCoordinator(queueStore: queue).importPending(
            context: context,
            preferredWorkspaceID: nil
        )

        let source = try XCTUnwrap(context.fetch(FetchDescriptor<InspirationSource>()).first)
        let brief = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        XCTAssertEqual(source.status, .converted)
        XCTAssertEqual(source.saveMode, .withRemix)
        XCTAssertEqual(source.linkedBriefID, brief.id)
        XCTAssertEqual(brief.inspirationSourceID, source.id)
        XCTAssertEqual(brief.title, result.idea.title)
        XCTAssertTrue(importResult.importedSourceIDs.contains(source.id))
    }

    func testOriginalOnlyResharePreservesAnExistingRemix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let result = Self.makeResult(pillarID: nil)
        let resultData = try JSONEncoder.agentCy.encode(result)
        let resultJSON = try XCTUnwrap(String(data: resultData, encoding: .utf8))
        let canonicalURL = "https://www.instagram.com/reel/EXISTING/"
        let coordinator = InspirationImportCoordinator(queueStore: queue)

        try queue.enqueue(InspirationShareEnvelope(
            workspaceHintID: nil,
            canonicalURLString: canonicalURL,
            platform: .instagram,
            shapeResultJSON: resultJSON,
            saveMode: .withRemix
        ))
        _ = try coordinator.importPending(context: context, preferredWorkspaceID: nil)

        try queue.enqueue(InspirationShareEnvelope(
            workspaceHintID: nil,
            canonicalURLString: canonicalURL,
            platform: .instagram,
            shapeResultJSON: resultJSON,
            saveMode: .originalOnly
        ))
        _ = try coordinator.importPending(context: context, preferredWorkspaceID: nil)

        let source = try XCTUnwrap(context.fetch(FetchDescriptor<InspirationSource>()).first)
        XCTAssertEqual(source.saveMode, .withRemix)
        XCTAssertNotNil(source.linkedBriefID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CreativeBrief>()), 1)
    }

    func testImportUsesValidWorkspaceHintRemovesQueueAndReplaysWithoutDuplication() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let preferredWorkspace = CreatorWorkspace(
            profileID: profileID,
            name: "Preferred",
            sortOrder: 0
        )
        let capturedWorkspace = CreatorWorkspace(
            profileID: profileID,
            name: "Captured",
            sortOrder: 1
        )
        context.insert(preferredWorkspace)
        context.insert(capturedWorkspace)
        try context.save()

        let envelope = InspirationShareEnvelope(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: capturedWorkspace.id,
            canonicalURLString: "https://www.instagram.com/reel/ABC/",
            platform: .instagram,
            creatorObservation: "The opening creates tension before the reveal.",
            sourceCaption: "Three ways to make your first take easier"
        )
        try queue.enqueue(envelope)
        let coordinator = InspirationImportCoordinator(queueStore: queue)

        let first = try coordinator.importPending(
            context: context,
            preferredWorkspaceID: preferredWorkspace.id
        )

        let sources = try context.fetch(FetchDescriptor<InspirationSource>())
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(first.importedSourceIDs, [source.id])
        XCTAssertEqual(first.reopenedSourceIDs, [])
        XCTAssertEqual(source.workspaceID, capturedWorkspace.id)
        XCTAssertEqual(source.sourceImportID, envelope.id)
        XCTAssertEqual(source.creatorObservation, envelope.creatorObservation)
        XCTAssertEqual(source.sourceCaption, envelope.sourceCaption)
        XCTAssertEqual(source.platform, .instagram)
        XCTAssertEqual(source.status, .pending)
        XCTAssertEqual(try queue.pending(), [])

        try queue.enqueue(envelope)
        let replay = try coordinator.importPending(
            context: context,
            preferredWorkspaceID: preferredWorkspace.id
        )

        XCTAssertEqual(replay.importedSourceIDs, [])
        XCTAssertEqual(replay.reopenedSourceIDs, [source.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<InspirationSource>()).count, 1)
        XCTAssertEqual(try queue.pending(), [])
    }

    func testImportFallsBackToPreferredWorkspaceAndDeduplicatesCanonicalURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspace = CreatorWorkspace(profileID: UUID(), name: "Current")
        context.insert(workspace)
        try context.save()
        let coordinator = InspirationImportCoordinator(queueStore: queue)

        let first = InspirationShareEnvelope(
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: UUID(),
            canonicalURLString: "https://youtu.be/ABC",
            platform: .youtube,
            creatorObservation: ""
        )
        try queue.enqueue(first)
        _ = try coordinator.importPending(context: context, preferredWorkspaceID: workspace.id)

        let second = InspirationShareEnvelope(
            capturedAt: Date(timeIntervalSince1970: 200),
            workspaceHintID: workspace.id,
            canonicalURLString: "https://youtu.be/ABC",
            platform: .youtube,
            creatorObservation: "I like the direct demonstration."
        )
        try queue.enqueue(second)
        let result = try coordinator.importPending(context: context, preferredWorkspaceID: workspace.id)

        let sources = try context.fetch(FetchDescriptor<InspirationSource>())
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(source.workspaceID, workspace.id)
        XCTAssertEqual(source.creatorObservation, second.creatorObservation)
        XCTAssertEqual(result.reopenedSourceIDs, [source.id])
    }

    func testSamePostImportedByTwoWorkspacesCreatesTwoPrivateRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let firstWorkspace = CreatorWorkspace(profileID: profileID, name: "First")
        let secondWorkspace = CreatorWorkspace(profileID: profileID, name: "Second")
        context.insert(firstWorkspace)
        context.insert(secondWorkspace)
        try context.save()
        let coordinator = InspirationImportCoordinator(queueStore: queue)
        let canonicalURL = "https://www.instagram.com/reel/PRIVATE/"

        try queue.enqueue(InspirationShareEnvelope(
            workspaceHintID: firstWorkspace.id,
            canonicalURLString: canonicalURL,
            platform: .instagram
        ))
        _ = try coordinator.importPending(context: context, preferredWorkspaceID: firstWorkspace.id)

        try queue.enqueue(InspirationShareEnvelope(
            workspaceHintID: secondWorkspace.id,
            canonicalURLString: canonicalURL,
            platform: .instagram
        ))
        _ = try coordinator.importPending(context: context, preferredWorkspaceID: secondWorkspace.id)

        let sources = try context.fetch(FetchDescriptor<InspirationSource>())
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(Set(sources.compactMap(\.workspaceID)), [firstWorkspace.id, secondWorkspace.id])
    }

    private static func makeResult(pillarID: UUID?) -> InspirationShapeResultWire {
        InspirationShapeResultWire(
            sourceSummary: "The creator explains why a smaller filming setup makes consistency easier.",
            keyPoints: ["Reduce the decisions required before the first take."],
            interpretedMechanic: InspirationMechanicWire(
                hookPattern: "Open on the friction",
                structurePattern: "Problem, reset, example",
                payoffPattern: "End with one action"
            ),
            originalityGuardrails: ["Use a firsthand example."],
            idea: InspirationIdeaWire(
                title: "The setup rule that gets me filming",
                premise: "Show the one setup limit that helps you start.",
                audience: "Creators who overprepare",
                takeaway: "A smaller setup creates momentum.",
                spokenHook: "My setup was the reason I was not filming.",
                firstFrameText: "MAKE THE SETUP SMALLER",
                filmingApproach: "Use talking-head delivery and one original demonstration.",
                recommendedFormat: "45-second vertical video",
                durationSeconds: 45
            ),
            suggestedPillarId: pillarID,
            assumptions: []
        )
    }
}
