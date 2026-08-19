import AuthenticationServices
import Security
import XCTest
@testable import AgentCy

@MainActor
final class PageRoot02Tests: XCTestCase {
    func testAccountAccessStatusPrioritizesCurrentProgressAndMarksErrorsUrgent() throws {
        let progress = AccountAccessStatus.resolve(
            isAuthorizing: true,
            notice: .error("An earlier attempt failed.")
        )
        let error = AccountAccessStatus.resolve(
            isAuthorizing: false,
            notice: .error("Sign in failed.")
        )
        let info = AccountAccessStatus.resolve(
            isAuthorizing: false,
            notice: .info("Account connected.")
        )

        XCTAssertEqual(progress, .progress("Connecting your workspace…"))
        XCTAssertEqual(error, .error("Sign in failed."))
        XCTAssertEqual(info, .info("Account connected."))
        XCTAssertFalse(try XCTUnwrap(progress).isUrgent)
        XCTAssertTrue(try XCTUnwrap(error).isUrgent)
        XCTAssertFalse(try XCTUnwrap(info).isUrgent)
        XCTAssertNil(AccountAccessStatus.resolve(isAuthorizing: false, notice: nil))
    }

    func testNonceGenerationMapsSecureBytesAndSurfacesGeneratorFailure() throws {
        let nonce = try AppleSignInNonce.make(length: 4) { bytes in
            bytes = [0, 1, 2, 3]
            return errSecSuccess
        }

        XCTAssertEqual(nonce, "0123")
        XCTAssertEqual(
            AppleSignInNonce.sha256(nonce),
            "1be2e452b46d7a0d9656bbb1f768e8248eba1b75baed65f5d99eafa948899a6a"
        )
        XCTAssertThrowsError(
            try AppleSignInNonce.make { _ in errSecNotAvailable }
        ) { error in
            guard case CredentialStoreError.keychain(errSecNotAvailable) = error else {
                return XCTFail("Expected the secure random error to be preserved.")
            }
        }
    }

    func testAppleCancellationIsSilentButOtherAuthorizationErrorsAreNot() {
        let cancelled = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )
        let failed = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.failed.rawValue
        )

        XCTAssertTrue(AppleAccountAuthorizationPolicy.isCancellation(cancelled))
        XCTAssertFalse(AppleAccountAuthorizationPolicy.isCancellation(failed))
        XCTAssertFalse(AppleAccountAuthorizationPolicy.isCancellation(CocoaError(.fileReadUnknown)))
    }

    func testAppleCompletionRequiresTokenCodeAndNonceBeforeAuthorization() {
        let expected = Self.authorizationMaterial

        let complete = AppleAccountAuthorizationPolicy.material(
            identityTokenData: Data(expected.identityToken.utf8),
            authorizationCodeData: Data(expected.authorizationCode.utf8),
            nonce: expected.nonce,
            appleUserID: expected.appleUserID
        )
        let missingToken = AppleAccountAuthorizationPolicy.material(
            identityTokenData: nil,
            authorizationCodeData: Data(expected.authorizationCode.utf8),
            nonce: expected.nonce,
            appleUserID: expected.appleUserID
        )
        let missingCode = AppleAccountAuthorizationPolicy.material(
            identityTokenData: Data(expected.identityToken.utf8),
            authorizationCodeData: nil,
            nonce: expected.nonce,
            appleUserID: expected.appleUserID
        )
        let missingNonce = AppleAccountAuthorizationPolicy.material(
            identityTokenData: Data(expected.identityToken.utf8),
            authorizationCodeData: Data(expected.authorizationCode.utf8),
            nonce: nil,
            appleUserID: expected.appleUserID
        )

        XCTAssertEqual(complete, expected)
        XCTAssertNil(missingToken)
        XCTAssertNil(missingCode)
        XCTAssertNil(missingNonce)
    }

    func testAuthorizationFailureReturnsToRetryableIdleState() async {
        let authorizer = ImmediateAccountAuthorizer(
            result: Self.linkedIdentity(),
            failureStatus: 503
        )
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            accountAuthorizationClient: authorizer,
            requiresInstallationInvite: true
        )

        let result = await model.authorizeAppleAccount(Self.authorizationMaterial)
        let endpoints = await authorizer.endpoints()

        XCTAssertFalse(result)
        XCTAssertEqual(endpoints, [.signIn])
        XCTAssertFalse(model.isAuthorizingAccount)
        XCTAssertTrue(model.isInstallationCredentialStatusResolved)
        XCTAssertFalse(model.hasInstallationCredential)
        XCTAssertFalse(model.hasLinkedAccount)
        XCTAssertEqual(
            model.notice,
            .error("Cy is unavailable right now. Your work is saved.")
        )
    }

    func testStoredInstallationLinksInsteadOfCreatingAnotherDeviceIdentity() async {
        let storedIdentity = InstallationIdentity(
            installationID: UUID(uuidString: "456B30D3-B9D4-427F-AEEE-93B9B8E54F45")!,
            credential: String(repeating: "a", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let authorizer = ImmediateAccountAuthorizer(result: Self.linkedIdentity())
        let model = AppModel(
            credentialStore: PreviewCredentialStore(identity: storedIdentity),
            accountAuthorizationClient: authorizer,
            requiresInstallationInvite: true
        )

        let result = await model.authorizeAppleAccount(Self.authorizationMaterial)
        let endpoints = await authorizer.endpoints()

        XCTAssertTrue(result)
        XCTAssertEqual(endpoints, [.link])
        XCTAssertTrue(model.hasInstallationCredential)
        XCTAssertTrue(model.hasLinkedAccount)
    }

    func testMissingInstallationSignsInAndPublishesRootExitState() async {
        let identity = Self.linkedIdentity()
        let authorizer = ImmediateAccountAuthorizer(result: identity)
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            accountAuthorizationClient: authorizer,
            requiresInstallationInvite: true
        )

        let result = await model.authorizeAppleAccount(Self.authorizationMaterial)
        let endpoints = await authorizer.endpoints()
        let restoringDestination = RootDestination.resolve(
            hasProfile: false,
            requiresInstallationInvite: model.requiresInstallationInvite,
            isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
            hasInstallationCredential: model.hasInstallationCredential,
            hasLinkedAccount: model.hasLinkedAccount
        )
        let existingProfileDestination = RootDestination.resolve(
            hasProfile: true,
            requiresInstallationInvite: model.requiresInstallationInvite,
            isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
            hasInstallationCredential: model.hasInstallationCredential,
            hasLinkedAccount: model.hasLinkedAccount
        )

        XCTAssertTrue(result)
        XCTAssertEqual(endpoints, [.signIn])
        XCTAssertFalse(model.isAuthorizingAccount)
        XCTAssertTrue(model.isInstallationCredentialStatusResolved)
        XCTAssertTrue(model.hasInstallationCredential)
        XCTAssertTrue(model.hasLinkedAccount)
        XCTAssertEqual(
            model.notice,
            .info("Your Apple account is connected. Your local work is still here.")
        )
        XCTAssertEqual(restoringDestination, .restoringAccount)
        XCTAssertEqual(existingProfileDestination, .app)
    }

    func testAuthorizationIgnoresDuplicateAttemptUntilOriginalRequestFinishes() async {
        let identity = Self.linkedIdentity()
        let authorizer = FirstRequestSuspendingAccountAuthorizer(result: identity)
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            accountAuthorizationClient: authorizer,
            requiresInstallationInvite: true
        )

        let firstAttempt = Task {
            await model.authorizeAppleAccount(Self.authorizationMaterial)
        }
        for _ in 0..<100 {
            if await authorizer.requestCount() == 1 { break }
            await Task.yield()
        }

        XCTAssertTrue(model.isAuthorizingAccount)

        let duplicateResult = await model.authorizeAppleAccount(Self.authorizationMaterial)
        let countAfterDuplicate = await authorizer.requestCount()
        await authorizer.finishFirstRequest()
        let firstResult = await firstAttempt.value

        XCTAssertFalse(duplicateResult)
        XCTAssertEqual(countAfterDuplicate, 1)
        XCTAssertTrue(firstResult)
        XCTAssertFalse(model.isAuthorizingAccount)
        XCTAssertTrue(model.hasInstallationCredential)
        XCTAssertTrue(model.hasLinkedAccount)
    }

    private static let authorizationMaterial = AppleAuthorizationMaterial(
        identityToken: "header.payload.signature",
        authorizationCode: "authorization-code",
        nonce: "raw-nonce-with-at-least-thirty-two-characters",
        appleUserID: "apple-user-id"
    )

    private static func linkedIdentity() -> InstallationIdentity {
        InstallationIdentity(
            installationID: UUID(uuidString: "456B30D3-B9D4-427F-AEEE-93B9B8E54F45")!,
            credential: String(repeating: "a", count: 48),
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil,
            accountID: UUID(uuidString: "B40785BF-47A7-42E7-879D-5D1F10E6F4F4")!,
            appleUserID: "apple-user-id"
        )
    }
}

private enum PageRoot02AuthorizationEndpoint: Equatable {
    case link
    case signIn
}

private actor ImmediateAccountAuthorizer: AccountAuthorizing {
    private let result: InstallationIdentity
    private let failureStatus: Int?
    private var recordedEndpoints: [PageRoot02AuthorizationEndpoint] = []

    init(result: InstallationIdentity, failureStatus: Int? = nil) {
        self.result = result
        self.failureStatus = failureStatus
    }

    func link(
        _ material: AppleAuthorizationMaterial,
        to identity: InstallationIdentity
    ) async throws -> InstallationIdentity {
        recordedEndpoints.append(.link)
        return try outcome()
    }

    func signIn(_ material: AppleAuthorizationMaterial) async throws -> InstallationIdentity {
        recordedEndpoints.append(.signIn)
        return try outcome()
    }

    func endpoints() -> [PageRoot02AuthorizationEndpoint] {
        recordedEndpoints
    }

    private func outcome() throws -> InstallationIdentity {
        if let failureStatus {
            throw AgentCyAPIError.http(failureStatus)
        }
        return result
    }
}

private actor FirstRequestSuspendingAccountAuthorizer: AccountAuthorizing {
    private let result: InstallationIdentity
    private var calls = 0
    private var firstContinuation: CheckedContinuation<InstallationIdentity, Never>?

    init(result: InstallationIdentity) {
        self.result = result
    }

    func link(
        _ material: AppleAuthorizationMaterial,
        to identity: InstallationIdentity
    ) async throws -> InstallationIdentity {
        try await authorize()
    }

    func signIn(_ material: AppleAuthorizationMaterial) async throws -> InstallationIdentity {
        try await authorize()
    }

    func requestCount() -> Int {
        calls
    }

    func finishFirstRequest() {
        firstContinuation?.resume(returning: result)
        firstContinuation = nil
    }

    private func authorize() async throws -> InstallationIdentity {
        calls += 1
        guard calls == 1 else { return result }
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }
}
