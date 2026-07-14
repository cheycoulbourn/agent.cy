import Foundation

enum AgentCyWidgetShared {
    static let appGroupIdentifier = "group.com.agentcy.app"
    static let snapshotKey = "agentCy.widget.snapshot.v1"
}

struct AgentCyWidgetSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var creatorName: String
    var focus: WidgetFocusSnapshot?
    var todayTasks: [WidgetTaskSnapshot]
    var nextPost: WidgetPostSnapshot?
    var week: [WidgetDaySnapshot]
    var latestIdea: WidgetIdeaSnapshot?
    var productionTasks: [WidgetTaskSnapshot]

    static let empty = AgentCyWidgetSnapshot(
        generatedAt: .distantPast,
        creatorName: "Creator",
        focus: nil,
        todayTasks: [],
        nextPost: nil,
        week: [],
        latestIdea: nil,
        productionTasks: []
    )

    static let preview: AgentCyWidgetSnapshot = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let week = (0..<7).compactMap { offset -> WidgetDaySnapshot? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let focusTitles = ["Planning", "Scripting", "Filming", "Editing", "Publishing", "Community", "Rest"]
            return WidgetDaySnapshot(
                date: date,
                focusTitle: focusTitles[offset],
                pillarColorHex: ["9B3A2E", "5E8069", "D7A46A", "5E8069", "7293BD", nil, nil][offset]
            )
        }
        return AgentCyWidgetSnapshot(
            generatedAt: Date(),
            creatorName: "Chey",
            focus: WidgetFocusSnapshot(
                title: "Batch film",
                directive: "Film 2–4 videos while the setup is ready.",
                durationMinutes: 90,
                startDate: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today),
                completedTaskCount: 1,
                taskCount: 4
            ),
            todayTasks: [
                WidgetTaskSnapshot(id: UUID(), title: "Set up filming corner", kind: "Production", targetDate: nil, isCompleted: false),
                WidgetTaskSnapshot(id: UUID(), title: "Film two short videos", kind: "Filming", targetDate: nil, isCompleted: false),
            ],
            nextPost: WidgetPostSnapshot(
                id: UUID(),
                title: "How I plan a week of content",
                pillarName: "Mind your business",
                pillarColorHex: "5E8069",
                platformLabel: "Instagram · Reel",
                targetDate: calendar.date(byAdding: .hour, value: 2, to: Date()),
                status: "Ready"
            ),
            week: week,
            latestIdea: WidgetIdeaSnapshot(
                id: UUID(),
                title: "What changed when I stopped chasing every format",
                pillarName: "Lifestyle",
                pillarColorHex: "5E8069",
                capturedAt: Date()
            ),
            productionTasks: [
                WidgetTaskSnapshot(id: UUID(), title: "Set up the filming corner", kind: "Production", targetDate: nil, isCompleted: true, lane: .production),
                WidgetTaskSnapshot(id: UUID(), title: "Film two clean takes", kind: "Filming", targetDate: nil, isCompleted: false, lane: .production),
                WidgetTaskSnapshot(id: UUID(), title: "Capture one B-roll detail", kind: "Filming", targetDate: nil, isCompleted: false, lane: .production),
                WidgetTaskSnapshot(id: UUID(), title: "Outline three Lifestyle ideas", kind: "Planning", targetDate: nil, isCompleted: false, lane: .pillar),
                WidgetTaskSnapshot(id: UUID(), title: "Review the Mind Your Business bank", kind: "Planning", targetDate: nil, isCompleted: false, lane: .pillar),
            ]
        )
    }()
}

struct WidgetFocusSnapshot: Codable, Equatable, Sendable {
    var title: String
    var directive: String
    var durationMinutes: Int?
    var startDate: Date?
    var completedTaskCount: Int
    var taskCount: Int
}

struct WidgetTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var kind: String
    var targetDate: Date?
    var isCompleted: Bool
    var lane: WidgetTaskLane? = nil
}

enum WidgetTaskLane: String, Codable, Equatable, CaseIterable, Sendable {
    case production
    case pillar
}

struct WidgetPostSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var pillarName: String
    var pillarColorHex: String?
    var platformLabel: String
    var targetDate: Date?
    var status: String
}

struct WidgetDaySnapshot: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var focusTitle: String
    var pillarColorHex: String?

    var id: Date { date }
}

struct WidgetIdeaSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var pillarName: String?
    var pillarColorHex: String?
    var capturedAt: Date
}

enum AgentCyWidgetSnapshotStore {
    static func load(defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)) -> AgentCyWidgetSnapshot? {
        guard let data = defaults?.data(forKey: AgentCyWidgetShared.snapshotKey) else { return nil }
        return try? decoder.decode(AgentCyWidgetSnapshot.self, from: data)
    }

    static func save(
        _ snapshot: AgentCyWidgetSnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) throws {
        guard let defaults else { throw AgentCyWidgetSnapshotStoreError.unavailableAppGroup }
        defaults.set(try encoder.encode(snapshot), forKey: AgentCyWidgetShared.snapshotKey)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

enum AgentCyWidgetSnapshotStoreError: Error {
    case unavailableAppGroup
}

enum AgentCyDeepLink: Equatable, Sendable {
    case today
    case agenda(day: Date?)
    case tasks
    case ideaBank
    case quickIdea
    case quickPost
    case quickTask
    case brief(UUID)

    var url: URL {
        var components = URLComponents()
        components.scheme = "agentcy"
        switch self {
        case .today:
            components.host = "today"
        case .agenda(let day):
            components.host = "agenda"
            if let day {
                components.queryItems = [URLQueryItem(name: "day", value: Self.dayFormatter.string(from: day))]
            }
        case .tasks:
            components.host = "tasks"
        case .ideaBank:
            components.host = "idea-bank"
        case .quickIdea:
            components.host = "capture"
            components.path = "/idea"
        case .quickPost:
            components.host = "capture"
            components.path = "/post"
        case .quickTask:
            components.host = "capture"
            components.path = "/task"
        case .brief(let id):
            components.host = "brief"
            components.path = "/\(id.uuidString.lowercased())"
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "agentcy" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host?.lowercased() {
        case "today":
            self = .today
        case "agenda":
            let value = components?.queryItems?.first(where: { $0.name == "day" })?.value
            self = .agenda(day: value.flatMap(Self.dayFormatter.date(from:)))
        case "tasks":
            self = .tasks
        case "idea-bank":
            self = .ideaBank
        case "capture":
            switch url.path.lowercased() {
            case "/idea": self = .quickIdea
            case "/post": self = .quickPost
            case "/task": self = .quickTask
            default: return nil
            }
        case "brief":
            guard let id = UUID(uuidString: String(url.path.dropFirst())) else { return nil }
            self = .brief(id)
        default:
            return nil
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
