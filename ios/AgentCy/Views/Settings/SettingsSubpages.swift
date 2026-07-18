import LinkPresentation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum InstagramProfilePhotoLoader {
    enum LoadError: Error {
        case unsupportedURL
        case imageUnavailable
        case invalidImage
    }

    static func isSupportedProfileURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "instagram.com" || host == "www.instagram.com" else { return false }
        let path = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = path.first?.lowercased(), path.count == 1 else { return false }
        return !["p", "reel", "reels", "stories", "explore", "accounts", "direct"].contains(first)
    }

    @MainActor
    static func load(from url: URL) async throws -> Data {
        guard isSupportedProfileURL(url) else { throw LoadError.unsupportedURL }
        let metadataProvider = LPMetadataProvider()
        metadataProvider.timeout = 12
        let metadata = try await metadataProvider.startFetchingMetadata(for: url)
        guard let imageProvider = metadata.imageProvider else { throw LoadError.imageUnavailable }

        let imageTypeIdentifier = imageProvider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        let sourceData: Data = try await withCheckedThrowingContinuation { continuation in
            imageProvider.loadDataRepresentation(forTypeIdentifier: imageTypeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: LoadError.imageUnavailable)
                    return
                }
                continuation.resume(returning: data)
            }
        }
        guard let normalized = AvatarImageProcessor.normalizedJPEGData(from: sourceData) else {
            throw LoadError.invalidImage
        }
        return normalized
    }
}

@MainActor
private enum AvatarImageProcessor {
    static func normalizedJPEGData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 512
        let scale = max(side / image.size.width, side / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawOrigin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

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
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
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
            SettingsTextField(label: "Name", placeholder: "Your name", text: creatorNameBinding)
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
            SocialAccountEditorView(profile: profile, initialIdentity: activeIdentity)
        }
        .sheet(item: $editingAccount) { account in
            SocialAccountEditorView(profile: profile, account: account)
        }
        .onChange(of: selectedAvatarPhoto) { _, item in
            importAvatar(item)
        }
    }

    private var avatarEditor: some View {
        let photoActionTitle = activeIdentity.avatarImageData == nil ? "Choose photo" : "Change photo"
        return VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("Profile photo")
            HStack(spacing: AgentSpacing.x4) {
                CreatorAvatar(identity: activeIdentity, size: 72)
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    PhotosPicker(selection: $selectedAvatarPhoto, matching: .images) {
                        Text(photoActionTitle)
                    }
                    .buttonStyle(AgentCompactSecondaryButtonStyle())

                    if activeIdentity.avatarImageData != nil {
                        Button("Remove photo") {
                            setAvatarImageData(nil)
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
                  let normalized = AvatarImageProcessor.normalizedJPEGData(from: data) else { return }
            setAvatarImageData(normalized)
            try? context.save()
        }
    }

    private var activeWorkspace: CreatorWorkspace? {
        let workspaceID = WorkspaceScope.activeWorkspaceID(
            preferredID: appModel.activeWorkspaceID,
            workspaces: workspaces
        )
        return workspaceID.flatMap { id in workspaces.first(where: { $0.id == id && !$0.isArchived }) }
    }

    private var activeIdentity: ActiveCreatorIdentity {
        ActiveCreatorIdentity.resolve(
            profile: profile,
            workspaces: workspaces,
            preferredWorkspaceID: appModel.activeWorkspaceID
        )
    }

    private var creatorNameBinding: Binding<String> {
        Binding(
            get: { activeIdentity.name },
            set: { newValue in
                if let workspace = activeWorkspace {
                    initializeIdentityIfNeeded(workspace)
                    workspace.creatorName = newValue
                    workspace.updatedAt = Date()
                } else {
                    profile.name = newValue
                }
            }
        )
    }

    private func setAvatarImageData(_ data: Data?) {
        if let workspace = activeWorkspace {
            initializeIdentityIfNeeded(workspace)
            workspace.avatarImageData = data
            workspace.updatedAt = Date()
        } else {
            profile.avatarImageData = data
        }
    }

    private func initializeIdentityIfNeeded(_ workspace: CreatorWorkspace) {
        guard !workspace.hasCustomIdentity else { return }
        workspace.creatorName = profile.name
        workspace.avatarImageData = profile.avatarImageData
        workspace.hasCustomIdentity = true
    }

    private var activeAccounts: [CreatorSocialAccount] {
        socialAccounts.filter {
            $0.profileID == profile.id &&
                !$0.isArchived &&
                WorkspaceScope.includes(
                    $0.workspaceID,
                    activeWorkspaceID: appModel.activeWorkspaceID,
                    workspaces: workspaces
                )
        }
    }

    private func destinationName(for account: CreatorSocialAccount) -> String {
        destinations.first(where: { $0.id == account.destinationID })?.name ?? "Platform"
    }
}

struct AccountSwitcherSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Bindable var profile: CreatorProfile
    @State private var pendingDeletion: AccountDeletionTarget?
    @State private var deletionErrorMessage: String?

    private var activeWorkspaces: [CreatorWorkspace] {
        workspaces.filter { $0.profileID == profile.id && !$0.isArchived }
    }

    var body: some View {
        SettingsPageShell(
            kicker: "Accounts",
            title: "Switch account",
            subtitle: "Each account keeps its own posts, pillars, tasks, ideas, and weekly focus."
        ) {
            if activeWorkspaces.isEmpty {
                Text("Add an account first, then return here to switch its workspace.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activeWorkspaces.enumerated()), id: \.element.id) { index, workspace in
                        VStack(spacing: 0) {
                            HStack(spacing: AgentSpacing.x2) {
                                Button {
                                    appModel.switchWorkspace(to: workspace.id, context: context)
                                } label: {
                                    HStack(spacing: AgentSpacing.x3) {
                                        CreatorAvatar(
                                            identity: ActiveCreatorIdentity.resolve(
                                                profile: profile,
                                                workspaces: [workspace],
                                                preferredWorkspaceID: workspace.id
                                            ),
                                            size: 48
                                        )
                                        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                            Text(workspace.name)
                                                .font(.agentBody.weight(.semibold))
                                            let creatorName = ActiveCreatorIdentity.resolve(
                                                profile: profile,
                                                workspaces: [workspace],
                                                preferredWorkspaceID: workspace.id
                                            ).name
                                            if !creatorName.isEmpty {
                                                Text(creatorName)
                                                    .font(.agentSubtext)
                                                    .foregroundStyle(Color.agentSecondary)
                                            }
                                            if let account = socialAccount(for: workspace) {
                                                MetaLabel(destinationName(for: account))
                                            } else {
                                                MetaLabel("CONTENT ACCOUNT")
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if appModel.activeWorkspaceID == workspace.id {
                                            Text("Active")
                                                .font(.agentMono)
                                                .foregroundStyle(Color.cyAccent)
                                        }
                                        Image(systemName: appModel.activeWorkspaceID == workspace.id ? "checkmark" : "circle")
                                            .font(.system(size: 13, weight: .semibold))
                                            .frame(width: 24, height: 24)
                                    }
                                    .foregroundStyle(Color.agentText)
                                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Switch to \(workspace.name)")
                                .accessibilityAddTraits(appModel.activeWorkspaceID == workspace.id ? .isSelected : [])

                                if activeWorkspaces.count > 1 {
                                    Menu {
                                        Button("Delete account", systemImage: "trash", role: .destructive) {
                                            pendingDeletion = AccountDeletionTarget(
                                                id: workspace.id,
                                                name: workspace.name
                                            )
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.agentText)
                                            .frame(width: 44, height: 44)
                                            .contentShape(.circle)
                                    }
                                    .accessibilityLabel("Account options for \(workspace.name)")
                                }
                            }
                            .padding(.vertical, AgentSpacing.x2)

                            if index < activeWorkspaces.count - 1 {
                                Rectangle()
                                    .fill(Color.agentBorder)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }

            Text("Switching changes the complete creator workspace. Content from your other accounts stays saved and returns when you switch back.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "this account")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete account and content", role: .destructive) {
                deletePendingAccount()
            }
            Button("Keep account", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently deletes its posts, pillars, ideas, tasks, weekly focus, and Cy conversations. This cannot be undone.")
        }
        .alert(
            "Account couldn’t be deleted",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("Close", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "Your work is unchanged.")
        }
    }

    private func socialAccount(for workspace: CreatorWorkspace) -> CreatorSocialAccount? {
        if let accountID = workspace.primarySocialAccountID,
           let account = socialAccounts.first(where: { $0.id == accountID && !$0.isArchived }) {
            return account
        }
        return socialAccounts.first(where: { $0.workspaceID == workspace.id && !$0.isArchived })
    }

    private func destinationName(for account: CreatorSocialAccount) -> String {
        destinations.first(where: { $0.id == account.destinationID })?.name ?? "Platform"
    }

    private func deletePendingAccount() {
        guard let target = pendingDeletion,
              activeWorkspaces.count > 1,
              let fallbackWorkspaceID = activeWorkspaces.first(where: { $0.id != target.id })?.id else {
            pendingDeletion = nil
            return
        }
        let wasActive = appModel.activeWorkspaceID == target.id
        do {
            try WorkspaceDeletionService.delete(workspaceID: target.id, context: context)
            pendingDeletion = nil
            if wasActive {
                appModel.switchWorkspace(to: fallbackWorkspaceID, context: context)
            }
        } catch {
            pendingDeletion = nil
            deletionErrorMessage = "That account could not be deleted. Your work is unchanged."
        }
    }

}

private struct AccountDeletionTarget: Identifiable {
    let id: UUID
    let name: String
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
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PublishingDestination.sortOrder) private var destinations: [PublishingDestination]
    @Query(sort: \CreatorSocialAccount.sortOrder) private var socialAccounts: [CreatorSocialAccount]
    @Query private var outputs: [PlatformOutput]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    let profile: CreatorProfile
    let account: CreatorSocialAccount?
    @State private var creatorName: String
    @State private var avatarImageData: Data?
    @State private var selectedAvatarPhoto: PhotosPickerItem?
    @State private var didLoadWorkspaceIdentity = false
    @State private var isLoadingInstagramPhoto = false
    @State private var instagramPhotoMessage: String?
    @State private var lastLoadedInstagramURLString: String?
    @State private var label: String
    @State private var profileURLString: String
    @State private var destinationID: UUID
    @State private var isPrimary: Bool
    @State private var confirmRemove = false
    @State private var lastSuggestedURL: String?

    init(
        profile: CreatorProfile,
        account: CreatorSocialAccount? = nil,
        initialIdentity: ActiveCreatorIdentity? = nil
    ) {
        self.profile = profile
        self.account = account
        let identity = initialIdentity ?? ActiveCreatorIdentity(
            name: profile.name,
            avatarImageData: profile.avatarImageData
        )
        _creatorName = State(initialValue: identity.name)
        _avatarImageData = State(initialValue: identity.avatarImageData)
        _selectedAvatarPhoto = State(initialValue: nil)
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
                accountIdentityEditor
                SettingsTextField(label: "Creator name", placeholder: "Your name", text: $creatorName)
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
            loadWorkspaceIdentityIfNeeded()
            if !activeDestinations.contains(where: { $0.id == destinationID }),
               let first = activeDestinations.first {
                destinationID = first.id
            }
            if account == nil { isPrimary = true }
            updateSuggestedURL()
        }
        .onChange(of: label) { _, _ in updateSuggestedURL() }
        .onChange(of: destinationID) { _, newDestinationID in
            if account == nil || account?.destinationID != newDestinationID {
                isPrimary = account == nil || accounts(for: newDestinationID).isEmpty
            }
            updateSuggestedURL()
        }
        .onChange(of: selectedAvatarPhoto) { _, item in
            importAvatar(item)
        }
        .task(id: instagramPhotoLookupKey) {
            guard avatarImageData == nil,
                  let url = instagramProfileURL,
                  lastLoadedInstagramURLString != url.absoluteString else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await loadInstagramPhoto(from: url)
        }
        .confirmationDialog("Remove this account?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove account", role: .destructive) { remove() }
            Button("Keep account", role: .cancel) {}
        } message: {
            Text("Existing posts stay intact. This account will no longer be available for new posts.")
        }
    }

    private var activeDestinations: [PublishingDestination] {
        destinations.filter { !$0.isArchived }
    }

    private var accountIdentityEditor: some View {
        let photoActionTitle = avatarImageData == nil ? "Choose photo" : "Change photo"
        return VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            MetaLabel("Profile photo")
            HStack(spacing: AgentSpacing.x4) {
                CreatorAvatar(
                    identity: ActiveCreatorIdentity(name: creatorName, avatarImageData: avatarImageData),
                    size: 72
                )
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    PhotosPicker(selection: $selectedAvatarPhoto, matching: .images) {
                        Text(photoActionTitle)
                    }
                    .buttonStyle(AgentCompactSecondaryButtonStyle())

                    if avatarImageData != nil {
                        Button("Remove photo") { avatarImageData = nil }
                            .font(.agentSubtext.weight(.medium))
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
            }

            if let url = instagramProfileURL {
                Button {
                    Task { await loadInstagramPhoto(from: url, force: true) }
                } label: {
                    HStack(spacing: AgentSpacing.x2) {
                        if isLoadingInstagramPhoto {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoadingInstagramPhoto ? "Checking Instagram…" : "Use Instagram photo")
                    }
                }
                .buttonStyle(AgentCompactSecondaryButtonStyle())
                .disabled(isLoadingInstagramPhoto)

                Text("Your Instagram profile must be public for agent.cy to find its photo.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let instagramPhotoMessage {
                Text(instagramPhotoMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var instagramPhotoLookupKey: String {
        instagramProfileURL?.absoluteString ?? ""
    }

    private var instagramProfileURL: URL? {
        guard activeDestinations.first(where: { $0.id == destinationID })?.builtInKind == .instagram,
              let urlString = resolvedProfileURLString,
              let url = URL(string: urlString),
              InstagramProfilePhotoLoader.isSupportedProfileURL(url) else { return nil }
        return url
    }

    private var validationMessage: String? {
        if creatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the name Cy should use for this account." }
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

    private func loadWorkspaceIdentityIfNeeded() {
        guard !didLoadWorkspaceIdentity else { return }
        defer { didLoadWorkspaceIdentity = true }
        guard let workspaceID = account?.workspaceID,
              let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        let identity = ActiveCreatorIdentity.resolve(
            profile: profile,
            workspaces: [workspace],
            preferredWorkspaceID: workspace.id
        )
        creatorName = identity.name
        avatarImageData = identity.avatarImageData
    }

    private func importAvatar(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            defer { selectedAvatarPhoto = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let normalized = AvatarImageProcessor.normalizedJPEGData(from: data) else { return }
            avatarImageData = normalized
        }
    }

    @MainActor
    private func loadInstagramPhoto(from url: URL, force: Bool = false) async {
        guard force || lastLoadedInstagramURLString != url.absoluteString else { return }
        isLoadingInstagramPhoto = true
        instagramPhotoMessage = nil
        defer { isLoadingInstagramPhoto = false }
        do {
            avatarImageData = try await InstagramProfilePhotoLoader.load(from: url)
            lastLoadedInstagramURLString = url.absoluteString
            instagramPhotoMessage = "Instagram photo ready. Review it before saving."
        } catch {
            lastLoadedInstagramURLString = url.absoluteString
            instagramPhotoMessage = "We couldn’t find a public profile photo. Make sure the account is public, or choose a photo instead."
        }
    }

    private func accounts(for destinationID: UUID, excluding excludedID: UUID? = nil) -> [CreatorSocialAccount] {
        socialAccounts.filter {
            $0.profileID == profile.id &&
                $0.destinationID == destinationID &&
                !$0.isArchived &&
                $0.id != excludedID &&
                (account == nil || $0.workspaceID == account?.workspaceID)
        }
    }

    private func save() {
        guard validationMessage == nil,
              let normalizedURL = resolvedProfileURLString else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCreatorName = creatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let peers = accounts(for: destinationID, excluding: account?.id)
        let shouldBePrimary = account == nil || isPrimary || !peers.contains(where: \.isPrimary)
        let savedAccount: CreatorSocialAccount

        if let account {
            let oldDestinationID = account.destinationID
            account.destinationID = destinationID
            account.label = cleanLabel
            account.profileURLString = normalizedURL
            account.isPrimary = shouldBePrimary
            account.updatedAt = Date()
            savedAccount = account

            if let workspace = workspaces.first(where: { $0.id == account.workspaceID }) {
                workspace.name = cleanLabel
                workspace.creatorName = cleanCreatorName
                workspace.avatarImageData = avatarImageData
                workspace.hasCustomIdentity = true
                workspace.primarySocialAccountID = account.id
                workspace.updatedAt = Date()
            }

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
            let workspace = CreatorWorkspace(
                profileID: profile.id,
                name: cleanLabel,
                creatorName: cleanCreatorName,
                avatarImageData: avatarImageData,
                hasCustomIdentity: true,
                primarySocialAccountID: newAccount.id,
                sortOrder: (workspaces.map(\.sortOrder).max() ?? -1) + 1
            )
            newAccount.workspaceID = workspace.id
            context.insert(workspace)
            context.insert(newAccount)
            savedAccount = newAccount
        }

        if savedAccount.isPrimary {
            for peer in peers { peer.isPrimary = false; peer.updatedAt = Date() }
        }
        try? context.save()
        if let workspaceID = savedAccount.workspaceID {
            appModel.switchWorkspace(to: workspaceID, context: context)
        }
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

struct CyQuickPromptsSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var profile: CreatorProfile
    @State private var prompts: [String]

    init(profile: CreatorProfile) {
        self.profile = profile
        _prompts = State(initialValue: profile.customCyQuickPrompts ?? CreatorProfile.defaultCyQuickPrompts)
    }

    var body: some View {
        SettingsPageShell(
            kicker: "Cy",
            title: "Quick prompts",
            subtitle: "Choose two shortcuts for starting a new conversation."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                SectionRuleHeader(title: "Your prompts", trailing: "2")

                ForEach(prompts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        SettingsTextField(
                            label: "Prompt \(index + 1)",
                            placeholder: "",
                            text: promptBinding(at: index)
                        )
                        Text("\(prompts[index].count)/\(CreatorProfile.maxCyQuickPromptLength)")
                            .font(.agentMono)
                            .foregroundStyle(Color.agentSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                Text("These replace the two suggestions shown before you send the first message in a new Cy conversation.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AgentSpacing.x3) {
                Button("Save prompts", action: savePrompts)
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .disabled(!canSave)

                Button("Restore defaults", action: restoreDefaults)
                    .buttonStyle(AgentSecondaryButtonStyle())
            }
        }
    }

    private var normalizedPrompts: [String] {
        prompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var canSave: Bool {
        normalizedPrompts.count == 2 && normalizedPrompts.allSatisfy { !$0.isEmpty }
    }

    private func promptBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { prompts[index] },
            set: { prompts[index] = String($0.prefix(CreatorProfile.maxCyQuickPromptLength)) }
        )
    }

    private func savePrompts() {
        guard canSave else { return }
        profile.setCustomCyQuickPrompts(normalizedPrompts)
        do {
            try context.save()
            appModel.notice = .info("Quick prompts updated.")
        } catch {
            appModel.notice = .error("Those quick prompts could not be saved.")
        }
    }

    private func restoreDefaults() {
        profile.restoreDefaultCyQuickPrompts()
        prompts = CreatorProfile.defaultCyQuickPrompts
        do {
            try context.save()
            appModel.notice = .info("Default quick prompts restored.")
        } catch {
            appModel.notice = .error("The default prompts could not be restored.")
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var profile: CreatorProfile
    @Query(sort: \Pillar.createdAt) private var allPillars: [Pillar]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]

    var body: some View {
        SettingsPageShell(
            kicker: "Display",
            title: "Appearance",
            subtitle: "Choose your display mode and pillar color palette."
        ) {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    SectionRuleHeader(title: "Mode")

                    VStack(spacing: 0) {
                        ForEach(AppearancePreference.allCases) { appearance in
                            Button {
                                profile.appearance = appearance
                                appModel.appearancePreference = appearance
                                AgentAppearanceController.apply(appearance)
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
                                .frame(minHeight: 64)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    SectionRuleHeader(title: "Pillar colors")

                    VStack(spacing: 0) {
                        ForEach(CreatorVibePalette.standardPalettes) { palette in
                            paletteRow(palette)
                        }
                    }

                    MetaLabel("Signature")
                        .padding(.top, AgentSpacing.x4)

                    VStack(spacing: 0) {
                        ForEach(CreatorVibePalette.signaturePalettes) { palette in
                            paletteRow(palette)
                        }
                    }

                    Text("Choosing a palette recolors up to five existing pillars for this account. If you have more than five, their current colors stay unchanged. Custom colors remain available.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AgentSpacing.x2)
                }
            }
        }
    }

    private func paletteRow(_ palette: CreatorVibePalette) -> some View {
        Button {
            selectPalette(palette)
        } label: {
            HStack(spacing: AgentSpacing.x3) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(palette.title)
                        .font(.agentBody.weight(.semibold))
                    Text(palette.detail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                Spacer(minLength: AgentSpacing.x2)

                HStack(spacing: 4) {
                    ForEach(palette.pillarColorHexes, id: \.self) { hex in
                        Circle()
                            .fill(Color(agentHex: hex))
                            .frame(width: 15, height: 15)
                            .overlay {
                                Circle().stroke(Color.agentBorder, lineWidth: 0.75)
                            }
                    }
                }

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(profile.vibePalette == palette ? 1 : 0)
                    .frame(width: 16)
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(profile.vibePalette == palette ? .isSelected : [])
    }

    private var activeWorkspacePillars: [Pillar] {
        allPillars.filter {
            !$0.isArchived && WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private func selectPalette(_ palette: CreatorVibePalette) {
        profile.vibePalette = palette
        PillarPaletteAssignment.apply(palette, to: activeWorkspacePillars)
        do {
            try context.save()
            WidgetSnapshotService.refresh(context: context)
        } catch {
            appModel.notice = .error("Those pillar colors could not be updated.")
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

struct NewPostSettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: CreatorProfile

    var body: some View {
        SettingsPageShell(
            kicker: "Publishing",
            title: "New post",
            subtitle: "Choose the optional sections you want while planning a post."
        ) {
            SectionRuleHeader(title: "Optional sections")

            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                postSectionToggle(
                    title: "Hook",
                    detail: "Keep a dedicated opening line in the post editor.",
                    isOn: $profile.showsHookInPostEditor
                )
                postSectionToggle(
                    title: "Brand deals",
                    detail: "Track partners, compensation, terms, and deal files.",
                    isOn: $profile.showsBrandDealsInPostEditor
                )
                postSectionToggle(
                    title: "Mood boards",
                    detail: "Add visual references and inspiration images.",
                    isOn: $profile.showsMoodBoardsInPostEditor
                )
            }

            Text("Turning a section off keeps new posts simpler. Existing information is never removed.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { try? context.save() }
    }

    private func postSectionToggle(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(title)
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                Text(detail)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AgentSpacing.x4)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(Color.actionAccent)
                .fixedSize()
        }
        .frame(minHeight: 52)
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
            subtitle: "Add scheduled posts and tasks to a calendar on this iPhone."
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
                SectionRuleHeader(title: "Sync to")
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
                SectionRuleHeader(title: "Include")
                Toggle("Scheduled posts", isOn: $syncScheduledPosts)
                    .font(.agentBody)
                    .tint(.actionAccent)
                    .frame(minHeight: 48)
                Toggle("Tasks", isOn: $syncTasks)
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

            Text("Changes made in Calendar do not update agent.cy.")
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
            subtitle: "Keep useful commitments close without adding pressure."
        ) {
            authorizationSection

            notificationGroup("Planning") {
                reminderRow(
                    title: "Daily overview",
                    detail: "Only on active focus days. Mondays use the weekly plan instead.",
                    isOn: $settings.dailyEnabled
                )
                if settings.dailyEnabled {
                    timeRow("Morning time", selection: timeBinding(hour: \.dailyHour, minute: \.dailyMinute))
                }
                reminderRow(
                    title: "Monday planning",
                    detail: "Your weekly focus, saved ideas, and what is already planned.",
                    isOn: $settings.weeklyEnabled
                )
                if settings.weeklyEnabled {
                    timeRow("Monday time", selection: timeBinding(hour: \.weeklyHour, minute: \.weeklyMinute))
                }
            }

            notificationGroup("Commitments") {
                reminderRow(title: "Scheduled posts", detail: "30 minutes before a timed post.", isOn: $settings.postRemindersEnabled)
                reminderRow(title: "Timed tasks", detail: "15 minutes before tasks with a saved time.", isOn: $settings.taskRemindersEnabled)
                reminderRow(title: "Draft preparation", detail: "The evening before a planned post is still a draft.", isOn: $settings.draftPrepRemindersEnabled)
                if settings.draftPrepRemindersEnabled {
                    timeRow("Evening time", selection: timeBinding(hour: \.draftPrepHour, minute: \.draftPrepMinute))
                }
                reminderRow(title: "Missed posts", detail: "One calm check-in if a scheduled post is still open.", isOn: $settings.missedPostRemindersEnabled)
                if settings.missedPostRemindersEnabled {
                    timeRow("Untimed post check-in", selection: timeBinding(hour: \.dateOnlyDeadlineHour, minute: \.dateOnlyDeadlineMinute))
                }
                reminderRow(title: "Trial or access", detail: "One reminder 24 hours before access changes.", isOn: $settings.accessRemindersEnabled)
            }

            notificationGroup("Quiet hours") {
                reminderRow(title: "Use quiet hours", detail: "Flexible nudges wait. Exact post, task, and focus reminders still fire.", isOn: $settings.quietHoursEnabled)
                if settings.quietHoursEnabled {
                    timeRow("Start", selection: timeBinding(hour: \.quietHoursStartHour, minute: \.quietHoursStartMinute))
                    timeRow("End", selection: timeBinding(hour: \.quietHoursEndHour, minute: \.quietHoursEndMinute))
                }
            }

            notificationGroup("Privacy") {
                reminderRow(
                    title: "Show titles",
                    detail: "Include post, task, and idea titles in notification previews.",
                    isOn: $settings.showNotificationTitles
                )
            }
        }
        .task { await appModel.refreshReminderSchedule(context: context) }
        .onChange(of: settingsFingerprint) { _, _ in apply() }
    }

    private var authorizationSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Status")
            HStack(alignment: .center, spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(authorizationTitle)
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                    Text(authorizationDetail)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if appModel.notificationAuthorization.canSchedule {
                    Toggle("Notifications", isOn: $settings.masterEnabled)
                        .labelsHidden()
                        .tint(.actionAccent)
                        .fixedSize()
                }
            }

            if appModel.notificationAuthorization == .notDetermined {
                Button("Turn on notifications") {
                    settings.masterEnabled = true
                    settings.dailyEnabled = true
                    settings.weeklyEnabled = true
                    Task { await appModel.applyReminderSettings(settings, context: context, requestPermission: true) }
                }
                .buttonStyle(AgentPrimaryButtonStyle())
            } else if appModel.notificationAuthorization == .denied {
                Button("Open iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(AgentSecondaryButtonStyle())
            }
        }
    }

    private func notificationGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            SectionRuleHeader(title: title)
            content()
        }
        .disabled(!settings.masterEnabled)
        .opacity(settings.masterEnabled ? 1 : 0.5)
    }

    private func reminderRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(title)
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                Text(detail)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AgentSpacing.x3)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(.actionAccent)
                .fixedSize()
        }
        .padding(.vertical, AgentSpacing.x1)
        .contentShape(.rect)
    }

    private func timeRow(_ title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: AgentSpacing.x4) {
            Text(title)
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
            Spacer(minLength: AgentSpacing.x3)
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
        }
        .frame(minHeight: 40)
    }

    private func timeBinding(
        hour: ReferenceWritableKeyPath<ReminderSettings, Int>,
        minute: ReferenceWritableKeyPath<ReminderSettings, Int>
    ) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings[keyPath: hour],
                    minute: settings[keyPath: minute],
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                settings[keyPath: hour] = Calendar.current.component(.hour, from: date)
                settings[keyPath: minute] = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private var authorizationTitle: String {
        switch appModel.notificationAuthorization {
        case .authorized, .provisional, .ephemeral: settings.masterEnabled ? "Notifications are on" : "Notifications are paused"
        case .denied: "Notifications are blocked"
        case .notDetermined: "Notifications are off"
        }
    }

    private var authorizationDetail: String {
        switch appModel.notificationAuthorization {
        case .authorized, .provisional, .ephemeral: "agent.cy will schedule only the categories you choose."
        case .denied: "Allow notifications in iPhone Settings to use reminders."
        case .notDetermined: "Daily and Monday planning are ready when you are."
        }
    }

    private var settingsFingerprint: String {
        [
            settings.masterEnabled ? 1 : 0,
            settings.dailyEnabled ? 1 : 0, settings.dailyHour, settings.dailyMinute,
            settings.weeklyEnabled ? 1 : 0, settings.weeklyHour, settings.weeklyMinute,
            settings.postRemindersEnabled ? 1 : 0,
            settings.taskRemindersEnabled ? 1 : 0,
            settings.draftPrepRemindersEnabled ? 1 : 0, settings.draftPrepHour, settings.draftPrepMinute,
            settings.missedPostRemindersEnabled ? 1 : 0, settings.dateOnlyDeadlineHour, settings.dateOnlyDeadlineMinute,
            settings.accessRemindersEnabled ? 1 : 0,
            settings.quietHoursEnabled ? 1 : 0, settings.quietHoursStartHour, settings.quietHoursStartMinute,
            settings.quietHoursEndHour, settings.quietHoursEndMinute,
            settings.showNotificationTitles ? 1 : 0,
        ].map(String.init).joined(separator: "|")
    }

    private func apply() {
        Task { await appModel.applyReminderSettings(settings, context: context) }
    }

}

struct AccessSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var subscriptions: [SubscriptionState]
    @State private var isRotating = false

    var body: some View {
        SettingsPageShell(
            kicker: "Access",
            title: "Your plan",
            subtitle: "Plan and create with Cy."
        ) {
            if let subscription = subscriptions.first {
                let effectiveAccess = AccessPolicy.effectiveAccess(for: subscription)
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionRuleHeader(title: "Plan details")
                        currentAccessCard(effectiveAccess, subscription: subscription)
                            .padding(.top, AgentSpacing.x4)
                        proAccessCard(effectiveAccess)
                            .padding(.top, AgentSpacing.x4)
                    }

                    Button("Restore purchases") {
                        Task { await appModel.restorePurchases(context: context) }
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())

                    Text("$8.99 a month after the trial. TestFlight access may be promotional and does not collect real money.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { isRotating = true }
    }

    private func currentAccessCard(
        _ access: SubscriptionAccess,
        subscription: SubscriptionState
    ) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x3) {
                MetaLabel("Current access")
                Spacer()
                Text(planStatus(access))
                    .font(.agentMono)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.horizontal, AgentSpacing.x3)
                    .frame(minHeight: 28)
                    .background(Color.agentCanvas, in: .capsule)
            }

            Text(accessTitle(access))
                .font(.agentHeadline)
                .foregroundStyle(Color.agentText)

            Text(accessDetail(access))
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let trialEnd = subscription.trialEnd {
                HStack {
                    Text(access == .trial ? "Trial ends" : "Access ends")
                    Spacer()
                    Text(trialEnd.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.agentSubtext.weight(.medium))
                .foregroundStyle(Color.agentText)
                .padding(.top, AgentSpacing.x1)
            }
        }
        .padding(AgentSpacing.x4)
        .background(Color.agentSurface, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    private func proAccessCard(_ access: SubscriptionAccess) -> some View {
        let isActive = proIsActive(access)
        return VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            HStack(alignment: .center, spacing: AgentSpacing.x3) {
                ZStack {
                    Circle()
                        .fill(Color.cyAccent)
                        .shadow(color: Color.cyAccent.opacity(0.3), radius: 14, y: 6)
                    CyAsterisk(color: .onCyAccent, size: 20, strokeWidth: 1.6)
                        .rotationEffect(.degrees(reduceMotion ? 0 : (isRotating ? 360 : 0)))
                        .animation(
                            reduceMotion ? nil : .linear(duration: 8).repeatForever(autoreverses: false),
                            value: isRotating
                        )
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    MetaLabel("Pro access")
                        .foregroundStyle(Color.cyAccent)
                    Text("Create your whole week with Cy.")
                        .font(.agentHeadline)
                        .foregroundStyle(Color.agentText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(isActive ? "Active" : "$8.99/mo")
                    .font(.agentMono)
                    .foregroundStyle(Color.onCyAccent)
                    .padding(.horizontal, AgentSpacing.x3)
                    .frame(minHeight: 30)
                    .background(Color.cyAccent, in: .capsule)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                planBenefit("Create new ideas, posts, tasks, and schedules")
                planBenefit("Plan with Cy using your goals, pillars, and saved work")
                planBenefit("Shape hooks, captions, platform posts, and revisions")
            }

            if !isActive {
                Button("Start 14-day trial") {
                    Task { await appModel.startTrial(context: context) }
                }
                .buttonStyle(AgentCyPrimaryButtonStyle())
            } else {
                Text("Included with your current plan.")
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.cyAccent)
            }
        }
        .padding(AgentSpacing.x4)
        .background(
            LinearGradient(
                colors: [Color.cyAccent.opacity(0.12), Color.cyAccent.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.cyAccent.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: Color.cyAccent.opacity(0.13), radius: 20, y: 8)
    }

    private func planBenefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            CyAsterisk(color: .cyAccent, size: 12, strokeWidth: 1.2)
                .frame(width: 16, height: 19)
            Text(text)
                .font(.agentSubtext.weight(.medium))
                .foregroundStyle(Color.agentText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }

    private func planStatus(_ access: SubscriptionAccess) -> String {
        switch access {
        case .freeJourney: "Free"
        case .trial: "Trial"
        case .paid, .comped: "Pro"
        case .expired: "Expired"
        }
    }

    private func proIsActive(_ access: SubscriptionAccess) -> Bool {
        access == .trial || access == .paid || access == .comped
    }

    private func accessTitle(_ access: SubscriptionAccess) -> String {
        switch access {
        case .freeJourney: "8 Cy credits"
        case .trial: "14-day trial"
        case .paid: "Monthly"
        case .comped: "Promotional access"
        case .expired: "Access expired"
        }
    }

    private func accessDetail(_ access: SubscriptionAccess) -> String {
        switch access {
        case .freeJourney: "Use your included credits for Cy ideas, planning, and revisions."
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
                SettingsPlainRow("Posts, platform details, and attachments")
                SettingsPlainRow("Tasks, pillars, and plans")
                SettingsPlainRow("Profile, conversations, and settings")
                SettingsPlainRow("Readable Markdown and structured JSON", isLast: true)
            }

            Button("Create export") { appModel.export(context: context) }
                .buttonStyle(AgentPrimaryButtonStyle())

            if let exportURL = appModel.exportURL {
                ShareLink(item: exportURL) {
                    Text("Save or share export").frame(maxWidth: .infinity)
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
                Text("Your posts, tasks, pillars, conversations, reminders, local files, and private iCloud records will be removed.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentText)
            }
            .padding(AgentSpacing.x4)
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentDestructive, lineWidth: 1))

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Before you erase")
                Text("Export a copy first if you may want this work later. If you used an invite code, agent.cy keeps only a private record that it was redeemed so it cannot be used again.")
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
                    if await appModel.eraseAll(context: context) {
                        onErased()
                    }
                }
            }
            Button("Keep my data", role: .cancel) {}
        } message: {
            Text("This permanently removes your content, private iCloud records, reminders, and locally cached access state.")
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
                SettingsPlainRow("Posts and drafts")
                SettingsPlainRow("Idea Bank entries and schedules")
                SettingsPlainRow("Open and completed tasks", isLast: true)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                MetaLabel("This will stay")
                SettingsPlainRow("Anchor pillar and branches")
                SettingsPlainRow("Creator profile and social accounts")
                SettingsPlainRow("Destinations, reminders, and access", isLast: true)
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
    var showsTopRule = true

    var body: some View {
        HStack {
            Text(title).font(.agentBody).foregroundStyle(Color.agentText)
            Spacer()
            Text(value).font(.agentBody).foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            if showsTopRule { Rectangle().fill(Color.agentBorder).frame(height: 1) }
        }
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
