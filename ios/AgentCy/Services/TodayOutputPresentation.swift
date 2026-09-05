enum TodayOutputSection: Equatable {
    case drafted
    case inProgress
    case goingLive
}

enum TodayOutputPresentation {
    static func section(
        outputStatus: PlatformOutputStatus,
        briefStatus: BriefStatus?
    ) -> TodayOutputSection {
        if briefStatus == .developing {
            return .inProgress
        }
        if outputStatus == .draft || briefStatus == .spark {
            return .drafted
        }
        return .goingLive
    }
}
