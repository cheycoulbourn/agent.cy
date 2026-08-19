import Foundation
import SwiftData

enum PillarRemovalService {
    @MainActor
    static func remove(
        _ pillar: Pillar,
        pillars: [Pillar],
        briefs: [CreativeBrief],
        tasks: [CreatorTask],
        context: ModelContext
    ) throws {
        let removedIDs = IDsRemoved(with: pillar, pillars: pillars)

        for item in pillars where removedIDs.contains(item.id) {
            item.isArchived = true
        }
        for brief in briefs where brief.pillarID.map(removedIDs.contains) == true {
            brief.pillarID = nil
        }
        for task in tasks where task.pillarID.map(removedIDs.contains) == true {
            task.pillarID = nil
        }

        try context.save()
    }

    static func IDsRemoved(with pillar: Pillar, pillars: [Pillar]) -> Set<UUID> {
        guard pillar.parentPillarID == nil else { return [pillar.id] }
        return Set([pillar.id] + pillars.filter { $0.parentPillarID == pillar.id }.map(\.id))
    }
}

enum PillarAnchorPromotionService {
    /// Promotes an existing secondary pillar without replacing its record.
    /// Content keeps pointing at the same pillar IDs; only the hierarchy changes.
    @discardableResult
    static func promote(_ candidate: Pillar, pillars: [Pillar]) -> Bool {
        guard !candidate.isArchived, candidate.role == .supporting else { return false }

        guard let currentAnchor = pillars.first(where: {
            !$0.isArchived && $0.id != candidate.id && $0.parentPillarID == nil && $0.role == .anchor
        }) ?? pillars.first(where: {
            !$0.isArchived && $0.id != candidate.id && $0.parentPillarID == nil
        }) else { return false }

        candidate.role = .anchor
        candidate.parentPillarID = nil

        for pillar in pillars where pillar.id != candidate.id {
            if pillar.id == currentAnchor.id || pillar.parentPillarID == currentAnchor.id {
                pillar.role = .supporting
                pillar.parentPillarID = candidate.id
            }
        }

        return true
    }
}
