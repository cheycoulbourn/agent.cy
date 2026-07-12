import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [CreatorProfile]
    @Query private var voiceExamples: [VoiceExample]
    @Query private var voiceProfiles: [VoiceProfile]
    @Query private var subscriptions: [SubscriptionState]
    @State private var confirmErase = false
    @State private var showTeachRequest = false
    @State private var showVoiceProposal = false
    @State private var showVoiceExamples = false

    var body: some View {
        NavigationStack {
            Form {
                if let profile = profiles.first {
                    Section("Creator") {
                        TextField("Name", text: Bindable(profile).name)
                        TextField("Goal", text: Bindable(profile).goal, axis: .vertical)
                        Picker("How Cy helps", selection: Bindable(profile).assistanceModeRaw) {
                            ForEach(AssistanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    }
                    Section("Platforms") {
                        ForEach(CreatorPlatform.allCases) { platform in
                            Toggle(platform.title, isOn: platformBinding(platform, profile: profile))
                        }
                    }
                }

                Section("Content examples") {
                    LabeledContent("Examples", value: "\(readyExampleCount) of 3")
                    Button(
                        currentVoiceProfile == nil ? "Add voice examples" : "Edit examples",
                        systemImage: "text.badge.plus"
                    ) {
                        showVoiceExamples = true
                    }
                    .frame(minHeight: 44)
                    if currentVoiceProfile == nil {
                        Text("Optional. Add writing, post links, dictation, or screenshots when you are ready.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let currentVoiceProfile, appModel.isVoiceProfileStale(currentVoiceProfile, context: context) {
                        Text("Your examples changed. Approve an update when you want Cy to relearn your voice.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let voiceProfile = currentVoiceProfile {
                    Section("Voice profile · v\(voiceProfile.version)") {
                        LabeledContent("Summary") {
                            Text(voiceProfile.summary).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Traits") {
                            Text(voiceProfile.traitsText).multilineTextAlignment(.trailing)
                        }
                        if !voiceProfile.avoidText.isEmpty {
                            LabeledContent("Avoid") {
                                Text(voiceProfile.avoidText).multilineTextAlignment(.trailing)
                            }
                        }
                        if appModel.voiceProfileProposal(context: context) != nil {
                            Button("Review voice update", systemImage: "doc.text.magnifyingglass") {
                                showVoiceProposal = true
                            }
                            .frame(minHeight: 44)
                        } else {
                            Button("Teach Cy", systemImage: "quote.bubble") { showTeachRequest = true }
                                .frame(minHeight: 44)
                                .disabled(!appModel.allows(.teachCy, context: context))
                            Text("Cy changes your voice profile only after you approve it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let subscription = subscriptions.first {
                    Section("Access") {
                        LabeledContent("Plan", value: subscription.access.rawValue.capitalized)
                        if subscription.access == .freeJourney || subscription.access == .expired {
                            Button("Start 14-day trial") { Task { await appModel.startTrial(context: context) } }
                        }
                        Button("Restore purchases") { Task { await appModel.restorePurchases(context: context) } }
                        Text("$8.99 a month after the trial. TestFlight access is promotional.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Your data") {
                    Button("Export data", systemImage: "square.and.arrow.up") { appModel.export(context: context) }
                    if let exportURL = appModel.exportURL {
                        ShareLink(item: exportURL) { Label("Share export ZIP", systemImage: "archivebox") }
                    }
                    Button("Erase all data", systemImage: "trash", role: .destructive) { confirmErase = true }
                }

                Section("Privacy") {
                    Text("Your content stays on your devices and private iCloud. Cy receives only the text needed for your request. Audio, screenshots, and Instagram links are never sent.")
                }

                Section("About") {
                    LabeledContent("Version", value: versionLabel)
                    LabeledContent("Release", value: "Paper redesign · Stage 3")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.agentCanvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .confirmationDialog("Erase all agent.cy data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    Task { await appModel.eraseAll(context: context); dismiss() }
                }
            } message: {
                Text("This removes local data, private iCloud records when synchronization completes, temporary audio, reminders, and locally cached access state. This cannot be undone.")
            }
            .sheet(isPresented: $showTeachRequest, onDismiss: {
                if appModel.voiceProfileProposal(context: context) != nil { showVoiceProposal = true }
            }) {
                TeachCyRequestView(freeUpdatesRemaining: freeTeachUpdatesRemaining)
            }
            .sheet(isPresented: $showVoiceProposal) {
                if let proposal = appModel.voiceProfileProposal(context: context) {
                    VoiceProfileProposalReviewView(initialProposal: proposal)
                }
            }
            .sheet(isPresented: $showVoiceExamples) {
                VoiceExamplesView()
            }
        }
    }

    private var currentVoiceProfile: VoiceProfile? {
        voiceProfiles
            .filter(\.isApproved)
            .sorted {
                if $0.version == $1.version { return $0.updatedAt > $1.updatedAt }
                return $0.version > $1.version
            }
            .first
    }

    private var freeTeachUpdatesRemaining: Int? {
        guard let state = subscriptions.first, state.access == .freeJourney else { return nil }
        return max(0, 1 - state.teachCyUpdatesUsed)
    }

    private var readyExampleCount: Int {
        guard let profileID = profiles.first?.id else { return 0 }
        return voiceExamples.filter {
            $0.profileID == profileID && $0.creatorConfirmed && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
        return "\(version) (\(build))"
    }

    private func platformBinding(_ platform: CreatorPlatform, profile: CreatorProfile) -> Binding<Bool> {
        Binding(
            get: { profile.selectedPlatforms.contains(platform) },
            set: { enabled in
                var platforms = profile.selectedPlatforms
                if enabled {
                    if !platforms.contains(platform) { platforms.append(platform) }
                } else if platforms.count > 1 {
                    platforms.removeAll { $0 == platform }
                }
                profile.selectedPlatforms = platforms
                try? context.save()
            }
        )
    }
}

private struct TeachCyRequestView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let freeUpdatesRemaining: Int?
    @State private var instruction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("For example: Keep my openings shorter and less polished", text: $instruction, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("What should Cy learn?")
                } footer: {
                    Text("Be specific. Cy will propose a new version of your voice profile without changing your three examples.")
                }
                if let freeUpdatesRemaining {
                    Section("Free journey") {
                        LabeledContent("Teach Cy updates remaining", value: "\(freeUpdatesRemaining)")
                    }
                }
                Button("Prepare voice update", systemImage: "quote.bubble") {
                    Task {
                        await appModel.requestTeachCy(instruction: instruction, context: context)
                        if appModel.voiceProfileProposal(context: context) != nil { dismiss() }
                    }
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isWorking)
            }
            .scrollContentBackground(.hidden)
            .background(Color.agentCanvas)
            .navigationTitle("Teach Cy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
    }
}

private struct VoiceProfileProposalReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var proposal: VoiceProfileChangeProposal

    init(initialProposal: VoiceProfileChangeProposal) {
        _proposal = State(initialValue: initialProposal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    EditorialHeader(
                        kicker: "Proposed voice profile · v\(proposal.sourceVersion + 1)",
                        title: "You decide what Cy learns.",
                        subtitle: "Edit the proposed profile below. Accepting creates a new approved version and keeps your original examples unchanged."
                    )

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        SectionRuleHeader(title: "Current summary")
                        Text(proposal.baseline.summary).font(.agentBody).foregroundStyle(Color.agentSecondary)
                        SectionRuleHeader(title: "Proposed summary")
                        ProfileTextField(label: "Summary", text: $proposal.edited.summary)
                    }

                    ProfileTextField(label: "Tone · one per line", text: listBinding(\.tone))
                    ProfileTextField(label: "Sentence style", text: $proposal.edited.sentenceStyle)
                    ProfileTextField(label: "Signature qualities · one per line", text: listBinding(\.signatureQualities))
                    ProfileTextField(label: "Phrases to use · one per line", text: listBinding(\.phrasesToUse))
                    ProfileTextField(label: "Phrases to avoid · one per line", text: listBinding(\.phrasesToAvoid))
                    ProfileTextField(label: "Guidance · one per line", text: listBinding(\.guidance))

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        MetaLabel("Voice confidence · \(Int(proposal.edited.confidence * 100))%")
                        Slider(value: $proposal.edited.confidence, in: 0...1, step: 0.01)
                            .accessibilityLabel("Voice confidence")
                    }

                    if !proposal.assumptions.isEmpty {
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            SectionRuleHeader(title: "Assumptions")
                            ForEach(proposal.assumptions, id: \.self) { Text("• \($0)").font(.agentBody).foregroundStyle(Color.agentSecondary) }
                        }
                    }
                    if !proposal.evidenceNotes.isEmpty {
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            SectionRuleHeader(title: "Evidence used")
                            ForEach(proposal.evidenceNotes, id: \.self) { Text("• \($0)").font(.agentBody).foregroundStyle(Color.agentSecondary) }
                        }
                    }

                    Button("Accept voice update", systemImage: "checkmark") {
                        appModel.acceptVoiceProfileChange(proposal, context: context)
                        dismiss()
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    Button("Keep current profile") {
                        appModel.discardVoiceProfileChange(context: context)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(AgentSpacing.x6)
            }
            .navigationTitle("Review voice update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .agentScreen()
        }
    }

    private func listBinding(_ keyPath: WritableKeyPath<VoiceProfileDraft, [String]>) -> Binding<String> {
        Binding(
            get: { proposal.edited[keyPath: keyPath].joined(separator: "\n") },
            set: { value in
                proposal.edited[keyPath: keyPath] = value
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct ProfileTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel(label)
            TextField(label, text: $text, axis: .vertical)
                .font(.agentBody)
                .lineLimit(2...8)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
        }
    }
}
