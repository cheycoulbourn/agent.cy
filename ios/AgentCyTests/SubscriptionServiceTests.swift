import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class SubscriptionServiceTests: XCTestCase {
    func testUnavailableLiveServicePreservesFreeJourney() async {
        let state = SubscriptionState(access: .freeJourney)

        await UnavailableLiveSubscriptionService().refresh(state: state)

        XCTAssertEqual(state.access, .freeJourney)
    }

    func testUnavailableLiveServicePreservesActiveAndLegacyUndatedPromotionalAccess() async {
        let service = UnavailableLiveSubscriptionService()
        let active = SubscriptionState(access: .comped, trialEnd: Date().addingTimeInterval(3_600))
        let expired = SubscriptionState(access: .comped, trialEnd: Date().addingTimeInterval(-3_600))
        let undated = SubscriptionState(access: .comped)

        await service.refresh(state: active)
        await service.refresh(state: expired)
        await service.refresh(state: undated)

        XCTAssertEqual(active.access, .comped)
        XCTAssertEqual(expired.access, .expired)
        XCTAssertEqual(undated.access, .comped)
    }

    func testUnavailableLiveServiceRejectsUnverifiedTrialAndPaidAccess() async {
        let service = UnavailableLiveSubscriptionService()
        let trial = SubscriptionState(access: .trial, trialEnd: Date().addingTimeInterval(3_600))
        let paid = SubscriptionState(access: .paid)

        await service.refresh(state: trial)
        await service.refresh(state: paid)

        XCTAssertEqual(trial.access, .expired)
        XCTAssertEqual(paid.access, .expired)
    }

    func testUnavailableLiveServiceCannotMintOrRestoreAccess() async {
        let service = UnavailableLiveSubscriptionService()
        let state = SubscriptionState(access: .freeJourney)

        do {
            try await service.startTrial(state: state)
            XCTFail("Expected trial creation to fail closed")
        } catch {
            XCTAssertEqual(error as? SubscriptionServiceError, .appStoreVerificationUnavailable)
        }
        XCTAssertEqual(state.access, .freeJourney)

        do {
            try await service.restore(state: state)
            XCTFail("Expected restore to fail closed")
        } catch {
            XCTAssertEqual(error as? SubscriptionServiceError, .appStoreVerificationUnavailable)
        }
        XCTAssertEqual(state.access, .freeJourney)
    }

#if DEBUG
    func testRuntimeFactoryFailsClosedForLiveDebugBuilds() {
        let service = SubscriptionServiceFactory.runtime(useLiveAI: true)
        XCTAssertTrue(service is UnavailableLiveSubscriptionService)
    }

    func testRuntimeFactoryUsesPreviewOnlyForDebugNonLiveRuns() {
        XCTAssertTrue(SubscriptionServiceFactory.runtime(useLiveAI: false) is PreviewSubscriptionService)
    }

    func testLiveDebugCredentialRefreshDoesNotExtendExpiredPromotionalAccess() async throws {
        let oldValue = ProcessInfo.processInfo.environment["AGENTCY_USE_LIVE_AI"]
        setenv("AGENTCY_USE_LIVE_AI", "1", 1)
        defer {
            if let oldValue {
                setenv("AGENTCY_USE_LIVE_AI", oldValue, 1)
            } else {
                unsetenv("AGENTCY_USE_LIVE_AI")
            }
        }

        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let originalEnd = Date().addingTimeInterval(-3_600)
        let state = SubscriptionState(access: .comped, trialEnd: originalEnd)
        context.insert(state)
        try context.save()

        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "c", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: originalEnd
        )
        let model = AppModel(
            credentialStore: PreviewCredentialStore(identity: identity),
            requiresInstallationInvite: true
        )

        await model.refreshInstallationCredentialStatus(context: context)

        XCTAssertEqual(state.access, .expired)
        XCTAssertEqual(state.trialEnd, originalEnd)
    }

    func testCredentialRefreshClearsStalePromotionalEndAfterPaidTransition() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let state = SubscriptionState(
            access: .comped,
            trialEnd: Date().addingTimeInterval(86_400)
        )
        context.insert(state)
        try context.save()

        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "p", count: 48),
            access: .paid,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let model = AppModel(
            credentialStore: PreviewCredentialStore(identity: identity),
            requiresInstallationInvite: true
        )

        await model.refreshInstallationCredentialStatus(context: context)

        XCTAssertEqual(state.access, .paid)
        XCTAssertNil(state.trialEnd)
    }
#else
    func testRuntimeFactoryFailsClosedWhenLivePurchaseVerificationIsUnavailable() {
        XCTAssertTrue(SubscriptionServiceFactory.runtime(useLiveAI: true) is UnavailableLiveSubscriptionService)
    }
#endif
}
