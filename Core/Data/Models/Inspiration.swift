import Foundation
import SwiftData

@Model
final class Inspiration {
    var sourceType: InspirationSourceType
    var sourceURL: String?
    var sourceApp: String?
    var title: String?
    var notes: String?
    var mediaPath: String?
    var thumbnailPath: String?
    var voiceMemoPath: String?

    // AI
    var aiSummary: String?
    var tags: [String]

    var createdAt: Date

    // Relationships
    @Relationship var pillar: ContentPillar?
    @Relationship var board: InspirationBoard?

    init(
        sourceType: InspirationSourceType,
        sourceURL: String? = nil,
        title: String? = nil,
        notes: String? = nil
    ) {
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.title = title
        self.notes = notes
        self.tags = []
        self.createdAt = .now
    }
}

enum InspirationSourceType: String, Codable, CaseIterable {
    case link
    case image
    case video
    case text
    case screenshot
    case voiceMemo

    var icon: String {
        switch self {
        case .link: "link"
        case .image: "photo"
        case .video: "video"
        case .text: "doc.text"
        case .screenshot: "camera.viewfinder"
        case .voiceMemo: "mic"
        }
    }

    var displayName: String {
        switch self {
        case .voiceMemo: "Voice Memo"
        default: rawValue.capitalized
        }
    }
}

@Model
final class InspirationBoard {
    var name: String
    var coverImagePath: String?

    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Inspiration.board) var items: [Inspiration]
    @Relationship var pillar: ContentPillar?

    init(name: String) {
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.items = []
    }
}
