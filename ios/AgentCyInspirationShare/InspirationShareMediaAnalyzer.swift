import AVFoundation
import Foundation
import Speech
import UIKit
import Vision

struct ShareMediaAnalysis: Equatable, Sendable {
    let transcript: String?
    let visualObservations: [String]
    let durationSeconds: Int?
    let thumbnailData: Data?
    let didAnalyzeFrames: Bool
    let didReadOnScreenText: Bool
}

actor InspirationShareMediaDownloader {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func downloadVideo(from url: URL, captureID: UUID) async throws -> String {
        guard Self.isSafeInstagramMediaURL(url) else {
            throw InspirationShareTransportError.unsupportedURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let expectedLength = Self.expectedLength(response),
              expectedLength <= InspirationSharedAssetKind.video.maximumBytes else {
            throw InspirationShareTransportError.oversizedAsset
        }
        return try InspirationSharedAssetStore().stageFile(
            from: temporaryURL,
            id: captureID,
            kind: .video
        )
    }

    func downloadThumbnail(from url: URL, captureID: UUID) async throws -> (String, Data) {
        guard Self.isSafeInstagramMediaURL(url) else {
            throw InspirationShareTransportError.unsupportedURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= Int(InspirationSharedAssetKind.thumbnail.maximumBytes),
              let image = UIImage(data: data),
              let normalized = Self.normalizedThumbnailData(image) else {
            throw InspirationShareTransportError.oversizedAsset
        }
        let filename = try InspirationSharedAssetStore().stageData(
            normalized,
            id: captureID,
            kind: .thumbnail,
            fileExtension: "jpg"
        )
        return (filename, normalized)
    }

    private static func expectedLength(_ response: URLResponse) -> Int64? {
        let value = response.expectedContentLength
        return value == NSURLSessionTransferSizeUnknown ? 0 : max(0, value)
    }

    private static func isSafeInstagramMediaURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".cdninstagram.com") || host.hasSuffix(".fbcdn.net")
    }

    private static func normalizedThumbnailData(_ image: UIImage) -> Data? {
        let maximumDimension: CGFloat = 1_200
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

actor InspirationShareMediaAnalyzer {
    func analyze(url: URL) async throws -> ShareMediaAnalysis {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let rawSeconds = CMTimeGetSeconds(duration)
        let durationSeconds = rawSeconds.isFinite && rawSeconds > 0
            ? Int(rawSeconds.rounded())
            : nil
        let frames = sampleFrames(asset: asset, durationSeconds: rawSeconds)
        var observations: [String] = []
        var didReadText = false
        var prominentFaceFrames = 0
        var visualLabels: [String] = []

        for (index, frame) in frames.enumerated() {
            let result = try analyzeFrame(frame)
            if !result.text.isEmpty {
                didReadText = true
                observations.append(
                    "Frame \(index + 1) on-screen text: \(result.text.joined(separator: " | "))"
                )
            }
            if result.hasProminentFace { prominentFaceFrames += 1 }
            visualLabels.append(contentsOf: result.labels)
        }
        if !frames.isEmpty, prominentFaceFrames >= max(2, (frames.count + 1) / 2) {
            observations.append("Video format: talking-head delivery.")
        }
        if let category = broadVisualCategory(for: visualLabels) {
            observations.append("Visual format: \(category).")
        }
        let transcript = await transcribeIfAvailable(url: url)
        let thumbnailData = frames.first.flatMap {
            UIImage(cgImage: $0).jpegData(compressionQuality: 0.82)
        }
        return ShareMediaAnalysis(
            transcript: transcript,
            visualObservations: Array(observations.prefix(20)),
            durationSeconds: durationSeconds,
            thumbnailData: thumbnailData,
            didAnalyzeFrames: !frames.isEmpty,
            didReadOnScreenText: didReadText
        )
    }

    private func sampleFrames(asset: AVAsset, durationSeconds: Double) -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_280, height: 1_280)
        let safeDuration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 1
        return [0.05, 0.25, 0.5, 0.75, 0.95].compactMap { fraction in
            try? generator.copyCGImage(
                at: CMTime(seconds: safeDuration * fraction, preferredTimescale: 600),
                actualTime: nil
            )
        }
    }

    private func analyzeFrame(
        _ image: CGImage
    ) throws -> (text: [String], labels: [String], hasProminentFace: Bool) {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let classifyRequest = VNClassifyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([textRequest, classifyRequest, faceRequest])
        let text = (textRequest.results ?? []).compactMap {
            $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.prefix(12)
        let labels = (classifyRequest.results ?? [])
            .filter { $0.confidence >= 0.45 }
            .prefix(4)
            .map(\.identifier)
        let hasProminentFace = (faceRequest.results ?? []).contains {
            $0.boundingBox.width * $0.boundingBox.height >= 0.035
        }
        return (Array(text), labels, hasProminentFace)
    }

    private func broadVisualCategory(for labels: [String]) -> String? {
        let normalized = labels.map { $0.lowercased() }
        let foodTerms = [
            "food", "meal", "dish", "cuisine", "cook", "beverage", "drink", "dessert",
            "fruit", "vegetable",
        ]
        if normalized.contains(where: { label in foodTerms.contains { label.contains($0) } }) {
            return "food-focused footage"
        }
        let lifestyleTerms = [
            "home", "interior", "travel", "beach", "fashion", "exercise", "fitness",
            "makeup", "shopping",
        ]
        if normalized.contains(where: { label in lifestyleTerms.contains { label.contains($0) } }) {
            return "lifestyle footage"
        }
        return nil
    }

    private func transcribeIfAvailable(url: URL) async -> String? {
        guard SpeechTranscriber.isAvailable else { return nil }
        let installedLocales = await SpeechTranscriber.installedLocales
        guard let locale = installedLocales.first(where: {
            $0.language.languageCode == Locale.current.language.languageCode
        }) ?? installedLocales.first else { return nil }
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            async let transcription = collectTranscript(from: transcriber)
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await transcription
        } catch {
            return nil
        }
    }

    private func collectTranscript(from transcriber: SpeechTranscriber) async throws -> String? {
        var text = ""
        for try await result in transcriber.results where result.isFinal {
            text += String(result.text.characters)
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(20_000))
    }
}
