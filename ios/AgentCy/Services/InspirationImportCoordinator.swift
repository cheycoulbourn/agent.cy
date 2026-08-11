import Foundation
import SwiftData

struct InspirationImportResult: Equatable, Sendable {
    var importedSourceIDs: [UUID] = []
    var reopenedSourceIDs: [UUID] = []
}

@MainActor
struct InspirationImportCoordinator {
    private let queueStore: InspirationImportQueueStore
    private let assetStore: InspirationSharedAssetStore?

    init(
        queueStore: InspirationImportQueueStore,
        assetStore: InspirationSharedAssetStore? = nil
    ) {
        self.queueStore = queueStore
        self.assetStore = assetStore
    }

    init() throws {
        queueStore = try InspirationImportQueueStore()
        assetStore = try InspirationSharedAssetStore()
    }

    func importPending(
        context: ModelContext,
        preferredWorkspaceID: UUID?
    ) throws -> InspirationImportResult {
        let workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let fallbackWorkspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        )
        var existingSources = try context.fetch(FetchDescriptor<InspirationSource>())
        var result = InspirationImportResult()

        for envelope in try queueStore.pending() {
            let canonicalURL = try InspirationLinkCanonicalizer.canonicalize(
                envelope.canonicalURLString
            )
            guard canonicalURL.absoluteString == envelope.canonicalURLString else {
                throw InspirationShareTransportError.invalidEnvelope
            }
            let workspaceID = resolvedWorkspaceID(
                hint: envelope.workspaceHintID,
                fallback: fallbackWorkspaceID,
                workspaces: workspaces
            )

            if let existing = existingSources.first(where: {
                $0.workspaceID == workspaceID &&
                    ($0.sourceImportID == envelope.id ||
                        $0.canonicalURLString == envelope.canonicalURLString)
            }) {
                existing.platform = InspirationLinkCanonicalizer.platform(for: canonicalURL)
                if !envelope.creatorObservation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.creatorObservation = envelope.creatorObservation
                }
                if let caption = envelope.sourceCaption?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !caption.isEmpty {
                    existing.sourceCaption = caption
                }
                let analyzedResult = try applyAnalysis(from: envelope, to: existing)
                try saveRemixIfRequested(
                    analyzedResult,
                    envelope: envelope,
                    source: existing,
                    context: context
                )
                if let videoFilename = envelope.sharedVideoFilename {
                    assetStore?.remove(filename: existing.sharedVideoFilename)
                    existing.sharedVideoFilename = videoFilename
                }
                if let thumbnailFilename = envelope.sharedThumbnailFilename,
                   let data = try assetStore?.data(filename: thumbnailFilename, maximumBytes: 10 * 1_024 * 1_024) {
                    existing.thumbnailData = data
                }
                if existing.sourceImportID == nil {
                    existing.sourceImportID = envelope.id
                }
                existing.updatedAt = max(existing.updatedAt, envelope.capturedAt)
                try context.save()
                try queueStore.remove(id: envelope.id)
                assetStore?.remove(filename: envelope.sharedThumbnailFilename)
                result.reopenedSourceIDs.append(existing.id)
                continue
            }

            let source = InspirationSource(
                workspaceID: workspaceID,
                canonicalURLString: canonicalURL.absoluteString,
                platform: InspirationLinkCanonicalizer.platform(for: canonicalURL),
                creatorObservation: envelope.creatorObservation,
                sourceImportID: envelope.id,
                createdAt: envelope.capturedAt
            )
            source.sourceCaption = envelope.sourceCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let analyzedResult = try applyAnalysis(from: envelope, to: source)
            source.sharedVideoFilename = envelope.sharedVideoFilename
            if let thumbnailFilename = envelope.sharedThumbnailFilename,
               let data = try assetStore?.data(filename: thumbnailFilename, maximumBytes: 10 * 1_024 * 1_024) {
                source.thumbnailData = data
            }
            context.insert(source)
            do {
                try saveRemixIfRequested(
                    analyzedResult,
                    envelope: envelope,
                    source: source,
                    context: context
                )
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            try queueStore.remove(id: envelope.id)
            assetStore?.remove(filename: envelope.sharedThumbnailFilename)
            existingSources.append(source)
            result.importedSourceIDs.append(source.id)
        }

        return result
    }

    private func resolvedWorkspaceID(
        hint: UUID?,
        fallback: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> UUID? {
        if let hint,
           workspaces.contains(where: { $0.id == hint && !$0.isArchived }) {
            return hint
        }
        return fallback
    }

    private func applyAnalysis(
        from envelope: InspirationShareEnvelope,
        to source: InspirationSource
    ) throws -> InspirationShapeResultWire? {
        if let title = envelope.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            source.sourceTitle = String(title.prefix(160))
        }
        if let transcript = envelope.sourceTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcript.isEmpty {
            source.sourceTranscript = String(transcript.prefix(20_000))
        }
        if let observations = envelope.visualObservations {
            source.visualObservations = Array(observations.prefix(20)).map {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
            }.filter { !$0.isEmpty }
        }
        if let analyzedInputs = envelope.analyzedInputs {
            source.analyzedInputs = analyzedInputs.compactMap(InspirationAnalyzedInputWire.init(rawValue:))
        }
        if let duration = envelope.sourceDurationSeconds, duration > 0, duration <= 21_600 {
            source.sourceDurationSeconds = duration
        }
        guard let resultJSON = envelope.shapeResultJSON,
              let data = resultJSON.data(using: .utf8) else {
            return nil
        }
        let result = try JSONDecoder.agentCy.decode(InspirationShapeResultWire.self, from: data)
        try InspirationShapeValidator.validate(result)
        source.shapePayloadJSON = resultJSON
        source.pillarID = result.suggestedPillarId
        // Re-sharing a source as "original only" must not hide or detach a
        // remix the creator already saved for that same canonical post.
        source.saveMode = source.linkedBriefID == nil
            ? (envelope.saveMode ?? .withRemix)
            : .withRemix
        source.status = .ready
        source.lastErrorCode = nil
        source.shapeOperationID = nil
        return result
    }

    private func saveRemixIfRequested(
        _ result: InspirationShapeResultWire?,
        envelope: InspirationShareEnvelope,
        source: InspirationSource,
        context: ModelContext
    ) throws {
        guard let result,
              (envelope.saveMode ?? .withRemix) == .withRemix,
              source.linkedBriefID == nil else { return }
        _ = try InspirationShapePersistenceCoordinator.save(
            InspirationEditableIdea(result: result),
            result: result,
            to: source,
            context: context
        )
    }
}
