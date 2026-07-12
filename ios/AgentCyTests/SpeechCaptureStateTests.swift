import Foundation
import XCTest
import Speech
@testable import AgentCy

@MainActor
final class SpeechCaptureStateTests: XCTestCase {
    func testSpeechAuthorizationBridgeAcceptsCallbackFromBackgroundQueue() async {
        let status = await SpeechAuthorizationBridge.request { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                completion(.authorized)
            }
        }

        XCTAssertEqual(status, .authorized)
    }

    func testOnlyPreparingDownloadingAndRecordingAreActive() {
        XCTAssertFalse(SpeechCaptureState.idle.isActive)
        XCTAssertTrue(SpeechCaptureState.preparing.isActive)
        XCTAssertTrue(SpeechCaptureState.downloadingAssets.isActive)
        XCTAssertTrue(SpeechCaptureState.recording.isActive)
        XCTAssertFalse(SpeechCaptureState.unavailable("Try typing.").isActive)

        XCTAssertTrue(SpeechCaptureState.preparing.isPreparing)
        XCTAssertTrue(SpeechCaptureState.downloadingAssets.isPreparing)
        XCTAssertFalse(SpeechCaptureState.recording.isPreparing)
        XCTAssertTrue(SpeechCaptureState.recording.isRecording)
    }

    func testPreparingAndDownloadPresentationsShowProgressWithoutPretendingToKnowAPercentage() {
        let preparing = SpeechCaptureState.preparing.presentation
        let downloading = SpeechCaptureState.downloadingAssets.presentation

        XCTAssertTrue(preparing.showsProgress)
        XCTAssertTrue(downloading.showsProgress)
        XCTAssertTrue(preparing.detail.contains("keep typing"))
        XCTAssertTrue(downloading.detail.contains("keyboard dictation"))
        XCTAssertFalse(downloading.detail.contains("%"))
    }

    func testIdleAndUnavailableCopyKeepTypingFallbackVisible() {
        let idle = SpeechCaptureState.idle.presentation
        let message = SpeechCaptureError.permissionDenied.localizedDescription
        let unavailable = SpeechCaptureState.unavailable(message).presentation

        XCTAssertTrue(idle.detail.contains("keyboard’s dictation button"))
        XCTAssertTrue(idle.detail.contains("Raw audio is never saved"))
        XCTAssertTrue(unavailable.detail.contains("Keep typing"))
        XCTAssertEqual(unavailable.systemImage, "keyboard")
    }

    func testPreviewCapturePreservesTranscriptCallbackAndStateTransitions() async throws {
        let recorder = PreviewSpeechCapture()
        let transcript = CapturedTranscript()

        try await recorder.start(initialTranscript: "An opening thought.") { transcript.value = $0 }

        XCTAssertEqual(recorder.state, .recording)
        XCTAssertTrue(transcript.value.hasPrefix("An opening thought."))

        await recorder.stop()
        XCTAssertEqual(recorder.state, .idle)
    }

    func testTranscriptAccumulatorPreservesExistingTextAndAppendsLaterSpeech() {
        var transcript = SpeechTranscriptAccumulator(initialTranscript: "Something I already typed.")

        let first = transcript.merge(
            "Here is the first spoken thought.",
            range: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 1_000))
        )
        let second = transcript.merge(
            "Then here is the next one.",
            range: CMTimeRange(
                start: CMTime(seconds: 2, preferredTimescale: 1_000),
                duration: CMTime(seconds: 2, preferredTimescale: 1_000)
            )
        )

        XCTAssertEqual(first, "Something I already typed. Here is the first spoken thought.")
        XCTAssertEqual(
            second,
            "Something I already typed. Here is the first spoken thought. Then here is the next one."
        )
    }

    func testTranscriptAccumulatorReplacesOnlyAnOverlappingProgressiveResult() {
        var transcript = SpeechTranscriptAccumulator(initialTranscript: "")
        let firstRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 2, preferredTimescale: 1_000)
        )
        let secondRange = CMTimeRange(
            start: CMTime(seconds: 2, preferredTimescale: 1_000),
            duration: CMTime(seconds: 2, preferredTimescale: 1_000)
        )

        _ = transcript.merge("Is this thing", range: firstRange)
        _ = transcript.merge("and now another thought", range: secondRange)
        let revised = transcript.merge("Is this thing working?", range: firstRange)

        XCTAssertEqual(revised, "Is this thing working? and now another thought")
    }
}

@MainActor
private final class CapturedTranscript {
    var value = ""
}
