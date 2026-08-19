import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class RootRoutingTests: XCTestCase {
    func testInvitationDisabledNewCreatorStartsOnboarding() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: false,
                requiresInstallationInvite: false,
                isInstallationCredentialStatusResolved: false,
                hasInstallationCredential: false,
                hasLinkedAccount: false
            ),
            .onboarding
        )
    }

    func testInvitationDisabledExistingCreatorStartsApp() {
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: false,
                isInstallationCredentialStatusResolved: false,
                hasInstallationCredential: false,
                hasLinkedAccount: false
            ),
            .app
        )
    }

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

    func testValidUnlinkedInstallationStartsOnboarding() async {
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "v", count: 48),
            access: .comped,
            credentialExpiresAt: Date().addingTimeInterval(3_600),
            promotionalEntitlementEndsAt: nil
        )
        let model = AppModel(
            credentialStore: PreviewCredentialStore(identity: identity),
            requiresInstallationInvite: true
        )

        await model.refreshInstallationCredentialStatus()

        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: false,
                requiresInstallationInvite: model.requiresInstallationInvite,
                isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
                hasInstallationCredential: model.hasInstallationCredential,
                hasLinkedAccount: model.hasLinkedAccount
            ),
            .onboarding
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

    func testExpiredLinkedCredentialReturnsToAccountAccess() async {
        let identity = InstallationIdentity(
            installationID: UUID(),
            credential: String(repeating: "e", count: 48),
            access: .comped,
            credentialExpiresAt: Date().addingTimeInterval(-1),
            promotionalEntitlementEndsAt: nil,
            accountID: UUID()
        )
        let model = AppModel(
            credentialStore: PreviewCredentialStore(identity: identity),
            requiresInstallationInvite: true
        )

        await model.refreshInstallationCredentialStatus()

        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: model.requiresInstallationInvite,
                isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
                hasInstallationCredential: model.hasInstallationCredential,
                hasLinkedAccount: model.hasLinkedAccount
            ),
            .accountAccess
        )
    }

    func testCredentialLoadFailureFailsClosedToAccountAccess() async {
        let model = AppModel(
            credentialStore: FailingRootCredentialStore(),
            requiresInstallationInvite: true
        )

        await model.refreshInstallationCredentialStatus()

        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: model.requiresInstallationInvite,
                isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
                hasInstallationCredential: model.hasInstallationCredential,
                hasLinkedAccount: model.hasLinkedAccount
            ),
            .accountAccess
        )
    }

    func testProfileArrivalMovesLinkedAccountFromRestoreToApp() {
        let restoring = RootDestination.resolve(
            hasProfile: false,
            requiresInstallationInvite: true,
            isInstallationCredentialStatusResolved: true,
            hasInstallationCredential: true,
            hasLinkedAccount: true
        )
        let restored = RootDestination.resolve(
            hasProfile: true,
            requiresInstallationInvite: true,
            isInstallationCredentialStatusResolved: true,
            hasInstallationCredential: true,
            hasLinkedAccount: true
        )

        XCTAssertEqual([restoring, restored], [.restoringAccount, .app])
    }

    func testRestoredProfileStillRoutesToAppAfterStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentCyRootRoutingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("AgentCy.store")

        do {
            let container = try ModelContainerFactory.makeLocal(at: storeURL)
            container.mainContext.insert(
                CreatorProfile(
                    name: "Restored creator",
                    goal: "Keep creating",
                    adultConfirmed: true,
                    onboardingCompleted: true
                )
            )
            try container.mainContext.save()
        }

        let reopened = try ModelContainerFactory.makeLocal(at: storeURL)
        let hasProfile = try !reopened.mainContext.fetch(FetchDescriptor<CreatorProfile>()).isEmpty

        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: hasProfile,
                requiresInstallationInvite: true,
                isInstallationCredentialStatusResolved: true,
                hasInstallationCredential: true,
                hasLinkedAccount: true
            ),
            .app
        )
    }

    #if DEBUG
    func testRuntimeFixtureProvidesRestoreAndProfileArrivalScenarios() {
        XCTAssertEqual(
            RootRuntimeFixture.resolve(
                arguments: ["agent.cy", "-agentCyRootFixture", "restoringAccount"]
            ),
            .restoringAccount
        )
        XCTAssertEqual(
            RootRuntimeFixture.resolve(
                arguments: ["agent.cy", "-agentCyRootFixture", "restoringThenApp"]
            ),
            .restoringThenApp
        )
    }
    #endif
}

private actor FailingRootCredentialStore: InstallationCredentialStoring {
    func load() throws -> InstallationIdentity? {
        throw CocoaError(.fileReadNoPermission)
    }

    func save(_ identity: InstallationIdentity) {}
    func delete() {}
}
