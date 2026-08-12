import Foundation
import SwiftData
import os

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
            return try ModelContainer(for: schema, migrationPlan: AgentCyMigrationPlan.self, configurations: [cloud])
        } catch {
            // A CloudKit-configured open can fail for reasons a plain local
            // open does not share (container entitlements, CloudKit schema
            // constraints). User data lives in the same local store either
            // way, so reopening without sync keeps it reachable.
            logger.fault("CloudKit-backed store failed to open, retrying local-only: \(error.localizedDescription, privacy: .public)")
            let localOnly = ModelConfiguration(
                "AgentCyStore",
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            do {
                let container = try ModelContainer(for: schema, migrationPlan: AgentCyMigrationPlan.self, configurations: [localOnly])
                didFallBackToLocalOnlyStore = true
                return container
            } catch {
                fatalError("agent.cy could not open its local store: \(error.localizedDescription)")
            }
        }
    }

    /// Set when the CloudKit-configured open failed and the app is running on
    /// the same store without sync. Surfaced so the UI can tell the user sync
    /// is off rather than failing silently. Written once during container
    /// creation, before any reader can observe it.
    nonisolated(unsafe) private(set) static var didFallBackToLocalOnlyStore = false

    private static let logger = Logger(subsystem: "com.agentcy.app", category: "ModelContainerFactory")

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
