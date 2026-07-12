import XCTest
@testable import AgentCy

@MainActor
final class SubscriptionServiceTests: XCTestCase {
    func testUnavailableLiveServicePreservesFreeJourney() async {
        let state = SubscriptionState(access: .freeJourney)

        await UnavailableLiveSubscriptionService().refresh(state: state)

        XCTAssertEqual(state.access, .freeJourney)
    }

    func testUnavailableLiveServicePreservesOnlyUnexpiredPromotionalAccess() async {
        let service = UnavailableLiveSubscriptionService()
        let active = SubscriptionState(access: .comped, trialEnd: Date().addingTimeInterval(3_600))
        let expired = SubscriptionState(access: .comped, trialEnd: Date().addingTimeInterval(-3_600))
        let undated = SubscriptionState(access: .comped)

        await service.refresh(state: active)
        await service.refresh(state: expired)
        await service.refresh(state: undated)

        XCTAssertEqual(active.access, .comped)
        XCTAssertEqual(expired.access, .expired)
        XCTAssertEqual(undated.access, .expired)
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

    func testRuntimeFactoryNeverUsesPreviewForLiveAI() {
        XCTAssertTrue(SubscriptionServiceFactory.runtime(useLiveAI: true) is UnavailableLiveSubscriptionService)
    }

#if DEBUG
    func testRuntimeFactoryUsesPreviewOnlyForDebugNonLiveRuns() {
        XCTAssertTrue(SubscriptionServiceFactory.runtime(useLiveAI: false) is PreviewSubscriptionService)
    }
#endif
}
