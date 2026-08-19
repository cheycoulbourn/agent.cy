import SwiftData
import UIKit
import UserNotifications

extension Notification.Name {
    static let agentCyNotificationRouteReady = Notification.Name("agentCyNotificationRouteReady")
    static let agentCyNotificationContentChanged = Notification.Name("agentCyNotificationContentChanged")
    static let agentCyMCPInboxChanged = Notification.Name("agentCyMCPInboxChanged")
}

enum AgentNotificationRouteKind: String, Codable {
    case day
    case week
    case cyWeek
    case brief
    case draft
    case task
    case access
    case mcpReview
}

struct AgentNotificationRoute: Codable, Equatable {
    let kind: AgentNotificationRouteKind
    let objectID: UUID?
    let date: Date?
}

enum AgentNotificationRouteResolver {
    static func route(
        from metadata: [String: String],
        overridingKind: AgentNotificationRouteKind? = nil
    ) -> AgentNotificationRoute {
        let routeValue = metadata[AgentNotificationMetadataKey.remoteRoute]
            ?? metadata[AgentNotificationMetadataKey.route]
        let resolvedKind: AgentNotificationRouteKind = switch routeValue {
        case "week": .week
        case "cyWeek": .cyWeek
        case "brief": .brief
        case "draft": .draft
        case "task": .task
        case "access": .access
        case "mcpReview": .mcpReview
        default: .day
        }
        let kind = overridingKind ?? resolvedKind
        let objectID: UUID? = switch kind {
        case .brief, .draft:
            metadata[AgentNotificationMetadataKey.briefID].flatMap(UUID.init(uuidString:))
        case .task:
            metadata[AgentNotificationMetadataKey.taskID].flatMap(UUID.init(uuidString:))
        default:
            nil
        }
        let date = metadata[AgentNotificationMetadataKey.date].flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return AgentNotificationRoute(kind: kind, objectID: objectID, date: date)
    }
}

enum AgentNotificationRouteStore {
    private static let key = "agentcy.pending-notification-route.v1"

    static func put(_ route: AgentNotificationRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .agentCyNotificationRouteReady, object: nil)
    }

    static func take() -> AgentNotificationRoute? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let route = try? JSONDecoder().decode(AgentNotificationRoute.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: key)
        return route
    }
}

@MainActor
final class NotificationActionMutationService {
    private let context: ModelContext

    init(context: ModelContext = ModelContainerFactory.shared.mainContext) {
        self.context = context
    }

    func completeTask(id: UUID) throws {
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        guard let task = tasks.first(where: { $0.id == id }), !task.isCompleted, !task.isSkipped else { return }
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let linkedBrief = task.briefID.flatMap { id in briefs.first { $0.id == id } }
        guard task.briefID == nil || (linkedBrief != nil && linkedBrief?.status != .archived) else { return }

        let priorMilestoneExists = task.briefID.map { briefID in
            tasks.contains { $0.id != task.id && $0.briefID == briefID && $0.recordingMilestoneEmitted }
        } ?? true
        _ = BriefLifecycle.toggleTask(task, brief: linkedBrief)
        if priorMilestoneExists, task.recordingMilestoneEmitted { task.recordingMilestoneEmitted = false }
        if task.isCompleted {
            try RecurringTaskMaterializer.createNextOccurrence(after: task, context: context)
        }
        try finishMutation()
    }

    func pauseTask(id: UUID) throws {
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        guard let task = tasks.first(where: { $0.id == id }), !task.isCompleted, !task.isSkipped else { return }
        task.targetDate = nil
        task.includesTargetTime = false
        task.dailyFocusDate = nil
        try finishMutation()
    }

    func markPosted(outputID: UUID) throws {
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        guard let output = outputs.first(where: { $0.id == outputID }), output.status != .posted else { return }
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        guard let brief = briefs.first(where: { $0.id == output.briefID }), brief.status != .archived else { return }
        guard BriefLifecycle.togglePosted(output, brief: brief) else { return }
        BriefLifecycle.synchronize(brief, outputs: outputs.filter { $0.briefID == brief.id })
        try finishMutation()
    }

    private func finishMutation() throws {
        try context.save()
        WidgetSnapshotService.refresh(context: context)
        try? EventKitCalendarSyncService.shared.reconcile(context: context)
        NotificationCenter.default.post(name: .agentCyNotificationContentChanged, object: nil)
    }
}

final class AgentCyApplicationDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        LocalReminderService.registerCategories(center: center)
        if BridgePushRegistrationPolicy.shouldRegisterOnCurrentPlatform {
            Task { @MainActor in
                let settings = await center.notificationSettings()
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    application.registerForRemoteNotifications()
                default:
                    break
                }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            let context = ModelContainerFactory.shared.mainContext
            let existingCapability = MCPBridgePushPreferences.capability
            guard BridgePushRegistrationPolicy.shouldRequestCapability(
                existing: existingCapability,
                registeredDeviceToken: MCPBridgePushPreferences.registeredDeviceToken,
                currentDeviceToken: deviceToken
            ) else {
                try? MCPBridgeService.sync(context: context)
                NotificationCenter.default.post(name: .agentCyMCPInboxChanged, object: nil)
                return
            }
            let showTitles = (try? context.fetch(FetchDescriptor<ReminderSettings>()).first?.showNotificationTitles) ?? true
            do {
                let capability = try await BridgePushRegistrationClient()
                    .register(deviceToken: deviceToken, showTitles: showTitles)
                MCPBridgePushPreferences.capability = capability
                MCPBridgePushPreferences.registeredDeviceToken = deviceToken
                try? MCPBridgeService.sync(context: context)
                NotificationCenter.default.post(name: .agentCyMCPInboxChanged, object: nil)
            } catch {
                // Registration is retried at the next launch or permission change.
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // The review queue remains available through foreground and manual refresh.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard MCPBridgePreferences.isConnected else {
                completionHandler(.noData)
                return
            }
            let before = (try? MCPBridgeService.pendingRequests().map(\.id)) ?? []
            let after = (try? await MCPBridgeService.refreshPendingRequests().map(\.id)) ?? before
            NotificationCenter.default.post(name: .agentCyMCPInboxChanged, object: nil)
            completionHandler(before == after ? .noData : .newData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // This delegate runs on UNUserNotificationCenter's queue; observers of
        // this notification do main-actor SwiftData work, so hop first.
        await MainActor.run {
            NotificationCenter.default.post(name: .agentCyNotificationContentChanged, object: nil)
            if notification.request.content.categoryIdentifier == AgentNotificationCategory.mcpReview {
                NotificationCenter.default.post(name: .agentCyMCPInboxChanged, object: nil)
            }
        }
        return []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let metadata = response.notification.request.content.userInfo.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String, let value = pair.value as? String else { return }
            result[key] = value
        }

        Task { @MainActor in
            defer { completionHandler() }
            do {
                try? AgentActivityCenterService.markRead(
                    notificationID: response.notification.request.identifier,
                    context: ModelContainerFactory.shared.mainContext
                )
                let mutation = NotificationActionMutationService()
                switch response.actionIdentifier {
                case AgentNotificationAction.markPosted:
                    if let id = uuid(metadata[AgentNotificationMetadataKey.outputID]) { try mutation.markPosted(outputID: id) }
                case AgentNotificationAction.completeTask:
                    if let id = uuid(metadata[AgentNotificationMetadataKey.taskID]) { try mutation.completeTask(id: id) }
                case AgentNotificationAction.pauseTask:
                    if let id = uuid(metadata[AgentNotificationMetadataKey.taskID]) { try mutation.pauseTask(id: id) }
                case AgentNotificationAction.planWithCy:
                    route(.cyWeek, metadata: metadata)
                case AgentNotificationAction.reschedulePost, AgentNotificationAction.moveDraft:
                    route(.draft, metadata: metadata)
                case AgentNotificationAction.finishDraft:
                    route(.draft, metadata: metadata)
                case AgentNotificationAction.moveTask, AgentNotificationAction.openTask:
                    route(.task, metadata: metadata)
                case AgentNotificationAction.openAccess:
                    route(.access, metadata: metadata)
                case AgentNotificationAction.openMCPReview:
                    route(.mcpReview, metadata: metadata)
                case UNNotificationDefaultActionIdentifier:
                    routeFromMetadata(metadata)
                default:
                    break
                }
                _ = try? await LocalReminderService().reconcile(context: ModelContainerFactory.shared.mainContext, now: Date())
            } catch {
                // Notification actions are idempotent. Missing or stale objects are safely ignored.
            }
        }
    }

    @MainActor
    private func routeFromMetadata(_ metadata: [String: String]) {
        AgentNotificationRouteStore.put(AgentNotificationRouteResolver.route(from: metadata))
    }

    @MainActor
    private func route(_ kind: AgentNotificationRouteKind, metadata: [String: String]) {
        AgentNotificationRouteStore.put(
            AgentNotificationRouteResolver.route(from: metadata, overridingKind: kind)
        )
    }

    private func uuid(_ value: String?) -> UUID? {
        value.flatMap(UUID.init(uuidString:))
    }
}
