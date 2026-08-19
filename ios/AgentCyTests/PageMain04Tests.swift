import XCTest
@testable import AgentCy

@MainActor
final class PageMain04Tests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    func testHierarchyIsDuplicateSafeAndKeepsEveryActivePillarReachable() throws {
        let early = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2)))
        let latest = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3)))
        let anchorID = UUID()
        let anchor = Pillar(id: anchorID, role: .anchor, name: "Anchor", createdAt: early)
        let duplicateAnchor = Pillar(id: anchorID, role: .anchor, name: "Duplicate", createdAt: later)
        let orphan = Pillar(parentPillarID: UUID(), role: .supporting, name: "Orphan", createdAt: later)
        let extraRoot = Pillar(role: .supporting, name: "Extra root", createdAt: latest)
        let archived = Pillar(parentPillarID: anchorID, role: .supporting, name: "Archived", createdAt: later)
        archived.isArchived = true

        let active = PillarRootHierarchyPolicy.activePillars(
            from: [duplicateAnchor, archived, orphan, extraRoot, anchor]
        )
        let resolvedAnchor = try XCTUnwrap(PillarRootHierarchyPolicy.anchor(in: active))
        let branches = PillarRootHierarchyPolicy.branches(anchor: resolvedAnchor, activePillars: active)

        XCTAssertEqual(active.map(\.id), [anchorID, orphan.id, extraRoot.id])
        XCTAssertEqual(resolvedAnchor.id, anchorID)
        XCTAssertEqual(Set(branches.map(\.id)), [orphan.id, extraRoot.id])
    }

    func testHierarchyFallsBackToAnOrphanInsteadOfInventingAnEmptyState() throws {
        let first = Pillar(parentPillarID: UUID(), role: .supporting, name: "First active")
        let second = Pillar(parentPillarID: UUID(), role: .supporting, name: "Second active")
        let active = PillarRootHierarchyPolicy.activePillars(from: [first, second])

        let anchor = try XCTUnwrap(PillarRootHierarchyPolicy.anchor(in: active))

        XCTAssertEqual(anchor.id, first.id)
        XCTAssertEqual(PillarRootHierarchyPolicy.branches(anchor: anchor, activePillars: active).map(\.id), [second.id])
    }

    func testProjectionCountsEachPlannedBriefOnceAndBuildsMetricsInOnePass() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 12
        )))
        let anchor = Pillar(role: .anchor, name: "Anchor")
        let branch = Pillar(parentPillarID: anchor.id, role: .supporting, name: "Branch")
        let anchorIdea = CreativeBrief(title: "Idea", status: .developing)
        anchorIdea.pillarID = anchor.id
        let anchorScheduled = CreativeBrief(title: "Scheduled", status: .scheduled)
        anchorScheduled.pillarID = anchor.id
        let branchPosted = CreativeBrief(title: "Posted", status: .posted)
        branchPosted.pillarID = branch.id
        let archived = CreativeBrief(title: "Archived", status: .archived)
        archived.pillarID = anchor.id

        func output(
            for brief: CreativeBrief,
            status: PlatformOutputStatus,
            day: Int,
            hour: Int = 9
        ) -> PlatformOutput {
            let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: status)
            output.targetDate = calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour
            ))
            return output
        }

        let projection = PillarRootProjectionPolicy.make(
            activePillars: [anchor, branch],
            briefs: [anchorIdea, anchorScheduled, branchPosted, archived],
            outputs: [
                output(for: anchorScheduled, status: .scheduled, day: 18),
                output(for: anchorScheduled, status: .scheduled, day: 19),
                output(for: branchPosted, status: .posted, day: 20),
                output(for: archived, status: .scheduled, day: 21),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(projection.orderedPillarIDs, [anchor.id, branch.id])
        XCTAssertEqual(projection.metricsByPillarID[anchor.id], PillarRootMetric(
            ideaCount: 1,
            thisWeekCount: 1,
            usagePercentage: 50
        ))
        XCTAssertEqual(projection.metricsByPillarID[branch.id], PillarRootMetric(
            ideaCount: 0,
            thisWeekCount: 1,
            usagePercentage: 50
        ))
    }

    func testUsageWeekExcludesTheExactNextMondayBoundary() throws {
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 17
        )))
        let nextMonday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: monday))
        let pillar = Pillar(role: .anchor, name: "Anchor")
        let brief = CreativeBrief(title: "Next week", status: .scheduled)
        brief.pillarID = pillar.id
        let output = PlatformOutput(briefID: brief.id, platform: .instagramReels, status: .scheduled)
        output.targetDate = nextMonday

        XCTAssertEqual(
            PillarUsageSchedulePolicy.scheduledBriefCountsByPillar(
                briefs: [brief],
                outputs: [output],
                interval: PillarUsageSchedulePolicy.weekInterval(containing: monday, calendar: calendar)
            ),
            [:]
        )
    }

    func testFirstCreatedPillarUsesTheWorkspacePaletteFirstColor() {
        XCTAssertEqual(
            PillarCreationPalettePolicy.defaultColor(palette: .tooCool, activeCount: 0),
            CreatorVibePalette.tooCool.pillarColorHexes[0]
        )
        XCTAssertEqual(
            PillarCreationPalettePolicy.defaultColor(palette: .tooCool, activeCount: 1),
            CreatorVibePalette.tooCool.pillarColorHexes[1]
        )
    }

    func testAccessibilityPresentationStacksStatsAndBuildsOneCompleteBranchLabel() {
        XCTAssertTrue(PillarRootAccessibilityPolicy.usesStackedStats(dynamicTypeSize: .accessibility1))
        XCTAssertTrue(PillarRootAccessibilityPolicy.usesStackedBranchLayout(dynamicTypeSize: .accessibility1))
        XCTAssertTrue(PillarRootAccessibilityPolicy.usesScrollableInfoPopover(dynamicTypeSize: .accessibility1))
        XCTAssertTrue(PillarRootAccessibilityPolicy.usesStackedAnchorMetadata(dynamicTypeSize: .accessibility1))
        XCTAssertTrue(PillarRootAccessibilityPolicy.usesExpandedWeekdayRows(dynamicTypeSize: .accessibility1))
        XCTAssertFalse(PillarRootAccessibilityPolicy.usesStackedStats(dynamicTypeSize: .large))
        XCTAssertFalse(PillarRootAccessibilityPolicy.usesStackedAnchorMetadata(dynamicTypeSize: .large))
        XCTAssertFalse(PillarRootAccessibilityPolicy.usesExpandedWeekdayRows(dynamicTypeSize: .large))
        XCTAssertEqual(
            PillarRootAccessibilityPolicy.branchLabel(
                name: "Practical tutorials",
                ideaCount: 4,
                thisWeekCount: 2,
                usagePercentage: 40,
                daySummary: "Monday · Wednesday"
            ),
            "Practical tutorials, 4 ideas, 2 this week, 40 percent usage, Monday and Wednesday"
        )
    }

    func testBranchCapacityCopyMatchesTheSixPillarLimit() {
        XCTAssertEqual(PillarRootHierarchyPolicy.maximumBranchCount, 5)
        XCTAssertEqual(
            PillarRootAccessibilityPolicy.branchCapacityLabel(branchCount: 5),
            "5 of 5 secondary pillars"
        )
    }
}
