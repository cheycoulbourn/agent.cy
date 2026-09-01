#if !targetEnvironment(macCatalyst)
import AVFoundation
import Combine
import Speech
import SwiftData
import SwiftUI

enum VoiceSparkAudioConfiguration {
    static let category: AVAudioSession.Category = .record
    static let mode: AVAudioSession.Mode = .default
    static let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]

    static func makeRecorderSettings() -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }
}

struct VoiceSparkCapture: Sendable {
    let temporaryURL: URL
    let transcript: String
    let durationSeconds: TimeInterval
}

@MainActor
final class VoiceSparkRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var startedAt: Date?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() async {
        errorMessage = nil

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is required to record a Voice Spark."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                VoiceSparkAudioConfiguration.category,
                mode: VoiceSparkAudioConfiguration.mode,
                options: VoiceSparkAudioConfiguration.options
            )
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-spark-\(UUID().uuidString.lowercased()).m4a")
            let recorder = try AVAudioRecorder(
                url: url,
                settings: VoiceSparkAudioConfiguration.makeRecorderSettings()
            )
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw VoiceSparkRecorderError.recordingCouldNotStart
            }

            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            isRecording = true
        } catch {
            errorMessage = "Voice Spark could not start recording. \(error.localizedDescription)"
            deactivateAudioSession()
        }
    }

    func stopAndTranscribe() async -> VoiceSparkCapture? {
        guard isRecording, let recordingURL else { return nil }
        let durationSeconds = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isRecording = false
        isTranscribing = true
        deactivateAudioSession()

        guard await speechAuthorization() == .authorized else {
            isTranscribing = false
            errorMessage = "Your recording was saved without a transcript. Allow Speech Recognition in Settings to transcribe future recordings."
            return VoiceSparkCapture(
                temporaryURL: recordingURL,
                transcript: "",
                durationSeconds: durationSeconds
            )
        }

        do {
            let transcript = try await transcribe(url: recordingURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            isTranscribing = false
            if transcript.isEmpty {
                errorMessage = "Your recording was saved, but no words were detected. You can still play it below."
            }
            return VoiceSparkCapture(
                temporaryURL: recordingURL,
                transcript: transcript,
                durationSeconds: durationSeconds
            )
        } catch {
            isTranscribing = false
            errorMessage = "Your recording was saved, but it could not be transcribed. You can still play it below."
            return VoiceSparkCapture(
                temporaryURL: recordingURL,
                transcript: "",
                durationSeconds: durationSeconds
            )
        }
    }

    func reset() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        isTranscribing = false
        startedAt = nil
        errorMessage = nil
        deactivateAudioSession()
        deleteRecording()
    }

    func finish() {
        deleteRecording()
        startedAt = nil
    }

    private func transcribe(url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            throw VoiceSparkRecorderError.speechRecognizerUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { continuation in
            let box = VoiceSparkRecognitionContinuation(continuation)
            box.task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume(throwing: error)
                } else if let result, result.isFinal {
                    box.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // The first-ever TCC prompt calls back on a system queue. `nonisolated`
    // keeps the callback free of this class's MainActor assumption — with it
    // inherited, the isolation check traps on first grant (crash reproduced
    // 2026-08-19, DEFECT-CAP-04-01).
    private nonisolated func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func deleteRecording() {
        guard let recordingURL else { return }
        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
    }
}

@MainActor
final class VoiceSparkPlaybackController: ObservableObject {
    @Published private(set) var currentRecordingID: UUID?
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var completionTask: Task<Void, Never>?

    func toggle(_ recording: VoiceSparkRecording) throws {
        if currentRecordingID == recording.id, player?.isPlaying == true {
            stop()
            return
        }

        stop()
        try activatePlaybackSession()
        let url = try VoiceSparkRecordingStore.audioURL(for: recording)
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        guard player.play() else { throw VoiceSparkPlaybackError.couldNotStart }
        self.player = player
        currentRecordingID = recording.id
        isPlaying = true
        monitorCompletion()
    }

    func stop() {
        completionTask?.cancel()
        completionTask = nil
        player?.stop()
        player = nil
        currentRecordingID = nil
        isPlaying = false
        deactivatePlaybackSession()
    }

    private func monitorCompletion() {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                guard let player = self.player, player.isPlaying else {
                    self.completionTask = nil
                    self.player = nil
                    self.currentRecordingID = nil
                    self.isPlaying = false
                    self.deactivatePlaybackSession()
                    return
                }
            }
        }
    }

    private func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }

    private func deactivatePlaybackSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private enum VoiceSparkPlaybackError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "That recording could not begin playing."
    }
}

private enum VoiceSparkRecorderError: LocalizedError {
    case recordingCouldNotStart
    case speechRecognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recordingCouldNotStart: "The microphone did not begin recording."
        case .speechRecognizerUnavailable: "Speech Recognition is temporarily unavailable."
        }
    }
}

private final class VoiceSparkRecognitionContinuation: @unchecked Sendable {
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
        task?.cancel()
        task = nil
        action(continuation)
    }
}

struct VoiceSparkView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var outputs: [PlatformOutput]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query private var destinations: [PublishingDestination]
    @Query private var formats: [PublishingFormat]
    @Query private var workspaces: [CreatorWorkspace]
    @Query private var subscriptionStates: [SubscriptionState]
    @StateObject private var recorder = VoiceSparkRecorder()
    @StateObject private var playback = VoiceSparkPlaybackController()
    @State private var transcript = ""
    @State private var recordings: [VoiceSparkRecording] = []
    @State private var sessionRecordingIDs: Set<UUID> = []
    @State private var libraryErrorMessage: String?
    @State private var linkRequest: VoiceSparkLinkRequest?
    @State private var selectedRecordingID: UUID?
    let autoLinkBrief: CreativeBrief?

    init(autoLinkBrief: CreativeBrief? = nil) {
        self.autoLinkBrief = autoLinkBrief
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    heading
                    recordingSurface
                    transcriptEditor
                    recordingsLog
                }
                .padding(.horizontal, AgentLayout.dashboardGutter)
                .padding(.top, AgentSpacing.x4)
                .padding(.bottom, AgentSpacing.x12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.agentCanvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedRecordingID) { recordingID in
                if let recording = recordings.first(where: { $0.id == recordingID }) {
                    let audioURL = try? VoiceSparkRecordingStore.audioURL(for: recording)
                    VoiceRecordingDetailPage(
                        title: recording.title ?? "",
                        transcript: recording.transcript,
                        recordedAt: recording.createdAt,
                        durationSeconds: recording.durationSeconds,
                        byteCount: recordingByteCount(recording),
                        playbackSource: audioURL.map(VoiceRecordingPlaybackSource.file),
                        downloadURL: audioURL,
                        isDownloadEnabled: audioURL != nil,
                        onDownload: {},
                        onDelete: { delete(recording) },
                        onTitleChange: { saveRecordingTitle(recordingID, title: $0) },
                        onConnect: {
                            linkRequest = VoiceSparkLinkRequest(recording: recording)
                        }
                    )
                }
            }
        }
        .interactiveDismissDisabled(recorder.isRecording || recorder.isTranscribing)
        .presentationBackground(Color.agentCanvas)
        .sheet(item: $linkRequest) { request in
            VoiceSparkLinkPickerView(
                posts: connectablePosts,
                pillars: availablePillars,
                destinations: destinations,
                formats: formats,
                onSelect: { post in
                    let shouldOpenPost = connect(request.recording, to: post.brief)
                    linkRequest = nil
                    guard shouldOpenPost else { return }
                    Task { @MainActor in
                        await Task.yield()
                        openPost(post.brief)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.agentCanvas)
        }
        .onAppear {
            purgeProcessedRecordings()
            reloadRecordings()
        }
        .onChange(of: appModel.activeWorkspaceID) {
            playback.stop()
            reloadRecordings()
        }
        .onDisappear {
            if recorder.isRecording { recorder.reset() }
            playback.stop()
        }
    }

    private var header: some View {
        ZStack {
            MetaLabel("Voice Spark")

            HStack {
                AgentCircularGlassIconButton(icon: .close, accessibilityLabel: "Close Voice Spark") {
                    recorder.reset()
                    playback.stop()
                    dismiss()
                }

                Spacer()

                AgentCircularGlassIconButton(
                    icon: .check,
                    accessibilityLabel: autoLinkBrief == nil ? "Save Voice Spark" : "Add recording to post",
                    isEnabled: VoiceSparkSessionPolicy.canSave(
                        autoLinksToPost: autoLinkBrief != nil,
                        transcript: cleanTranscript,
                        recordingCount: autoLinkBrief == nil ? recordings.count : sessionRecordingIDs.count,
                        isBusy: recorder.isRecording || recorder.isTranscribing
                    ),
                    action: save
                )
            }
        }
        .padding(.horizontal, AgentLayout.pageMargin)
        .frame(maxWidth: .infinity)
        .agentQuickAddHeaderSurface()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            Text(autoLinkBrief == nil ? "Say it before it leaves." : "Add a thought to this post.")
                .font(.agentDisplay)
                .tracking(-0.64)
            Text(headingDescription)
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headingDescription: String {
        guard let autoLinkBrief else {
            return "Record the thought. Agent.cy turns it into an editable Idea Bank entry."
        }
        return "Your recording and transcript will be attached directly to \(VoiceSparkSessionPolicy.displayTitle(autoLinkBrief.title))."
    }

    private var recordingSurface: some View {
        VStack(spacing: AgentSpacing.x5) {
            Button {
                Task {
                    if recorder.isRecording {
                        if let capture = await recorder.stopAndTranscribe() {
                            saveCapture(capture)
                        }
                    } else {
                        playback.stop()
                        await recorder.start()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.cyAccent.opacity(0.16) : Color.agentSurface.opacity(0.76))
                    Circle()
                        .stroke(recorder.isRecording ? Color.cyAccent.opacity(0.72) : Color.agentBorder, lineWidth: 1)
                    AgentIconView(recorder.isRecording ? .stop : .microphone, size: 30)
                        .foregroundStyle(recorder.isRecording ? Color.cyAccent : Color.agentText)
                }
                .frame(width: 112, height: 112)
                .glassEffect(.clear.interactive(), in: .circle)
                .shadow(color: Color.agentPureBlack.opacity(0.09), radius: 20, y: 8)
            }
            .buttonStyle(AgentPressButtonStyle())
            .disabled(recorder.isTranscribing)
            .accessibilityLabel(recorder.isRecording ? "Stop and save recording" : "Start recording")

            VStack(spacing: AgentSpacing.x1) {
                if recorder.isRecording, let startedAt = recorder.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Self.durationText(context.date.timeIntervalSince(startedAt)))
                            .font(.agentHeadline.monospacedDigit())
                    }
                    Text("Stop & save recording")
                        .font(.agentHeadline)
                    Text("Your audio will be added to Recordings.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                } else if recorder.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving recording…")
                        .font(.agentHeadline)
                    Text("Transcribing and keeping the original audio.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                } else {
                    Text(sessionRecordingIDs.isEmpty ? "Start recording" : "Record another thought")
                        .font(.agentHeadline)
                    Text(recordingReadyDescription)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let libraryErrorMessage {
                Text(libraryErrorMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.cyAccent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AgentSpacing.x6)
        .padding(.horizontal, AgentSpacing.x5)
        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
        .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
    }

    private var recordingReadyDescription: String {
        if autoLinkBrief != nil {
            return "Tap the checkmark when you are ready to add the recording to this post."
        }
        return "Unlinked recordings stay here until you connect them to a post or delete them."
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Your Thoughts")
            TextEditor(text: $transcript)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 142)
                .padding(AgentSpacing.x3)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.control)
                        .stroke(Color.agentBorder, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if transcript.isEmpty {
                        Text("Your transcript will appear here. You can also type the thought yourself.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .padding(.horizontal, AgentSpacing.x4)
                            .padding(.vertical, AgentSpacing.x5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var recordingsLog: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x3) {
                MetaLabel("Recordings")
                Spacer()
                if !recordings.isEmpty {
                    Text("Swipe left to delete")
                        .font(.agentMetadata)
                        .foregroundStyle(Color.agentSecondary)
                }
            }

            if recordings.isEmpty {
                HStack(alignment: .top, spacing: AgentSpacing.x3) {
                    AgentIconView(.microphone, size: 18)
                        .foregroundStyle(Color.agentSecondary)
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("No recordings yet")
                            .font(.agentHeadline)
                        Text(emptyRecordingDescription)
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
            } else {
                LazyVStack(spacing: AgentSpacing.x2) {
                    ForEach(recordings) { recording in
                        recordingRow(recording)
                    }
                }
            }
        }
    }

    private var emptyRecordingDescription: String {
        if autoLinkBrief != nil {
            return "Tap Start recording above. The saved audio will stay with this post."
        }
        return "Tap Start recording above. Recordings without a linked post stay in this library."
    }

    private func recordingRow(_ recording: VoiceSparkRecording) -> some View {
        let isThisPlaying = playback.currentRecordingID == recording.id && playback.isPlaying

        return AgentSwipeDeleteRow(onDelete: { delete(recording) }) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                HStack(spacing: AgentSpacing.x3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(VoiceSparkSessionPolicy.displayTitle(recording.title))
                            .font(.agentHeadline)
                            .foregroundStyle(Color.agentText)
                        Text("\(Self.durationText(recording.durationSeconds)) · \(recording.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.agentMetadata.monospacedDigit())
                            .foregroundStyle(Color.agentSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { selectedRecordingID = recording.id }

                    HStack(spacing: 0) {
                        Button {
                            do {
                                libraryErrorMessage = nil
                                try playback.toggle(recording)
                            } catch {
                                libraryErrorMessage = error.localizedDescription
                            }
                        } label: {
                            AgentIconView(isThisPlaying ? .stop : .play, size: 16)
                                .foregroundStyle(Color.agentText)
                                .offset(x: isThisPlaying ? 0 : 1)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(AgentPressButtonStyle())
                        .contentShape(.rect)
                        .accessibilityLabel(isThisPlaying ? "Stop recording playback" : "Play recording")

                        if let audioURL = try? VoiceSparkRecordingStore.audioURL(for: recording) {
                            let transfer = VoiceRecordingTransfer(
                                sourceURL: audioURL,
                                fileName: VoiceRecordingExportNaming.fileName(
                                    title: recording.title,
                                    recordedAt: recording.createdAt,
                                    postTitle: recording.linkedBriefTitle
                                )
                            )
                            ShareLink(
                                item: transfer,
                                preview: SharePreview(transfer.fileName)
                            ) {
                                AgentIconView(.download, size: 16)
                                    .foregroundStyle(Color.agentText)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(AgentPressButtonStyle())
                            .contentShape(.rect)
                            .accessibilityLabel("Save or share recording")
                        }
                    }
                }

                Text(recording.transcript.isEmpty ? "Audio saved without a transcript." : recording.transcript)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(.rect)
                    .onTapGesture { selectedRecordingID = recording.id }

                if VoiceSparkSessionPolicy.shouldShowFreshActions(
                    for: recording.id,
                    sessionRecordingIDs: sessionRecordingIDs,
                    autoLinksToPost: autoLinkBrief != nil
                ) {
                    freshRecordingActions(recording)
                }
            }
            .padding(AgentSpacing.x3)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.card))
            .agentSurfaceChrome(cornerRadius: AgentRadius.card)
        }
    }

    private func freshRecordingActions(_ recording: VoiceSparkRecording) -> some View {
        VStack(spacing: AgentSpacing.x2) {
            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            HStack(spacing: 0) {
                Button {
                    createPost(from: recording)
                } label: {
                    freshActionLabel(title: "Create post", icon: .add)
                }
                .buttonStyle(AgentPressButtonStyle())

                Rectangle()
                    .fill(Color.agentBorder)
                    .frame(width: 1, height: 20)

                Button {
                    linkRequest = VoiceSparkLinkRequest(recording: recording)
                } label: {
                    freshActionLabel(title: "Connect", icon: .link)
                }
                .buttonStyle(AgentPressButtonStyle())
            }
        }
    }

    private func freshActionLabel(title: String, icon: AgentIcon) -> some View {
        HStack(spacing: AgentSpacing.x2) {
            AgentIconView(icon, size: 14)
            Text(title)
        }
        .font(.agentSubtext.weight(.semibold))
        .foregroundStyle(Color.agentText)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
    }

    private var availableBriefs: [CreativeBrief] {
        briefs.filter {
            $0.status != .archived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var availableOutputs: [PlatformOutput] {
        outputs.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var availablePillars: [Pillar] {
        pillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var connectablePosts: [VoiceSparkConnectPost] {
        VoiceSparkConnectPostPolicy.posts(
            briefs: availableBriefs,
            outputs: availableOutputs
        )
    }

    private var activeWorkspaceID: UUID? {
        WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        )
    }

    private var hasLinkedPost: Bool {
        !VoiceSparkSessionPolicy.shouldCreateSeparateIdea(for: recordings)
    }

    private var cleanTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        if let autoLinkBrief {
            saveToLinkedPost(autoLinkBrief)
            return
        }
        guard !cleanTranscript.isEmpty else { return }
        if hasLinkedPost {
            let linkedPost = recordings
                .first(where: { $0.linkedPlacement == .post })
                .flatMap { recording in briefs.first(where: { $0.id == recording.linkedBriefID }) }
            finishCurrentSession()
            if let linkedPost {
                openPost(linkedPost)
            } else {
                appModel.notice = .info("Voice Spark finished. No separate Idea Bank entry was created.")
                dismiss()
            }
            return
        }
        guard AccessPolicy.allows(.createSpark, state: subscriptionStates.first) else {
            appModel.notice = .info("Open Access in Settings to restore creation access.")
            return
        }

        let activeID = activeWorkspaceID
        let brief = CreativeBrief(
            title: Self.title(from: cleanTranscript),
            premise: cleanTranscript,
            source: .voiceTranscript
        )
        brief.workspaceID = activeID
        brief.ideaBankPlacement = .idea
        brief.pillarID = VoiceSparkSessionPolicy.capturedContentPillarID
        context.insert(brief)

        do {
            try context.save()
            var failedAttachmentCount = 0
            for recording in recordings where sessionRecordingIDs.contains(recording.id) {
                do {
                    try attach(recording, to: brief)
                } catch {
                    failedAttachmentCount += 1
                }
            }
            finishCurrentSession()
            WidgetSnapshotService.refresh(context: context, workspaceID: activeID)
            appModel.notice = failedAttachmentCount == 0
                ? .info("Voice Spark saved to your Idea Bank.")
                : .info("Your thought was saved, but one or more recordings could not be attached.")
            dismiss()
        } catch {
            appModel.notice = .error("Voice Spark could not be saved. Your transcript is still here.")
        }
    }

    private func saveToLinkedPost(_ brief: CreativeBrief) {
        let sessionRecordings = recordings.filter { sessionRecordingIDs.contains($0.id) }
        guard !sessionRecordings.isEmpty else { return }

        do {
            for recording in sessionRecordings {
                try attach(recording, to: brief)
            }
            finishCurrentSession(removing: sessionRecordings)
            WidgetSnapshotService.refresh(context: context, workspaceID: activeWorkspaceID)
            dismiss()
        } catch {
            libraryErrorMessage = "That recording could not be added to this post. \(error.localizedDescription)"
        }
    }

    private func saveCapture(_ capture: VoiceSparkCapture) {
        do {
            libraryErrorMessage = nil
            let recording = try VoiceSparkRecordingStore.save(
                temporaryURL: capture.temporaryURL,
                workspaceID: activeWorkspaceID,
                transcript: capture.transcript,
                durationSeconds: capture.durationSeconds
            )
            sessionRecordingIDs.insert(recording.id)
            if !recording.transcript.isEmpty {
                transcript = cleanTranscript.isEmpty
                    ? recording.transcript
                    : "\(cleanTranscript)\n\n\(recording.transcript)"
            }
            recorder.finish()
            reloadRecordings()
        } catch {
            recorder.finish()
            libraryErrorMessage = "That recording could not be added to your log. \(error.localizedDescription)"
        }
    }

    private func reloadRecordings() {
        do {
            libraryErrorMessage = nil
            let storedRecordings = try VoiceSparkRecordingStore.load()
            if autoLinkBrief == nil {
                recordings = VoiceSparkSessionPolicy.libraryRecordings(
                    from: storedRecordings,
                    workspaceID: activeWorkspaceID
                )
            } else {
                recordings = VoiceSparkSessionPolicy.currentRecordings(
                    from: storedRecordings,
                    sessionRecordingIDs: sessionRecordingIDs,
                    workspaceID: activeWorkspaceID
                )
            }
        } catch {
            recordings = []
            libraryErrorMessage = "Your recordings could not be loaded. \(error.localizedDescription)"
        }
    }

    private func createPost(from recording: VoiceSparkRecording) {
        guard AccessPolicy.allows(.createSpark, state: subscriptionStates.first) else {
            appModel.notice = .info("Open Access in Settings to restore creation access.")
            return
        }

        let body = cleanTranscript.isEmpty && recording.transcript.isEmpty
            ? "Voice recording from \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))"
            : (cleanTranscript.isEmpty ? recording.transcript : cleanTranscript)
        guard let brief = appModel.createSpark(
            text: body,
            source: .voiceTranscript,
            notes: body,
            pillarID: VoiceSparkSessionPolicy.capturedContentPillarID,
            placement: .post,
            context: context
        ) else { return }

        guard appModel.ensurePostDraft(for: brief, context: context) != nil else { return }
        do {
            let actionRecordings = actionRecordings(for: recording)
            for sessionRecording in actionRecordings {
                try attach(sessionRecording, to: brief)
            }
            finishCurrentSession(removing: actionRecordings)
            WidgetSnapshotService.refresh(context: context, workspaceID: activeWorkspaceID)
            Task { @MainActor in
                await Task.yield()
                openPost(brief)
            }
        } catch {
            appModel.notice = .error("The post was created, but the recording could not be attached.")
        }
    }

    @discardableResult
    private func connect(_ recording: VoiceSparkRecording, to brief: CreativeBrief) -> Bool {
        let selectedRecordings = VoiceSparkLinkSelectionPolicy.recordingsToAttach(
            from: recordings,
            selected: recording.id
        )
        guard !selectedRecordings.isEmpty else {
            libraryErrorMessage = "That recording is no longer available to connect."
            return false
        }

        do {
            for selectedRecording in selectedRecordings {
                try attach(selectedRecording, to: brief)
            }
            let placement: IdeaBankPlacement = IdeaBankPlacementPolicy.includes(brief) ? .idea : .post
            finishCurrentSession(removing: placement == .post ? selectedRecordings : [])
            if placement == .idea {
                appModel.notice = .info("Recording connected to the idea “\(brief.title)”. A new Voice Spark is ready.")
            }
            return VoiceSparkSessionPolicy.shouldOpenPost(afterConnectingTo: placement)
        } catch {
            libraryErrorMessage = "That recording could not be connected. \(error.localizedDescription)"
            return false
        }
    }

    private func openPost(_ brief: CreativeBrief) {
        appModel.widgetBriefOpensEditor = true
        appModel.requestedPlanMode = .week
        appModel.selectedTab = .today
        appModel.presentedSheet = nil
        appModel.widgetBriefID = brief.id
        dismiss()
    }

    private func attach(_ recording: VoiceSparkRecording, to brief: CreativeBrief) throws {
        let audioData = try VoiceSparkRecordingStore.audioData(for: recording)
        let fileName = recording.fileName
        let existing = try context.fetch(FetchDescriptor<CreatorAttachment>(
            predicate: #Predicate { $0.fileName == fileName }
        )).first(where: { $0.ownerKind == .referenceFile })
        let attachment: CreatorAttachment

        if let existing {
            attachment = existing
            attachment.briefID = brief.id
            attachment.workspaceID = brief.workspaceID ?? activeWorkspaceID
            attachment.displayTitle = recording.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            attachment.voiceTranscript = recording.transcript
            attachment.voiceDurationSeconds = recording.durationSeconds
            attachment.cloudData = audioData
            attachment.byteCount = Int64(audioData.count)
            attachment.updatedAt = Date()
            attachment.syncState = .synced
        } else {
            attachment = CreatorAttachment(
                ownerKind: .referenceFile,
                briefID: brief.id,
                fileName: recording.fileName,
                displayTitle: recording.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                voiceTranscript: recording.transcript,
                voiceDurationSeconds: recording.durationSeconds,
                kind: .other,
                uniformTypeIdentifier: "public.mpeg-4-audio",
                byteCount: Int64(audioData.count),
                localRelativePath: "",
                cloudData: audioData,
                syncState: .synced
            )
            attachment.workspaceID = brief.workspaceID ?? activeWorkspaceID
            context.insert(attachment)
        }

        try context.save()
        let placement: IdeaBankPlacement = IdeaBankPlacementPolicy.includes(brief) ? .idea : .post
        _ = try VoiceSparkRecordingStore.connect(
            recordingID: recording.id,
            briefID: brief.id,
            briefTitle: brief.title,
            placement: placement
        )
        reloadRecordings()
    }

    private func delete(_ recording: VoiceSparkRecording) {
        do {
            if playback.currentRecordingID == recording.id { playback.stop() }
            if selectedRecordingID == recording.id { selectedRecordingID = nil }
            try VoiceSparkRecordingStore.remove(recordingID: recording.id)
            sessionRecordingIDs.remove(recording.id)
            reloadRecordings()
        } catch {
            libraryErrorMessage = "That recording could not be deleted. \(error.localizedDescription)"
        }
    }

    private func actionRecordings(for recording: VoiceSparkRecording) -> [VoiceSparkRecording] {
        VoiceSparkSessionPolicy.actionRecordings(
            from: recordings,
            selected: recording.id,
            sessionRecordingIDs: sessionRecordingIDs
        )
    }

    @discardableResult
    private func saveRecordingTitle(_ recordingID: UUID, title: String) -> Bool {
        do {
            let updated = try VoiceSparkRecordingStore.updateTitle(
                recordingID: recordingID,
                title: title
            )
            guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return false }
            recordings[index] = updated
            return true
        } catch {
            libraryErrorMessage = "That recording title could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    private func finishCurrentSession(removing processedRecordings: [VoiceSparkRecording] = []) {
        playback.stop()
        selectedRecordingID = nil
        for recording in processedRecordings {
            try? VoiceSparkRecordingStore.remove(recordingID: recording.id)
        }
        sessionRecordingIDs.removeAll()
        transcript = ""
        libraryErrorMessage = nil
        recorder.reset()
        reloadRecordings()
    }

    private func recordingByteCount(_ recording: VoiceSparkRecording) -> Int64? {
        guard let url = try? VoiceSparkRecordingStore.audioURL(for: recording),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return nil }
        return Int64(fileSize)
    }

    private func purgeProcessedRecordings() {
        guard let existing = try? VoiceSparkRecordingStore.load() else { return }
        for recording in existing where recording.linkedPlacement == .post {
            try? VoiceSparkRecordingStore.remove(recordingID: recording.id)
        }
    }

    private static func title(from transcript: String) -> String {
        let words = transcript
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(7)
            .joined(separator: " ")
        guard let first = words.first else { return "Untitled Voice Spark" }
        return String(first).uppercased() + words.dropFirst()
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VoiceSparkLinkRequest: Identifiable {
    let recording: VoiceSparkRecording
    var id: UUID { recording.id }
}

enum VoiceSparkLinkSelectionPolicy {
    static func recordingsToAttach(
        from recordings: [VoiceSparkRecording],
        selected recordingID: UUID
    ) -> [VoiceSparkRecording] {
        recordings.filter { $0.id == recordingID }
    }
}

enum VoiceSparkConnectDateKind: Int, Equatable {
    case work
    case post
}

struct VoiceSparkConnectPost: Identifiable {
    let brief: CreativeBrief
    let output: PlatformOutput
    let date: Date?
    let dateKind: VoiceSparkConnectDateKind?

    var id: UUID { output.id }
}

enum VoiceSparkConnectPostPolicy {
    static func posts(
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [VoiceSparkConnectPost] {
        let briefByID = DuplicateSafeIndex.firstValues(briefs.map { ($0.id, $0) })

        return outputs
            .compactMap { output -> VoiceSparkConnectPost? in
                guard let brief = briefByID[output.briefID],
                      ContinueWorkingPostPolicy.includes(
                        briefStatus: brief.status,
                        outputStatus: output.status,
                        customStatus: brief.resolvedCustomStatusLabel,
                        ideaBankPlacement: brief.ideaBankPlacement
                      ) else {
                    return nil
                }

                let resolvedDate = resolvedDate(
                    brief: brief,
                    output: output,
                    calendar: calendar
                )
                return VoiceSparkConnectPost(
                    brief: brief,
                    output: output,
                    date: resolvedDate.date,
                    dateKind: resolvedDate.kind
                )
            }
            .sorted {
                precedes($0, $1, now: now, calendar: calendar)
            }
    }

    private static func resolvedDate(
        brief: CreativeBrief,
        output: PlatformOutput,
        calendar: Calendar
    ) -> (date: Date?, kind: VoiceSparkConnectDateKind?) {
        if let workDate = brief.workDate {
            if let postDate = output.targetDate,
               calendar.isDate(workDate, inSameDayAs: postDate) {
                return (postDate, .post)
            }
            return (workDate, .work)
        }
        if let postDate = output.targetDate {
            return (postDate, .post)
        }
        return (nil, nil)
    }

    private static func precedes(
        _ lhs: VoiceSparkConnectPost,
        _ rhs: VoiceSparkConnectPost,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let lhsGroup = sortGroup(for: lhs.date, today: today, calendar: calendar)
        let rhsGroup = sortGroup(for: rhs.date, today: today, calendar: calendar)
        if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }

        switch (lhs.date, rhs.date) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsGroup == 1 ? lhsDate > rhsDate : lhsDate < rhsDate
        case (nil, nil):
            if lhs.brief.updatedAt != rhs.brief.updatedAt {
                return lhs.brief.updatedAt > rhs.brief.updatedAt
            }
        default:
            break
        }

        if lhs.dateKind?.rawValue != rhs.dateKind?.rawValue {
            return (lhs.dateKind?.rawValue ?? Int.max) <
                (rhs.dateKind?.rawValue ?? Int.max)
        }
        let lhsTitle = displayTitle(for: lhs)
        let rhsTitle = displayTitle(for: rhs)
        let titleOrder = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.output.id.uuidString < rhs.output.id.uuidString
    }

    private static func sortGroup(
        for date: Date?,
        today: Date,
        calendar: Calendar
    ) -> Int {
        guard let date else { return 2 }
        return calendar.startOfDay(for: date) >= today ? 0 : 1
    }

    static func displayTitle(for post: VoiceSparkConnectPost) -> String {
        let titleOverride = post.output.titleOverride
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return titleOverride.isEmpty ? post.brief.title : titleOverride
    }

    static func filteredPosts(
        _ posts: [VoiceSparkConnectPost],
        query: String,
        platformLabel: (PlatformOutput) -> String,
        pillarName: (CreativeBrief) -> String
    ) -> [VoiceSparkConnectPost] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return posts }
        return posts.filter { post in
            displayTitle(for: post).localizedCaseInsensitiveContains(normalizedQuery)
                || post.brief.premise.localizedCaseInsensitiveContains(normalizedQuery)
                || platformLabel(post.output).localizedCaseInsensitiveContains(normalizedQuery)
                || pillarName(post.brief).localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

private struct VoiceSparkLinkPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let posts: [VoiceSparkConnectPost]
    let pillars: [Pillar]
    let destinations: [PublishingDestination]
    let formats: [PublishingFormat]
    let onSelect: (VoiceSparkConnectPost) -> Void
    @State private var searchText = ""

    var body: some View {
        let visiblePosts = filteredPosts
        let visibleGroups = postGroups(from: visiblePosts)

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    if visiblePosts.isEmpty {
                        Text(searchText.isEmpty ? "No open posts yet." : "No matching open posts.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AgentSpacing.x5)
                    } else {
                        ForEach(visibleGroups) { group in
                            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.dateLabel.uppercased())
                                        .font(.agentMetadata)
                                        .tracking(0.7)
                                    Spacer()
                                    Text(group.sectionLabel.uppercased())
                                        .font(.agentMetadata)
                                        .tracking(0.7)
                                        .foregroundStyle(Color.agentSecondary)
                                }

                                ForEach(group.posts) { post in
                                    Button {
                                        onSelect(post)
                                    } label: {
                                        AgentPostCard(
                                            title: VoiceSparkConnectPostPolicy.displayTitle(for: post),
                                            pillar: pillarName(for: post.brief),
                                            accent: pillarAccent(for: post.brief),
                                            status: displayStatus(for: post),
                                            metadata: metadata(for: post),
                                            timeText: timeText(for: post),
                                            statusTextOverride: statusText(for: post)
                                        )
                                    }
                                    .buttonStyle(AgentPressButtonStyle())
                                    .accessibilityHint("Connect this recording to the post")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AgentLayout.dashboardGutter)
                .padding(.top, AgentSpacing.x2)
                .padding(.bottom, AgentSpacing.x8)
            }
            .background(Color.agentCanvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: AgentSpacing.x4) {
                VStack(spacing: AgentSpacing.x3) {
                    ZStack {
                        VStack(spacing: AgentSpacing.x1) {
                            MetaLabel("Connect Recording")
                            Text("Choose an open post")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                        }
                        HStack {
                            AgentCircularGlassIconButton(icon: .close, accessibilityLabel: "Close picker") {
                                dismiss()
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 58)

                    HStack(spacing: AgentSpacing.x3) {
                        AgentIconView(.search, size: 16)
                            .foregroundStyle(Color.agentSecondary)
                        TextField("Search open posts", text: $searchText)
                            .font(.agentBody)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 48)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AgentRadius.control)
                            .stroke(Color.agentBorder, lineWidth: 1)
                    }
                }
                .padding(.horizontal, AgentLayout.dashboardGutter)
                .padding(.top, AgentSpacing.x2)
                .background(Color.agentCanvas)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var filteredPosts: [VoiceSparkConnectPost] {
        VoiceSparkConnectPostPolicy.filteredPosts(
            posts,
            query: searchText,
            platformLabel: platformLabel,
            pillarName: pillarName
        )
    }

    private func postGroups(
        from posts: [VoiceSparkConnectPost]
    ) -> [VoiceSparkConnectPostGroup] {
        var groups: [VoiceSparkConnectPostGroup] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for post in posts {
            let day = post.date.map { calendar.startOfDay(for: $0) }
            let key = day.map { String($0.timeIntervalSinceReferenceDate) } ?? "undated"
            if groups.last?.id == key {
                groups[groups.count - 1].posts.append(post)
                continue
            }

            let sectionLabel: String
            if let day {
                sectionLabel = day >= today ? "Upcoming" : "Past"
            } else {
                sectionLabel = "Open"
            }
            groups.append(
                VoiceSparkConnectPostGroup(
                    id: key,
                    dateLabel: day.map { dateLabel(for: $0) } ?? "No date",
                    sectionLabel: sectionLabel,
                    posts: [post]
                )
            )
        }
        return groups
    }

    private func dateLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        guard let pillarID = brief.pillarID else { return nil }
        return pillars.first(where: { $0.id == pillarID && !$0.isArchived })
    }

    private func pillarName(for brief: CreativeBrief) -> String {
        pillar(for: brief)?.name ?? "Unfiled"
    }

    private func pillarAccent(for brief: CreativeBrief) -> Color {
        guard let pillar = pillar(for: brief) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: pillars))
    }

    private func platformLabel(for output: PlatformOutput) -> String {
        if let destinationID = output.destinationID,
           let destination = destinations.first(where: { $0.id == destinationID }) {
            return destination.name
        }
        if let formatID = output.formatID,
           let format = formats.first(where: { $0.id == formatID }) {
            return format.name
        }
        return output.platform.title
    }

    private func displayStatus(for post: VoiceSparkConnectPost) -> PlatformOutputStatus {
        if post.brief.resolvedCustomStatusLabel != nil { return .draft }
        if post.dateKind == .post { return .scheduled }
        return post.output.status
    }

    private func statusText(for post: VoiceSparkConnectPost) -> String {
        if let customStatus = post.brief.resolvedCustomStatusLabel {
            return customStatus
        }
        if post.dateKind == .post { return "Scheduled draft" }
        return ContinueWorkingPostPolicy.displayLabel(
            briefStatus: post.brief.status,
            outputStatus: post.output.status,
            customStatus: post.brief.resolvedCustomStatusLabel,
            ideaBankPlacement: post.brief.ideaBankPlacement
        )
    }

    private func metadata(for post: VoiceSparkConnectPost) -> String {
        let dateKind = switch post.dateKind {
        case .work: "Work date"
        case .post: "Post date"
        case nil: "Open post"
        }
        return "\(dateKind) · \(platformLabel(for: post.output))"
    }

    private func timeText(for post: VoiceSparkConnectPost) -> String? {
        guard let date = post.date else { return nil }
        let includesTime = switch post.dateKind {
        case .work: post.brief.includesWorkTime
        case .post: post.output.includesTargetTime
        case nil: false
        }
        return includesTime ? date.formatted(date: .omitted, time: .shortened) : nil
    }
}

private struct VoiceSparkConnectPostGroup: Identifiable {
    let id: String
    let dateLabel: String
    let sectionLabel: String
    var posts: [VoiceSparkConnectPost]
}
#endif
