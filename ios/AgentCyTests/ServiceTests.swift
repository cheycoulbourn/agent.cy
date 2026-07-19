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
