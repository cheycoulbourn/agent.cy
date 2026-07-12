import Foundation
import XCTest
@testable import AgentCy

final class LiveContractTests: XCTestCase {
    func testCanonicalVoiceProfileFixtureDecodes() throws {
        let result = try decodeFixture("voice-profile-result", as: VoiceProfileResultWire.self)
        XCTAssertEqual(result.profile.tone, ["warm", "plainspoken"])
        XCTAssertEqual(result.profile.confidence, 0.8)
        XCTAssertFalse(result.evidenceNotes.isEmpty)
    }

    func testCanonicalIdeasFixtureDecodesExactlyThreeDirections() throws {
        let result = try decodeFixture("ideas-result", as: IdeasResultWire.self)
        XCTAssertEqual(result.ideas.count, 3)
        XCTAssertEqual(Set(result.ideas.map(\.directionId)).count, 3)
    }

    func testCanonicalSparkTurnFixtureDecodesNullableQuestionAndState() throws {
        let result = try decodeFixture("spark-turn-result", as: SparkTurnResultWire.self)
        XCTAssertNil(result.focusedQuestion)
        XCTAssertEqual(result.recommendedNextStep, .composeNow)
        XCTAssertEqual(result.workingState.constraints.count, 2)
    }

    func testCanonicalComposeFixtureDecodesSparsePlatformVariantsAndTasks() throws {
        let result = try decodeFixture("compose-brief-result", as: ComposeBriefResultWire.self)
        XCTAssertEqual(result.brief.platformVariants.count, 3)
        XCTAssertEqual(result.brief.proposedTasks.filter(\.isRecordingMilestone).count, 1)
        XCTAssertEqual(result.brief.platformVariants[1].openingAdjustment, "Show the messy note before the first spoken word.")
    }

    func testCanonicalChatFixtureDecodesApprovalGatedAction() throws {
        let result = try decodeFixture("chat-turn-result", as: ChatTurnResultWire.self)
        XCTAssertEqual(result.proposedAction?.kind, .developSpark)
        XCTAssertEqual(result.suggestions.count, 1)
    }

    func testCanonicalRevisionFixtureDecodesChangedScope() throws {
        let result = try decodeFixture("revise-brief-result", as: ReviseBriefResultWire.self)
        XCTAssertEqual(result.brief.briefId, UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
        XCTAssertEqual(result.changedFields, [.spokenHook, .firstFrameText])
        XCTAssertFalse(result.explanation.isEmpty)
    }

    func testPaidRevisionOrdinalAboveFreeAllowanceEncodesExactly() throws {
        let composed = try decodeFixture("compose-brief-result", as: ComposeBriefResultWire.self)
        let request = ReviseBriefRequestWire(
            schemaVersion: AIContractVersion.schema,
            promptVersion: AIContractVersion.reviseBriefPrompt,
            operationId: UUID(),
            appBuild: "0.1 (1)",
            assistanceMode: .collaborate,
            creatorContext: creatorContext(),
            brief: composed.brief,
            revisionNumber: 27,
            scope: .spokenHook,
            instruction: "Make the opening more direct."
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["promptVersion"] as? String, "revise-brief.v1")
        XCTAssertEqual(object["revisionNumber"] as? Int, 27)
        XCTAssertEqual(object["scope"] as? String, "spokenHook")
    }

    func testTeachCyRequestEncodesRequiredInstructionAndCurrentProfile() throws {
        let current = VoiceProfileWire(
            summary: "Direct teaching",
            tone: ["direct"],
            sentenceStyle: "Short sentences.",
            signatureQualities: ["specific"],
            phrasesToUse: [],
            phrasesToAvoid: ["hype"],
            guidance: ["Use one example."],
            confidence: 0.8
        )
        let base = creatorContext()
        let context = CreatorContextWire(
            name: base.name,
            primaryGoal: base.primaryGoal,
            selectedPlatforms: base.selectedPlatforms,
            voiceExamples: base.voiceExamples,
            voiceProfile: current,
            pillars: base.pillars,
            librarySummaries: base.librarySummaries
        )
        let request = VoiceProfileRequestWire(
            schemaVersion: AIContractVersion.schema,
            promptVersion: AIContractVersion.voiceProfilePrompt,
            operationId: UUID(),
            appBuild: "0.1 (1)",
            assistanceMode: .collaborate,
            creatorContext: context,
            intent: .teachCy,
            teachingInstruction: "Use shorter, less polished openings."
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["intent"] as? String, "teachCy")
        XCTAssertEqual(object["teachingInstruction"] as? String, "Use shorter, less polished openings.")
        XCTAssertNotNil((object["creatorContext"] as? [String: Any])?["voiceProfile"])
    }

    func testVoiceProfileRequestEncodesCanonicalRolesAndMetadata() throws {
        let context = creatorContext()
        let request = VoiceProfileRequestWire(
            schemaVersion: AIContractVersion.schema,
            promptVersion: AIContractVersion.voiceProfilePrompt,
            operationId: UUID(),
            appBuild: "0.1 (1)",
            assistanceMode: .collaborate,
            creatorContext: context,
            intent: .onboarding,
            teachingInstruction: nil
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["promptVersion"] as? String, "voice-profile.v1")
        XCTAssertEqual(object["intent"] as? String, "onboarding")
        XCTAssertNil(object["teachingInstruction"])
        let encodedContext = try XCTUnwrap(object["creatorContext"] as? [String: Any])
        XCTAssertEqual((encodedContext["voiceExamples"] as? [[String: Any]])?.count, 3)
    }

    func testInstallationRedemptionUsesCanonicalEndpointAndStoresCredential() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let installationID = UUID()
        let credential = String(repeating: "c", count: 48)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = try JSONSerialization.data(withJSONObject: [
                "installationId": installationID.uuidString,
                "credential": credential,
                "access": "comped"
            ])
            return (response, data)
        }
        defer { StubURLProtocol.handler = nil }

        let store = PreviewCredentialStore()
        let client = InstallationRedemptionClient(
            baseURL: URL(string: "https://unit.test")!,
            session: session,
            store: store
        )
        let identity = try await client.redeem(inviteCode: "PILOT-123")
        XCTAssertEqual(identity.installationID, installationID)
        XCTAssertEqual(identity.access, .comped)
        let saved = await store.load()
        XCTAssertEqual(saved, identity)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/installations/redeem")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
    }

    func testAPIClientSendsRequestOperationIDAndDecodesCanonicalIdeasSSE() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let operationID = UUID()
        let fixture = try JSONSerialization.jsonObject(with: fixtureData("ideas-result"))
        let compactFixture = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys])
        let resultJSON = String(decoding: compactFixture, as: UTF8.self)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let requestID = UUID()
            let stream = """
            event: meta
            data: {"operationId":"\(operationID.uuidString)","requestId":"\(requestID.uuidString)","operation":"ideas","schemaVersion":"ideas.result.v1","model":"claude-sonnet-5","startedAt":"2026-07-11T12:00:00Z"}

            event: phase
            data: {"operationId":"\(operationID.uuidString)","phase":"accepted"}

            event: result
            data: {"operationId":"\(operationID.uuidString)","payload":{"operation":"ideas","result":\(resultJSON)}}

            event: done
            data: {"operationId":"\(operationID.uuidString)","status":"succeeded","completedAt":"2026-07-11T12:00:01Z"}

            """
            return (response, Data(stream.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let store = PreviewCredentialStore(
            identity: InstallationIdentity(
                installationID: UUID(),
                credential: String(repeating: "a", count: 48),
                access: .comped,
                credentialExpiresAt: nil,
                promotionalEntitlementEndsAt: nil
            )
        )
        let client = AgentCyAPIClient(baseURL: URL(string: "https://unit.test")!, session: session, store: store)
        let request = IdeasRequestWire(
            schemaVersion: AIContractVersion.schema,
            promptVersion: AIContractVersion.ideasPrompt,
            operationId: operationID,
            appBuild: "0.1 (1)",
            assistanceMode: .collaborate,
            creatorContext: creatorContext(),
            count: 3,
            startingPoint: nil,
            constraints: []
        )
        let result = try await client.perform(operation: .ideas, request: request, result: IdeasResultWire.self)
        XCTAssertEqual(result.ideas.count, 3)
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer \(String(repeating: "a", count: 48))")
    }

    func testPrivacyDeletionUsesExactAuthenticatedContract() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let installationID = UUID()
        let credential = String(repeating: "p", count: 48)
        StubURLProtocol.handler = { request in
            let data = try XCTUnwrap(StubURLProtocol.bodyData(for: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(object.keys), Set(["requestId", "installationId", "appBuild", "scope", "confirmation"]))
            XCTAssertEqual(object["installationId"] as? String, installationID.uuidString)
            XCTAssertEqual(object["appBuild"] as? String, "0.1 (99)")
            XCTAssertEqual(object["scope"] as? String, "serverMetadata")
            XCTAssertEqual(object["confirmation"] as? String, "ERASE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(credential)")
            let requestID = try XCTUnwrap(object["requestId"] as? String)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let responseData = try JSONSerialization.data(withJSONObject: [
                "requestId": requestID,
                "deletedAt": "2026-07-11T12:00:00.000Z",
                "retained": [
                    ["category": "inviteRedemptionTombstone", "reason": "fraudPrevention"],
                    ["category": "freeBriefConsumption", "reason": "entitlementIntegrity"],
                    ["category": "entitlementHistory", "reason": "entitlementIntegrity"]
                ]
            ])
            return (response, responseData)
        }
        defer { StubURLProtocol.handler = nil }

        let client = PrivacyDeletionClient(
            baseURL: URL(string: "https://unit.test")!,
            session: session,
            appBuild: "0.1 (99)"
        )
        let identity = InstallationIdentity(
            installationID: installationID,
            credential: credential,
            access: .comped,
            credentialExpiresAt: nil,
            promotionalEntitlementEndsAt: nil
        )
        let result = try await client.deleteServerMetadata(for: identity)

        XCTAssertEqual(result.retained.count, 3)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/privacy/delete")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
    }

    private func creatorContext() -> CreatorContextWire {
        CreatorContextWire(
            name: "Ari",
            primaryGoal: "Help new designers",
            selectedPlatforms: [.instagramReels, .tiktok],
            voiceExamples: (0..<3).map { index in
                VoiceExampleWire(exampleId: UUID(), order: index, text: "Example \(index) with a practical takeaway.")
            },
            voiceProfile: nil,
            pillars: [],
            librarySummaries: []
        )
    }

    private func decodeFixture<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: fixtureData(name))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appending(path: "contracts/test/fixtures/\(name).json")
        return try Data(contentsOf: url)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func bodyData(for request: URLRequest) -> Data? {
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
