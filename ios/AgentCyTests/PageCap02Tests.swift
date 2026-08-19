import SwiftData
import XCTest
@testable import AgentCy

@MainActor
final class PageCap02Tests: XCTestCase {

    // Creator feature 2026-08-19: the idea quick action offers an optional
    // Platform, and once a platform is chosen, the formats under it. Both
    // stay optional; a format never outlives its platform.
    func testFormatsAreScopedToTheChosenPlatform() {
        let instagram = PublishingDestination(name: "Instagram", sortOrder: 0)
        let tiktok = PublishingDestination(name: "TikTok", sortOrder: 1)

        let reel = PublishingFormat(destinationID: instagram.id, name: "Reel", kind: .shortVideo, sortOrder: 0)
        let story = PublishingFormat(destinationID: instagram.id, name: "Story", kind: .nonVideo, sortOrder: 1)
        let archived = PublishingFormat(destinationID: instagram.id, name: "Old", kind: .shortVideo, sortOrder: 2)
        archived.isArchived = true
        let tiktokVideo = PublishingFormat(destinationID: tiktok.id, name: "Video", kind: .shortVideo, sortOrder: 0)
        let formats = [tiktokVideo, story, archived, reel]

        let scoped = IdeaPlatformChoicePolicy.availableFormats(
            destinationID: instagram.id,
            formats: formats
        )
        XCTAssertEqual(scoped.map(\.name), ["Reel", "Story"], "Sorted, unarchived, platform-scoped")
        XCTAssertTrue(IdeaPlatformChoicePolicy.availableFormats(destinationID: nil, formats: formats).isEmpty)
    }

    func testSelectionNormalizationDropsOrphanedFormat() {
        let instagram = PublishingDestination(name: "Instagram", sortOrder: 0)
        let tiktok = PublishingDestination(name: "TikTok", sortOrder: 1)
        let reel = PublishingFormat(destinationID: instagram.id, name: "Reel", kind: .shortVideo, sortOrder: 0)
        let destinations = [instagram, tiktok]
        let formats = [reel]

        // Format follows its platform.
        var selection = IdeaPlatformChoicePolicy.normalizedSelection(
            destinationID: instagram.id, formatID: reel.id,
            destinations: destinations, formats: formats
        )
        XCTAssertEqual(selection.destinationID, instagram.id)
        XCTAssertEqual(selection.formatID, reel.id)

        // Switching platforms drops a format that belongs elsewhere.
        selection = IdeaPlatformChoicePolicy.normalizedSelection(
            destinationID: tiktok.id, formatID: reel.id,
            destinations: destinations, formats: formats
        )
        XCTAssertEqual(selection.destinationID, tiktok.id)
        XCTAssertNil(selection.formatID)

        // No platform means no format.
        selection = IdeaPlatformChoicePolicy.normalizedSelection(
            destinationID: nil, formatID: reel.id,
            destinations: destinations, formats: formats
        )
        XCTAssertNil(selection.destinationID)
        XCTAssertNil(selection.formatID)
    }

    func testCreateSparkStoresPreferredPlatformAndFormat() throws {
        let container = try ModelContainer(
            for: CreativeBrief.self, CreatorWorkspace.self, CreatorProfile.self, SubscriptionState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(SubscriptionState(access: .comped))
        let appModel = AppModel(creativeService: PreviewCreativeService())

        let destinationID = UUID()
        let formatID = UUID()
        let brief = appModel.createSpark(
            text: "Platform-tagged idea",
            source: .text,
            title: "Platform-tagged idea",
            preferredDestinationID: destinationID,
            preferredFormatID: formatID,
            context: context
        )
        XCTAssertEqual(brief?.preferredDestinationID, destinationID)
        XCTAssertEqual(brief?.preferredFormatID, formatID)
    }

    // The tag has to carry forward: developing a platform-tagged idea must
    // start the post draft on that platform and format, not the profile default.
    func testDevelopedIdeaStartsOnItsPreferredPlatform() throws {
        let container = try ModelContainer(
            for: CreativeBrief.self, PlatformOutput.self, CreatorProfile.self,
            CreatorWorkspace.self, PublishingDestination.self, PublishingFormat.self,
            CreatorSocialAccount.self, SubscriptionState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(SubscriptionState(access: .comped))
        for seed in PublishingCatalog.destinationSeeds {
            context.insert(PublishingDestination(id: seed.0, name: seed.1, builtInKind: seed.2, sortOrder: seed.3))
        }
        for seed in PublishingCatalog.formatSeeds {
            context.insert(PublishingFormat(id: seed.0, destinationID: seed.1, name: seed.2, kind: seed.3, sortOrder: seed.4))
        }
        let appModel = AppModel(creativeService: PreviewCreativeService())

        let tagged = CreativeBrief(title: "TikTok idea", premise: "TikTok idea")
        tagged.preferredDestinationID = PublishingCatalog.tiktokID
        tagged.preferredFormatID = PublishingCatalog.tiktokLongID
        context.insert(tagged)
        let taggedOutput = appModel.ensurePostDraft(for: tagged, context: context)
        XCTAssertEqual(taggedOutput?.destinationID, PublishingCatalog.tiktokID)
        XCTAssertEqual(taggedOutput?.formatID, PublishingCatalog.tiktokLongID)
        XCTAssertEqual(taggedOutput?.platform, .tiktok)

        // Platform-only tags fall back to that platform's first format.
        let platformOnly = CreativeBrief(title: "YouTube idea", premise: "YouTube idea")
        platformOnly.preferredDestinationID = PublishingCatalog.youtubeID
        context.insert(platformOnly)
        let platformOnlyOutput = appModel.ensurePostDraft(for: platformOnly, context: context)
        XCTAssertEqual(platformOnlyOutput?.destinationID, PublishingCatalog.youtubeID)
        XCTAssertEqual(platformOnlyOutput?.formatID, PublishingCatalog.youtubeShortID)

        // An untagged idea keeps today's profile-default behavior.
        let untagged = CreativeBrief(title: "Plain idea", premise: "Plain idea")
        context.insert(untagged)
        let untaggedOutput = appModel.ensurePostDraft(for: untagged, context: context)
        XCTAssertEqual(untaggedOutput?.destinationID, PublishingCatalog.instagramID)
        XCTAssertEqual(untaggedOutput?.formatID, PublishingCatalog.instagramReelID)
    }
}
