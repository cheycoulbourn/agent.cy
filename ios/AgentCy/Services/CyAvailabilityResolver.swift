import Foundation

enum CyAvailabilityState: Equatable {
    case checking
    case localBridge
    case hosted
    case unavailable

    var label: String {
        switch self {
        case .checking: "Checking"
        case .localBridge: "Local bridge"
        case .hosted: "Hosted Cy"
        case .unavailable: "Unavailable"
        }
    }

    var isAvailable: Bool { self == .localBridge || self == .hosted }

    var detail: String {
        switch self {
        case .checking: "Checking this device’s access to Cy."
        case .localBridge: "Claude or Codex on your Mac is available to help."
        case .hosted: "Hosted access is enabled on this device."
        case .unavailable: "Check hosted access or connect Claude or Codex on your Mac."
        }
    }

    static func resolve(localAvailable: Bool, hostedAllowed: Bool, identity: InstallationIdentity?, now: Date = Date()) -> Self {
        if localAvailable { return .localBridge }
        guard hostedAllowed, let identity, !identity.credential.isEmpty,
              identity.credentialExpiresAt.map({ $0 > now }) ?? true else { return .unavailable }
        return .hosted
    }
}

@MainActor
enum CyAvailabilityResolver {
    static func resolve(subscription: SubscriptionState?) async -> CyAvailabilityState {
        if await LocalCyAIClient.shared.isAvailable() { return .localBridge }
        let identity = try? await DeviceOnlyKeychainCredentialStore.shared.load()
        return CyAvailabilityState.resolve(
            localAvailable: false,
            hostedAllowed: AccessPolicy.allows(.askCy, state: subscription),
            identity: identity
        )
    }
}
