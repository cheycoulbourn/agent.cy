import AVFoundation
import Speech
import XCTest
@testable import AgentCy

final class SpeechAudioPipelineTests: XCTestCase {
    func testAudioTapBridgeAcceptsBufferFromRealtimeQueue() async throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let converter = try XCTUnwrap(SpeechAudioBufferConverter(from: format, to: format))
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        var iterator = stream.makeAsyncIterator()
        let handler = SpeechAudioTapBridge.makeHandler(converter: converter, continuation: continuation)
        let boxedBuffer = TestPCMBufferBox(buffer)

        await withCheckedContinuation { finished in
            DispatchQueue(label: "RealtimeMessenger.mServiceQueue").async {
                handler(boxedBuffer.value, AVAudioTime())
                finished.resume()
            }
        }

        let delivered = await iterator.next()
        XCTAssertNotNil(delivered)
        continuation.finish()
    }

    func testMicrophoneTapUsesHardwareCaptureFormatInsteadOfAnalyzerFormat() throws {
        let capture = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let analyzer = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let plan = SpeechCaptureAudioPlan(captureFormat: capture, analyzerFormat: analyzer)

        XCTAssertEqual(plan.tapFormat.sampleRate, 48_000)
        XCTAssertEqual(plan.tapFormat.channelCount, 1)
    }

    func testZeroRateOrChannelCaptureFormatIsRejectedBeforeInstallingTap() {
        XCTAssertFalse(SpeechCaptureAudioPlan.isUsableCaptureFormat(sampleRate: 0, channelCount: 1))
        XCTAssertFalse(SpeechCaptureAudioPlan.isUsableCaptureFormat(sampleRate: 48_000, channelCount: 0))
        XCTAssertTrue(SpeechCaptureAudioPlan.isUsableCaptureFormat(sampleRate: 48_000, channelCount: 1))
    }

    func testHardwareBufferIsConvertedBeforeItBecomesAnalyzerInput() throws {
        let capture = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let analyzer = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: capture, frameCapacity: 480))
        input.frameLength = 480
        input.floatChannelData?[0][0] = 0.25
        let converter = try XCTUnwrap(SpeechAudioBufferConverter(from: capture, to: analyzer))

        let output = try XCTUnwrap(converter.convert(input))

        XCTAssertEqual(output.format.sampleRate, 16_000)
        XCTAssertEqual(output.format.channelCount, 1)
        XCTAssertGreaterThan(output.frameLength, 0)
    }
}

private final class TestPCMBufferBox: @unchecked Sendable {
    let value: AVAudioPCMBuffer

    init(_ value: AVAudioPCMBuffer) {
        self.value = value
    }
}
