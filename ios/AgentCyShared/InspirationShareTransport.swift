import Foundation

enum InspirationSharedContainer {
    static let appGroupIdentifier = "group.com.agentcy.app"
    static let incomingDirectoryName = "IncomingInspiration"
    static let activeWorkspaceHintKey = "agentcy.inspiration.activeWorkspaceHint.v1"
}

enum InspirationPlatform: String, Codable, CaseIterable, Sendable {
    case instagram
    case tiktok
    case youtube
    case threads
    case web
}

enum InspirationShareTransportError: Error, Equatable, LocalizedError {
    case invalidURL
    case unsupportedURL
    case expectedOneURL
    case unavailableSharedContainer
    case oversizedEnvelope
    case invalidEnvelope
    case fileCollision
    case oversizedAsset

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "That link is not valid."
        case .unsupportedURL:
            "Use a public HTTPS link."
        case .expectedOneURL:
            "Share one post link at a time."
        case .unavailableSharedContainer:
            "agent.cy could not access its private import queue."
        case .oversizedEnvelope:
            "That saved inspiration is too large."
        case .invalidEnvelope:
            "That saved inspiration is not valid."
        case .fileCollision:
            "That saved inspiration conflicts with an existing import."
        case .oversizedAsset:
            "That shared video is too large to import."
        }
    }
}

enum InspirationLinkCanonicalizer {
    static let maximumURLLength = 2_048

    static func canonicalize(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf16.count <= maximumURLLength,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let originalHost = components.host?.lowercased(),
              isEligibleHost(originalHost) else {
            throw InspirationShareTransportError.unsupportedURL
        }

        components.scheme = "https"
        components.host = originalHost
        components.fragment = nil
        if components.port == 443 {
            components.port = nil
        }

        let platform = platform(forHost: originalHost)
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                if name.hasPrefix("utm_") {
                    return false
                }
                switch platform {
                case .instagram:
                    return name != "igsh"
                case .youtube:
                    return name != "si" && name != "feature"
                case .tiktok:
                    return name != "share_id"
                case .threads, .web:
                    return true
                }
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        guard let result = components.url,
              result.absoluteString.utf16.count <= maximumURLLength else {
            throw InspirationShareTransportError.invalidURL
        }
        return result
    }

    static func platform(for url: URL) -> InspirationPlatform {
        platform(forHost: url.host?.lowercased() ?? "")
    }

    private static func platform(forHost host: String) -> InspirationPlatform {
        switch host {
        case "instagram.com", "www.instagram.com", "m.instagram.com":
            .instagram
        case "tiktok.com", "www.tiktok.com", "m.tiktok.com", "vm.tiktok.com":
            .tiktok
        case "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be":
            .youtube
        case "threads.net", "www.threads.net":
            .threads
        default:
            .web
        }
    }

    private static func isEligibleHost(_ host: String) -> Bool {
        guard host != "localhost",
              !host.hasSuffix(".local"),
              host.contains("."),
              !host.contains(":"),
              !isIPv4Literal(host) else {
            return false
        }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
            return String(value) == part || (part.count > 1 && part.allSatisfy(\.isNumber))
        }
    }
}

enum InspirationSharedTextExtractor {
    static func extractCanonicalURL(from text: String) throws -> URL {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let canonicalURLs = try detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .map { try InspirationLinkCanonicalizer.canonicalize($0.absoluteString) }

        var unique: [String: URL] = [:]
        for url in canonicalURLs {
            unique[url.absoluteString] = url
        }
        guard unique.count == 1, let url = unique.values.first else {
            throw InspirationShareTransportError.expectedOneURL
        }
        return url
    }

    static func captionExcludingLinks(from values: [String]) -> String? {
        var unique: [String] = []
        for value in values {
            let cleaned = removingLinks(from: value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !unique.contains(cleaned) else { continue }
            unique.append(cleaned)
        }
        let combined = unique.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { return nil }
        return String(combined.prefix(20_000))
    }

    private static func removingLinks(from text: String) -> String {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        for match in detector.matches(in: text, options: [], range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            result.removeSubrange(swiftRange)
        }
        return result
            .split(whereSeparator: \Character.isNewline)
            .map { $0.split(whereSeparator: \Character.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct InspirationShareResolvedCandidate: Equatable, Sendable {
    let url: URL
    let sourceCaption: String?
}

enum InspirationShareCandidateResolver {
    static func resolve(urlValues: [String], textValues: [String]) throws -> URL {
        if !urlValues.isEmpty {
            let canonicalURLs = try urlValues.map(InspirationLinkCanonicalizer.canonicalize)
            let unique = Dictionary(
                canonicalURLs.map { ($0.absoluteString, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            guard unique.count == 1, let result = unique.values.first else {
                throw InspirationShareTransportError.expectedOneURL
            }
            return result
        }
        return try InspirationSharedTextExtractor.extractCanonicalURL(
            from: textValues.joined(separator: "\n")
        )
    }

    static func resolveCandidate(
        urlValues: [String],
        textValues: [String]
    ) throws -> InspirationShareResolvedCandidate {
        InspirationShareResolvedCandidate(
            url: try resolve(urlValues: urlValues, textValues: textValues),
            sourceCaption: InspirationSharedTextExtractor.captionExcludingLinks(from: textValues)
        )
    }
}

enum InspirationSavedPostTitlePolicy {
    static let maximumLength = 160

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumLength))
    }
}

struct InspirationShareEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3
    static let readableSchemaVersions = 1...currentSchemaVersion

    var schemaVersion: Int
    var id: UUID
    var capturedAt: Date
    var workspaceHintID: UUID?
    var canonicalURLString: String
    var platform: InspirationPlatform
    var creatorObservation: String
    var sourceCaption: String?
    var sourceTitle: String?
    var sourceCreatorName: String?
    var sourceCreatorHandle: String?
    var sourceTranscript: String?
    var visualObservations: [String]?
    var analyzedInputs: [String]?
    var sourceDurationSeconds: Int?
    var shapeResultJSON: String?
    var saveMode: InspirationSaveMode?
    var sharedVideoFilename: String?
    var sharedThumbnailFilename: String?

    init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        workspaceHintID: UUID?,
        canonicalURLString: String,
        platform: InspirationPlatform,
        creatorObservation: String = "",
        sourceCaption: String? = nil,
        sourceTitle: String? = nil,
        sourceCreatorName: String? = nil,
        sourceCreatorHandle: String? = nil,
        sourceTranscript: String? = nil,
        visualObservations: [String]? = nil,
        analyzedInputs: [String]? = nil,
        sourceDurationSeconds: Int? = nil,
        shapeResultJSON: String? = nil,
        saveMode: InspirationSaveMode? = nil,
        sharedVideoFilename: String? = nil,
        sharedThumbnailFilename: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.capturedAt = capturedAt
        self.workspaceHintID = workspaceHintID
        self.canonicalURLString = canonicalURLString
        self.platform = platform
        self.creatorObservation = creatorObservation
        self.sourceCaption = sourceCaption
        self.sourceTitle = sourceTitle
        self.sourceCreatorName = sourceCreatorName
        self.sourceCreatorHandle = sourceCreatorHandle
        self.sourceTranscript = sourceTranscript
        self.visualObservations = visualObservations
        self.analyzedInputs = analyzedInputs
        self.sourceDurationSeconds = sourceDurationSeconds
        self.shapeResultJSON = shapeResultJSON
        self.saveMode = saveMode
        self.sharedVideoFilename = sharedVideoFilename
        self.sharedThumbnailFilename = sharedThumbnailFilename
    }
}

enum InspirationSaveMode: String, Codable, Equatable, Sendable {
    case withRemix
    case originalOnly
}

enum InspirationSharedAssetKind: String, Sendable {
    case video
    case thumbnail

    var maximumBytes: Int64 {
        switch self {
        case .video: 250 * 1_024 * 1_024
        case .thumbnail: 10 * 1_024 * 1_024
        }
    }
}

struct InspirationSharedAssetStore {
    private let rootDirectoryURL: URL
    private let appliesFileProtection: Bool
    private let fileManager: FileManager

    init(
        rootDirectoryURL: URL,
        appliesFileProtection: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.appliesFileProtection = appliesFileProtection
        self.fileManager = fileManager
    }

    init(fileManager: FileManager = .default) throws {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: InspirationSharedContainer.appGroupIdentifier
        ) else {
            throw InspirationShareTransportError.unavailableSharedContainer
        }
        self.init(
            rootDirectoryURL: containerURL.appendingPathComponent(
                InspirationSharedContainer.incomingDirectoryName,
                isDirectory: true
            ),
            appliesFileProtection: true,
            fileManager: fileManager
        )
    }

    func stageFile(from sourceURL: URL, id: UUID, kind: InspirationSharedAssetKind) throws -> String {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? 0) <= kind.maximumBytes else {
            throw InspirationShareTransportError.oversizedAsset
        }
        try ensureDirectory()
        let rawExtension = sourceURL.pathExtension.lowercased()
        let safeExtension = rawExtension.isEmpty || rawExtension.count > 10 ||
            !rawExtension.allSatisfy({ $0.isLetter || $0.isNumber })
            ? (kind == .video ? "mov" : "jpg")
            : rawExtension
        let filename = "\(id.uuidString).\(kind.rawValue).\(safeExtension)"
        let destinationURL = try url(for: filename)
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw InspirationShareTransportError.fileCollision
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            if appliesFileProtection {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: destinationURL.path
                )
            }
            return filename
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func stageData(
        _ data: Data,
        id: UUID,
        kind: InspirationSharedAssetKind,
        fileExtension: String
    ) throws -> String {
        guard Int64(data.count) <= kind.maximumBytes,
              !fileExtension.isEmpty,
              fileExtension.count <= 10,
              fileExtension.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw InspirationShareTransportError.oversizedAsset
        }
        try ensureDirectory()
        let filename = "\(id.uuidString).\(kind.rawValue).\(fileExtension.lowercased())"
        let destinationURL = try url(for: filename)
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw InspirationShareTransportError.fileCollision
        }
        do {
            try data.write(
                to: destinationURL,
                options: appliesFileProtection
                    ? [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    : [.atomic]
            )
            return filename
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func assetURL(filename: String) throws -> URL {
        let url = try url(for: filename)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    func data(filename: String, maximumBytes: Int) throws -> Data {
        let url = try assetURL(filename: filename)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= maximumBytes else {
            throw InspirationShareTransportError.oversizedAsset
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func remove(filename: String?) {
        guard let filename, let url = try? url(for: filename) else { return }
        try? fileManager.removeItem(at: url)
    }

    func finalizeStagedFile(
        _ filename: String?,
        taskWasCancelled: Bool
    ) -> String? {
        guard taskWasCancelled else { return filename }
        remove(filename: filename)
        return nil
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectoryURL,
            withIntermediateDirectories: true,
            attributes: appliesFileProtection
                ? [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                : nil
        )
    }

    private func url(for filename: String) throws -> URL {
        guard !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.hasPrefix(".") else {
            throw InspirationShareTransportError.invalidEnvelope
        }
        return rootDirectoryURL.appendingPathComponent(filename, isDirectory: false)
    }
}

struct InspirationImportQueueStore {
    static let maximumEnvelopeBytes = 128 * 1_024

    private let rootDirectoryURL: URL
    private let appliesFileProtection: Bool
    private let fileManager: FileManager

    init(
        rootDirectoryURL: URL,
        appliesFileProtection: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.appliesFileProtection = appliesFileProtection
        self.fileManager = fileManager
    }

    init(fileManager: FileManager = .default) throws {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: InspirationSharedContainer.appGroupIdentifier
        ) else {
            throw InspirationShareTransportError.unavailableSharedContainer
        }
        self.init(
            rootDirectoryURL: containerURL.appendingPathComponent(
                InspirationSharedContainer.incomingDirectoryName,
                isDirectory: true
            ),
            appliesFileProtection: true,
            fileManager: fileManager
        )
    }

    func enqueue(_ envelope: InspirationShareEnvelope) throws {
        guard envelope.schemaVersion == InspirationShareEnvelope.currentSchemaVersion,
              let canonicalURL = try? InspirationLinkCanonicalizer.canonicalize(envelope.canonicalURLString),
              canonicalURL.absoluteString == envelope.canonicalURLString,
              envelope.creatorObservation.utf16.count <= 2_000,
              (envelope.sourceTitle?.utf16.count ?? 0) <= 500,
              (envelope.sourceCreatorName?.utf16.count ?? 0) <= 160,
              (envelope.sourceCreatorHandle?.utf16.count ?? 0) <= 160,
              (envelope.sourceCaption?.utf16.count ?? 0) <= 20_000,
              (envelope.sourceTranscript?.utf16.count ?? 0) <= 20_000,
              (envelope.shapeResultJSON?.utf16.count ?? 0) <= 40_000,
              (envelope.visualObservations?.count ?? 0) <= 20,
              envelope.visualObservations?.allSatisfy({ $0.utf16.count <= 2_000 }) ?? true,
              (envelope.analyzedInputs?.count ?? 0) <= 5 else {
            throw InspirationShareTransportError.invalidEnvelope
        }

        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEnvelopeBytes else {
            throw InspirationShareTransportError.oversizedEnvelope
        }

        try ensureDirectory()
        let destinationURL = url(for: envelope.id)
        if fileManager.fileExists(atPath: destinationURL.path) {
            let existing = try decoder.decode(
                InspirationShareEnvelope.self,
                from: Data(contentsOf: destinationURL)
            )
            guard existing == envelope else {
                throw InspirationShareTransportError.fileCollision
            }
            return
        }

        let temporaryURL = rootDirectoryURL.appendingPathComponent(
            ".\(envelope.id.uuidString).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL, options: .atomic)
            if appliesFileProtection {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: temporaryURL.path
                )
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    func pending() throws -> [InspirationShareEnvelope] {
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .map { url in
            let data = try Data(contentsOf: url)
            let envelope = try decoder.decode(InspirationShareEnvelope.self, from: data)
            guard InspirationShareEnvelope.readableSchemaVersions.contains(envelope.schemaVersion) else {
                throw InspirationShareTransportError.invalidEnvelope
            }
            return envelope
        }
        .sorted {
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func remove(id: UUID) throws {
        let destinationURL = url(for: id)
        guard fileManager.fileExists(atPath: destinationURL.path) else { return }
        try fileManager.removeItem(at: destinationURL)
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else { return }
        try fileManager.removeItem(at: rootDirectoryURL)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectoryURL,
            withIntermediateDirectories: true,
            attributes: appliesFileProtection
                ? [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                : nil
        )
    }

    private func url(for id: UUID) -> URL {
        rootDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum InspirationWorkspaceHintStore {
    static func load(defaults: UserDefaults?) -> UUID? {
        defaults?
            .string(forKey: InspirationSharedContainer.activeWorkspaceHintKey)
            .flatMap(UUID.init(uuidString:))
    }

    static func save(_ id: UUID?, defaults: UserDefaults?) {
        if let id {
            defaults?.set(id.uuidString, forKey: InspirationSharedContainer.activeWorkspaceHintKey)
        } else {
            defaults?.removeObject(forKey: InspirationSharedContainer.activeWorkspaceHintKey)
        }
    }
}
