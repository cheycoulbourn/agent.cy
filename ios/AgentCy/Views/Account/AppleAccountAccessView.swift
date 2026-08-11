import AuthenticationServices
import CryptoKit
import Security
import SwiftData
import SwiftUI

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

                    if appModel.isAuthorizingAccount {
                        HStack(spacing: AgentSpacing.x3) {
                            ProgressView()
                            Text("Connecting your workspace…")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                        }
                    }
                }
                .padding(AgentSpacing.x5)
                .background(Color.agentSurface, in: .rect(cornerRadius: 24))
                .agentSurfaceChrome(cornerRadius: 24)

                Button("I have an invitation code") {
                    showsInvitation = true
                }
                .buttonStyle(AgentSecondaryButtonStyle())

                Text("New here? Use the invitation code you received. You can link Apple after setup without moving or deleting anything.")
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let notice = appModel.notice {
                    Text(notice.message)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

struct AccountRestoreView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        VStack(spacing: AgentSpacing.x6) {
            CyAsterisk(color: .cyAccent, size: 44, strokeWidth: 2.4)
                .rotationEffect(.degrees(reduceMotion ? 0 : (isRotating ? 360 : 0)))
                .animation(
                    reduceMotion ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false),
                    value: isRotating
                )
                .frame(width: 72, height: 72)
                .background(Color.cyAccent.opacity(0.1), in: .circle)

            VStack(spacing: AgentSpacing.x2) {
                Text("Restoring your workspace")
                    .font(.agentTitle)
                    .foregroundStyle(Color.agentText)
                Text("Your account is connected. Keep agent.cy open while your ideas, plans, and settings arrive from iCloud.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 480)
        .padding(AgentSpacing.x8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isRotating = true }
        .accessibilityElement(children: .combine)
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
                  let rawNonce,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let authorizationCodeData = credential.authorizationCode,
                  let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
                appModel.notice = .error("Apple returned an incomplete sign-in. Please try again.")
                return
            }
            self.rawNonce = nil
            Task {
                await appModel.authorizeAppleAccount(
                    AppleAuthorizationMaterial(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode,
                        nonce: rawNonce,
                        appleUserID: credential.user
                    ),
                    context: context
                )
            }
        case .failure(let error):
            rawNonce = nil
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            appModel.presentCreatorError(error, action: "Sign in with Apple")
        }
    }
}

private enum AppleSignInNonce {
    static func make(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
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
}
