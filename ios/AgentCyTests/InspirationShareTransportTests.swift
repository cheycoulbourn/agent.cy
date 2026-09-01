import Foundation
import XCTest
@testable import AgentCy

final class InspirationShareTransportTests: XCTestCase {
    func testSavedPostTitleNormalizationRequiresContentAndKeepsAReadableTitle() {
        XCTAssertNil(InspirationSavedPostTitlePolicy.normalized(nil))
        XCTAssertNil(InspirationSavedPostTitlePolicy.normalized("  \n  "))
        XCTAssertEqual(
            InspirationSavedPostTitlePolicy.normalized("  A   better\nfilming setup  "),
            "A better filming setup"
        )

        let longTitle = String(repeating: "a", count: 200)
        XCTAssertEqual(
            InspirationSavedPostTitlePolicy.normalized(longTitle)?.count,
            InspirationSavedPostTitlePolicy.maximumLength
        )
    }

    func testCreatorSnapshotPreservesPillarColorsAndDecodesOlderSnapshots() throws {
        let pillarID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let creatorContext = Data("{}".utf8)
        let snapshot = InspirationShareCreatorSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            assistanceMode: "collaborate",
            creatorContextJSON: creatorContext,
            pillarColorHexByID: [pillarID.uuidString.lowercased(): "5E8069"]
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(InspirationShareCreatorSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.pillarColorHexByID?[pillarID.uuidString.lowercased()], "5E8069")

        let olderSnapshot = InspirationShareCreatorSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            assistanceMode: "collaborate",
            creatorContextJSON: creatorContext
        )
        let olderData = try JSONEncoder().encode(olderSnapshot)
        let decodedOlder = try JSONDecoder().decode(InspirationShareCreatorSnapshot.self, from: olderData)
        XCTAssertNil(decodedOlder.pillarColorHexByID)
    }

    func testURLRepresentationsTakePriorityOverHostSuppliedText() throws {
        let resolved = try InspirationShareCandidateResolver.resolve(
            urlValues: ["https://www.instagram.com/reel/ABC/?igsh=secret"],
            textValues: ["A caption we must discard https://example.com/other"]
        )

        XCTAssertEqual(resolved.absoluteString, "https://www.instagram.com/reel/ABC/")
    }

    func testCanonicalizationRemovesOnlyPlatformTrackingAndKeepsContentParameters() throws {
        let canonical = try InspirationLinkCanonicalizer.canonicalize(
            "HTTPS://WWW.YOUTUBE.COM/watch?v=abc123&si=share-token&feature=shared&utm_source=copy#comments"
        )

        XCTAssertEqual(canonical.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(InspirationLinkCanonicalizer.platform(for: canonical), .youtube)

        let web = try InspirationLinkCanonicalizer.canonicalize(
            "https://example.com/story?si=meaningful&feature=paid&utm_campaign=launch"
        )
        XCTAssertEqual(web.absoluteString, "https://example.com/story?si=meaningful&feature=paid")
        XCTAssertEqual(InspirationLinkCanonicalizer.platform(for: web), .web)
    }

    func testCanonicalizationRejectsUnsafeOrNonPublicHosts() {
        let rejected = [
            "http://example.com/post",
            "https://user:password@example.com/post",
            "https://localhost/post",
            "https://printer.local/post",
            "https://intranet/post",
            "https://127.0.0.1/post",
            "https://[::1]/post",
        ]

        for value in rejected {
            XCTAssertThrowsError(try InspirationLinkCanonicalizer.canonicalize(value), value)
        }
    }

    func testTextExtractionRequiresOneUniqueHTTPSLink() throws {
        let result = try InspirationSharedTextExtractor.extractCanonicalURL(
            from: "This hook worked for me: https://www.instagram.com/reel/ABC/?igsh=tracking"
        )

        XCTAssertEqual(result.absoluteString, "https://www.instagram.com/reel/ABC/")

        XCTAssertThrowsError(
            try InspirationSharedTextExtractor.extractCanonicalURL(
                from: "Compare https://example.com/one with https://example.com/two"
            )
        )

        XCTAssertNoThrow(
            try InspirationSharedTextExtractor.extractCanonicalURL(
                from: "https://example.com/idea https://example.com/idea#repeat"
            )
        )
    }

    func testResolvedCandidateKeepsCaptionButRemovesEverySharedLink() throws {
        let candidate = try InspirationShareCandidateResolver.resolveCandidate(
            urlValues: ["https://www.instagram.com/reel/ABC/?igsh=tracking"],
            textValues: [
                "Three ways to make your first take easier https://www.instagram.com/reel/ABC/?igsh=tracking"
            ]
        )

        XCTAssertEqual(candidate.url.absoluteString, "https://www.instagram.com/reel/ABC/")
        XCTAssertEqual(candidate.sourceCaption, "Three ways to make your first take easier")
        XCTAssertFalse(candidate.sourceCaption?.contains("https://") == true)
    }

    func testQueueRoundTripIsOldestFirstAndRemovalIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let later = InspirationShareEnvelope(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            capturedAt: Date(timeIntervalSince1970: 200),
            workspaceHintID: nil,
            canonicalURLString: "https://example.com/later",
            platform: .web,
            creatorObservation: "The reveal is delayed."
        )
        let earlier = InspirationShareEnvelope(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: UUID(uuidString: "00000000-0000-0000-0000-000000000010"),
            canonicalURLString: "https://www.tiktok.com/@creator/video/1",
            platform: .tiktok,
            creatorObservation: ""
        )

        try store.enqueue(later)
        try store.enqueue(earlier)

        XCTAssertEqual(try store.pending(), [earlier, later])

        try store.remove(id: earlier.id)
        try store.remove(id: earlier.id)
        XCTAssertEqual(try store.pending(), [later])
    }

    func testQueueRejectsOversizedCreatorObservation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let envelope = InspirationShareEnvelope(
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: nil,
            canonicalURLString: "https://example.com/post",
            platform: .web,
            creatorObservation: String(repeating: "a", count: 33_000)
        )

        XCTAssertThrowsError(try store.enqueue(envelope))
        XCTAssertEqual(try store.pending(), [])
    }

    func testQueueReplayIsIdempotentAndConflictingCaptureIsRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = InspirationImportQueueStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let envelope = InspirationShareEnvelope(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            capturedAt: Date(timeIntervalSince1970: 100),
            workspaceHintID: nil,
            canonicalURLString: "https://example.com/post",
            platform: .web,
            sourceTitle: "Original title"
        )

        try store.enqueue(envelope)
        XCTAssertNoThrow(try store.enqueue(envelope))
        XCTAssertEqual(try store.pending(), [envelope])

        var conflictingEnvelope = envelope
        conflictingEnvelope.sourceTitle = "Conflicting title"
        XCTAssertThrowsError(try store.enqueue(conflictingEnvelope)) { error in
            XCTAssertEqual(error as? InspirationShareTransportError, .fileCollision)
        }
        XCTAssertEqual(try store.pending(), [envelope])
    }

    func testCancelledShareLoadDiscardsAssetThatFinishedStagingLate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = InspirationSharedAssetStore(
            rootDirectoryURL: root,
            appliesFileProtection: false
        )
        let filename = try store.stageData(
            Data("thumbnail".utf8),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            kind: .thumbnail,
            fileExtension: "jpg"
        )

        let retainedFilename = store.finalizeStagedFile(
            filename,
            taskWasCancelled: true
        )

        XCTAssertNil(retainedFilename)
        XCTAssertThrowsError(try store.assetURL(filename: filename))
    }
}
