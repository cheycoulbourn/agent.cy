import Foundation

struct DailyFocusTaskTemplateDefinition: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var focusKind: DailyFocusKind
    var title: String
    var priority: TaskPriority
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        focusKind: DailyFocusKind,
        title: String,
        priority: TaskPriority = .none,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.focusKind = focusKind
        self.title = title
        self.priority = priority.normalized
        self.sortOrder = sortOrder
    }
}

enum DailyFocusTaskDefaults {
    static func definitions(for kinds: [DailyFocusKind]) -> [DailyFocusTaskTemplateDefinition] {
        var sortOrder = 0
        return kinds.flatMap { kind in
            titles(for: kind).map { title in
                defer { sortOrder += 1 }
                return DailyFocusTaskTemplateDefinition(
                    focusKind: kind,
                    title: title,
                    sortOrder: sortOrder
                )
            }
        }
    }

    static func addingDefaults(
        for kind: DailyFocusKind,
        to definitions: [DailyFocusTaskTemplateDefinition]
    ) -> [DailyFocusTaskTemplateDefinition] {
        guard !definitions.contains(where: { $0.focusKind == kind }) else { return definitions }
        let startingOrder = (definitions.map(\.sortOrder).max() ?? -1) + 1
        let additions = self.definitions(for: [kind]).enumerated().map { index, definition in
            var value = definition
            value.sortOrder = startingOrder + index
            return value
        }
        return definitions + additions
    }

    /// Returns revised defaults only when the complete stored set still matches
    /// the previous built-ins. IDs are retained so open generated occurrences
    /// can update in place during recurrence reconciliation.
    static func migratedLegacyDefaultsIfUntouched(
        _ definitions: [DailyFocusTaskTemplateDefinition],
        for kinds: [DailyFocusKind]
    ) -> [DailyFocusTaskTemplateDefinition]? {
        let uniqueKinds = kinds.reduce(into: [DailyFocusKind]()) { values, kind in
            if !values.contains(kind) { values.append(kind) }
        }
        let legacy = legacyDefinitions(for: uniqueKinds)
        guard definitions.count == legacy.count,
              zip(definitions, legacy).allSatisfy({ pair in
                  pair.0.focusKind == pair.1.focusKind &&
                      pair.0.title == pair.1.title &&
                      pair.0.priority.normalized == .none
              }) else {
            return nil
        }

        var migrated: [DailyFocusTaskTemplateDefinition] = []
        var sortOrder = 0
        for kind in uniqueKinds {
            let existingForKind = definitions.filter { $0.focusKind == kind }
            for (index, title) in titles(for: kind).enumerated() {
                migrated.append(DailyFocusTaskTemplateDefinition(
                    id: existingForKind.indices.contains(index) ? existingForKind[index].id : UUID(),
                    focusKind: kind,
                    title: title,
                    priority: .none,
                    sortOrder: sortOrder
                ))
                sortOrder += 1
            }
        }
        return migrated
    }

    private static func titles(for kind: DailyFocusKind) -> [String] {
        switch kind {
        case .planning:
            ["Review your backlog", "Plan around this week’s pillars", "Structure and schedule your next post"]
        case .scripting:
            ["Draft the hook", "Write the script or outline", "Write the caption and call to action"]
        case .filming:
            ["Prep your setup and shot list", "Record the planned content and B-roll"]
        case .editing:
            ["Sort the footage", "Edit every planned post", "Export and organize the final files"]
        case .publishing, .posting:
            ["Review the final post", "Finish the caption, cover, and posting details", "Schedule or publish the post"]
        case .community:
            ["Reply to comments and messages", "Engage with your audience and creator community", "Save useful questions or feedback as ideas"]
        case .businessAdmin, .admin:
            ["Review email and partnerships", "Handle contracts, invoices, and payments", "Follow up on open opportunities"]
        case .custom:
            []
        }
    }

    private static func legacyDefinitions(for kinds: [DailyFocusKind]) -> [DailyFocusTaskTemplateDefinition] {
        var sortOrder = 0
        return kinds.flatMap { kind in
            legacyTitles(for: kind).map { title in
                defer { sortOrder += 1 }
                return DailyFocusTaskTemplateDefinition(
                    focusKind: kind,
                    title: title,
                    sortOrder: sortOrder
                )
            }
        }
    }

    private static func legacyTitles(for kind: DailyFocusKind) -> [String] {
        switch kind {
        case .planning:
            ["Review your idea bank", "Choose what to make next"]
        case .scripting:
            ["Draft hooks and outlines", "Finish the next script"]
        case .filming:
            ["Prep your filming setup", "Record planned content"]
        case .editing:
            ["Edit the next post", "Add captions and finishing touches"]
        case .publishing, .posting:
            ["Finalize the caption and cover", "Schedule or publish the post"]
        case .community:
            ["Reply to comments and messages", "Engage with your community"]
        case .businessAdmin, .admin:
            ["Review creator admin", "Handle the next business task"]
        case .custom:
            []
        }
    }
}

struct ResolvedDailyFocus {
    let kinds: [DailyFocusKind]
    let title: String
    let note: String
    let durationMinutes: Int?
    let time: Date?
    let templateEntryID: UUID?
}

struct DailyFocusTaskAssignment: Hashable {
    let date: Date
    let title: String
    let taskKind: CreatorTaskKind
    let templateEntryID: UUID?
}

enum DailyFocusResolver {
    static func resolve(
        date: Date,
        templates: [DailyFocusTemplateEntry],
        overrides: [DailyFocusOverride],
        calendar: Calendar = .current
    ) -> ResolvedDailyFocus? {
        if let override = overrides.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            guard !override.isCleared else { return nil }
            let kinds = normalizedKinds(
                primary: override.kind,
                secondary: override.secondaryKind,
                storedTitle: override.title
            )
            return ResolvedDailyFocus(
                kinds: kinds,
                title: resolvedTitle(storedTitle: override.title, kinds: kinds),
                note: resolvedNote(
                    storedNote: override.note,
                    kinds: kinds,
                    ignoresStoredNote: usesLegacyKind(override.kind, override.secondaryKind)
                ),
                durationMinutes: override.durationMinutes,
                time: time(minutes: override.startMinutesFromMidnight, date: date, calendar: calendar),
                templateEntryID: override.templateEntryID
            )
        }

        guard let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: date)),
              let template = templates.first(where: { $0.weekday == weekday && $0.isActive }) else {
            return nil
        }

        let kinds = normalizedKinds(
            primary: template.kind,
            secondary: template.secondaryKind,
            storedTitle: template.title
        )
        return ResolvedDailyFocus(
            kinds: kinds,
            title: resolvedTitle(storedTitle: template.title, kinds: kinds),
            note: resolvedNote(
                storedNote: template.note,
                kinds: kinds,
                ignoresStoredNote: usesLegacyKind(template.kind, template.secondaryKind)
            ),
            durationMinutes: template.durationMinutes,
            time: time(minutes: template.startMinutesFromMidnight, date: date, calendar: calendar),
            templateEntryID: template.id
        )
    }

    static func normalizedKinds(
        primary: DailyFocusKind,
        secondary: DailyFocusKind?,
        storedTitle: String
    ) -> [DailyFocusKind] {
        let inferred = inferredKinds(from: storedTitle)
        var result: [DailyFocusKind] = []

        for kind in [primary, secondary].compactMap({ $0 }) {
            let candidates: [DailyFocusKind]
            switch kind {
            case .custom:
                candidates = inferred
            case .posting:
                candidates = [.publishing]
            case .admin:
                candidates = [.businessAdmin]
            default:
                candidates = [kind]
            }

            for candidate in candidates where !result.contains(candidate) {
                result.append(candidate)
                if result.count == 2 { return result }
            }
        }
        return result
    }

    private static func resolvedTitle(storedTitle: String, kinds: [DailyFocusKind]) -> String {
        if kinds.isEmpty {
            let trimmed = storedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Rest" : trimmed
        }
        return DailyFocusKind.combinedTitle(kinds)
    }

    private static func resolvedNote(
        storedNote: String,
        kinds: [DailyFocusKind],
        ignoresStoredNote: Bool
    ) -> String {
        let trimmed = storedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || ignoresStoredNote ? DailyFocusKind.combinedDirective(kinds) : trimmed
    }

    private static func usesLegacyKind(_ primary: DailyFocusKind, _ secondary: DailyFocusKind?) -> Bool {
        [primary, secondary].compactMap { $0 }.contains { [.custom, .posting, .admin].contains($0) }
    }

    private static func inferredKinds(from title: String) -> [DailyFocusKind] {
        let value = title.lowercased()
        let keywords: [(DailyFocusKind, [String])] = [
            (.planning, ["planning", "plan"]),
            (.scripting, ["scripting", "script"]),
            (.filming, ["filming", "film", "record"]),
            (.editing, ["editing", "edit"]),
            (.publishing, ["publishing", "publish", "posting", "post"]),
            (.community, ["community", "engage"]),
            (.businessAdmin, ["business", "admin"]),
        ]

        return keywords.compactMap { kind, terms -> (DailyFocusKind, Int)? in
            let position = terms.compactMap { term in
                value.range(of: term).map { value.distance(from: value.startIndex, to: $0.lowerBound) }
            }.min()
            return position.map { (kind, $0) }
        }
        .sorted { $0.1 < $1.1 }
        .prefix(2)
        .map { $0.0 }
    }

    private static func time(minutes: Int?, date: Date, calendar: Calendar) -> Date? {
        guard let minutes else { return nil }
        return calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: date
        )
    }
}

struct FocusDayRecommendation: Equatable {
    let date: Date
    let focusTitle: String
}

enum DailyFocusRecommendation {
    static func nextDate(
        for taskKind: CreatorTaskKind,
        templates: [DailyFocusTemplateEntry],
        overrides: [DailyFocusOverride],
        after date: Date,
        calendar: Calendar = .current,
        searchDayCount: Int = 21
    ) -> FocusDayRecommendation? {
        let start = calendar.startOfDay(for: date)

        for dayOffset in 0..<searchDayCount {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start),
                  let focus = DailyFocusResolver.resolve(
                      date: day,
                      templates: templates,
                      overrides: overrides,
                      calendar: calendar
                  ),
                  focus.kinds.contains(where: { $0.taskKind == taskKind }) else {
                continue
            }

            let recommendedDate = focus.time
                ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
                ?? day
            return FocusDayRecommendation(date: recommendedDate, focusTitle: focus.title)
        }

        return nil
    }
}
