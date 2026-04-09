import Foundation
import Observation

enum SubscriptionTier: String, Codable {
    case free
    case pro
    case studio
}

struct EntitlementLimits {
    let maxPillars: Int
    let maxCapturesPerMonth: Int
    let maxAIExpansionsPerMonth: Int
    let maxAIMessagesPerDay: Int
    let hasFullCalendar: Bool
    let hasBrandDeals: Bool
    let hasCalendarSync: Bool
    let hasAnalytics: Bool
    let maxInspoBoards: Int
    let showsWatermark: Bool

    static let free = EntitlementLimits(
        maxPillars: 3,
        maxCapturesPerMonth: 20,
        maxAIExpansionsPerMonth: 5,
        maxAIMessagesPerDay: 10,
        hasFullCalendar: false,
        hasBrandDeals: false,
        hasCalendarSync: false,
        hasAnalytics: false,
        maxInspoBoards: 1,
        showsWatermark: true
    )

    static let pro = EntitlementLimits(
        maxPillars: .max,
        maxCapturesPerMonth: .max,
        maxAIExpansionsPerMonth: .max,
        maxAIMessagesPerDay: .max,
        hasFullCalendar: true,
        hasBrandDeals: true,
        hasCalendarSync: true,
        hasAnalytics: true,
        maxInspoBoards: .max,
        showsWatermark: false
    )

    static let studio = EntitlementLimits(
        maxPillars: .max,
        maxCapturesPerMonth: .max,
        maxAIExpansionsPerMonth: .max,
        maxAIMessagesPerDay: .max,
        hasFullCalendar: true,
        hasBrandDeals: true,
        hasCalendarSync: true,
        hasAnalytics: true,
        maxInspoBoards: .max,
        showsWatermark: false
    )
}

@Observable
final class SubscriptionManager {
    var currentTier: SubscriptionTier = .free

    var limits: EntitlementLimits {
        switch currentTier {
        case .free: .free
        case .pro: .pro
        case .studio: .studio
        }
    }

    var isPremium: Bool {
        currentTier != .free
    }

    func purchase(tier: SubscriptionTier) async throws {
        // TODO: Integrate RevenueCat
        currentTier = tier
    }

    func restorePurchases() async throws {
        // TODO: Integrate RevenueCat restore
    }
}
