import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import AgentCy

@MainActor
final class ServiceTests: XCTestCase {
    func testMCPBridgeBookmarkPolicyUsesSecurityScopeOnlyForMacCatalyst() {
        XCTAssertEqual(
            MCPBridgeBookmarkPolicy.strategy(isMacCatalyst: true),
            .securityScoped
        )
        XCTAssertEqual(
            MCPBridgeBookmarkPolicy.strategy(isMacCatalyst: false),
            .minimal
        )
    }

    func testMCPBridgeMaterializationRequestsTheLogicalFileBehindAnICloudPlaceholder() {
        let root = URL(fileURLWithPath: "/tmp/agent.cy MCP", isDirectory: true)
        let requests = root.appending(path: "requests", directoryHint: .isDirectory)
        let placeholder = requests.appending(path: ".proposal.json.icloud")
        let logical = requests.appending(path: "proposal.json")

        XCTAssertEqual(
            MCPBridgeQueueMaterializationPolicy.logicalURL(forICloudPlaceholder: placeholder),
            logical
        )
        XCTAssertEqual(
            MCPBridgeQueueMaterializationPolicy.downloadCandidates(
                rootDirectory: root,
                requestsDirectory: requests,
                entries: [placeholder]
            ),
            [root, requests, placeholder, logical]
        )
    }

    func testMCPBridgeMaterializationKeepsRetryingWhilePlaceholdersRemain() {
        XCTAssertTrue(MCPBridgeQueueMaterializationPolicy.shouldRetry(
            completedAttempt: MCPBridgeQueueMaterializationPolicy.minimumEmptyRefreshAttempts,
            hasUndownloadedPlaceholders: true,
            requestCount: 0
        ))
        XCTAssertFalse(MCPBridgeQueueMaterializationPolicy.shouldRetry(
            completedAttempt: MCPBridgeQueueMaterializationPolicy.maximumRefreshAttempts - 1,
            hasUndownloadedPlaceholders: true,
            requestCount: 0
        ))
        XCTAssertFalse(MCPBridgeQueueMaterializationPolicy.shouldRetry(
            completedAttempt: MCPBridgeQueueMaterializationPolicy.minimumEmptyRefreshAttempts,
            hasUndownloadedPlaceholders: false,
            requestCount: 0
        ))
    }

    func testBridgePushRegistrationUsesPhoneAsTheSingleNotificationDestination() {
        XCTAssertTrue(BridgePushRegistrationPolicy.shouldRegister(isMacCatalyst: false))
        XCTAssertFalse(BridgePushRegistrationPolicy.shouldRegister(isMacCatalyst: true))
    }

    func testDesktopSnapshotPreservesPhoneCapabilityInsteadOfPublishingStaleMacCapability() throws {
        let phoneCapability = MCPBridgePushCapability(
            endpoint: try XCTUnwrap(URL(string: "https://agentcy.example/v1/bridge/notifications")),
            token: String(repeating: "p", count: 48)
        )
        let staleMacCapability = MCPBridgePushCapability(
            endpoint: try XCTUnwrap(URL(string: "https://agentcy.example/v1/bridge/notifications")),
            token: String(repeating: "m", count: 48)
        )

        XCTAssertEqual(
            BridgePushRegistrationPolicy.snapshotCapability(
                isMacCatalyst: true,
                local: staleMacCapability,
                existing: phoneCapability
            ),
            phoneCapability
        )
        XCTAssertEqual(
            BridgePushRegistrationPolicy.snapshotCapability(
                isMacCatalyst: false,
                local: phoneCapability,
                existing: staleMacCapability
            ),
            phoneCapability
        )
    }

    func testBridgePushRegistrationReusesAnExistingPrivateCapability() throws {
        let capability = MCPBridgePushCapability(
            endpoint: try XCTUnwrap(URL(string: "https://agentcy.example/v1/bridge/notifications")),
            token: String(repeating: "c", count: 48)
        )
        let currentDeviceToken = Data([0x01, 0x02, 0x03])

        XCTAssertTrue(BridgePushRegistrationPolicy.shouldRequestCapability(
            existing: nil,
            registeredDeviceToken: nil,
            currentDeviceToken: currentDeviceToken
        ))
        XCTAssertTrue(BridgePushRegistrationPolicy.shouldRequestCapability(
            existing: capability,
            registeredDeviceToken: nil,
            currentDeviceToken: currentDeviceToken
        ))
        XCTAssertFalse(BridgePushRegistrationPolicy.shouldRequestCapability(
            existing: capability,
            registeredDeviceToken: currentDeviceToken,
            currentDeviceToken: currentDeviceToken
        ))
        XCTAssertTrue(BridgePushRegistrationPolicy.shouldRequestCapability(
            existing: capability,
            registeredDeviceToken: Data([0xFF]),
            currentDeviceToken: currentDeviceToken
        ))
    }

    func testSparkContextUsesVisiblePostContentWhenLegacyPremiseIsEmpty() {
        let brief = CreativeBrief(title: "Anatomy of a rough hit rate")
        brief.spokenHook = "The number is not the whole story."
        brief.scriptBeatsText = "Explain the context behind the result."
        brief.notes = "Keep this direct and evidence-led."
        brief.ctaIntent = "Save this for your next review."

        let text = SparkContextBuilder.text(
            for: brief,
            postContext: "Help me tighten the opening."
        )

        XCTAssertTrue(text.hasPrefix("Anatomy of a rough hit rate"))
        XCTAssertTrue(text.contains(brief.spokenHook))
        XCTAssertTrue(text.contains(brief.scriptBeatsText))
        XCTAssertTrue(text.contains(brief.notes))
        XCTAssertTrue(text.contains(brief.ctaIntent))
        XCTAssertTrue(text.contains("Help me tighten the opening."))
    }

    func testSparkContextDeduplicatesRepeatedVisibleContent() {
        let brief = CreativeBrief(title: "One useful line")
        brief.premise = "One useful line"

        let text = SparkContextBuilder.text(for: brief, postContext: "One useful line")

        XCTAssertEqual(text, "One useful line")
    }

    func testSparkContextRespectsServerUTF16LimitWithEmoji() {
        let brief = CreativeBrief(title: "Emoji-heavy post")
        brief.notes = String(repeating: "😀", count: 10_100)

        let text = SparkContextBuilder.text(for: brief, postContext: nil)

        XCTAssertLessThanOrEqual(text.utf16.count, 20_000)
        XCTAssertTrue(text.hasPrefix("Emoji-heavy post"))
    }

    func testAIRequestNormalizerBoundsRetainedCreatorContext() {
        let context = CreatorContextWire(
            name: String(repeating: "Creator😀", count: 30),
            primaryGoal: String(repeating: "Make useful work 😀 ", count: 300),
            selectedPlatforms: [.instagramReels, .instagramReels, .tiktok],
            voiceExamples: [
                VoiceExampleWire(exampleId: UUID(), order: 0, text: String(repeating: "Old voice data ", count: 2_000))
            ],
            voiceProfile: nil,
            pillars: [],
            librarySummaries: [],
            taskSummaries: []
        )

        let normalized = AIRequestNormalizer.creatorContext(context)

        XCTAssertLessThanOrEqual(normalized.name.utf16.count, 80)
        XCTAssertLessThanOrEqual(normalized.primaryGoal.utf16.count, 2_000)
        XCTAssertEqual(normalized.selectedPlatforms, [.instagramReels, .tiktok])
        XCTAssertTrue(normalized.voiceExamples.isEmpty)
        XCTAssertNil(normalized.voiceProfile)
    }

    func testAIRequestNormalizerBoundsConversationAndWorkingState() {
        let oversized = String(repeating: "😀", count: 10_100)
        let messages = (0..<20).map { index in
            ConversationMessageWire(
                messageId: UUID(),
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: oversized
            )
        }
        let state = SparkDevelopmentStateWire(
            premise: oversized,
            audience: oversized,
            creativeGoal: oversized,
            proofOrStory: oversized,
            desiredTakeaway: oversized,
            constraints: Array(repeating: oversized, count: 12)
        )

        let normalizedMessages = AIRequestNormalizer.conversation(messages, limit: 16)
        let normalizedState = AIRequestNormalizer.developmentState(state)

        XCTAssertEqual(normalizedMessages.count, 16)
        XCTAssertTrue(normalizedMessages.allSatisfy { $0.content.utf16.count <= 20_000 })
        XCTAssertLessThanOrEqual(normalizedState.premise?.utf16.count ?? 0, 2_000)
        XCTAssertEqual(normalizedState.constraints.count, 10)
        XCTAssertTrue(normalizedState.constraints.allSatisfy { $0.utf16.count <= 2_000 })
    }

    func testInvalidHostedRequestDoesNotBlameCreatorForHiddenFields() {
        let error = AIWireError(
            code: .invalidInput,
            message: "Invalid request",
            retryable: false,
            retryAfterSeconds: nil,
            quotaScope: nil,
            fieldIssues: nil
        )

        let presentation = CreatorFacingErrorMapper.presentation(for: error)

        XCTAssertEqual(presentation.message, "Cy couldn’t read this post yet. Your work is saved.")
        XCTAssertFalse(presentation.canRetry)
    }

    func testInspirationContentErrorExplainsWhatCyNeeds() {
        let presentation = CreatorFacingErrorMapper.presentation(
            for: InspirationContentAnalysisError.insufficientSourceContent,
            action: "This inspiration"
        )

        XCTAssertTrue(presentation.message.contains("could not access enough of this post"))
        XCTAssertFalse(presentation.canRetry)
    }

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

    func testPreviewCreativeServiceProducesExactlyThreeDirections() async throws {
        let service = PreviewCreativeService()
        let ideas = try await service.findIdeas(context: creatorContext(), mode: .collaborate)
        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(Set(ideas.map(\.title)).count, 3)
        XCTAssertTrue(ideas.allSatisfy { !$0.assumption.isEmpty })
    }

    func testPreviewCreativeServiceDoesNotAssignEveryIdeaToTheFirstPillar() async throws {
        let pillarIDs = [UUID(), UUID(), UUID()]
        let base = creatorContext()
        let context = CreatorContextWire(
            name: base.name,
            primaryGoal: base.primaryGoal,
            selectedPlatforms: base.selectedPlatforms,
            voiceExamples: base.voiceExamples,
            voiceProfile: base.voiceProfile,
            pillars: zip(pillarIDs, ["Lifestyle", "Beauty", "Tech"]).map { id, name in
                PillarSummaryWire(pillarId: id, name: name, description: nil)
            },
            librarySummaries: base.librarySummaries,
            taskSummaries: base.taskSummaries
        )

        let ideas = try await PreviewCreativeService().findIdeas(context: context, mode: .collaborate)

        XCTAssertEqual(ideas.map(\.suggestedPillarID), pillarIDs.map(Optional.some))
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

    func testCancellingPostCompositionDoesNotStageAProposalOrShowAnErrorNotice() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        )
        context.insert(SubscriptionState(access: .paid))
        context.insert(profile)
        for index in 0..<3 {
            context.insert(VoiceExample(
                profileID: profile.id,
                text: "Creator-owned example \(index) with a clear practical point.",
                sortOrder: index
            ))
        }
        let brief = CreativeBrief(title: "Keep this spark", premise: "A useful starting point")
        context.insert(brief)
        try context.save()
        let appModel = AppModel(
            creativeService: CancelledIdeasCreativeService(),
            reminderService: PreviewReminderService()
        )

        let succeeded = await appModel.compose(brief: brief, context: context)

        XCTAssertFalse(succeeded)
        XCTAssertNil(appModel.proposal(for: brief, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingBriefProposal>()).isEmpty)
        XCTAssertEqual(brief.status, .spark)
        XCTAssertNil(appModel.notice)
        XCTAssertFalse(appModel.isWorking)
    }

    func testCancellingPostDialogueDoesNotAppendMessagesOrShowAnErrorNotice() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        )
        context.insert(SubscriptionState(access: .paid))
        context.insert(profile)
        for index in 0..<3 {
            context.insert(VoiceExample(
                profileID: profile.id,
                text: "Creator-owned example \(index) with a clear practical point.",
                sortOrder: index
            ))
        }
        let brief = CreativeBrief(title: "Keep this spark", premise: "A useful starting point")
        context.insert(brief)
        try context.save()
        let appModel = AppModel(
            creativeService: CancelledIdeasCreativeService(),
            reminderService: PreviewReminderService()
        )
        let thread = appModel.developmentThread(for: brief, context: context)
        let originalMessageIDs = appModel.messages(for: thread, context: context).map(\.id)

        let succeeded = await appModel.sendDialogueTurn(
            brief: brief,
            answer: "Help me sharpen this",
            context: context
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(appModel.messages(for: thread, context: context).map(\.id), originalMessageIDs)
        XCTAssertEqual(thread.turnCount, 0)
        XCTAssertEqual(brief.status, .spark)
        XCTAssertNil(appModel.notice)
        XCTAssertFalse(appModel.isWorking)
    }

    func testDevelopBriefIgnoresASecondDialogueRequestWhileTheFirstIsRunning() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        )
        context.insert(SubscriptionState(access: .paid))
        context.insert(profile)
        for index in 0..<3 {
            context.insert(VoiceExample(
                profileID: profile.id,
                text: "Creator-owned example \(index) with a clear practical point.",
                sortOrder: index
            ))
        }
        let brief = CreativeBrief(title: "Keep this spark", premise: "A useful starting point")
        context.insert(brief)
        try context.save()
        let appModel = AppModel(
            creativeService: SlowDialogueCreativeService(),
            reminderService: PreviewReminderService()
        )
        let thread = appModel.developmentThread(for: brief, context: context)
        let originalMessageCount = appModel.messages(for: thread, context: context).count

        let first = Task { @MainActor in
            await appModel.sendDialogueTurn(brief: brief, answer: "First request", context: context)
        }
        let second = Task { @MainActor in
            await appModel.sendDialogueTurn(brief: brief, answer: "Second request", context: context)
        }
        let firstSucceeded = await first.value
        let secondSucceeded = await second.value

        XCTAssertEqual([firstSucceeded, secondSucceeded].filter { $0 }.count, 1)
        XCTAssertEqual(thread.turnCount, 1)
        XCTAssertEqual(appModel.messages(for: thread, context: context).count, originalMessageCount + 2)
        XCTAssertEqual(brief.status, .developing)
        XCTAssertFalse(appModel.isWorking)
    }

    func testFailedPostDialoguePreservesTheSparkAndReportsFailure() async throws {
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
        let brief = CreativeBrief(title: "Keep this spark", premise: "A useful starting point")
        context.insert(brief)
        try context.save()
        let appModel = AppModel(
            creativeService: FailedIdeasCreativeService(),
            reminderService: PreviewReminderService()
        )
        let thread = appModel.developmentThread(for: brief, context: context)
        let originalMessageIDs = appModel.messages(for: thread, context: context).map(\.id)

        let succeeded = await appModel.sendDialogueTurn(
            brief: brief,
            answer: "Keep this available for retry",
            context: context
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(appModel.messages(for: thread, context: context).map(\.id), originalMessageIDs)
        XCTAssertEqual(brief.status, .spark)
        XCTAssertEqual(appModel.notice?.message, "Cy couldn’t be completed. Your work is saved. Try again.")
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

    func testProviderCreditFailureDoesNotOfferAnUpgradeThatCannotFixIt() async throws {
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
            return XCTFail("Expected an inline unavailable result")
        }
        XCTAssertFalse(requiresUpgrade)
        XCTAssertNil(appModel.notice)
    }

    func testFailedIdeaGenerationDoesNotConsumeFreeAllowance() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let subscription = SubscriptionState(access: .freeJourney)
        context.insert(subscription)
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: FailedIdeasCreativeService())

        _ = await appModel.findIdeaSuggestions(context: context)

        XCTAssertEqual(subscription.ideationRequestsUsed, 0)
    }

    func testSuccessfulHostedIdeasConsumeAllowanceOnlyAfterSuccess() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let subscription = SubscriptionState(access: .freeJourney)
        context.insert(subscription)
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: ProviderIdeasCreativeService(provider: .hosted))

        let outcome = await appModel.findIdeaSuggestions(context: context)

        guard case .success(let ideas) = outcome else {
            return XCTFail("Expected hosted ideas to succeed")
        }
        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(subscription.ideationRequestsUsed, 1)
    }

    func testSuccessfulLocalBridgeIdeasDoNotConsumeHostedAllowance() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let subscription = SubscriptionState(access: .freeJourney)
        context.insert(subscription)
        context.insert(CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        ))
        try context.save()
        let appModel = AppModel(creativeService: ProviderIdeasCreativeService(provider: .localBridge))

        let outcome = await appModel.findIdeaSuggestions(context: context)

        guard case .success(let ideas) = outcome else {
            return XCTFail("Expected local bridge ideas to succeed")
        }
        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(subscription.ideationRequestsUsed, 0)
    }

    func testAskCyReceivesIncompletePostsAndCurrentTaskContext() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(
            name: "Chey",
            goal: "Create useful content",
            selectedPlatforms: [.instagramReels],
            adultConfirmed: true,
            onboardingCompleted: true
        )
        let pillar = Pillar(name: "Lifestyle", colorHex: "55705B")
        let post = CreativeBrief(title: "DITL vlog", premise: "", status: .scheduled)
        post.pillarID = pillar.id
        post.notes = "Show the unpolished version of the day."
        post.spokenHook = "This is what the day actually looked like."
        let output = PlatformOutput(briefID: post.id, platform: .instagramReels, status: .scheduled)
        output.caption = "A real day, not a perfect routine."
        output.targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        let task = CreatorTask(
            briefID: post.id,
            pillarID: pillar.id,
            platformOutputID: output.id,
            title: "Edit the first cut",
            kind: .editing,
            priority: .high,
            targetDate: output.targetDate
        )
        context.insert(profile)
        context.insert(SubscriptionState(access: .paid))
        context.insert(pillar)
        context.insert(post)
        context.insert(output)
        context.insert(task)
        try context.save()

        let service = CapturingChatCreativeService()
        let appModel = AppModel(creativeService: service)
        _ = await appModel.askCy("What do I have planned?", context: context)

        let captured = try XCTUnwrap(service.capturedContext)
        let postSummary = try XCTUnwrap(captured.librarySummaries.first { $0.briefId == post.id })
        XCTAssertNil(postSummary.premise)
        XCTAssertEqual(postSummary.notes, "Show the unpolished version of the day.")
        XCTAssertEqual(postSummary.hook, "This is what the day actually looked like.")
        XCTAssertEqual(postSummary.caption, "A real day, not a perfect routine.")
        XCTAssertEqual(postSummary.pillarName, "Lifestyle")
        XCTAssertEqual(postSummary.targetDate, output.targetDate)
        XCTAssertEqual(postSummary.taskCount, 1)
        XCTAssertEqual(postSummary.completedTaskCount, 0)
        let taskSummary = try XCTUnwrap(captured.taskSummaries.first { $0.taskId == task.id })
        XCTAssertEqual(taskSummary.title, "Edit the first cut")
        XCTAssertEqual(taskSummary.priority, .high)
        XCTAssertEqual(taskSummary.postId, post.id)
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

    func testAIRequestNormalizerExcludesOversizedDormantVoiceEvidence() {
        let oversized = String(repeating: "😀", count: 10_001)
        let context = creatorContext(examples: [oversized, "Second example", "Third example"])
        let normalized = AIRequestNormalizer.creatorContext(context)

        XCTAssertTrue(normalized.voiceExamples.isEmpty)
        XCTAssertNil(normalized.voiceProfile)
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
        XCTAssertNotNil(data.range(of: Data("posts.md".utf8)))
        XCTAssertNotNil(data.range(of: Data("pendingBriefProposals".utf8)))
        XCTAssertNotNil(data.range(of: Data("Pending proposal title".utf8)))
        XCTAssertNotNil(data.range(of: Data("@ari.creates".utf8)))
        XCTAssertNotNil(data.range(of: Data("https://instagram.com/ari.creates".utf8)))
    }

    func testExportSanitizesAttachmentArchivePaths() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "Attachment", premise: "Keep the export safe")
        context.insert(brief)
        let attachmentID = UUID()
        context.insert(CreatorAttachment(
            id: attachmentID,
            ownerKind: .referenceFile,
            briefID: brief.id,
            fileName: "../../private\nname.txt",
            kind: .document,
            uniformTypeIdentifier: "public.plain-text",
            byteCount: 4,
            localRelativePath: "",
            cloudData: Data("safe".utf8),
            syncState: .synced
        ))

        let url = try LocalExportService().makeArchive(context: context)
        let data = try Data(contentsOf: url)
        let safePath = "attachments/\(attachmentID.uuidString)-private_name.txt"
        let unsafePath = "attachments/\(attachmentID.uuidString)-../../"

        XCTAssertNotNil(data.range(of: Data(safePath.utf8)))
        XCTAssertNil(data.range(of: Data(unsafePath.utf8)))
    }

    func testPostMarkdownExportCreatesCleanNotionReadyHandoff() {
        let brief = CreativeBrief(
            title: "The small shift",
            premise: "Show the useful change behind the result.",
            status: .scheduled
        )
        brief.spokenHook = "The result was not the part that changed everything."
        brief.scriptBeats = ["Name the old approach.", "Show the turning point."]
        brief.notes = "Keep the delivery conversational."
        brief.isBrandCollaboration = true
        brief.brandName = "North Star"
        brief.compensationType = .paid
        brief.compensationAmount = 750
        brief.compensationCurrencyCode = "USD"

        let pillar = Pillar(name: "Lifestyle", colorHex: "FED3FF")
        brief.pillarID = pillar.id
        let destination = PublishingDestination(name: "Instagram", builtInKind: .instagram)
        let format = PublishingFormat(destinationID: destination.id, name: "Reel", kind: .shortVideo)
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            destinationID: destination.id,
            formatID: format.id,
            durationSeconds: 45,
            status: .scheduled
        )
        output.caption = "Save this for the next time you feel stuck."
        output.targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        output.includesTargetTime = true

        let task = CreatorTask(
            briefID: brief.id,
            title: "Film the talking head",
            kind: .filming,
            priority: .high
        )
        let attachment = CreatorAttachment(
            ownerKind: .postMedia,
            briefID: brief.id,
            platformOutputID: output.id,
            fileName: "opening-shot.mov",
            kind: .video,
            uniformTypeIdentifier: "public.movie",
            byteCount: 42,
            localRelativePath: ""
        )

        let markdown = PostMarkdownExporter.makeMarkdown(
            brief: brief,
            outputs: [output],
            tasks: [task],
            pillar: pillar,
            destinations: [destination],
            formats: [format],
            socialAccounts: [],
            attachments: [attachment],
            exportedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        XCTAssertTrue(markdown.hasPrefix("# The small shift\n"))
        XCTAssertTrue(markdown.contains("## Overview"))
        XCTAssertTrue(markdown.contains("- **Status:** Scheduled"))
        XCTAssertTrue(markdown.contains("- **Pillar:** Lifestyle"))
        XCTAssertTrue(markdown.contains("### Instagram · Reel"))
        XCTAssertTrue(markdown.contains("#### Caption"))
        XCTAssertTrue(markdown.contains("## Brand collaboration"))
        XCTAssertTrue(markdown.contains("- [ ] Film the talking head — Filming · High"))
        XCTAssertTrue(markdown.contains("- **Post media:** opening-shot.mov"))
        XCTAssertFalse(markdown.contains("## First-frame text"))
        XCTAssertFalse(markdown.contains(brief.id.uuidString))
        XCTAssertEqual(PostMarkdownExporter.defaultFileName(for: brief), "the-small-shift.md")
    }

    func testMCPBridgeSnapshotIncludesCleanPostHandoffWithoutAttachmentBytes() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profile = CreatorProfile(name: "Chey", goal: "Create consistently")
        let pillar = Pillar(role: .anchor, name: "Lifestyle", colorHex: "fed3ff", assignedWeekdays: [.monday])
        let brief = CreativeBrief(title: "A clear handoff", premise: "Keep the idea useful.", status: .ready)
        brief.pillarID = pillar.id
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready)
        output.caption = "A finished caption."
        let task = CreatorTask(briefID: brief.id, title: "Film opening", kind: .filming)
        let attachment = CreatorAttachment(
            ownerKind: .postMedia,
            briefID: brief.id,
            fileName: "private-image.jpg",
            kind: .photo,
            uniformTypeIdentifier: "public.jpeg",
            byteCount: 4,
            localRelativePath: "",
            cloudData: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        context.insert(profile)
        context.insert(pillar)
        context.insert(brief)
        context.insert(output)
        context.insert(task)
        context.insert(attachment)

        let snapshot = try MCPBridgeService.makeSnapshot(context: context)
        let post = try XCTUnwrap(snapshot.posts.first)
        let data = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedPillars = try XCTUnwrap(object["pillars"] as? [[String: Any]])
        let encodedPosts = try XCTUnwrap(object["posts"] as? [[String: Any]])
        let encodedOutputs = try XCTUnwrap(encodedPosts.first?["outputs"] as? [[String: Any]])
        let encodedTasks = try XCTUnwrap(encodedPosts.first?["tasks"] as? [[String: Any]])

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.pillars.first?.colorHex, "FED3FF")
        XCTAssertEqual(post.outputs.first?.caption, "A finished caption.")
        XCTAssertTrue(post.markdown.contains("# A clear handoff"))
        XCTAssertTrue(post.markdown.contains("private-image.jpg"))
        XCTAssertNil(data.range(of: Data([0xDE, 0xAD, 0xBE, 0xEF])))
        XCTAssertTrue(encodedPillars.first?["parentPillarId"] is NSNull)
        XCTAssertTrue(encodedOutputs.first?["account"] is NSNull)
        XCTAssertTrue(encodedOutputs.first?["targetDate"] is NSNull)
        XCTAssertTrue(encodedTasks.first?["outputId"] is NSNull)
        XCTAssertTrue(encodedTasks.first?["parentTaskId"] is NSNull)
    }

    func testMCPBridgeSnapshotPublishesPrivateNotificationCapability() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let capability = MCPBridgePushCapability(
            endpoint: try XCTUnwrap(URL(string: "https://agentcy.example/v1/bridge/notifications")),
            token: String(repeating: "a", count: 48)
        )
        MCPBridgePushPreferences.capability = capability
        defer { MCPBridgePushPreferences.capability = nil }

        let snapshot = try MCPBridgeService.makeSnapshot(context: container.mainContext)

        XCTAssertEqual(snapshot.notification, capability)
    }

    func testMCPBridgeSyncPreservesExistingNotificationCapabilityWhenCurrentClientHasNone() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-notification-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let capability = MCPBridgePushCapability(
            endpoint: try XCTUnwrap(URL(string: "https://agentcy.example/v1/bridge/notifications")),
            token: String(repeating: "b", count: 48)
        )
        MCPBridgePushPreferences.capability = capability
        let existingSnapshot = try MCPBridgeService.makeSnapshot(context: container.mainContext)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(existingSnapshot).write(to: directory.appending(path: "snapshot.json"))
        MCPBridgePushPreferences.capability = nil
        defer { MCPBridgePushPreferences.capability = nil }

        try MCPBridgeService.sync(context: container.mainContext, directory: directory)

        let data = try Data(contentsOf: directory.appending(path: "snapshot.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let refreshedSnapshot = try decoder.decode(MCPBridgeWorkspaceSnapshot.self, from: data)
        XCTAssertEqual(refreshedSnapshot.notification, capability)
    }

    func testMCPBridgeRefreshReturnsNewlyQueuedRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-refresh-\(UUID().uuidString)", directoryHint: .isDirectory)
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "id": "\(id.uuidString)",
          "createdAt": "2026-08-17T16:00:00Z",
          "source": "codex",
          "type": "createIdea",
          "payload": { "title": "A newly delivered request" }
        }
        """
        try Data(json.utf8).write(to: requests.appending(path: "\(id.uuidString).json"))

        let refreshed = try await MCPBridgeService.refreshPendingRequests(directory: directory)

        XCTAssertEqual(refreshed.map(\.id), [id])
    }

    func testMCPReviewPushMetadataRoutesToCyReviewInbox() {
        let route = AgentNotificationRouteResolver.route(from: [
            AgentNotificationMetadataKey.remoteRoute: "mcpReview",
        ])

        XCTAssertEqual(route.kind, .mcpReview)
        XCTAssertNil(route.objectID)
    }

    func testMCPReviewLayoutUsesTwoPanesOnlyAtDesktopWidth() {
        XCTAssertFalse(MCPReviewLayoutPolicy.usesSplitView(availableWidth: 760))
        XCTAssertTrue(MCPReviewLayoutPolicy.usesSplitView(availableWidth: 1_000))
    }

    func testMCPReviewRefreshContainerProvidesRefreshActionWhenInboxIsEmpty() async {
        let view = MCPReviewRefreshableScrollView(refresh: {}) {
            Color.clear.frame(height: 1)
        }
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try? await Task.sleep(for: .milliseconds(100))

        let scrollViews = host.view.agentDescendants.compactMap { $0 as? UIScrollView }
        XCTAssertTrue(scrollViews.contains { $0.refreshControl != nil })
    }

    func testMCPBridgeReadsFractionalSecondCLIRequestsFromFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-mcp-\(UUID().uuidString)", directoryHint: .isDirectory)
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        let id = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "id": "\(id.uuidString)",
          "createdAt": "2026-07-15T17:30:22.123Z",
          "source": "codex",
          "type": "createIdea",
          "payload": { "title": "A CLI idea", "notes": "Keep it concrete." }
        }
        """
        try Data(json.utf8).write(to: requests.appending(path: "\(id.uuidString).json"))

        let pending = try MCPBridgeService.pendingRequests(directory: directory)

        XCTAssertEqual(pending.map(\.id), [id])
        XCTAssertEqual(pending.first?.title, "Save an idea")
        XCTAssertEqual(pending.first?.summary, "A CLI idea")
    }

    func testMCPBridgeSkipsUnreadableRequestsOwnedByAnotherWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-mcp-\(UUID().uuidString)", directoryHint: .isDirectory)
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let currentWorkspaceID = UUID()
        let otherWorkspaceID = UUID()
        let currentRequestID = UUID()
        let otherRequestID = UUID()
        let currentJSON = """
        {
          "schemaVersion": 1,
          "id": "\(currentRequestID.uuidString)",
          "createdAt": "2026-08-17T19:00:00Z",
          "source": "codex",
          "workspaceId": "\(currentWorkspaceID.uuidString)",
          "type": "createIdea",
          "payload": { "title": "Current workspace review" }
        }
        """
        let unreadableOtherWorkspaceJSON = """
        {
          "schemaVersion": 1,
          "id": "\(otherRequestID.uuidString)",
          "createdAt": "2026-08-17T18:00:00Z",
          "source": "codex",
          "workspaceId": "\(otherWorkspaceID.uuidString)",
          "type": "createSeries",
          "payload": "temporarily unavailable"
        }
        """
        try Data(currentJSON.utf8).write(to: requests.appending(path: "current.json"))
        try Data(unreadableOtherWorkspaceJSON.utf8).write(to: requests.appending(path: "other.json"))

        let pending = try MCPBridgeService.pendingRequests(
            directory: directory,
            workspaceID: currentWorkspaceID
        )

        XCTAssertEqual(pending.map(\.id), [currentRequestID])
    }

    func testMCPBridgeQueuesReusableDemoDraftForReview() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "Lifestyle", colorHex: "FED3FF")
        context.insert(pillar)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-demo-mcp-\(UUID().uuidString)", directoryHint: .isDirectory)

        let queued = try MCPBridgeService.queueDemoDraft(context: context, directory: directory)
        let pending = try MCPBridgeService.pendingRequests(directory: directory)

        XCTAssertEqual(queued.type, "createPostDraft")
        XCTAssertEqual(pending.map(\.id), [queued.id])
        XCTAssertEqual(pending.first?.payload.pillarId, pillar.id)
        XCTAssertFalse(pending.first?.payload.caption?.isEmpty ?? true)
        XCTAssertNotEqual(pending.first?.payload.caption, pending.first?.payload.notes)
    }

    func testCyNoticedOnlyReportsUnreconciledLateWorkAndOverduePosts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lateWork = CreativeBrief(title: "Late work", status: .developing)
        lateWork.workDate = now.addingTimeInterval(-86_400)
        let lateWorkOutput = PlatformOutput(briefID: lateWork.id, status: .draft)

        let overduePost = CreativeBrief(title: "Overdue post", status: .scheduled)
        let overdueOutput = PlatformOutput(briefID: overduePost.id, status: .scheduled)
        overdueOutput.targetDate = now.addingTimeInterval(-86_400)

        let summary = CyNoticedReconciliationPolicy.summary(
            briefs: [lateWork, overduePost],
            outputs: [lateWorkOutput, overdueOutput],
            now: now
        )
        XCTAssertTrue(summary.needsAttention)
        XCTAssertEqual(summary.lateWorkCount, 1)
        XCTAssertEqual(summary.overduePostCount, 1)

        lateWork.workDate = now.addingTimeInterval(86_400)
        overdueOutput.status = .posted
        let reconciled = CyNoticedReconciliationPolicy.summary(
            briefs: [lateWork, overduePost],
            outputs: [lateWorkOutput, overdueOutput],
            now: now
        )
        XCTAssertFalse(reconciled.needsAttention)
        XCTAssertEqual(reconciled.message, "")
    }

    func testMCPBridgeCreatesSeriesEpisodeAndBrandPartnerChanges() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "Creator systems", colorHex: "A78BFA")
        let series = ContentSeries(name: "Studio notes", pillarID: pillar.id)
        context.insert(pillar)
        context.insert(series)
        let workDate = Date(timeIntervalSince1970: 1_800_100_000)
        let episodeRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "What changed in the studio",
                seriesId: series.id,
                episodeLabel: "Studio reset",
                workDate: workDate,
                includesWorkTime: false
            )
        )
        try MCPBridgeService.apply(episodeRequest, context: context)

        let episode = try XCTUnwrap(
            context.fetch(FetchDescriptor<CreativeBrief>()).first(where: { $0.seriesID == series.id })
        )
        XCTAssertEqual(episode.title, "What changed in the studio")
        XCTAssertEqual(episode.workDate, workDate)
        XCTAssertEqual(episode.episodeLabel, "Studio reset")
        XCTAssertEqual(episode.pillarID, pillar.id)

        let partnerRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createBrandPartner",
            payload: MCPBridgeRequestPayload(
                name: "Example Brand",
                brandType: BrandPartnerType.brand.rawValue,
                brandStage: BrandPartnerStage.talking.rawValue,
                socialHandle: "@example"
            )
        )
        try MCPBridgeService.apply(partnerRequest, context: context)

        let partner = try XCTUnwrap(context.fetch(FetchDescriptor<BrandPartner>()).first)
        XCTAssertEqual(partner.name, "Example Brand")
        XCTAssertEqual(partner.stage, .talking)
        XCTAssertEqual(partner.socialHandle, "@example")
    }

    func testMCPBridgeEpisodeApprovalRepairsAStaleSeriesPillarFromTheReviewedPayload() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let activePillar = Pillar(role: .anchor, name: "Creative Ambition", colorHex: "FCE6B7")
        let stalePillarID = UUID()
        let series = ContentSeries(name: "Gear for the Girlies", pillarID: stalePillarID)
        context.insert(activePillar)
        context.insert(series)
        let targetDate = Date(timeIntervalSince1970: 1_800_100_000)
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "FX3 or ZV-E1?",
                pillarId: activePillar.id,
                targetDate: targetDate,
                includesTargetTime: false,
                seriesId: series.id
            )
        )

        try MCPBridgeService.apply(request, context: context)

        let episode = try XCTUnwrap(
            context.fetch(FetchDescriptor<CreativeBrief>()).first(where: { $0.seriesID == series.id })
        )
        XCTAssertEqual(series.pillarID, activePillar.id)
        XCTAssertEqual(episode.pillarID, activePillar.id)
    }

    func testMCPBridgeDeniedSeriesEpisodeKeepsContextAndApprovedRevisionUsesTheSameSlot() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "SkipMatrix education", colorHex: "A78BFA")
        let series = ContentSeries(name: "Data Diaries", pillarID: pillar.id)
        context.insert(pillar)
        context.insert(series)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-episode-revision-\(UUID().uuidString)", directoryHint: .isDirectory)
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        let episodeReviewID = UUID()
        let proposedSlotID = UUID()
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "The premium-data break-even question",
                premise: "Show the break-even calculation.",
                seriesId: series.id,
                proposedEpisodeSlotId: proposedSlotID,
                episodeReviewId: episodeReviewID,
                revisionNumber: 1,
                episodeNumber: 2,
                workDate: Date(timeIntervalSince1970: 1_800_100_000),
                includesWorkTime: false
            )
        )
        try Data("{}".utf8).write(
            to: requests.appending(path: "\(request.id.uuidString.lowercased()).json")
        )

        try MCPBridgeService.reject(
            request,
            decisionNote: "Show every input and make the result checkable.",
            directory: directory
        )

        let denied = try XCTUnwrap(MCPBridgeService.episodeRevisions(directory: directory).first)
        XCTAssertEqual(denied.status, "needsRevision")
        XCTAssertEqual(denied.episodeReviewId, episodeReviewID)
        XCTAssertEqual(denied.episodeSlotId, proposedSlotID)
        XCTAssertEqual(denied.decisionNote, "Show every input and make the result checkable.")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: requests.appending(path: "\(request.id.uuidString.lowercased()).json").path
        ))

        var revisedPayload = denied.request.payload
        revisedPayload.premise = "Show the inputs, formula, and worked result."
        revisedPayload.revisionNumber = 2
        revisedPayload.revisionOfRequestId = request.id
        let revisedRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: revisedPayload
        )

        try MCPBridgeService.approve(revisedRequest, context: context, directory: directory)

        let slot = try XCTUnwrap(context.fetch(FetchDescriptor<SeriesEpisodeSlot>()).first)
        let episode = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        XCTAssertEqual(slot.id, proposedSlotID)
        XCTAssertEqual(slot.status, .converted)
        XCTAssertEqual(slot.convertedBriefID, episode.id)
        XCTAssertEqual(episode.premise, "Show the inputs, formula, and worked result.")
        XCTAssertEqual(episode.pillarID, pillar.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
        XCTAssertEqual(try MCPBridgeService.episodeRevisions(directory: directory).first?.status, "approved")

        let receiptData = try Data(contentsOf: directory.appending(
            path: "responses/\(revisedRequest.id.uuidString.lowercased()).json"
        ))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: receiptData) as? [String: Any])
        XCTAssertEqual(receipt["status"] as? String, "approved")
        XCTAssertEqual(receipt["episodeReviewId"] as? String, episodeReviewID.uuidString)
        XCTAssertEqual(receipt["episodeSlotId"] as? String, proposedSlotID.uuidString)
        XCTAssertEqual(receipt["resultPostId"] as? String, episode.id.uuidString)
    }

    func testMCPBridgeRejectsAnMCPSeriesWithoutAnActivePillar() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeries",
            payload: MCPBridgeRequestPayload(name: "Unfiled series", seriesId: UUID())
        )

        XCTAssertThrowsError(try MCPBridgeService.apply(request, context: context)) { error in
            guard let bridgeError = error as? MCPBridgeError else {
                return XCTFail("Expected an MCP bridge validation error.")
            }
            guard case .invalidRequest(let message) = bridgeError else {
                return XCTFail("Expected the missing pillar to invalidate the series request.")
            }
            XCTAssertTrue(message.contains("Choose a pillar"))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<ContentSeries>()).isEmpty)
    }

    func testMCPBridgeSeriesBundleApprovalRollsBackEverythingWhenOneEpisodeFails() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "SkipMatrix education", colorHex: "A78BFA")
        context.insert(pillar)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-series-bundle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let seriesID = UUID()
        let seriesRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeries",
            payload: MCPBridgeRequestPayload(pillarId: pillar.id, name: "Data Diaries", seriesId: seriesID)
        )
        let firstWorkDate = Date(timeIntervalSince1970: 1_800_100_000)
        let firstEpisode = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "The hidden bill behind cheap data",
                targetDate: firstWorkDate.addingTimeInterval(86_400),
                seriesId: seriesID,
                proposedEpisodeSlotId: UUID(),
                episodeReviewId: UUID(),
                revisionNumber: 1,
                workDate: firstWorkDate
            )
        )
        let invalidEpisode = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "The premium-data break-even question",
                targetDate: firstWorkDate.addingTimeInterval(-86_400),
                seriesId: seriesID,
                proposedEpisodeSlotId: UUID(),
                episodeReviewId: UUID(),
                revisionNumber: 1,
                workDate: firstWorkDate
            )
        )

        XCTAssertThrowsError(try MCPBridgeService.approve(
            [seriesRequest, firstEpisode, invalidEpisode],
            context: context,
            directory: directory
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<ContentSeries>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SeriesEpisodeSlot>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
    }

    func testMCPBridgePersistsEditedPendingEpisodeBeforeFinalApproval() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-edited-episode-\(UUID().uuidString)", directoryHint: .isDirectory)
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "Original title",
                seriesId: UUID(),
                proposedEpisodeSlotId: UUID(),
                episodeReviewId: UUID(),
                revisionNumber: 1,
                episodeNumber: 1,
                workDate: Date(timeIntervalSince1970: 1_800_100_000)
            )
        )
        var editedPayload = request.payload
        editedPayload.title = "Edited title"
        editedPayload.premise = "Edited premise"

        try MCPBridgeService.updatePendingRequest(
            request.replacingPayload(editedPayload),
            directory: directory
        )

        let persisted = try XCTUnwrap(MCPBridgeService.pendingRequests(directory: directory).first)
        XCTAssertEqual(persisted.id, request.id)
        XCTAssertEqual(persisted.payload.title, "Edited title")
        XCTAssertEqual(persisted.payload.premise, "Edited premise")
    }

    func testMCPBridgeSeriesBundleApprovalCreatesOneSeriesAndEveryEpisode() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "SkipMatrix education", colorHex: "A78BFA")
        context.insert(pillar)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-series-bundle-success-\(UUID().uuidString)", directoryHint: .isDirectory)
        let seriesID = UUID()
        let seriesRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeries",
            payload: MCPBridgeRequestPayload(pillarId: pillar.id, name: "Data Diaries", seriesId: seriesID)
        )
        let workDate = Date(timeIntervalSince1970: 1_800_100_000)
        let episodes = [2, 1].map { number in
            MCPBridgeChangeRequest(
                schemaVersion: 1,
                id: UUID(),
                createdAt: Date(),
                source: "codex",
                workspaceId: nil,
                type: "createSeriesEpisode",
                payload: MCPBridgeRequestPayload(
                    title: "Episode \(number)",
                    seriesId: seriesID,
                    proposedEpisodeSlotId: UUID(),
                    episodeReviewId: UUID(),
                    revisionNumber: 1,
                    episodeNumber: number,
                    workDate: workDate.addingTimeInterval(Double(number) * 86_400)
                )
            )
        }

        try MCPBridgeService.approve(
            [episodes[0], seriesRequest, episodes[1]],
            context: context,
            directory: directory
        )

        let approvedSeries = try XCTUnwrap(context.fetch(FetchDescriptor<ContentSeries>()).first)
        XCTAssertEqual(approvedSeries.id, seriesID)
        XCTAssertEqual(approvedSeries.pillarID, pillar.id)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CreativeBrief>()).compactMap(\.episodeNumber).sorted(),
            [1, 2]
        )
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<CreativeBrief>()).compactMap(\.pillarID)),
            [pillar.id]
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<SeriesEpisodeSlot>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlatformOutput>()).count, 2)
    }

    func testMCPBridgeSingleEpisodeApprovalKeepsSeriesProposalForFinalReview() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "SkipMatrix education", colorHex: "A78BFA")
        context.insert(pillar)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-single-episode-approval-\(UUID().uuidString)", directoryHint: .isDirectory)
        let seriesID = UUID()
        let seriesRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeries",
            payload: MCPBridgeRequestPayload(pillarId: pillar.id, name: "Data Diaries", seriesId: seriesID)
        )
        let episodeRequest = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "The premium-data break-even question",
                seriesId: seriesID,
                proposedEpisodeSlotId: UUID(),
                episodeReviewId: UUID(),
                revisionNumber: 1,
                episodeNumber: 2,
                workDate: Date(timeIntervalSince1970: 1_800_100_000)
            )
        )
        try MCPBridgeService.updatePendingRequest(seriesRequest, directory: directory)
        try MCPBridgeService.updatePendingRequest(episodeRequest, directory: directory)

        try MCPBridgeService.approveEpisodeInBundle(
            episodeRequest,
            seriesRequest: seriesRequest,
            context: context,
            directory: directory
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<ContentSeries>()).map(\.id), [seriesID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).first?.pillarID, pillar.id)
        XCTAssertEqual(try MCPBridgeService.pendingRequests(directory: directory).map(\.id), [seriesRequest.id])

        try MCPBridgeService.approve(
            try MCPBridgeService.pendingRequests(directory: directory),
            context: context,
            directory: directory
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<ContentSeries>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreativeBrief>()).count, 1)
    }

    func testMCPBridgeScheduledSeriesEpisodeAppearsAsAnAgendaPost() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let pillar = Pillar(role: .anchor, name: "Creator systems", colorHex: "A78BFA")
        let series = ContentSeries(name: "Studio notes", pillarID: pillar.id)
        context.insert(pillar)
        context.insert(series)
        let workDate = Date(timeIntervalSince1970: 1_800_100_000)
        let targetDate = workDate.addingTimeInterval(86_400)
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createSeriesEpisode",
            payload: MCPBridgeRequestPayload(
                title: "What changed in the studio",
                targetDate: targetDate,
                includesTargetTime: false,
                seriesId: series.id,
                episodeLabel: "Studio reset",
                workDate: workDate,
                includesWorkTime: false
            )
        )

        try MCPBridgeService.apply(request, context: context)

        let episode = try XCTUnwrap(
            context.fetch(FetchDescriptor<CreativeBrief>()).first(where: { $0.seriesID == series.id })
        )
        let output = try XCTUnwrap(
            context.fetch(FetchDescriptor<PlatformOutput>()).first(where: { $0.briefID == episode.id })
        )
        XCTAssertEqual(episode.ideaBankPlacement, .post)
        XCTAssertEqual(episode.status, .scheduled)
        XCTAssertEqual(episode.agendaDate, targetDate)
        XCTAssertEqual(episode.pillarID, pillar.id)
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertEqual(output.targetDate, targetDate)
        XCTAssertTrue(
            AgendaOpenPostPolicy.includes(
                briefStatus: episode.status,
                outputStatus: output.status,
                ideaBankPlacement: episode.ideaBankPlacement
            )
        )
    }

    func testMCPBridgeDoesNotSilentlyDropUnreadableRequestFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-mcp-\(UUID().uuidString)", directoryHint: .isDirectory)
        let requests = directory.appending(path: "requests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
        let validID = UUID()
        let validJSON = """
        {
          "schemaVersion": 1,
          "id": "\(validID.uuidString)",
          "createdAt": "2026-07-15T17:30:22.123Z",
          "source": "codex",
          "type": "createIdea",
          "payload": { "title": "A CLI idea" }
        }
        """
        try Data(validJSON.utf8).write(to: requests.appending(path: "\(validID.uuidString).json"))
        try Data("{ temporarily unavailable".utf8).write(
            to: requests.appending(path: "incomplete.json")
        )

        XCTAssertThrowsError(try MCPBridgeService.pendingRequests(directory: directory))
    }

    func testMCPBridgeRestoresPremiseAfterLegacyEditorCopiedNotesIntoIt() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(
            title: "Review-safe post",
            premise: "The original premise",
            status: .spark
        )
        brief.notes = "Detailed production notes"
        context.insert(brief)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "agentcy-mcp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try MCPBridgeService.sync(context: context, directory: directory)
        brief.premise = brief.notes

        XCTAssertTrue(
            try MCPBridgeService.restorePremiseIfNotesWereCopied(brief, directory: directory)
        )
        XCTAssertEqual(brief.premise, "The original premise")
        XCTAssertEqual(brief.notes, "Detailed production notes")
    }

    func testMCPBridgeMovesLegacyFormatAndCallToActionOutOfNotes() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let brief = CreativeBrief(title: "A slow Asheville day", status: .spark)
        brief.notes = """
        FORMAT
        Instagram Reel · 45 seconds

        STRUCTURE
        1. Open on the road.
        2. Let the day unfold.

        CALL TO ACTION
        Save this for a slower Asheville day.

        STORIES
        1. Share the arrival.
        """
        let output = PlatformOutput(
            briefID: brief.id,
            platform: .instagramReels,
            destinationID: PublishingCatalog.instagramID,
            formatID: nil,
            status: .draft
        )
        let reel = PublishingFormat(
            id: PublishingCatalog.instagramReelID,
            destinationID: PublishingCatalog.instagramID,
            name: "Reel",
            kind: .shortVideo
        )
        context.insert(brief)
        context.insert(output)
        context.insert(reel)

        XCTAssertTrue(try MCPBridgeService.migrateStructuredPostFields(context: context))
        XCTAssertEqual(brief.ctaIntent, "Save this for a slower Asheville day.")
        XCTAssertEqual(output.cta, "Save this for a slower Asheville day.")
        XCTAssertEqual(output.formatID, PublishingCatalog.instagramReelID)
        XCTAssertEqual(
            brief.notes,
            "STRUCTURE\n1. Open on the road.\n2. Let the day unfold.\n\nSTORIES\n1. Share the arrival."
        )
    }

    func testApprovedCLISchedulePromotesDraftBeforeScheduling() throws {
        let brief = CreativeBrief(title: "Reviewed draft", status: .spark)
        let output = PlatformOutput(briefID: brief.id, status: .draft)
        let date = Date(timeIntervalSince1970: 1_800_100_000)

        try MCPBridgeService.prepareForApprovedScheduling(brief)
        XCTAssertEqual(brief.status, .ready)
        XCTAssertTrue(BriefLifecycle.schedule(output, for: date, brief: brief))
        BriefLifecycle.synchronize(brief, outputs: [output])

        XCTAssertEqual(brief.status, .scheduled)
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertEqual(output.targetDate, date)
    }

    func testApprovedCLIScheduleDoesNotReviveArchivedPost() {
        let brief = CreativeBrief(title: "Archived", status: .archived)

        XCTAssertThrowsError(try MCPBridgeService.prepareForApprovedScheduling(brief))
        XCTAssertEqual(brief.status, .archived)
    }

    func testMCPBridgeCreatesAndSchedulesNewPostInOneApproval() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(PublishingFormat(
            id: PublishingCatalog.instagramReelID,
            destinationID: PublishingCatalog.instagramID,
            name: "Reel",
            kind: .shortVideo
        ))
        try context.save()
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createPostDraft",
            payload: MCPBridgeRequestPayload(
                title: "A soft weekend in Charlotte",
                premise: "Let a slow day unfold.",
                notes: "Use the arrival footage first.",
                pillarId: nil,
                platform: CreatorPlatform.instagramReels.rawValue,
                format: "Reel",
                postId: nil,
                outputId: nil,
                hook: "Come spend a slow day in Charlotte with me.",
                caption: "Charlotte, slowly.",
                callToAction: "Save this for a slower weekend.",
                targetDate: date,
                includesTargetTime: false,
                kind: nil,
                lane: nil,
                priority: nil,
                taskId: nil
            )
        )

        try MCPBridgeService.apply(request, context: context)

        let brief = try XCTUnwrap(context.fetch(FetchDescriptor<CreativeBrief>()).first)
        let output = try XCTUnwrap(context.fetch(FetchDescriptor<PlatformOutput>()).first)
        XCTAssertEqual(brief.status, .scheduled)
        XCTAssertEqual(brief.agendaDate, date)
        XCTAssertEqual(output.status, .scheduled)
        XCTAssertEqual(output.targetDate, date)
        XCTAssertFalse(output.includesTargetTime)
        XCTAssertEqual(output.formatID, PublishingCatalog.instagramReelID)
    }

    func testMCPBridgeRequiresExplicitAccountWhenAPlatformHasMultipleAccounts() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let first = CreatorSocialAccount(
            profileID: UUID(),
            destinationID: PublishingCatalog.instagramID,
            label: "@main",
            profileURLString: "",
            isPrimary: true
        )
        let second = CreatorSocialAccount(
            profileID: UUID(),
            destinationID: PublishingCatalog.instagramID,
            label: "@studio",
            profileURLString: ""
        )
        context.insert(first)
        context.insert(second)

        let ambiguous = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createPostDraft",
            payload: MCPBridgeRequestPayload(
                title: "Choose the right account",
                platform: CreatorPlatform.instagramReels.rawValue
            )
        )

        XCTAssertThrowsError(try MCPBridgeService.apply(ambiguous, context: context)) { error in
            XCTAssertTrue(error.localizedDescription.contains("multiple social accounts"))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)

        let explicit = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createPostDraft",
            payload: MCPBridgeRequestPayload(
                title: "Choose the right account",
                platform: CreatorPlatform.instagramReels.rawValue,
                socialAccountId: second.id
            )
        )
        try MCPBridgeService.apply(explicit, context: context)

        let output = try XCTUnwrap(context.fetch(FetchDescriptor<PlatformOutput>()).first)
        XCTAssertEqual(output.socialAccountID, second.id)
        let snapshot = try MCPBridgeService.makeSnapshot(context: context)
        XCTAssertEqual(Set(snapshot.socialAccounts.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(snapshot.posts.first?.outputs.first?.socialAccountId, second.id)
    }

    func testMCPBridgeRejectsAProposalForADifferentCreatorWorkspace() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let profileID = UUID()
        let active = CreatorWorkspace(profileID: profileID, name: "Main")
        let other = CreatorWorkspace(profileID: profileID, name: "Second")
        context.insert(active)
        context.insert(other)
        let priorWorkspaceID = CreatorWorkspacePreferences.activeWorkspaceID
        CreatorWorkspacePreferences.activeWorkspaceID = active.id
        defer { CreatorWorkspacePreferences.activeWorkspaceID = priorWorkspaceID }

        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: other.id,
            type: "createIdea",
            payload: MCPBridgeRequestPayload(title: "Wrong workspace")
        )

        XCTAssertThrowsError(try MCPBridgeService.apply(request, context: context)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Switch to the account"))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
    }

    func testMCPBridgeInvalidFormatLeavesNoPartialPost() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(PublishingFormat(
            id: PublishingCatalog.instagramReelID,
            destinationID: PublishingCatalog.instagramID,
            name: "Reel",
            kind: .shortVideo
        ))
        try context.save()
        let request = MCPBridgeChangeRequest(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            source: "codex",
            workspaceId: nil,
            type: "createPostDraft",
            payload: MCPBridgeRequestPayload(
                title: "A soft weekend in Charlotte",
                premise: nil,
                notes: nil,
                pillarId: nil,
                platform: CreatorPlatform.instagramReels.rawValue,
                format: "Instagram Reel with a quiet opening",
                postId: nil,
                outputId: nil,
                hook: nil,
                caption: nil,
                callToAction: nil,
                targetDate: Date(),
                includesTargetTime: false,
                kind: nil,
                lane: nil,
                priority: nil,
                taskId: nil
            )
        )

        XCTAssertThrowsError(try MCPBridgeService.apply(request, context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
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
            librarySummaries: [],
            taskSummaries: []
        )
    }
}

private extension UIView {
    var agentDescendants: [UIView] {
        subviews + subviews.flatMap(\.agentDescendants)
    }
}

@MainActor
private struct SlowDialogueCreativeService: CreativeServicing {
    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction {
        throw CancellationError()
    }

    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] {
        throw CancellationError()
    }

    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String {
        try await Task.sleep(for: .milliseconds(100))
        return "A focused response for \(answer)."
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
            quotaScope: .providerCredits,
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

@MainActor
private struct ProviderIdeasCreativeService: CreativeServicing {
    let provider: CyExecutionProvider

    private var ideas: [IdeaDirection] {
        [
            IdeaDirection(
                title: "Start with the smallest version",
                premise: "Show the simplest useful way to begin.",
                opening: "You do not need the full version yet.",
                assumption: "The creator wants a practical first step."
            ),
            IdeaDirection(
                title: "Behind the decision",
                premise: "Explain one honest creative tradeoff.",
                opening: "I almost chose the obvious option.",
                assumption: "The audience learns from the creator's judgment."
            ),
            IdeaDirection(
                title: "What I would do first",
                premise: "Give a grounded starting point.",
                opening: "If I had to start again, I would begin here.",
                assumption: "The audience needs a useful first move."
            )
        ]
    }

    func findIdeasExecution(
        context: CreatorContextWire,
        mode: AssistanceMode
    ) async throws -> CyExecution<[IdeaDirection]> {
        CyExecution(value: ideas, provider: provider)
    }

    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] {
        ideas
    }

    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction { throw TestError.unused }
    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String { throw TestError.unused }
    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal { throw TestError.unused }
    func proposeRevision(of brief: ReadyBriefWire, localBriefID: UUID, revisionNumber: Int, scope: BriefRevisionFieldWire, instruction: String, mode: AssistanceMode, context: CreatorContextWire, baseline: BriefProposal, sourceUpdatedAt: Date, sourceTaskIDs: [UUID]) async throws -> BriefRevisionProposal { throw TestError.unused }
    func proposeVoiceProfileChange(profileID: UUID, sourceVersion: Int, sourceUpdatedAt: Date, current: VoiceProfileDraft, instruction: String, mode: AssistanceMode, context: CreatorContextWire) async throws -> VoiceProfileChangeProposal { throw TestError.unused }
    func reply(to message: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], relevantBriefIDs: [UUID]) async throws -> String { throw TestError.unused }

    private enum TestError: Error { case unused }
}

@MainActor
private final class CapturingChatCreativeService: CreativeServicing {
    var capturedContext: CreatorContextWire?

    func reply(
        to message: String,
        mode: AssistanceMode,
        context: CreatorContextWire,
        conversation: [ConversationMessageWire],
        relevantBriefIDs: [UUID]
    ) async throws -> String {
        capturedContext = context
        return "I found your current posts and tasks."
    }

    func extractVoiceProfile(context: CreatorContextWire, mode: AssistanceMode) async throws -> VoiceProfileExtraction { throw TestError.unused }
    func findIdeas(context: CreatorContextWire, mode: AssistanceMode) async throws -> [IdeaDirection] { throw TestError.unused }
    func nextQuestion(for brief: CreativeBrief, turn: Int, answer: String, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire], postContext: String?) async throws -> String { throw TestError.unused }
    func composeProposal(from brief: CreativeBrief, mode: AssistanceMode, context: CreatorContextWire, conversation: [ConversationMessageWire]) async throws -> BriefProposal { throw TestError.unused }
    func proposeRevision(of brief: ReadyBriefWire, localBriefID: UUID, revisionNumber: Int, scope: BriefRevisionFieldWire, instruction: String, mode: AssistanceMode, context: CreatorContextWire, baseline: BriefProposal, sourceUpdatedAt: Date, sourceTaskIDs: [UUID]) async throws -> BriefRevisionProposal { throw TestError.unused }
    func proposeVoiceProfileChange(profileID: UUID, sourceVersion: Int, sourceUpdatedAt: Date, current: VoiceProfileDraft, instruction: String, mode: AssistanceMode, context: CreatorContextWire) async throws -> VoiceProfileChangeProposal { throw TestError.unused }

    private enum TestError: Error { case unused }
}
