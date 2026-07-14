import PhotosUI
import SwiftUI

struct VoiceExampleInputCard: View {
    @Binding var example: VoiceExampleDraft
    let number: Int
    let onRemove: (() -> Void)?
    let onNotice: (String) -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isReadingScreenshot = false
    @State private var importMessage: String?
    @FocusState private var exampleTextIsFocused: Bool

    private var canonicalInstagramURL: URL? {
        InstagramPostReference.canonicalURL(from: example.sourceURLString)
    }

    private var hasInvalidInstagramURL: Bool {
        !example.sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && canonicalInstagramURL == nil
    }

    private var textUTF16Units: Int { example.trimmedText.utf16.count }

    private var textExceedsLimit: Bool {
        textUTF16Units > VoiceExampleEvidenceLimits.maximumExampleUTF16Units
    }

    var body: some View {
        let screenshotButtonTitle = isReadingScreenshot ? "Reading…" : "Screenshot"
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Example \(number)")
                Spacer()
                Label(example.source.title, systemImage: example.source.symbol)
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                if let onRemove {
                    Button("Remove example", systemImage: "trash", role: .destructive, action: onRemove)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Instagram link · optional")
                TextField("https://www.instagram.com/reel/…", text: $example.sourceURLString)
                    .font(.agentBody)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .agentSingleLineSubmit()
                    .padding(AgentSpacing.x3)
                    .background(Color.agentCanvas)
                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(hasInvalidInstagramURL ? Color.cyAccent : Color.agentBorder, lineWidth: 1))
                    .onChange(of: example.sourceURLString) { _, _ in
                        if canonicalInstagramURL != nil, example.source == .text {
                            example.source = .publicPostText
                        }
                    }

                if hasInvalidInstagramURL {
                    Text("Use a full HTTPS link to an Instagram post, Reel, or video.")
                        .font(.agentMono)
                        .foregroundStyle(Color.cyAccent)
                } else if let canonicalInstagramURL {
                    HStack {
                        Label("Link saved on this device", systemImage: "checkmark.circle")
                        Spacer()
                        Link("Open post", destination: canonicalInstagramURL)
                    }
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                }
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                AgentInputHeader(title: "Your words", isEditing: exampleTextIsFocused) {
                    exampleTextIsFocused = false
                }
                ZStack(alignment: .topLeading) {
                    if example.text.isEmpty {
                        Text("Paste something you wrote")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .padding(.horizontal, AgentSpacing.x3 + 4)
                            .padding(.vertical, AgentSpacing.x3 + 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $example.text)
                        .font(.agentBody)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 128)
                        .padding(AgentSpacing.x3)
                        .background(Color.agentCanvas)
                        .clipShape(.rect(cornerRadius: AgentRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                        .accessibilityLabel("Content example \(number)")
                        .focused($exampleTextIsFocused)
                }
            }

            HStack {
                if textExceedsLimit {
                    Text("Trim this example before saving.")
                        .foregroundStyle(Color.cyAccent)
                }
                Spacer()
                Text("\(textUTF16Units.formatted()) / 20,000")
                    .foregroundStyle(textExceedsLimit ? Color.cyAccent : Color.agentSecondary)
            }
            .font(.agentMono)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(screenshotButtonTitle, systemImage: "text.viewfinder")
            }
            .buttonStyle(AgentCompactSecondaryButtonStyle())
            .disabled(isReadingScreenshot)
            .frame(minHeight: 44)

            if let importMessage {
                Text(importMessage)
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            } else if canonicalInstagramURL != nil && !example.isUsableEvidence {
                Text("Add the caption text or a screenshot. Cy cannot read the link itself.")
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
            }

            Text("Screenshot text is read on this iPhone. The image is discarded.")
                .font(.agentMono)
                .foregroundStyle(Color.agentSecondary)
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: AgentRadius.panel))
        .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await readScreenshot(item) }
        }
    }

    @MainActor
    private func readScreenshot(_ item: PhotosPickerItem) async {
        isReadingScreenshot = true
        importMessage = nil
        defer {
            isReadingScreenshot = false
            selectedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw VoiceExampleImportError.unreadableImage
            }
            let recognized = try await OnDeviceScreenshotTextRecognizer().recognizeText(in: data)
            if example.trimmedText.isEmpty {
                example.text = recognized
            } else {
                example.text = "\(example.trimmedText)\n\n\(recognized)"
            }
            example.source = .screenshotText
            importMessage = "Text added. Remove anything that is not yours."
        } catch is CancellationError {
            return
        } catch {
            onNotice(error.localizedDescription)
        }
    }
}
