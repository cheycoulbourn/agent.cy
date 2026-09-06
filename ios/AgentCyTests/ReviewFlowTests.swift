import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class ReviewFlowTests: XCTestCase {
    func testClosingCompositionPreservesEditsWithoutAcceptingThePost() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Original post", premise: "Original premise")
        context.insert(brief)
        var proposal = ReviewFlowPreview.proposal(for: brief)
        context.insert(try pending(proposal, briefID: brief.id))
        try context.save()
        let model = AppModel(reminderService: PreviewReminderService())
        model.briefProposals[brief.id] = proposal
        proposal.draft.title = "My reviewed title"
        proposal.draft.spokenHook = "My reviewed hook"
        XCTAssertTrue(model.saveProposalReview(proposal, for: brief, context: context))
        XCTAssertEqual(model.proposal(for: brief, context: context), proposal)
        let reopened = AppModel(reminderService: PreviewReminderService())
        XCTAssertEqual(reopened.proposal(for: brief, context: context), proposal)
        XCTAssertEqual(brief.title, "Original post")
        XCTAssertEqual(brief.premise, "Original premise")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlatformOutput>()), 0)
    }

    func testLateCloseCannotRecreateOrOverwriteAReplacedProposal() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Original")
        context.insert(brief)
        let stale = ReviewFlowPreview.proposal(for: brief)
        let replacement = ReviewFlowPreview.proposal(for: brief)
        let record = try pending(replacement, briefID: brief.id)
        context.insert(record)
        try context.save()
        let model = AppModel(reminderService: PreviewReminderService())
        XCTAssertFalse(model.saveProposalReview(stale, for: brief, context: context))
        XCTAssertEqual(model.proposal(for: brief, context: context), replacement)
        context.delete(record)
        try context.save()
        XCTAssertFalse(model.saveProposalReview(stale, for: brief, context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingBriefProposal>()), 0)
    }

    func testRevisionReviewPreservesItsBaselineAndScope() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Existing post")
        context.insert(brief)
        let baseline = ReviewFlowPreview.proposal(for: brief)
        let canonical = ReadyBriefWire(
            briefId: brief.id, title: "Existing post", premise: "Premise", audience: "Creators",
            creativeGoal: "Teach", desiredTakeaway: "Start small", durationSeconds: 45,
            spokenHook: "Hook", firstFrameText: "First frame", scriptBeats: [], close: "Close",
            ctaIntent: "Save", filmingGuidance: FilmingGuidanceWire(setup: "", shots: [], bRoll: [], delivery: "", editing: "", audio: "", onScreenText: []),
            proposedTasks: [], assumptions: [], voiceConfidence: 0.8, platformVariants: []
        )
        let revision = BriefRevisionProposal(
            briefID: brief.id, sourceUpdatedAt: brief.updatedAt, requestedScope: .spokenHook,
            instruction: "Improve the hook", changedFields: [.spokenHook], explanation: "Clearer opening",
            baseline: baseline, edited: baseline, sourceTaskIDs: [], canonicalBrief: canonical
        )
        context.insert(try pending(revision, briefID: brief.id, kind: "revision"))
        try context.save()
        let model = AppModel(reminderService: PreviewReminderService())
        var edited = baseline
        edited.draft.spokenHook = "Reviewed opening"
        XCTAssertTrue(model.saveProposalReview(edited, for: brief, revisionID: revision.id, context: context))
        let reopened = AppModel(reminderService: PreviewReminderService())
        let saved = try XCTUnwrap(reopened.revisionProposal(for: brief, context: context))
        XCTAssertEqual(saved.edited, edited)
        XCTAssertEqual(saved.baseline, baseline)
        XCTAssertEqual(saved.sourceUpdatedAt, revision.sourceUpdatedAt)
        XCTAssertEqual(saved.requestedScope, .spokenHook)
        XCTAssertEqual(brief.title, "Existing post")
    }

    func testConnectionStatusRequiresLocalAvailabilityOrValidHostedAccess() {
        let now = Date()
        let identity = InstallationIdentity(
            installationID: UUID(), credential: "fixture", access: .comped,
            credentialExpiresAt: now.addingTimeInterval(60), promotionalEntitlementEndsAt: nil, accountID: UUID()
        )
        XCTAssertEqual(CyAvailabilityState.resolve(localAvailable: true, hostedAllowed: false, identity: nil), .localBridge)
        XCTAssertEqual(CyAvailabilityState.resolve(localAvailable: false, hostedAllowed: true, identity: identity, now: now), .hosted)
        XCTAssertEqual(CyAvailabilityState.resolve(localAvailable: false, hostedAllowed: false, identity: identity, now: now), .unavailable)
        XCTAssertEqual(CyAvailabilityState.resolve(localAvailable: false, hostedAllowed: true, identity: nil), .unavailable)
        XCTAssertEqual(CyAvailabilityState.resolve(localAvailable: false, hostedAllowed: true, identity: identity, now: now.addingTimeInterval(61)), .unavailable)
        XCTAssertFalse(CyAvailabilityState.checking.isAvailable)
    }

    func testEpisodeReviewKeepsSeriesDefaultsAndAppliesAnEditedPlatformAndFormat() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(name: "Pillar")
        let series = ContentSeries(name: "Series", pillarID: pillar.id)
        series.defaultPlatform = .instagramReels
        series.defaultDestinationID = PublishingCatalog.instagramID
        series.defaultFormatID = PublishingCatalog.instagramCarouselID
        series.defaultDurationSeconds = 90
        let carousel = PublishingFormat(id: PublishingCatalog.instagramCarouselID, destinationID: PublishingCatalog.instagramID, name: "Carousel", kind: .nonVideo)
        let longVideo = PublishingFormat(id: PublishingCatalog.tiktokLongID, destinationID: PublishingCatalog.tiktokID, name: "Long video", kind: .longVideo)
        context.insert(pillar)
        context.insert(series)
        context.insert(carousel)
        context.insert(longVideo)
        let session = MCPSeriesEpisodeEditSession(
            requestID: UUID(), workspaceID: nil,
            payload: MCPBridgeRequestPayload(title: "Episode", notes: "Notes", seriesId: series.id, workDate: Date()),
            inheritedPillarID: pillar.id, seriesName: series.name, series: series, formats: [carousel, longVideo]
        )
        XCTAssertEqual(session.output.formatID, carousel.id)
        XCTAssertEqual(session.output.durationSeconds, 90)
        XCTAssertEqual(session.brief.ideaBankPlacement, .post)
        session.output.platform = .tiktok
        session.output.destinationID = PublishingCatalog.tiktokID
        session.output.formatID = longVideo.id
        session.output.caption = "Reviewed caption"
        session.brief.spokenHook = "Reviewed hook"
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1, id: session.id, createdAt: Date(), source: "test", workspaceId: nil,
            type: "createSeriesEpisode", payload: session.updatedPayload(formats: [carousel, longVideo])
        )
        try MCPBridgeService.apply(request, context: context)
        let output = try XCTUnwrap(context.fetch(FetchDescriptor<PlatformOutput>()).first)
        let post = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        XCTAssertEqual(output.destinationID, PublishingCatalog.tiktokID)
        XCTAssertEqual(output.formatID, longVideo.id)
        XCTAssertEqual(output.platform, .tiktok)
        XCTAssertEqual(output.caption, "Reviewed caption")
        XCTAssertEqual(post.spokenHook, "Reviewed hook")
    }

    private func pending<T: Encodable>(_ value: T, briefID: UUID, kind: String = "composition") throws -> PendingBriefProposal {
        PendingBriefProposal(briefID: briefID, payloadJSON: String(decoding: try JSONEncoder().encode(value), as: UTF8.self), proposalKindRaw: kind)
    }
}
