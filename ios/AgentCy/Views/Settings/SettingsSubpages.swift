import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct SettingsIndexSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: title)
            content
                .padding(.top, AgentSpacing.x1)
        }
    }
}

struct SettingsIndexRow: View {
    let title: String
    let value: String
    var isLast = false
    var showsChevron = true
    var tint: Color = .agentText
    var secondaryTint: Color = .agentSecondary

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            Text(title)
                .font(.agentBody)
                .foregroundStyle(tint)
            Spacer(minLength: AgentSpacing.x4)
            if !value.isEmpty {
                Text(value)
                    .font(.agentBody)
                    .foregroundStyle(secondaryTint)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTint)
            }
        }
        .frame(minHeight: 48)
        .contentShape(.rect)
    }
}

struct SettingsPageShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var headerHeight: CGFloat = 0
    let kicker: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    EditorialHeader(kicker: kicker, title: title, subtitle: subtitle)
                        .padding(.horizontal, AgentLayout.pageMargin)
                        .padding(.top, AgentSpacing.x8)
                        .padding(.bottom, AgentSpacing.x6)
                        .reportAgentViewHeight()

                    VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AgentLayout.pageMargin)
                    .padding(.top, AgentSpacing.x6)
                    .padding(.bottom, AgentSpacing.x16)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(0, proxy.size.height - headerHeight),
                        alignment: .topLeading
                    )
                    .background(Color.agentSurface)
                    .clipShape(.rect(cornerRadius: AgentRadius.floating))
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Color.agentCanvas)
        .onPreferenceChange(AgentViewHeightPreferenceKey.self) { headerHeight = $0 }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", systemImage: "chevron.left") { dismiss() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .principal) {
                Text("Settings").font(.agentHeadline)
            }
        }
        .agentKeyboardDismissal()
    }
}

struct CreatorProfileSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Bindable var profile: CreatorProfile
    @State private var showNewAccount = false
    @State private var editingAccount: CreatorSocialAccount?
    @State private var selectedAvatarPhoto: PhotosPickerItem?

    var body: some View {
        SettingsPageShell(
            kicker: "Account",
            title: "Creator profile",
            subtitle: "Keep the basics Cy uses to shape your work."
        ) {
            avatarEditor
            SettingsTextField(label: "Name", placeholder: "Your name", text: $profile.name)
            SettingsTextField(
                label: "Primary goal",
                placeholder: "What do you want your content to do?",
                text: $profile.goal,
                lineRange: 3...7
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    MetaLabel("Social accounts")
                    Spacer()
                    Text("Manual references")
                        .font(.agentMono)
                        .foregroundStyle(Color.agentSecondary)
                }
                .padding(.bottom, AgentSpacing.x3)

                if activeAccounts.isEmpty {
                    Text("Add the profiles you own so each post can point to the right account.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                        .padding(.vertical, AgentSpacing.x4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
                } else {
                    ForEach(Array(activeAccounts.enumerated()), id: \.element.id) { index, account in
                        SocialAccountRow(
                            account: account,
                            destinationName: destinationName(for: account),
                            isLast: index == activeAccounts.count - 1,
                            onEdit: { editingAccount = account }
                        )
                    }
                }

                Button("Add account", systemImage: "plus") { showNewAccount = true }
                    .buttonStyle(AgentSecondaryButtonStyle())
                    .padding(.top, AgentSpacing.x4)

                Text("Links stay private and are not connected, fetched, or posted to automatically.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.top, AgentSpacing.x3)
            }

            Text("Changes save automatically.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
        .onDisappear { try? context.save() }
        .sheet(isPresented: $showNewAccount) {
            SocialAccountEditorView(profile: profile)
        }
        .sheet(item: $editingAccount) { account in
            SocialAccountEditorView(profile: profile, account: account)
        }
        .onChange(of: selectedAvatarPhoto) { _, item in
            importAvatar(item)
        }
    }

    private var avatarEditor: some View {
        let photoActionTitle = profile.avatarImageData == nil ? "Choose photo" : "Change photo"
        return VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("Profile photo")
            HStack(spacing: AgentSpacing.x4) {
                CreatorAvatar(profile: profile, size: 72)
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    PhotosPicker(selection: $selectedAvatarPhoto, matching: .images) {
                        Text(photoActionTitle)
                    }
                    .buttonStyle(AgentCompactSecondaryButtonStyle())

                    if profile.avatarImageData != nil {
                        Button("Remove photo") {
                            profile.avatarImageData = nil
                            try? context.save()
                        }
                        .font(.agentSubtext.weight(.medium))
                        .foregroundStyle(Color.agentSecondary)
                    }
                }
            }
        }
    }

    private func importAvatar(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            defer { selectedAvatarPhoto = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            let side: CGFloat = 512
            let scale = max(side / image.size.width, side / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let drawOrigin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
                image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
            }
            profile.avatarImageData = rendered.jpegData(compressionQuality: 0.82)
            try? context.save()
        }
    }

    private var activeAccounts: [CreatorSocialAccount] {
        socialAccounts.filter { $0.profileID == profile.id && !$0.isArchived }
    }

    private func destinationName(for account: CreatorSocialAccount) -> String {
        destinations.first(where: { $0.id == account.destinationID })?.name ?? "Platform"
    }
}

struct AccountSwitcherSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Bindable var profile: CreatorProfile

    private var activeAccounts: [CreatorSocialAccount] {
        socialAccounts.filter { $0.profileID == profile.id && !$0.isArchived }
    }

    var body: some View {
        SettingsPageShell(
            kicker: "Accounts",
            title: "Switch account",
            subtitle: "Choose the default account Cy uses for each platform."
        ) {
            if activeAccounts.isEmpty {
                Text("Add an account first, then return here to choose its platform default.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activeAccounts.enumerated()), id: \.element.id) { index, account in
                        Button {
                            makePrimary(account)
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(account.label)
                                        .font(.agentBody.weight(.semibold))
                                    MetaLabel(destinationName(for: account))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if account.isPrimary {
                                    Text("Default")
                                        .font(.agentMono)
                                        .foregroundStyle(Color.cyAccent)
                                }
                                Image(systemName: account.isPrimary ? "checkmark" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 24, height: 24)
                            }
                            .foregroundStyle(Color.agentText)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .contentShape(.rect)
                            .overlay(alignment: .top) {
                                if index > 0 { Rectangle().fill(Color.agentBorder).frame(height: 1) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use \(account.label) by default for \(destinationName(for: account))")
                        .accessibilityAddTraits(account.isPrimary ? .isSelected : [])
                    }
                }
            }

            Text("Switching changes the default for new posts. Existing posts keep the account already assigned to them.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
    }

    private func destinationName(for account: CreatorSocialAccount) -> String {
        destinations.first(where: { $0.id == account.destinationID })?.name ?? "Platform"
    }

    private func makePrimary(_ account: CreatorSocialAccount) {
        for peer in activeAccounts where peer.destinationID == account.destinationID {
            peer.isPrimary = peer.id == account.id
            peer.updatedAt = Date()
        }
        try? context.save()
    }
}

private struct SocialAccountRow: View {
    let account: CreatorSocialAccount
    let destinationName: String
    let isLast: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(account.label)
                        .font(.agentHeadline)
                        .foregroundStyle(Color.agentText)
                        .lineLimit(1)
                    HStack(spacing: AgentSpacing.x2) {
                        MetaLabel(destinationName)
                        if account.isPrimary { MetaLabel("Primary").foregroundStyle(Color.cyAccent) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if let url = account.profileURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.agentText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open \(account.label) profile")
            }

            Button(action: onEdit) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.agentSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(account.label)")
        }
        .frame(minHeight: 68)
        .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        .overlay(alignment: .bottom) {
            if isLast { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        }
    }
}

struct SocialAccountEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query private var outputs: [PlatformOutput]

    let profile: CreatorProfile
    let account: CreatorSocialAccount?
    @State private var label: String
    @State private var profileURLString: String
    @State private var destinationID: UUID
    @State private var isPrimary: Bool
    @State private var confirmRemove = false
    @State private var lastSuggestedURL: String?

    init(profile: CreatorProfile, account: CreatorSocialAccount? = nil) {
        self.profile = profile
        self.account = account
        _label = State(initialValue: account?.label ?? "")
        _profileURLString = State(initialValue: account?.profileURLString ?? "")
        _destinationID = State(initialValue: account?.destinationID ?? PublishingCatalog.instagramID)
        _isPrimary = State(initialValue: account?.isPrimary ?? false)
        _lastSuggestedURL = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            SettingsPageShell(
                kicker: "Creator profile",
                title: account == nil ? "Add account" : "Edit account",
                subtitle: "Keep each profile distinct when you plan where a post will go."
            ) {
                SettingsTextField(label: "Account", placeholder: "@handle or account name", text: $label)
                SettingsTextField(label: "Profile link", placeholder: "https://instagram.com/yourname", text: $profileURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Platform")
                    Picker("Platform", selection: $destinationID) {
                        ForEach(activeDestinations) { destination in
                            Text(destination.name).tag(destination.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, AgentSpacing.x4)
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                }

                Toggle(isOn: $isPrimary) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text("Default account").font(.agentHeadline).foregroundStyle(Color.agentText)
                        Text("Use this first for new posts on this platform.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
                .tint(.actionAccent)

                if let message = validationMessage {
                    Text(message)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentDestructive)
                }

                Button(account == nil ? "Add account" : "Save account") { save() }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(validationMessage != nil || activeDestinations.isEmpty)

                if account != nil {
                    Button("Remove account", role: .destructive) { confirmRemove = true }
                        .buttonStyle(AgentSecondaryButtonStyle())
                }

                Text("agent.cy stores this as a private reference. It does not sign in, read posts, or publish for you.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
        .onAppear {
            if !activeDestinations.contains(where: { $0.id == destinationID }),
               let first = activeDestinations.first {
                destinationID = first.id
            }
            if account == nil && accounts(for: destinationID).isEmpty { isPrimary = true }
            updateSuggestedURL()
        }
        .onChange(of: label) { _, _ in updateSuggestedURL() }
        .onChange(of: destinationID) { _, newDestinationID in
            if account == nil || account?.destinationID != newDestinationID {
                isPrimary = accounts(for: newDestinationID).isEmpty
            }
            updateSuggestedURL()
        }
        .confirmationDialog("Remove this account?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove account", role: .destructive) { remove() }
            Button("Keep account", role: .cancel) {}
        } message: {
            Text("Existing posts stay intact. This account will no longer be available for new post versions.")
        }
    }

    private var activeDestinations: [PublishingDestination] {
        destinations.filter { !$0.isArchived }
    }

    private var validationMessage: String? {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add an account name or handle." }
        if resolvedProfileURLString == nil { return "Add a handle or use a valid HTTPS profile link." }
        return nil
    }

    private var resolvedProfileURLString: String? {
        let typed = profileURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return CreatorSocialAccount.normalizedURLString(typed) }
        return suggestedProfileURL
    }

    private var suggestedProfileURL: String? {
        guard let destination = activeDestinations.first(where: { $0.id == destinationID }),
              let kind = destination.builtInKind else { return nil }
        return CreatorSocialAccount.profileURLString(forHandle: label, destination: kind)
    }

    private func updateSuggestedURL() {
        let suggestion = suggestedProfileURL
        let current = profileURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == lastSuggestedURL {
            profileURLString = suggestion ?? ""
        }
        lastSuggestedURL = suggestion
    }

    private func accounts(for destinationID: UUID, excluding excludedID: UUID? = nil) -> [CreatorSocialAccount] {
        socialAccounts.filter {
            $0.profileID == profile.id &&
                $0.destinationID == destinationID &&
                !$0.isArchived &&
                $0.id != excludedID
        }
    }

    private func save() {
        guard validationMessage == nil,
              let normalizedURL = resolvedProfileURLString else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let peers = accounts(for: destinationID, excluding: account?.id)
        let shouldBePrimary = isPrimary || !peers.contains(where: \.isPrimary)
        let savedAccount: CreatorSocialAccount

        if let account {
            let oldDestinationID = account.destinationID
            account.destinationID = destinationID
            account.label = cleanLabel
            account.profileURLString = normalizedURL
            account.isPrimary = shouldBePrimary
            account.updatedAt = Date()
            savedAccount = account

            if oldDestinationID != destinationID {
                for output in outputs where output.socialAccountID == account.id && output.destinationID != destinationID {
                    output.socialAccountID = nil
                }
                promotePrimaryIfNeeded(for: oldDestinationID, excluding: account.id)
            }
        } else {
            let nextSortOrder = (socialAccounts.map(\.sortOrder).max() ?? -1) + 1
            let newAccount = CreatorSocialAccount(
                profileID: profile.id,
                destinationID: destinationID,
                label: cleanLabel,
                profileURLString: normalizedURL,
                isPrimary: shouldBePrimary,
                sortOrder: nextSortOrder
            )
            context.insert(newAccount)
            savedAccount = newAccount
        }

        if savedAccount.isPrimary {
            for peer in peers { peer.isPrimary = false; peer.updatedAt = Date() }
        }
        try? context.save()
        dismiss()
    }

    private func remove() {
        guard let account else { return }
        account.isArchived = true
        account.updatedAt = Date()
        for output in outputs where output.socialAccountID == account.id { output.socialAccountID = nil }
        if account.isPrimary { promotePrimaryIfNeeded(for: account.destinationID, excluding: account.id) }
        try? context.save()
        dismiss()
    }

    private func promotePrimaryIfNeeded(for destinationID: UUID, excluding excludedID: UUID) {
        let remaining = accounts(for: destinationID, excluding: excludedID)
        guard !remaining.contains(where: \.isPrimary), let first = remaining.first else { return }
        first.isPrimary = true
        first.updatedAt = Date()
    }
}

struct CyAssistanceSettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: CreatorProfile

    var body: some View {
        SettingsPageShell(
            kicker: "Cy",
            title: "How Cy helps",
            subtitle: "Choose how much initiative Cy should take."
        ) {
            VStack(spacing: 0) {
                ForEach(Array(AssistanceMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    Button {
                        profile.assistanceMode = mode
                        try? context.save()
                    } label: {
                        SettingsSelectionRow(
                            title: mode.title,
                            detail: mode.detail,
                            isSelected: profile.assistanceMode == mode,
                            isLast: index == AssistanceMode.allCases.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var profile: CreatorProfile

    var body: some View {
        SettingsPageShell(
            kicker: "Display",
            title: "Appearance",
            subtitle: "Choose the look that feels best right now."
        ) {
            VStack(spacing: 0) {
                ForEach(Array(AppearancePreference.allCases.enumerated()), id: \.element.id) { index, appearance in
                    Button {
                        profile.appearance = appearance
                        appModel.appearancePreference = appearance
                        try? context.save()
                    } label: {
                        HStack(spacing: AgentSpacing.x4) {
                            AppearanceSwatch(appearance: appearance)
                            Text(appearance.title)
                                .font(.agentHeadline)
                                .foregroundStyle(Color.agentText)
                            Spacer()
                            if profile.appearance == appearance {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.agentText)
                            }
                        }
                        .frame(minHeight: 72)
                        .contentShape(.rect)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.agentBorder).frame(height: 1)
                        }
                        .overlay(alignment: .bottom) {
                            if index == AppearancePreference.allCases.count - 1 {
                                Rectangle().fill(Color.agentBorder).frame(height: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AppearanceSwatch: View {
    let appearance: AppearancePreference

    var body: some View {
        Group {
            switch appearance {
            case .system:
                LinearGradient(
                    colors: [.agentSurface, .agentSurface, .agentText, .agentText],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .light:
                Color.agentSurface
            case .dark:
                Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.agentBorder, lineWidth: 1))
    }
}

struct PublishingSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \PublishingFormat.sortOrder) private var formats: [PublishingFormat]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @State private var showNewDestination = false
    @State private var destinationForNewFormat: PublishingDestination?

    var body: some View {
        SettingsPageShell(
            kicker: "Publishing",
            title: "Destinations & formats",
            subtitle: "Choose where you publish and the formats you use."
        ) {
            ForEach(destinations.filter { !$0.isArchived }) { destination in
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    HStack {
                        Text(destination.name)
                            .font(.agentHeadline)
                            .foregroundStyle(Color.agentText)
                        Spacer()
                        if destination.builtInKind == nil {
                            Button("Remove", role: .destructive) {
                                remove(destination)
                            }
                            .font(.agentSubtext)
                        }
                    }
                    .padding(.bottom, AgentSpacing.x2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.agentBorder).frame(height: 1)
                    }

                    ForEach(formats.filter { $0.destinationID == destination.id }) { format in
                        Toggle(isOn: formatBinding(format)) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                Text(format.name)
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentText)
                                Text(format.kind.title)
                                    .font(.agentMono)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                        }
                        .tint(.actionAccent)
                        .frame(minHeight: 50)
                    }

                    Button("Add format", systemImage: "plus") {
                        destinationForNewFormat = destination
                    }
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentText)
                    .frame(minHeight: 44)
                }
            }

            Button("Add destination", systemImage: "plus") {
                showNewDestination = true
            }
            .buttonStyle(AgentSecondaryButtonStyle())
        }
        .sheet(isPresented: $showNewDestination) { NewDestinationView() }
        .sheet(item: $destinationForNewFormat) { destination in
            NewPublishingFormatView(destination: destination)
        }
    }

    private func formatBinding(_ format: PublishingFormat) -> Binding<Bool> {
        Binding(
            get: { !format.isArchived },
            set: { enabled in
                format.isArchived = !enabled
                try? context.save()
            }
        )
    }

    private func remove(_ destination: PublishingDestination) {
        destination.isArchived = true
        for format in formats where format.destinationID == destination.id {
            format.isArchived = true
        }
        for account in socialAccounts where account.destinationID == destination.id {
            account.isArchived = true
            account.updatedAt = Date()
        }
        try? context.save()
    }
}

private struct NewPublishingFormatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let destination: PublishingDestination
    @State private var name = ""
    @State private var kind: PublishingFormatKind = .shortVideo

    var body: some View {
        NavigationStack {
            SettingsPageShell(
                kicker: destination.name,
                title: "New format",
                subtitle: "Add another way you publish here."
            ) {
                SettingsTextField(label: "Format name", placeholder: "For example: Carousel", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(PublishingFormatKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Add format") {
                    context.insert(PublishingFormat(
                        destinationID: destination.id,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        kind: kind
                    ))
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct CalendarIntegrationSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(CalendarIntegrationPreferences.selectedCalendarIdentifierKey) private var calendarIdentifier = ""
    @AppStorage(CalendarIntegrationPreferences.selectedCalendarTitleKey) private var calendarTitle = ""
    @AppStorage(CalendarIntegrationPreferences.syncScheduledPostsKey) private var syncScheduledPosts = false
    @AppStorage(CalendarIntegrationPreferences.syncTasksKey) private var syncTasks = false
    @State private var authorization: AgentCalendarAuthorization = .notDetermined
    @State private var calendars: [AgentCalendarChoice] = []
    @State private var isConnecting = false
    @State private var confirmDisconnect = false

    var body: some View {
        SettingsPageShell(
            kicker: "Publishing",
            title: "Calendar",
            subtitle: "Keep scheduled work beside the rest of your week."
        ) {
            if isConnected {
                connectedContent
            } else {
                connectionContent
            }
        }
        .task { reloadState() }
        .onChange(of: syncScheduledPosts) { _, _ in syncAfterPreferenceChange() }
        .onChange(of: syncTasks) { _, _ in syncAfterPreferenceChange() }
        .confirmationDialog("Disconnect calendar?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect calendar", role: .destructive) {
                appModel.disconnectCalendar(context: context)
                reloadState()
            }
            Button("Keep connected", role: .cancel) {}
        } message: {
            Text("Calendar events created by agent.cy will be removed. Your posts, tasks, and agenda stay in agent.cy.")
        }
    }

    private var connectionContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x6) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                SectionRuleHeader(title: "Connect")
                Text(connectionMessage)
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }

            if authorization == .denied || authorization == .restricted {
                Button("Open iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .buttonStyle(AgentPrimaryButtonStyle())
            } else {
                Button(isConnecting ? "Connecting…" : "Connect calendar") {
                    Task { await connect() }
                }
                .buttonStyle(AgentPrimaryButtonStyle())
                .disabled(isConnecting)
            }

            Text("Google calendars already added to this iPhone will appear as choices. agent.cy never receives your Google password.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x8) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                SectionRuleHeader(title: "Calendar")
                Menu {
                    ForEach(calendars) { calendar in
                        Button {
                            select(calendar)
                        } label: {
                            if calendar.id == calendarIdentifier {
                                Label(calendar.displayTitle, systemImage: "checkmark")
                            } else {
                                Text(calendar.displayTitle)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AgentSpacing.x3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendarTitle.isEmpty ? "Choose calendar" : calendarTitle)
                                .font(.agentBody.weight(.semibold))
                                .foregroundStyle(Color.agentText)
                            if let selectedCalendar, !selectedCalendar.sourceTitle.isEmpty {
                                Text(selectedCalendar.sourceTitle)
                                    .font(.agentSubtext)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.agentSecondary)
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(minHeight: 56)
                    .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                SectionRuleHeader(title: "Sync")
                Toggle("Scheduled posts", isOn: $syncScheduledPosts)
                    .font(.agentBody)
                    .tint(.actionAccent)
                    .frame(minHeight: 48)
                Toggle("Production tasks", isOn: $syncTasks)
                    .font(.agentBody)
                    .tint(.actionAccent)
                    .frame(minHeight: 48)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                Button("Sync now") {
                    appModel.refreshCalendarSync(context: context, showConfirmation: true)
                }
                .buttonStyle(AgentSecondaryButtonStyle())

                Button("Disconnect calendar", role: .destructive) {
                    confirmDisconnect = true
                }
                .font(.agentBody.weight(.semibold))
                .foregroundStyle(Color.agentDestructive)
                .frame(maxWidth: .infinity, minHeight: 44)
            }

            Text("agent.cy remains the source of truth. Changes made directly in Calendar do not change your agent.cy agenda.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
    }

    private var isConnected: Bool {
        authorization == .fullAccess && !calendarIdentifier.isEmpty && selectedCalendar != nil
    }

    private var selectedCalendar: AgentCalendarChoice? {
        calendars.first(where: { $0.id == calendarIdentifier })
    }

    private var connectionMessage: String {
        switch authorization {
        case .denied, .restricted:
            "Calendar access is off. Allow full calendar access in iPhone Settings to choose a calendar and keep events updated."
        case .writeOnly:
            "Full access is needed so agent.cy can update or remove events when your agenda changes."
        case .notDetermined, .fullAccess:
            "Choose any writable calendar already on this iPhone, including a connected Google calendar."
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        guard await appModel.requestCalendarAccess() else {
            reloadState()
            return
        }
        reloadState()
        guard let choice = selectedCalendar ?? calendars.first(where: \.isDefault) ?? calendars.first else {
            appModel.notice = .error("No writable calendars are available on this iPhone.")
            return
        }
        calendarIdentifier = choice.id
        calendarTitle = choice.title
        syncScheduledPosts = true
        appModel.refreshCalendarSync(context: context, showConfirmation: true)
    }

    private func select(_ calendar: AgentCalendarChoice) {
        calendarIdentifier = calendar.id
        calendarTitle = calendar.title
        appModel.refreshCalendarSync(context: context)
    }

    private func syncAfterPreferenceChange() {
        guard !calendarIdentifier.isEmpty else { return }
        appModel.queueCalendarSync(context: context)
    }

    private func reloadState() {
        authorization = appModel.calendarAuthorization
        calendars = appModel.availableCalendars()
        if !calendarIdentifier.isEmpty, selectedCalendar == nil {
            calendarTitle = ""
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var reminders: [ReminderSettings]

    var body: some View {
        Group {
            if let reminder = reminders.first {
                NotificationSettingsContent(settings: reminder)
            } else {
                SettingsPageShell(
                    kicker: "Publishing",
                    title: "Notifications",
                    subtitle: "Choose when agent.cy should get your attention."
                ) {
                    ProgressView()
                }
                .task {
                    guard reminders.isEmpty else { return }
                    context.insert(ReminderSettings())
                    try? context.save()
                }
            }
        }
    }
}

private struct NotificationSettingsContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var settings: ReminderSettings

    var body: some View {
        SettingsPageShell(
            kicker: "Publishing",
            title: "Notifications",
            subtitle: "Choose when agent.cy should get your attention."
        ) {
            MetaLabel("Reminders")
            reminderBlock(
                title: "Daily focus",
                detail: "A gentle prompt to choose today’s next move.",
                isOn: $settings.dailyEnabled
            ) {
                DatePicker("Time", selection: hourBinding(\.dailyHour), displayedComponents: .hourAndMinute)
                    .font(.agentBody)
                    .frame(minHeight: 52)
            }

            reminderBlock(
                title: "New week",
                detail: "Cy checks in every Monday to help you plan the week.",
                isOn: $settings.weeklyEnabled
            ) {
                DatePicker("Time", selection: hourBinding(\.weeklyHour), displayedComponents: .hourAndMinute)
                    .font(.agentBody)
                    .frame(minHeight: 52)
            }

            Text("agent.cy asks for notification permission only after you turn on a reminder.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
        .onChange(of: settings.dailyEnabled) { _, _ in apply() }
        .onChange(of: settings.dailyHour) { _, _ in apply() }
        .onChange(of: settings.weeklyEnabled) { _, _ in apply() }
        .onChange(of: settings.weeklyHour) { _, _ in apply() }
    }

    private func reminderBlock<Content: View>(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        @ViewBuilder controls: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title).font(.agentHeadline).foregroundStyle(Color.agentText)
                    Text(detail).font(.agentBody).foregroundStyle(Color.agentSecondary)
                }
            }
            .tint(.actionAccent)
            controls()
                .padding(.horizontal, AgentSpacing.x1)
                .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1 : 0.5)
        }
    }

    private func hourBinding(_ keyPath: ReferenceWritableKeyPath<ReminderSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings[keyPath: keyPath], minute: 0, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                settings[keyPath: keyPath] = Calendar.current.component(.hour, from: date)
            }
        )
    }

    private func apply() {
        Task { await appModel.applyReminderSettings(settings, context: context) }
    }
}

struct AccessSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var subscriptions: [SubscriptionState]

    var body: some View {
        SettingsPageShell(
            kicker: "Access",
            title: "Your plan",
            subtitle: "See what is available and manage your App Store access."
        ) {
            if let subscription = subscriptions.first {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    MetaLabel("Current access")
                    HStack(alignment: .firstTextBaseline) {
                        Text(accessTitle(subscription.access))
                            .font(.agentTitle)
                            .foregroundStyle(Color.agentText)
                        Spacer()
                        MetaLabel(subscription.access.canCreate ? "Active" : "Expired")
                            .foregroundStyle(subscription.access.canCreate ? Color.agentSuccess : Color.agentDestructive)
                    }
                    Text(accessDetail(subscription))
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                }
                .padding(.bottom, AgentSpacing.x4)

                if let trialEnd = subscription.trialEnd {
                    SettingsValueRow(title: "Access ends", value: trialEnd.formatted(date: .abbreviated, time: .omitted))
                }
                SettingsValueRow(title: "Billing", value: "Monthly", isLast: true)

                if subscription.access == .freeJourney || subscription.access == .expired {
                    Button("Start 14-day trial") {
                        Task { await appModel.startTrial(context: context) }
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                }

                Button("Restore purchases") {
                    Task { await appModel.restorePurchases(context: context) }
                }
                .buttonStyle(AgentSecondaryButtonStyle())

                Text("$8.99 a month after the trial. TestFlight access may be promotional and does not collect real money.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
            }
        }
    }

    private func accessTitle(_ access: SubscriptionAccess) -> String {
        switch access {
        case .freeJourney: "First brief free"
        case .trial: "14-day trial"
        case .paid: "Monthly"
        case .comped: "Promotional access"
        case .expired: "Access expired"
        }
    }

    private func accessDetail(_ subscription: SubscriptionState) -> String {
        switch subscription.access {
        case .freeJourney: "Your first complete brief is included."
        case .trial: "Then $8.99 a month. Cancel anytime in App Store settings."
        case .paid: "$8.99 a month through the App Store."
        case .comped: "Your current access is provided at no charge."
        case .expired: "You can still edit, finish, export, and erase existing work."
        }
    }
}

struct ExportSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context

    var body: some View {
        SettingsPageShell(
            kicker: "Your data",
            title: "Export data",
            subtitle: "Take a complete copy of your work with you."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                MetaLabel("Your export includes")
                    .padding(.bottom, AgentSpacing.x3)
                SettingsPlainRow("Briefs and post versions")
                SettingsPlainRow("Tasks, pillars, and week plans")
                SettingsPlainRow("Voice examples and profile")
                SettingsPlainRow("Readable Markdown and canonical JSON", isLast: true)
            }

            Button("Prepare export") { appModel.export(context: context) }
                .buttonStyle(AgentPrimaryButtonStyle())

            if let exportURL = appModel.exportURL {
                ShareLink(item: exportURL) {
                    Text("Save or share ZIP").frame(maxWidth: .infinity)
                }
                .buttonStyle(AgentSecondaryButtonStyle())
            }

            Text("The ZIP is created on this device. You choose where to save or share it.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
    }
}

struct EraseDataSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let onErased: () -> Void
    @State private var confirmErase = false

    var body: some View {
        SettingsPageShell(
            kicker: "Your data",
            title: "Erase all data",
            subtitle: "Permanently remove agent.cy and everything it knows about you."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("This cannot be undone")
                    .foregroundStyle(Color.agentDestructive)
                Text("Your briefs, tasks, pillars, conversations, voice profile, reminders, local files, and private iCloud records will be removed.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
            }
            .padding(AgentSpacing.x4)
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentDestructive, lineWidth: 1))

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Before you erase")
                Text("Export a copy first if you may want this work later. A non-content invite tombstone may remain so a redeemed code cannot be reused.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            }

            VStack(spacing: AgentSpacing.x3) {
                Button("Erase everything", role: .destructive) { confirmErase = true }
                    .buttonStyle(AgentPrimaryButtonStyle(
                        background: .agentDestructive,
                        foreground: .onCyAccent
                    ))

                Button("Keep my data") { dismiss() }
                    .buttonStyle(AgentSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Erase all agent.cy data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) {
                Task {
                    await appModel.eraseAll(context: context)
                    onErased()
                }
            }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("This permanently removes your content, private iCloud records, temporary audio, reminders, and locally cached access state.")
        }
    }
}

struct ResetPostsAndTasksSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        SettingsPageShell(
            kicker: "Fresh start",
            title: "Reset posts & tasks",
            subtitle: "Clear your work without rebuilding your creator setup."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                MetaLabel("This will clear")
                SettingsPlainRow("Posts, drafts, and post versions")
                SettingsPlainRow("Idea Bank entries and schedules")
                SettingsPlainRow("Open and completed tasks", isLast: true)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                MetaLabel("This will stay")
                SettingsPlainRow("Anchor pillar and branches")
                SettingsPlainRow("Creator profile and social accounts")
                SettingsPlainRow("Voice, destinations, reminders, and access", isLast: true)
            }

            VStack(spacing: AgentSpacing.x3) {
                Button("Reset posts & tasks", role: .destructive) { confirmReset = true }
                    .buttonStyle(AgentPrimaryButtonStyle(
                        background: .agentDestructive,
                        foreground: .onCyAccent
                    ))

                Button("Keep my work") { dismiss() }
                    .buttonStyle(AgentSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Reset posts and tasks?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset posts & tasks", role: .destructive) {
                if appModel.resetPostsAndTasks(context: context) {
                    dismiss()
                }
            }
            Button("Keep my work", role: .cancel) {}
        } message: {
            Text("Your posts, drafts, Idea Bank entries, schedules, and tasks will be permanently removed. Your pillars and creator setup will stay.")
        }
    }
}

private struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var lineRange: ClosedRange<Int> = 1...1
    @FocusState private var isFocused: Bool

    private var visiblePlaceholder: String {
        label.localizedCaseInsensitiveContains("note") ? "" : placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            if lineRange.upperBound > 1 {
                AgentInputHeader(title: label, isEditing: isFocused) { isFocused = false }
                TextField(visiblePlaceholder, text: $text, axis: .vertical)
                    .font(.agentBody)
                    .lineLimit(lineRange)
                    .focused($isFocused)
                    .padding(.horizontal, AgentSpacing.x4)
                    .padding(.vertical, AgentSpacing.x3)
                    .frame(minHeight: 104, alignment: .topLeading)
                    .background(Color.agentSurface)
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
            } else {
                MetaLabel(label)
                TextField(visiblePlaceholder, text: $text)
                    .font(.agentBody)
                    .agentSingleLineSubmit()
                    .padding(.horizontal, AgentSpacing.x4)
                    .padding(.vertical, AgentSpacing.x3)
                    .frame(minHeight: 52, alignment: .leading)
                    .background(Color.agentSurface)
                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
            }
        }
    }
}

private struct SettingsSelectionRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            ZStack {
                Circle().stroke(Color.agentText, lineWidth: 1.25)
                if isSelected { Circle().fill(Color.agentText).padding(5) }
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(title).font(.agentHeadline).foregroundStyle(Color.agentText)
                Text(detail).font(.agentBody).foregroundStyle(Color.agentSecondary)
            }
            Spacer()
        }
        .padding(.vertical, AgentSpacing.x4)
        .contentShape(.rect)
        .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        .overlay(alignment: .bottom) {
            if isLast { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    var isLast = false

    var body: some View {
        HStack {
            Text(title).font(.agentBody).foregroundStyle(Color.agentText)
            Spacer()
            Text(value).font(.agentBody).foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        .overlay(alignment: .bottom) {
            if isLast { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        }
    }
}

private struct SettingsPlainRow: View {
    let title: String
    var isLast = false

    init(_ title: String, isLast: Bool = false) {
        self.title = title
        self.isLast = isLast
    }

    var body: some View {
        Text(title)
            .font(.agentBody)
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.agentBorder).frame(height: 1) }
            .overlay(alignment: .bottom) {
                if isLast { Rectangle().fill(Color.agentBorder).frame(height: 1) }
            }
    }
}
