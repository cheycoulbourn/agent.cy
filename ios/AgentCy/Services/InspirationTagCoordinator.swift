import Foundation
import SwiftData

enum InspirationTagError: Error, LocalizedError {
    case invalidName
    case tooManyTags

    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a tag name between 1 and 40 characters."
        case .tooManyTags: "A saved post can have up to 20 tags."
        }
    }
}

@MainActor
enum InspirationTagCoordinator {
    @discardableResult
    static func assign(
        name rawName: String,
        to source: InspirationSource,
        context: ModelContext
    ) throws -> InspirationTag {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw InspirationTagError.invalidName }
        let normalized = InspirationTag.normalize(name)
        let tags = try context.fetch(FetchDescriptor<InspirationTag>())
        let tag = tags.first {
            $0.workspaceID == source.workspaceID && $0.normalizedName == normalized
        } ?? InspirationTag(workspaceID: source.workspaceID, name: name)
        if tag.modelContext == nil { context.insert(tag) }
        guard source.tagIDs.contains(tag.id) || source.tagIDs.count < 20 else {
            throw InspirationTagError.tooManyTags
        }
        if !source.tagIDs.contains(tag.id) {
            source.tagIDs.append(tag.id)
        }
        source.updatedAt = Date()
        try context.save()
        return tag
    }

    static func toggle(
        _ tag: InspirationTag,
        on source: InspirationSource,
        context: ModelContext
    ) throws {
        var ids = source.tagIDs
        if let index = ids.firstIndex(of: tag.id) {
            ids.remove(at: index)
        } else {
            guard ids.count < 20 else { throw InspirationTagError.tooManyTags }
            ids.append(tag.id)
        }
        source.tagIDs = ids
        source.updatedAt = Date()
        try context.save()
    }
}
