import AVFoundation
import Foundation
import LinkPresentation
import Speech
import UIKit
import UniformTypeIdentifiers
import Vision

struct InspirationContentAnalysis: Sendable {
    let title: String?
    let caption: String?
    let transcript: String?
    let visualObservations: [String]
    let analyzedInputs: [InspirationAnalyzedInputWire]
    let durationSeconds: Int?
    let thumbnailData: Data?

    var sourceMaterial: InspirationSourceMaterialWire {
        InspirationSourceMaterialWire(
            title: title,
            caption: caption,
            transcript: transcript,
            visualObservations: visualObservations,
            analyzedInputs: analyzedInputs,
            durationSeconds: durationSeconds
        )
    }
}

enum InspirationContentAnalysisError: Error, LocalizedError {
    case insufficientSourceContent

    var errorDescription: String? {
        switch self {
        case .insufficientSourceContent:
            "agent.cy could not access enough of this post to analyze it. The link is still saved, and you can try again later."
        }
    }
}

protocol InspirationContentAnalyzing: Sendable {
    func analyze(
        url: URL,
        platform: InspirationPlatform,
        hostCaption: String?,
        sharedVideoFilename: String?,
        existingThumbnailData: Data?
    ) async throws -> InspirationContentAnalysis
}

struct PreviewInspirationContentAnalysisService: InspirationContentAnalyzing {
    func analyze(
        url _: URL,
        platform _: InspirationPlatform,
        hostCaption: String?,
        sharedVideoFilename _: String?,
        existingThumbnailData: Data?
    ) async throws -> InspirationContentAnalysis {
        InspirationContentAnalysis(
            title: "A practical creator workflow reset",
            caption: hostCaption ?? "A smaller starting ritual can make filming easier.",
            transcript: nil,
            visualObservations: ["The post opens direct to camera and demonstrates one workflow change."],
            analyzedInputs: [.caption, .videoFrames, .linkMetadata],
            durationSeconds: 45,
            thumbnailData: existingThumbnailData
        )
    }
}

actor RuntimeInspirationContentAnalysisService: InspirationContentAnalyzing {
    private let metadataService: PostLinkMetadataService
    private let videoAnalyzer: SharedVideoAnalyzer
    private let assetStore: InspirationSharedAssetStore?

    init(
        metadataService: PostLinkMetadataService = PostLinkMetadataService(),
        videoAnalyzer: SharedVideoAnalyzer = SharedVideoAnalyzer(),
        assetStore: InspirationSharedAssetStore? = try? InspirationSharedAssetStore()
    ) {
        self.metadataService = metadataService
        self.videoAnalyzer = videoAnalyzer
        self.assetStore = assetStore
    }

    func analyze(
        url: URL,
        platform: InspirationPlatform,
        hostCaption: String?,
        sharedVideoFilename: String?,
        existingThumbnailData: Data?
    ) async throws -> InspirationContentAnalysis {
        try Task.checkCancellation()
        async let fetchedMetadata = metadataService.fetch(url: url, platform: platform)
        var videoAnalysis: SharedVideoAnalysis?
        if let sharedVideoFilename,
           let videoURL = try? assetStore?.assetURL(filename: sharedVideoFilename) {
            videoAnalysis = try? await videoAnalyzer.analyze(url: videoURL)
        }
        try Task.checkCancellation()
        let metadata = try? await fetchedMetadata
        try Task.checkCancellation()
        let caption = firstNonempty(hostCaption, metadata?.caption)
        let title = firstNonempty(
            creatorAttribution(metadata?.creatorName, platform: platform),
            metadata?.title
        )
        let thumbnailData = existingThumbnailData ?? videoAnalysis?.thumbnailData ?? metadata?.thumbnailData
        let observations = videoAnalysis?.visualObservations ?? []

        var inputs: [InspirationAnalyzedInputWire] = []
        if caption != nil { inputs.append(.caption) }
        if videoAnalysis?.transcript != nil { inputs.append(.audioTranscript) }
        if videoAnalysis?.didAnalyzeFrames == true { inputs.append(.videoFrames) }
        if videoAnalysis?.didReadOnScreenText == true { inputs.append(.onScreenText) }
        if metadata != nil || title != nil { inputs.append(.linkMetadata) }
        inputs = Array(Set(inputs)).sorted { $0.rawValue < $1.rawValue }

        let hasContentEvidence = caption != nil ||
            videoAnalysis?.transcript != nil ||
            videoAnalysis?.didReadOnScreenText == true
        guard hasContentEvidence, !inputs.isEmpty else {
            throw InspirationContentAnalysisError.insufficientSourceContent
        }

        return InspirationContentAnalysis(
            title: title,
            caption: caption,
            transcript: videoAnalysis?.transcript,
            visualObservations: Array(observations.prefix(20)),
            analyzedInputs: inputs,
            durationSeconds: videoAnalysis?.durationSeconds,
            thumbnailData: thumbnailData
        )
    }

    private func firstNonempty(_ values: String?...) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private func creatorAttribution(
        _ creatorName: String?,
        platform: InspirationPlatform
    ) -> String? {
        guard let creatorName = firstNonempty(creatorName) else { return nil }
        let platformName: String = switch platform {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .threads: "Threads"
        case .web: "the web"
        }
        return "\(creatorName) on \(platformName)"
    }
}

struct PostLinkMetadata: Sendable {
    let title: String?
    let caption: String?
    let creatorName: String?
    let thumbnailData: Data?
}

protocol PostLinkMetadataFetching: Sendable {
    func fetch(url: URL, platform: InspirationPlatform) async throws -> PostLinkMetadata
}

struct PostLinkMetadataService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: URL, platform: InspirationPlatform) async throws -> PostLinkMetadata {
        if platform == .instagram {
            let embed = try? await fetchOEmbed(url: url, platform: platform)
            let link = try? await fetchLinkPresentation(url: url)
            if embed != nil || link != nil {
                return PostLinkMetadata(
                    title: firstNonempty(embed?.title, link?.title),
                    caption: firstNonempty(embed?.caption, link?.caption),
                    creatorName: firstNonempty(embed?.creatorName, link?.creatorName),
                    thumbnailData: embed?.thumbnailData ?? link?.thumbnailData
                )
            }
        } else if platform == .tiktok || platform == .youtube,
                  let metadata = try? await fetchOEmbed(url: url, platform: platform) {
            return metadata
        }
        return try await fetchLinkPresentation(url: url)
    }

    private func firstNonempty(_ values: String?...) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private func fetchOEmbed(url: URL, platform: InspirationPlatform) async throws -> PostLinkMetadata {
        let endpoint: String = switch platform {
        case .instagram: "https://graph.facebook.com/v25.0/instagram_oembed"
        case .tiktok: "https://www.tiktok.com/oembed"
        case .youtube: "https://www.youtube.com/oembed"
        default: throw InspirationContentAnalysisError.insufficientSourceContent
        }
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 256 * 1_024 else {
            throw InspirationContentAnalysisError.insufficientSourceContent
        }
        let payload = try JSONDecoder().decode(OEmbedPayload.self, from: data)
        let thumbnail: Data?
        if let thumbnailURL = payload.thumbnailURL {
            thumbnail = try await fetchThumbnail(url: thumbnailURL)
        } else {
            thumbnail = nil
        }
        return PostLinkMetadata(
            title: payload.title,
            caption: platform == .tiktok ? payload.title : nil,
            creatorName: payload.authorName,
            thumbnailData: thumbnail
        )
    }

    @MainActor
    private func fetchLinkPresentation(url: URL) async throws -> PostLinkMetadata {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        let metadata = try await provider.startFetchingMetadata(for: url)
        let thumbnail: Data?
        if let imageProvider = metadata.imageProvider {
            thumbnail = await loadImageData(from: imageProvider)
        } else {
            thumbnail = nil
        }
        return PostLinkMetadata(
            title: metadata.title,
            caption: nil,
            creatorName: nil,
            thumbnailData: thumbnail
        )
    }

    private func fetchThumbnail(url: URL) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 5 * 1_024 * 1_024 else { return nil }
        return data
    }

    @MainActor
    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data.flatMap(Self.normalizedThumbnailData))
            }
        }
    }

    private static func normalizedThumbnailData(_ data: Data) -> Data? {
        guard data.count <= 10 * 1_024 * 1_024, let image = UIImage(data: data) else { return nil }
        let maximumDimension: CGFloat = 1_200
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.82)
    }

    private struct OEmbedPayload: Decodable {
        let title: String?
        let authorName: String?
        let thumbnailURL: URL?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
            case thumbnailURL = "thumbnail_url"
        }
    }
}

extension PostLinkMetadataService: PostLinkMetadataFetching {}

struct SharedVideoAnalysis: Sendable {
    let transcript: String?
    let visualObservations: [String]
    let durationSeconds: Int?
    let thumbnailData: Data?
    let didAnalyzeFrames: Bool
    let didReadOnScreenText: Bool
}

actor SharedVideoAnalyzer {
    func analyze(url: URL) async throws -> SharedVideoAnalysis {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        try Task.checkCancellation()
        let rawSeconds = CMTimeGetSeconds(duration)
        let durationSeconds = rawSeconds.isFinite && rawSeconds > 0 ? Int(rawSeconds.rounded()) : nil
        let frames = try sampleFrames(asset: asset, durationSeconds: rawSeconds)
        var observations: [String] = []
        var didReadText = false
        var prominentFaceFrames = 0
        var visualLabels: [String] = []
        for (index, frame) in frames.enumerated() {
            try Task.checkCancellation()
            let result = try analyzeFrame(frame)
            if !result.text.isEmpty {
                didReadText = true
                observations.append("Frame \(index + 1) on-screen text: \(result.text.joined(separator: " | "))")
            }
            if result.hasProminentFace { prominentFaceFrames += 1 }
            visualLabels.append(contentsOf: result.labels)
        }
        if !frames.isEmpty, prominentFaceFrames >= max(2, (frames.count + 1) / 2) {
            observations.append("Video format: talking-head delivery.")
        }
        if let category = broadVisualCategory(for: visualLabels) {
            observations.append("Visual category: \(category).")
        }
        try Task.checkCancellation()
        let transcript = try? await transcribe(url: url)
        try Task.checkCancellation()
        let thumbnailData = frames.first.flatMap {
            UIImage(cgImage: $0).jpegData(compressionQuality: 0.82)
        }
        return SharedVideoAnalysis(
            transcript: transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            visualObservations: observations,
            durationSeconds: durationSeconds,
            thumbnailData: thumbnailData,
            didAnalyzeFrames: !frames.isEmpty,
            didReadOnScreenText: didReadText
        )
    }

    private func sampleFrames(asset: AVAsset, durationSeconds: Double) throws -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_280, height: 1_280)
        let safeDuration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 1
        let fractions = [0.05, 0.25, 0.5, 0.75, 0.95]
        var frames: [CGImage] = []
        for fraction in fractions {
            try Task.checkCancellation()
            let time = CMTime(seconds: safeDuration * fraction, preferredTimescale: 600)
            if let frame = try? generator.copyCGImage(at: time, actualTime: nil) {
                frames.append(frame)
            }
        }
        return frames
    }

    private func analyzeFrame(_ image: CGImage) throws -> (text: [String], labels: [String], hasProminentFace: Bool) {
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
        let labels = (classifyRequest.results ?? []).filter { $0.confidence >= 0.45 }
            .prefix(4)
            .map(\.identifier)
        let hasProminentFace = (faceRequest.results ?? []).contains { face in
            face.boundingBox.width * face.boundingBox.height >= 0.035
        }
        return (Array(text), labels, hasProminentFace)
    }

    private func broadVisualCategory(for labels: [String]) -> String? {
        let normalized = labels.map { $0.lowercased() }
        let foodTerms = ["food", "meal", "dish", "cuisine", "cook", "beverage", "drink", "dessert", "fruit", "vegetable"]
        if normalized.contains(where: { label in foodTerms.contains { label.contains($0) } }) {
            return "food-focused footage"
        }
        let lifestyleTerms = ["home", "interior", "travel", "beach", "fashion", "exercise", "fitness", "makeup", "shopping"]
        if normalized.contains(where: { label in lifestyleTerms.contains { label.contains($0) } }) {
            return "lifestyle footage"
        }
        return nil
    }

    private func transcribe(url: URL) async throws -> String {
        let authorization = await speechAuthorization()
        guard authorization == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.isAvailable else { return "" }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { continuation in
            let box = SpeechRecognitionContinuation(continuation)
            box.task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume(throwing: error)
                } else if let result, result.isFinal {
                    box.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // Same hardening as VoiceSparkRecorder: the TCC callback arrives on a
    // system queue, so the continuation must not inherit actor isolation.
    private nonisolated func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}

private final class SpeechRecognitionContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    var task: SFSpeechRecognitionTask?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        finish { $0.resume(returning: value) }
    }

    func resume(throwing error: Error) {
        finish { $0.resume(throwing: error) }
    }

    private func finish(_ action: (CheckedContinuation<String, Error>) -> Void) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        action(continuation)
        task?.cancel()
        task = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
