import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [CreatorProfile]
    @Query private var subscriptions: [SubscriptionState]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query private var reminders: [ReminderSettings]
    @AppStorage(CalendarIntegrationPreferences.selectedCalendarTitleKey) private var calendarTitle = ""
    @AppStorage(CalendarIntegrationPreferences.syncScheduledPostsKey) private var syncCalendarPosts = false
    @AppStorage(CalendarIntegrationPreferences.syncTasksKey) private var syncCalendarTasks = false
    @State private var showAddAccount = false
    @State private var showOnboardingPreview = false
    @State private var reviewTestMessage: String?

    var body: some View {
        @Bindable var model = appModel
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
                    .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)

                    VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                        if let profile = profiles.first {
                            SettingsIndexSection(title: "Profile") {
                                NavigationLink {
                                    CreatorProfileSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(
                                        title: "Creator profile",
                                        value: activeIdentity.name.isEmpty ? "Add name" : activeIdentity.name
                                    )
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
                            if let profile = profiles.first {
                                NavigationLink {
                                    NewPostSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(
                                        title: "New post",
                                        value: "\(enabledPostSectionCount(for: profile)) enabled"
                                    )
                                }
                            }
                            NavigationLink {
                                PublishingSettingsView()
                            } label: {
                                SettingsIndexRow(title: "Destinations & formats", value: "\(activeDestinationCount)")
                            }
                            if let profile = profiles.first {
                                NavigationLink {
                                    BrandPartnershipSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(
                                        title: "Brand partnerships",
                                        value: profile.showsBrandDealsInPostEditor ? "Enabled" : "Off"
                                    )
                                }
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
                                    value: "Connected"
                                )
                            }
                            if let profile = profiles.first {
                                NavigationLink {
                                    CyQuickPromptsSettingsView(profile: profile)
                                } label: {
                                    SettingsIndexRow(
                                        title: "Quick prompts",
                                        value: "2"
                                    )
                                }
                            }
                            NavigationLink {
                                MCPBridgeSettingsView()
                            } label: {
                                SettingsIndexRow(
                                    title: "Claude & Codex",
                                    value: MCPBridgePreferences.isConnected ? "Connected" : "Set up"
                                )
                            }
                            Button(action: sendReviewPostTest) {
                                SettingsIndexRow(
                                    title: "Review post test",
                                    value: "Send to Cy",
                                    isLast: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsIndexSection(title: "Shortcuts & widgets") {
                            NavigationLink {
                                CaptureIdeaShortcutSettingsView()
                            } label: {
                                SettingsIndexRow(
                                    title: "Idea capture & widgets",
                                    value: "Set up",
                                    isLast: true
                                )
                            }
                        }

                        SettingsIndexSection(title: "Cy & your data") {
                            Button {
                                showOnboardingPreview = true
                            } label: {
                                SettingsIndexRow(title: "Preview onboarding", value: "Review")
                            }
                            .buttonStyle(.plain)
                            Button {
                                appModel.startWalkthrough()
                                dismiss()
                            } label: {
                                SettingsIndexRow(
                                    title: "Replay walkthrough",
                                    value: "\(AppWalkthroughStep.allCases.count) steps"
                                )
                            }
                            .buttonStyle(.plain)
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
                            .font(.agentMetadata)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, AgentSpacing.x2)
                    }
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x3)
                    .padding(.bottom, AgentSpacing.x12)
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.floating))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.floating, role: .structural)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color.agentCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .navigationDestination(item: $model.requestedSettingsPage) { page in
            switch page {
            case .notifications: NotificationSettingsView()
            case .access: AccessSettingsView()
            case .mcpBridge: MCPBridgeSettingsView()
            }
        }
        .agentKeyboardDismissal()
        .sheet(isPresented: $showAddAccount) {
            if let profile = profiles.first {
                SocialAccountEditorView(profile: profile, initialIdentity: activeIdentity)
            }
        }
        .fullScreenCover(isPresented: $showOnboardingPreview) {
            if let profile = profiles.first {
                OnboardingView(
                    previewOnly: true,
                    initialDraft: OnboardingDraft(
                        name: activeIdentity.name,
                        goal: profile.goal,
                        vibePalette: profile.vibePalette,
                        appearance: profile.appearance,
                        aiProvider: LocalCyPreferences.isEnabled ? .claudeOrCodex : .agentCy,
                        brandPartnershipsEnabled: profile.showsBrandDealsInPostEditor
                    )
                )
            }
        }
        .alert("agent.cy", isPresented: Binding(
            get: { reviewTestMessage != nil },
            set: { if !$0 { reviewTestMessage = nil } }
        )) {
            Button("Close", role: .cancel) { reviewTestMessage = nil }
        } message: {
            Text(reviewTestMessage ?? "")
        }
    }

    private var activeDestinationCount: Int {
        destinations.filter { !$0.isArchived }.count
    }

    private func sendReviewPostTest() {
        do {
            try MCPBridgeService.queueDemoDraft(context: context)
            appModel.requestedSettingsPage = nil
            appModel.presentedSheet = nil
            appModel.selectedTab = .cy
        } catch {
            reviewTestMessage = CreatorFacingErrorMapper.presentation(
                for: error,
                action: "The review post test"
            ).message
        }
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profiles.first,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private func enabledPostSectionCount(for profile: CreatorProfile) -> Int {
        [
            profile.showsHookInPostEditor,
            profile.showsMoodBoardsInPostEditor,
        ].filter { $0 }.count
    }

    private var reminderSummary: String {
        guard let reminder = reminders.first else { return "Off" }
        guard reminder.masterEnabled else { return "Off" }
        let count = [
            reminder.dailyEnabled,
            reminder.weeklyEnabled,
            reminder.postRemindersEnabled,
            reminder.missedPostRemindersEnabled,
            reminder.taskRemindersEnabled,
            reminder.draftPrepRemindersEnabled,
            reminder.accessRemindersEnabled,
        ].filter { $0 }.count
        return count == 0 ? "Off" : "\(count) enabled"
    }

    private var calendarSummary: String {
        guard !calendarTitle.isEmpty else { return "Off" }
        guard syncCalendarPosts || syncCalendarTasks else { return "Connected" }
        return calendarTitle
    }

    private func accountSummary(for profile: CreatorProfile) -> String {
        if let activeID = appModel.activeWorkspaceID,
           let workspace = workspaces.first(where: { $0.id == activeID && !$0.isArchived }) {
            return workspace.name
        }
        let active = socialAccounts.filter { $0.profileID == profile.id && !$0.isArchived }
        if let primary = active.first(where: \.isPrimary) { return primary.label }
        if let first = active.first { return first.label }
        return "None"
    }

    private var accessSummary: String {
        guard let subscription = subscriptions.first else { return "Free" }
        return switch AccessPolicy.effectiveAccess(for: subscription) {
        case .freeJourney: "8 Cy credits"
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
                    Button("Create destination") {
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
