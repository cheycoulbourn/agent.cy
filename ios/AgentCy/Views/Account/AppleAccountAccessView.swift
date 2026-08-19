import AuthenticationServices
import CloudKit
import CryptoKit
import Network
import Observation
import Security
import SwiftData
import SwiftUI
import UIKit

struct AccountAccessGate: View {
    @Environment(AppModel.self) private var appModel
    @State private var showsInvitation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: "Your agent.cy",
                    title: "Pick up where you left off.",
                    subtitle: "Sign in to connect this device to your existing workspace."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    CyAsterisk(color: .cyAccent, size: 34, strokeWidth: 2.2)
                        .frame(width: 52, height: 52)
                        .background(Color.cyAccent.opacity(0.1), in: .circle)

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        Text("Your planning stays yours")
                            .font(.agentHeadline)
                            .foregroundStyle(Color.agentText)
                        Text("Apple confirms your account. agent.cy keeps a separate secure connection for this device and restores your synced workspace.")
                            .font(.agentBody)
                            .foregroundStyle(Color.agentSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AgentAppleAccountButton()
                }
                .padding(AgentSpacing.x5)
                .background(Color.agentSurface, in: .rect(cornerRadius: 24))
                .agentSurfaceChrome(cornerRadius: 24)

                if let status = AccountAccessStatus.resolve(
                    isAuthorizing: appModel.isAuthorizingAccount,
                    notice: appModel.notice
                ) {
                    AccountAccessStatusView(status: status)
                }

                Button("I have an invitation code") {
                    showsInvitation = true
                }
                .buttonStyle(AgentSecondaryButtonStyle())

                Text("New here? Use the invitation code you received. You can link Apple after setup without moving or deleting anything.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .frame(maxWidth: 560)
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.vertical, AgentSpacing.x12)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsInvitation) {
            NavigationStack {
                InstallationInviteGate()
            }
        }
    }
}

enum AccountAccessStatus: Equatable {
    case progress(String)
    case info(String)
    case error(String)

    static func resolve(isAuthorizing: Bool, notice: AppNotice?) -> Self? {
        if isAuthorizing {
            return .progress("Connecting your workspace…")
        }
        switch notice {
        case .info(let message):
            return .info(message)
        case .error(let message):
            return .error(message)
        case nil:
            return nil
        }
    }

    var message: String {
        switch self {
        case .progress(let message), .info(let message), .error(let message):
            return message
        }
    }

    var showsProgress: Bool {
        if case .progress = self { return true }
        return false
    }

    var isUrgent: Bool {
        if case .error = self { return true }
        return false
    }
}

private struct AccountAccessStatusView: View {
    let status: AccountAccessStatus

    var body: some View {
        HStack(spacing: AgentSpacing.x3) {
            if status.showsProgress {
                ProgressView()
            }
            Text(status.message)
                .font(.agentSubtext)
                .foregroundStyle(status.isUrgent ? Color.agentDestructive : Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.message)
        .accessibilityIdentifier("account-access-status")
        .onAppear { announce(status) }
        .onChange(of: status) { _, status in
            announce(status)
        }
    }

    private func announce(_ status: AccountAccessStatus) {
        let message = NSMutableAttributedString(string: status.message)
        message.addAttribute(
            .accessibilitySpeechAnnouncementPriority,
            value: status.isUrgent ? UIAccessibilityPriority.high : UIAccessibilityPriority.low,
            range: NSRange(location: 0, length: message.length)
        )
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

enum AccountRestoreSyncState: Equatable {
    case checking
    case available
    case offline
    case cloudUnavailable
    case localOnlyFallback
}

enum AccountRestoreConnectivityState: Equatable {
    case checking
    case online
    case offline
}

@MainActor
@Observable
final class AccountRestoreConnectivityMonitor {
    private(set) var status: AccountRestoreConnectivityState = .checking

    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let queue = DispatchQueue(
        label: "com.agentcy.app.account-restore-connectivity",
        qos: .utility
    )

    func start() {
        guard monitor == nil else { return }
        status = .checking
        generation = UUID()
        let generation = generation
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status: AccountRestoreConnectivityState = path.status == .satisfied
                ? .online
                : .offline
            Task { @MainActor [weak self] in
                self?.receive(status, generation: generation)
            }
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        generation = UUID()
        monitor?.cancel()
        monitor = nil
    }

    private func receive(
        _ status: AccountRestoreConnectivityState,
        generation: UUID
    ) {
        guard generation == self.generation else { return }
        self.status = status
    }
}

enum AccountRestoreSyncPolicy {
    static func effectiveState(
        cloudState: AccountRestoreSyncState,
        connectivity: AccountRestoreConnectivityState
    ) -> AccountRestoreSyncState {
        connectivity == .offline ? .offline : cloudState
    }

    static func resolve(
        localOnlyFallback: Bool,
        accountStatus: CKAccountStatus?,
        error: Error?
    ) -> AccountRestoreSyncState {
        if localOnlyFallback {
            return .localOnlyFallback
        }
        if let error, isOffline(error) {
            return .offline
        }
        guard error == nil, let accountStatus else {
            return .cloudUnavailable
        }
        switch accountStatus {
        case .available:
            return .available
        case .couldNotDetermine, .restricted, .noAccount, .temporarilyUnavailable:
            return .cloudUnavailable
        @unknown default:
            return .cloudUnavailable
        }
    }

    static func check(localOnlyFallback: Bool) async -> AccountRestoreSyncState {
        if localOnlyFallback {
            return .localOnlyFallback
        }
        do {
            let accountStatus = try await CKContainer(
                identifier: "iCloud.com.agentcy.app"
            ).accountStatus()
            return resolve(
                localOnlyFallback: false,
                accountStatus: accountStatus,
                error: nil
            )
        } catch {
            return resolve(
                localOnlyFallback: false,
                accountStatus: nil,
                error: error
            )
        }
    }

    private static func isOffline(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .notConnectedToInternet,
                .networkConnectionLost,
                .dataNotAllowed,
                .internationalRoamingOff
            ].contains(urlError.code)
        }
        let error = error as NSError
        guard error.domain == CKErrorDomain,
              let code = CKError.Code(rawValue: error.code) else {
            return false
        }
        return code == .networkUnavailable || code == .networkFailure
    }
}

#if DEBUG
enum AccountRestoreRuntimeFixture: String, Equatable {
    case active
    case offline
    case unavailable
    case fallback
    case delayed

    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Self? {
        guard let marker = arguments.firstIndex(of: "-agentCyAccountRestoreFixture"),
              arguments.indices.contains(marker + 1) else {
            return nil
        }
        return Self(rawValue: arguments[marker + 1])
    }

    var syncState: AccountRestoreSyncState {
        switch self {
        case .active, .delayed:
            return .available
        case .offline:
            return .offline
        case .unavailable:
            return .cloudUnavailable
        case .fallback:
            return .localOnlyFallback
        }
    }

    var startsDelayed: Bool {
        self == .delayed
    }
}
#endif

enum AccountRestorePhase: Equatable {
    case checking
    case restoring
    case delayed
    case offline
    case unavailable
}

struct AccountRestorePresentation: Equatable {
    static let delayedAfterSeconds: UInt64 = 15

    let phase: AccountRestorePhase
    let title: String
    let message: String
    let accessibilityValue: String
    let showsProgress: Bool
    let offersRetry: Bool
    let offersAccountRecovery: Bool

    let accessibilityLabel = "Workspace restoration status"

    static func resolve(
        syncState: AccountRestoreSyncState,
        hasExceededDelay: Bool
    ) -> Self {
        if hasExceededDelay,
           syncState == .checking || syncState == .available {
            return Self(
                phase: .delayed,
                title: "Your workspace is taking longer than expected",
                message: "Your account is connected, but your workspace has not arrived yet. Check again, or sign out of this device to use a different account.",
                accessibilityValue: "Restoration delayed. Recovery actions are available.",
                showsProgress: false,
                offersRetry: true,
                offersAccountRecovery: true
            )
        }

        switch syncState {
        case .checking:
            return Self(
                phase: .checking,
                title: "Checking iCloud",
                message: "Confirming that this device can restore your connected workspace.",
                accessibilityValue: "Checking iCloud availability",
                showsProgress: true,
                offersRetry: false,
                offersAccountRecovery: false
            )
        case .available:
            return Self(
                phase: .restoring,
                title: "Restoring your workspace",
                message: "Your account is connected. Keep agent.cy open while your ideas, plans, and settings arrive from iCloud.",
                accessibilityValue: "Restoring from iCloud",
                showsProgress: true,
                offersRetry: false,
                offersAccountRecovery: false
            )
        case .offline:
            return Self(
                phase: .offline,
                title: "Connect to continue restoring",
                message: "agent.cy cannot reach iCloud while this device is offline. Your local data is safe. Reconnect, then try again.",
                accessibilityValue: "Restoration paused. This device is offline.",
                showsProgress: false,
                offersRetry: true,
                offersAccountRecovery: true
            )
        case .cloudUnavailable:
            return Self(
                phase: .unavailable,
                title: "iCloud sync is not available",
                message: "iCloud is not available for agent.cy on this device. Check your Apple ID and iCloud settings, then try again.",
                accessibilityValue: "Restoration unavailable. Check iCloud settings.",
                showsProgress: false,
                offersRetry: true,
                offersAccountRecovery: true
            )
        case .localOnlyFallback:
            return Self(
                phase: .unavailable,
                title: "iCloud sync did not start",
                message: "iCloud sync did not start. Your local data is safe. Close and reopen agent.cy. If this continues, sign out of this device and connect again.",
                accessibilityValue: "Restoration unavailable. Restart agent.cy or sign out of this device.",
                showsProgress: false,
                offersRetry: false,
                offersAccountRecovery: true
            )
        }
    }

    func animatesAsterisk(reduceMotion: Bool) -> Bool {
        phase == .restoring && !reduceMotion
    }
}

struct AccountRestoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var connectivityMonitor = AccountRestoreConnectivityMonitor()
    @State private var cloudState: AccountRestoreSyncState = .checking
    @State private var hasExceededDelay = false
    @State private var restoreAttempt = 0
    @State private var isRotating = false
    @State private var showsAccountRecovery = false
    @State private var recoveryError: String?

    private let localOnlyFallback: Bool

    init(localOnlyFallback: Bool = ModelContainerFactory.didFallBackToLocalOnlyStore) {
        self.localOnlyFallback = localOnlyFallback
    }

    private var presentation: AccountRestorePresentation {
        .resolve(
            syncState: AccountRestoreSyncPolicy.effectiveState(
                cloudState: cloudState,
                connectivity: connectivityMonitor.status
            ),
            hasExceededDelay: hasExceededDelay
        )
    }

    private var shouldAnimate: Bool {
        presentation.animatesAsterisk(reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: AgentSpacing.x6) {
                    restoreIndicator
                    restoreStatus
                    recoveryActions
                }
                .frame(maxWidth: 480)
                .padding(AgentSpacing.x8)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .task(id: restoreAttempt) {
            cloudState = .checking
            recoveryError = nil
            #if DEBUG
            if let fixture = AccountRestoreRuntimeFixture.resolve() {
                cloudState = fixture.syncState
                return
            }
            #endif
            cloudState = await AccountRestoreSyncPolicy.check(
                localOnlyFallback: localOnlyFallback
            )
        }
        .task(id: restoreAttempt) {
            hasExceededDelay = false
            #if DEBUG
            if AccountRestoreRuntimeFixture.resolve()?.startsDelayed == true {
                hasExceededDelay = true
                return
            }
            #endif
            do {
                try await Task.sleep(
                    for: .seconds(AccountRestorePresentation.delayedAfterSeconds)
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            hasExceededDelay = true
        }
        .onChange(of: shouldAnimate, initial: true) { _, shouldAnimate in
            isRotating = shouldAnimate
        }
        .onChange(of: presentation) { _, presentation in
            announce(presentation)
        }
        .onChange(of: connectivityMonitor.status) { oldStatus, newStatus in
            guard oldStatus == .offline, newStatus == .online else { return }
            restoreAttempt &+= 1
        }
        .onAppear {
            connectivityMonitor.start()
        }
        .onDisappear {
            isRotating = false
            connectivityMonitor.stop()
        }
        .confirmationDialog(
            "Sign out of this device?",
            isPresented: $showsAccountRecovery,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                recoverWithAnotherAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local ideas, plans, and drafts stay on this device. Signing out removes only this device's secure account connection.")
        }
    }

    private var restoreIndicator: some View {
        ZStack {
            if presentation.phase == .checking {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.cyAccent)
            } else {
                CyAsterisk(color: .cyAccent, size: 44, strokeWidth: 2.4)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                    .animation(
                        shouldAnimate
                            ? .linear(duration: 1.6).repeatForever(autoreverses: false)
                            : nil,
                        value: isRotating
                    )
            }
        }
        .frame(width: 72, height: 72)
        .background(Color.cyAccent.opacity(0.1), in: .circle)
        .accessibilityHidden(true)
    }

    private var restoreStatus: some View {
        VStack(spacing: AgentSpacing.x2) {
            Text(presentation.title)
                .font(.agentTitle)
                .foregroundStyle(Color.agentText)
                .multilineTextAlignment(.center)
            Text(presentation.message)
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let recoveryError {
                Text(recoveryError)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentDestructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityIdentifier("account-restore-status")
    }

    @ViewBuilder
    private var recoveryActions: some View {
        if presentation.offersRetry || presentation.offersAccountRecovery {
            VStack(spacing: AgentSpacing.x3) {
                if presentation.offersRetry {
                    Button("Check again") {
                        connectivityMonitor.restart()
                        restoreAttempt &+= 1
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
                    .accessibilityHint("Checks iCloud availability and restarts the restoration wait.")
                }

                if presentation.offersAccountRecovery {
                    Button("Use a different account") {
                        showsAccountRecovery = true
                    }
                    .buttonStyle(AgentSecondaryButtonStyle())
                    .accessibilityHint("Signs out this device after confirmation. Local work stays on the device.")
                }
            }
            .frame(maxWidth: 360)
        }
    }

    private func recoverWithAnotherAccount() {
        Task {
            await appModel.signOutOfAccount(
                successMessage: "Signed out of this device."
            )
            guard appModel.hasLinkedAccount else { return }
            recoveryError = appModel.notice?.message
                ?? "agent.cy could not sign out this device. Try again."
        }
    }

    private func announce(_ presentation: AccountRestorePresentation) {
        UIAccessibility.post(
            notification: .announcement,
            argument: presentation.accessibilityValue
        )
    }
}

enum AppleAccountAuthorizationPolicy {
    static func material(
        identityTokenData: Data?,
        authorizationCodeData: Data?,
        nonce: String?,
        appleUserID: String
    ) -> AppleAuthorizationMaterial? {
        guard let nonce,
              let identityTokenData,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            return nil
        }
        return AppleAuthorizationMaterial(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: nonce,
            appleUserID: appleUserID
        )
    }

    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == ASAuthorizationError.errorDomain
            && error.code == ASAuthorizationError.canceled.rawValue
    }
}

struct AgentAppleAccountButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            do {
                let nonce = try AppleSignInNonce.make()
                rawNonce = nonce
                request.nonce = AppleSignInNonce.sha256(nonce)
            } catch {
                rawNonce = nil
                appModel.presentCreatorError(error, action: "Sign in with Apple")
            }
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .clipShape(.rect(cornerRadius: AgentRadius.control))
        .disabled(appModel.isAuthorizingAccount)
        .accessibilityHint("Connects this device to your agent.cy account.")
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let material = AppleAccountAuthorizationPolicy.material(
                    identityTokenData: credential.identityToken,
                    authorizationCodeData: credential.authorizationCode,
                    nonce: rawNonce,
                    appleUserID: credential.user
                  ) else {
                appModel.notice = .error("Apple returned an incomplete sign-in. Please try again.")
                return
            }
            self.rawNonce = nil
            Task {
                await appModel.authorizeAppleAccount(material, context: context)
            }
        case .failure(let error):
            rawNonce = nil
            if AppleAccountAuthorizationPolicy.isCancellation(error) { return }
            appModel.presentCreatorError(error, action: "Sign in with Apple")
        }
    }
}

enum AppleSignInNonce {
    static func make(
        length: Int = 32,
        using fill: (inout [UInt8]) -> OSStatus = fillSecureRandom
    ) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = fill(&bytes)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func fillSecureRandom(_ bytes: inout [UInt8]) -> OSStatus {
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    }
}
