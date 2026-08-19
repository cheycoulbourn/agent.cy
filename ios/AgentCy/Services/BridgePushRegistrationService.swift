import Foundation

enum BridgePushRegistrationPolicy {
    static func shouldRegister(isMacCatalyst: Bool) -> Bool {
        !isMacCatalyst
    }

    static func shouldRequestCapability(
        existing: MCPBridgePushCapability?,
        registeredDeviceToken: Data?,
        currentDeviceToken: Data
    ) -> Bool {
        existing == nil || registeredDeviceToken != currentDeviceToken
    }

    static func snapshotCapability(
        isMacCatalyst: Bool,
        local: MCPBridgePushCapability?,
        existing: MCPBridgePushCapability?
    ) -> MCPBridgePushCapability? {
        isMacCatalyst ? existing : (local ?? existing)
    }

    static var shouldRegisterOnCurrentPlatform: Bool {
        #if targetEnvironment(macCatalyst)
        shouldRegister(isMacCatalyst: true)
        #else
        shouldRegister(isMacCatalyst: false)
        #endif
    }

    static func snapshotCapabilityForCurrentPlatform(
        local: MCPBridgePushCapability?,
        existing: MCPBridgePushCapability?
    ) -> MCPBridgePushCapability? {
        #if targetEnvironment(macCatalyst)
        snapshotCapability(isMacCatalyst: true, local: local, existing: existing)
        #else
        snapshotCapability(isMacCatalyst: false, local: local, existing: existing)
        #endif
    }
}

struct MCPBridgePushCapability: Codable, Equatable, Sendable {
    let endpoint: URL
    let token: String
}

private struct BridgePushRegistrationRequest: Encodable {
    let deviceToken: String
    let platform: String
    let appBuild: String
    let showTitles: Bool
}

private struct BridgePushRegistrationResponse: Decodable {
    let notification: MCPBridgePushCapability
}

private struct BridgePushHTTPErrorEnvelope: Decodable {
    let error: AIWireError
}

actor BridgePushRegistrationClient {
    private let baseURL: URL
    private let session: URLSession
    private let store: any InstallationCredentialStoring
    private let appBuild: String

    init(
        baseURL: URL = APIConfiguration.baseURL,
        session: URLSession = .shared,
        store: any InstallationCredentialStoring = DeviceOnlyKeychainCredentialStore.shared,
        appBuild: String = APIConfiguration.appBuild
    ) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
        self.appBuild = appBuild
    }

    func register(deviceToken: Data, showTitles: Bool) async throws -> MCPBridgePushCapability {
        guard let identity = try await store.load() else {
            throw AgentCyAPIError.missingCredential
        }
        var request = URLRequest(url: baseURL.appending(path: "/v1/bridge/notifications/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identity.credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.agentCy.encode(BridgePushRegistrationRequest(
            deviceToken: deviceToken.map { String(format: "%02x", $0) }.joined(),
            platform: Self.platform,
            appBuild: appBuild,
            showTitles: showTitles
        ))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder.agentCy.decode(BridgePushHTTPErrorEnvelope.self, from: data) {
                throw AgentCyAPIError.server(envelope.error)
            }
            throw AgentCyAPIError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let capability = try JSONDecoder.agentCy
            .decode(BridgePushRegistrationResponse.self, from: data)
            .notification
        guard Self.isSecureBridgeEndpoint(capability.endpoint), capability.token.count >= 32 else {
            throw AgentCyAPIError.invalidStream("The push registration capability was invalid.")
        }
        return capability
    }

    private static var platform: String {
        #if targetEnvironment(macCatalyst)
        "macCatalyst"
        #else
        "ios"
        #endif
    }

    private static func isSecureBridgeEndpoint(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
        #if DEBUG
        return url.scheme?.lowercased() == "http" && ["127.0.0.1", "localhost"].contains(url.host?.lowercased())
        #else
        return false
        #endif
    }
}

enum MCPBridgePushPreferences {
    private static let capabilityKey = "agentcy.mcp.push-capability.v1"
    private static let registeredDeviceTokenKey = "agentcy.mcp.push-device-token.v1"

    static var capability: MCPBridgePushCapability? {
        get {
            guard let data = UserDefaults.standard.data(forKey: capabilityKey) else { return nil }
            return try? JSONDecoder.agentCy.decode(MCPBridgePushCapability.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder.agentCy.encode(newValue) {
                UserDefaults.standard.set(data, forKey: capabilityKey)
            } else {
                UserDefaults.standard.removeObject(forKey: capabilityKey)
            }
        }
    }

    static var registeredDeviceToken: Data? {
        get { UserDefaults.standard.data(forKey: registeredDeviceTokenKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: registeredDeviceTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: registeredDeviceTokenKey)
            }
        }
    }
}
