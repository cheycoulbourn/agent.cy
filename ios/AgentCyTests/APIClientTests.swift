import Foundation
import XCTest
@testable import AgentCy

final class APIClientTests: XCTestCase {
    func testSSELineDecoderHandlesEventBlocks() throws {
        var decoder = SSELineDecoder()
        XCTAssertNil(decoder.consume("event: phase"))
        XCTAssertNil(decoder.consume("data: {\"phase\":\"generating\"}"))
        let block = try XCTUnwrap(decoder.consume(""))
        XCTAssertEqual(block.event, "phase")
        XCTAssertEqual(String(decoding: block.data, as: UTF8.self), "{\"phase\":\"generating\"}")
    }

    func testSSESequenceRequiresVerifiedSonnetModelAndOrder() throws {
        struct ResultValue: Codable, Equatable { let value: String }
        let id = UUID()
        let blocks = [
            block("meta", ["operationId": id.uuidString, "requestId": UUID().uuidString, "operation": "ideas", "schemaVersion": "ideas.result.v1", "model": "claude-sonnet-5", "startedAt": "2026-07-11T12:00:00Z"]),
            block("phase", ["operationId": id.uuidString, "phase": "generating"]),
            block("result", ["operationId": id.uuidString, "payload": ["operation": "ideas", "result": ["value": "ok"]]]),
            block("done", ["operationId": id.uuidString, "status": "succeeded", "completedAt": "2026-07-11T12:00:01Z"])
        ]
        let decoded = try SSESequenceDecoder.decode(ResultValue.self, blocks: blocks, expectedOperation: .ideas, expectedOperationID: id)
        XCTAssertEqual(decoded, ResultValue(value: "ok"))
    }

    func testSSESequenceRejectsModelReroute() {
        struct ResultValue: Codable { let value: String }
        let id = UUID()
        let blocks = [
            block("meta", ["operationId": id.uuidString, "requestId": UUID().uuidString, "operation": "ideas", "schemaVersion": "ideas.result.v1", "model": "claude-opus-5", "startedAt": "2026-07-11T12:00:00Z"]),
            block("phase", ["operationId": id.uuidString, "phase": "generating"]),
            block("result", ["operationId": id.uuidString, "payload": ["operation": "ideas", "result": ["value": "no"]]]),
            block("done", ["operationId": id.uuidString, "status": "succeeded", "completedAt": "2026-07-11T12:00:01Z"])
        ]
        XCTAssertThrowsError(try SSESequenceDecoder.decode(ResultValue.self, blocks: blocks, expectedOperation: .ideas, expectedOperationID: id))
    }

    func testSSESequenceRejectsOperationIDThatDoesNotEchoRequest() {
        struct ResultValue: Codable { let value: String }
        let requestID = UUID()
        let responseID = UUID()
        let blocks = [
            block("meta", ["operationId": responseID.uuidString, "requestId": UUID().uuidString, "operation": "ideas", "schemaVersion": "ideas.result.v1", "model": "claude-sonnet-5", "startedAt": "2026-07-11T12:00:00Z"]),
            block("phase", ["operationId": responseID.uuidString, "phase": "generating"]),
            block("result", ["operationId": responseID.uuidString, "payload": ["operation": "ideas", "result": ["value": "no"]]]),
            block("done", ["operationId": responseID.uuidString, "status": "succeeded", "completedAt": "2026-07-11T12:00:01Z"])
        ]
        XCTAssertThrowsError(try SSESequenceDecoder.decode(ResultValue.self, blocks: blocks, expectedOperation: .ideas, expectedOperationID: requestID))
    }

    func testErrorStreamStillRequiresMatchingFailedDoneEvent() {
        struct ResultValue: Codable { let value: String }
        let id = UUID()
        let blocks = [
            block("meta", ["operationId": id.uuidString, "requestId": UUID().uuidString, "operation": "ideas", "schemaVersion": "ideas.result.v1", "model": "claude-sonnet-5", "startedAt": "2026-07-11T12:00:00Z"]),
            block("phase", ["operationId": id.uuidString, "phase": "accepted"]),
            block("error", ["operationId": id.uuidString, "error": ["code": "quota_exceeded", "message": "Try later.", "retryable": true, "retryAfterSeconds": 60]]),
            block("done", ["operationId": id.uuidString, "status": "failed", "completedAt": "2026-07-11T12:00:01Z"])
        ]
        XCTAssertThrowsError(try SSESequenceDecoder.decode(ResultValue.self, blocks: blocks, expectedOperation: .ideas, expectedOperationID: id)) { error in
            guard case AgentCyAPIError.server(let wire) = error else { return XCTFail("Expected server error") }
            XCTAssertEqual(wire.code, .quotaExceeded)
        }
    }

    func testSSESequenceRejectsPhaseAfterTerminalEvent() {
        struct ResultValue: Codable { let value: String }
        let id = UUID()
        let blocks = [
            block("meta", ["operationId": id.uuidString, "requestId": UUID().uuidString, "operation": "ideas", "schemaVersion": "ideas.result.v1", "model": "claude-sonnet-5", "startedAt": "2026-07-11T12:00:00Z"]),
            block("result", ["operationId": id.uuidString, "payload": ["operation": "ideas", "result": ["value": "no"]]]),
            block("phase", ["operationId": id.uuidString, "phase": "validating"]),
            block("done", ["operationId": id.uuidString, "status": "succeeded", "completedAt": "2026-07-11T12:00:01Z"])
        ]
        XCTAssertThrowsError(try SSESequenceDecoder.decode(ResultValue.self, blocks: blocks, expectedOperation: .ideas, expectedOperationID: id))
    }

    func testPreviewCredentialStoreNeverSyncsAndCanErase() async throws {
        let store = PreviewCredentialStore()
        let identity = InstallationIdentity(installationID: UUID(), credential: String(repeating: "a", count: 32), access: .comped, credentialExpiresAt: nil, promotionalEntitlementEndsAt: nil)
        await store.save(identity)
        let loaded = await store.load()
        XCTAssertEqual(loaded, identity)
        await store.delete()
        let erased = await store.load()
        XCTAssertNil(erased)
    }

    private func block(_ event: String, _ object: [String: Any]) -> SSEBlock {
        SSEBlock(event: event, data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}
