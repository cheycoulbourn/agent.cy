import Foundation
import SwiftData
import SwiftUI

@Model
final class ContentPillar {
    var name: String
    var pillarDescription: String
    var colorHex: String
    var iconName: String
    var targetPercentage: Double
    var sortOrder: Int
    var isActive: Bool

    var createdAt: Date
    var updatedAt: Date

    // Relationships
    @Relationship(inverse: \CreatorProfile.pillars) var profile: CreatorProfile?
    @Relationship(deleteRule: .nullify) var contentItems: [ContentItem]

    var color: Color {
        Color(hex: colorHex)
    }

    init(
        name: String,
        description: String = "",
        colorHex: String = "6C8EBF",
        iconName: String = "circle.fill",
        targetPercentage: Double = 25.0,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.pillarDescription = description
        self.colorHex = colorHex
        self.iconName = iconName
        self.targetPercentage = targetPercentage
        self.sortOrder = sortOrder
        self.isActive = true
        self.createdAt = .now
        self.updatedAt = .now
        self.contentItems = []
    }
}
