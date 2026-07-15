import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class VoiceExampleTests: XCTestCase {
    func testDeferredOnboardingCreatesNoBlankExamplesOrVoiceProfile() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.adultConfirmed = true
        draft.name = "Ari"
        draft.goal = "Teach practical design"

        let model = AppModel(reminderService: PreviewReminderService())
        await model.completeOnboarding(draft, context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VoiceExample>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VoiceProfile>()).isEmpty)
    }

    func testInstagramPostReferenceCanonicalizesAndRejectsSpoofedHosts() {
        XCTAssertEqual(
            InstagramPostReference.canonicalURL(from: "https://m.instagram.com/reel/ABC123/?igsh=tracking#fragment")?.absoluteString,
            "https://www.instagram.com/reel/ABC123/"
        )
        XCTAssertNil(InstagramPostReference.canonicalURL(from: "http://instagram.com/reel/ABC123"))
        XCTAssertNil(InstagramPostReference.canonicalURL(from: "https://instagram.com.evil.test/reel/ABC123"))
        XCTAssertNil(InstagramPostReference.canonicalURL(from: "https://www.instagram.com/explore/"))
    }

    func testSavingExamplesPersistsOnlyReviewedTextAndLocalProvenance() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true)
        context.insert(profile)
        context.insert(SubscriptionState())
        let model = AppModel(reminderService: PreviewReminderService())
        let postID = UUID()

        XCTAssertTrue(model.saveVoiceExamples([
            VoiceExampleDraft(
                id: postID,
                text: "A caption I wrote.",
                source: .publicPostText,
                sourceURLString: "https://www.instagram.com/p/POST123/?utm_source=copy"
            ),
            VoiceExampleDraft(text: "Words read from my screenshot.", source: .screenshotText),
            VoiceExampleDraft()
        ], context: context))

        let examples = try context.fetch(FetchDescriptor<VoiceExample>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(examples.count, 2)
        XCTAssertEqual(examples.first?.id, postID)
        XCTAssertEqual(examples.first?.source, .publicPostText)
        XCTAssertEqual(examples.first?.sourceURL?.absoluteString, "https://www.instagram.com/p/POST123/")
        XCTAssertTrue(examples.allSatisfy(\.creatorConfirmed))

        let archive = try LocalExportService().makeArchive(context: context)
        let archiveData = try Data(contentsOf: archive)
        XCTAssertNotNil(archiveData.range(of: Data("publicPostText".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("https://www.instagram.com/p/POST123/".utf8)))
        XCTAssertNil(archiveData.range(of: Data("imageData".utf8)))
        XCTAssertNil(archiveData.range(of: Data("imagePath".utf8)))
    }

    func testSavingRejectsExampleOverTwentyThousandUTF16Units() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true))
        context.insert(SubscriptionState())
        let model = AppModel(reminderService: PreviewReminderService())

        let text = String(repeating: "😀", count: 10_001)
        XCTAssertLessThan(text.count, VoiceExampleEvidenceLimits.maximumExampleUTF16Units)
        XCTAssertFalse(model.saveVoiceExamples([VoiceExampleDraft(text: text)], context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<VoiceExample>()).isEmpty)
        XCTAssertTrue(model.notice?.message.contains("20,000") == true)
        XCTAssertTrue(model.notice?.message.contains("UTF-16") == true)
    }

    func testOnboardingRejectsCombinedEvidenceOverFortyThousandUTF8BytesWithoutPartialData() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.adultConfirmed = true
        draft.name = "Ari"
        draft.goal = "Teach"
        draft.voiceExamples = [
            VoiceExampleDraft(text: String(repeating: "a", count: 20_000)),
            VoiceExampleDraft(text: String(repeating: "b", count: 20_000)),
            VoiceExampleDraft(text: "c")
        ]
        let model = AppModel(reminderService: PreviewReminderService())

        let completed = await model.completeOnboarding(draft, context: context)

        XCTAssertFalse(completed)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VoiceExample>()).isEmpty)
        XCTAssertTrue(model.notice?.message.contains("40,000") == true)
        XCTAssertTrue(model.notice?.message.contains("UTF-8") == true)
    }

    func testFingerprintUsesOnlyAIVisibleEvidenceAndIgnoresLocalInstagramURL() {
        let id = UUID()
        let first = VoiceExampleDraft(
            id: id,
            text: "A caption I wrote.",
            source: .publicPostText,
            sourceURLString: "https://www.instagram.com/p/FIRST/"
        )
        let second = VoiceExampleDraft(
            id: id,
            text: "A caption I wrote.",
            source: .publicPostText,
            sourceURLString: "https://www.instagram.com/reel/SECOND/"
        )

        XCTAssertEqual(VoiceExampleFingerprint.make(from: [first]), VoiceExampleFingerprint.make(from: [second]))
    }

    func testInitialVoiceProfileCanBeBuiltAfterFreeBriefWasConsumed() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        let access = SubscriptionState()
        access.freeBriefConsumed = true
        context.insert(access)
        let model = AppModel(reminderService: PreviewReminderService())
        let drafts = (0..<3).map {
            VoiceExampleDraft(text: "Example \($0) with a real practical point.", source: $0 == 2 ? .screenshotText : .text)
        }
        XCTAssertTrue(model.saveVoiceExamples(drafts, context: context))

        let prepared = await model.prepareInitialVoiceProfile(context: context)
        let proposal = try XCTUnwrap(prepared)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).first?.proposalKindRaw, "initial")

        let relaunched = AppModel(reminderService: PreviewReminderService())
        XCTAssertEqual(relaunched.initialVoiceProfileProposal(context: context)?.id, proposal.id)
        relaunched.acceptInitialVoiceProfile(proposal, context: context)

        let approved = try XCTUnwrap(relaunched.approvedVoiceProfile(context: context))
        XCTAssertTrue(approved.isApproved)
        XCTAssertFalse(approved.evidenceFingerprint.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).isEmpty)
    }

    func testSavingUnchangedEvidencePreservesPendingInitialProposal() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Ari", goal: "Teach", adultConfirmed: true, onboardingCompleted: true)
        context.insert(profile)
        context.insert(SubscriptionState())
        let model = AppModel(reminderService: PreviewReminderService())
        let drafts = (0..<3).map { index in
            VoiceExampleDraft(
                text: "Example \(index) with a real practical point.",
                source: index == 0 ? .publicPostText : .text,
                sourceURLString: index == 0 ? "https://www.instagram.com/p/FIRST/" : ""
            )
        }
        XCTAssertTrue(model.saveVoiceExamples(drafts, context: context))
        let prepared = await model.prepareInitialVoiceProfile(context: context)
        let proposal = try XCTUnwrap(prepared)

        var localReferenceEdit = drafts
        localReferenceEdit[0].sourceURLString = "https://www.instagram.com/reel/SECOND/"
        XCTAssertTrue(model.saveVoiceExamples(localReferenceEdit, context: context))

        XCTAssertEqual(model.initialVoiceProfileProposal(context: context)?.id, proposal.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>()).filter { $0.proposalKindRaw == "initial" }.count,
            1
        )
    }

    func testOnboardingPersistsPaperSetupWithoutGeneratingVoiceProfile() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let anchorID = UUID()
        let branchID = UUID()
        var draft = OnboardingDraft()
        draft.adultConfirmed = true
        draft.name = "Ari"
        draft.goal = "Teach practical design"
        draft.platforms = [.instagramReels, .youtubeShorts]
        draft.pillars = [
            OnboardingPillarDraft(id: anchorID, name: "Design", colorHex: "55705B", assignedWeekdays: [.monday]),
            OnboardingPillarDraft(id: branchID, name: "Tools", colorHex: "416B85", assignedWeekdays: [.thursday]),
        ]
        draft.voiceExamples = [VoiceExampleDraft(text: "A real caption in my voice.")]
        draft.accountHandles[.instagram] = "@ari.designs"
        let model = AppModel(reminderService: PreviewReminderService())

        let completed = await model.completeOnboarding(draft, context: context)
        XCTAssertTrue(completed)

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<CreatorProfile>()).first)
        XCTAssertTrue(profile.onboardingCompleted)
        XCTAssertEqual(profile.assistanceMode, .collaborate)
        XCTAssertEqual(Set(profile.selectedPlatforms), [.instagramReels, .youtubeShorts])

        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let anchor = try XCTUnwrap(pillars.first(where: { $0.id == anchorID }))
        let branch = try XCTUnwrap(pillars.first(where: { $0.id == branchID }))
        XCTAssertEqual(anchor.role, .anchor)
        XCTAssertNil(anchor.parentPillarID)
        XCTAssertEqual(branch.role, .supporting)
        XCTAssertEqual(branch.parentPillarID, anchorID)
        XCTAssertEqual(branch.colorHex, "416B85")

        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreatorSocialAccount>()).first)
        XCTAssertEqual(account.label, "@ari.designs")
        XCTAssertEqual(account.profileURLString, "https://www.instagram.com/ari.designs/")
        XCTAssertEqual(try context.fetch(FetchDescriptor<VoiceExample>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VoiceProfile>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderSettings>()).count, 1)
    }

    func testOnboardingCompletionIsIdempotent() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.adultConfirmed = true
        draft.name = "Ari"
        draft.goal = "Create consistently"
        draft.pillars = [OnboardingPillarDraft(name: "Lifestyle")]
        let model = AppModel(reminderService: PreviewReminderService())

        let firstCompletion = await model.completeOnboarding(draft, context: context)
        let secondCompletion = await model.completeOnboarding(draft, context: context)
        XCTAssertTrue(firstCompletion)
        XCTAssertTrue(secondCompletion)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CreatorProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pillar>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderSettings>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SubscriptionState>()).count, 1)
    }

    func testOnboardingRejectsMissingGoalWithoutPartialData() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        var draft = OnboardingDraft()
        draft.adultConfirmed = true
        draft.name = "Ari"
        let model = AppModel(reminderService: PreviewReminderService())

        let completed = await model.completeOnboarding(draft, context: context)
        XCTAssertFalse(completed)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Pillar>()).isEmpty)
    }

    func testScreenshotTextJoiningDropsBlankLines() {
        XCTAssertEqual(
            OnDeviceScreenshotTextRecognizer.joinedText(from: ["  First line ", "", "Second line\n"]),
            "First line\nSecond line"
        )
    }

    func testDeferredVoiceExtractionAccessSurvivesFreeBriefConsumption() {
        let state = SubscriptionState(access: .freeJourney)
        state.freeBriefConsumed = true
        XCTAssertTrue(AccessPolicy.allows(.extractVoiceProfile, state: state))
        state.access = .expired
        XCTAssertFalse(AccessPolicy.allows(.extractVoiceProfile, state: state))
    }
}
