import SwiftData
import SwiftUI

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

@MainActor
enum CreatorSessionActivityController {
    static func start(
        title: String,
        modes: [CreatorSessionMode],
        style: CreatorSessionStyle,
        customDurationMinutes: Int,
        plan: CreatorSessionPlan,
        timerTheme: CreatorSessionTimerTheme,
        linkedPostID: UUID? = nil,
        linkedPostTitle: String? = nil,
        accentColorHex: String? = nil,
        now: Date = Date()
    ) async throws -> ActiveCreatorSessionRecord {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPostTitle = linkedPostTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let orderedModes = CreatorSessionMode.allCases.filter(Set(modes).contains)
        let primaryMode = orderedModes.first ?? .filming
        let intervalMinutes = style == .pomodoro ? max(1, plan.focusMinutes) : max(1, customDurationMinutes)
        let plannedMinutes = style == .pomodoro ? plan.plannedDurationMinutes : intervalMinutes
        let record = ActiveCreatorSessionRecord(
            sessionID: UUID().uuidString.lowercased(),
            title: cleanTitle,
            mode: primaryMode,
            modes: orderedModes,
            startedAt: now,
            endDate: now.addingTimeInterval(TimeInterval(intervalMinutes * 60)),
            durationMinutes: plannedMinutes,
            linkedPostID: linkedPostID,
            linkedPostTitle: cleanPostTitle,
            style: style,
            phase: .focus,
            focusMinutes: intervalMinutes,
            shortBreakMinutes: plan.shortBreakMinutes,
            longBreakMinutes: plan.longBreakMinutes,
            totalRounds: style == .pomodoro ? max(1, plan.rounds) : 1,
            accentColorHex: accentColorHex,
            timerTheme: timerTheme
        )

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        for activity in Activity<CreatorSessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
#endif
        try CreatorSessionRecordStore.save(record)
        await requestLiveActivity(for: record)
        return record
    }

    static func togglePause(_ record: ActiveCreatorSessionRecord, now: Date = Date()) async -> ActiveCreatorSessionRecord {
        var updated = record
        if record.isPaused {
            updated.endDate = now.addingTimeInterval(TimeInterval(max(1, record.pausedRemainingSeconds ?? 1)))
            updated.isPaused = false
            updated.pausedRemainingSeconds = nil
        } else {
            updated.pausedRemainingSeconds = record.remainingSeconds(at: now)
            updated.isPaused = true
        }
        await persistAndUpdate(updated)
        return updated
    }

    static func addMinute(_ record: ActiveCreatorSessionRecord, now: Date = Date()) async -> ActiveCreatorSessionRecord {
        var updated = record
        if record.isPaused {
            updated.pausedRemainingSeconds = max(0, record.pausedRemainingSeconds ?? 0) + 60
        } else {
            updated.endDate = max(record.endDate, now).addingTimeInterval(60)
        }
        await persistAndUpdate(updated)
        return updated
    }

    static func advance(_ record: ActiveCreatorSessionRecord, now: Date = Date()) async -> ActiveCreatorSessionRecord? {
        guard record.style == .pomodoro else {
            await end(record, now: now)
            return nil
        }
        var updated = record
        updated.isPaused = false
        updated.pausedRemainingSeconds = nil
        switch record.phase {
        case .focus:
            updated.completedFocusRounds = min(record.totalRounds, record.completedFocusRounds + 1)
            guard updated.completedFocusRounds < record.totalRounds else {
                await end(updated, now: now)
                return nil
            }
            updated.phase = .shortBreak
            updated.endDate = now.addingTimeInterval(TimeInterval(max(1, record.shortBreakMinutes) * 60))
        case .shortBreak, .longBreak:
            updated.currentRound = min(record.totalRounds, record.currentRound + 1)
            updated.phase = .focus
            updated.endDate = now.addingTimeInterval(TimeInterval(max(1, record.focusMinutes) * 60))
        }
        await persistAndUpdate(updated)
        return updated
    }

    static func end(_ record: ActiveCreatorSessionRecord, now: Date = Date()) async {
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        for activity in Activity<CreatorSessionAttributes>.activities where activity.attributes.sessionID == record.sessionID {
            let state = contentState(for: record, finished: true, now: now)
            await activity.end(ActivityContent(state: state, staleDate: now), dismissalPolicy: .immediate)
        }
#endif
        try? CreatorSessionLogStore.append(CreatorSessionLog(session: record, endedAt: now))
        CreatorSessionRecordStore.clear()
    }

    /// Removes any active system or in-app timer while the feature is withheld.
    /// Existing completed logs stay intact so redesign work does not erase history.
    static func retireUnavailableFeature(now: Date = Date()) async {
        let record = CreatorSessionRecordStore.load()
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        for activity in Activity<CreatorSessionAttributes>.activities {
            let state = CreatorSessionAttributes.ContentState(
                endDate: now,
                isFinished: true,
                isPaused: false,
                remainingSeconds: 0,
                phase: activity.content.state.phase,
                currentRound: activity.content.state.currentRound
            )
            await activity.end(
                ActivityContent(state: state, staleDate: now),
                dismissalPolicy: .immediate
            )
        }
#endif
        if let record {
            try? CreatorSessionLogStore.append(CreatorSessionLog(session: record, endedAt: now))
        }
        CreatorSessionRecordStore.clear()
    }

    private static func persistAndUpdate(_ record: ActiveCreatorSessionRecord) async {
        try? CreatorSessionRecordStore.save(record)
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        for activity in Activity<CreatorSessionAttributes>.activities where activity.attributes.sessionID == record.sessionID {
            let state = contentState(for: record, finished: false, now: Date())
            await activity.update(ActivityContent(state: state, staleDate: record.isPaused ? nil : record.endDate))
        }
#endif
    }

    private static func requestLiveActivity(for record: ActiveCreatorSessionRecord) async {
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = CreatorSessionAttributes(
            sessionID: record.sessionID,
            title: record.displayTitle,
            mode: record.mode,
            style: record.style,
            startedAt: record.startedAt,
            durationMinutes: record.durationMinutes,
            totalRounds: record.totalRounds,
            linkedPostID: record.linkedPostID,
            linkedPostTitle: record.linkedPostTitle,
            accentColorHex: record.accentColorHex,
            timerTheme: record.timerTheme
        )
        let state = contentState(for: record, finished: false, now: record.startedAt)
        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: record.endDate),
            pushType: nil
        )
#endif
    }

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private static func contentState(for record: ActiveCreatorSessionRecord, finished: Bool, now: Date) -> CreatorSessionAttributes.ContentState {
        CreatorSessionAttributes.ContentState(
            endDate: finished ? now : record.endDate,
            isFinished: finished,
            isPaused: record.isPaused,
            remainingSeconds: finished ? 0 : record.remainingSeconds(at: now),
            phase: record.phase,
            currentRound: record.currentRound
        )
    }
#endif
}

private enum CreatorSessionPage: Equatable {
    case editor
    case timerTheme(startsSession: Bool)
}

struct CreatorSessionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @AppStorage(CreatorSessionPreferences.timerThemeStorageKey) private var storedTimerTheme = ""

    @State private var selectedModes: Set<CreatorSessionMode> = [.filming]
    @State private var selectedStyle: CreatorSessionStyle = .pomodoro
    @State private var selectedTimerTheme: CreatorSessionTimerTheme?
    @State private var plan = CreatorSessionPlan()
    @State private var durationHours = 0
    @State private var durationMinuteComponent = 45
    @State private var sessionTitle = ""
    @State private var selectedPostID: UUID?
    @State private var requestedPostTitle: String?
    @State private var activeSession: ActiveCreatorSessionRecord?
    @State private var now = Date()
    @State private var isWorking = false
    @State private var isTimerFullScreen = false
    @State private var presentedPage = CreatorSessionPage.editor
    @State private var previewedTimerTheme = CreatorSessionTimerTheme.quietRing
    @State private var errorMessage: String?

    private let onDismiss: (() -> Void)?
    private let hourOptions = Array(0...23)
    private let minuteOptions = Array(0...59)
    private static let scrollAnchor = "creator-session-scroll-top"

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
#if targetEnvironment(macCatalyst)
        desktopBody
            .fullScreenCover(isPresented: $isTimerFullScreen) {
                fullScreenTimerPresentation
            }
#else
        phoneBody
#endif
    }

    private var phoneBody: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    sessionContent
                        .id(Self.scrollAnchor)
                        .padding(.horizontal, AgentLayout.dashboardGutter)
                        .padding(.top, AgentSpacing.x4)
                        .padding(.bottom, AgentSpacing.x12)
                }
                .onChange(of: activeSession?.sessionID) { previousID, currentID in
                    resetSessionScroll(proxy, previousID: previousID, currentID: currentID)
                }
            }
            .background(Color.agentCanvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(Color.agentCanvas)
        .creatorSessionLifecycle(activeSession: $activeSession, now: $now, onAppear: restoreState, onIntervalFinished: advanceSession)
    }

    private var desktopBody: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.agentHairline).frame(height: 1).padding(.horizontal, AgentSpacing.x8)
            ScrollViewReader { proxy in
                ScrollView {
                    sessionContent
                        .id(Self.scrollAnchor)
                        .padding(.horizontal, AgentSpacing.x8)
                        .padding(.top, AgentSpacing.x6)
                        .padding(.bottom, AgentSpacing.x8)
                }
                .onChange(of: activeSession?.sessionID) { previousID, currentID in
                    resetSessionScroll(proxy, previousID: previousID, currentID: currentID)
                }
            }
        }
        .background(Color.agentCanvas)
        .creatorSessionLifecycle(activeSession: $activeSession, now: $now, onAppear: restoreState, onIntervalFinished: advanceSession)
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch presentedPage {
        case .editor:
            if let activeSession { activeContent(activeSession) } else { setupContent }
        case .timerTheme(let startsSession):
            timerThemeGallery(startsSession: startsSession)
        }
    }

    private var header: some View {
        ZStack {
            MetaLabel(presentedPage == .editor ? "Creator Session" : "Timer Appearance")
            HStack {
                if presentedPage == .editor {
                    closeButton
                } else {
                    headerIconButton(icon: .back, accessibilityLabel: "Back to Creator Session") {
                        presentedPage = .editor
                    }
                }
                Spacer()
                if presentedPage == .editor, activeSession != nil {
                    Button("End") { endSession() }
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentDestructive)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(AgentPressButtonStyle())
                }
            }
        }
        .frame(height: AgentQuickAddLayout.headerHeight)
        .padding(.top, AgentQuickAddLayout.headerTopPadding)
        .padding(.horizontal, AgentSpacing.x5)
    }

    private var closeButton: some View {
        headerIconButton(icon: .close, accessibilityLabel: "Close Creator Session", action: close)
    }

    @ViewBuilder
    private func headerIconButton(
        icon: AgentIcon,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
#if targetEnvironment(macCatalyst)
        Button(action: action) {
            AgentIconView(icon, size: 16)
                .foregroundStyle(Color.agentText)
                .frame(width: 44, height: 44)
                .background(Color.agentSurface, in: .circle)
                .overlay { Circle().stroke(Color.agentHairline, lineWidth: 1) }
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
#else
        AgentCircularGlassIconButton(icon: icon, accessibilityLabel: accessibilityLabel, action: action)
#endif
    }

    @ViewBuilder
    private var fullScreenTimerPresentation: some View {
        if let activeSession {
            fullScreenTimer(activeSession)
        } else {
            Color.agentCanvas
                .ignoresSafeArea()
                .onAppear { isTimerFullScreen = false }
        }
    }

    private func fullScreenTimer(_ session: ActiveCreatorSessionRecord) -> some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 2) {
                        MetaLabel("Creator Session")
                        Text(phaseLabel(session))
                            .font(.agentMetadata.weight(.semibold))
                            .foregroundStyle(Color.agentSecondary)
                    }
                    HStack {
                        headerIconButton(
                            icon: .back,
                            accessibilityLabel: "Exit full screen"
                        ) {
                            isTimerFullScreen = false
                        }
                        Spacer()
                        Button("End") { endSession() }
                            .font(.agentSubtext.weight(.semibold))
                            .foregroundStyle(Color.agentDestructive)
                            .frame(minWidth: 44, minHeight: 44)
                            .buttonStyle(AgentPressButtonStyle())
                    }
                }
                .frame(height: AgentQuickAddLayout.headerHeight)
                .padding(.top, AgentQuickAddLayout.headerTopPadding)
                .padding(.horizontal, AgentSpacing.x5)

                Rectangle()
                    .fill(Color.agentHairline)
                    .frame(height: 1)

                    HStack(alignment: .top, spacing: AgentSpacing.x5) {
                        desktopFullScreenTimerStage(session)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        desktopFullScreenSessionRail(session)
                            .frame(width: min(320, max(260, proxy.size.width * 0.24)))
                    }
                    .padding(AgentSpacing.x6)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Color.agentCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(Color.agentCanvas)
        .interactiveDismissDisabled()
    }

    private func desktopFullScreenTimerStage(_ session: ActiveCreatorSessionRecord) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                desktopFullScreenTheme(session, availableSize: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }

            Rectangle()
                .fill(Color.agentHairline)
                .frame(height: 1)

            timerControls(
                session,
                offersFullScreen: false,
                offersEndSession: false
            )
            .frame(maxWidth: 620)
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.vertical, AgentSpacing.x4)
        }
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func desktopFullScreenTheme(
        _ session: ActiveCreatorSessionRecord,
        availableSize: CGSize
    ) -> some View {
        let dialSize = min(400, max(250, min(availableSize.width * 0.56, availableSize.height * 0.62)))

        switch session.timerTheme {
        case .quietRing:
            VStack(spacing: AgentSpacing.x4) {
                Text(session.phase.title.uppercased())
                    .font(.agentMetadata.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.agentSecondary)
                TimerRing(
                    progress: session.progress(at: now),
                    color: timerAccent(session),
                    size: dialSize,
                    lineWidth: 9
                ) {
                    timerDigits(session, size: min(86, dialSize * 0.21))
                    Text(timerSubtitle(session))
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
                if session.style == .pomodoro {
                    Text(nextIntervalLabel(session))
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AgentSpacing.x6)

        case .splitDial:
            VStack(spacing: AgentSpacing.x4) {
                HStack(spacing: AgentSpacing.x2) {
                    Circle().fill(timerAccent(session)).frame(width: 8, height: 8)
                    Text(phaseLabel(session).uppercased())
                        .font(.agentMetadata.weight(.semibold))
                        .tracking(1.3)
                        .foregroundStyle(timerAccent(session))
                }
                TimerRing(
                    progress: session.progress(at: now),
                    color: timerAccent(session),
                    size: dialSize,
                    lineWidth: 11,
                    trackColor: timerAccent(session).opacity(0.16)
                ) {
                    timerDigits(session, size: min(82, dialSize * 0.20))
                    Text(timerSubtitle(session))
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
                Text(session.displayTitle)
                    .font(.agentHeadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 640, maxHeight: .infinity)
            .padding(AgentSpacing.x6)
            .background(timerAccent(session).opacity(0.055))
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(timerAccent(session).opacity(0.20), lineWidth: 1)
            }
            .padding(AgentSpacing.x6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .focusConsole:
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        Text(session.phase.title.uppercased())
                            .font(.agentMetadata.weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(timerAccent(session))
                        Text(consoleHeadline(session))
                            .font(.agentDisplay)
                    }
                    Spacer()
                    Text(session.style == .pomodoro ? "\(session.currentRound)/\(session.totalRounds)" : "1/1")
                        .font(.agentHeadline.monospacedDigit())
                }

                Spacer(minLength: AgentSpacing.x3)

                timerDigits(session, size: min(112, max(76, availableSize.width * 0.12)))
                Text(timerSubtitle(session))
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(timerAccent(session).opacity(0.14))
                        Capsule()
                            .fill(timerAccent(session))
                            .frame(width: max(8, proxy.size.width * session.progress(at: now)))
                    }
                }
                .frame(height: 7)

                Text(consoleSupportingCopy(session))
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 680, maxHeight: 520, alignment: .leading)
            .padding(AgentSpacing.x8)
            .background(timerAccent(session).opacity(0.055))
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(timerAccent(session).opacity(0.20), lineWidth: 1)
            }
            .padding(AgentSpacing.x6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func desktopFullScreenSessionRail(_ session: ActiveCreatorSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Session")
                Text(session.displayTitle)
                    .font(.agentTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Color.agentHairline).frame(height: 1)

            if let linkedPostTitle = session.linkedPostTitle?.nonEmpty {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    MetaLabel("Linked post")
                    HStack(alignment: .top, spacing: AgentSpacing.x2) {
                        AgentIconView(.link, size: 15)
                            .foregroundStyle(Color.agentSecondary)
                        Text(linkedPostTitle)
                            .font(.agentSubtext.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Rectangle().fill(Color.agentHairline).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                MetaLabel("Modes")
                ForEach(session.modes) { mode in
                    HStack(spacing: AgentSpacing.x2) {
                        AgentIconView(mode.agentIcon, size: 15)
                        Text(mode.title).font(.agentSubtext.weight(.semibold))
                    }
                    .foregroundStyle(Color.agentText)
                }
            }

            Rectangle().fill(Color.agentHairline).frame(height: 1)

            VStack(spacing: AgentSpacing.x3) {
                fullScreenRailMetric("Started", session.startedAt.formatted(date: .omitted, time: .shortened))
                fullScreenRailMetric("Elapsed", elapsedLabel(session))
                if session.style == .pomodoro {
                    fullScreenRailMetric("Next", nextMetricLabel(session))
                    fullScreenRailMetric("Round", "\(session.currentRound) of \(session.totalRounds)")
                }
            }

            Spacer(minLength: AgentSpacing.x3)

            Text("You can leave this view. The session keeps running and stays available from the floating timer.")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AgentSpacing.x5)
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
    }

    private func fullScreenRailMetric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
            Spacer(minLength: AgentSpacing.x2)
            Text(value)
                .font(.agentSubtext.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text("Protect the next block.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                Text("Choose a rhythm, link the work if you want, and leave yourself an optional session note.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            styleSelector
            setupConfiguration
            optionalLogField
            if let errorMessage {
                Text(errorMessage).font(.agentSubtext).foregroundStyle(Color.agentSecondary)
            }
            startButton
            timerAppearanceSettingsButton
        }
    }

    private var styleSelector: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Session style")
            HStack(spacing: AgentSpacing.x3) {
                ForEach(CreatorSessionStyle.allCases) { style in
                    selectionButton(title: style.title, detail: style.detail, selected: selectedStyle == style) {
                        selectedStyle = style
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var setupConfiguration: some View {
#if targetEnvironment(macCatalyst)
        HStack(alignment: .top, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                modeSelector
                durationConfiguration
            }
            .frame(maxWidth: .infinity)
            linkedPostPicker.frame(width: 270)
        }
#else
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            modeSelector
            durationConfiguration
            linkedPostPicker
        }
#endif
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel("Modes")
                Spacer()
                Text("Choose one or more")
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
#if targetEnvironment(macCatalyst)
            HStack(spacing: AgentSpacing.x2) {
                ForEach(CreatorSessionMode.allCases) { mode in modeButton(mode) }
            }
#else
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AgentSpacing.x3) {
                ForEach(CreatorSessionMode.allCases) { mode in modeButton(mode) }
            }
#endif
        }
    }

    @ViewBuilder
    private var durationConfiguration: some View {
        if selectedStyle == .custom {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                HStack(alignment: .firstTextBaseline) {
                    MetaLabel("Length")
                    Spacer()
                    Text(durationSummary)
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentSecondary)
                }
                durationPicker
            }
        } else {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                MetaLabel("Pomodoro rhythm")
                HStack(spacing: 0) {
                    rhythmMetric(value: "\(plan.focusMinutes)", label: "Focus")
                    metricDivider
                    rhythmMetric(value: "\(plan.shortBreakMinutes)", label: "Break")
                    metricDivider
                    rhythmMetric(value: "\(plan.rounds)", label: "Rounds")
                }
                .frame(minHeight: 70)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.card))
                .overlay { RoundedRectangle(cornerRadius: AgentRadius.card).stroke(Color.agentBorder, lineWidth: 1) }
            }
        }
    }

    private var metricDivider: some View {
        Rectangle().fill(Color.agentHairline).frame(width: 1, height: 34)
    }

    private func rhythmMetric(value: String, label: String) -> some View {
        VStack(spacing: AgentSpacing.x1) {
            Text(value).font(.agentHeadline.monospacedDigit())
            Text(label).font(.agentMetadata).foregroundStyle(Color.agentSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            Picker("Hours", selection: $durationHours) {
                ForEach(hourOptions, id: \.self) { Text("\($0) hr").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            Rectangle().fill(Color.agentHairline).frame(width: 1, height: 92)
            Picker("Minutes", selection: $durationMinuteComponent) {
                ForEach(minuteOptions, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 132)
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: AgentRadius.panel))
        .overlay { RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session duration")
    }

    private var linkedPostPicker: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("Linked post")
            Menu {
                Button("No linked post") {
                    selectedPostID = nil
                    requestedPostTitle = nil
                }
                if !availablePosts.isEmpty { Divider() }
                ForEach(availablePosts) { post in
                    Button {
                        selectedPostID = post.id
                        requestedPostTitle = nil
                    } label: {
                        HStack {
                            Text(post.title)
                            if selectedPostID == post.id {
                                Spacer()
                                AgentIconView(.check, size: 12)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AgentSpacing.x3) {
                    AgentIconView(.link, size: 16)
                        .foregroundStyle(Color.agentSecondary)
                    Text(selectedPostTitle ?? "No linked post")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentText)
                        .lineLimit(2)
                    Spacer(minLength: AgentSpacing.x2)
                    AgentIconView(.expand, size: 12)
                        .foregroundStyle(Color.agentSecondary)
                }
                .padding(.horizontal, AgentSpacing.x4)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay { RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            Text("Completed time is logged against the linked post.")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optionalLogField: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
            MetaLabel("What are you working on? · Optional")
            TextField("Add a note for this session", text: $sessionTitle)
                .font(.agentBody)
                .padding(.horizontal, AgentSpacing.x4)
                .frame(minHeight: 50)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.control))
                .overlay { RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1) }
        }
    }

    private var startButton: some View {
        Button(action: beginStartFlow) {
            HStack(spacing: AgentSpacing.x3) {
                if isWorking {
                    ProgressView().tint(Color.agentText)
                } else {
                    AgentIconView(.play, size: 16).offset(x: 1)
                }
                Text(startButtonTitle).font(.agentHeadline)
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.agentSelectionFill)
            .clipShape(.rect(cornerRadius: AgentRadius.button))
            .overlay { RoundedRectangle(cornerRadius: AgentRadius.button).stroke(Color.agentSelectionIndicator, lineWidth: 1) }
        }
        .buttonStyle(AgentPressButtonStyle())
        .disabled(isWorking || (selectedStyle == .custom && durationMinutes == 0))
    }

    private var startButtonTitle: String {
        if selectedStyle == .pomodoro { return "Start Pomodoro session" }
        return durationMinutes > 0 ? "Start \(durationSummary) session" : "Choose a duration"
    }

    private var timerAppearanceSettingsButton: some View {
        Button {
            openTimerThemeGallery(startsSession: false)
        } label: {
            VStack(spacing: AgentSpacing.x1) {
                AgentIconView(.sliders, size: 16)
                    .frame(width: 44, height: 44)
                    .background(Color.agentSurface, in: .circle)
                    .overlay { Circle().stroke(Color.agentBorder, lineWidth: 1) }
                Text("Timer appearance")
                    .font(.agentMetadata.weight(.semibold))
                    .foregroundStyle(Color.agentSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityLabel("Change default timer appearance")
    }

    private func timerThemeGallery(startsSession: Bool) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text(startsSession ? "Choose how focus feels." : "Choose your default timer.")
                    .font(.agentDisplay)
                    .tracking(-0.64)
                Text("Swipe through all three timer views. This choice only changes the timer itself.")
                    .font(.agentBody)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TabView(selection: $previewedTimerTheme) {
                ForEach(CreatorSessionTimerTheme.allCases) { theme in
                    VStack(spacing: AgentSpacing.x3) {
                        TimerThemeScreenshot(theme: theme, accent: timerPreviewAccent)
                        VStack(spacing: AgentSpacing.x1) {
                            Text(theme.title)
                                .font(.agentTitle.weight(.semibold))
                            Text(theme.detail)
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                        }
                    }
                    .padding(.horizontal, AgentSpacing.x1)
                    .tag(theme)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(theme.title). \(theme.detail)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: timerThemeGalleryHeight)

            HStack(spacing: AgentSpacing.x2) {
                ForEach(CreatorSessionTimerTheme.allCases) { theme in
                    Capsule()
                        .fill(theme == previewedTimerTheme ? Color.agentText : Color.agentHairline)
                        .frame(width: theme == previewedTimerTheme ? 22 : 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: previewedTimerTheme)
            .accessibilityHidden(true)

            Button {
                chooseTimerThemeAndContinue(startsSession: startsSession)
            } label: {
                HStack(spacing: AgentSpacing.x2) {
                    AgentIconView(.check, size: 14)
                    Text(startsSession ? "Use \(previewedTimerTheme.title) and start" : "Set \(previewedTimerTheme.title) as default")
                        .font(.agentHeadline)
                }
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.agentSelectionFill)
                .clipShape(.rect(cornerRadius: AgentRadius.button))
                .overlay {
                    RoundedRectangle(cornerRadius: AgentRadius.button)
                        .stroke(Color.agentSelectionIndicator, lineWidth: 1)
                }
            }
            .buttonStyle(AgentPressButtonStyle())
        }
    }

    private var timerThemeGalleryHeight: CGFloat {
#if targetEnvironment(macCatalyst)
        420
#else
        390
#endif
    }

    private func modeButton(_ mode: CreatorSessionMode) -> some View {
        let selected = selectedModes.contains(mode)
        return Button { toggleMode(mode) } label: {
            HStack(spacing: AgentSpacing.x2) {
                AgentIconView(mode.agentIcon, size: 16)
                Text(mode.title)
                Spacer(minLength: AgentSpacing.x1)
                if selected { AgentIconView(.check, size: 12) }
            }
            .font(.agentSubtext.weight(.semibold))
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x3)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? Color.agentSelectionFill : Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.button))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.button)
                    .stroke(selected ? Color.agentSelectionIndicator : Color.agentBorder, lineWidth: selected ? 1.25 : 1)
            }
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectionButton(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                HStack {
                    Text(title).font(.agentSubtext.weight(.semibold))
                    Spacer()
                    if selected { AgentIconView(.check, size: 12) }
                }
                Text(detail)
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(2)
            }
            .foregroundStyle(Color.agentText)
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(selected ? Color.agentSelectionFill : Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.button))
            .overlay {
                RoundedRectangle(cornerRadius: AgentRadius.button)
                    .stroke(selected ? Color.agentSelectionIndicator : Color.agentBorder, lineWidth: selected ? 1.25 : 1)
            }
        }
        .buttonStyle(AgentPressButtonStyle())
    }

    private func activeContent(_ session: ActiveCreatorSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            switch session.timerTheme {
            case .quietRing: quietRingTimer(session)
            case .splitDial: splitDialTimer(session)
            case .focusConsole: focusConsoleTimer(session)
            }
            sessionModesLine(session)
            timerControls(session)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: session.phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: session.isPaused)
    }

    private func quietRingTimer(_ session: ActiveCreatorSessionRecord) -> some View {
        VStack(spacing: AgentSpacing.x5) {
            Text(phaseLabel(session).uppercased())
                .font(.agentMetadata.weight(.semibold))
                .tracking(1.3)
                .foregroundStyle(Color.agentSecondary)
            TimerRing(
                progress: session.progress(at: now),
                color: timerAccent(session),
                size: timerRingSize,
                lineWidth: 9
            ) {
                timerDigits(session, size: timerDigitSize)
                Text(timerSubtitle(session)).font(.agentSubtext).foregroundStyle(Color.agentSecondary)
            }
            if session.style == .pomodoro {
                Text(nextIntervalLabel(session)).font(.agentSubtext).foregroundStyle(Color.agentSecondary)
            }
            linkedPostRow(session)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AgentSpacing.x4)
    }

    private func splitDialTimer(_ session: ActiveCreatorSessionRecord) -> some View {
        VStack(spacing: AgentSpacing.x5) {
            VStack(spacing: AgentSpacing.x4) {
                HStack(spacing: AgentSpacing.x2) {
                    Circle().fill(timerAccent(session)).frame(width: 8, height: 8)
                    Text(phaseLabel(session).uppercased())
                        .font(.agentMetadata.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(timerAccent(session))
                }
                TimerRing(
                    progress: session.progress(at: now),
                    color: timerAccent(session),
                    size: splitDialSize,
                    lineWidth: 10,
                    trackColor: timerAccent(session).opacity(0.18)
                ) {
                    timerDigits(session, size: splitDigitSize)
                    Text(timerSubtitle(session)).font(.agentSubtext).foregroundStyle(Color.agentSecondary)
                }
                Text(session.displayTitle)
                    .font(.agentSubtext.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(AgentSpacing.x6)
            .frame(maxWidth: .infinity)
            .background(timerAccent(session).opacity(0.07))
            .clipShape(.rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(timerAccent(session).opacity(0.24), lineWidth: 1) }
            if session.style == .pomodoro { sessionMetrics(session) }
            linkedPostRow(session)
        }
    }

    private func focusConsoleTimer(_ session: ActiveCreatorSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(session.phase.title.uppercased())
                        .font(.agentMetadata.weight(.semibold))
                        .tracking(1.3)
                        .foregroundStyle(timerAccent(session))
                    Text(consoleHeadline(session))
                        .font(.agentTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(session.style == .pomodoro ? "\(session.currentRound)/\(session.totalRounds)" : "1/1")
                    .font(.agentSubtext.weight(.bold).monospacedDigit())
                    .frame(width: 44, height: 44)
                    .background(timerAccent(session).opacity(0.12), in: .circle)
                    .overlay { Circle().stroke(timerAccent(session).opacity(0.28), lineWidth: 1) }
            }
            VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                HStack(alignment: .lastTextBaseline) {
                    timerDigits(session, size: consoleDigitSize)
                    Spacer()
                    Text("of \(formattedMinutes(session.currentIntervalMinutes))")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(timerAccent(session).opacity(0.14))
                        Capsule()
                            .fill(timerAccent(session))
                            .frame(width: max(6, proxy.size.width * session.progress(at: now)))
                    }
                }
                .frame(height: 6)
                Text(consoleSupportingCopy(session))
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AgentSpacing.x6)
            .background(timerAccent(session).opacity(0.065))
            .clipShape(.rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(timerAccent(session).opacity(0.22), lineWidth: 1) }
            linkedPostRow(session)
            if session.style == .pomodoro { sessionMetrics(session) }
        }
    }

    @ViewBuilder
    private func linkedPostRow(_ session: ActiveCreatorSessionRecord) -> some View {
        if let linkedPostTitle = session.linkedPostTitle?.nonEmpty {
            HStack(spacing: AgentSpacing.x3) {
                AgentIconView(.link, size: 16)
                    .foregroundStyle(Color.agentSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LINKED POST")
                        .font(.agentMetadata)
                        .tracking(1.1)
                        .foregroundStyle(Color.agentSecondary)
                    Text(linkedPostTitle)
                        .font(.agentSubtext.weight(.semibold))
                        .foregroundStyle(Color.agentText)
                        .lineLimit(2)
                }
                Spacer(minLength: AgentSpacing.x2)
            }
            .padding(.horizontal, AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.agentSurface)
            .clipShape(.rect(cornerRadius: AgentRadius.card))
            .overlay { RoundedRectangle(cornerRadius: AgentRadius.card).stroke(Color.agentHairline, lineWidth: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Linked post: \(linkedPostTitle)")
        }
    }

    private func sessionMetrics(_ session: ActiveCreatorSessionRecord) -> some View {
        HStack(spacing: 0) {
            metricColumn("Elapsed", elapsedLabel(session))
            metricDivider
            metricColumn("Up next", nextMetricLabel(session))
            metricDivider
            metricColumn("Round", "\(session.currentRound) / \(session.totalRounds)")
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionModesLine(_ session: ActiveCreatorSessionRecord) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            ForEach(Array(session.modes.enumerated()), id: \.element.id) { index, mode in
                if index > 0 {
                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(width: 1, height: 16)
                }
                HStack(spacing: AgentSpacing.x1) {
                    AgentIconView(mode.agentIcon, size: 13)
                    Text(mode.title)
                        .font(.agentMetadata.weight(.semibold))
                }
                .foregroundStyle(Color.agentSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session modes: \(session.modeSummary)")
    }

    private func metricColumn(_ label: String, _ value: String) -> some View {
        VStack(spacing: AgentSpacing.x1) {
            Text(label.uppercased()).font(.agentMetadata).tracking(1).foregroundStyle(Color.agentSecondary)
            Text(value).font(.agentSubtext.weight(.semibold).monospacedDigit()).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func timerControls(
        _ session: ActiveCreatorSessionRecord,
        offersFullScreen: Bool = true,
        offersEndSession: Bool = true
    ) -> some View {
        VStack(spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x3) {
                timerControl(title: "+1", accessibilityLabel: "Add one minute") {
                    Task { activeSession = await CreatorSessionActivityController.addMinute(session) }
                }
                .frame(width: 56)
                timerControl(
                    title: session.isPaused ? "Resume" : "Pause",
                    icon: session.isPaused ? .play : nil,
                    accessibilityLabel: session.isPaused ? "Resume session" : "Pause session",
                    prominent: true
                ) {
                    Task { activeSession = await CreatorSessionActivityController.togglePause(session) }
                }
                .frame(maxWidth: .infinity)
                if session.style == .pomodoro {
                    timerControl(title: "Skip", accessibilityLabel: "Skip this interval") {
                        Task { await advanceSession(session) }
                    }
                    .frame(width: 68)
                }
            }
            if offersFullScreen || offersEndSession {
                HStack(spacing: AgentSpacing.x4) {
#if targetEnvironment(macCatalyst)
                if offersFullScreen {
                    Button {
                        isTimerFullScreen = true
                    } label: {
                        HStack(spacing: AgentSpacing.x2) {
                            AgentIconView(.external, size: 14)
                            Text("Full screen")
                        }
                    }
                    .font(.agentSubtext.weight(.semibold))
                    .foregroundStyle(Color.agentText)
                    .frame(minWidth: 120, minHeight: 44)
                    .buttonStyle(AgentPressButtonStyle())
                    .accessibilityLabel("Make timer full screen")

                    Rectangle()
                        .fill(Color.agentHairline)
                        .frame(width: 1, height: 20)
                }
#endif

                    if offersEndSession {
                        Button("End session") { endSession() }
                            .font(.agentSubtext.weight(.semibold))
                            .foregroundStyle(Color.agentDestructive)
                            .frame(minWidth: 120, minHeight: 44)
                            .buttonStyle(AgentPressButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func timerControl(
        title: String,
        icon: AgentIcon? = nil,
        accessibilityLabel: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x2) {
                if let icon { AgentIconView(icon, size: 15) }
                Text(title).font(.agentSubtext.weight(.semibold))
            }
            .foregroundStyle(Color.agentText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(prominent ? Color.agentSelectionFill : Color.agentSurface)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(prominent ? Color.agentSelectionIndicator : Color.agentBorder, lineWidth: 1)
            }
        }
        .buttonStyle(AgentPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func timerDigits(_ session: ActiveCreatorSessionRecord, size: CGFloat) -> some View {
        Text(formattedTime(session.remainingSeconds(at: now)))
            .font(.agentInter(size: size, weight: .medium, relativeTo: .largeTitle).monospacedDigit())
            .tracking(-1.6)
            .foregroundStyle(Color.agentText)
            .contentTransition(.numericText(countsDown: true))
            .accessibilityLabel("\(session.remainingSeconds(at: now)) seconds remaining")
    }

    private var timerRingSize: CGFloat {
#if targetEnvironment(macCatalyst)
        isTimerFullScreen ? 440 : 360
#else
        isTimerFullScreen ? 300 : 250
#endif
    }

    private var timerDigitSize: CGFloat {
#if targetEnvironment(macCatalyst)
        isTimerFullScreen ? 92 : 76
#else
        isTimerFullScreen ? 68 : 58
#endif
    }

    private var splitDialSize: CGFloat {
#if targetEnvironment(macCatalyst)
        isTimerFullScreen ? 360 : 300
#else
        isTimerFullScreen ? 270 : 224
#endif
    }

    private var splitDigitSize: CGFloat {
#if targetEnvironment(macCatalyst)
        isTimerFullScreen ? 82 : 68
#else
        isTimerFullScreen ? 62 : 52
#endif
    }

    private var consoleDigitSize: CGFloat {
#if targetEnvironment(macCatalyst)
        isTimerFullScreen ? 104 : 80
#else
        isTimerFullScreen ? 72 : 62
#endif
    }

    private var fullScreenTimerContentWidth: CGFloat {
#if targetEnvironment(macCatalyst)
        840
#else
        .infinity
#endif
    }

    private var durationMinutes: Int { durationHours * 60 + durationMinuteComponent }

    private var durationSummary: String {
        switch (durationHours, durationMinuteComponent) {
        case (0, 0): "No time selected"
        case (0, let minutes): "\(minutes) min"
        case (let hours, 0): "\(hours) hr"
        case (let hours, let minutes): "\(hours) hr \(minutes) min"
        }
    }

    private var availablePosts: [CreativeBrief] {
        let activeID = WorkspaceScope.activeWorkspaceID(preferredID: appModel.activeWorkspaceID, workspaces: workspaces)
        return briefs.filter { brief in
            brief.status != .archived
                && !IdeaBankPlacementPolicy.includes(brief)
                && WorkspaceScope.includes(brief.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
    }

    private var selectedPost: CreativeBrief? {
        selectedPostID.flatMap { id in availablePosts.first { $0.id == id } }
    }

    private var selectedPostTitle: String? {
        selectedPost?.title.nonEmpty ?? requestedPostTitle?.nonEmpty
    }

    private var selectedPillarColorHex: String? {
        guard let pillarID = selectedPost?.pillarID else { return nil }
        return pillars.first(where: { $0.id == pillarID })?.colorHex
    }

    private func beginStartFlow() {
        guard selectedStyle != .custom || durationMinutes > 0 else { return }
        guard let selectedTimerTheme else {
            openTimerThemeGallery(startsSession: true)
            return
        }
        start(using: selectedTimerTheme)
    }

    private func openTimerThemeGallery(startsSession: Bool) {
        previewedTimerTheme = selectedTimerTheme ?? .quietRing
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            presentedPage = .timerTheme(startsSession: startsSession)
        }
    }

    private func chooseTimerThemeAndContinue(startsSession: Bool) {
        selectedTimerTheme = previewedTimerTheme
        storedTimerTheme = previewedTimerTheme.rawValue
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            presentedPage = .editor
        }
        if startsSession {
            start(using: previewedTimerTheme)
        }
    }

    private func start(using timerTheme: CreatorSessionTimerTheme) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                activeSession = try await CreatorSessionActivityController.start(
                    title: sessionTitle,
                    modes: CreatorSessionMode.allCases.filter(selectedModes.contains),
                    style: selectedStyle,
                    customDurationMinutes: durationMinutes,
                    plan: plan,
                    timerTheme: timerTheme,
                    linkedPostID: selectedPostID,
                    linkedPostTitle: selectedPostTitle,
                    accentColorHex: selectedPillarColorHex
                )
                now = Date()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func endSession() {
        guard let session = activeSession else { return }
        Task {
            await CreatorSessionActivityController.end(session)
            isTimerFullScreen = false
            activeSession = nil
            sessionTitle = ""
        }
    }

    private func advanceSession(_ session: ActiveCreatorSessionRecord) async {
        activeSession = await CreatorSessionActivityController.advance(session)
        now = Date()
        if activeSession == nil {
            isTimerFullScreen = false
            sessionTitle = ""
        }
    }

    private func restoreState() {
        if let stored = CreatorSessionTimerTheme(rawValue: storedTimerTheme) {
            selectedTimerTheme = stored
            previewedTimerTheme = stored
        }
        let request = appModel.consumeCreatorSessionRequest()
        if let postID = request.postID {
            selectedPostID = postID
            requestedPostTitle = request.postTitle
        }
        if let stored = CreatorSessionRecordStore.load() {
            activeSession = stored
            now = Date()
        }
    }

    private func close() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    private func toggleMode(_ mode: CreatorSessionMode) {
        if selectedModes.contains(mode) {
            guard selectedModes.count > 1 else { return }
            selectedModes.remove(mode)
        } else {
            selectedModes.insert(mode)
        }
    }

    private func resetSessionScroll(
        _ proxy: ScrollViewProxy,
        previousID: String?,
        currentID: String?
    ) {
        guard CreatorSessionPresentationPolicy.shouldResetScroll(
            previousSessionID: previousID,
            currentSessionID: currentID
        ) else { return }
        proxy.scrollTo(Self.scrollAnchor, anchor: .top)
    }

    private var timerPreviewAccent: Color {
        Color(agentHex: selectedPillarColorHex ?? "895A38")
    }

    private func timerAccent(_ session: ActiveCreatorSessionRecord) -> Color {
        Color(agentHex: session.accentColorHex ?? "895A38")
    }

    private func phaseLabel(_ session: ActiveCreatorSessionRecord) -> String {
        if session.style == .custom { return "Custom session · \(session.durationMinutes) min" }
        return "\(session.phase.title) · Round \(session.currentRound) of \(session.totalRounds)"
    }

    private func timerSubtitle(_ session: ActiveCreatorSessionRecord) -> String {
        "of \(formattedMinutes(session.currentIntervalMinutes))"
    }

    private func nextIntervalLabel(_ session: ActiveCreatorSessionRecord) -> String {
        switch session.phase {
        case .focus: "Up next · \(session.shortBreakMinutes) minute break"
        case .shortBreak, .longBreak: "Up next · Focus round \(min(session.totalRounds, session.currentRound + 1))"
        }
    }

    private func nextMetricLabel(_ session: ActiveCreatorSessionRecord) -> String {
        switch session.phase {
        case .focus: "\(session.shortBreakMinutes) min break"
        case .shortBreak, .longBreak: "Focus \(min(session.totalRounds, session.currentRound + 1))"
        }
    }

    private func elapsedLabel(_ session: ActiveCreatorSessionRecord) -> String {
        formattedTime(max(0, Int(now.timeIntervalSince(session.startedAt))))
    }

    private func consoleHeadline(_ session: ActiveCreatorSessionRecord) -> String {
        if session.style == .custom { return session.displayTitle }
        switch session.phase {
        case .focus: return "Protect round \(session.currentRound)."
        case .shortBreak: return "Breathe before round \(min(session.totalRounds, session.currentRound + 1))."
        case .longBreak: return "Reset before the next set."
        }
    }

    private func consoleSupportingCopy(_ session: ActiveCreatorSessionRecord) -> String {
        if session.isPaused { return "Paused. Resume whenever you are ready." }
        switch session.phase {
        case .focus: return "Stay with this block. The next break is already planned."
        case .shortBreak, .longBreak: return "The next focus can begin automatically or whenever you are ready."
        }
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private func formattedTime(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let remainingSeconds = safe % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct TimerThemeScreenshot: View {
    let theme: CreatorSessionTimerTheme
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch theme {
                case .quietRing:
                    quietRingPreview(size: proxy.size)
                case .splitDial:
                    splitDialPreview(size: proxy.size)
                case .focusConsole:
                    focusConsolePreview(size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.agentSurface)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.agentBorder, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func quietRingPreview(size: CGSize) -> some View {
        let dialSize = min(220, max(150, min(size.width * 0.48, size.height * 0.62)))
        return VStack(spacing: AgentSpacing.x3) {
            previewHeader("FOCUS · ROUND 2 OF 4")
            TimerRing(progress: 0.68, color: accent, size: dialSize, lineWidth: 7) {
                Text("18:42")
                    .font(.agentInter(size: min(46, dialSize * 0.22), weight: .medium, relativeTo: .title).monospacedDigit())
                Text("of 25 minutes")
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
            }
            Text("Up next · 5 minute break")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)
            previewControls
        }
        .padding(AgentSpacing.x4)
    }

    private func splitDialPreview(size: CGSize) -> some View {
        let dialSize = min(210, max(145, min(size.width * 0.46, size.height * 0.58)))
        return VStack(spacing: AgentSpacing.x3) {
            HStack(spacing: AgentSpacing.x2) {
                Circle().fill(accent).frame(width: 7, height: 7)
                previewHeader("FOCUS · ROUND 2 OF 4", color: accent)
            }
            VStack(spacing: AgentSpacing.x2) {
                TimerRing(
                    progress: 0.68,
                    color: accent,
                    size: dialSize,
                    lineWidth: 8,
                    trackColor: accent.opacity(0.16)
                ) {
                    Text("18:42")
                        .font(.agentInter(size: min(44, dialSize * 0.21), weight: .medium, relativeTo: .title).monospacedDigit())
                    Text("FOCUS")
                        .font(.agentMetadata.weight(.semibold))
                        .foregroundStyle(Color.agentSecondary)
                }
                Text("Campaign edit")
                    .font(.agentSubtext.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AgentSpacing.x3)
            .background(accent.opacity(0.055))
            .clipShape(.rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.20), lineWidth: 1) }
            previewControls
        }
        .padding(AgentSpacing.x4)
    }

    private func focusConsolePreview(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    previewHeader("FOCUS", color: accent)
                    Text("Protect round 2.")
                        .font(.agentHeadline)
                }
                Spacer()
                Text("2/4")
                    .font(.agentSubtext.weight(.bold).monospacedDigit())
            }

            Spacer(minLength: 0)

            Text("18:42")
                .font(.agentInter(size: min(64, max(46, size.width * 0.11)), weight: .medium, relativeTo: .largeTitle).monospacedDigit())
                .tracking(-1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.14))
                    Capsule().fill(accent).frame(width: proxy.size.width * 0.68)
                }
            }
            .frame(height: 6)

            Text("Stay with this block. Your break is already planned.")
                .font(.agentMetadata)
                .foregroundStyle(Color.agentSecondary)

            Spacer(minLength: 0)
            previewControls
        }
        .padding(AgentSpacing.x5)
        .background(accent.opacity(0.045))
    }

    private func previewHeader(_ text: String, color: Color = Color.agentSecondary) -> some View {
        Text(text)
            .font(.agentMetadata.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(color)
    }

    private var previewControls: some View {
        HStack(spacing: AgentSpacing.x2) {
            Text("+1")
                .frame(width: 42, height: 34)
                .background(Color.agentCanvas)
                .clipShape(.rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.agentBorder, lineWidth: 1) }
            HStack(spacing: AgentSpacing.x2) {
                AgentIconView(.play, size: 12)
                Text("Pause")
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color.agentSelectionFill)
            .clipShape(.rect(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.agentSelectionIndicator, lineWidth: 1) }
            Text("Skip")
                .frame(width: 52, height: 34)
                .background(Color.agentCanvas)
                .clipShape(.rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.agentBorder, lineWidth: 1) }
        }
        .font(.agentMetadata.weight(.semibold))
        .foregroundStyle(Color.agentText)
    }
}

private struct TimerRing<Content: View>: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat
    var trackColor: Color = Color.agentHairline
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: AgentSpacing.x1) { content() }
                .padding(lineWidth + AgentSpacing.x4)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

private struct CreatorSessionLifecycleModifier: ViewModifier {
    @Binding var activeSession: ActiveCreatorSessionRecord?
    @Binding var now: Date
    let onAppear: () -> Void
    let onIntervalFinished: (ActiveCreatorSessionRecord) async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppear)
            .task(id: activeSession?.sessionID) {
                while !Task.isCancelled, let session = activeSession {
                    now = Date()
                    if !session.isPaused, session.remainingSeconds(at: now) == 0 {
                        await onIntervalFinished(session)
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

private extension View {
    func creatorSessionLifecycle(
        activeSession: Binding<ActiveCreatorSessionRecord?>,
        now: Binding<Date>,
        onAppear: @escaping () -> Void,
        onIntervalFinished: @escaping (ActiveCreatorSessionRecord) async -> Void
    ) -> some View {
        modifier(CreatorSessionLifecycleModifier(
            activeSession: activeSession,
            now: now,
            onAppear: onAppear,
            onIntervalFinished: onIntervalFinished
        ))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension CreatorSessionMode {
    var agentIcon: AgentIcon {
        switch self {
        case .planning: .tasks
        case .writing: .text
        case .filming: .video
        case .editing: .sliders
        }
    }
}
