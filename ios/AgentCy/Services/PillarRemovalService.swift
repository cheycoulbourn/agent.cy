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
