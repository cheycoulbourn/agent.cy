import Foundation
import SwiftData
import UIKit

@MainActor
enum PreviewData {
    static func makeContainer() -> ModelContainer {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        seed(container.mainContext)
        return container
    }

    static func seed(_ context: ModelContext) {
        let homeState = PreviewHomeRuntimeState.resolve()
        let pillarState = PreviewPillarRuntimeState.resolve()
        let ideaBankState = PreviewIdeaBankRuntimeState.resolve()
        let profile = CreatorProfile(
            name: "Maya",
            goal: "Help independent creators build practical systems",
            selectedPlatforms: [.instagramReels, .tiktok, .youtubeShorts],
            assistanceMode: .collaborate,
            adultConfirmed: true,
            onboardingCompleted: true,
            showsBrandDealsInPostEditor: true
        )
        context.insert(profile)
        var previewWorkspace: CreatorWorkspace?
        if ProcessInfo.processInfo.arguments.contains("-agentCyPreviewPillarPalette")
            || PlanRuntimeFixture.requestsEpisodeSlotActions(arguments: ProcessInfo.processInfo.arguments)
            || PlanRuntimeFixture.requestsAddLivePost(arguments: ProcessInfo.processInfo.arguments)
            || ideaBankState != nil {
            let workspace = CreatorWorkspace(
                profileID: profile.id,
                name: "@maya",
                creatorName: profile.name,
                hasCustomIdentity: true
            )
            if ProcessInfo.processInfo.arguments.contains("-agentCyPreviewPillarPalette") {
                workspace.vibePalette = .tooCool
            }
            context.insert(workspace)
            previewWorkspace = workspace
        }
        context.insert(SubscriptionState(access: .comped))
        context.insert(VoiceProfile(profileID: profile.id, summary: "Direct, calm, and specific", traitsText: "Practical examples, short openings, honest tradeoffs", avoidText: "Hype and false urgency", isApproved: true))
        for (index, example) in [
            "A useful system should make the next decision easier, not make you feel managed.",
            "Start with the version you can repeat on a hard week.",
            "You do not need more ideas. You need one idea with one clear job."
        ].enumerated() {
            context.insert(VoiceExample(profileID: profile.id, text: example, sortOrder: index))
        }

        let systemsPillar = Pillar(
            role: .anchor,
            name: "Creator systems",
            detail: "Simple ways to make creative work easier.",
            colorHex: "9B3A2E",
            assignedWeekdays: [.monday, .wednesday, .friday]
        )
        let honestWorkPillar = Pillar(
            parentPillarID: systemsPillar.id,
            role: .supporting,
            name: "Behind the work",
            detail: "Honest lessons from the process.",
            colorHex: "55705B",
            assignedWeekdays: [.tuesday, .thursday]
        )
        let tutorialBranch = Pillar(
            parentPillarID: systemsPillar.id,
            role: .supporting,
            name: "Practical tutorials",
            detail: "Walkthroughs people can use today.",
            colorHex: systemsPillar.colorHex,
            assignedWeekdays: systemsPillar.assignedWeekdays
        )
        [systemsPillar, honestWorkPillar, tutorialBranch].forEach {
            $0.workspaceID = previewWorkspace?.id
        }
        if pillarState != .empty {
            if pillarState == .archived {
                honestWorkPillar.isArchived = true
            }
            context.insert(systemsPillar)
            context.insert(honestWorkPillar)
            context.insert(tutorialBranch)

            if pillarState == .limit {
                for (index, name) in ["Creator business", "Sustainable process", "Audience trust"].enumerated() {
                    let branch = Pillar(
                        parentPillarID: systemsPillar.id,
                        role: .supporting,
                        name: name,
                        colorHex: CreatorVibePalette.tooCool.pillarColorHexes[index + 2]
                    )
                    branch.workspaceID = previewWorkspace?.id
                    context.insert(branch)
                }
            } else if pillarState == .orphan {
                let orphan = Pillar(
                    parentPillarID: UUID(),
                    role: .supporting,
                    name: "Recovered orphan",
                    colorHex: "416B85"
                )
                orphan.workspaceID = previewWorkspace?.id
                context.insert(orphan)
            }
        }

        let ready = CreativeBrief(title: "The one-job idea test", premise: "A rough idea becomes filmable when it has one audience and one job.", status: .ready)
        ready.pillarID = systemsPillar.id
        ready.audience = "Solo creators with too many half-finished notes"
        ready.creativeGoal = "Make narrowing feel practical"
        ready.takeaway = "Choose one audience and one change."
        ready.spokenHook = "Your idea probably is not bad. It is carrying too many jobs."
        ready.firstFrameText = "ONE IDEA. ONE JOB."
        ready.scriptBeats = ["Name the overloaded note", "Show the one-job test", "Apply it to a real example", "Give the viewer one next step"]
        ready.close = "That is enough clarity to make the next creative decision."
        ready.ctaIntent = "Invite the viewer to test a saved idea"
        ready.voiceConfidence = 0.86
        context.insert(ready)

        let reel = PlatformOutput(briefID: ready.id, platform: .instagramReels, status: .scheduled)
        reel.caption = "One audience. One change. That is enough to rescue the note."
        reel.targetDate = switch homeState {
        case .todayPost: Date()
        case .latePost: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        default: Calendar.current.date(byAdding: .day, value: 1, to: Date())
        }
        context.insert(reel)
        if let mediaData = makePostMediaPreviewData() {
            let media = CreatorAttachment(
                ownerKind: .postMedia,
                briefID: ready.id,
                platformOutputID: reel.id,
                fileName: "one-idea-one-job.png",
                kind: .photo,
                uniformTypeIdentifier: "public.png",
                byteCount: Int64(mediaData.count),
                localRelativePath: "",
                cloudData: mediaData,
                previewData: mediaData,
                syncState: .eligible
            )
            reel.coverAttachmentID = media.id
            context.insert(media)
        }
        let filmingTask = CreatorTask(briefID: ready.id, title: "Film the one-job walkthrough", kind: .filming, targetDate: Date(), sortOrder: 0, isRecordingMilestoneDesignated: true)
        context.insert(filmingTask)
        context.insert(CreatorTask(briefID: ready.id, parentTaskID: filmingTask.id, title: "Set the camera", kind: .filming, sortOrder: 0))
        context.insert(CreatorTask(briefID: ready.id, parentTaskID: filmingTask.id, title: "Record two takes", kind: .filming, sortOrder: 1))
        context.insert(CreatorTask(briefID: ready.id, title: "Edit the 45-second cut", kind: .editing, sortOrder: 1))

        let developing = CreativeBrief(title: "What I stopped tracking", premise: "Share why fewer creator metrics created better work.", source: .text, status: .developing)
        developing.pillarID = honestWorkPillar.id
        developing.workspaceID = previewWorkspace?.id
        developing.ideaBankPlacement = .idea
        if ideaBankState != .empty {
            if ideaBankState == .archived {
                developing.status = .archived
            }
            context.insert(developing)
            context.insert(CreatorTask(
                briefID: developing.id,
                title: "Shape the opening",
                kind: .scripting,
                targetDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())
            ))
        }
        if let ideaBankState, ideaBankState != .empty {
            let saved = InspirationSource(
                workspaceID: previewWorkspace?.id,
                canonicalURLString: "https://example.com/saved/creator-workflow",
                platform: .instagram,
                status: .ready
            )
            saved.sourceTitle = "A calmer creator workflow"
            saved.sourceCaption = "Three decisions that make weekly creation lighter."
            saved.pillarID = systemsPillar.id
            saved.thumbnailData = Data([0])
            context.insert(saved)

            let secondIdea = CreativeBrief(
                title: "The ritual that makes publishing easier",
                premise: "Show the small repeatable setup that reduces creative friction.",
                status: .spark
            )
            secondIdea.workspaceID = previewWorkspace?.id
            secondIdea.pillarID = systemsPillar.id
            secondIdea.ideaBankPlacement = .idea
            context.insert(secondIdea)
        }
        if homeState == .activityMix {
            // Mirrors the 2026-08-19 field report: post notifications owned
            // by a non-active account, task notifications in the active one.
            let activeMixWorkspace = CreatorWorkspace(
                profileID: profile.id,
                name: "Main",
                creatorName: profile.name,
                hasCustomIdentity: true,
                sortOrder: 0
            )
            context.insert(activeMixWorkspace)
            let foreignWorkspace = CreatorWorkspace(
                profileID: profile.id,
                name: "@otheraccount",
                creatorName: profile.name,
                hasCustomIdentity: true,
                sortOrder: 99
            )
            context.insert(foreignWorkspace)
            let postKinds: [(String, AgentNotificationKind, Int)] = [
                ("preview-post-scheduled", .scheduledPost, 3),
                ("preview-post-missed", .missedPost, 2),
                ("preview-post-draft", .draftPreparation, 1),
            ]
            for (index, entry) in postKinds.enumerated() {
                context.insert(AgentActivityRecord(
                    notificationID: entry.0,
                    workspaceID: foreignWorkspace.id,
                    kind: entry.1,
                    availableAt: Date().addingTimeInterval(Double(-60 * (index + 1))),
                    title: "Post reminder \(index + 1)",
                    body: "A post needs attention.",
                    reason: "Preview activity mix",
                    priority: entry.2,
                    briefID: ready.id,
                    route: .day
                ))
            }
            for index in 0..<2 {
                let readTask = AgentActivityRecord(
                    notificationID: "preview-task-read-\(index)",
                    workspaceID: nil,
                    kind: .timedTask,
                    availableAt: Date().addingTimeInterval(Double(-3600 * (index + 1))),
                    title: "Task reminder \(index + 1)",
                    body: "This task was already read.",
                    reason: "Preview activity mix",
                    priority: 1,
                    taskID: filmingTask.id,
                    route: .task
                )
                readTask.readAt = Date().addingTimeInterval(-1800)
                readTask.resolvedAt = Date().addingTimeInterval(-1700)
                context.insert(readTask)
            }
        }
        if homeState == .unreadActivity {
            context.insert(AgentActivityRecord(
                notificationID: "preview-home-unread",
                workspaceID: nil,
                kind: .timedTask,
                availableAt: Date().addingTimeInterval(-60),
                title: "Film the one-job walkthrough",
                body: "This task is ready when you are.",
                reason: "Preview unread activity",
                priority: 2,
                taskID: filmingTask.id,
                route: .task,
                eventDate: filmingTask.targetDate
            ))
        }
        let previewArguments = ProcessInfo.processInfo.arguments
        if PlanRuntimeFixture.requestsDailyFocusDetail(arguments: previewArguments)
            || PlanRuntimeFixture.requestsDailyFocusEditor(arguments: previewArguments) {
            seedDailyFocusDetail(context)
        }
        if PlanRuntimeFixture.requestsEpisodeSlotActions(arguments: previewArguments) {
            seedEpisodeSlotActions(
                context,
                workspaceID: previewWorkspace?.id,
                pillarID: systemsPillar.id
            )
        }
        context.insert(WeekPlan(weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date(), rhythmEntriesText: "Monday: choose one idea\nWednesday: film\nFriday: edit and post"))
        try? context.save()
    }

    private static func seedDailyFocusDetail(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekday = PillarWeekday(rawValue: calendar.component(.weekday, from: today)) else {
            return
        }
        let review = DailyFocusTaskTemplateDefinition(
            focusKind: .planning,
            title: "Review your backlog",
            priority: .high,
            sortOrder: 0
        )
        let schedule = DailyFocusTaskTemplateDefinition(
            focusKind: .planning,
            title: "Structure and schedule your next post",
            sortOrder: 1
        )
        let focus = DailyFocusTemplateEntry(
            weekday: weekday,
            kind: .planning,
            title: "Planning",
            durationMinutes: 90,
            startMinutesFromMidnight: 9 * 60
        )
        focus.focusTaskTemplates = [review, schedule]
        context.insert(focus)

        let completed = CreatorTask(
            title: review.title,
            kind: .planning,
            lane: .production,
            priority: review.priority,
            targetDate: today,
            includesTargetTime: false,
            dailyFocusDate: today,
            dailyFocusTitle: focus.title,
            dailyFocusTemplateEntryID: focus.id,
            focusTaskTemplateID: review.id,
            sortOrder: 0
        )
        completed.isCompleted = true
        completed.completedAt = Date()
        context.insert(completed)
        context.insert(CreatorTask(
            title: schedule.title,
            kind: .planning,
            lane: .production,
            targetDate: today,
            includesTargetTime: false,
            dailyFocusDate: today,
            dailyFocusTitle: focus.title,
            dailyFocusTemplateEntryID: focus.id,
            focusTaskTemplateID: schedule.id,
            sortOrder: 1
        ))
        context.insert(DailyFocusDayDetail(
            date: today,
            note: "Keep the plan small enough to finish."
        ))
    }

    private static func seedEpisodeSlotActions(
        _ context: ModelContext,
        workspaceID: UUID?,
        pillarID: UUID
    ) {
        let calendar = Calendar.current
        let plannedDate = calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        ) ?? Date()
        let series = ContentSeries(
            workspaceID: workspaceID,
            name: "Creator Systems Weekly",
            pillarID: pillarID,
            platform: .instagramReels,
            durationSeconds: 60
        )
        series.taskTemplate = [
            SeriesTaskTemplateItem(
                title: "Outline this episode",
                kind: .scripting,
                priority: .high,
                estimatedMinutes: 30,
                sortOrder: 0
            )
        ]
        context.insert(series)
        context.insert(SeriesEpisodeSlot(
            workspaceID: workspaceID,
            seriesID: series.id,
            plannedDate: plannedDate
        ))

        let idea = CreativeBrief(
            title: "The planning habit that finally stuck",
            premise: "Show the small planning loop that is easy to repeat.",
            status: .spark
        )
        idea.workspaceID = workspaceID
        idea.ideaBankPlacement = .idea
        idea.pillarID = pillarID
        context.insert(idea)
    }

    private static func makePostMediaPreviewData() -> Data? {
        guard let eyebrowFont = UIFont(name: "InterVariable", size: 24),
              let titleFont = UIFont(name: "InterVariable", size: 72) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let size = CGSize(width: 540, height: 960)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.pngData { rendererContext in
            let context = rendererContext.cgContext
            let colors = [
                UIColor(red: 0.96, green: 0.91, blue: 0.88, alpha: 1).cgColor,
                UIColor(red: 0.71, green: 0.24, blue: 0.18, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            )
            if let gradient {
                context.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let eyebrowAttributes: [NSAttributedString.Key: Any] = [
                .font: eyebrowFont,
                .foregroundColor: UIColor.black.withAlphaComponent(0.64),
                .kern: 4,
                .paragraphStyle: paragraph
            ]
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            ("CREATOR SYSTEMS" as NSString).draw(
                in: CGRect(x: 40, y: 250, width: 460, height: 44),
                withAttributes: eyebrowAttributes
            )
            ("ONE IDEA\nONE JOB" as NSString).draw(
                in: CGRect(x: 36, y: 330, width: 468, height: 210),
                withAttributes: titleAttributes
            )
        }
    }
}

private enum PreviewHomeRuntimeState: String {
    case todayPost
    case latePost
    case unreadActivity
    /// Field-report shape 2026-08-19: unread post-kind records alongside
    /// read task records, for replaying the Activity All-tab report.
    case activityMix

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let marker = arguments.firstIndex(of: "-agentCyPreviewHomeState"),
              arguments.indices.contains(marker + 1) else { return nil }
        return Self(rawValue: arguments[marker + 1])
    }
}

private enum PreviewPillarRuntimeState: String {
    case empty
    case limit
    case archived
    case orphan

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let marker = arguments.firstIndex(of: "-agentCyPreviewPillarState"),
              arguments.indices.contains(marker + 1) else { return nil }
        return Self(rawValue: arguments[marker + 1])
    }
}

private enum PreviewIdeaBankRuntimeState: String {
    case populated
    case empty
    case archived
    case query
    case selection
    case missing

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard let marker = arguments.firstIndex(of: "-agentCyPreviewIdeaBankState"),
              arguments.indices.contains(marker + 1) else { return nil }
        return Self(rawValue: arguments[marker + 1])
    }
}
