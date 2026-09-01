import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class InspirationShapingTests: XCTestCase {
    func testShapeRequestSerializesAnalyzedContentButNeverSourceURL() throws {
        let canonicalURL = "https://www.instagram.com/reel/private-source/"
        let request = InspirationShapeRequestWire(
            schemaVersion: AIContractVersion.inspirationShapeRequest,
            promptVersion: AIContractVersion.inspirationShapePrompt,
            operationId: UUID(),
            appBuild: "test",
            assistanceMode: .collaborate,
            creatorContext: creatorContext,
            sourcePlatform: .instagram,
            sourceMaterial: sourceMaterial
        )

        let data = try JSONEncoder.agentCy.encode(request)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains(canonicalURL))
        XCTAssertFalse(json.contains("sourceURL"))
        XCTAssertTrue(json.contains("sourceMaterial"))
        XCTAssertTrue(json.contains("audioTranscript"))
        XCTAssertTrue(json.contains("instagram"))
    }

    func testValidatedShapeCreatesExactlyOneLinkedSparkAcrossRetries() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram,
            creatorObservation: "The hook creates tension before a practical reset.",
            status: .shaping
        )
        source.shapeOperationID = UUID()
        context.insert(source)
        try context.save()
        let result = inspirationResult

        let first = try InspirationShapePersistenceCoordinator.apply(
            result,
            to: source,
            context: context
        )
        let second = try InspirationShapePersistenceCoordinator.apply(
            result,
            to: source,
            context: context
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
        XCTAssertEqual(first.source, .sharedInspiration)
        XCTAssertEqual(first.status, .spark)
        XCTAssertEqual(first.inspirationSourceID, source.id)
        XCTAssertEqual(first.title, result.idea.title)
        XCTAssertEqual(first.filmingGuidance, result.idea.filmingApproach)
        XCTAssertEqual(source.linkedBriefID, first.id)
        XCTAssertEqual(source.status, .converted)
        XCTAssertFalse(source.shapePayloadJSON.isEmpty)
    }

    func testAnalysisStagesEditableIdeaBeforeSavingBrief() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram,
            status: .shaping
        )
        context.insert(source)
        try context.save()

        try InspirationShapePersistenceCoordinator.stage(
            inspirationResult,
            on: source,
            context: context
        )

        XCTAssertEqual(source.status, .ready)
        XCTAssertNil(source.linkedBriefID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)

        var edited = InspirationEditableIdea(result: inspirationResult)
        edited.title = "My edited idea"
        let brief = try InspirationShapePersistenceCoordinator.save(
            edited,
            result: inspirationResult,
            to: source,
            context: context
        )

        XCTAssertEqual(brief.title, "My edited idea")
        XCTAssertEqual(source.status, .converted)
        XCTAssertEqual(source.linkedBriefID, brief.id)
    }

    func testSavingAnalyzedSavedPostChangesUpdatesPayloadWithoutCreatingBrief() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let pillar = Pillar(name: "Creator Life", colorHex: "D22630")
        pillar.workspaceID = workspaceID
        let source = InspirationSource(
            workspaceID: workspaceID,
            canonicalURLString: "https://www.instagram.com/reel/editable-reference/",
            platform: .instagram,
            status: .shaping
        )
        context.insert(pillar)
        context.insert(source)
        try context.save()
        try InspirationShapePersistenceCoordinator.stage(
            inspirationResult,
            on: source,
            context: context
        )

        var draft = InspirationEditableIdea(result: inspirationResult)
        draft.title = "My saved take on the reset"
        draft.pillarID = pillar.id
        let saved = try InspirationShapePersistenceCoordinator.persistEdits(
            draft,
            result: inspirationResult,
            to: source,
            context: context
        )

        let payload = try XCTUnwrap(source.shapePayloadJSON.data(using: .utf8))
        let decoded = try JSONDecoder.agentCy.decode(InspirationShapeResultWire.self, from: payload)
        XCTAssertEqual(saved, decoded)
        XCTAssertEqual(decoded.idea.title, draft.title)
        XCTAssertEqual(decoded.suggestedPillarId, pillar.id)
        XCTAssertEqual(source.pillarID, pillar.id)
        XCTAssertEqual(source.status, .ready)
        XCTAssertNil(source.linkedBriefID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
    }

    func testIncompleteManualSavedPostDraftRoundTripsWithoutCreatingBrief() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let pillar = Pillar(name: "Behind the Scenes", colorHex: "D22630")
        pillar.workspaceID = workspaceID
        let source = InspirationSource(
            workspaceID: workspaceID,
            canonicalURLString: "https://example.com/unfinished-reference",
            platform: .web,
            status: .pending
        )
        context.insert(pillar)
        context.insert(source)
        try context.save()
        let draft = ManualInspirationIdeaDraft(
            premise: "Tell the story from my own experience.",
            pillarID: pillar.id
        )

        let saved = try InspirationShapePersistenceCoordinator.persistManualDraft(
            draft,
            to: source,
            context: context
        )
        let restored = InspirationShapePersistenceCoordinator.manualDraft(for: source)

        XCTAssertEqual(saved, restored)
        XCTAssertEqual(restored.premise, draft.premise)
        XCTAssertTrue(restored.title.isEmpty)
        XCTAssertEqual(restored.pillarID, pillar.id)
        XCTAssertEqual(source.pillarID, pillar.id)
        XCTAssertNil(source.linkedBriefID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
    }

    func testManualDraftKeepsItsOwnPillarWithoutReplacingAnalyzedSuggestion() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let suggestedPillar = Pillar(name: "Creator Life", colorHex: "D22630")
        suggestedPillar.workspaceID = workspaceID
        let manualPillar = Pillar(name: "Business", colorHex: "5E8069")
        manualPillar.workspaceID = workspaceID
        let source = InspirationSource(
            workspaceID: workspaceID,
            canonicalURLString: "https://example.com/two-directions",
            platform: .web,
            status: .ready
        )
        source.shapePayloadJSON = "{\"saved\":true}"
        source.pillarID = suggestedPillar.id
        context.insert(suggestedPillar)
        context.insert(manualPillar)
        context.insert(source)
        try context.save()

        let savedDraft = try InspirationShapePersistenceCoordinator.persistManualDraft(
            ManualInspirationIdeaDraft(
                title: "My own direction",
                pillarID: manualPillar.id
            ),
            to: source,
            context: context
        )

        XCTAssertEqual(savedDraft.pillarID, manualPillar.id)
        XCTAssertEqual(source.pillarID, suggestedPillar.id)
        XCTAssertEqual(
            InspirationShapePersistenceCoordinator.manualDraft(for: source).pillarID,
            manualPillar.id
        )
    }

    func testManualIdeaCreatesOneLinkedPostWithoutCyOrChangingTheReference() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let pillar = Pillar(name: "Creator Life", colorHex: "D22630")
        pillar.workspaceID = workspaceID
        let sourceURL = "https://www.instagram.com/reel/manual-inspiration/"
        let source = InspirationSource(
            workspaceID: workspaceID,
            canonicalURLString: sourceURL,
            platform: .instagram,
            status: .pending
        )
        context.insert(pillar)
        context.insert(source)
        try context.save()

        let draft = ManualInspirationIdeaDraft(
            title: "What I learned from rebuilding my routine",
            premise: "Use the original post as a jumping-off point for my own reset story.",
            spokenHook: "I thought I needed more discipline, but that was not the problem.",
            takeaway: "Make the routine easier to return to.",
            filmingApproach: "Talking head with clips from my actual morning reset.",
            pillarID: pillar.id
        )

        let first = try InspirationShapePersistenceCoordinator.saveManual(
            draft,
            to: source,
            context: context
        )
        let second = try InspirationShapePersistenceCoordinator.saveManual(
            draft,
            to: source,
            context: context
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CreativeBrief>()), 1)
        XCTAssertEqual(first.title, draft.title)
        XCTAssertEqual(first.premise, draft.premise)
        XCTAssertEqual(first.spokenHook, draft.spokenHook)
        XCTAssertEqual(first.takeaway, draft.takeaway)
        XCTAssertEqual(first.filmingGuidance, draft.filmingApproach)
        XCTAssertEqual(first.pillarID, pillar.id)
        XCTAssertEqual(first.source, .sharedInspiration)
        XCTAssertEqual(first.inspirationSourceID, source.id)
        XCTAssertEqual(source.canonicalURLString, sourceURL)
        XCTAssertEqual(source.linkedBriefID, first.id)
        XCTAssertEqual(source.status, .converted)
        XCTAssertTrue(source.shapePayloadJSON.isEmpty)
    }

    func testSourceMaterialRejectsThumbnailOnlyObservations() {
        let thumbnailOnly = InspirationSourceMaterialWire(
            title: "Julia Broome on Instagram",
            caption: nil,
            transcript: nil,
            visualObservations: ["Thumbnail subjects: person, glasses"],
            analyzedInputs: [.linkMetadata],
            durationSeconds: nil
        )

        XCTAssertThrowsError(try InspirationSourceMaterialValidator.validate(thumbnailOnly)) { error in
            XCTAssertEqual(error as? InspirationShapingError, .invalidSourceMaterial)
        }
    }

    func testSelectedExistingPillarPersistsToSavedPostAndSpark() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(name: "Content Strategy", colorHex: "D22630")
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram,
            status: .shaping
        )
        context.insert(pillar)
        context.insert(source)
        try context.save()
        let result = inspirationResult(pillarID: pillar.id)

        try InspirationShapePersistenceCoordinator.stage(result, on: source, context: context)
        let brief = try InspirationShapePersistenceCoordinator.save(
            InspirationEditableIdea(result: result),
            result: result,
            to: source,
            context: context
        )

        XCTAssertEqual(source.pillarID, pillar.id)
        XCTAssertEqual(brief.pillarID, pillar.id)
    }

    func testTagsDeduplicateByNameAndToggleOnSavedPost() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram
        )
        context.insert(source)
        try context.save()

        let first = try InspirationTagCoordinator.assign(name: "Hooks", to: source, context: context)
        let duplicate = try InspirationTagCoordinator.assign(name: " hooks ", to: source, context: context)

        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(source.tagIDs, [first.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<InspirationTag>()).count, 1)

        try InspirationTagCoordinator.toggle(first, on: source, context: context)
        XCTAssertTrue(source.tagIDs.isEmpty)
    }

    func testSchedulingFilmingIsIdempotentAndUpdatesTheLinkedSpark() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram,
            creatorObservation: "The hook creates tension before a practical reset.",
            status: .converted
        )
        let brief = CreativeBrief(
            title: "The reset that made starting easier",
            premise: "Show one original workflow adjustment that reduced friction.",
            source: .sharedInspiration
        )
        brief.inspirationSourceID = source.id
        source.linkedBriefID = brief.id
        context.insert(source)
        context.insert(brief)
        try context.save()
        let firstDate = Date(timeIntervalSince1970: 1_786_400_000)
        let updatedDate = firstDate.addingTimeInterval(7_200)

        let first = try InspirationFilmingScheduler.schedule(
            source: source,
            brief: brief,
            date: firstDate,
            includesTime: false,
            context: context
        )
        let second = try InspirationFilmingScheduler.schedule(
            source: source,
            brief: brief,
            date: updatedDate,
            includesTime: true,
            context: context
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(source.filmingTaskID, first.id)
        XCTAssertEqual(brief.workDate, updatedDate)
        XCTAssertTrue(brief.includesWorkTime)
        XCTAssertEqual(second.targetDate, updatedDate)
        XCTAssertTrue(second.includesTargetTime)
        XCTAssertEqual(second.briefID, brief.id)
        XCTAssertEqual(second.kind, .filming)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).count, 1)
    }

    func testSchedulingFilmingRejectsALinkedBriefFromAnotherWorkspace() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let source = InspirationSource(
            workspaceID: UUID(),
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram,
            status: .converted
        )
        let brief = CreativeBrief(
            title: "A brief in another workspace",
            premise: "This must not become scheduled work.",
            source: .sharedInspiration
        )
        brief.workspaceID = UUID()
        brief.inspirationSourceID = source.id
        source.linkedBriefID = brief.id
        context.insert(source)
        context.insert(brief)
        try context.save()

        XCTAssertThrowsError(
            try InspirationFilmingScheduler.schedule(
                source: source,
                brief: brief,
                date: Date(timeIntervalSince1970: 1_786_400_000),
                includesTime: false,
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? InspirationShapingError, .invalidSourceState)
        }
        XCTAssertNil(source.filmingTaskID)
        XCTAssertNil(brief.workDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorTask>()).isEmpty)
    }

    func testSchedulingFilmingDoesNotRewriteAStaleTaskLink() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let source = InspirationSource(
            workspaceID: workspaceID,
            canonicalURLString: "https://www.instagram.com/reel/private-source/",
            platform: .instagram,
            status: .converted
        )
        let brief = CreativeBrief(
            title: "The linked filming brief",
            premise: "Schedule only the work derived from this brief.",
            source: .sharedInspiration
        )
        brief.workspaceID = workspaceID
        brief.inspirationSourceID = source.id
        source.linkedBriefID = brief.id
        let unrelatedBriefID = UUID()
        let unrelatedTask = CreatorTask(
            briefID: unrelatedBriefID,
            title: "Do not rewrite this task",
            kind: .editing,
            targetDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        unrelatedTask.workspaceID = workspaceID
        source.filmingTaskID = unrelatedTask.id
        context.insert(source)
        context.insert(brief)
        context.insert(unrelatedTask)
        try context.save()

        let filmingTask = try InspirationFilmingScheduler.schedule(
            source: source,
            brief: brief,
            date: Date(timeIntervalSince1970: 1_786_400_000),
            includesTime: false,
            context: context
        )

        XCTAssertNotEqual(filmingTask.id, unrelatedTask.id)
        XCTAssertEqual(filmingTask.briefID, brief.id)
        XCTAssertEqual(filmingTask.workspaceID, workspaceID)
        XCTAssertEqual(source.filmingTaskID, filmingTask.id)
        XCTAssertEqual(unrelatedTask.title, "Do not rewrite this task")
        XCTAssertEqual(unrelatedTask.briefID, unrelatedBriefID)
        XCTAssertEqual(unrelatedTask.kind, .editing)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorTask>()).count, 2)
    }

    private var creatorContext: CreatorContextWire {
        CreatorContextWire(
            name: "Chey",
            primaryGoal: "Create useful original videos",
            selectedPlatforms: [.instagramReels],
            voiceExamples: [],
            voiceProfile: nil,
            pillars: [],
            librarySummaries: [],
            taskSummaries: []
        )
    }

    private var inspirationResult: InspirationShapeResultWire {
        inspirationResult(pillarID: nil)
    }

    private func inspirationResult(pillarID: UUID?) -> InspirationShapeResultWire {
        InspirationShapeResultWire(
            sourceSummary: "The post demonstrates how a smaller setup decision reduces filming friction.",
            keyPoints: ["Name the tension first.", "Demonstrate one practical reset."],
            interpretedMechanic: InspirationMechanicWire(
                hookPattern: "Open with tension",
                structurePattern: "Tension, reset, demonstration",
                payoffPattern: "One smaller next move"
            ),
            originalityGuardrails: [
                "Use a firsthand example.",
                "Do not reuse source wording or story details."
            ],
            idea: InspirationIdeaWire(
                title: "The reset that made starting easier",
                premise: "Show one original workflow adjustment that reduced friction.",
                audience: "Solo creators delaying their first take",
                takeaway: "Shrink one setup decision.",
                spokenHook: "The plan was not the problem.",
                firstFrameText: "MAKE THE FIRST TAKE EASIER",
                filmingApproach: "Direct to camera with one firsthand demonstration.",
                recommendedFormat: "45-second vertical video",
                durationSeconds: 45
            ),
            suggestedPillarId: pillarID,
            assumptions: ["The creator has a firsthand example."]
        )
    }

    private var sourceMaterial: InspirationSourceMaterialWire {
        InspirationSourceMaterialWire(
            title: "A practical filming reset",
            caption: "The hook creates tension before a practical reset.",
            transcript: "I made filming easier by shrinking one setup decision.",
            visualObservations: ["Direct-to-camera opening followed by a demonstration."],
            analyzedInputs: [.caption, .audioTranscript, .videoFrames],
            durationSeconds: 45
        )
    }
}
