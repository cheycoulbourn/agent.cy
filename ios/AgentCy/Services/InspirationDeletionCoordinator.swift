import Foundation
import SwiftData

@MainActor
enum InspirationDeletionCoordinator {
    static func delete(
        _ source: InspirationSource,
        context: ModelContext,
        assetStore: InspirationSharedAssetStore? = try? InspirationSharedAssetStore()
    ) throws {
        let sourceID = source.id
        let sharedVideoFilename = source.sharedVideoFilename
        let linkedBriefs = try context.fetch(FetchDescriptor<CreativeBrief>())
            .filter { $0.inspirationSourceID == sourceID }

        linkedBriefs.forEach { $0.inspirationSourceID = nil }
        context.delete(source)

        do {
            try context.save()
            assetStore?.remove(filename: sharedVideoFilename)
        } catch {
            context.rollback()
            throw error
        }
    }
}
