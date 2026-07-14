import XCTest
@testable import AgentCy

final class RootRoutingTests: XCTestCase {
    func testExistingCreatorNeverSeesInviteBeforeCredentialCheckFinishes() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: false,
                hasInstallationCredential: false
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
                hasInstallationCredential: false
            ),
            .launch
        )
    }

    func testResolvedCreatorRoutesToInviteOrApp() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: true,
                hasInstallationCredential: false
            ),
            .installationInvite
        )
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: true,
                hasInstallationCredential: true
            ),
            .app
        )
    }
}
