import Foundation
import SwiftData

struct SubscriptionOffering: Equatable, Sendable {
    let monthlyPrice: String
    let trialDays: Int
    let isPromotionalCohort: Bool
}

@MainActor
protocol SubscriptionServicing {
    var offering: SubscriptionOffering { get }
    /// False while App Store verification is not wired (pre-RevenueCat); the
    /// UI must not offer trial/restore actions that can only throw.
    var supportsPurchases: Bool { get }
    func refresh(state: SubscriptionState) async
    func startTrial(state: SubscriptionState) async throws
    func restore(state: SubscriptionState) async throws
}

enum SubscriptionServiceError: LocalizedError, Equatable {
    case appStoreVerificationUnavailable

    var errorDescription: String? {
        switch self {
        case .appStoreVerificationUnavailable:
            "App Store purchase verification is not available in this build yet. Your existing work remains available."
        }
    }
}

@MainActor
struct UnavailableLiveSubscriptionService: SubscriptionServicing {
    let offering = SubscriptionOffering(monthlyPrice: "$8.99", trialDays: 14, isPromotionalCohort: false)
    let supportsPurchases = false

    func refresh(state: SubscriptionState) async {
        let now = Date()
        let isVerifiedLocally: Bool
        switch state.access {
        case .freeJourney, .expired:
            isVerifiedLocally = true
        case .comped:
            // Older pilot credentials did not carry an end date. Preserve the
            // server-granted comped state instead of expiring those creators
            // locally; newer redemptions include a concrete promotional end.
            isVerifiedLocally = state.trialEnd.map { $0 > now } ?? true
        case .trial, .paid:
            isVerifiedLocally = false
        }

        guard !isVerifiedLocally, state.access != .expired else { return }
        state.access = .expired
        state.updatedAt = now
    }

    func startTrial(state: SubscriptionState) async throws {
        throw SubscriptionServiceError.appStoreVerificationUnavailable
    }

    func restore(state: SubscriptionState) async throws {
        throw SubscriptionServiceError.appStoreVerificationUnavailable
    }
}

enum SubscriptionServiceFactory {
    @MainActor
    static func runtime(useLiveAI: Bool) -> any SubscriptionServicing {
#if DEBUG
        if !useLiveAI { return PreviewSubscriptionService() }
#endif
        return UnavailableLiveSubscriptionService()
    }
}

/// Gives the creator a non-billing Pro entitlement while testing Local Cy in a
/// development build. Release builds never alter App Store or server access.
enum DevelopmentSubscriptionAccess {
    @MainActor
    static func applyLocalCyPro(context: ModelContext) {
#if DEBUG
        guard LocalCyPreferences.isEnabledAndConnected else { return }
        let descriptor = FetchDescriptor<SubscriptionState>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let state = try? context.fetch(descriptor).first else { return }
        state.access = .comped
        state.trialEnd = nil
        state.updatedAt = Date()
        try? context.save()
#endif
    }
}

@MainActor
struct PreviewSubscriptionService: SubscriptionServicing {
    let offering = SubscriptionOffering(monthlyPrice: "$8.99", trialDays: 14, isPromotionalCohort: true)
    let supportsPurchases = true

    func refresh(state: SubscriptionState) async {
        if state.access == .trial, let trialEnd = state.trialEnd, trialEnd < Date() {
            state.access = .expired
            state.updatedAt = Date()
        }
    }

    func startTrial(state: SubscriptionState) async throws {
        state.access = .trial
        state.trialEnd = Calendar.current.date(byAdding: .day, value: offering.trialDays, to: Date())
        state.updatedAt = Date()
    }

    func restore(state: SubscriptionState) async throws {
        // RevenueCat will replace this implementation. The offline build keeps current access unchanged.
        state.updatedAt = Date()
    }
}
