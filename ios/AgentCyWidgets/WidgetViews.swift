import SwiftUI
import UIKit
import WidgetKit

private enum WidgetPalette {
    static let canvas = Color.widgetAdaptive(light: AgentColorPalette.canvasLight, dark: AgentColorPalette.canvasDark)
    static let surface = Color.widgetAdaptive(light: AgentColorPalette.surfaceLight, dark: AgentColorPalette.surfaceDark)
    static let ink = Color.widgetAdaptive(light: AgentColorPalette.inkLight, dark: AgentColorPalette.inkDark)
    static let secondary = Color.widgetAdaptive(light: AgentColorPalette.secondaryLight, dark: AgentColorPalette.secondaryDark)
    static let border = Color.widgetAdaptive(light: AgentColorPalette.borderLight, dark: AgentColorPalette.borderDark)
    static let hairline = Color.widgetAdaptive(light: AgentColorPalette.hairlineLight, dark: AgentColorPalette.hairlineDark)
    static let cy = Color.widgetAdaptive(light: AgentColorPalette.cy, dark: AgentColorPalette.cyTextDark)
}

private struct WidgetSurface<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    init(background: Color = WidgetPalette.surface, @ViewBuilder content: @escaping () -> Content) {
        self.background = background
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) { background }
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(WidgetPalette.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct TodayFocusWidgetView: View {
    let entry: AgentCyWidgetEntry

    var body: some View {
        WidgetSurface {
            VStack(alignment: .leading, spacing: 0) {
                Text("TODAY’S FOCUS")
                    .widgetMeta()
                Rectangle()
                    .fill(WidgetPalette.hairline)
                    .frame(height: 1)
                    .padding(.top, 13)
                    .padding(.bottom, 12)

                if let focus = entry.snapshot.focus {
                    Text(focus.title)
                        .font(.widgetInter(size: 25, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(focus.directive.isEmpty ? "One clear direction for today." : focus.directive)
                        .font(.widgetInter(size: 13, weight: .regular))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(2)
                        .padding(.top, 4)
                    Spacer(minLength: 8)
                    HStack(spacing: 12) {
                        if let duration = focus.durationMinutes {
                            Text("\(duration) MIN").widgetMeta()
                        }
                        if let start = focus.startDate {
                            Text(start.formatted(date: .omitted, time: .shortened).uppercased()).widgetMeta()
                        }
                        Spacer()
                        Text("\(focus.completedTaskCount)/\(focus.taskCount) TASKS").widgetMeta()
                    }
                } else {
                    Text("Rest")
                        .font(.widgetInter(size: 25, weight: .bold))
                    Text("Nothing is assigned. Leave room or choose a focus in agent.cy.")
                        .font(.widgetInter(size: 13, weight: .regular))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(2)
                        .padding(.top, 4)
                    Spacer()
                    Text("OPEN TODAY →").widgetMeta()
                }
            }
            .foregroundStyle(WidgetPalette.ink)
            .padding(20)
            .privacySensitive()
            .widgetURL(AgentCyDeepLink.today.url)
        }
    }
}

struct QuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgentCyWidgetEntry

    var body: some View {
        if family == .systemSmall {
            WidgetSurface(background: Color(uiColor: AgentColorPalette.surfaceDark.uiColor)) {
                VStack(alignment: .leading, spacing: 0) {
                    CyAsteriskBadge(size: 30)
                    Spacer(minLength: 12)
                    Text("Capture\nan idea.")
                        .font(.widgetInter(size: 23, weight: .bold))
                        .foregroundStyle(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                        .lineSpacing(0)
                    Text("Before it leaves.")
                        .font(.widgetInter(size: 12, weight: .regular))
                        .foregroundStyle(Color(uiColor: AgentColorPalette.secondaryDark.uiColor))
                        .padding(.top, 5)
                    Spacer(minLength: 8)
                    HStack {
                        Text("NEW IDEA").widgetMeta(color: Color(uiColor: AgentColorPalette.inkDark.uiColor))
                        Spacer()
                        Text("+")
                            .font(.widgetInter(size: 20, weight: .regular))
                            .foregroundStyle(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                    }
                }
                .padding(18)
                .widgetURL(AgentCyDeepLink.quickIdea.url)
            }
        } else {
            WidgetSurface {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        CyAsteriskBadge(size: 30)
                        Text("Quick capture")
                            .font(.widgetInter(size: 24, weight: .bold))
                            .foregroundStyle(WidgetPalette.ink)
                        Spacer()
                    }
                    Text("Capture an idea, post, or task on the go. Never lose a moment.")
                        .font(.widgetInter(size: 13, weight: .regular))
                        .foregroundStyle(WidgetPalette.secondary)
                        .padding(.top, 7)
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        captureTile("Idea", destination: .quickIdea)
                        captureTile("Post", destination: .quickPost)
                        captureTile("Task", destination: .quickTask)
                    }
                }
                .padding(20)
            }
        }
    }

    private func captureTile(_ title: String, destination: AgentCyDeepLink) -> some View {
        Link(destination: destination.url) {
            HStack {
                Text(title)
                    .font(.widgetInter(size: 14, weight: .semibold))
                Spacer(minLength: 4)
                Text("+")
                    .font(.widgetInter(size: 18, weight: .regular))
            }
            .foregroundStyle(WidgetPalette.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(WidgetPalette.canvas, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(WidgetPalette.border, lineWidth: 1)
            }
        }
    }
}

struct NextPostWidgetView: View {
    let entry: AgentCyWidgetEntry

    var body: some View {
        WidgetSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("NEXT POST").widgetMeta()
                    Spacer()
                    Text(entry.snapshot.nextPost?.status.uppercased() ?? "EMPTY").widgetMeta()
                }
                Rectangle().fill(WidgetPalette.hairline).frame(height: 1).padding(.top, 13)
                if let post = entry.snapshot.nextPost {
                    Spacer(minLength: 10)
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(hex: post.pillarColorHex ?? AgentColorPalette.pillarFallbackHex))
                            .frame(width: 7, height: 7)
                        Text(post.pillarName.uppercased()).widgetMeta()
                    }
                    Text(post.title)
                        .font(.widgetInter(size: 18, weight: .bold))
                        .lineLimit(3)
                        .padding(.top, 7)
                    Spacer(minLength: 8)
                    HStack {
                        Text(post.platformLabel.uppercased()).widgetMeta()
                            .lineLimit(1)
                        Spacer()
                        if let target = post.targetDate {
                            Text(target.formatted(date: .omitted, time: .shortened).uppercased()).widgetMeta()
                        }
                    }
                } else {
                    Spacer()
                    Text("Nothing scheduled")
                        .font(.widgetInter(size: 18, weight: .bold))
                    Text("Plan a post when you’re ready.")
                        .font(.widgetInter(size: 12, weight: .regular))
                        .foregroundStyle(WidgetPalette.secondary)
                        .padding(.top, 4)
                    Spacer()
                    Text("OPEN AGENDA →").widgetMeta()
                }
            }
            .foregroundStyle(WidgetPalette.ink)
            .padding(18)
            .privacySensitive()
            .widgetURL(entry.snapshot.nextPost.map { AgentCyDeepLink.brief($0.id).url } ?? AgentCyDeepLink.agenda(day: nil).url)
        }
    }
}

struct WeeklyRhythmWidgetView: View {
    let entry: AgentCyWidgetEntry

    var body: some View {
        WidgetSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("WEEKLY RHYTHM").widgetMeta()
                    Spacer()
                    Text(Date().formatted(.dateTime.month(.abbreviated).day()).uppercased()).widgetMeta()
                }
                HStack(spacing: 5) {
                    ForEach(days) { day in
                        Link(destination: AgentCyDeepLink.agenda(day: day.date).url) {
                            VStack(spacing: 4) {
                                Text(day.date.formatted(.dateTime.weekday(.narrow)).uppercased())
                                    .font(.widgetMetadata(size: 9))
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.widgetInter(size: 16, weight: .semibold))
                                if let color = day.pillarColorHex {
                                    Circle().fill(Color(hex: color)).frame(width: 6, height: 6)
                                } else {
                                    Color.clear.frame(width: 6, height: 6)
                                }
                            }
                            .foregroundStyle(WidgetPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .overlay {
                                if Calendar.current.isDateInToday(day.date) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(WidgetPalette.ink, lineWidth: 1.25)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
                Rectangle().fill(WidgetPalette.hairline).frame(height: 1)
                Spacer(minLength: 9)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY’S FOCUS").widgetMeta()
                        Text(todayFocus)
                            .font(.widgetInter(size: 13, weight: .semibold))
                            .foregroundStyle(WidgetPalette.ink)
                            .lineLimit(1)
                    }
                    Spacer()
                    Link(destination: AgentCyDeepLink.agenda(day: nil).url) {
                        Text("OPEN WEEK →").widgetMeta(color: WidgetPalette.ink)
                    }
                }
                .frame(minHeight: 31)
            }
            .padding(20)
            .privacySensitive()
        }
    }

    private var days: [WidgetDaySnapshot] {
        entry.snapshot.week.isEmpty ? AgentCyWidgetSnapshot.preview.week : entry.snapshot.week
    }

    private var todayFocus: String {
        days.first(where: { Calendar.current.isDateInToday($0.date) })?.focusTitle ?? "Rest"
    }
}

struct IdeaBankWidgetView: View {
    let entry: AgentCyWidgetEntry

    var body: some View {
        WidgetSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("IDEA BANK").widgetMeta()
                    Spacer()
                    Text("AGENT.CY").widgetMeta(color: WidgetPalette.cy)
                }
                if let idea = entry.snapshot.latestIdea {
                    HStack(alignment: .top, spacing: 9) {
                        Rectangle()
                            .fill(Color(hex: idea.pillarColorHex ?? AgentColorPalette.pillarFallbackHex))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(idea.title)
                                .font(.widgetInter(size: 18, weight: .bold))
                                .lineLimit(2)
                            Text((idea.pillarName ?? "Unfiled").uppercased()).widgetMeta()
                        }
                    }
                    .padding(.top, 13)
                    .padding(.bottom, 8)
                    .privacySensitive()
                } else {
                    Text("Catch the thought before it leaves.")
                        .font(.widgetInter(size: 18, weight: .bold))
                        .lineLimit(2)
                        .padding(.top, 13)
                        .padding(.bottom, 8)
                }
                Spacer(minLength: 8)
                Rectangle().fill(WidgetPalette.hairline).frame(height: 1)
                HStack {
                    Link(destination: AgentCyDeepLink.ideaBank.url) {
                        Text("OPEN IDEA BANK").widgetMeta(color: WidgetPalette.ink)
                    }
                    Spacer()
                    Link(destination: AgentCyDeepLink.quickIdea.url) {
                        HStack(spacing: 5) {
                            Text("CAPTURE").widgetMeta(color: WidgetPalette.ink)
                            Text("+")
                                .font(.widgetInter(size: 18, weight: .regular))
                                .foregroundStyle(WidgetPalette.ink)
                        }
                        .frame(minHeight: 31)
                    }
                }
                .padding(.top, 7)
            }
            .foregroundStyle(WidgetPalette.ink)
            .padding(20)
        }
    }
}

struct ProductionQueueWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: AgentCyWidgetEntry

    var body: some View {
        WidgetSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(queueLabel).widgetMeta()
                        Text(queueTitle)
                            .font(.widgetInter(size: 26, weight: .bold))
                            .tracking(-0.9)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    if entry.snapshot.nextPost != nil {
                        Text(queueProgress).widgetMeta()
                            .padding(.top, 4)
                    }
                }

                if entry.snapshot.nextPost == nil {
                    Rectangle()
                        .fill(WidgetPalette.hairline)
                        .frame(height: 1)
                        .padding(.top, 18)
                        .padding(.bottom, 14)
                } else {
                    Spacer().frame(height: 22)
                }

                if let post = entry.snapshot.nextPost {
                    Link(destination: AgentCyDeepLink.brief(post.id).url) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(postAccent(post))
                                        .frame(width: 7, height: 7)
                                    Text(post.pillarName.uppercased()).widgetMeta()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer()
                                Text(post.status.uppercased())
                                    .font(.widgetMetadata(size: 10))
                                    .tracking(0.4)
                                    .foregroundStyle(WidgetPalette.ink)
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: 24)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(WidgetPalette.ink.opacity(0.20), lineWidth: 1)
                                    }
                            }

                            Text(post.title)
                                .font(.widgetInter(size: 17, weight: .semibold))
                                .tracking(-0.17)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            HStack(spacing: 8) {
                                Text(postMetadata(post)).widgetMeta(color: WidgetPalette.ink)
                                    .tracking(0.4)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("›")
                                    .font(.widgetInter(size: 15, weight: .regular))
                                    .foregroundStyle(WidgetPalette.ink)
                            }
                            .padding(.top, 2)
                        }
                        .foregroundStyle(WidgetPalette.ink)
                        .padding(16)
                        .background(postBackground(post), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(postBorder(post), lineWidth: 1)
                        }
                    }
                } else {
                    Link(destination: AgentCyDeepLink.quickPost.url) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("TODAY’S POSTS").widgetMeta()
                                Spacer()
                                Text("0").widgetMeta()
                            }

                            Text("Nothing planned for today.")
                                .font(.widgetInter(size: 17, weight: .semibold))
                                .lineLimit(2)

                            Text("Start with one clear idea.")
                                .font(.widgetInter(size: 13, weight: .regular))
                                .foregroundStyle(WidgetPalette.secondary)

                            Text("+ CREATE POST")
                                .font(.widgetMetadata(size: 10))
                                .tracking(1)
                                .foregroundStyle(WidgetPalette.cy)
                                .padding(.top, 3)
                        }
                        .foregroundStyle(WidgetPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .background(WidgetPalette.canvas, in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(WidgetPalette.border, lineWidth: 1)
                        }
                    }
                }

                HStack {
                    Text(tasks.isEmpty ? "TASKS" : "NEXT TASKS").widgetMeta()
                    Spacer()
                    Text(tasks.isEmpty ? "0" : "\(openTaskCount) LEFT").widgetMeta()
                }
                .padding(.top, tasks.isEmpty ? 15 : 19)
                .padding(.bottom, tasks.isEmpty ? 10 : 8)

                VStack(spacing: 0) {
                    if tasks.isEmpty {
                        Link(destination: AgentCyDeepLink.quickTask.url) {
                            HStack {
                                Text("+ Add task")
                                    .font(.widgetInter(size: 14, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.ink)
                                Spacer()
                                Text("→")
                                    .font(.widgetInter(size: 17, weight: .regular))
                                    .foregroundStyle(WidgetPalette.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 43)
                            .background(WidgetPalette.canvas, in: .rect(cornerRadius: 12))
                        }
                    } else {
                        ForEach(tasks.prefix(2)) { task in
                            HStack(spacing: 12) {
                                Button(intent: SetWidgetTaskCompletionIntent(
                                    taskID: task.id,
                                    isCompleted: !task.isCompleted
                                )) {
                                    taskCheckbox(task)
                                        .frame(width: 44, height: 44, alignment: .leading)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(task.isCompleted ? "Mark \(task.title) open" : "Complete \(task.title)")

                                Link(destination: AgentCyDeepLink.tasks.url) {
                                    Text(task.title)
                                        .font(.widgetInter(size: 14, weight: task.isCompleted ? .regular : .medium))
                                        .foregroundStyle(task.isCompleted ? WidgetPalette.secondary : WidgetPalette.ink)
                                        .strikethrough(task.isCompleted, color: WidgetPalette.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .frame(height: 45)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(WidgetPalette.hairline).frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .privacySensitive()
        }
    }

    private var queueTitle: String {
        if entry.snapshot.nextPost == nil {
            return todayFocusTitle
        }
        if entry.taskLane == .pillar {
            return "Pillar tasks"
        }
        let title = entry.snapshot.focus?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Make what’s next" : title
    }

    private var queueLabel: String {
        if entry.snapshot.nextPost == nil {
            return "TODAY’S FOCUS"
        }
        return entry.taskLane == .production ? "PRODUCTION QUEUE" : "PILLAR TASKS"
    }

    private var queueProgress: String {
        if entry.taskLane == .production,
           let focus = entry.snapshot.focus,
           focus.taskCount > 0 {
            return "\(focus.completedTaskCount) OF \(focus.taskCount)"
        }
        return "\(laneTasks.filter(\.isCompleted).count) OF \(laneTasks.count)"
    }

    private var openTaskCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    private var todayFocusTitle: String {
        let title = entry.snapshot.focus?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Rest" : title
    }

    private func postAccent(_ post: WidgetPostSnapshot) -> Color {
        Color(hex: post.pillarColorHex ?? AgentColorPalette.pillarFallbackHex)
    }

    private func postBackground(_ post: WidgetPostSnapshot) -> Color {
        guard post.status.caseInsensitiveCompare("Draft") != .orderedSame else {
            return WidgetPalette.surface
        }
        return postAccent(post).opacity(colorScheme == .dark ? 0.24 : 0.10)
    }

    private func postBorder(_ post: WidgetPostSnapshot) -> Color {
        guard post.status.caseInsensitiveCompare("Draft") != .orderedSame else {
            return WidgetPalette.ink.opacity(0.28)
        }
        return postAccent(post).opacity(colorScheme == .dark ? 0.82 : 0.68)
    }

    private func postMetadata(_ post: WidgetPostSnapshot) -> String {
        let platform = post.platformLabel.uppercased()
        guard let targetDate = post.targetDate else { return platform }
        return "\(platform) · \(targetDate.formatted(date: .omitted, time: .shortened).uppercased())"
    }

    @ViewBuilder
    private func taskCheckbox(_ task: WidgetTaskSnapshot) -> some View {
        if task.isCompleted {
            RoundedRectangle(cornerRadius: 4)
                .fill(WidgetPalette.ink)
                .frame(width: 18, height: 18)
                .overlay {
                    Text("✓")
                        .font(.widgetInter(size: 12, weight: .regular))
                        .foregroundStyle(WidgetPalette.surface)
                }
        } else {
            RoundedRectangle(cornerRadius: 4)
                .stroke(WidgetPalette.ink, lineWidth: 1.5)
                .frame(width: 18, height: 18)
        }
    }

    private var tasks: [WidgetTaskSnapshot] {
        entry.snapshot.openProductionTasks(in: entry.taskLane)
    }

    private var laneTasks: [WidgetTaskSnapshot] {
        entry.snapshot.productionTasks.filter { ($0.lane ?? .production) == entry.taskLane }
    }
}

private struct CyAsteriskBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(WidgetPalette.cy)
            ForEach([0.0, 45.0, 90.0, 135.0], id: \.self) { angle in
                Capsule()
                    .fill(Color(uiColor: AgentColorPalette.inkDark.uiColor))
                    .frame(width: size * 0.53, height: max(1.5, size * 0.06))
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension View {
    func widgetMeta(color: Color = WidgetPalette.secondary) -> some View {
        font(.widgetMetadata(size: 10))
            .monospacedDigit()
            .tracking(1.15)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private extension Font {
    static func widgetInter(size: CGFloat, weight: Weight) -> Font {
        .custom("InterVariable", size: size).weight(weight)
    }

    static func widgetMetadata(size: CGFloat) -> Font {
        .custom("InterVariable", size: size).weight(.medium)
    }
}

private extension Color {
    init(hex: String) {
        let oklch = AgentOKLCH(hex: hex) ?? AgentColorPalette.secondaryLight
        self.init(uiColor: oklch.uiColor)
    }

    static func widgetAdaptive(light: AgentOKLCH, dark: AgentOKLCH) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        })
    }
}
