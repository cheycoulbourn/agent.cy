import Foundation
import SwiftData

enum ModelContainerFactory {
    /// The app and its App Intents share one container so a shortcut can save
    /// directly into the same offline-first store without opening a second copy.
    static let shared = make()

    static func make(isStoredInMemoryOnly: Bool = false) -> ModelContainer {
        let schema = AgentCySchema.schema
        if isStoredInMemoryOnly {
            let configuration = ModelConfiguration("AgentCyPreview", schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }

        #if targetEnvironment(simulator) || AGENTCY_LOCAL_ONLY
        let forceLocalOnly = true
        #else
        let forceLocalOnly = false
        #endif
        let database: ModelConfiguration.CloudKitDatabase = shouldUseCloudKit(
            cloudKitEnabled: cloudKitEnabled,
            forceLocalOnly: forceLocalOnly
        ) ? .private("iCloud.com.agentcy.app") : .none
        let cloud = ModelConfiguration(
            "AgentCyStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .none,
            cloudKitDatabase: database
        )
        do {
            // The CloudKit-backed store is itself offline-first. SwiftData writes locally and syncs when iCloud is available.
            return try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            fatalError("agent.cy could not open its CloudKit-backed local store: \(error.localizedDescription)")
        }
    }

    static func shouldUseCloudKit(cloudKitEnabled: Bool, forceLocalOnly: Bool) -> Bool {
        cloudKitEnabled && !forceLocalOnly
    }

    /// Creates a file-backed local store at a caller-controlled URL. This is
    /// used by migration characterization tests so reopening exercises SQLite
    /// persistence rather than the in-memory test path.
    static func makeLocal(at url: URL) throws -> ModelContainer {
        let schema = AgentCySchema.schema
        let configuration = ModelConfiguration(
            "AgentCyMigrationTest",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static var cloudKitEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "AGENTCY_CLOUDKIT_ENABLED") as? String
        return (value as NSString?)?.boolValue ?? false
    }
}
