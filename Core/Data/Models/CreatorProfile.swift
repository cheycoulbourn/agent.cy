import Foundation
import SwiftData

@Model
final class CreatorProfile {
    var displayName: String
    var handle: String
    var avatarPath: String?
    var niche: String
    var subNiches: [String]

    // Brand voice
    var voiceAdjectives: [String]
    var voiceSamples: [String]
    var voiceDescription: String?

    // Goals
    var primaryGoal: CreatorGoal
    var weeklyPostTarget: Int
    var targetAudience: String?

    // Status
    var onboardingCompleted: Bool

    var createdAt: Date
    var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .cascade) var pillars: [ContentPillar]
    @Relationship(deleteRule: .cascade) var platformAccounts: [PlatformAccount]

    init(
        displayName: String,
        handle: String = "",
        niche: String = "",
        subNiches: [String] = [],
        voiceAdjectives: [String] = [],
        voiceSamples: [String] = [],
        primaryGoal: CreatorGoal = .growAudience,
        weeklyPostTarget: Int = 3
    ) {
        self.displayName = displayName
        self.handle = handle
        self.niche = niche
        self.subNiches = subNiches
        self.voiceAdjectives = voiceAdjectives
        self.voiceSamples = voiceSamples
        self.primaryGoal = primaryGoal
        self.weeklyPostTarget = weeklyPostTarget
        self.onboardingCompleted = false
        self.createdAt = .now
        self.updatedAt = .now
        self.pillars = []
        self.platformAccounts = []
    }
}

enum CreatorGoal: String, Codable, CaseIterable {
    case growAudience = "Grow Audience"
    case monetize = "Monetize"
    case buildCommunity = "Build Community"
    case launchProduct = "Launch Product"
    case all = "All of the Above"

    var icon: String {
        switch self {
        case .growAudience: "chart.line.uptrend.xyaxis"
        case .monetize: "dollarsign.circle"
        case .buildCommunity: "person.3"
        case .launchProduct: "rocket"
        case .all: "star"
        }
    }
}
