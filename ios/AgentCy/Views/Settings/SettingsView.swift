import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [CreatorProfile]
    @Query private var voiceExamples: [VoiceExample]
    @Query private var subscriptions: [SubscriptionState]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query private var reminders: [ReminderSettings]
    @AppStorage(CalendarIntegrationPreferences.selectedCalendarTitleKey) private var calendarTitle = ""
    @AppStorage(CalendarIntegrationPreferences.syncScheduledPostsKey) private var syncCalendarPosts = false
    @AppStorage(CalendarIntegrationPreferences.syncTasksKey) private var syncCalendarTasks = false
    @State private var showAddAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    EditorialHeader(
                        kicker: "Account",
                        title: "Settings",
                        subtitle: "Make agent.cy feel like yours."
                    )
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x8)
                    .padding(.bottom, AgentSpacing.x6)

                    VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                        if let profile = profiles.first {
                            SettingsIndexSection(title: "Profile") {
                                NavigationLink {
                                    CreatorProfileSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(title: "Creator profile", value: profile.name.isEmpty ? "Add name" : profile.name)
                                }
                                NavigationLink {
                                    CyAssistanceSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(title: "How Cy helps", value: profile.assistanceMode.title)
                                }
                                NavigationLink {
                                    AppearanceSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(title: "Appearance", value: profile.appearance.title, isLast: true)
                                }
                            }

                            SettingsIndexSection(title: "Accounts") {
                                NavigationLink {
                                    AccountSwitcherSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(title: "Switch account", value: accountSummary(for: profile))
                                }
                                Button {
                                    showAddAccount = true
                                } label: {
                                    SettingsIndexRow(title: "Add account", value: "", isLast: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        SettingsIndexSection(title: "Publishing") {
                            NavigationLink {
                                PublishingSettingsView()
                            } label: {
                                SettingsIndexRow(title: "Destinations & formats", value: "\(activeDestinationCount)")
                            }
                            NavigationLink {
                                CalendarIntegrationSettingsView()
                            } label: {
                                SettingsIndexRow(title: "Calendar", value: calendarSummary)
                            }
                            NavigationLink {
                                NotificationSettingsView()
                            } label: {
                                SettingsIndexRow(title: "Notifications", value: reminderSummary, isLast: true)
                            }
                        }

                        SettingsIndexSection(title: "AI") {
                            NavigationLink {
                                AIConnectionsSettingsView()
                            } label: {
                                SettingsIndexRow(
                                    title: "Cy connection",
                                    value: "Connected",
                                    isLast: true
                                )
                            }
                        }

                        SettingsIndexSection(title: "Shortcuts & widgets") {
                            NavigationLink {
                                CaptureIdeaShortcutSettingsView()
                            } label: {
                                SettingsIndexRow(
                                    title: "Idea Capture Shortcut",
                                    value: "Setup",
                                    isLast: true
                                )
                            }
                        }

                        SettingsIndexSection(title: "Cy & your data") {
                            NavigationLink {
                                VoiceExamplesView(embeddedInNavigation: true)
                            } label: {
                                SettingsIndexRow(title: "Voice examples", value: "\(readyExampleCount)")
                            }
                            NavigationLink {
                                AccessSettingsView()
                            } label: {
                                SettingsIndexRow(title: "Access", value: accessSummary)
                            }
                            NavigationLink {
                                ExportSettingsView()
                            } label: {
                                SettingsIndexRow(title: "Export data", value: "↗", isLast: true, showsChevron: false)
                            }
                        }

                        SettingsIndexSection(title: "Reset") {
                            NavigationLink {
                                ResetPostsAndTasksSettingsView()
                            } label: {
                                SettingsIndexRow(
                                    title: "Reset posts & tasks",
                                    value: "",
                                    tint: .agentDestructive,
                                    secondaryTint: .agentDestructive
                                )
                            }
                            NavigationLink {
                                EraseDataSettingsView(onErased: { dismiss() })
                            } label: {
                                SettingsIndexRow(
                                    title: "Erase all data",
                                    value: "",
                                    isLast: true,
                                    tint: .agentDestructive,
                                    secondaryTint: .agentDestructive
                                )
                            }
                        }

                        Text("Version \(versionLabel)")
                            .font(.agentMono)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, AgentSpacing.x2)
                    }
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x3)
                    .padding(.bottom, AgentSpacing.x12)
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.floating))
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.agentCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .agentKeyboardDismissal()
        .sheet(isPresented: $showAddAccount) {
            if let profile = profiles.first {
                SocialAccountEditorView(profile: profile)
            }
        }
    }

    private var readyExampleCount: Int {
        guard let profileID = profiles.first?.id else { return 0 }
        return voiceExamples.filter {
            $0.profileID == profileID && $0.creatorConfirmed && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var activeDestinationCount: Int {
        destinations.filter { !$0.isArchived }.count
    }

    private var reminderSummary: String {
        guard let reminder = reminders.first else { return "Off" }
        if reminder.dailyEnabled && reminder.weeklyEnabled { return "2 on" }
        if reminder.dailyEnabled || reminder.weeklyEnabled { return "1 on" }
        return "Off"
    }

    private var calendarSummary: String {
        guard !calendarTitle.isEmpty else { return "Off" }
        guard syncCalendarPosts || syncCalendarTasks else { return "Connected" }
        return calendarTitle
    }

    private func accountSummary(for profile: CreatorProfile) -> String {
        let active = socialAccounts.filter { $0.profileID == profile.id && !$0.isArchived }
        if let primary = active.first(where: \.isPrimary) { return primary.label }
        if let first = active.first { return first.label }
        return "None"
    }

    private var accessSummary: String {
        guard let subscription = subscriptions.first else { return "Free" }
        return switch AccessPolicy.effectiveAccess(for: subscription) {
        case .freeJourney: "Free"
        case .trial: "Trial"
        case .paid: "Paid"
        case .comped: "Promotional"
        case .expired: "Expired"
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "18"
        return "\(version) (\(build))"
    }
}

struct NewDestinationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var formatName = "Post"
    @State private var kind: PublishingFormatKind = .nonVideo

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") { TextField("Name", text: $name).agentSingleLineSubmit() }
                Section("Default format") {
                    TextField("Format name", text: $formatName)
                        .agentSingleLineSubmit()
                    Picker("Type", selection: $kind) {
                        ForEach(PublishingFormatKind.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .navigationTitle("New destination")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let destination = PublishingDestination(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        context.insert(destination)
                        context.insert(PublishingFormat(destinationID: destination.id, name: formatName.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind))
                        try? context.save(); dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || formatName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .agentKeyboardDismissal()
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
                    AgentMultilineField(
                        label: "Guidance",
                        placeholder: "For example: Keep my openings shorter and less polished",
                        text: $instruction,
                        lineLimit: 3...8
                    )
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
        .agentKeyboardDismissal()
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
        .agentKeyboardDismissal()
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
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            AgentInputHeader(title: label, isEditing: isFocused) { isFocused = false }
            TextField(label, text: $text, axis: .vertical)
                .font(.agentBody)
                .lineLimit(2...8)
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                .focused($isFocused)
        }
    }
}
