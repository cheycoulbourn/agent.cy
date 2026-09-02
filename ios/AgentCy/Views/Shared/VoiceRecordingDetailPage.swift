import AVFoundation
import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum VoiceRecordingDetailTitlePolicy {
    static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasChanges(current: String, saved: String) -> Bool {
        normalized(current) != normalized(saved)
    }
}

enum VoiceRecordingDetailTranscriptPolicy {
    static func normalized(_ transcript: String) -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VoiceRecordingDetailAction {
    case back
    case delete
}

struct VoiceRecordingDetailNavigationDecision: Equatable {
    let dismissesDetail: Bool
    let deletesRecording: Bool
}

enum VoiceRecordingDetailNavigationPolicy {
    static func decision(
        for action: VoiceRecordingDetailAction
    ) -> VoiceRecordingDetailNavigationDecision {
        switch action {
        case .back:
            VoiceRecordingDetailNavigationDecision(
                dismissesDetail: true,
                deletesRecording: false
            )
        case .delete:
            // The owning recording section clears its selected destination as
            // part of deletion. Dismissing here as well would pop twice and
            // can send the creator past the related post editor to Agenda.
            VoiceRecordingDetailNavigationDecision(
                dismissesDetail: false,
                deletesRecording: true
            )
        }
    }
}

enum VoiceRecordingDetailAudioState: Equatable {
    case ready
    case unavailable(message: String)
}

enum VoiceRecordingDetailAudioPolicy {
    static func state(hasPlayableAudio: Bool) -> VoiceRecordingDetailAudioState {
        hasPlayableAudio
            ? .ready
            : .unavailable(message: "The original audio isn’t available on this device.")
    }
}

enum VoiceRecordingPlaybackSource {
    case file(URL)
    case data(Data)

    fileprivate func makePlayer() throws -> AVAudioPlayer {
        switch self {
        case .file(let url):
            try AVAudioPlayer(contentsOf: url)
        case .data(let data):
            try AVAudioPlayer(data: data)
        }
    }
}

@MainActor
final class VoiceRecordingDetailPlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var completionTask: Task<Void, Never>?

    func toggle(_ source: VoiceRecordingPlaybackSource) throws {
        if player?.isPlaying == true {
            stop()
            return
        }

        stop()
        try activatePlaybackSession()
        do {
            let player = try source.makePlayer()
            player.prepareToPlay()
            guard player.play() else {
                throw VoiceRecordingDetailPlaybackError.couldNotStart
            }
            self.player = player
            isPlaying = true
            monitorCompletion()
        } catch {
            deactivatePlaybackSession()
            throw error
        }
    }

    func stop() {
        completionTask?.cancel()
        completionTask = nil
        player?.stop()
        player = nil
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

private enum VoiceRecordingDetailPlaybackError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "That recording could not begin playing."
    }
}

enum VoiceRecordingExportNaming {
    static func fileName(
        title: String?,
        recordedAt: Date,
        postTitle: String?,
        calendar: Calendar = .current
    ) -> String {
        let recordingTitle = sanitizedComponent(title ?? "")
        let postName = sanitizedComponent(postTitle ?? "")
        let components = calendar.dateComponents([.year, .month, .day], from: recordedAt)
        let date = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        var parts = [recordingTitle.isEmpty ? "Voice recording" : recordingTitle, date]
        if !postName.isEmpty { parts.append(postName) }
        return "\(parts.joined(separator: " - ")).m4a"
    }

    private static func sanitizedComponent(_ value: String) -> String {
        let withoutEmoji = value.filter { character in
            !character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && scalar.value > 0x238C)
            }
        }
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
        let safeScalars = withoutEmoji.unicodeScalars.map { scalar in
            unsafe.contains(scalar) ? " " : String(scalar)
        }.joined()
        let collapsed = safeScalars
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return String(collapsed.prefix(80))
    }
}

struct VoiceRecordingTransfer: Transferable {
    let sourceURL: URL
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Audio) { transfer in
            let fileManager = FileManager.default
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("AgentCy Recording Exports", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(transfer.fileName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: transfer.sourceURL, to: destination)
            return SentTransferredFile(destination)
        }
    }
}

struct VoiceRecordingDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let transcript: String
    let recordedAt: Date
    let durationSeconds: TimeInterval
    let byteCount: Int64?
    let playbackSource: VoiceRecordingPlaybackSource?
    let downloadURL: URL?
    let isDownloadEnabled: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onTitleChange: (String) -> Bool
    let onConnect: (() -> Void)?

    @State private var title: String
    @State private var savedTitle: String
    @State private var playbackErrorMessage: String?
    @StateObject private var playback = VoiceRecordingDetailPlaybackController()

    init(
        title: String,
        transcript: String,
        recordedAt: Date,
        durationSeconds: TimeInterval,
        byteCount: Int64?,
        playbackSource: VoiceRecordingPlaybackSource?,
        downloadURL: URL?,
        isDownloadEnabled: Bool,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onTitleChange: @escaping (String) -> Bool,
        onConnect: (() -> Void)? = nil
    ) {
        let normalizedTitle = VoiceRecordingDetailTitlePolicy.normalized(title)
        self.transcript = VoiceRecordingDetailTranscriptPolicy.normalized(transcript)
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.byteCount = byteCount
        self.playbackSource = playbackSource
        self.downloadURL = downloadURL
        self.isDownloadEnabled = isDownloadEnabled
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onTitleChange = onTitleChange
        self.onConnect = onConnect
        _title = State(initialValue: normalizedTitle)
        _savedTitle = State(initialValue: normalizedTitle)
        _playbackErrorMessage = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    titleSection
                    playbackSection
                    transcriptSection
                    detailsSection
                    connectToPostSection
                    bottomActions
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x5)
                .padding(.bottom, AgentLayout.bottomNavigationClearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.agentCanvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { playback.stop() }
    }

    private var header: some View {
        ZStack {
            MetaLabel("Recording")

            HStack {
                AgentToolbarIconButton(
                    title: "Back",
                    icon: .back,
                    action: { handle(.back) }
                )

                Spacer()

                AgentToolbarIconButton(
                    title: "Save recording title",
                    icon: .check,
                    isEnabled: hasTitleChanges,
                    action: saveTitle
                )
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.agentCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Title")
            TextField("Add a title (optional)", text: $title)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 54)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                .agentSurfaceChrome(cornerRadius: AgentRadius.card)
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Audio")

            switch VoiceRecordingDetailAudioPolicy.state(
                hasPlayableAudio: playbackSource != nil
            ) {
            case .ready:
                Button(action: togglePlayback) {
                    HStack(spacing: AgentSpacing.x3) {
                        AgentIconView(playback.isPlaying ? .stop : .play, size: 16)
                            .offset(x: playback.isPlaying ? 0 : 1)
                        Text(playback.isPlaying ? "Stop recording" : "Play recording")
                            .font(.agentSubtext.weight(.semibold))
                        Spacer(minLength: AgentSpacing.x3)
                        Text(Self.durationText(durationSeconds))
                            .font(.agentMetadata.monospacedDigit())
                            .foregroundStyle(Color.agentSecondary)
                    }
                    .foregroundStyle(Color.agentText)
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 54)
                    .contentShape(.rect)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.card)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityLabel(playback.isPlaying ? "Stop recording playback" : "Play recording")

            case .unavailable(let message):
                HStack(alignment: .top, spacing: AgentSpacing.x3) {
                    AgentIconView(.warning, size: 16)
                        .foregroundStyle(Color.agentSecondary)
                    Text(message)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AgentSpacing.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                .agentSurfaceChrome(cornerRadius: AgentRadius.card)
            }

            if let playbackErrorMessage {
                Text(playbackErrorMessage)
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentDestructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Playback error: \(playbackErrorMessage)")
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Transcript")
            Text(transcript.isEmpty ? "No transcript is available for this recording." : transcript)
                .font(.agentBody)
                .foregroundStyle(transcript.isEmpty ? Color.agentSecondary : Color.agentText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AgentSpacing.x4)
                .padding(.vertical, AgentSpacing.x4)
                .padding(.trailing, 60)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
                .agentSurfaceChrome(cornerRadius: AgentRadius.card)
                .overlay(alignment: .topTrailing) {
                    Button {
                        UIPasteboard.general.string = transcript
                    } label: {
                        AgentIconView(.copy, size: 16)
                            .foregroundStyle(Color.agentText)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(AgentPressButtonStyle())
                    .disabled(transcript.isEmpty)
                    .opacity(transcript.isEmpty ? 0.34 : 1)
                    .accessibilityLabel("Copy transcript")
                    .padding(.top, AgentSpacing.x1)
                    .padding(.trailing, AgentSpacing.x1)
                }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Details")
            VStack(spacing: 0) {
                detailRow("Recorded", value: recordedAt.formatted(date: .abbreviated, time: .shortened))
                Divider().overlay(Color.agentBorder)
                detailRow("Duration", value: Self.durationText(durationSeconds))
                if let byteCount {
                    Divider().overlay(Color.agentBorder)
                    detailRow("File size", value: ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                }
                Divider().overlay(Color.agentBorder)
                detailRow("Format", value: "M4A audio")
            }
            .padding(.horizontal, AgentSpacing.x4)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
            .agentSurfaceChrome(cornerRadius: AgentRadius.card)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x4) {
            Text(label)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
            Spacer(minLength: AgentSpacing.x4)
            Text(value)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, AgentSpacing.x3)
    }

    @ViewBuilder
    private var connectToPostSection: some View {
        if let onConnect {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                SectionRuleHeader(title: "Post")

                Button(action: onConnect) {
                    HStack(spacing: AgentSpacing.x3) {
                        AgentIconView(.link, size: 16)
                        Text("Connect to a post")
                            .font(.agentSubtext.weight(.semibold))
                        Spacer(minLength: AgentSpacing.x3)
                        AgentIconView(.forward, size: 14)
                            .foregroundStyle(Color.agentSecondary)
                    }
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(AgentPressButtonStyle())
                .accessibilityHint("Shows open posts that can receive this recording")
            }
        }
    }

    private var hasTitleChanges: Bool {
        VoiceRecordingDetailTitlePolicy.hasChanges(current: title, saved: savedTitle)
    }

    private var bottomActions: some View {
        HStack(spacing: 0) {
            Button(role: .destructive) {
                handle(.delete)
            } label: {
                bottomActionLabel("Delete", color: .agentDestructive)
            }
            .buttonStyle(AgentPressButtonStyle())
            .accessibilityLabel("Delete recording")

            Rectangle()
                .fill(Color.agentBorder)
                .frame(width: 1, height: 22)

            if let downloadURL {
                let transfer = VoiceRecordingTransfer(
                    sourceURL: downloadURL,
                    fileName: VoiceRecordingExportNaming.fileName(
                        title: title,
                        recordedAt: recordedAt,
                        postTitle: nil
                    )
                )
                ShareLink(
                    item: transfer,
                    preview: SharePreview(transfer.fileName)
                ) {
                    bottomActionLabel("Download", color: .agentText)
                }
                .buttonStyle(AgentPressButtonStyle())
                .disabled(!isDownloadEnabled)
                .opacity(isDownloadEnabled ? 1 : 0.34)
                .accessibilityLabel("Download recording")
            } else {
                Button(action: onDownload) {
                    bottomActionLabel("Download", color: .agentText)
                }
                .buttonStyle(AgentPressButtonStyle())
                .disabled(!isDownloadEnabled)
                .opacity(isDownloadEnabled ? 1 : 0.34)
                .accessibilityLabel("Download recording")
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
    }

    private func handle(_ action: VoiceRecordingDetailAction) {
        let decision = VoiceRecordingDetailNavigationPolicy.decision(for: action)
        if decision.dismissesDetail { dismiss() }
        if decision.deletesRecording { onDelete() }
    }

    @ViewBuilder
    private func bottomActionLabel(_ text: String, color: Color) -> some View {
#if targetEnvironment(macCatalyst)
        Text(text)
            .font(.agentSubtext.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 112)
            .frame(minHeight: 44)
            .contentShape(.rect)
#else
        Text(text)
            .font(.agentSubtext.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
#endif
    }

    private func saveTitle() {
        let normalizedTitle = VoiceRecordingDetailTitlePolicy.normalized(title)
        guard hasTitleChanges, onTitleChange(normalizedTitle) else { return }
        title = normalizedTitle
        savedTitle = normalizedTitle
    }

    private func togglePlayback() {
        guard let playbackSource else { return }
        do {
            playbackErrorMessage = nil
            try playback.toggle(playbackSource)
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
