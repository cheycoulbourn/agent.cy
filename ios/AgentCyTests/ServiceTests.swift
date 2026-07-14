import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class ServiceTests: XCTestCase {
    func testSparkDevelopmentStateEncodesEmptyFieldsAsExplicitNulls() throws {
        let state = SparkDevelopmentStateWire(
            premise: "Life lately",
            audience: nil,
            creativeGoal: nil,
            proofOrStory: nil,
            desiredTakeaway: nil,
            constraints: []
        )

        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["premise"] as? String, "Life lately")
        XCTAssertTrue(object["audience"] is NSNull)
        XCTAssertTrue(object["creativeGoal"] is NSNull)
        XCTAssertTrue(object["proofOrStory"] is NSNull)
        XCTAssertTrue(object["desiredTakeaway"] is NSNull)
        XCTAssertNotNil(object["constraints"])
    }

#if DEBUG
    func testLiveDebugBuildGrantsPromotionalTestingAccess() async {
        let state = SubscriptionState(access: .expired)
        let service = LocalDevelopmentSubscriptionService()

        await service.refresh(state: state)

        XCTAssertEqual(state.access, .comped)
        XCTAssertGreaterThan(state.trialEnd ?? .distantPast, Date())
    }
#endif

    func testPreviewCreativeServiceProducesExactlyThreeDirections() async throws {
        let service = PreviewCreativeService()
        let ideas = try await service.findIdeas(context: creatorContext(), mode: .collaborate)
        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(Set(ideas.map(\.title)).count, 3)
        XCTAssertTrue(ideas.allSatisfy { !$0.assumption.isEmpty })
    }

    func testCancellingIdeaGenerationDoesNotShowAnErrorNotice() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: CancelledIdeasCreativeService())

        let ideas = await appModel.findIdeas(context: context)

        XCTAssertTrue(ideas.isEmpty)
        XCTAssertNil(appModel.notice)
        XCTAssertFalse(appModel.isWorking)
    }

    func testSuggestionFailureStaysInlineInsteadOfShowingGlobalNotice() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .paid))
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: FailedIdeasCreativeService())

        let outcome = await appModel.findIdeaSuggestions(context: context)

        guard case .unavailable(let message, let requiresUpgrade) = outcome else {
            return XCTFail("Expected an inline unavailable result")
        }
        XCTAssertEqual(message, "The pilot allowance needs refreshing.")
        XCTAssertFalse(requiresUpgrade)
        XCTAssertNil(appModel.notice)
        XCTAssertFalse(appModel.isWorking)
    }

    func testConsumedFreeIdeasReturnUpgradeUpsellWithoutGlobalNotice() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let subscription = SubscriptionState(access: .freeJourney)
        subscription.ideationRequestsUsed = 3
        context.insert(subscription)
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: PreviewCreativeService())

        let outcome = await appModel.findIdeaSuggestions(context: context)

        guard case .unavailable(let message, let requiresUpgrade) = outcome else {
            return XCTFail("Expected an upgrade result")
        }
        XCTAssertEqual(message, "Your three free idea sessions have been used.")
        XCTAssertTrue(requiresUpgrade)
        XCTAssertNil(appModel.notice)
    }

    func testProviderCreditLimitReturnsUpgradeUpsellInsteadOfRetry() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(SubscriptionState(access: .comped))
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: NoCreditsIdeasCreativeService())

        let outcome = await appModel.findIdeaSuggestions(context: context)

        guard case .unavailable(_, let requiresUpgrade) = outcome else {
            return XCTFail("Expected an upgrade result")
        }
        XCTAssertTrue(requiresUpgrade)
        XCTAssertNil(appModel.notice)
    }

    func testIdeaPresentationKeepsUpgradeAndTransientFailuresSeparate() {
        XCTAssertEqual(
            CyIdeaRequestPhase.failure(message: "Access used", requiresUpgrade: true),
            .upgradeRequired(message: "Access used")
        )
        XCTAssertEqual(
            CyIdeaRequestPhase.failure(message: "Offline", requiresUpgrade: false),
            .unavailable(message: "Offline")
        )
    }

    func testVoiceExtractionRequiresThreeExamples() async {
        let service = PreviewCreativeService()
        do {
            _ = try await service.extractVoiceProfile(context: creatorContext(examples: ["One", "Two"]), mode: .collaborate)
            XCTFail("Expected missing input")
        } catch {
            XCTAssertNotNil(error as? CreativeServiceError)
        }
    }

    func testRemoteCreativeServiceRejectsOversizedVoiceEvidenceBeforeNetworkRequest() async {
        let service = RemoteCreativeService()
        let oversized = String(repeating: "😀", count: 10_001)
        let context = creatorContext(examples: [oversized, "Second example", "Third example"])

        do {
            _ = try await service.findIdeas(context: context, mode: .collaborate)
            XCTFail("Expected local voice-evidence validation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Example 1"))
            XCTAssertTrue(error.localizedDescription.contains("20,000"))
            XCTAssertTrue(error.localizedDescription.contains("UTF-16"))
            XCTAssertFalse(error.localizedDescription.contains("app contract"))
        }
    }

    func testExportIsAReadableZipSignatureAndContainsAllEntries() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        let instagram = PublishingDestination(id: PublishingCatalog.instagramID, name: "Instagram")
        context.insert(instagram)
        let socialAccount = CreatorSocialAccount(
            profileID: profile.id,
            destinationID: instagram.id,
            label: "@ari.creates",
            profileURLString: "https://instagram.com/ari.creates",
            isPrimary: true
        )
        context.insert(socialAccount)
        context.insert(VoiceExample(profileID: profile.id, text: "A real example", sortOrder: 0))
        context.insert(VoiceProfile(profileID: profile.id, summary: "Direct", traitsText: "Clear", avoidText: "Hype", isApproved: true))
        context.insert(ReminderSettings())
        context.insert(SubscriptionState())
        context.insert(RhythmTemplate(entriesText: "Monday: plan"))
        context.insert(WeekPlan(rhythmEntriesText: "Monday: plan"))
        let brief = CreativeBrief(title: "Test brief", premise: "A premise", status: .ready)
        context.insert(brief)
        let pending = BriefProposal(
            briefID: brief.id,
            draft: BriefDraft(
                title: "Pending proposal title",
                premise: "A proposed premise",
                audience: "Solo creators",
                goal: "Make the next step clear",
                takeaway: "Start smaller",
                durationSeconds: 45,
                spokenHook: "Start here.",
                firstFrameText: "START HERE",
                scriptBeats: ["Name the friction"],
                close: "Take one step.",
                ctaIntent: "Save the prompt",
                filmingGuidance: "Face camera",
                editingGuidance: "Keep it light",
                assumptions: ["The creator is comfortable on camera"],
                voiceConfidence: 0.8
            ),
            variants: [],
            tasks: []
        )
        let pendingData = try JSONEncoder().encode(pending)
        context.insert(PendingBriefProposal(briefID: brief.id, payloadJSON: String(decoding: pendingData, as: UTF8.self)))
        context.insert(PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            destinationID: instagram.id,
            socialAccountID: socialAccount.id,
            status: .ready
        ))
        context.insert(CreatorTask(briefID: brief.id, title: "Film", kind: .filming))
        context.insert(Pillar(name: "Teaching", detail: "Practical lessons"))
        let thread = ConversationThread(briefID: brief.id, title: "Develop")
        context.insert(thread)
        context.insert(ConversationMessage(threadID: thread.id, role: .creator, text: "A thought"))

        let url = try LocalExportService().makeArchive(context: context)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertNotNil(data.range(of: Data("agentcy-export.json".utf8)))
        XCTAssertNotNil(data.range(of: Data("briefs.md".utf8)))
        XCTAssertNotNil(data.range(of: Data("pendingBriefProposals".utf8)))
        XCTAssertNotNil(data.range(of: Data("Pending proposal title".utf8)))
        XCTAssertNotNil(data.range(of: Data("@ari.creates".utf8)))
        XCTAssertNotNil(data.range(of: Data("https://instagram.com/ari.creates".utf8)))
    }

    func testCanonicalComposeResultDecodesAndMapsToNonpersistentProposal() throws {
        let json = #"""
        {
          "brief": {
            "briefId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "title": "The one-job idea test",
            "premise": "A rough idea becomes usable when it has one audience and one takeaway.",
            "audience": "Solo creators with a half-written note",
            "creativeGoal": "Make the next creative decision easier",
            "desiredTakeaway": "Clarity comes from narrowing.",
            "durationSeconds": 45,
            "spokenHook": "Your idea is carrying too many jobs.",
            "firstFrameText": "ONE IDEA. ONE JOB.",
            "scriptBeats": [{"order":0,"label":"Name the friction","purpose":"Create recognition","script":"Name the overloaded note."}],
            "close": "That is enough structure to continue.",
            "ctaIntent": "Try the prompt on a saved idea.",
            "filmingGuidance": {"setup":"Desk setup","shots":["Medium shot"],"bRoll":["Edit the note"],"delivery":"Calm","editing":"Two cuts","audio":"Clear voice","onScreenText":["One audience"]},
            "proposedTasks": [{"title":"Film the walkthrough","kind":"filming","notes":"Capture one close-up","estimatedMinutes":25,"isRecordingMilestone":true,"order":0}],
            "assumptions": ["The creator is comfortable on camera."],
            "voiceConfidence": 0.84,
            "platformVariants": [{"platform":"instagramReels","caption":"One audience. One takeaway.","editChanges":[]}]
          }
        }
        """#
        let result = try JSONDecoder().decode(ComposeBriefResultWire.self, from: Data(json.utf8))
        let localID = UUID()
        let proposal = result.brief.proposal(for: localID)
        XCTAssertEqual(proposal.briefID, localID)
        XCTAssertEqual(proposal.draft.durationSeconds, 45)
        XCTAssertEqual(proposal.variants.first?.platform, .instagramReels)
        XCTAssertEqual(proposal.tasks.first?.isRecordingMilestone, true)
    }

    func testPreviewRevisionDeterministicallySupportsEveryCanonicalScope() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "contracts/test/fixtures/compose-brief-result.json"))
        let ready = try JSONDecoder().decode(ComposeBriefResultWire.self, from: data).brief
        let baseline = ready.proposal(for: ready.briefId)
        let service = PreviewCreativeService()

        for (index, scope) in BriefRevisionFieldWire.allCases.enumerated() {
            let proposal = try await service.proposeRevision(
                of: ready,
                localBriefID: ready.briefId,
                revisionNumber: index + 1,
                scope: scope,
                instruction: "Make this field more specific.",
                mode: .collaborate,
                context: creatorContext(),
                baseline: baseline,
                sourceUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                sourceTaskIDs: []
            )
            XCTAssertEqual(proposal.changedFields, [scope])
            XCTAssertNotEqual(proposal.edited, baseline)
        }
    }

    private func creatorContext(examples: [String] = ["One useful example", "A second practical example", "A third direct example"]) -> CreatorContextWire {
        CreatorContextWire(
            name: "Ari",
            primaryGoal: "Help new designers",
            selectedPlatforms: [.youtubeShorts],
            voiceExamples: examples.enumerated().map { index, text in
                VoiceExampleWire(exampleId: UUID(), order: index, text: text)
            },
            voiceProfile: nil,
            pillars: [],
            librarySummaries: []
        )
    }
}

@MainActor
private struct CancelledIdeasCreativeService: CreativeServicing {
    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction {
        throw CancellationError()
    }

    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] {
        throw CancellationError()
    }

    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String {
        throw CancellationError()
    }

    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal {
        throw CancellationError()
    }

    func proposeRevision(
        of brief: ReadyBriefWire,
        localBriefID: UUID,
        revisionNumber: Int,
        scope: BriefRevisionFieldWire,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        baseline: BriefProposal,
        sourceUpdatedAt: Date,
        sourceTaskIDs: [UUID]
    ) async throws -> BriefRevisionProposal {
        throw CancellationError()
    }

    func proposeVoiceProfileChange(
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        current: VoiceProfileDraft,
        instruction: String,
        mode: AssistanceMode,
        context: CreatorContextWire
    ) async throws -> VoiceProfileChangeProposal {
        throw CancellationError()
    }

    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String {
        throw CancellationError()
    }
}

@MainActor
private struct FailedIdeasCreativeService: CreativeServicing {
    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction { throw TestError.failed }
    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] { throw TestError.failed }
    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String { throw TestError.failed }
    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal { throw TestError.failed }
    func proposeRevision(of brief: ReadyBriefWire, localBriefID: UUID, revisionNumber: Int, scope: BriefRevisionFieldWire, instruction: String, mode: AssistanceMode, context: CreatorContextWire, baseline: BriefProposal, sourceUpdatedAt: Date, sourceTaskIDs: [UUID]) async throws -> BriefRevisionProposal { throw TestError.failed }
    func proposeVoiceProfileChange(profileID: UUID, sourceVersion: Int, sourceUpdatedAt: Date, current: VoiceProfileDraft, instruction: String, mode: AssistanceMode, context: CreatorContextWire) async throws -> VoiceProfileChangeProposal { throw TestError.failed }
    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String { throw TestError.failed }

    private enum TestError: LocalizedError {
        case failed
        var errorDescription: String? { "The pilot allowance needs refreshing." }
    }
}

@MainActor
private struct NoCreditsIdeasCreativeService: CreativeServicing {
    private var noCreditsError: AgentCyAPIError {
        .server(AIWireError(
            code: .usageLimit,
            message: "Cy does not have generation credits available.",
            retryable: false,
            retryAfterSeconds: nil,
            fieldIssues: nil
        ))
    }

    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction { throw noCreditsError }
    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] { throw noCreditsError }
    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String { throw noCreditsError }
    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal { throw noCreditsError }
    func proposeRevision(of brief: ReadyBriefWire, localBriefID: UUID, revisionNumber: Int, scope: BriefRevisionFieldWire, instruction: String, mode: AssistanceMode, context: CreatorContextWire, baseline: BriefProposal, sourceUpdatedAt: Date, sourceTaskIDs: [UUID]) async throws -> BriefRevisionProposal { throw noCreditsError }
    func proposeVoiceProfileChange(profileID: UUID, sourceVersion: Int, sourceUpdatedAt: Date, current: VoiceProfileDraft, instruction: String, mode: AssistanceMode, context: CreatorContextWire) async throws -> VoiceProfileChangeProposal { throw noCreditsError }
    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String { throw noCreditsError }
}
