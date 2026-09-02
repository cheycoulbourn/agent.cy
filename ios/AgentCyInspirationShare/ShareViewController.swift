import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let model = InspirationShareViewModel()
    private var loadTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = InspirationShareView(
            model: model,
            close: { [weak self] in
                self?.close()
            }
        )
        let hostingController = UIHostingController(rootView: root)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)

        loadTask = Task { [weak self] in
            await self?.loadSharedPost()
        }
    }

    private func loadSharedPost() async {
        let items = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
        let providers = items.reduce(into: [NSItemProvider]()) { result, item in
            result.append(contentsOf: item.attachments ?? [])
        }
        let urlValues = await loadURLValues(from: providers)
        guard !Task.isCancelled else { return }
        var textValues = items.compactMap { item in
            let text = item.attributedContentText?.string
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }
        textValues.append(contentsOf: await loadTextValues(from: providers))
        guard !Task.isCancelled else { return }
        do {
            let candidate = try InspirationShareCandidateResolver.resolveCandidate(
                urlValues: urlValues,
                textValues: textValues
            )
            model.url = candidate.url
            model.sourceCaption = candidate.sourceCaption
            let videoFilename = await stageFirstAsset(
                from: providers,
                type: .movie,
                kind: .video
            )
            model.sharedVideoFilename = finalizeStagedFile(videoFilename)
            guard !Task.isCancelled else { return }
            let thumbnailFilename = await stageFirstAsset(
                from: providers,
                type: .image,
                kind: .thumbnail
            )
            model.sharedThumbnailFilename = finalizeStagedFile(thumbnailFilename)
            guard !Task.isCancelled else { return }
            if let filename = model.sharedThumbnailFilename,
               let store = try? InspirationSharedAssetStore(),
               let data = try? store.data(
                   filename: filename,
                   maximumBytes: 10 * 1_024 * 1_024
               ) {
                model.previewImage = UIImage(data: data)
            }
            model.stage = .ready
            await model.prepareLinkThumbnailIfNeeded()
        } catch {
            guard !Task.isCancelled else { return }
            model.unavailableMessage = (error as? LocalizedError)?.errorDescription
                ?? "Share one public HTTPS post link at a time."
            model.stage = .unavailable
        }
    }

    private func stageFirstAsset(
        from providers: [NSItemProvider],
        type: UTType,
        kind: InspirationSharedAssetKind
    ) async -> String? {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(type.identifier)
        }) else { return nil }
        let captureID = model.captureID
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let filename = try? InspirationSharedAssetStore().stageFile(
                    from: url,
                    id: captureID,
                    kind: kind
                )
                continuation.resume(returning: filename)
            }
        }
    }

    private func loadURLValues(from providers: [NSItemProvider]) async -> [String] {
        var values: [String] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            guard !Task.isCancelled else { return values }
            if let value = await loadURL(from: provider) { values.append(value) }
        }
        return values
    }

    private func loadTextValues(from providers: [NSItemProvider]) async -> [String] {
        var values: [String] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            guard !Task.isCancelled else { return values }
            if let value = await loadText(from: provider) { values.append(value) }
        }
        return values
    }

    private func loadURL(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? URL)?.absoluteString)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: object as? String)
            }
        }
    }

    private func finalizeStagedFile(_ filename: String?) -> String? {
        guard let store = try? InspirationSharedAssetStore() else { return nil }
        return store.finalizeStagedFile(
            filename,
            taskWasCancelled: Task.isCancelled
        )
    }

    private func close() {
        loadTask?.cancel()
        loadTask = nil
        model.cancelPendingWorkAndCleanup()
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private enum InspirationShareStage: Equatable {
    case loading
    case ready
    case analyzing
    case review
    case savedAnalyzed
    case savedOriginal
    case savedLink
    case unavailable

    var isSaved: Bool {
        switch self {
        case .savedAnalyzed, .savedOriginal, .savedLink: true
        default: false
        }
    }
}

@MainActor
private final class InspirationShareViewModel: ObservableObject {
    let captureID = UUID()
    @Published var stage: InspirationShareStage = .loading
    @Published var url: URL?
    @Published var sourceCaption: String?
    @Published var sharedVideoFilename: String?
    @Published var sharedThumbnailFilename: String?
    @Published var previewImage: UIImage?
    @Published var extraction: ShareExtraction?
    @Published var shapeResult: ShareInspirationShapeResult?
    @Published var suggestedPillarName: String?
    @Published var suggestedPillarColorHex: String?
    @Published var saveTitle = ""
    @Published var progressTitle = "Preparing the post"
    @Published var progressDetail = "Reading the link and anything the platform shared with agent.cy."
    @Published var errorMessage: String?
    @Published var unavailableMessage: String?

    private let apiClient = InspirationShareAPIClient()
    private let mediaDownloader = InspirationShareMediaDownloader()
    private let mediaAnalyzer = InspirationShareMediaAnalyzer()
    private var preparedEnvelope: InspirationShareEnvelope?
    private var hasQueuedEnvelope = false
    private var linkExtractionTask: Task<ShareExtraction, Error>?
    private var activeOperationTask: Task<Void, Never>?

    func startAnalysis() {
        guard activeOperationTask == nil else { return }
        activeOperationTask = Task { [weak self] in
            await self?.analyze()
            self?.activeOperationTask = nil
        }
    }

    func startSavingLinkOnly() {
        guard activeOperationTask == nil else { return }
        activeOperationTask = Task { [weak self] in
            await self?.saveLinkOnly()
            self?.activeOperationTask = nil
        }
    }

    private func analyze() async {
        guard let url else {
            errorMessage = InspirationShareTransportError.invalidURL.localizedDescription
            return
        }
        stage = .analyzing
        progressTitle = "Reading the post"
        progressDetail = "Pulling the creator, caption, original media, and post details."

        do {
            guard let snapshot = try InspirationShareCreatorSnapshotStore.load() else {
                throw InspirationShareAPIError.invalidCreatorContext
            }
            let extraction = try await loadExtraction(for: url)
            try Task.checkCancellation()

            progressTitle = "Studying the video"
            progressDetail = "Reviewing the spoken message, on-screen text, and content format."
            await acquireThumbnail(from: extraction)
            let mediaAnalysis = await analyzeMedia(from: extraction)
            try Task.checkCancellation()

            progressTitle = "Making it yours"
            progressDetail = "Connecting the post’s actual message to your pillars and past content."
            let sourceMaterial = makeSourceMaterial(
                extraction: extraction,
                mediaAnalysis: mediaAnalysis
            )
            let operationID = UUID()
            let shaped = try await apiClient.shape(
                platform: extraction.platform,
                sourceMaterial: sourceMaterial,
                snapshot: snapshot,
                operationID: operationID
            )
            try Task.checkCancellation()
            shapeResult = shaped.result
            let suggestedPillar = pillar(
                id: shaped.result.suggestedPillarId,
                snapshot: snapshot
            )
            suggestedPillarName = suggestedPillar?.name
            suggestedPillarColorHex = suggestedPillar?.colorHex
            if normalizedSaveTitle == nil {
                saveTitle = shaped.result.idea.title
            }
            preparedEnvelope = InspirationShareEnvelope(
                id: captureID,
                workspaceHintID: InspirationWorkspaceHintStore.load(
                    defaults: UserDefaults(
                        suiteName: InspirationSharedContainer.appGroupIdentifier
                    )
                ),
                canonicalURLString: url.absoluteString,
                platform: extraction.platform,
                sourceCaption: sourceMaterial.caption,
                sourceTitle: extraction.displaySourceTitle,
                sourceCreatorName: extraction.creatorName,
                sourceCreatorHandle: extraction.creatorHandle,
                sourceTranscript: sourceMaterial.transcript,
                visualObservations: sourceMaterial.visualObservations,
                analyzedInputs: sourceMaterial.analyzedInputs,
                sourceDurationSeconds: sourceMaterial.durationSeconds,
                shapeResultJSON: shaped.json,
                sharedThumbnailFilename: sharedThumbnailFilename
            )
            stage = .review
        } catch {
            guard !Task.isCancelled else {
                cleanupStagedAssetsIfNeeded()
                return
            }
            stage = .ready
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Cy could not analyze this post right now. Try again."
        }
    }

    func saveAnalyzedPost(mode: InspirationSaveMode) {
        guard var envelope = preparedEnvelope,
              let normalizedSaveTitle else {
            errorMessage = "Add a title before saving this post."
            return
        }
        envelope.sourceTitle = normalizedSaveTitle
        envelope.saveMode = mode
        do {
            try InspirationImportQueueStore().enqueue(envelope)
            hasQueuedEnvelope = true
            removeStagedVideo()
            stage = mode == .originalOnly ? .savedOriginal : .savedAnalyzed
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "agent.cy could not save this post. Try again."
        }
    }

    private func saveLinkOnly() async {
        guard let url else { return }
        guard let normalizedSaveTitle else {
            errorMessage = "Add a title before saving this post."
            return
        }
        await prepareLinkThumbnailIfNeeded()
        guard !Task.isCancelled else {
            cleanupStagedAssetsIfNeeded()
            return
        }
        do {
            let envelope = InspirationShareEnvelope(
                id: captureID,
                workspaceHintID: InspirationWorkspaceHintStore.load(
                    defaults: UserDefaults(
                        suiteName: InspirationSharedContainer.appGroupIdentifier
                    )
                ),
                canonicalURLString: url.absoluteString,
                platform: InspirationLinkCanonicalizer.platform(for: url),
                sourceCaption: sourceCaption,
                sourceTitle: normalizedSaveTitle,
                sharedVideoFilename: sharedVideoFilename,
                sharedThumbnailFilename: sharedThumbnailFilename
            )
            try InspirationImportQueueStore().enqueue(envelope)
            hasQueuedEnvelope = true
            stage = .savedLink
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "agent.cy could not save this link. Try again."
        }
    }

    func cleanupStagedAssetsIfNeeded() {
        guard !hasQueuedEnvelope, let store = try? InspirationSharedAssetStore() else { return }
        store.remove(filename: sharedVideoFilename)
        store.remove(filename: sharedThumbnailFilename)
    }

    func cancelPendingWorkAndCleanup() {
        activeOperationTask?.cancel()
        activeOperationTask = nil
        linkExtractionTask?.cancel()
        linkExtractionTask = nil
        cleanupStagedAssetsIfNeeded()
    }

    var canSave: Bool {
        normalizedSaveTitle != nil
    }

    func prepareLinkThumbnailIfNeeded() async {
        guard previewImage == nil,
              sharedThumbnailFilename == nil,
              let url,
              let extraction = try? await loadExtraction(for: url)
        else { return }
        guard !Task.isCancelled else { return }
        await acquireThumbnail(from: extraction)
    }

    private var normalizedSaveTitle: String? {
        InspirationSavedPostTitlePolicy.normalized(saveTitle)
    }

    private func loadExtraction(for url: URL) async throws -> ShareExtraction {
        if let extraction { return extraction }
        if let linkExtractionTask { return try await linkExtractionTask.value }

        let task = Task { try await apiClient.extract(url: url) }
        linkExtractionTask = task
        defer { linkExtractionTask = nil }
        let extraction = try await task.value
        try Task.checkCancellation()
        self.extraction = extraction
        return extraction
    }

    private func acquireThumbnail(from extraction: ShareExtraction) async {
        guard previewImage == nil,
              sharedThumbnailFilename == nil,
              let thumbnailURL = extraction.thumbnailUrl,
              let downloaded = try? await mediaDownloader.downloadThumbnail(
                  from: thumbnailURL,
                  captureID: captureID
              ) else { return }
        guard let store = try? InspirationSharedAssetStore() else { return }
        sharedThumbnailFilename = store.finalizeStagedFile(
            downloaded.0,
            taskWasCancelled: Task.isCancelled
        )
        guard !Task.isCancelled else { return }
        previewImage = UIImage(data: downloaded.1)
    }

    private func analyzeMedia(from extraction: ShareExtraction) async -> ShareMediaAnalysis? {
        if sharedVideoFilename == nil,
           extraction.mediaKind == "video",
           let mediaURL = extraction.mediaUrls.first {
            let downloadedFilename = try? await mediaDownloader.downloadVideo(
                from: mediaURL,
                captureID: captureID
            )
            if let store = try? InspirationSharedAssetStore() {
                sharedVideoFilename = store.finalizeStagedFile(
                    downloadedFilename,
                    taskWasCancelled: Task.isCancelled
                )
            }
        }
        guard !Task.isCancelled else { return nil }
        guard let sharedVideoFilename,
              let store = try? InspirationSharedAssetStore(),
              let videoURL = try? store.assetURL(filename: sharedVideoFilename),
              let analysis = try? await mediaAnalyzer.analyze(url: videoURL) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        if previewImage == nil,
           self.sharedThumbnailFilename == nil,
           let thumbnailData = analysis.thumbnailData,
           let filename = try? store.stageData(
               thumbnailData,
               id: captureID,
               kind: .thumbnail,
               fileExtension: "jpg"
           ) {
            self.sharedThumbnailFilename = store.finalizeStagedFile(
                filename,
                taskWasCancelled: Task.isCancelled
            )
            guard !Task.isCancelled else { return nil }
            previewImage = UIImage(data: thumbnailData)
        }
        return analysis
    }

    private func makeSourceMaterial(
        extraction: ShareExtraction,
        mediaAnalysis: ShareMediaAnalysis?
    ) -> ShareSourceMaterial {
        let caption = firstNonempty(extraction.caption, sourceCaption).map {
            String($0.prefix(20_000))
        }
        var inputs = ["linkMetadata"]
        if caption != nil { inputs.append("caption") }
        if mediaAnalysis?.transcript != nil { inputs.append("audioTranscript") }
        if mediaAnalysis?.didAnalyzeFrames == true { inputs.append("videoFrames") }
        if mediaAnalysis?.didReadOnScreenText == true { inputs.append("onScreenText") }
        let duration = mediaAnalysis?.durationSeconds
            ?? extraction.durationSeconds.map { Int($0.rounded()) }
        return ShareSourceMaterial(
            title: extraction.displaySourceTitle.map { String($0.prefix(160)) },
            caption: caption,
            transcript: mediaAnalysis?.transcript.map { String($0.prefix(20_000)) },
            visualObservations: Array((mediaAnalysis?.visualObservations ?? []).prefix(20)),
            analyzedInputs: Array(Set(inputs)).sorted(),
            durationSeconds: duration.flatMap { (1...21_600).contains($0) ? $0 : nil }
        )
    }

    private func pillar(
        id: UUID?,
        snapshot: InspirationShareCreatorSnapshot
    ) -> (name: String, colorHex: String?)? {
        guard let id,
              let object = try? JSONSerialization.jsonObject(with: snapshot.creatorContextJSON),
              let context = object as? [String: Any],
              let pillars = context["pillars"] as? [[String: Any]] else { return nil }
        guard let name = pillars.first(where: {
            ($0["pillarId"] as? String)?.lowercased() == id.uuidString.lowercased()
        })?["name"] as? String else { return nil }
        return (
            name,
            snapshot.pillarColorHexByID?[id.uuidString.lowercased()]
        )
    }

    private func firstNonempty(_ values: String?...) -> String? {
        values.compactMap { value in
            let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return cleaned.isEmpty ? nil : cleaned
        }.first
    }

    private func removeStagedVideo() {
        guard let store = try? InspirationSharedAssetStore() else { return }
        store.remove(filename: sharedVideoFilename)
        sharedVideoFilename = nil
    }
}

private struct InspirationShareView: View {
    @ObservedObject var model: InspirationShareViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var isTitleFocused: Bool
    @AccessibilityFocusState private var isTitleAccessibilityFocused: Bool
    @State private var titleValidationMessage: String?
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.shareCanvas.ignoresSafeArea()
                content
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
            .foregroundStyle(Color.shareText)
            .font(.shareBody)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                        .font(.shareBodyStrong)
                        .foregroundStyle(Color.shareText)
                }
            }
            .animation(.easeOut(duration: reduceMotion ? 0.01 : 0.22), value: model.stage)
            .alert("agent.cy", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("Close") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .task(id: model.stage) {
            guard model.stage.isSaved else { return }
            let delay: Duration = voiceOverEnabled ? .seconds(4.5) : .seconds(1.6)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, model.stage.isSaved else { return }
            close()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .loading:
            analyzingView
        case .ready:
            readyView
        case .analyzing:
            analyzingView
        case .review:
            reviewView
        case .savedAnalyzed:
            savedView(
                title: "Post and remix saved",
                message: "Saved together in your Idea Bank."
            )
        case .savedOriginal:
            savedView(
                title: "Original post saved",
                message: "Saved to Saved Posts without a remix."
            )
        case .savedLink:
            savedView(
                title: "Post link saved",
                message: "Saved to Saved Posts for later."
            )
        case .unavailable:
            unavailableView
        }
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: ShareSpacing.x6) {
                    SharePanel {
                        HStack(alignment: .top, spacing: ShareSpacing.x4) {
                            sourcePreview
                            VStack(alignment: .leading, spacing: ShareSpacing.x2) {
                                ShareMetaLabel("Ready for Cy")
                                Text("Turn this post into your next idea")
                                    .font(.shareHeadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(platformTitle)
                                    .font(.shareCaption)
                                    .foregroundStyle(Color.shareSecondary)
                            }
                        }
                    }

                    savedPostTitleField

                    VStack(alignment: .leading, spacing: ShareSpacing.x3) {
                        outcomeRow("Understand the post’s actual message", icon: "text.alignleft")
                        outcomeRow("Pull the creator, caption, and video evidence", icon: "play.rectangle")
                        outcomeRow("Build a fresh direction around your pillars", icon: "sparkles")
                    }

                    Text("The original post stays attached as a private reference with a link back to the creator.")
                        .font(.shareCaption)
                        .foregroundStyle(Color.shareSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ShareSpacing.x5)
            }

            VStack(spacing: ShareSpacing.x3) {
                Button {
                    model.startAnalysis()
                } label: {
                    Label("Analyze with Cy", systemImage: "sparkles")
                }
                .buttonStyle(SharePrimaryButtonStyle())

                Button("Save post link without analyzing") {
                    guard validateSaveTitle() else { return }
                    model.startSavingLinkOnly()
                }
                .buttonStyle(ShareSecondaryButtonStyle())
            }
            .padding(.horizontal, ShareSpacing.x5)
            .padding(.vertical, ShareSpacing.x4)
            .background(Color.shareCanvas)
        }
    }

    private var analyzingView: some View {
        VStack(spacing: ShareSpacing.x6) {
            ShareCyThinkingMark(size: 48)
            VStack(spacing: ShareSpacing.x3) {
                Text(model.progressTitle)
                    .font(.shareHeadline)
                    .multilineTextAlignment(.center)
                Text(model.progressDetail)
                    .font(.shareBody)
                    .foregroundStyle(Color.shareSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Keep this popup open while Cy builds the source summary, key points, and a direction made for your content.")
                .font(.shareCaption)
                .foregroundStyle(Color.shareSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShareSpacing.x6)
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShareSpacing.x4) {
                SharePanel {
                    HStack(spacing: ShareSpacing.x4) {
                        sourcePreview
                        VStack(alignment: .leading, spacing: ShareSpacing.x1) {
                            ShareMetaLabel("Source")
                            Text(model.extraction?.displaySourceTitle ?? platformTitle)
                                .font(.shareBodyStrong)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Original post linked")
                                .font(.shareCaption)
                                .foregroundStyle(Color.shareSecondary)
                        }
                    }
                }

                if let result = model.shapeResult {
                    SharePanel {
                        VStack(alignment: .leading, spacing: ShareSpacing.x3) {
                            ShareMetaLabel("What the post is about")
                            Text(result.sourceSummary)
                                .font(.shareBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SharePanel {
                        VStack(alignment: .leading, spacing: ShareSpacing.x4) {
                            ShareMetaLabel("Key points")
                            ForEach(Array(result.keyPoints.enumerated()), id: \.offset) { index, point in
                                HStack(alignment: .top, spacing: ShareSpacing.x3) {
                                    Text("\(index + 1)")
                                        .font(.shareMeta)
                                        .foregroundStyle(Color.shareCyText)
                                        .frame(width: 18, alignment: .leading)
                                    Text(point)
                                        .font(.shareBody)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    SharePanel {
                        VStack(alignment: .leading, spacing: ShareSpacing.x4) {
                            ShareMetaLabel("Suggested for you")
                            Text(result.idea.title)
                                .font(.shareHeadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(result.idea.premise)
                                .font(.shareBody)
                                .foregroundStyle(Color.shareSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider().overlay(Color.shareHairline)
                            labeledValue("Opening", value: result.idea.spokenHook)
                            labeledValue("Takeaway", value: result.idea.takeaway)
                            if let pillar = model.suggestedPillarName {
                                HStack(spacing: ShareSpacing.x2) {
                                    Circle()
                                        .fill(Color.sharePillar(hex: model.suggestedPillarColorHex))
                                        .frame(width: 7, height: 7)
                                    Text(pillar)
                                        .font(.shareCaption.weight(.semibold))
                                }
                                .padding(.horizontal, ShareSpacing.x3)
                                .padding(.vertical, ShareSpacing.x2)
                                .background(Color.shareCanvas, in: .capsule)
                                .overlay { Capsule().stroke(Color.shareBorder, lineWidth: 1) }
                                .accessibilityLabel("Pillar: \(pillar)")
                            }
                        }
                    }

                    savedPostTitleField

                    Button {
                        guard validateSaveTitle() else { return }
                        model.saveAnalyzedPost(mode: .withRemix)
                    } label: {
                        Label("Save post + remix", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(SharePrimaryButtonStyle())
                    .padding(.top, ShareSpacing.x2)

                    Button("Save original only") {
                        guard validateSaveTitle() else { return }
                        model.saveAnalyzedPost(mode: .originalOnly)
                    }
                    .buttonStyle(ShareSecondaryButtonStyle())
                }
            }
            .padding(ShareSpacing.x5)
        }
    }

    private var savedPostTitleField: some View {
        SharePanel {
            VStack(alignment: .leading, spacing: ShareSpacing.x3) {
                ShareMetaLabel("Saved post title")
                TextField("Give this post a title", text: $model.saveTitle)
                    .font(.shareBodyStrong)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($isTitleFocused)
                    .padding(.horizontal, ShareSpacing.x4)
                    .frame(minHeight: 48)
                    .background(Color.shareCanvas, in: .rect(cornerRadius: ShareRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: ShareRadius.control)
                            .stroke(
                                isTitleFocused ? Color.shareCyText : Color.shareBorder,
                                lineWidth: isTitleFocused ? 1.5 : 1
                            )
                    }
                    .onSubmit { isTitleFocused = false }
                    .onChange(of: model.saveTitle) { _, title in
                        guard title.count > InspirationSavedPostTitlePolicy.maximumLength else { return }
                        model.saveTitle = String(
                            title.prefix(InspirationSavedPostTitlePolicy.maximumLength)
                        )
                    }
                    .onChange(of: model.canSave) { _, canSave in
                        if canSave { titleValidationMessage = nil }
                    }
                    .accessibilityLabel("Saved post title, required")
                    .accessibilityHint(titleFieldAccessibilityHint)
                    .accessibilityFocused($isTitleAccessibilityFocused)

                Text(titleFieldHelperText)
                    .font(.shareCaption)
                    .foregroundStyle(titleValidationMessage == nil ? Color.shareSecondary : Color.shareCyText)
                    .accessibilityLabel(titleFieldHelperText)
            }
        }
    }

    private var titleFieldHelperText: String {
        if let titleValidationMessage { return titleValidationMessage }
        return model.canSave ? "You can change this later." : "Required before saving."
    }

    private var titleFieldAccessibilityHint: String {
        titleValidationMessage ?? "Enter the title to use in Saved Posts."
    }

    @discardableResult
    private func validateSaveTitle() -> Bool {
        guard model.canSave else {
            let message = "Add a title before saving this post."
            titleValidationMessage = message
            isTitleFocused = true
            isTitleAccessibilityFocused = true
            UIAccessibility.post(notification: .announcement, argument: message)
            return false
        }
        titleValidationMessage = nil
        return true
    }

    private func savedView(title: String, message: String) -> some View {
        VStack(spacing: ShareSpacing.x6) {
            ZStack {
                Circle()
                    .fill(Color.shareSuccess.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.shareTitle)
                    .foregroundStyle(Color.shareSuccess)
            }
            VStack(spacing: ShareSpacing.x3) {
                Text(title)
                    .font(.shareTitle)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.shareBody)
                    .foregroundStyle(Color.shareSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShareSpacing.x5)
        .accessibilityElement(children: .combine)
    }

    private var unavailableView: some View {
        VStack(spacing: ShareSpacing.x5) {
            Image(systemName: "link.badge.plus")
                .font(.shareTitle)
                .foregroundStyle(Color.shareSecondary)
            VStack(spacing: ShareSpacing.x2) {
                Text("Share one public post")
                    .font(.shareHeadline)
                Text(model.unavailableMessage ?? "Choose a public Instagram post, reel, or supported web link.")
                    .font(.shareBody)
                    .foregroundStyle(Color.shareSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ShareSpacing.x6)
    }

    private var sourcePreview: some View {
        Group {
            if let image = model.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.shareCanvas
                    Image(systemName: "link")
                        .font(.shareHeadline)
                        .foregroundStyle(Color.shareSecondary)
                }
            }
        }
        .frame(width: 76, height: 96)
        .clipShape(.rect(cornerRadius: ShareRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: ShareRadius.control)
                .stroke(Color.shareBorder, lineWidth: 1)
        }
    }

    private func outcomeRow(_ title: String, icon: String) -> some View {
        HStack(spacing: ShareSpacing.x3) {
            Image(systemName: icon)
                .font(.shareBodyStrong)
                .foregroundStyle(Color.shareCyText)
                .frame(width: 24)
            Text(title)
                .font(.shareBody)
            Spacer(minLength: 0)
        }
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: ShareSpacing.x1) {
            Text(label.uppercased())
                .font(.shareMeta)
                .foregroundStyle(Color.shareSecondary)
            Text(value)
                .font(.shareBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var navigationTitle: String {
        switch model.stage {
        case .loading: "Preparing post"
        case .ready: "Save inspiration"
        case .analyzing: "Analyzing post"
        case .review: "Review your idea"
        case .savedAnalyzed, .savedOriginal, .savedLink: "Saved"
        case .unavailable: "Save inspiration"
        }
    }

    private var platformTitle: String {
        guard let url = model.url else { return "Shared post" }
        return switch InspirationLinkCanonicalizer.platform(for: url) {
        case .instagram: "Instagram post"
        case .tiktok: "TikTok post"
        case .youtube: "YouTube video"
        case .threads: "Threads post"
        case .web: "Web post"
        }
    }
}
