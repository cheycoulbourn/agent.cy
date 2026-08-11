import AppIntents
import Foundation
import WidgetKit

struct WidgetTaskCompletionAction: Codable, Equatable, Sendable {
    var id: UUID
    var taskID: UUID
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        taskID: UUID,
        isCompleted: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

enum WidgetTaskCompletionActionStore {
    private static let key = "agentCy.widget.taskCompletionActions.v1"

    static func pending(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) throws -> [WidgetTaskCompletionAction] {
        guard let defaults else { throw AgentCyWidgetTaskActionStoreError.unavailableAppGroup }
        guard let data = defaults.data(forKey: key) else { return [] }
        return try decoder.decode([WidgetTaskCompletionAction].self, from: data)
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func enqueue(
        _ action: WidgetTaskCompletionAction,
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) throws {
        guard let defaults else { throw AgentCyWidgetTaskActionStoreError.unavailableAppGroup }
        var actions = try pending(defaults: defaults)
        actions.removeAll { $0.taskID == action.taskID }
        actions.append(action)
        defaults.set(try encoder.encode(actions), forKey: key)
    }

    static func remove(
        _ acknowledged: [WidgetTaskCompletionAction],
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) throws {
        guard let defaults else { throw AgentCyWidgetTaskActionStoreError.unavailableAppGroup }
        guard !acknowledged.isEmpty else { return }
        let acknowledgedByTask = Dictionary(
            acknowledged.map { ($0.taskID, $0.id) },
            uniquingKeysWith: { current, _ in current }
        )
        let remaining = try pending(defaults: defaults).filter { action in
            acknowledgedByTask[action.taskID] != action.id
        }
        defaults.set(try encoder.encode(remaining), forKey: key)
    }

    private static var encoder: JSONEncoder { JSONEncoder() }
    private static var decoder: JSONDecoder { JSONDecoder() }
}

enum AgentCyWidgetTaskActionStoreError: Error {
    case unavailableAppGroup
}

struct SetWidgetTaskCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Task"
    static let description = IntentDescription("Mark an agent.cy task complete or open from a widget.")
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var taskID: String

    @Parameter(title: "Completed")
    var isCompleted: Bool

    init() {}

    init(taskID: UUID, isCompleted: Bool) {
        self.taskID = taskID.uuidString
        self.isCompleted = isCompleted
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }

        let action = WidgetTaskCompletionAction(taskID: id, isCompleted: isCompleted)
        try WidgetTaskCompletionActionStore.enqueue(action)

        if var snapshot = AgentCyWidgetSnapshotStore.load() {
            snapshot.setTaskCompletion(taskID: id, isCompleted: isCompleted)
            try AgentCyWidgetSnapshotStore.save(snapshot)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "com.agentcy.widget.production-queue")
        return .result()
    }
}
