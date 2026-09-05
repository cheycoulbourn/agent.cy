import CoreGraphics
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
    var latestVoiceSpark: WidgetIdeaSnapshot? = nil
    var productionTasks: [WidgetTaskSnapshot]
    var pillarUsage: WidgetPillarUsageSnapshot? = nil
    var consistency: WidgetConsistencySnapshot? = nil

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
            latestVoiceSpark: WidgetIdeaSnapshot(
                id: UUID(),
                title: "The story about choosing a slower creative rhythm",
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
            ],
            pillarUsage: WidgetPillarUsageSnapshot(
                segments: [
                    WidgetPillarSegmentSnapshot(name: "Anchor", colorHex: "8A5A3B", percentage: 44),
                    WidgetPillarSegmentSnapshot(name: "Business", colorHex: "6B6136", percentage: 24),
                    WidgetPillarSegmentSnapshot(name: "Lifestyle", colorHex: "AFBCC6", percentage: 20),
                    WidgetPillarSegmentSnapshot(name: "Community", colorHex: "C9B48D", percentage: 12),
                ],
                leadingPillarName: "Anchor",
                leadingPercentage: 44
            ),
            consistency: {
                let mondayOffset = (calendar.component(.weekday, from: today) + 5) % 7
                let weekStart = calendar.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
                let postedOffsets: Set<Int> = [0, 1, 3]
                let days = (0..<7).compactMap { offset -> WidgetConsistencyDaySnapshot? in
                    guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
                    return WidgetConsistencyDaySnapshot(date: date, hasPost: postedOffsets.contains(offset))
                }
                return WidgetConsistencySnapshot(
                    completedWeeks: [false, false, false, false, false, true, true, false],
                    streak: 0,
                    currentPostedCount: 3,
                    currentPlannedCount: 4,
                    days: days,
                    postedDayCount: 3,
                    goal: 4
                )
            }()
        )
    }()

    @discardableResult
    mutating func setTaskCompletion(taskID: UUID, isCompleted: Bool) -> Bool {
        let previousState = productionTasks.first(where: { $0.id == taskID })?.isCompleted
            ?? todayTasks.first(where: { $0.id == taskID })?.isCompleted
        guard let previousState else { return false }

        for index in productionTasks.indices where productionTasks[index].id == taskID {
            productionTasks[index].isCompleted = isCompleted
        }
        for index in todayTasks.indices where todayTasks[index].id == taskID {
            todayTasks[index].isCompleted = isCompleted
        }

        if previousState != isCompleted, var focus {
            let delta = isCompleted ? 1 : -1
            focus.completedTaskCount = min(
                focus.taskCount,
                max(0, focus.completedTaskCount + delta)
            )
            self.focus = focus
        }
        generatedAt = Date()
        return true
    }

    func openProductionTasks(in lane: WidgetTaskLane) -> [WidgetTaskSnapshot] {
        productionTasks.filter { task in
            (task.lane ?? .production) == lane && !task.isCompleted
        }
    }
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
    var postCount: Int? = nil

    var id: Date { date }
}

struct WidgetPillarUsageSnapshot: Codable, Equatable, Sendable {
    var segments: [WidgetPillarSegmentSnapshot]
    var leadingPillarName: String
    var leadingPercentage: Int
}

enum WidgetPillarUsagePresentation {
    static func usage(
        for snapshot: AgentCyWidgetSnapshot,
        isPreview: Bool
    ) -> WidgetPillarUsageSnapshot? {
        if let usage = snapshot.pillarUsage {
            return usage
        }
        return isPreview ? AgentCyWidgetSnapshot.preview.pillarUsage : nil
    }
}

struct WidgetPillarSegmentSnapshot: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var colorHex: String
    var percentage: Int

    var id: String { name }
}

enum WidgetPillarBarLayout {
    static let segmentSpacing: CGFloat = 3

    static func segmentWidths(
        percentages: [Int],
        totalWidth: CGFloat,
        minimumWidth: CGFloat = 8
    ) -> [CGFloat] {
        let normalized = percentages.map { max(0, $0) }
        let total = normalized.reduce(0, +)
        guard total > 0, !normalized.isEmpty else { return [] }

        let gapWidth = segmentSpacing * CGFloat(max(0, normalized.count - 1))
        let availableWidth = max(0, totalWidth - gapWidth)
        let reservedWidth = min(availableWidth, minimumWidth * CGFloat(normalized.count))
        let minimumPerSegment = reservedWidth / CGFloat(normalized.count)
        let proportionalWidth = max(0, availableWidth - reservedWidth)

        return normalized.map { percentage in
            minimumPerSegment + proportionalWidth * CGFloat(percentage) / CGFloat(total)
        }
    }
}

/// Legacy fields carry the pre-goal posted-vs-planned week math so installed
/// widget binaries keep decoding; new installs read the goal fields and fall
/// back to legacy rendering when a stale snapshot predates them.
struct WidgetConsistencySnapshot: Codable, Equatable, Sendable {
    var completedWeeks: [Bool]
    var streak: Int
    var currentPostedCount: Int
    var currentPlannedCount: Int
    var days: [WidgetConsistencyDaySnapshot]? = nil
    var postedDayCount: Int? = nil
    var goal: Int? = nil
}

struct WidgetConsistencyDaySnapshot: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var hasPost: Bool

    var id: Date { date }
}

/// Resolves what the consistency tile renders. Goal-aware snapshots mirror the
/// in-app card; snapshots written before the goal fields keep the legacy
/// posted-vs-planned tile; production never substitutes preview data.
enum WidgetConsistencyPresentation {
    struct DayMarker: Equatable, Identifiable {
        let date: Date
        let symbol: String
        let hasPost: Bool
        let isToday: Bool

        var id: Date { date }
    }

    enum Mode: Equatable {
        case unset
        case goal(days: [DayMarker], postedDayCount: Int, goal: Int, goalMet: Bool, streak: Int)
        case legacy(WidgetConsistencySnapshot)
    }

    static func mode(
        for snapshot: AgentCyWidgetSnapshot,
        isPreview: Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Mode {
        let consistency = snapshot.consistency
            ?? (isPreview ? AgentCyWidgetSnapshot.preview.consistency : nil)
        guard let consistency else { return .unset }
        guard let days = consistency.days, let postedDayCount = consistency.postedDayCount else {
            return .legacy(consistency)
        }
        guard let goal = consistency.goal else { return .unset }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let markers = days.map { day in
            DayMarker(
                date: day.date,
                symbol: symbols[calendar.component(.weekday, from: day.date) - 1],
                hasPost: day.hasPost,
                isToday: calendar.isDate(day.date, inSameDayAs: now)
            )
        }
        return .goal(
            days: markers,
            postedDayCount: postedDayCount,
            goal: goal,
            goalMet: postedDayCount >= goal,
            streak: consistency.streak
        )
    }
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

    static func delete(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) {
        defaults?.removeObject(forKey: AgentCyWidgetShared.snapshotKey)
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
    case pillars
    case ideaBank
    case quickIdea
    case quickPost
    case quickTask
    case voiceSpark
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
        case .pillars:
            components.host = "pillars"
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
        case .voiceSpark:
            components.host = "voice-spark"
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
        case "pillars":
            self = .pillars
        case "idea-bank":
            self = .ideaBank
        case "voice-spark":
            self = .voiceSpark
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
