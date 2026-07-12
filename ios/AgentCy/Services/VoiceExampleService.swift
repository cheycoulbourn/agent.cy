import CryptoKit
import Foundation
import Vision

enum VoiceExampleImportError: LocalizedError, Equatable {
    case imageTooLarge
    case noTextFound
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            "That screenshot is too large to read safely. Try a cropped screenshot."
        case .noTextFound:
            "No readable text was found. Try a clearer crop or paste the caption instead."
        case .unreadableImage:
            "That image could not be read. Try another screenshot or paste the caption instead."
        }
    }
}

protocol ScreenshotTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> String
}

enum VoiceExampleEvidenceLimits {
    static let maximumExampleUTF16Units = 20_000
    static let maximumCombinedUTF8Bytes = 40_000

    static func issue(in drafts: [VoiceExampleDraft]) -> String? {
        issue(in: drafts.filter(\.isUsableEvidence).prefix(5).map(\.trimmedText))
    }

    static func issue(in examples: [VoiceExampleWire]) -> String? {
        issue(in: examples.prefix(5).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private static func issue<S: Sequence>(in texts: S) -> String? where S.Element == String {
        let values = Array(texts)
        if let oversized = values.enumerated().first(where: { $0.element.utf16.count > maximumExampleUTF16Units }) {
            let overflow = oversized.element.utf16.count - maximumExampleUTF16Units
            return "Example \(oversized.offset + 1) is too long. Trim at least \(overflow.formatted()) UTF-16 \(overflow == 1 ? "unit" : "units") so it is 20,000 or fewer."
        }

        let combinedBytes = values.reduce(0) { $0 + $1.lengthOfBytes(using: .utf8) }
        if combinedBytes > maximumCombinedUTF8Bytes {
            let overflow = combinedBytes - maximumCombinedUTF8Bytes
            return "These examples are too long together. Trim at least \(overflow.formatted()) UTF-8 \(overflow == 1 ? "byte" : "bytes") so the total is 40,000 or fewer."
        }
        return nil
    }
}

struct OnDeviceScreenshotTextRecognizer: ScreenshotTextRecognizing {
    static let maximumImageBytes = 20 * 1_024 * 1_024

    func recognizeText(in imageData: Data) async throws -> String {
        guard !imageData.isEmpty else { throw VoiceExampleImportError.unreadableImage }
        guard imageData.count <= Self.maximumImageBytes else { throw VoiceExampleImportError.imageTooLarge }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: imageData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceExampleImportError.unreadableImage
        }

        let text = Self.joinedText(from: observations.compactMap { $0.topCandidates(1).first?.string })
        guard !text.isEmpty else { throw VoiceExampleImportError.noTextFound }
        return text
    }

    static func joinedText(from lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum VoiceExampleFingerprint {
    static func make(from drafts: [VoiceExampleDraft]) -> String {
        make(from: drafts
            .filter(\.isUsableEvidence)
            .prefix(5)
            .enumerated()
            .map { index, draft in
                VoiceExampleWire(
                    exampleId: draft.id,
                    order: index,
                    text: draft.trimmedText,
                    source: draft.source,
                    creatorConfirmed: true
                )
            })
    }

    static func make(from examples: [VoiceExampleWire]) -> String {
        let canonical = examples
            .filter { $0.creatorConfirmed && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(5)
            .map { example in
                "\(example.order)|\(example.exampleId.uuidString.lowercased())|\(example.source.rawValue)|\(example.creatorConfirmed)|\(example.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func make(from examples: [VoiceExample]) -> String {
        make(from: examples
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                VoiceExampleDraft(
                    id: $0.id,
                    text: $0.text,
                    source: $0.source,
                    sourceURLString: $0.sourceURLString
                )
            })
    }
}

struct InitialVoiceProfileProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    var edited: VoiceProfileDraft
    let evidenceFingerprint: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        profileID: UUID,
        edited: VoiceProfileDraft,
        evidenceFingerprint: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.edited = edited
        self.evidenceFingerprint = evidenceFingerprint
        self.createdAt = createdAt
    }
}
