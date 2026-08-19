import CloudKit
import XCTest
@testable import AgentCy

@MainActor
final class PageRoot04Tests: XCTestCase {
    func testLocalOnlyFallbackNeverClaimsICloudRestorationIsActive() {
        let presentation = AccountRestorePresentation.resolve(
            syncState: .localOnlyFallback,
            hasExceededDelay: false
        )

        XCTAssertEqual(presentation.phase, .unavailable)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertFalse(presentation.offersRetry)
        XCTAssertTrue(presentation.offersAccountRecovery)
        XCTAssertFalse(presentation.message.localizedCaseInsensitiveContains("arrive from iCloud"))
    }

    func testOfflineAndUnavailableStatesExposeRetryAndAccountRecovery() {
        let offline = AccountRestorePresentation.resolve(
            syncState: .offline,
            hasExceededDelay: false
        )
        let unavailable = AccountRestorePresentation.resolve(
            syncState: .cloudUnavailable,
            hasExceededDelay: false
        )

        XCTAssertEqual(offline.phase, .offline)
        XCTAssertEqual(unavailable.phase, .unavailable)
        for presentation in [offline, unavailable] {
            XCTAssertFalse(presentation.showsProgress)
            XCTAssertTrue(presentation.offersRetry)
            XCTAssertTrue(presentation.offersAccountRecovery)
        }
    }

    func testActiveRestoreBecomesDelayedAfterTheBoundedWait() {
        let active = AccountRestorePresentation.resolve(
            syncState: .available,
            hasExceededDelay: false
        )
        let delayed = AccountRestorePresentation.resolve(
            syncState: .available,
            hasExceededDelay: true
        )

        XCTAssertEqual(AccountRestorePresentation.delayedAfterSeconds, 15)
        XCTAssertEqual(active.phase, .restoring)
        XCTAssertTrue(active.showsProgress)
        XCTAssertFalse(active.offersRetry)
        XCTAssertFalse(active.offersAccountRecovery)
        XCTAssertEqual(delayed.phase, .delayed)
        XCTAssertFalse(delayed.showsProgress)
        XCTAssertTrue(delayed.offersRetry)
        XCTAssertTrue(delayed.offersAccountRecovery)
    }

    func testRestoreStatusHasNamedAccessibilityStateAndBoundedMotion() {
        let checking = AccountRestorePresentation.resolve(
            syncState: .checking,
            hasExceededDelay: false
        )
        let active = AccountRestorePresentation.resolve(
            syncState: .available,
            hasExceededDelay: false
        )

        XCTAssertEqual(active.accessibilityLabel, "Workspace restoration status")
        XCTAssertEqual(active.accessibilityValue, "Restoring from iCloud")
        XCTAssertEqual(checking.phase, .checking)
        XCTAssertFalse(checking.animatesAsterisk(reduceMotion: false))
        XCTAssertTrue(active.animatesAsterisk(reduceMotion: false))
        XCTAssertFalse(active.animatesAsterisk(reduceMotion: true))
    }

    func testCloudCheckClassifiesAvailableOfflineAndUnavailableStates() {
        XCTAssertEqual(
            AccountRestoreSyncPolicy.resolve(
                localOnlyFallback: true,
                accountStatus: .available,
                error: nil
            ),
            .localOnlyFallback
        )
        XCTAssertEqual(
            AccountRestoreSyncPolicy.resolve(
                localOnlyFallback: false,
                accountStatus: .available,
                error: nil
            ),
            .available
        )
        XCTAssertEqual(
            AccountRestoreSyncPolicy.resolve(
                localOnlyFallback: false,
                accountStatus: .noAccount,
                error: nil
            ),
            .cloudUnavailable
        )
        XCTAssertEqual(
            AccountRestoreSyncPolicy.resolve(
                localOnlyFallback: false,
                accountStatus: nil,
                error: URLError(.notConnectedToInternet)
            ),
            .offline
        )
    }

    func testLiveConnectivityOverridesACachedAvailableCloudStatus() {
        XCTAssertEqual(
            AccountRestoreSyncPolicy.effectiveState(
                cloudState: .available,
                connectivity: .offline
            ),
            .offline
        )
        XCTAssertEqual(
            AccountRestoreSyncPolicy.effectiveState(
                cloudState: .available,
                connectivity: .online
            ),
            .available
        )
    }

    #if DEBUG
    func testRuntimeFixturesCoverEveryRestorePresentationState() {
        let fixtureArguments = [
            "active": AccountRestoreSyncState.available,
            "offline": .offline,
            "unavailable": .cloudUnavailable,
            "fallback": .localOnlyFallback,
            "delayed": .available
        ]

        for (rawValue, expectedState) in fixtureArguments {
            let fixture = AccountRestoreRuntimeFixture.resolve(
                arguments: [
                    "agent.cy",
                    "-agentCyAccountRestoreFixture",
                    rawValue
                ]
            )
            XCTAssertEqual(fixture?.syncState, expectedState)
        }
        XCTAssertTrue(AccountRestoreRuntimeFixture.delayed.startsDelayed)
        XCTAssertFalse(AccountRestoreRuntimeFixture.active.startsDelayed)
    }
    #endif

    func testAccountRecoverySignsOutWithoutCreatingAReplacementProfile() async {
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "r", count: 48),
            access: .comped,
            credentialExpiresAt: Date().addingTimeInterval(3_600),
            promotionalEntitlementEndsAt: nil,
            accountID: UUID()
        )
        let credentialStore = PreviewCredentialStore(identity: identity)
        let model = AppModel(
            credentialStore: credentialStore,
            requiresInstallationInvite: true
        )

        await model.refreshInstallationCredentialStatus()
        await model.signOutOfAccount(
            successMessage: "Signed out of this device."
        )
        let storedIdentity = await credentialStore.load()

        XCTAssertFalse(model.hasInstallationCredential)
        XCTAssertFalse(model.hasLinkedAccount)
        XCTAssertNil(storedIdentity)
        XCTAssertEqual(model.notice, .info("Signed out of this device."))
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: false,
                requiresInstallationInvite: model.requiresInstallationInvite,
                isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
                hasInstallationCredential: model.hasInstallationCredential,
                hasLinkedAccount: model.hasLinkedAccount
            ),
            .accountAccess
        )
    }
}
