#if !targetEnvironment(macCatalyst)
import Foundation

struct VoiceSparkRecording: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var workspaceID: UUID?
    var createdAt: Date
    var durationSeconds: TimeInterval
    var title: String? = nil
    var transcript: String
    var fileName: String
    var linkedBriefID: UUID?
    var linkedBriefTitle: String?
    var linkedPlacement: IdeaBankPlacement?
}

enum VoiceSparkSessionPolicy {
    static func currentRecordings(
        from recordings: [VoiceSparkRecording],
        sessionRecordingIDs: Set<UUID>,
        workspaceID: UUID?
    ) -> [VoiceSparkRecording] {
        recordings.filter {
            sessionRecordingIDs.contains($0.id) && $0.workspaceID == workspaceID
        }
    }

    static func libraryRecordings(
        from recordings: [VoiceSparkRecording],
        workspaceID: UUID?
    ) -> [VoiceSparkRecording] {
        recordings.filter {
            $0.workspaceID == workspaceID && $0.linkedPlacement != .post
        }
    }

    static func shouldShowFreshActions(
        for recordingID: UUID,
        sessionRecordingIDs: Set<UUID>,
        autoLinksToPost: Bool
    ) -> Bool {
        !autoLinksToPost && sessionRecordingIDs.contains(recordingID)
    }

    static func actionRecordings(
        from recordings: [VoiceSparkRecording],
        selected recordingID: UUID,
        sessionRecordingIDs: Set<UUID>
    ) -> [VoiceSparkRecording] {
        guard sessionRecordingIDs.contains(recordingID) else {
            return recordings.filter { $0.id == recordingID }
        }
        return recordings.filter { sessionRecordingIDs.contains($0.id) }
    }

    static func shouldCreateSeparateIdea(for recordings: [VoiceSparkRecording]) -> Bool {
        !recordings.contains { $0.linkedPlacement == .post }
    }

    static func canSave(
        autoLinksToPost: Bool,
        transcript: String,
        recordingCount: Int,
        isBusy: Bool
    ) -> Bool {
        guard !isBusy else { return false }
        if autoLinksToPost {
            return recordingCount > 0
        }
        return !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Voice capture stays unfiled until the creator connects it to existing content.
    static var capturedContentPillarID: UUID? { nil }

    static func shouldOpenPost(afterConnectingTo placement: IdeaBankPlacement) -> Bool {
        placement == .post
    }

    static func displayTitle(_ title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Voice recording" : trimmed
    }
}

@MainActor
enum VoiceSparkRecordingStore {
    private static let directoryName = "Voice Sparks"
    private static let indexFileName = "recordings.json"

    static func load(rootURL: URL? = nil, fileManager: FileManager = .default) throws -> [VoiceSparkRecording] {
        let indexURL = try directory(rootURL: rootURL, fileManager: fileManager)
            .appendingPathComponent(indexFileName)
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([VoiceSparkRecording].self, from: Data(contentsOf: indexURL))
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(
        temporaryURL: URL,
        workspaceID: UUID?,
        transcript: String,
        durationSeconds: TimeInterval,
        createdAt: Date = Date(),
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> VoiceSparkRecording {
        let root = try directory(rootURL: rootURL, fileManager: fileManager)
        let id = UUID()
        let fileName = "voice-spark-\(id.uuidString.lowercased()).m4a"
        let destinationURL = root.appendingPathComponent(fileName)
        try fileManager.copyItem(at: temporaryURL, to: destinationURL)

        let recording = VoiceSparkRecording(
            id: id,
            workspaceID: workspaceID,
            createdAt: createdAt,
            durationSeconds: max(0, durationSeconds),
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            fileName: fileName,
            linkedBriefID: nil,
            linkedBriefTitle: nil,
            linkedPlacement: nil
        )

        do {
            var recordings = try load(rootURL: root, fileManager: fileManager)
            recordings.insert(recording, at: 0)
            try persist(recordings, rootURL: root, fileManager: fileManager)
            return recording
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    @discardableResult
    static func connect(
        recordingID: UUID,
        briefID: UUID,
        briefTitle: String,
        placement: IdeaBankPlacement,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> VoiceSparkRecording {
        try update(recordingID: recordingID, rootURL: rootURL, fileManager: fileManager) { recording in
            recording.linkedBriefID = briefID
            recording.linkedBriefTitle = briefTitle
            recording.linkedPlacement = placement
        }
    }

    @discardableResult
    static func updateTranscript(
        recordingID: UUID,
        transcript: String,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> VoiceSparkRecording {
        try update(recordingID: recordingID, rootURL: rootURL, fileManager: fileManager) { recording in
            recording.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @discardableResult
    static func updateTitle(
        recordingID: UUID,
        title: String,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> VoiceSparkRecording {
        try update(recordingID: recordingID, rootURL: rootURL, fileManager: fileManager) { recording in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            recording.title = trimmed.isEmpty ? nil : trimmed
        }
    }

    static func audioURL(
        for recording: VoiceSparkRecording,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try directory(rootURL: rootURL, fileManager: fileManager)
            .appendingPathComponent(recording.fileName)
    }

    static func audioData(
        for recording: VoiceSparkRecording,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Data {
        try Data(contentsOf: audioURL(for: recording, rootURL: rootURL, fileManager: fileManager))
    }

    static func remove(
        recordingID: UUID,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let root = try directory(rootURL: rootURL, fileManager: fileManager)
        var recordings = try load(rootURL: root, fileManager: fileManager)
        guard let recording = recordings.first(where: { $0.id == recordingID }) else { return }
        recordings.removeAll { $0.id == recordingID }
        try persist(recordings, rootURL: root, fileManager: fileManager)
        let audioURL = root.appendingPathComponent(recording.fileName)
        if fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }
    }

    static func clear(
        workspaceID: UUID?,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let root = try directory(rootURL: rootURL, fileManager: fileManager)
        let recordings = try load(rootURL: root, fileManager: fileManager)
        let removed = recordings.filter { $0.workspaceID == workspaceID }
        let kept = recordings.filter { $0.workspaceID != workspaceID }
        try persist(kept, rootURL: root, fileManager: fileManager)
        for recording in removed {
            let url = root.appendingPathComponent(recording.fileName)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    static func clearAll(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        let root = try directory(rootURL: rootURL, fileManager: fileManager)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    private static func update(
        recordingID: UUID,
        rootURL: URL?,
        fileManager: FileManager,
        transform: (inout VoiceSparkRecording) -> Void
    ) throws -> VoiceSparkRecording {
        let root = try directory(rootURL: rootURL, fileManager: fileManager)
        var recordings = try load(rootURL: root, fileManager: fileManager)
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            throw VoiceSparkRecordingStoreError.missingRecording
        }
        transform(&recordings[index])
        let updated = recordings[index]
        try persist(recordings, rootURL: root, fileManager: fileManager)
        return updated
    }

    private static func persist(
        _ recordings: [VoiceSparkRecording],
        rootURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(recordings.sorted { $0.createdAt > $1.createdAt })
            .write(to: rootURL.appendingPathComponent(indexFileName), options: .atomic)
    }

    private static func directory(rootURL: URL?, fileManager: FileManager) throws -> URL {
        let root: URL
        if let rootURL {
            root = rootURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = applicationSupport
                .appendingPathComponent("agent.cy", isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

enum VoiceSparkRecordingStoreError: LocalizedError {
    case missingRecording

    var errorDescription: String? {
        "That Voice Spark recording is no longer available."
    }
}
#endif
