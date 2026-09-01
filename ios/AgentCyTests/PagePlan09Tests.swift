import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PagePlan09Tests: XCTestCase {
    func testEpisodeSlotPreviewRequiresExplicitLaunchArgument() {
        XCTAssertTrue(PlanRuntimeFixture.requestsEpisodeSlotActions(
            arguments: ["agent.cy", "-agentCyPreviewEpisodeSlotActions"]
        ))
        XCTAssertFalse(PlanRuntimeFixture.requestsEpisodeSlotActions(
            arguments: ["agent.cy", "-agentCyPreviewData"]
        ))
    }

    func testIdeaConversionClearsRecurrenceFromReusedOutput() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let series = ContentSeries(workspaceID: workspaceID, name: "Creator systems")
        let slot = SeriesEpisodeSlot(
            workspaceID: workspaceID,
            seriesID: series.id,
            plannedDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let idea = CreativeBrief(title: "A reusable idea", status: .spark)
        idea.workspaceID = workspaceID
        idea.ideaBankPlacement = .idea
        let output = PlatformOutput(briefID: idea.id, platform: .instagramReels)
        output.workspaceID = workspaceID
        output.recurrence = .weekly
        output.seriesRootOutputID = UUID()
        output.targetDate = slot.plannedDate
        context.insert(series)
        context.insert(slot)
        context.insert(idea)
        context.insert(output)
        try context.save()

        let result = try SeriesEpisodePlanner.convert(
            slot: slot,
            series: series,
            using: idea,
            output: output,
            context: context
        )

        XCTAssertEqual(result.output.recurrence, .none)
        XCTAssertNil(result.output.seriesRootOutputID)
        XCTAssertNil(result.output.targetDate)
        XCTAssertEqual(result.output.status, .draft)
    }

    func testStaleConversionLinkDoesNotCreateASecondEpisode() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let missingBriefID = UUID()
        let series = ContentSeries(workspaceID: workspaceID, name: "Creator systems")
        let slot = SeriesEpisodeSlot(
            workspaceID: workspaceID,
            seriesID: series.id,
            plannedDate: Date(timeIntervalSince1970: 1_800_000_000),
            convertedBriefID: missingBriefID
        )
        context.insert(series)
        context.insert(slot)
        try context.save()

        XCTAssertThrowsError(try SeriesEpisodePlanner.convert(
            slot: slot,
            series: series,
            context: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
        XCTAssertEqual(slot.status, .open)
        XCTAssertEqual(slot.convertedBriefID, missingBriefID)
    }

    func testConvertedSlotCannotBeSkippedAndLoseItsEpisodeLink() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let briefID = UUID()
        let slot = SeriesEpisodeSlot(
            workspaceID: workspaceID,
            seriesID: UUID(),
            plannedDate: Date(timeIntervalSince1970: 1_800_000_000),
            status: .converted,
            convertedBriefID: briefID
        )
        context.insert(slot)
        try context.save()

        XCTAssertThrowsError(try SeriesEpisodePlanner.skip(slot, context: context))
        XCTAssertEqual(slot.status, .converted)
        XCTAssertEqual(slot.convertedBriefID, briefID)
    }

    func testSkippedSlotCannotBeConvertedIntoAHiddenEpisode() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let series = ContentSeries(workspaceID: workspaceID, name: "Creator systems")
        let slot = SeriesEpisodeSlot(
            workspaceID: workspaceID,
            seriesID: series.id,
            plannedDate: Date(timeIntervalSince1970: 1_800_000_000),
            status: .skipped
        )
        context.insert(series)
        context.insert(slot)
        try context.save()

        XCTAssertThrowsError(try SeriesEpisodePlanner.convert(
            slot: slot,
            series: series,
            context: context
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreativeBrief>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlatformOutput>()).isEmpty)
        XCTAssertEqual(slot.status, .skipped)
    }

    func testIdeaWithAmbiguousOutputsDoesNotChooseOneArbitrarily() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let series = ContentSeries(workspaceID: workspaceID, name: "Creator systems")
        let slot = SeriesEpisodeSlot(
            workspaceID: workspaceID,
            seriesID: series.id,
            plannedDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let idea = CreativeBrief(title: "Ambiguous idea", status: .spark)
        idea.workspaceID = workspaceID
        idea.ideaBankPlacement = .idea
        let firstOutput = PlatformOutput(briefID: idea.id, platform: .instagramReels)
        firstOutput.workspaceID = workspaceID
        let secondOutput = PlatformOutput(briefID: idea.id, platform: .tiktok)
        secondOutput.workspaceID = workspaceID
        context.insert(series)
        context.insert(slot)
        context.insert(idea)
        context.insert(firstOutput)
        context.insert(secondOutput)
        try context.save()

        XCTAssertThrowsError(try SeriesEpisodePlanner.convert(
            slot: slot,
            series: series,
            using: idea,
            context: context
        )) { error in
            guard case SeriesEpisodePlannerError.ambiguousIdeaOutputs = error else {
                return XCTFail("Expected ambiguous output error, received \(error)")
            }
        }
        XCTAssertEqual(slot.status, .open)
        XCTAssertNil(slot.convertedBriefID)
        XCTAssertEqual(idea.ideaBankPlacement, .idea)
        XCTAssertNil(idea.seriesID)
    }
}
