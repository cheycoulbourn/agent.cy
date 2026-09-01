import Foundation
import SwiftData

protocol InspirationShapingServicing: Sendable {
    func shape(
        sourcePlatform: InspirationPlatform,
        sourceMaterial: InspirationSourceMaterialWire,
        creatorContext: CreatorContextWire,
        assistanceMode: AssistanceMode,
        operationID: UUID
    ) async throws -> InspirationShapeResultWire
}

actor RemoteInspirationShapingService: InspirationShapingServicing {
    private let client: AgentCyAPIClient

    init(client: AgentCyAPIClient = AgentCyAPIClient()) {
        self.client = client
    }

    func shape(
        sourcePlatform: InspirationPlatform,
        sourceMaterial: InspirationSourceMaterialWire,
        creatorContext: CreatorContextWire,
        assistanceMode: AssistanceMode,
        operationID: UUID
    ) async throws -> InspirationShapeResultWire {
        try InspirationSourceMaterialValidator.validate(sourceMaterial)
        let safeContext = AIRequestNormalizer.creatorContext(creatorContext)
        let request = InspirationShapeRequestWire(
            schemaVersion: AIContractVersion.inspirationShapeRequest,
            promptVersion: AIContractVersion.inspirationShapePrompt,
            operationId: operationID,
            appBuild: APIConfiguration.appBuild,
            assistanceMode: assistanceMode,
            creatorContext: safeContext,
            sourcePlatform: sourcePlatform,
            sourceMaterial: sourceMaterial
        )
        do {
            return try await client.perform(
                operation: .shapeInspiration,
                request: request,
                result: InspirationShapeResultWire.self,
                validateResult: InspirationShapeValidator.validate
            )
        } catch {
            guard Self.shouldUseHostedV1Compatibility(after: error) else { throw error }
            let legacyRequest = LegacyInspirationShapeRequestWire(
                schemaVersion: "inspiration-shape.request.v1",
                promptVersion: "inspiration-shape.v1",
                operationId: UUID(),
                appBuild: APIConfiguration.appBuild,
                assistanceMode: assistanceMode,
                creatorContext: safeContext,
                sourcePlatform: sourcePlatform,
                creatorObservation: Self.legacyObservation(sourceMaterial)
            )
            let legacy = try await client.performHostedCompatibility(
                operation: .shapeInspiration,
                request: legacyRequest,
                result: LegacyInspirationShapeResultWire.self,
                expectedResultSchemaVersion: "inspiration-shape.result.v1"
            )
            let result = Self.adapt(
                legacy,
                sourceMaterial: sourceMaterial,
                creatorContext: safeContext
            )
            try InspirationShapeValidator.validate(result)
            return result
        }
    }

    private static func shouldUseHostedV1Compatibility(after error: Error) -> Bool {
        guard let apiError = error as? AgentCyAPIError else { return false }
        switch apiError {
        case .invalidStream:
            return true
        case .server(let wireError):
            return wireError.code == .invalidInput
        case .invalidRequest, .payloadTooLarge, .missingCredential, .noAvailableProvider,
             .http:
            return false
        }
    }

    private static func legacyObservation(_ material: InspirationSourceMaterialWire) -> String {
        var sections: [String] = []
        if let title = material.title { sections.append("Title: \(title)") }
        if let caption = material.caption { sections.append("Caption: \(caption)") }
        if let transcript = material.transcript { sections.append("Transcript: \(transcript)") }
        if !material.visualObservations.isEmpty {
            sections.append("Visual observations: \(material.visualObservations.joined(separator: " | "))")
        }
        return String(sections.joined(separator: "\n").prefix(2_000))
    }

    private static func adapt(
        _ legacy: LegacyInspirationShapeResultWire,
        sourceMaterial: InspirationSourceMaterialWire,
        creatorContext: CreatorContextWire
    ) -> InspirationShapeResultWire {
        let evidence = [sourceMaterial.caption, sourceMaterial.transcript, sourceMaterial.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summary = String((evidence.first ?? sourceMaterial.visualObservations.first ?? "Shared post analysis").prefix(2_000))
        let points = evidence
            .flatMap { value in
                value.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, point in
                let bounded = String(point.prefix(2_000))
                if !result.contains(bounded) { result.append(bounded) }
            }
        let keyPoints = Array((points.isEmpty ? [summary] : points).prefix(4))
        return InspirationShapeResultWire(
            sourceSummary: summary,
            keyPoints: keyPoints,
            interpretedMechanic: legacy.interpretedMechanic,
            originalityGuardrails: legacy.originalityGuardrails,
            idea: legacy.idea,
            suggestedPillarId: creatorContext.pillars.first?.pillarId,
            assumptions: legacy.assumptions
        )
    }
}

struct PreviewInspirationShapingService: InspirationShapingServicing {
    func shape(
        sourcePlatform _: InspirationPlatform,
        sourceMaterial _: InspirationSourceMaterialWire,
        creatorContext: CreatorContextWire,
        assistanceMode _: AssistanceMode,
        operationID _: UUID
    ) async throws -> InspirationShapeResultWire {
        InspirationShapeResultWire(
            sourceSummary: "The post shows how a smaller starting ritual can reduce the friction before creative work.",
            keyPoints: [
                "Name the tension before offering the reset.",
                "Demonstrate one specific change instead of listing advice.",
                "End with a small action the viewer can repeat."
            ],
            interpretedMechanic: InspirationMechanicWire(
                hookPattern: "Open with tension before the practical shift",
                structurePattern: "Tension, reset, original demonstration",
                payoffPattern: "End with one smaller action"
            ),
            originalityGuardrails: [
                "Use a firsthand example from your own process.",
                "Do not reuse source wording, story details, or shot order."
            ],
            idea: InspirationIdeaWire(
                title: "The smaller reset that made starting easier",
                premise: "Show one original workflow adjustment that reduced creative friction.",
                audience: "Solo creators who postpone filming while perfecting the setup",
                takeaway: "Make the first take easier by shrinking one setup decision.",
                spokenHook: "The plan was not what kept me from filming.",
                firstFrameText: "MAKE THE FIRST TAKE EASIER",
                filmingApproach: "Use direct-to-camera explanation and one firsthand demonstration from \(creatorContext.name)'s workflow.",
                recommendedFormat: "45-second vertical video",
                durationSeconds: 45
            ),
            suggestedPillarId: creatorContext.pillars.first?.pillarId,
            assumptions: ["You have a firsthand workflow reset to demonstrate."]
        )
    }
}

enum InspirationShapingError: LocalizedError, Equatable {
    case invalidObservation
    case invalidSourceMaterial
    case invalidResult
    case invalidSourceState

    var errorDescription: String? {
        switch self {
        case .invalidObservation:
            "Add what caught your attention before shaping this idea."
        case .invalidSourceMaterial:
            "agent.cy could not find enough post content to create an accurate idea."
        case .invalidResult:
            "Cy couldn’t shape a reliable original idea. Add more detail and try again."
        case .invalidSourceState:
            "This saved inspiration changed while Cy was working. Open it and try again."
        }
    }
}

enum InspirationSourceMaterialValidator {
    static func validate(_ material: InspirationSourceMaterialWire) throws {
        let title = material.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = material.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = material.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let observations = material.visualObservations.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let hasContentEvidence = caption?.isEmpty == false ||
            transcript?.isEmpty == false ||
            material.analyzedInputs.contains(.onScreenText)
        guard material.analyzedInputs.count == Set(material.analyzedInputs).count,
              !material.analyzedInputs.isEmpty,
              material.analyzedInputs.count <= 5,
              (title?.utf16.count ?? 0) <= 160,
              (caption?.utf16.count ?? 0) <= 20_000,
              (transcript?.utf16.count ?? 0) <= 20_000,
              observations.count <= 20,
              observations.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 2_000 }),
              hasContentEvidence,
              material.durationSeconds.map({ (1...21_600).contains($0) }) ?? true else {
            throw InspirationShapingError.invalidSourceMaterial
        }
    }

}

enum InspirationShapeValidator {
    static func validate(_ result: InspirationShapeResultWire) throws {
        let mechanic = result.interpretedMechanic
        let idea = result.idea
        let requiredMediumText = [
            result.sourceSummary,
            mechanic.hookPattern,
            mechanic.structurePattern,
            mechanic.payoffPattern,
            idea.premise,
            idea.audience,
            idea.takeaway,
            idea.spokenHook,
            idea.firstFrameText,
            idea.filmingApproach,
        ]
        // Legacy contract durations remain valid so a generated Spark is never
        // rejected solely because it uses an existing saved-work duration.
        let allowedDurations: Set<Int> = [
            15, 30, 45, 60, 90, 180, 300, 480,
            600, 900, 1_200, 1_800, 2_700, 3_600,
        ]
        guard !idea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              idea.title.utf16.count <= 160,
              !idea.recommendedFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              idea.recommendedFormat.utf16.count <= 160,
              requiredMediumText.allSatisfy({
                  let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !trimmed.isEmpty && trimmed.utf16.count <= 2_000
              }),
              (1...3).contains(result.originalityGuardrails.count),
              (1...4).contains(result.keyPoints.count),
              result.keyPoints.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 2_000 }),
              result.originalityGuardrails.allSatisfy({
                  let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !trimmed.isEmpty && trimmed.utf16.count <= 2_000
              }),
              result.assumptions.count <= 8,
              result.assumptions.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 2_000 }),
              allowedDurations.contains(idea.durationSeconds) else {
            throw InspirationShapingError.invalidResult
        }
    }
}

struct InspirationEditableIdea: Equatable, Sendable {
    var title: String
    var premise: String
    var audience: String
    var takeaway: String
    var spokenHook: String
    var firstFrameText: String
    var filmingApproach: String
    var pillarID: UUID?

    var isValid: Bool {
        let values = [title, premise, audience, takeaway, spokenHook, firstFrameText, filmingApproach]
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            title.utf16.count <= 160 &&
            values.dropFirst().allSatisfy {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed.utf16.count <= 2_000
            }
    }

    init(result: InspirationShapeResultWire) {
        title = result.idea.title
        premise = result.idea.premise
        audience = result.idea.audience
        takeaway = result.idea.takeaway
        spokenHook = result.idea.spokenHook
        firstFrameText = result.idea.firstFrameText
        filmingApproach = result.idea.filmingApproach
        pillarID = result.suggestedPillarId
    }
}

struct ManualInspirationIdeaDraft: Codable, Equatable, Sendable {
    var title: String
    var premise: String
    var spokenHook: String
    var takeaway: String
    var filmingApproach: String
    var pillarID: UUID?

    var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty &&
            title.utf16.count <= 160 &&
            [premise, spokenHook, takeaway, filmingApproach].allSatisfy {
                $0.utf16.count <= 2_000
            }
    }

    var hasContent: Bool {
        pillarID != nil || [title, premise, spokenHook, takeaway, filmingApproach]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init(
        title: String = "",
        premise: String = "",
        spokenHook: String = "",
        takeaway: String = "",
        filmingApproach: String = "",
        pillarID: UUID? = nil
    ) {
        self.title = title
        self.premise = premise
        self.spokenHook = spokenHook
        self.takeaway = takeaway
        self.filmingApproach = filmingApproach
        self.pillarID = pillarID
    }
}

@MainActor
enum InspirationShapePersistenceCoordinator {
    static func stage(
        _ result: InspirationShapeResultWire,
        on source: InspirationSource,
        context: ModelContext
    ) throws {
        guard source.status == .shaping, source.linkedBriefID == nil else {
            throw InspirationShapingError.invalidSourceState
        }
        try InspirationShapeValidator.validate(result)
        let payload = try JSONEncoder.agentCy.encode(result)
        source.shapePayloadJSON = String(decoding: payload, as: UTF8.self)
        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        source.pillarID = result.suggestedPillarId.flatMap { pillarID in
            pillars.first {
                $0.id == pillarID && !$0.isArchived && $0.workspaceID == source.workspaceID
            }?.id
        }
        source.status = .ready
        source.lastErrorCode = nil
        source.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func apply(
        _ result: InspirationShapeResultWire,
        to source: InspirationSource,
        context: ModelContext
    ) throws -> CreativeBrief {
        if let linkedBriefID = source.linkedBriefID,
           let existing = try context.fetch(FetchDescriptor<CreativeBrief>())
            .first(where: { $0.id == linkedBriefID }) {
            return existing
        }
        if source.status == .shaping {
            try stage(result, on: source, context: context)
        }
        return try save(
            InspirationEditableIdea(result: result),
            result: result,
            to: source,
            context: context
        )
    }

    static func save(
        _ draft: InspirationEditableIdea,
        result: InspirationShapeResultWire,
        to source: InspirationSource,
        context: ModelContext
    ) throws -> CreativeBrief {
        if let linkedBriefID = source.linkedBriefID,
           let existing = try context.fetch(FetchDescriptor<CreativeBrief>())
            .first(where: { $0.id == linkedBriefID }) {
            return existing
        }
        guard source.status == .ready, source.linkedBriefID == nil else {
            throw InspirationShapingError.invalidSourceState
        }
        guard draft.isValid else { throw InspirationShapingError.invalidResult }
        try InspirationShapeValidator.validate(result)

        let idea = result.idea
        let brief = CreativeBrief(
            title: draft.title,
            premise: draft.premise,
            source: .sharedInspiration,
            status: .spark
        )
        brief.workspaceID = source.workspaceID
        brief.inspirationSourceID = source.id
        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let selectedPillar = draft.pillarID.flatMap { pillarID in
            pillars.first {
                $0.id == pillarID && !$0.isArchived && $0.workspaceID == source.workspaceID
            }
        }
        brief.pillarID = selectedPillar?.id
        source.pillarID = selectedPillar?.id
        brief.audience = draft.audience
        brief.creativeGoal = "Create an original \(idea.recommendedFormat)"
        brief.takeaway = draft.takeaway
        brief.durationSeconds = idea.durationSeconds
        brief.spokenHook = draft.spokenHook
        brief.firstFrameText = draft.firstFrameText
        brief.filmingGuidance = draft.filmingApproach
        brief.assumptions = result.assumptions + result.originalityGuardrails

        context.insert(brief)
        source.linkedBriefID = brief.id
        source.status = .converted
        source.lastErrorCode = nil
        source.updatedAt = Date()

        do {
            try context.save()
            return brief
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Saves changes to an analyzed Saved Post without creating an Idea Bank post.
    static func persistEdits(
        _ draft: InspirationEditableIdea,
        result: InspirationShapeResultWire,
        to source: InspirationSource,
        context: ModelContext
    ) throws -> InspirationShapeResultWire {
        guard source.status == .ready, source.linkedBriefID == nil else {
            throw InspirationShapingError.invalidSourceState
        }
        guard draft.isValid else { throw InspirationShapingError.invalidResult }
        try InspirationShapeValidator.validate(result)

        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let selectedPillarID = draft.pillarID.flatMap { pillarID in
            pillars.first {
                $0.id == pillarID && !$0.isArchived && $0.workspaceID == source.workspaceID
            }?.id
        }
        let editedResult = InspirationShapeResultWire(
            sourceSummary: result.sourceSummary,
            keyPoints: result.keyPoints,
            interpretedMechanic: result.interpretedMechanic,
            originalityGuardrails: result.originalityGuardrails,
            idea: InspirationIdeaWire(
                title: draft.title,
                premise: draft.premise,
                audience: draft.audience,
                takeaway: draft.takeaway,
                spokenHook: draft.spokenHook,
                firstFrameText: draft.firstFrameText,
                filmingApproach: draft.filmingApproach,
                recommendedFormat: result.idea.recommendedFormat,
                durationSeconds: result.idea.durationSeconds
            ),
            suggestedPillarId: selectedPillarID,
            assumptions: result.assumptions
        )
        try InspirationShapeValidator.validate(editedResult)
        let payload = try JSONEncoder.agentCy.encode(editedResult)
        source.shapePayloadJSON = String(decoding: payload, as: UTF8.self)
        source.pillarID = selectedPillarID
        source.updatedAt = Date()

        do {
            try context.save()
            return editedResult
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Saves an incomplete creator-authored draft on the reference itself.
    /// A title is intentionally not required until the creator makes a post.
    static func persistManualDraft(
        _ draft: ManualInspirationIdeaDraft,
        to source: InspirationSource,
        context: ModelContext
    ) throws -> ManualInspirationIdeaDraft {
        guard source.linkedBriefID == nil,
              draft.title.utf16.count <= 160,
              [draft.premise, draft.spokenHook, draft.takeaway, draft.filmingApproach]
              .allSatisfy({ $0.utf16.count <= 2_000 }) else {
            throw InspirationShapingError.invalidResult
        }

        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let selectedPillarID = draft.pillarID.flatMap { pillarID in
            pillars.first {
                $0.id == pillarID && !$0.isArchived && $0.workspaceID == source.workspaceID
            }?.id
        }
        var persistedDraft = draft
        persistedDraft.pillarID = selectedPillarID
        let payload = try JSONEncoder.agentCy.encode(persistedDraft)
        source.manualDraftPayloadJSON = String(decoding: payload, as: UTF8.self)
        if source.shapePayloadJSON.isEmpty {
            source.pillarID = selectedPillarID
        }
        source.updatedAt = Date()

        do {
            try context.save()
            return persistedDraft
        } catch {
            context.rollback()
            throw error
        }
    }

    static func manualDraft(for source: InspirationSource) -> ManualInspirationIdeaDraft {
        guard let data = source.manualDraftPayloadJSON.data(using: .utf8),
              let decoded = try? JSONDecoder.agentCy.decode(
                  ManualInspirationIdeaDraft.self,
                  from: data
              ) else {
            return ManualInspirationIdeaDraft(pillarID: source.pillarID)
        }
        return decoded
    }

    static func saveManual(
        _ draft: ManualInspirationIdeaDraft,
        to source: InspirationSource,
        context: ModelContext
    ) throws -> CreativeBrief {
        if let linkedBriefID = source.linkedBriefID,
           let existing = try context.fetch(FetchDescriptor<CreativeBrief>())
            .first(where: { $0.id == linkedBriefID }) {
            return existing
        }
        guard source.status != .shaping, source.linkedBriefID == nil else {
            throw InspirationShapingError.invalidSourceState
        }
        guard draft.isValid else { throw InspirationShapingError.invalidResult }

        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let selectedPillar = draft.pillarID.flatMap { pillarID in
            pillars.first {
                $0.id == pillarID && !$0.isArchived && $0.workspaceID == source.workspaceID
            }
        }
        let brief = CreativeBrief(
            title: draft.title,
            premise: draft.premise,
            source: .sharedInspiration,
            status: .spark
        )
        brief.workspaceID = source.workspaceID
        brief.inspirationSourceID = source.id
        brief.pillarID = selectedPillar?.id
        brief.spokenHook = draft.spokenHook
        brief.takeaway = draft.takeaway
        brief.filmingGuidance = draft.filmingApproach

        context.insert(brief)
        source.pillarID = selectedPillar?.id
        source.saveMode = .withRemix
        source.linkedBriefID = brief.id
        source.status = .converted
        source.lastErrorCode = nil
        source.updatedAt = Date()

        do {
            try context.save()
            return brief
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
enum InspirationFilmingScheduler {
    @discardableResult
    static func schedule(
        source: InspirationSource,
        brief: CreativeBrief,
        date: Date,
        includesTime: Bool,
        context: ModelContext
    ) throws -> CreatorTask {
        guard source.workspaceID == brief.workspaceID,
              source.linkedBriefID == brief.id,
              brief.inspirationSourceID == source.id else {
            throw InspirationShapingError.invalidSourceState
        }

        let briefID = brief.id
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>(
            predicate: #Predicate { $0.briefID == briefID }
        ))
        let filmingTasks = tasks.filter {
            $0.workspaceID == brief.workspaceID && $0.kind == .filming
        }
        let task = source.filmingTaskID
            .flatMap { taskID in filmingTasks.first(where: { $0.id == taskID }) }
            ?? filmingTasks.first
            ?? CreatorTask(
                briefID: brief.id,
                title: "Film \(brief.title)",
                kind: .filming,
                lane: .production,
                targetDate: date,
                includesTargetTime: includesTime,
                isRecordingMilestoneDesignated: true
            )

        if task.modelContext == nil {
            task.workspaceID = brief.workspaceID
            context.insert(task)
        }
        task.briefID = brief.id
        task.title = "Film \(brief.title)"
        task.targetDate = date
        task.includesTargetTime = includesTime
        task.kind = .filming
        task.lane = .production
        task.isRecordingMilestoneDesignated = true
        brief.workDate = date
        brief.includesWorkTime = includesTime
        brief.updatedAt = Date()
        source.filmingTaskID = task.id
        source.updatedAt = Date()

        do {
            try context.save()
            return task
        } catch {
            context.rollback()
            throw error
        }
    }
}
