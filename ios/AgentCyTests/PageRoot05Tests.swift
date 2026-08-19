import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageRoot05Tests: XCTestCase {
    func testCompletionFailureKeepsTheDraftRecoverableOnTheResponsibleStep() {
        let invalidHandle = OnboardingCompletionAlert.resolve(
            notice: .info("Check the Instagram handle. Use only the account name, with or without @.")
        )
        let storageFailure = OnboardingCompletionAlert.resolve(
            notice: .error("Setup couldn’t save your changes. Try again.")
        )

        XCTAssertEqual(invalidHandle.message, "Check the Instagram handle. Use only the account name, with or without @.")
        XCTAssertEqual(invalidHandle.recovery, .platforms)
        XCTAssertEqual(storageFailure.message, "Setup couldn’t save your changes. Try again.")
        XCTAssertEqual(storageFailure.recovery, .ready)
    }

    func testNotificationPermissionIsRequestedOnlyForAnEnabledReminderThatNeedsAuthorization() {
        XCTAssertFalse(OnboardingNotificationPermissionPolicy.shouldRequestAuthorization(
            dailyEnabled: false,
            weeklyEnabled: false,
            canSchedule: false,
            previewOnly: false
        ))
        XCTAssertFalse(OnboardingNotificationPermissionPolicy.shouldRequestAuthorization(
            dailyEnabled: true,
            weeklyEnabled: false,
            canSchedule: true,
            previewOnly: false
        ))
        XCTAssertFalse(OnboardingNotificationPermissionPolicy.shouldRequestAuthorization(
            dailyEnabled: true,
            weeklyEnabled: false,
            canSchedule: false,
            previewOnly: true
        ))
        XCTAssertTrue(OnboardingNotificationPermissionPolicy.shouldRequestAuthorization(
            dailyEnabled: false,
            weeklyEnabled: true,
            canSchedule: false,
            previewOnly: false
        ))
    }

    func testOnboardingAccessibilityNamesFieldsAndDistinguishesSelectionControls() {
        XCTAssertEqual(OnboardingAccessibility.goalFieldLabel, "What are you working toward?")
        XCTAssertEqual(OnboardingAccessibility.selectionValue(isSelected: true), "Selected")
        XCTAssertEqual(OnboardingAccessibility.selectionValue(isSelected: false), "Not selected")
        XCTAssertEqual(OnboardingAccessibility.pillarColorLabel(index: 0, count: 4), "Pillar color 1 of 4")
        XCTAssertEqual(OnboardingAccessibility.pillarColorLabel(index: 1, count: 4), "Pillar color 2 of 4")
    }

    func testVibePalettesCollapseToOneColumnAtAccessibilityTextSizes() {
        XCTAssertEqual(OnboardingVibeLayout.columnCount(isAccessibilitySize: false), 2)
        XCTAssertEqual(OnboardingVibeLayout.columnCount(isAccessibilitySize: true), 1)
    }

    func testChosenVibeColorsFeedTheFirstPillarEditor() {
        XCTAssertEqual(
            OnboardingPillarColorPolicy.choices(for: .pastel),
            CreatorVibePalette.pastel.pillarColorHexes
        )
        XCTAssertEqual(
            OnboardingPillarColorPolicy.initialColor(for: .pastel, existingPillarCount: 0),
            CreatorVibePalette.pastel.pillarColorHexes[0]
        )
        XCTAssertEqual(
            OnboardingPillarColorPolicy.choices(for: nil),
            CreatorVibePalette.fallbackPillarColorHexes
        )
        XCTAssertEqual(
            OnboardingPillarColorPolicy.initialColor(for: nil, existingPillarCount: 0),
            CreatorVibePalette.fallbackPillarColorHexes[0]
        )
        XCTAssertFalse(OnboardingPillarColorPolicy.shouldRetheme(
            from: .pastel,
            to: .pastel
        ))
        XCTAssertTrue(OnboardingPillarColorPolicy.shouldRetheme(
            from: .pastel,
            to: .neutral
        ))
    }

    func testInvalidHandleCompletionReplacesAStaleNoticeAndRoutesBackToPlatforms() async throws {
        let container = ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let model = AppModel(reminderService: PreviewReminderService())
        model.notice = .error("An older unrelated error")
        var draft = OnboardingDraft()
        draft.adultConfirmed = true
        draft.name = "Ari"
        draft.goal = "Create consistently"
        draft.platforms = [.instagramReels]
        draft.accountHandles[.instagram] = "@bad handle"

        OnboardingCompletionAttempt.prepare(model)
        let completed = await model.completeOnboarding(draft, context: context)
        let alert = OnboardingCompletionAlert.resolve(notice: model.notice)

        XCTAssertFalse(completed)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CreatorProfile>()).isEmpty)
        XCTAssertEqual(alert.recovery, .platforms)
        XCTAssertEqual(
            alert.message,
            "Check the Instagram handle. Use only the account name, with or without @."
        )
    }

    func testBridgeStatusReaderCanRunOutsideTheMainActor() async {
        let completed = await Task.detached {
            _ = try? MCPBridgeService.connectionStatus()
            return true
        }.value

        XCTAssertTrue(completed)
    }

    // The posting-goal step joined the flow 2026-08-19 per creator request:
    // the weekly goal is set during onboarding and skippable.
    func testNineStepFlowCanReturnFromReadyAndResetsScrollIdentity() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.welcome, .name, .vibe, .pillars, .platforms, .postingGoal, .ai, .notifications, .ready]
        )
        XCTAssertEqual(OnboardingStep.ready.previous, .notifications)
        XCTAssertEqual(OnboardingStep.postingGoal.next, .ai)
        XCTAssertEqual(OnboardingStep.ai.previous, .postingGoal)
        XCTAssertNotEqual(OnboardingStep.notifications.scrollResetID, OnboardingStep.ready.scrollResetID)
    }

    func testPreviewCompletionNeverPersistsOnboardingData() {
        XCTAssertFalse(OnboardingPersistencePolicy.shouldPersist(previewOnly: true))
        XCTAssertTrue(OnboardingPersistencePolicy.shouldPersist(previewOnly: false))
    }
}
