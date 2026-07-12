import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make(isStoredInMemoryOnly: Bool = false) -> ModelContainer {
        let schema = AgentCySchema.schema
        if isStoredInMemoryOnly {
            let configuration = ModelConfiguration("AgentCyPreview", schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }

        #if targetEnvironment(simulator) || AGENTCY_LOCAL_ONLY
        let database: ModelConfiguration.CloudKitDatabase = .none
        #else
        let database: ModelConfiguration.CloudKitDatabase = .private("iCloud.com.agentcy.app")
        #endif
        let cloud = ModelConfiguration(
            "AgentCyStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: database
        )
        do {
            // The CloudKit-backed store is itself offline-first. SwiftData writes locally and syncs when iCloud is available.
            return try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            fatalError("agent.cy could not open its CloudKit-backed local store: \(error.localizedDescription)")
        }
    }
}
