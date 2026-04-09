import Foundation
import SwiftData

@Model
final class BrandDeal {
    var brandName: String
    var contactName: String?
    var contactEmail: String?
    var status: DealStatus
    var paymentAmount: Decimal?
    var paymentCurrency: String
    var paymentTerms: String?
    var contractURL: String?
    var notes: String?
    var startDate: Date?
    var endDate: Date?

    var createdAt: Date
    var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify) var deliverables: [ContentItem]
    @Relationship var pillar: ContentPillar?

    init(brandName: String, status: DealStatus = .pitched) {
        self.brandName = brandName
        self.status = status
        self.paymentCurrency = "USD"
        self.createdAt = .now
        self.updatedAt = .now
        self.deliverables = []
    }
}

enum DealStatus: String, Codable, CaseIterable {
    case pitched
    case negotiating
    case contracted
    case inProgress
    case delivered
    case paid
    case declined

    var displayName: String {
        switch self {
        case .inProgress: "In Progress"
        default: rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .pitched: "paperplane"
        case .negotiating: "bubble.left.and.bubble.right"
        case .contracted: "doc.text.magnifyingglass"
        case .inProgress: "arrow.triangle.2.circlepath"
        case .delivered: "checkmark.circle"
        case .paid: "dollarsign.circle.fill"
        case .declined: "xmark.circle"
        }
    }
}
