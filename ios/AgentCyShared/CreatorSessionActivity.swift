import Foundation

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents
#endif

/// Keeps the unfinished Creator Session implementation available for iteration
/// without exposing it in shipping phone or desktop surfaces.
enum CreatorSessionFeatureAvailability {
    static let isEnabled = false
}

enum CreatorSessionMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case planning
    case writing
    case filming
    case editing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planning: "Plan"
        case .writing: "Write"
        case .filming: "Film"
        case .editing: "Edit"
        }
    }

    var systemImage: String {
        switch self {
        case .planning: "list.bullet.clipboard"
        case .writing: "text.cursor"
        case .filming: "video.fill"
        case .editing: "slider.horizontal.3"
        }
    }
}

enum CreatorSessionStyle: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case pomodoro
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pomodoro: "Pomodoro"
        case .custom: "Custom timer"
        }
    }

    var detail: String {
        switch self {
        case .pomodoro: "Focus rounds with breaks"
        case .custom: "Set your own hours and minutes"
        }
    }
}

enum CreatorSessionPhase: String, Codable, Hashable, Sendable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

enum CreatorSessionTimerTheme: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case quietRing
    case splitDial
    case focusConsole

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quietRing: "Quiet Ring"
        case .splitDial: "Split Dial"
        case .focusConsole: "Focus Console"
        }
    }

    var detail: String {
        switch self {
        case .quietRing: "Calm and minimal"
        case .splitDial: "Focused with progress details"
        case .focusConsole: "Structured and information-rich"
        }
    }
}

enum CreatorSessionPreferences {
    static let timerThemeStorageKey = "agentcy.creatorSession.defaultTimerTheme.v1"
}

enum CreatorSessionPresentationPolicy {
    static func shouldResetScroll(previousSessionID: String?, currentSessionID: String?) -> Bool {
        previousSessionID != currentSessionID
            && (previousSessionID != nil || currentSessionID != nil)
    }
}

struct CreatorSessionPlan: Codable, Equatable, Sendable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var rounds: Int = 4
    var longBreakMinutes: Int = 15

    var plannedDurationMinutes: Int {
        max(1, focusMinutes) * max(1, rounds)
            + max(0, shortBreakMinutes) * max(0, rounds - 1)
    }
}

struct ActiveCreatorSessionRecord: Codable, Equatable, Sendable {
    var sessionID: String
    /// Optional creator-authored log. The linked post title is stored separately.
    var title: String
    /// `mode` remains the primary mode for backward compatibility and compact surfaces.
    var mode: CreatorSessionMode
    var modes: [CreatorSessionMode]
    var startedAt: Date
    /// The end of the current interval, not the end of the full Pomodoro plan.
    var endDate: Date
    var durationMinutes: Int
    var linkedPostID: UUID?
    var linkedPostTitle: String?
    var style: CreatorSessionStyle
    var phase: CreatorSessionPhase
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var totalRounds: Int
    var currentRound: Int
    var completedFocusRounds: Int
    var isPaused: Bool
    var pausedRemainingSeconds: Int?
    var accentColorHex: String?
    var timerTheme: CreatorSessionTimerTheme

    init(
        sessionID: String,
        title: String,
        mode: CreatorSessionMode,
        modes: [CreatorSessionMode]? = nil,
        startedAt: Date,
        endDate: Date,
        durationMinutes: Int,
        linkedPostID: UUID? = nil,
        linkedPostTitle: String? = nil,
        style: CreatorSessionStyle = .custom,
        phase: CreatorSessionPhase = .focus,
        focusMinutes: Int? = nil,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        totalRounds: Int = 1,
        currentRound: Int = 1,
        completedFocusRounds: Int = 0,
        isPaused: Bool = false,
        pausedRemainingSeconds: Int? = nil,
        accentColorHex: String? = nil,
        timerTheme: CreatorSessionTimerTheme = .quietRing
    ) {
        self.sessionID = sessionID
        self.title = title
        self.modes = Self.normalizedModes(modes, fallback: mode)
        self.mode = self.modes.first ?? mode
        self.startedAt = startedAt
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.linkedPostID = linkedPostID
        self.linkedPostTitle = linkedPostTitle
        self.style = style
        self.phase = phase
        self.focusMinutes = focusMinutes ?? durationMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.totalRounds = totalRounds
        self.currentRound = currentRound
        self.completedFocusRounds = completedFocusRounds
        self.isPaused = isPaused
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.accentColorHex = accentColorHex
        self.timerTheme = timerTheme
    }

    var displayTitle: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? "\(modeSummary) session" : cleanTitle
    }

    var modeSummary: String {
        modes.map(\.title).joined(separator: " + ")
    }

    var currentIntervalMinutes: Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    func remainingSeconds(at date: Date) -> Int {
        if isPaused {
            return max(0, pausedRemainingSeconds ?? 0)
        }
        return max(0, Int(endDate.timeIntervalSince(date).rounded(.up)))
    }

    func progress(at date: Date) -> Double {
        let duration = max(1, currentIntervalMinutes * 60)
        let remaining = min(duration, remainingSeconds(at: date))
        return min(1, max(0, Double(duration - remaining) / Double(duration)))
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, title, mode, modes, startedAt, endDate, durationMinutes
        case linkedPostID, linkedPostTitle, style, phase, focusMinutes
        case shortBreakMinutes, longBreakMinutes, totalRounds, currentRound
        case completedFocusRounds, isPaused, pausedRemainingSeconds, accentColorHex, timerTheme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        title = try container.decode(String.self, forKey: .title)
        let legacyMode = try container.decodeIfPresent(CreatorSessionMode.self, forKey: .mode) ?? .filming
        modes = Self.normalizedModes(
            try container.decodeIfPresent([CreatorSessionMode].self, forKey: .modes),
            fallback: legacyMode
        )
        mode = modes.first ?? legacyMode
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endDate = try container.decode(Date.self, forKey: .endDate)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        linkedPostID = try container.decodeIfPresent(UUID.self, forKey: .linkedPostID)
        linkedPostTitle = try container.decodeIfPresent(String.self, forKey: .linkedPostTitle)
        style = try container.decodeIfPresent(CreatorSessionStyle.self, forKey: .style) ?? .custom
        phase = try container.decodeIfPresent(CreatorSessionPhase.self, forKey: .phase) ?? .focus
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? durationMinutes
        shortBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        longBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        totalRounds = try container.decodeIfPresent(Int.self, forKey: .totalRounds) ?? 1
        currentRound = try container.decodeIfPresent(Int.self, forKey: .currentRound) ?? 1
        completedFocusRounds = try container.decodeIfPresent(Int.self, forKey: .completedFocusRounds) ?? 0
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        pausedRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .pausedRemainingSeconds)
        accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex)
        timerTheme = try container.decodeIfPresent(CreatorSessionTimerTheme.self, forKey: .timerTheme) ?? .quietRing
    }

    private static func normalizedModes(
        _ modes: [CreatorSessionMode]?,
        fallback: CreatorSessionMode
    ) -> [CreatorSessionMode] {
        let requested = Set(modes ?? [fallback])
        let ordered = CreatorSessionMode.allCases.filter(requested.contains)
        return ordered.isEmpty ? [fallback] : ordered
    }
}

struct CreatorSessionLog: Codable, Equatable, Identifiable, Sendable {
    var id: String { sessionID }
    var sessionID: String
    var title: String
    var mode: CreatorSessionMode
    var modes: [CreatorSessionMode]
    var startedAt: Date
    var endedAt: Date
    var plannedDurationMinutes: Int
    var linkedPostID: UUID?
    var linkedPostTitle: String?
    var style: CreatorSessionStyle
    var completedFocusRounds: Int
    var timerTheme: CreatorSessionTimerTheme

    init(session: ActiveCreatorSessionRecord, endedAt: Date) {
        self.sessionID = session.sessionID
        self.title = session.title
        self.mode = session.mode
        self.modes = session.modes
        self.startedAt = session.startedAt
        self.endedAt = max(session.startedAt, endedAt)
        self.plannedDurationMinutes = session.durationMinutes
        self.linkedPostID = session.linkedPostID
        self.linkedPostTitle = session.linkedPostTitle
        self.style = session.style
        self.completedFocusRounds = session.completedFocusRounds
        self.timerTheme = session.timerTheme
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, title, mode, modes, startedAt, endedAt, plannedDurationMinutes
        case linkedPostID, linkedPostTitle, style, completedFocusRounds, timerTheme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        title = try container.decode(String.self, forKey: .title)
        let legacyMode = try container.decodeIfPresent(CreatorSessionMode.self, forKey: .mode) ?? .filming
        let requestedModes = Set(
            try container.decodeIfPresent([CreatorSessionMode].self, forKey: .modes) ?? [legacyMode]
        )
        modes = CreatorSessionMode.allCases.filter(requestedModes.contains)
        if modes.isEmpty { modes = [legacyMode] }
        mode = modes.first ?? legacyMode
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        plannedDurationMinutes = try container.decode(Int.self, forKey: .plannedDurationMinutes)
        linkedPostID = try container.decodeIfPresent(UUID.self, forKey: .linkedPostID)
        linkedPostTitle = try container.decodeIfPresent(String.self, forKey: .linkedPostTitle)
        style = try container.decodeIfPresent(CreatorSessionStyle.self, forKey: .style) ?? .custom
        completedFocusRounds = try container.decodeIfPresent(Int.self, forKey: .completedFocusRounds) ?? 0
        timerTheme = try container.decodeIfPresent(CreatorSessionTimerTheme.self, forKey: .timerTheme) ?? .quietRing
    }
}

enum CreatorSessionRecordStore {
    private static let key = "agentCy.creatorSession.active.v1"

    static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) -> ActiveCreatorSessionRecord? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActiveCreatorSessionRecord.self, from: data)
    }

    static func save(
        _ session: ActiveCreatorSessionRecord,
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) throws {
        guard let defaults else { throw CreatorSessionRecordStoreError.unavailableAppGroup }
        defaults.set(try JSONEncoder().encode(session), forKey: key)
    }

    static func clear(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) {
        defaults?.removeObject(forKey: key)
    }
}

enum CreatorSessionRecordStoreError: Error {
    case unavailableAppGroup
}

enum CreatorSessionLogStore {
    private static let key = "agentCy.creatorSession.logs.v1"
    private static let historyLimit = 200

    static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) -> [CreatorSessionLog] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CreatorSessionLog].self, from: data)) ?? []
    }

    static func append(
        _ log: CreatorSessionLog,
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) throws {
        guard let defaults else { throw CreatorSessionRecordStoreError.unavailableAppGroup }
        var logs = load(defaults: defaults)
        logs.removeAll { $0.sessionID == log.sessionID }
        logs.insert(log, at: 0)
        if logs.count > historyLimit {
            logs.removeLast(logs.count - historyLimit)
        }
        defaults.set(try JSONEncoder().encode(logs), forKey: key)
    }

    static func clear(
        defaults: UserDefaults? = UserDefaults(suiteName: AgentCyWidgetShared.appGroupIdentifier)
    ) {
        defaults?.removeObject(forKey: key)
    }
}

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
struct CreatorSessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var isFinished: Bool
        var isPaused: Bool
        var remainingSeconds: Int
        var phase: CreatorSessionPhase
        var currentRound: Int
    }

    var sessionID: String
    var title: String
    var mode: CreatorSessionMode
    var style: CreatorSessionStyle
    var startedAt: Date
    var durationMinutes: Int
    var totalRounds: Int
    var linkedPostID: UUID?
    var linkedPostTitle: String?
    var accentColorHex: String?
    var timerTheme: CreatorSessionTimerTheme
}

struct EndCreatorSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Creator Session"
    static let description = IntentDescription("End the active creator session.")
    static let openAppWhenRun = false

    @Parameter(title: "Session")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        let activeRecord = CreatorSessionRecordStore.load()
        for activity in Activity<CreatorSessionAttributes>.activities
        where activity.attributes.sessionID == sessionID {
            let state = CreatorSessionAttributes.ContentState(
                endDate: min(activity.content.state.endDate, Date()),
                isFinished: true,
                isPaused: false,
                remainingSeconds: 0,
                phase: activity.content.state.phase,
                currentRound: activity.content.state.currentRound
            )
            await activity.end(
                ActivityContent(state: state, staleDate: Date()),
                dismissalPolicy: .immediate
            )
        }
        if let activeRecord, activeRecord.sessionID == sessionID {
            try? CreatorSessionLogStore.append(CreatorSessionLog(session: activeRecord, endedAt: Date()))
        }
        CreatorSessionRecordStore.clear()
        return .result()
    }
}
#endif
