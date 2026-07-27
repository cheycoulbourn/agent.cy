import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class BrandPartnershipTests: XCTestCase {
    func testBrandActivityUsesPresetOrCustomTitle() {
        let partnerID = UUID()
        let preset = BrandActivity(brandPartnerID: partnerID, kind: .followedUp)
        let custom = BrandActivity(
            brandPartnerID: partnerID,
            kind: .custom,
            customTitle: "  Sent the revised rate card  "
        )

        XCTAssertEqual(preset.title, "Sent a follow-up")
        XCTAssertEqual(custom.title, "Sent the revised rate card")
    }

    func testImportSuggestionsDeduplicateNamesAndInferRelationshipStage() {
        let workspaceID = UUID()
        let active = CreativeBrief(
            title: "Summer launch",
            premise: "",
            status: .scheduled
        )
        active.workspaceID = workspaceID
        active.isBrandCollaboration = true
        active.brandName = " Studio North "

        let duplicate = CreativeBrief(
            title: "Second deliverable",
            premise: "",
            status: .ready
        )
        duplicate.workspaceID = workspaceID
        duplicate.isBrandCollaboration = true
        duplicate.brandName = "studio  north"

        let previous = CreativeBrief(
            title: "Past campaign",
            premise: "",
            status: .posted
        )
        previous.workspaceID = workspaceID
        previous.isBrandCollaboration = true
        previous.brandName = "Old Friend"

        let existing = BrandPartner(workspaceID: workspaceID, name: "STUDIO NORTH")
        let suggestions = BrandPartnershipService.importSuggestions(
            briefs: [active, duplicate, previous],
            outputs: [],
            existingPartners: [existing],
            workspaceID: workspaceID
        )

        XCTAssertEqual(suggestions.map(\.name), ["Old Friend"])
        XCTAssertEqual(suggestions.first?.stage, .pastPartner)
        XCTAssertEqual(suggestions.first?.briefIDs, [previous.id])
    }

    func testImportSuggestionLinksEveryMatchingPostWithoutChangingSnapshotMeaning() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let first = CreativeBrief(title: "First", premise: "")
        let second = CreativeBrief(title: "Second", premise: "")
        [first, second].forEach {
            $0.workspaceID = workspaceID
            $0.isBrandCollaboration = true
            $0.brandName = "Northstar"
            context.insert($0)
        }

        let suggestion = BrandImportSuggestion(
            id: "northstar",
            name: "Northstar",
            stage: .workingTogether,
            briefIDs: [first.id, second.id]
        )
        let partner = BrandPartnershipService.importSuggestion(
            suggestion,
            workspaceID: workspaceID,
            briefs: [first, second],
            context: context
        )
        try context.save()

        XCTAssertEqual(first.brandPartnerID, partner.id)
        XCTAssertEqual(second.brandPartnerID, partner.id)
        XCTAssertEqual(first.brandName, "Northstar")
        XCTAssertEqual(second.brandName, "Northstar")
    }

    func testFollowUpReconciliationMaintainsOneOpenFocusTaskAndPreservesCompletedWork() throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let workspaceID = UUID()
        let followUpDate = Date(timeIntervalSince1970: 1_800_000_000)
        let partner = BrandPartner(
            workspaceID: workspaceID,
            name: "Northstar",
            stage: .talking
        )
        partner.nextFollowUpAt = followUpDate
        let completed = CreatorTask(title: "Previous follow up")
        completed.workspaceID = workspaceID
        completed.brandPartnerID = partner.id
        completed.isCompleted = true
        completed.completedAt = Date()
        context.insert(partner)
        context.insert(completed)

        BrandPartnershipService.reconcileFollowUpTask(
            for: partner,
            tasks: [completed],
            context: context
        )
        try context.save()

        var tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let open = tasks.filter { !$0.isCompleted }
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.title, "Follow up with Northstar")
        XCTAssertEqual(open.first?.targetDate, followUpDate)
        XCTAssertEqual(open.first?.brandPartnerID, partner.id)
        XCTAssertNil(open.first?.briefID)

        partner.nextFollowUpAt = nil
        BrandPartnershipService.reconcileFollowUpTask(
            for: partner,
            tasks: tasks,
            context: context
        )
        try context.save()

        tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        XCTAssertEqual(tasks.map(\.id), [completed.id])
        XCTAssertTrue(tasks[0].isCompleted)
    }
}
