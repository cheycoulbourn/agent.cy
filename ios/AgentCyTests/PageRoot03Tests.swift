import Foundation
import Security
import XCTest
@testable import AgentCy

@MainActor
final class PageRoot03Tests: XCTestCase {
    func testInvitationInputExplainsIncompleteAndTooLongCodesAndNormalizesValidInput() {
        XCTAssertEqual(
            InstallationInviteInput.resolve("   "),
            .invalid("Enter the complete invitation code.")
        )
        XCTAssertEqual(
            InstallationInviteInput.resolve("ABC"),
            .invalid("Enter the complete invitation code.")
        )
        XCTAssertEqual(
            InstallationInviteInput.resolve(String(repeating: "A", count: 129)),
            .invalid("The invitation code is too long.")
        )
        XCTAssertEqual(
            InstallationInviteInput.resolve("  PILOT-123  "),
            .valid("PILOT-123")
        )
        let keyboardSubmit = InstallationInviteInput.consumeSubmitMarker(
            in: "PAGE-ROOT-03-VALID\n"
        )
        XCTAssertEqual(keyboardSubmit.code, "PAGE-ROOT-03-VALID")
        XCTAssertTrue(keyboardSubmit.shouldSubmit)
    }

    func testInvitationStatusDistinguishesPoliteProgressFromUrgentFailure() throws {
        let progress = InstallationInviteStatus.progress("Checking your invitation…")
        let error = InstallationInviteStatus.error("Check the code and try again.")

        XCTAssertEqual(progress.message, "Checking your invitation…")
        XCTAssertTrue(progress.showsProgress)
        XCTAssertFalse(progress.isUrgent)
        XCTAssertFalse(error.showsProgress)
        XCTAssertTrue(error.isUrgent)
        XCTAssertNil(InstallationInviteStatus.idle.message)
    }

    func testInvalidInvitationUsesPageSpecificStatusWithoutChangingAccountNotice() async {
        let redeemer = ImmediateInstallationRedeemer(
            error: AIWireError(
                code: .installationInvalid,
                message: "That invitation is invalid or has already been used.",
                retryable: false,
                retryAfterSeconds: nil,
                quotaScope: nil,
                fieldIssues: nil
            )
        )
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            installationRedemptionClient: redeemer,
            requiresInstallationInvite: true
        )
        model.notice = .error("Account sign-in failed.")

        let outcome = await model.redeemInstallationInvite("WRONG1")

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(
            model.installationInviteStatus,
            .error("That invitation is invalid or has already been used. Check the code or ask for a new one.")
        )
        XCTAssertEqual(model.notice, .error("Account sign-in failed."))
        XCTAssertFalse(model.isRedeemingInvite)
        XCTAssertFalse(model.hasInstallationCredential)
    }

    func testInvitationErrorsGiveActionableCopyWithoutClaimingWorkWasSaved() {
        let expired = InstallationInviteErrorMapper.message(
            for: AgentCyAPIError.server(
                Self.wireError(
                    code: .installationInvalid,
                    message: "That invitation has expired."
                )
            )
        )
        let rateLimited = InstallationInviteErrorMapper.message(
            for: AgentCyAPIError.server(
                Self.wireError(
                    code: .rateLimited,
                    message: "Too many invitation attempts.",
                    retryable: true,
                    retryAfterSeconds: 600
                )
            )
        )
        let storage = InstallationInviteErrorMapper.message(
            for: CredentialStoreError.keychain(errSecNotAvailable)
        )
        let sharedStorage = InstallationInviteErrorMapper.message(
            for: InspirationShareBridgeError.keychain(errSecMissingEntitlement)
        )
        let offline = InstallationInviteErrorMapper.message(
            for: URLError(.notConnectedToInternet)
        )

        XCTAssertEqual(expired, "That invitation has expired. Ask for a new code.")
        XCTAssertEqual(rateLimited, "Too many invitation attempts. Try again in 10 minutes.")
        XCTAssertEqual(storage, "Cy couldn’t save this device connection. Your invitation can be retried safely.")
        XCTAssertEqual(sharedStorage, "Cy couldn’t save this device connection. Your invitation can be retried safely.")
        XCTAssertEqual(offline, "Cy couldn’t reach the invitation service. Check your connection and try again.")
        for message in [expired, rateLimited, storage, sharedStorage, offline] {
            XCTAssertFalse(message.localizedCaseInsensitiveContains("work is saved"))
        }
    }

    func testValidationStopsBeforeTheRedemptionClient() async {
        let redeemer = ImmediateInstallationRedeemer(identity: Self.identity)
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            installationRedemptionClient: redeemer,
            requiresInstallationInvite: true
        )

        let outcome = await model.redeemInstallationInvite("ABC")
        let requestCount = await redeemer.requestCount()

        XCTAssertEqual(outcome, .validationFailed)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(
            model.installationInviteStatus,
            .error("Enter the complete invitation code.")
        )
        XCTAssertTrue(model.isInstallationCredentialStatusResolved)
    }

    func testSuccessfulRedemptionPublishesBothRootExitStates() async {
        let redeemer = ImmediateInstallationRedeemer(identity: Self.identity)
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            installationRedemptionClient: redeemer,
            requiresInstallationInvite: true
        )

        let outcome = await model.redeemInstallationInvite("PILOT-123")

        XCTAssertEqual(outcome, .redeemed)
        XCTAssertEqual(model.installationInviteStatus, .idle)
        XCTAssertTrue(model.hasInstallationCredential)
        XCTAssertFalse(model.hasLinkedAccount)
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
        XCTAssertEqual(
            RootDestination.resolve(
                hasProfile: true,
                requiresInstallationInvite: model.requiresInstallationInvite,
                isInstallationCredentialStatusResolved: model.isInstallationCredentialStatusResolved,
                hasInstallationCredential: model.hasInstallationCredential,
                hasLinkedAccount: model.hasLinkedAccount
            ),
            .app
        )
    }

    func testDuplicateSubmissionIsIgnoredWhileTheFirstRequestIsActive() async {
        let redeemer = SuspendingInstallationRedeemer(identity: Self.identity)
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            installationRedemptionClient: redeemer,
            requiresInstallationInvite: true
        )
        let first = Task { await model.redeemInstallationInvite("PILOT-123") }
        for _ in 0..<100 {
            if await redeemer.requestCount() == 1 { break }
            await Task.yield()
        }

        XCTAssertEqual(model.installationInviteStatus, .progress("Checking your invitation…"))
        let duplicate = await model.redeemInstallationInvite("PILOT-123")
        let requestCount = await redeemer.requestCount()
        XCTAssertEqual(duplicate, .duplicateIgnored)
        XCTAssertEqual(requestCount, 1)

        await redeemer.finish()
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .redeemed)
        XCTAssertEqual(model.installationInviteStatus, .idle)
    }

    func testCancellationReturnsToIdleWithoutAnErrorMessage() async {
        let model = AppModel(
            credentialStore: PreviewCredentialStore(),
            installationRedemptionClient: CancellingInstallationRedeemer(),
            requiresInstallationInvite: true
        )

        let outcome = await model.redeemInstallationInvite("PILOT-123")

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(model.installationInviteStatus, .idle)
        XCTAssertFalse(model.isRedeemingInvite)
    }

    func testCredentialSaveFailureKeepsTheSameRecoverableRedemptionAttempt() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PageRoot03URLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            PageRoot03URLProtocol.reset()
        }
        PageRoot03URLProtocol.prepare(credentials: [
            String(repeating: "a", count: 48),
            String(repeating: "b", count: 48),
        ])
        let credentialStore = FailFirstInviteCredentialStore()
        let attemptStore = InMemoryRedemptionAttemptStore()
        let client = InstallationRedemptionClient(
            baseURL: URL(string: "https://unit.test")!,
            session: session,
            store: credentialStore,
            attemptStore: attemptStore
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await client.redeem(inviteCode: "PILOT-123")
        }
        let recovered = try await client.redeem(inviteCode: "PILOT-123")
        let attemptIDs = try PageRoot03URLProtocol.recordedAttemptIDs()
        let saved = await credentialStore.load()
        let attemptStoreIsEmpty = await attemptStore.isEmpty()

        XCTAssertEqual(attemptIDs.count, 2)
        XCTAssertEqual(attemptIDs.first, attemptIDs.last)
        XCTAssertEqual(recovered.credential, String(repeating: "b", count: 48))
        XCTAssertEqual(saved, recovered)
        XCTAssertTrue(attemptStoreIsEmpty)
    }

    private static func wireError(
        code: AIErrorCodeWire,
        message: String,
        retryable: Bool = false,
        retryAfterSeconds: Int? = nil
    ) -> AIWireError {
        AIWireError(
            code: code,
            message: message,
            retryable: retryable,
            retryAfterSeconds: retryAfterSeconds,
            quotaScope: nil,
            fieldIssues: nil
        )
    }

    private static let identity = InstallationIdentity(
        installationID: UUID(uuidString: "A1E62795-D166-4317-B5D5-C6B966389DB5")!,
        credential: String(repeating: "i", count: 48),
        access: .comped,
        credentialExpiresAt: nil,
        promotionalEntitlementEndsAt: nil
    )
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected the async operation to throw.", file: file, line: line)
    } catch {
        // Expected.
    }
}

private actor ImmediateInstallationRedeemer: InstallationRedeeming {
    private let identity: InstallationIdentity?
    private let error: AIWireError?
    private var calls = 0

    init(identity: InstallationIdentity? = nil, error: AIWireError? = nil) {
        self.identity = identity
        self.error = error
    }

    func redeem(inviteCode: String) async throws -> InstallationIdentity {
        calls += 1
        if let error {
            throw AgentCyAPIError.server(error)
        }
        return try XCTUnwrap(identity)
    }

    func requestCount() -> Int { calls }
}

private actor SuspendingInstallationRedeemer: InstallationRedeeming {
    private let identity: InstallationIdentity
    private var calls = 0
    private var continuation: CheckedContinuation<InstallationIdentity, Never>?

    init(identity: InstallationIdentity) {
        self.identity = identity
    }

    func redeem(inviteCode: String) async throws -> InstallationIdentity {
        calls += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func requestCount() -> Int { calls }

    func finish() {
        continuation?.resume(returning: identity)
        continuation = nil
    }
}

private actor CancellingInstallationRedeemer: InstallationRedeeming {
    func redeem(inviteCode: String) async throws -> InstallationIdentity {
        throw CancellationError()
    }
}

private actor FailFirstInviteCredentialStore: InstallationCredentialStoring {
    private var identity: InstallationIdentity?
    private var saveCount = 0

    func load() -> InstallationIdentity? { identity }

    func save(_ identity: InstallationIdentity) throws {
        saveCount += 1
        if saveCount == 1 {
            throw CredentialStoreError.keychain(errSecNotAvailable)
        }
        self.identity = identity
    }

    func delete() { identity = nil }
}

private actor InMemoryRedemptionAttemptStore: InstallationRedemptionAttemptStoring {
    private var attempts: [String: UUID] = [:]

    func attemptID(for inviteFingerprint: String) -> UUID {
        if let existing = attempts[inviteFingerprint] { return existing }
        let created = UUID()
        attempts[inviteFingerprint] = created
        return created
    }

    func clear(inviteFingerprint: String) {
        attempts[inviteFingerprint] = nil
    }

    func isEmpty() -> Bool { attempts.isEmpty }
}

private final class PageRoot03URLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var credentials: [String] = []
    nonisolated(unsafe) private static var requestBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let credential = Self.credentials.first else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.credentials.removeFirst()
        if let body = Self.bodyData(for: request) {
            Self.requestBodies.append(body)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try! JSONSerialization.data(withJSONObject: [
            "installationId": "A1E62795-D166-4317-B5D5-C6B966389DB5",
            "credential": credential,
            "access": "comped",
        ])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func prepare(credentials: [String]) {
        self.credentials = credentials
        requestBodies = []
    }

    static func reset() {
        credentials = []
        requestBodies = []
    }

    static func recordedAttemptIDs() throws -> [String] {
        try requestBodies.map { data in
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            return try XCTUnwrap(object["redemptionAttemptId"] as? String)
        }
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
