import AVFoundation
import Combine
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum PostVoiceRecordingPolicy {
    static func recordings(
        from attachments: [CreatorAttachment],
        briefID: UUID
    ) -> [CreatorAttachment] {
        attachments
            .filter { $0.briefID == briefID && isVoiceRecording($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func isVoiceRecording(_ attachment: CreatorAttachment) -> Bool {
        guard attachment.ownerKind == .referenceFile else { return false }
        if UTType(attachment.uniformTypeIdentifier)?.conforms(to: .audio) == true { return true }
        let fileExtension = URL(fileURLWithPath: attachment.fileName).pathExtension.lowercased()
        return ["m4a", "mp3", "wav", "aac", "aiff", "caf"].contains(fileExtension)
    }

    static func displayTitle(_ attachment: CreatorAttachment) -> String {
        let title = attachment.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Voice recording" : title
    }
}

@MainActor
final class PostVoiceRecordingPlaybackController: ObservableObject {
    @Published private(set) var currentAttachmentID: UUID?
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var completionTask: Task<Void, Never>?

    func toggle(_ attachment: CreatorAttachment) throws {
        if currentAttachmentID == attachment.id, player?.isPlaying == true {
            stop()
            return
        }

        guard let data = attachment.cloudData else {
            throw PostVoiceRecordingPlaybackError.audioUnavailable
        }
        stop()
        try activatePlaybackSession()
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        guard player.play() else { throw PostVoiceRecordingPlaybackError.couldNotStart }
        self.player = player
        currentAttachmentID = attachment.id
        isPlaying = true
        monitorCompletion()
    }

    func stop() {
        completionTask?.cancel()
        completionTask = nil
        player?.stop()
        player = nil
        currentAttachmentID = nil
        isPlaying = false
        deactivatePlaybackSession()
    }

    private func monitorCompletion() {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                guard self.player?.isPlaying == true else {
                    self.completionTask = nil
                    self.player = nil
                    self.currentAttachmentID = nil
                    self.isPlaying = false
                    self.deactivatePlaybackSession()
                    return
                }
            }
        }
    }

    private func activatePlaybackSession() throws {
#if !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
#endif
    }

    private func deactivatePlaybackSession() {
#if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}

private enum PostVoiceRecordingPlaybackError: LocalizedError {
    case audioUnavailable
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .audioUnavailable: "The original recording is still downloading to this device."
        case .couldNotStart: "That recording could not begin playing."
        }
    }
}

struct PostVoiceRecordingsSection: View {
    let recordings: [CreatorAttachment]
    let onAdd: (() -> Void)?
    let onDownload: (CreatorAttachment) -> Void
    let onDelete: (CreatorAttachment) -> Void
    let onTitleChange: (CreatorAttachment, String) -> Bool
    let onPlaybackError: (String) -> Void
    @StateObject private var playback = PostVoiceRecordingPlaybackController()
    @State private var selectedRecordingID: UUID?

    init(
        recordings: [CreatorAttachment],
        onAdd: (() -> Void)? = nil,
        onDownload: @escaping (CreatorAttachment) -> Void,
        onDelete: @escaping (CreatorAttachment) -> Void,
        onTitleChange: @escaping (CreatorAttachment, String) -> Bool,
        onPlaybackError: @escaping (String) -> Void
    ) {
        self.recordings = recordings
        self.onAdd = onAdd
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onTitleChange = onTitleChange
        self.onPlaybackError = onPlaybackError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(
                title: "Voice recordings",
                trailing: recordings.count == 1 ? "1 recording" : "\(recordings.count) recordings"
            )

            ForEach(recordings) { recording in
                recordingRow(recording)
            }

            if let onAdd {
                AgentBlockAddActionButton(title: "Add voice recording", action: onAdd)
            }
        }
        .onDisappear { playback.stop() }
        .navigationDestination(item: $selectedRecordingID) { recordingID in
            if let recording = recordings.first(where: { $0.id == recordingID }) {
                VoiceRecordingDetailPage(
                    title: recording.displayTitle,
                    transcript: recording.voiceTranscript,
                    recordedAt: recording.createdAt,
                    durationSeconds: recording.voiceDurationSeconds,
                    byteCount: recording.byteCount,
                    downloadURL: nil,
                    isDownloadEnabled: recording.cloudData != nil,
                    onDownload: { onDownload(recording) },
                    onDelete: { delete(recording) },
                    onTitleChange: { onTitleChange(recording, $0) }
                )
            }
        }
    }

    private func recordingRow(_ recording: CreatorAttachment) -> some View {
#if targetEnvironment(macCatalyst)
        recordingContent(recording, showsDeleteButton: true)
#else
        AgentSwipeDeleteRow(onDelete: { delete(recording) }) {
            recordingContent(recording, showsDeleteButton: false)
        }
#endif
    }

    private func recordingContent(
        _ recording: CreatorAttachment,
        showsDeleteButton: Bool
    ) -> some View {
        let isThisPlaying = playback.currentAttachmentID == recording.id && playback.isPlaying

        return HStack(spacing: AgentSpacing.x2) {
            Button {
                selectedRecordingID = recording.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PostVoiceRecordingPolicy.displayTitle(recording))
                        .font(.agentHeadline)
                        .foregroundStyle(Color.agentText)
                    Text(recording.cloudData == nil
                        ? "Waiting for original audio"
                        : recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(PostVoiceRecordingPolicy.displayTitle(recording))")
            .accessibilityHint("Shows the recording transcript and details")

            HStack(spacing: 0) {
                Button {
                    do {
                        try playback.toggle(recording)
                    } catch {
                        onPlaybackError(error.localizedDescription)
                    }
                } label: {
                    AgentIconView(isThisPlaying ? .stop : .play, size: 16)
                        .foregroundStyle(Color.agentText)
                        .offset(x: isThisPlaying ? 0 : 1)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(AgentPressButtonStyle())
                .contentShape(.rect)
                .accessibilityLabel(isThisPlaying ? "Stop Voice Spark playback" : "Play Voice Spark recording")

                Button {
                    onDownload(recording)
                } label: {
                    AgentIconView(.download, size: 16)
                        .foregroundStyle(Color.agentText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(AgentPressButtonStyle())
                .contentShape(.rect)
                .disabled(recording.cloudData == nil)
                .opacity(recording.cloudData == nil ? 0.34 : 1)
                .accessibilityLabel("Save Voice Spark audio")

                if showsDeleteButton {
                    Button(role: .destructive) {
                        delete(recording)
                    } label: {
                        AgentIconView(.trash, size: 16)
                            .foregroundStyle(Color.agentDestructive)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())
                    .accessibilityLabel("Delete Voice Spark recording")
                }
            }
        }
        .padding(.horizontal, AgentSpacing.x3)
        .padding(.vertical, AgentSpacing.x2)
        .frame(minHeight: 60)
        .background(recordingRecordBackground, in: .rect(cornerRadius: AgentRadius.card))
        .agentSurfaceChrome(
            cornerRadius: AgentRadius.card,
            borderColor: recordingRecordBorder,
            role: recordingRecordChromeRole
        )
    }

    private var recordingRecordBackground: Color {
#if targetEnvironment(macCatalyst)
        Color.agentWarmWhite
#else
        Color.agentSurface
#endif
    }

    private var recordingRecordBorder: Color? {
#if targetEnvironment(macCatalyst)
        Color.agentPureBlack.opacity(0.22)
#else
        nil
#endif
    }

    private var recordingRecordChromeRole: AgentSurfaceRole {
#if targetEnvironment(macCatalyst)
        .structural
#else
        .card
#endif
    }

    private func delete(_ recording: CreatorAttachment) {
        if playback.currentAttachmentID == recording.id { playback.stop() }
        if selectedRecordingID == recording.id { selectedRecordingID = nil }
        onDelete(recording)
    }
}

enum PostMediaPresentationPolicy {
    static func resolvedCoverID(preferredID: UUID?, mediaIDs: [UUID]) -> UUID? {
        if let preferredID, mediaIDs.contains(preferredID) { return preferredID }
        return mediaIDs.first
    }

    static func sourceAspectRatio(
        pixelWidth: CGFloat,
        pixelHeight: CGFloat
    ) -> CGFloat {
        guard pixelWidth.isFinite,
              pixelHeight.isFinite,
              pixelWidth > 0,
              pixelHeight > 0
        else { return 1 }
        return pixelWidth / pixelHeight
    }
}

struct PostMediaFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PostMediaExportRequest {
    let document: PostMediaFileDocument
    let contentType: UTType
    let fileName: String

    init?(attachment: CreatorAttachment, preferredFileName: String? = nil) {
        guard let data = attachment.cloudData else { return nil }
        document = PostMediaFileDocument(data: data)
        contentType = UTType(attachment.uniformTypeIdentifier) ?? .data
        let candidate = URL(fileURLWithPath: preferredFileName ?? attachment.fileName).lastPathComponent
        fileName = candidate.isEmpty ? "post-media" : candidate
    }
}

struct AgentQuietSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isEmphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.agentSubtext.weight(isEmphasized ? .semibold : .medium))
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isEmphasized ? AgentActionButtonTheme.primaryFill : AgentActionButtonTheme.secondaryFill,
                in: .rect(cornerRadius: AgentActionButtonTheme.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AgentActionButtonTheme.radius)
                    .stroke(AgentActionButtonTheme.border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(AgentButtonPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .animation(
                AgentButtonPressFeedback.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private actor PostMediaPreviewFactory {
    static let shared = PostMediaPreviewFactory()

    func makePreviewData(
        from data: Data,
        kind: AttachmentKind,
        fileExtension: String
    ) async -> Data? {
        switch kind {
        case .photo:
            return imagePreviewData(from: data)
        case .video:
            return await videoPreviewData(from: data, fileExtension: fileExtension)
        case .document, .other:
            return nil
        }
    }

    private func imagePreviewData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }

    private func videoPreviewData(from data: Data, fileExtension: String) async -> Data? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-cy-media-preview", isDirectory: true)
        let safeExtension = fileExtension.isEmpty ? "mov" : fileExtension
        let url = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(safeExtension)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }

            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1_600, height: 1_600)
            let result = try await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
            return UIImage(cgImage: result.image).jpegData(compressionQuality: 0.82)
        } catch {
            return nil
        }
    }
}

@MainActor
enum PostMediaImportService {
    static let maximumByteCount = 45 * 1_024 * 1_024

    struct Result: Equatable {
        var addedCount = 0
        var oversizedCount = 0
        var failedCount = 0

        var notice: String? {
            if oversizedCount > 0 {
                return "Choose photos or videos smaller than 45 MB each."
            }
            if failedCount > 0 {
                return "One media item could not be added."
            }
            return nil
        }
    }

    static func add(
        items: [PhotosPickerItem],
        briefID: UUID,
        output: PlatformOutput,
        workspaceID: UUID?,
        asSeparateCover: Bool = false,
        context: ModelContext
    ) async -> Result {
        var result = Result()

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    result.failedCount += 1
                    continue
                }
                guard data.count <= maximumByteCount else {
                    result.oversizedCount += 1
                    continue
                }

                let type = item.supportedContentTypes.first ?? .data
                let kind: AttachmentKind = type.conforms(to: .movie) ? .video : .photo
                let fileExtension = type.preferredFilenameExtension ?? (kind == .video ? "mov" : "jpg")
                let previewData = await PostMediaPreviewFactory.shared.makePreviewData(
                    from: data,
                    kind: kind,
                    fileExtension: fileExtension
                )
                let attachment = CreatorAttachment(
                    ownerKind: .postMedia,
                    briefID: briefID,
                    platformOutputID: output.id,
                    fileName: "\(asSeparateCover ? "cover" : "media")-\(UUID().uuidString.prefix(8)).\(fileExtension)",
                    kind: kind,
                    uniformTypeIdentifier: type.identifier,
                    byteCount: Int64(data.count),
                    localRelativePath: "",
                    cloudData: data,
                    previewData: previewData,
                    isCoverOnly: asSeparateCover,
                    syncState: .synced
                )
                attachment.workspaceID = workspaceID

                if asSeparateCover {
                    let outputID = output.id
                    let existingCoverUploads = (try? context.fetch(FetchDescriptor<CreatorAttachment>(
                        predicate: #Predicate {
                            $0.platformOutputID == outputID && $0.isCoverOnly
                        }
                    ))) ?? []
                    for existing in existingCoverUploads { context.delete(existing) }
                    output.coverAttachmentID = attachment.id
                } else if output.coverAttachmentID == nil {
                    output.coverAttachmentID = attachment.id
                }

                context.insert(attachment)
                result.addedCount += 1
                if asSeparateCover { break }
            } catch {
                result.failedCount += 1
            }
        }

        do {
            try context.save()
        } catch {
            result.failedCount += max(1, result.addedCount)
        }
        return result
    }
}

@MainActor
enum PostMediaPreviewBackfillService {
    static func populateMissingPreviews(
        for attachments: [CreatorAttachment],
        context: ModelContext
    ) async {
        var changed = false
        for attachment in attachments where attachment.previewData == nil {
            guard let data = attachment.cloudData,
                  attachment.kind == .photo || attachment.kind == .video else { continue }
            let fileExtension = URL(fileURLWithPath: attachment.fileName).pathExtension
            attachment.previewData = await PostMediaPreviewFactory.shared.makePreviewData(
                from: data,
                kind: attachment.kind,
                fileExtension: fileExtension
            )
            changed = changed || attachment.previewData != nil
        }
        if changed { try? context.save() }
    }
}

struct PostMediaSpotlight: View {
    @Environment(\.colorScheme) private var colorScheme

    let attachments: [CreatorAttachment]
    let coverAttachmentID: UUID?
    let onOpen: (CreatorAttachment) -> Void
    let onDownload: (CreatorAttachment) -> Void

    @State private var selectedAttachmentID: UUID?

    init(
        attachments: [CreatorAttachment],
        coverAttachmentID: UUID?,
        onOpen: @escaping (CreatorAttachment) -> Void,
        onDownload: @escaping (CreatorAttachment) -> Void
    ) {
        self.attachments = attachments
        self.coverAttachmentID = coverAttachmentID
        self.onOpen = onOpen
        self.onDownload = onDownload
        _selectedAttachmentID = State(initialValue: PostMediaPresentationPolicy.resolvedCoverID(
            preferredID: coverAttachmentID,
            mediaIDs: attachments.map(\.id)
        ))
    }

    var body: some View {
        TabView(selection: $selectedAttachmentID) {
            ForEach(attachments) { attachment in
                PostMediaSpotlightPage(attachment: attachment) {
                    onOpen(attachment)
                }
                .tag(attachment.id as UUID?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(currentAspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: AgentRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.card)
                .stroke(
                    colorScheme == .dark
                        ? Color.agentPureWhite.opacity(0.10)
                        : Color.agentPureBlack.opacity(0.10),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if currentAttachment?.id == resolvedCoverID {
                spotlightPill("COVER")
                    .padding(AgentSpacing.x3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if attachments.count > 1, let currentIndex {
                spotlightPill("\(currentIndex + 1) / \(attachments.count)")
                    .padding(AgentSpacing.x3)
            }
        }
        .overlay(alignment: .bottom) {
            if attachments.count > 1 {
                HStack(spacing: 5) {
                    ForEach(attachments) { attachment in
                        Circle()
                            .fill(
                                attachment.id == selectedAttachmentID
                                    ? Color.agentPureWhite
                                    : Color.agentPureWhite.opacity(0.45)
                            )
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, AgentSpacing.x3)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let currentAttachment {
                Button {
                    onDownload(currentAttachment)
                } label: {
                    AgentIconView(.download, size: 12)
                        .foregroundStyle(Color.agentPureWhite)
                        .frame(width: 28, height: 28)
                        .background(Color.agentPureBlack.opacity(0.58), in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(AgentPressButtonStyle())
                .padding(AgentSpacing.x2)
                .accessibilityLabel("Download original \(currentAttachment.fileName)")
            }
        }
        .background(Color.agentCanvas)
        .onChange(of: attachmentIDs) { _, ids in
            if let selectedAttachmentID, ids.contains(selectedAttachmentID) { return }
            selectedAttachmentID = resolvedCoverID
        }
        .onChange(of: coverAttachmentID) { _, _ in
            if selectedAttachmentID == nil { selectedAttachmentID = resolvedCoverID }
        }
    }

    private var attachmentIDs: [UUID] { attachments.map(\.id) }
    private var resolvedCoverID: UUID? {
        PostMediaPresentationPolicy.resolvedCoverID(
            preferredID: coverAttachmentID,
            mediaIDs: attachmentIDs
        )
    }
    private var currentAttachment: CreatorAttachment? {
        attachments.first(where: { $0.id == selectedAttachmentID }) ?? attachments.first
    }
    private var currentIndex: Int? {
        guard let currentAttachment else { return nil }
        return attachments.firstIndex(where: { $0.id == currentAttachment.id })
    }
    private var currentAspectRatio: CGFloat {
        guard let data = currentAttachment?.previewData ?? currentAttachment?.cloudData,
              let image = UIImage(data: data) else { return 1 }
        return PostMediaPresentationPolicy.sourceAspectRatio(
            pixelWidth: image.size.width,
            pixelHeight: image.size.height
        )
    }

    private func spotlightPill(_ title: String) -> some View {
        Text(title)
            .font(.agentMetadata.weight(.semibold))
            .tracking(0.45)
            .foregroundStyle(Color.agentPureWhite)
            .padding(.horizontal, AgentSpacing.x2)
            .frame(minHeight: 24)
            .background(Color.agentPureBlack.opacity(0.58), in: .capsule)
    }
}

private struct PostMediaSpotlightPage: View {
    let attachment: CreatorAttachment
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            Color.agentCanvas
            if let data = attachment.previewData ?? attachment.cloudData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                AgentIconView(attachment.kind == .video ? .video : .image, size: 30)
                    .foregroundStyle(Color.agentSecondary)
            }

            if attachment.kind == .video {
                AgentIconView(.play, size: 20)
                    .foregroundStyle(Color.agentPureWhite)
                    .frame(width: 48, height: 48)
                    .background(Color.agentPureBlack.opacity(0.58), in: .circle)
            }
        }
        .clipped()
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(attachment.kind == .video ? "Open video" : "Open photo")
    }
}

struct PostMediaActionBar: View {
    @Binding var selection: [PhotosPickerItem]
    let isImporting: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button("Edit", action: onEdit)
                .buttonStyle(AgentPressButtonStyle())
                .frame(maxWidth: .infinity, minHeight: 44)

            Rectangle()
                .fill(Color.agentHairline)
                .frame(width: 1, height: 18)

            PhotosPicker(
                selection: $selection,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current
            ) {
                HStack(spacing: AgentSpacing.x2) {
                    Text(isImporting ? "Adding" : "Add")
                    if isImporting { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(AgentPressButtonStyle())
            .disabled(isImporting)
        }
        .font(.agentSubtext.weight(.medium))
        .foregroundStyle(Color.agentText)
    }
}

struct PostMediaEmptyAddButton: View {
    @Binding var selection: [PhotosPickerItem]
    let isImporting: Bool

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current
        ) {
            HStack(spacing: AgentSpacing.x3) {
                AgentIconView(.image, size: 15)
                Text(isImporting ? "Adding media" : "Add photos or videos")
                Spacer()
                if isImporting { ProgressView().controlSize(.small) }
                else { AgentIconView(.add, size: 12) }
            }
            .font(.agentBody.weight(.semibold))
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.agentSelectionFill, in: .rect(cornerRadius: AgentRadius.button))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.button)
                    .stroke(Color.agentBorder, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(AgentPressButtonStyle())
        .disabled(isImporting)
    }
}

struct PostMediaManagerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let briefID: UUID
    let workspaceID: UUID?
    @Bindable var output: PlatformOutput
    @Query private var attachments: [CreatorAttachment]

    @State private var selectedMedia: [PhotosPickerItem] = []
    @State private var selectedCover: [PhotosPickerItem] = []
    @State private var isImportingMedia = false
    @State private var isImportingCover = false
    @State private var pendingRemoval: CreatorAttachment?
    @State private var exportRequest: PostMediaExportRequest?

    init(briefID: UUID, workspaceID: UUID?, output: PlatformOutput) {
        self.briefID = briefID
        self.workspaceID = workspaceID
        self.output = output
        let outputID = output.id
        _attachments = Query(
            filter: #Predicate<CreatorAttachment> { $0.platformOutputID == outputID },
            sort: \CreatorAttachment.createdAt
        )
    }

    var body: some View {
        let importingMedia = isImportingMedia
        let importingCover = isImportingCover
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    coverSurface

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(postMedia.enumerated()), id: \.element.id) { index, attachment in
                            PostMediaManagerRow(
                                attachment: attachment,
                                itemNumber: index + 1,
                                isCover: attachment.id == resolvedCoverID,
                                onSetCover: { setCover(attachment) },
                                onDownload: { requestExport(attachment) },
                                onRemove: { pendingRemoval = attachment }
                            )
                            if attachment.id != postMedia.last?.id {
                                Rectangle().fill(Color.agentHairline).frame(height: 1)
                            }
                        }
                    }
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.card)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }

                    VStack(spacing: AgentSpacing.x3) {
                        PhotosPicker(
                            selection: $selectedMedia,
                            maxSelectionCount: 10,
                            matching: .any(of: [.images, .videos]),
                            preferredItemEncoding: .current
                        ) {
                            PostMediaManagerActionLabel(
                                title: importingMedia ? "Adding media" : "Add photos or videos",
                                icon: .add,
                                showsProgress: importingMedia
                            )
                        }
                        .buttonStyle(AgentQuietSecondaryButtonStyle(isEmphasized: true))
                        .disabled(isImportingMedia || isImportingCover)

                        PhotosPicker(
                            selection: $selectedCover,
                            maxSelectionCount: 1,
                            matching: .images,
                            preferredItemEncoding: .current
                        ) {
                            PostMediaManagerActionLabel(
                                title: importingCover ? "Uploading cover" : "Upload separate cover",
                                icon: .image,
                                showsProgress: importingCover
                            )
                        }
                        .buttonStyle(AgentQuietSecondaryButtonStyle())
                        .disabled(isImportingMedia || isImportingCover)
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.vertical, AgentSpacing.x6)
            }
            .background(Color.agentCanvas)
            .navigationTitle("Edit media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.agentCanvas)
        .agentSheetDragIndicator()
        .onChange(of: selectedMedia) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMedia(items, asSeparateCover: false) }
        }
        .onChange(of: selectedCover) { _, items in
            guard !items.isEmpty else { return }
            Task { await importMedia(items, asSeparateCover: true) }
        }
        .confirmationDialog(
            "Remove this media?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { attachment in
            Button("Remove media", role: .destructive) { remove(attachment) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text("This removes the stored original from this post.")
        }
        .fileExporter(
            isPresented: exportPresented,
            document: exportRequest?.document,
            contentType: exportRequest?.contentType ?? .data,
            defaultFilename: exportRequest?.fileName ?? "post-media",
            onCompletion: handleExport
        )
        .task(id: previewKey) {
            await PostMediaPreviewBackfillService.populateMissingPreviews(
                for: postMedia,
                context: context
            )
        }
    }

    private var postMedia: [CreatorAttachment] {
        attachments.filter { $0.ownerKind == .postMedia }
    }
    private var resolvedCoverID: UUID? {
        PostMediaPresentationPolicy.resolvedCoverID(
            preferredID: output.coverAttachmentID,
            mediaIDs: postMedia.map(\.id)
        )
    }
    private var currentCover: CreatorAttachment? {
        postMedia.first { $0.id == resolvedCoverID }
    }
    private var previewKey: String {
        postMedia.map { "\($0.id.uuidString):\($0.previewData == nil ? 0 : 1)" }.joined(separator: "|")
    }
    private var exportPresented: Binding<Bool> {
        Binding(
            get: { exportRequest != nil },
            set: { if !$0 { exportRequest = nil } }
        )
    }

    private var coverSurface: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("Cover")
            if let currentCover {
                HStack(spacing: AgentSpacing.x4) {
                    PostMediaManagerThumbnail(attachment: currentCover)
                        .frame(width: 74, height: 92)
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(currentCover.isCoverOnly ? "Separate thumbnail" : "Media cover")
                            .font(.agentBody.weight(.semibold))
                        Text("Used in the Feed grid and marked in the post spotlight.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Add media or upload a separate thumbnail to set the cover.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .padding(AgentSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.agentSelectionFill, in: .rect(cornerRadius: AgentRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.card)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    private func setCover(_ attachment: CreatorAttachment) {
        guard attachment.id != resolvedCoverID else { return }
        if !attachment.isCoverOnly {
            for coverUpload in postMedia where coverUpload.isCoverOnly {
                context.delete(coverUpload)
            }
        }
        output.coverAttachmentID = attachment.id
        try? context.save()
    }

    private func remove(_ attachment: CreatorAttachment) {
        let remaining = postMedia.filter { $0.id != attachment.id }
        if output.coverAttachmentID == attachment.id || resolvedCoverID == attachment.id {
            output.coverAttachmentID = PostMediaPresentationPolicy.resolvedCoverID(
                preferredID: nil,
                mediaIDs: remaining.map(\.id)
            )
        }
        context.delete(attachment)
        try? context.save()
        pendingRemoval = nil
    }

    private func requestExport(_ attachment: CreatorAttachment) {
        guard let request = PostMediaExportRequest(attachment: attachment) else {
            appModel.notice = .error("That original is not available on this device yet.")
            return
        }
        exportRequest = request
    }

    private func handleExport(_ result: Result<URL, Error>) {
        defer { exportRequest = nil }
        switch result {
        case .success:
            appModel.notice = .info("Full-resolution media saved to Files.")
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                appModel.notice = .error("That media file could not be saved.")
            }
        }
    }

    private func importMedia(_ items: [PhotosPickerItem], asSeparateCover: Bool) async {
        if asSeparateCover { isImportingCover = true }
        else { isImportingMedia = true }
        defer {
            if asSeparateCover {
                isImportingCover = false
                selectedCover = []
            } else {
                isImportingMedia = false
                selectedMedia = []
            }
        }

        let result = await PostMediaImportService.add(
            items: items,
            briefID: briefID,
            output: output,
            workspaceID: workspaceID,
            asSeparateCover: asSeparateCover,
            context: context
        )
        if let notice = result.notice { appModel.notice = .info(notice) }
    }
}

private struct PostMediaManagerActionLabel: View {
    let title: String
    let icon: AgentIcon
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: AgentSpacing.x2) {
            AgentIconView(icon, size: 13)
            Text(title)
            if showsProgress { ProgressView().controlSize(.small) }
        }
    }
}

private struct PostMediaManagerRow: View {
    let attachment: CreatorAttachment
    let itemNumber: Int
    let isCover: Bool
    let onSetCover: () -> Void
    let onDownload: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            PostMediaManagerThumbnail(attachment: attachment)
                .frame(width: 68, height: 84)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                HStack(spacing: AgentSpacing.x2) {
                    Text(attachment.isCoverOnly ? "Separate cover" : "Media \(itemNumber)")
                        .font(.agentBody.weight(.semibold))
                    if isCover {
                        Text("COVER")
                            .font(.agentMetadata.weight(.semibold))
                            .padding(.horizontal, 6)
                            .frame(minHeight: 20)
                            .background(Color.agentText.opacity(0.09), in: .capsule)
                    }
                }
                Text(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)

                if !isCover {
                    Button("Use as cover", action: onSetCover)
                        .font(.agentSubtext.weight(.medium))
                        .foregroundStyle(Color.agentText)
                        .frame(minHeight: 32)
                        .buttonStyle(AgentPressButtonStyle())
                }
            }

            Spacer(minLength: AgentSpacing.x2)

            Menu {
                Button(action: onDownload) {
                    AgentIconLabel(title: "Download original", icon: .download)
                }
                Button(role: .destructive, action: onRemove) {
                    AgentIconLabel(title: "Remove", icon: .trash)
                }
            } label: {
                AgentIconView(.more)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Media options")
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x2)
        .frame(minHeight: 100)
    }
}

private struct PostMediaManagerThumbnail: View {
    let attachment: CreatorAttachment

    var body: some View {
        ZStack {
            Color.agentCanvas
            if let data = attachment.previewData ?? attachment.cloudData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AgentIconView(attachment.kind == .video ? .video : .image, size: 18)
                    .foregroundStyle(Color.agentSecondary)
            }
            if attachment.kind == .video {
                AgentIconView(.play, size: 13)
                    .foregroundStyle(Color.agentPureWhite)
                    .frame(width: 30, height: 30)
                    .background(Color.agentPureBlack.opacity(0.58), in: .circle)
            }
        }
        .clipped()
        .clipShape(.rect(cornerRadius: AgentRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AgentRadius.control)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }
}
