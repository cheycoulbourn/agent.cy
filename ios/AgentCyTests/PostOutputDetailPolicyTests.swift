import XCTest
import UIKit
@testable import AgentCy

final class PostOutputDetailPolicyTests: XCTestCase {
    func testAppearancePreferencesMapToWindowStyles() {
        XCTAssertEqual(AppearancePreference.system.userInterfaceStyle, .unspecified)
        XCTAssertEqual(AppearancePreference.light.userInterfaceStyle, .light)
        XCTAssertEqual(AppearancePreference.dark.userInterfaceStyle, .dark)
    }

    func testMCPReviewEditingIsAvailableForExistingPostChanges() {
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "updatePost"))
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "schedulePost"))
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "createPostDraft"))
        XCTAssertTrue(MCPReviewEditPolicy.allowsEditing(type: "createSeriesEpisode"))
        XCTAssertFalse(MCPReviewEditPolicy.allowsEditing(type: "addTask"))
    }

    func testMCPSeriesReviewBundleKeepsSeriesFirstAndOrdersEpisodes() {
        let seriesID = UUID()
        let pillarID = UUID()
        let series = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeries",
            payload: MCPBridgeRequestPayload(pillarId: pillarID, name: "Data Diaries", seriesId: seriesID)
        )
        let second = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(title: "Second", seriesId: seriesID, episodeNumber: 2)
        )
        let first = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(title: "First", seriesId: seriesID, episodeNumber: 1)
        )

        let bundle = MCPSeriesReviewBundle(series: series, episodes: [second, first])

        XCTAssertEqual(bundle.episodes.map(\.payload.episodeNumber), [1, 2])
        XCTAssertEqual(bundle.requests.map(\.id), [series.id, first.id, second.id])
    }

    func testMCPIdeaReviewKeepsItsPillarNameAndIdentifiesMetadataAsAnIdea() {
        XCTAssertEqual(
            MCPReviewPillarPresentation.label(type: "createIdea", pillarName: "Lifestyle"),
            "Lifestyle"
        )
        XCTAssertEqual(
            MCPReviewPillarPresentation.label(type: "createIdea", pillarName: "Unfiled"),
            "Unfiled"
        )
        XCTAssertEqual(
            MCPReviewPillarPresentation.metadata(type: "createIdea", fallback: "Post"),
            "Idea"
        )
    }

    func testMCPPostReviewKeepsPostPillarAndMetadata() {
        XCTAssertEqual(
            MCPReviewPillarPresentation.label(type: "createPostDraft", pillarName: "Lifestyle"),
            "Lifestyle"
        )
        XCTAssertEqual(
            MCPReviewPillarPresentation.metadata(type: "createPostDraft", fallback: "Instagram"),
            "Instagram"
        )
    }

    func testDatedDraftOnScheduledBriefAlwaysResumesPostEditor() {
        XCTAssertEqual(
            PostOutputDetailPolicy.destination(
                briefStatus: .scheduled,
                outputStatus: .draft,
                targetDate: Date()
            ),
            .draftEditor
        )
    }

    func testScheduledAndPostedOutputsUseFinalizedDetail() {
        XCTAssertTrue(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .scheduled, targetDate: nil))
        XCTAssertTrue(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .posted, targetDate: nil))
    }

    func testReadyOutputWithDateUsesFinalizedDetail() {
        XCTAssertTrue(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .ready, targetDate: Date()))
    }

    func testDraftAndUnscheduledReadyOutputsKeepTheirCreationFlow() {
        XCTAssertFalse(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .draft, targetDate: Date()))
        XCTAssertFalse(PostOutputDetailPolicy.usesFinalizedView(outputStatus: .ready, targetDate: nil))
    }

    func testPastScheduledPostKeepsItsStatusWhileUsingLatePresentation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertTrue(FinalizedPostPresentation.isMissed(
            outputStatus: .scheduled,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(FinalizedPostPresentation.pageTitle(
            outputStatus: .scheduled,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "Scheduled post")
        XCTAssertEqual(FinalizedPostPresentation.statusTitle(
            outputStatus: .scheduled,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "SCHEDULED")
    }

    func testPastReadyPostKeepsReadyStatusWhileUsingLatePresentation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertTrue(FinalizedPostPresentation.isMissed(
            outputStatus: .ready,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(FinalizedPostPresentation.statusTitle(
            outputStatus: .ready,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "READY")
    }

    func testPostedPostNeverUsesMissedPresentation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertFalse(FinalizedPostPresentation.isMissed(
            outputStatus: .posted,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(FinalizedPostPresentation.pageTitle(
            outputStatus: .posted,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "Posted")
        XCTAssertEqual(FinalizedPostPresentation.statusTitle(
            outputStatus: .posted,
            targetDate: yesterday,
            now: now,
            calendar: calendar
        ), "POSTED")
    }

    func testBottomPostActionUsesScheduledDateAndLateTiming() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 17,
            hour: 12
        )))
        let earlierToday = try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: now))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))

        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .draft,
            scheduledDate: nil,
            includesScheduledTime: false,
            now: now,
            calendar: calendar
        ), .schedule)
        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .scheduled,
            scheduledDate: tomorrow,
            includesScheduledTime: false,
            now: now,
            calendar: calendar
        ), .markPosted)
        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .scheduled,
            scheduledDate: yesterday,
            includesScheduledTime: false,
            now: now,
            calendar: calendar
        ), .markPostedAndReschedule)
        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .scheduled,
            scheduledDate: earlierToday,
            includesScheduledTime: false,
            now: now,
            calendar: calendar
        ), .markPosted)
        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .scheduled,
            scheduledDate: earlierToday,
            includesScheduledTime: true,
            now: now,
            calendar: calendar
        ), .markPostedAndReschedule)
        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .posted,
            scheduledDate: yesterday,
            includesScheduledTime: true,
            now: now,
            calendar: calendar
        ), .markNotPosted)
    }

    func testSuggestedAgendaDateRemainsAScheduleActionUntilCommitted() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let selectedDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 17,
            hour: 12
        )))
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: selectedDay))

        XCTAssertEqual(PostBottomActionPolicy.action(
            outputStatus: .draft,
            scheduledDate: selectedDay,
            includesScheduledTime: false,
            hasPersistedScheduledDate: false,
            now: later,
            calendar: calendar
        ), .schedule)
        XCTAssertEqual(
            PostScheduleActionPresentation.title(
                suggestedDate: selectedDay,
                hasPersistedScheduledDate: false,
                calendar: calendar,
                locale: Locale(identifier: "en_US")
            ),
            "Schedule for Monday, Aug 17"
        )
        XCTAssertTrue(PostScheduleActionPresentation.shouldScheduleImmediately(
            suggestedDate: selectedDay,
            hasPersistedScheduledDate: false
        ))
    }

    func testLinkedTaskUsesItsExactPlatformOutput() {
        let brief = CreativeBrief(title: "DITL vlog")
        let other = PlatformOutput(briefID: brief.id, platform: .tiktok)
        other.status = .scheduled
        let linked = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        linked.status = .scheduled
        let task = CreatorTask(
            briefID: brief.id,
            platformOutputID: linked.id,
            title: "Film the vlog"
        )

        XCTAssertEqual(TaskLinkedPostPolicy.output(for: task, in: [other, linked])?.id, linked.id)
    }

    func testLegacyLinkedTaskPrefersFinalizedOutputForItsBrief() {
        let brief = CreativeBrief(title: "DITL vlog")
        let unrelated = PlatformOutput(briefID: UUID(), platform: .youtubeShorts)
        unrelated.status = .scheduled
        let draft = PlatformOutput(briefID: brief.id, platform: .tiktok)
        draft.status = .draft
        let scheduled = PlatformOutput(briefID: brief.id, platform: .instagramReels)
        scheduled.status = .scheduled
        let task = CreatorTask(briefID: brief.id, title: "Film the vlog")

        XCTAssertEqual(
            TaskLinkedPostPolicy.output(for: task, in: [unrelated, draft, scheduled])?.id,
            scheduled.id
        )
    }
}
