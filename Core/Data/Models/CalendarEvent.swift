import Foundation
import SwiftData

@Model
final class CalendarEvent {
    var title: String
    var eventType: CalendarEventType
    var scheduledAt: Date
    var externalEventID: String?

    var createdAt: Date
    var updatedAt: Date

    @Relationship var contentItem: ContentItem?
    @Relationship var brandDeal: BrandDeal?

    init(
        title: String,
        eventType: CalendarEventType = .post,
        scheduledAt: Date
    ) {
        self.title = title
        self.eventType = eventType
        self.scheduledAt = scheduledAt
        self.createdAt = .now
        self.updatedAt = .now
    }
}

enum CalendarEventType: String, Codable, CaseIterable {
    case post
    case story
    case reel
    case video
    case dealDeadline
    case meeting
    case other

    var displayName: String {
        switch self {
        case .dealDeadline: "Deal Deadline"
        default: rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .post: "square"
        case .story: "circle.dashed"
        case .reel: "film"
        case .video: "play.rectangle"
        case .dealDeadline: "exclamationmark.circle"
        case .meeting: "person.2"
        case .other: "calendar"
        }
    }
}
