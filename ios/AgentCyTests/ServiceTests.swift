import Foundation
import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class ServiceTests: XCTestCase {
    func testPreviewCreativeServiceProducesExactlyThreeDirections() async throws {
        let service = PreviewCreativeService()
        let ideas = try await service.findIdeas(context: creatorContext(), mode: .collaborate)
        XCTAssertEqual(ideas.count, 3)
        XCTAssertEqual(Set(ideas.map(\.title)).count, 3)
        XCTAssertTrue(ideas.allSatisfy { !$0.assumption.isEmpty })
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
        context.insert(PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .ready))
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
