import Foundation

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
