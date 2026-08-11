import XCTest
@testable import AgentCy

final class RootRoutingTests: XCTestCase {
    func testExistingCreatorNeverSeesInviteBeforeCredentialCheckFinishes() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: false,
                hasInstallationCredential: false,
                hasLinkedAccount: false
            ),
            .launch
        )
    }

    func testUnresolvedStartupNeverShowsOnboardingBeforeStoredDataSettles() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: false,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: false,
                hasInstallationCredential: false,
                hasLinkedAccount: false
            ),
            .launch
        )
    }

    func testResolvedCreatorRoutesToAccountAccessOrApp() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: true,
                hasInstallationCredential: false,
                hasLinkedAccount: false
            ),
            .accountAccess
        )
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: true,
                hasInstallationCredential: true,
                hasLinkedAccount: true
            ),
            .app
        )
    }

    func testSignedInAccountWaitsForItsSyncedProfileInsteadOfStartingOver() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: false,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: true,
                hasInstallationCredential: true,
                hasLinkedAccount: true
            ),
            .restoringAccount
        )
    }
}
