import AppIntents
import Foundation

enum PhoneFeatureLaunchRoute: String, Codable, Sendable {
    case voiceSpark
}

enum PhoneFeatureLaunchRequestStore {
    private static let key = "agentCy.phoneFeature.pendingRoute.v1"

    static func request(
        _ route: PhoneFeatureLaunchRoute,
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) {
        defaults?.set(route.rawValue, forKey: key)
    }

    static func take(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) -> PhoneFeatureLaunchRoute? {
        guard let rawValue = defaults?.string(forKey: key) else { return nil }
        defaults?.removeObject(forKey: key)
        return PhoneFeatureLaunchRoute(rawValue: rawValue)
    }
}

struct OpenVoiceSparkIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Voice Spark"
    static let description = IntentDescription("Open agent.cy directly to Voice Spark recording.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PhoneFeatureLaunchRequestStore.request(.voiceSpark)
        return .result()
    }
}
