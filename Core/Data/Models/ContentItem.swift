import Foundation
import SwiftData

@Model
final class ContentItem {
    var title: String
    var caption: String?
    var hooks: [String]
    var hashtags: [String]
    var notes: String?

    // Classification
    var status: ContentStatus
    var format: ContentFormat
    var platforms: [SocialPlatform]

    // Media
    var mediaPaths: [String]

    // Scheduling
    var scheduledDate: Date?
    var publishedDate: Date?

    // Collaboration
    var collaborators: [String]
    var isBrandCollab: Bool
    var brandName: String?

    // AI
    var aiGenerated: Bool
    var aiSuggestions: [String]

    var createdAt: Date
    var updatedAt: Date

    // Relationships
    @Relationship(inverse: \ContentPillar.contentItems) var pillar: ContentPillar?
    @Relationship var inspiration: Inspiration?
    @Relationship(inverse: \BrandDeal.deliverables) var brandDeal: BrandDeal?

    init(
        title: String,
        status: ContentStatus = .captured,
        format: ContentFormat = .post,
        platforms: [SocialPlatform] = []
    ) {
        self.title = title
        self.status = status
        self.format = format
        self.platforms = platforms
        self.caption = nil
        self.hooks = []
        self.hashtags = []
        self.notes = nil
        self.mediaPaths = []
        self.scheduledDate = nil
        self.publishedDate = nil
        self.collaborators = []
        self.isBrandCollab = false
        self.aiGenerated = false
        self.aiSuggestions = []
        self.createdAt = .now
        self.updatedAt = .now
    }
}

enum ContentFormat: String, Codable, CaseIterable {
    case post
    case reel
    case carousel
    case story
    case thread
    case longformVideo = "Long-form Video"
    case shortVideo = "Short Video"
    case pin
    case live

    var displayName: String {
        switch self {
        case .longformVideo: "Long-form Video"
        case .shortVideo: "Short Video"
        default: rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .post: "square"
        case .reel: "film"
        case .carousel: "rectangle.stack"
        case .story: "circle.dashed"
        case .thread: "text.alignleft"
        case .longformVideo: "play.rectangle"
        case .shortVideo: "video"
        case .pin: "pin"
        case .live: "antenna.radiowaves.left.and.right"
        }
    }
}
