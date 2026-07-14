import SwiftData
import SwiftUI

struct VoiceExamplesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [VoiceExampleDraft] = []
    @State private var proposal: InitialVoiceProfileProposal?
    @State private var didLoad = false
    let embeddedInNavigation: Bool

    init(embeddedInNavigation: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
    }

    private var usableCount: Int { drafts.filter(\.isUsableEvidence).count }
    private var approvedProfile: VoiceProfile? { appModel.approvedVoiceProfile(context: context) }

    var body: some View {
        Group {
            if embeddedInNavigation {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    EditorialHeader(
                        kicker: "\(usableCount) of 3 examples",
                        title: "Teach Cy your voice.",
                        subtitle: "Add real work you have already shared."
                    )

                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, example in
                        VoiceExampleInputCard(
                            example: exampleBinding(for: example.id),
                            number: index + 1,
                            onRemove: { removeDraft(id: example.id) },
                            onNotice: { appModel.notice = .info($0) }
                        )
                        .disabled(appModel.isWorking)
                    }

                    if drafts.count < 5 {
                        Button("Add example", systemImage: "plus") {
                            drafts.append(VoiceExampleDraft())
                        }
                        .frame(minHeight: 44)
                        .disabled(appModel.isWorking)
                    }

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        Button("Save examples", systemImage: "checkmark") {
                            _ = appModel.saveVoiceExamples(drafts, context: context)
                        }
                        .buttonStyle(AgentSecondaryButtonStyle())
                        .disabled(appModel.isWorking)

                        if approvedProfile == nil {
                            Button("Build voice profile", systemImage: "waveform.and.person.filled") {
                                buildVoiceProfile()
                            }
                            .buttonStyle(AgentPrimaryButtonStyle())
                            .disabled(usableCount < 3 || appModel.isWorking)
                            if usableCount < 3 {
                                Text("Add \(3 - usableCount) more \(usableCount == 2 ? "example" : "examples").")
                                    .font(.agentMono)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                        } else if let approvedProfile, appModel.isVoiceProfileStale(approvedProfile, context: context) {
                            CyCallout(heading: .noticed) {
                                Text("Examples saved. Use Teach Cy in Settings when you want to update your voice profile.")
                                    .font(.agentBody)
                            }
                        }
                    }
                }
                .padding(AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.agentCanvas)
        .navigationTitle(embeddedInNavigation ? "Settings" : "Content examples")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(embeddedInNavigation)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    embeddedInNavigation ? "Back" : "Close",
                    systemImage: embeddedInNavigation ? "chevron.left" : "xmark"
                ) { dismiss() }
                .labelStyle(.iconOnly)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            drafts = appModel.voiceExampleDrafts(context: context)
            while drafts.count < 3 { drafts.append(VoiceExampleDraft()) }
            proposal = appModel.initialVoiceProfileProposal(context: context)
        }
        .sheet(item: $proposal) { proposal in
            InitialVoiceProfileReviewView(initialProposal: proposal)
        }
        .agentKeyboardDismissal()
    }

    private func buildVoiceProfile() {
        guard appModel.saveVoiceExamples(drafts, context: context) else { return }
        Task {
            proposal = await appModel.prepareInitialVoiceProfile(context: context)
        }
    }

    private func removeDraft(id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts.remove(at: index)
        if drafts.isEmpty { drafts.append(VoiceExampleDraft()) }
    }

    private func exampleBinding(for id: UUID) -> Binding<VoiceExampleDraft> {
        Binding(
            get: { drafts.first(where: { $0.id == id }) ?? VoiceExampleDraft(id: id) },
            set: { updated in
                guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
                drafts[index] = updated
            }
        )
    }
}

private struct InitialVoiceProfileReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var proposal: InitialVoiceProfileProposal

    init(initialProposal: InitialVoiceProfileProposal) {
        _proposal = State(initialValue: initialProposal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    EditorialHeader(
                        kicker: "Visible, editable memory",
                        title: "Does this sound like you?",
                        subtitle: "Edit anything that feels wrong. Your voice profile changes only when you accept this version."
                    )

                    InitialProfileTextField(label: "Summary", text: $proposal.edited.summary)
                    InitialProfileTextField(label: "Tone · one per line", text: listBinding(\.tone))
                    InitialProfileTextField(label: "Sentence style", text: $proposal.edited.sentenceStyle)
                    InitialProfileTextField(label: "Signature qualities · one per line", text: listBinding(\.signatureQualities))
                    InitialProfileTextField(label: "Phrases to use · one per line", text: listBinding(\.phrasesToUse))
                    InitialProfileTextField(label: "Phrases to avoid · one per line", text: listBinding(\.phrasesToAvoid))
                    InitialProfileTextField(label: "Guidance · one per line", text: listBinding(\.guidance))

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        MetaLabel("Voice confidence · \(Int(proposal.edited.confidence * 100))%")
                        Slider(value: $proposal.edited.confidence, in: 0...1, step: 0.01)
                            .accessibilityLabel("Voice confidence")
                    }

                    Button("Accept voice profile", systemImage: "checkmark") {
                        appModel.acceptInitialVoiceProfile(proposal, context: context)
                        dismiss()
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())

                    Button("Keep examples without this profile") {
                        appModel.discardInitialVoiceProfile(context: context)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(AgentSpacing.x6)
            }
            .background(Color.agentCanvas)
            .navigationTitle("Review voice profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .agentKeyboardDismissal()
    }

    private func listBinding(_ keyPath: WritableKeyPath<VoiceProfileDraft, [String]>) -> Binding<String> {
        Binding(
            get: { proposal.edited[keyPath: keyPath].joined(separator: "\n") },
            set: { value in
                proposal.edited[keyPath: keyPath] = value
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct InitialProfileTextField: View {
    let label: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) { isFocused = false }
            TextField(label, text: $text, axis: .vertical)
                .lineLimit(2...8)
                .font(.agentBody)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                .focused($isFocused)
        }
    }
}
