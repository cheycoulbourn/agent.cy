import AppIntents
import SwiftUI
import WidgetKit

struct AgentCyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AgentCyWidgetSnapshot
    var taskLane: WidgetTaskLane = .production
    var isPreview = false
}

extension WidgetTaskLane: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task type")
    static let caseDisplayRepresentations: [WidgetTaskLane: DisplayRepresentation] = [
        .production: DisplayRepresentation(title: "Focus tasks"),
        .pillar: DisplayRepresentation(title: "Pillar tasks"),
    ]
}

struct ProductionQueueConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Focus Queue"
    static let description = IntentDescription("Choose which kind of tasks the widget shows.")

    @Parameter(title: "Tasks", default: .production)
    var taskLane: WidgetTaskLane
}

struct AgentCyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentCyWidgetEntry {
        AgentCyWidgetEntry(date: Date(), snapshot: .preview, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentCyWidgetEntry) -> Void) {
        let snapshot = context.isPreview
            ? AgentCyWidgetSnapshot.preview
            : AgentCyWidgetSnapshotStore.load() ?? .empty
        completion(AgentCyWidgetEntry(date: Date(), snapshot: snapshot, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentCyWidgetEntry>) -> Void) {
        let snapshot = AgentCyWidgetSnapshotStore.load() ?? .empty
        let entry = AgentCyWidgetEntry(date: Date(), snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct ProductionQueueWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AgentCyWidgetEntry {
        AgentCyWidgetEntry(date: Date(), snapshot: .preview, isPreview: true)
    }

    func snapshot(
        for configuration: ProductionQueueConfigurationIntent,
        in context: Context
    ) async -> AgentCyWidgetEntry {
        let snapshot = context.isPreview
            ? AgentCyWidgetSnapshot.preview
            : AgentCyWidgetSnapshotStore.load() ?? .empty
        return AgentCyWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            taskLane: configuration.taskLane,
            isPreview: context.isPreview
        )
    }

    func timeline(
        for configuration: ProductionQueueConfigurationIntent,
        in context: Context
    ) async -> Timeline<AgentCyWidgetEntry> {
        let snapshot = AgentCyWidgetSnapshotStore.load() ?? .empty
        let entry = AgentCyWidgetEntry(date: Date(), snapshot: snapshot, taskLane: configuration.taskLane)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct TodayFocusWidget: Widget {
    let kind = "com.agentcy.widget.today-focus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            TodayFocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Today’s Focus")
        .description("See the work you batched for today.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct QuickCaptureWidget: Widget {
    let kind = "com.agentcy.widget.quick-capture"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            QuickCaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Capture")
        .description("Capture an idea, post, or task without hunting through the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct VoiceSparkWidget: Widget {
    let kind = "com.agentcy.widget.voice-spark"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            VoiceSparkWidgetView(entry: entry)
        }
        .configurationDisplayName("Voice Spark")
        .description("Record a thought and turn it into an editable Idea Bank entry.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct NextPostWidget: Widget {
    let kind = "com.agentcy.widget.next-post"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            NextPostWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Post")
        .description("Keep the next planned post close.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct WeeklyRhythmWidget: Widget {
    let kind = "com.agentcy.widget.weekly-rhythm"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            WeeklyRhythmWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly Rhythm")
        .description("See the focus and pillar rhythm for this week.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct IdeaBankWidget: Widget {
    let kind = "com.agentcy.widget.idea-bank"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            IdeaBankWidgetView(entry: entry)
        }
        .configurationDisplayName("Idea Bank")
        .description("Keep your newest idea visible and capture the next one.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct PillarUsageWidget: Widget {
    let kind = "com.agentcy.widget.pillar-usage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            PillarUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Pillar Usage")
        .description("See how this week’s planned posts are distributed across your pillars.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct ConsistencyWidget: Widget {
    let kind = "com.agentcy.widget.consistency"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            ConsistencyWidgetView(entry: entry)
        }
        .configurationDisplayName("Consistency")
        .description("Track how many weeks you’ve posted on plan.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct WeekAtAGlanceWidget: Widget {
    let kind = "com.agentcy.widget.week-at-a-glance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            WeekAtAGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Week at a Glance")
        .description("See the posting shape of your week without opening the app.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct TasksWidget: Widget {
    let kind = "com.agentcy.widget.tasks"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentCyWidgetProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks")
        .description("Keep today’s next two tasks on your Home Screen.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct ProductionQueueWidget: Widget {
    let kind = "com.agentcy.widget.production-queue"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProductionQueueConfigurationIntent.self, provider: ProductionQueueWidgetProvider()) { entry in
            ProductionQueueWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus Queue")
        .description("See the next post and the work that moves it forward.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AgentCyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayFocusWidget()
        QuickCaptureWidget()
        VoiceSparkWidget()
        NextPostWidget()
        WeeklyRhythmWidget()
        IdeaBankWidget()
        PillarUsageWidget()
        ConsistencyWidget()
        WeekAtAGlanceWidget()
        TasksWidget()
        ProductionQueueWidget()
        VoiceSparkControlWidget()
    }
}
