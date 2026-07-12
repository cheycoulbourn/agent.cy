import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static func makeContainer() -> ModelContainer {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        seed(container.mainContext)
        return container
    }

    static func seed(_ context: ModelContext) {
        let profile = CreatorProfile(
            name: "Maya",
            goal: "Help independent creators build practical systems",
            selectedPlatforms: [.instagramReels, .tiktok, .youtubeShorts],
            assistanceMode: .collaborate,
            adultConfirmed: true,
            onboardingCompleted: true
        )
        context.insert(profile)
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
            name: "Creator systems",
            detail: "Simple ways to make creative work easier.",
            colorHex: "9B3A2E",
            assignedWeekdays: [.monday, .wednesday, .friday]
        )
        let honestWorkPillar = Pillar(
            name: "Behind the work",
            detail: "Honest lessons from the process.",
            colorHex: "55705B",
            assignedWeekdays: [.tuesday, .thursday]
        )
        let tutorialBranch = Pillar(
            parentPillarID: systemsPillar.id,
            name: "Practical tutorials",
            detail: "Walkthroughs people can use today.",
            colorHex: systemsPillar.colorHex,
            assignedWeekdays: systemsPillar.assignedWeekdays
        )
        context.insert(systemsPillar)
        context.insert(honestWorkPillar)
        context.insert(tutorialBranch)

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
        reel.targetDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        context.insert(reel)
        let filmingTask = CreatorTask(briefID: ready.id, title: "Film the one-job walkthrough", kind: .filming, targetDate: Date(), sortOrder: 0, isRecordingMilestoneDesignated: true)
        context.insert(filmingTask)
        context.insert(CreatorTask(briefID: ready.id, parentTaskID: filmingTask.id, title: "Set the camera", kind: .filming, sortOrder: 0))
        context.insert(CreatorTask(briefID: ready.id, parentTaskID: filmingTask.id, title: "Record two takes", kind: .filming, sortOrder: 1))
        context.insert(CreatorTask(briefID: ready.id, title: "Edit the 45-second cut", kind: .editing, sortOrder: 1))

        let developing = CreativeBrief(title: "What I stopped tracking", premise: "Share why fewer creator metrics created better work.", source: .text, status: .developing)
        developing.pillarID = honestWorkPillar.id
        context.insert(developing)
        context.insert(CreatorTask(
            briefID: developing.id,
            title: "Shape the opening",
            kind: .scripting,
            targetDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())
        ))
        context.insert(WeekPlan(weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date(), rhythmEntriesText: "Monday: choose one idea\nWednesday: film\nFriday: edit and post"))
        try? context.save()
    }
}
