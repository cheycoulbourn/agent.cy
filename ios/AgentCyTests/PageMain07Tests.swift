import SwiftUI
import XCTest
@testable import AgentCy

@MainActor
final class PageMain07Tests: XCTestCase {

    // DEFECT-MAIN-07-01: the Feed grid previews Instagram only, so its
    // add-live sheet must reject TikTok/YouTube links honestly instead of
    // saving records the page can never show.
    func testInstagramOnlyScopeRejectsCrossPlatformLinks() throws {
        let tiktok = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.tiktok.com/@creator/video/7234567890123456789"))
        let youtube = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let instagram = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.instagram.com/p/AuditControl123/"))

        XCTAssertFalse(LivePostLinkScope.instagramOnly.allows(tiktok))
        XCTAssertFalse(LivePostLinkScope.instagramOnly.allows(youtube))
        XCTAssertTrue(LivePostLinkScope.instagramOnly.allows(instagram))
    }

    // Agenda and the Creation Hub keep full cross-platform live capture.
    func testAllPlatformsScopeKeepsCrossPlatformCapture() throws {
        let tiktok = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.tiktok.com/@creator/video/7234567890123456789"))
        let youtube = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        let instagram = try XCTUnwrap(LivePostURLPolicy.descriptor(
            from: "https://www.instagram.com/p/AuditControl123/"))

        XCTAssertTrue(LivePostLinkScope.allPlatforms.allows(tiktok))
        XCTAssertTrue(LivePostLinkScope.allPlatforms.allows(youtube))
        XCTAssertTrue(LivePostLinkScope.allPlatforms.allows(instagram))
    }

    // The rejection must say where cross-platform links do belong.
    func testInstagramOnlyRejectionExplainsTheAlternative() {
        let message = LivePostLinkScope.instagramOnly.rejectionMessage
        XCTAssertTrue(message.localizedCaseInsensitiveContains("instagram"))
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("agenda")
                || message.localizedCaseInsensitiveContains("create")
        )
    }
}
