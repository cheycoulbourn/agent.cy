import Foundation
import SwiftData

enum PublishingCatalog {
    static let instagramID = UUID(uuidString: "A6C71530-458A-4BF8-97FD-89D427A17901")!
    static let tiktokID = UUID(uuidString: "A6C71530-458A-4BF8-97FD-89D427A17902")!
    static let youtubeID = UUID(uuidString: "A6C71530-458A-4BF8-97FD-89D427A17903")!

    static let instagramReelID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28001")!
    static let instagramCarouselID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28002")!
    static let instagramFeedID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28003")!
    static let instagramStoryID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28004")!
    static let tiktokShortID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28005")!
    static let tiktokLongID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28006")!
    static let youtubeShortID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28007")!
    static let youtubeVideoID = UUID(uuidString: "B7D82641-569B-4CF9-A80E-90E538B28008")!

    static let destinationSeeds: [(UUID, String, BuiltInDestinationKind, Int)] = [
        (instagramID, "Instagram", .instagram, 0),
        (tiktokID, "TikTok", .tiktok, 1),
        (youtubeID, "YouTube", .youtube, 2)
    ]

    static let formatSeeds: [(UUID, UUID, String, PublishingFormatKind, Int)] = [
        (instagramReelID, instagramID, "Reel", .shortVideo, 0),
        (instagramCarouselID, instagramID, "Carousel", .nonVideo, 1),
        (instagramFeedID, instagramID, "Feed post", .nonVideo, 2),
        (instagramStoryID, instagramID, "Story", .nonVideo, 3),
        (tiktokShortID, tiktokID, "Short video", .shortVideo, 0),
        (tiktokLongID, tiktokID, "Long video", .longVideo, 1),
        (youtubeShortID, youtubeID, "Short", .shortVideo, 0),
        (youtubeVideoID, youtubeID, "Video", .longVideo, 1)
    ]

    static func identifiers(for legacy: CreatorPlatform) -> (destination: UUID, format: UUID) {
        switch legacy {
        case .instagramReels: (instagramID, instagramReelID)
        case .tiktok: (tiktokID, tiktokShortID)
        case .youtubeShorts: (youtubeID, youtubeShortID)
        case .youtubeVideo: (youtubeID, youtubeVideoID)
        }
    }

    static func legacyPlatform(destinationID: UUID, formatID: UUID) -> CreatorPlatform? {
        switch (destinationID, formatID) {
        case (instagramID, instagramReelID): .instagramReels
        case (tiktokID, tiktokShortID), (tiktokID, tiktokLongID): .tiktok
        case (youtubeID, youtubeShortID): .youtubeShorts
        case (youtubeID, youtubeVideoID): .youtubeVideo
        default: nil
        }
    }
}

@MainActor
enum StoreBootstrapService {
    static func run(context: ModelContext) throws {
        var destinations = try context.fetch(FetchDescriptor<PublishingDestination>())
        var formats = try context.fetch(FetchDescriptor<PublishingFormat>())

        for seed in PublishingCatalog.destinationSeeds where !destinations.contains(where: { $0.id == seed.0 }) {
            context.insert(PublishingDestination(id: seed.0, name: seed.1, builtInKind: seed.2, sortOrder: seed.3))
        }
        for seed in PublishingCatalog.formatSeeds where !formats.contains(where: { $0.id == seed.0 }) {
            context.insert(PublishingFormat(id: seed.0, destinationID: seed.1, name: seed.2, kind: seed.3, sortOrder: seed.4))
        }

        try context.save()
        destinations = try context.fetch(FetchDescriptor<PublishingDestination>())
        formats = try context.fetch(FetchDescriptor<PublishingFormat>())
        try deduplicateCatalog(destinations: destinations, formats: formats, context: context)

        try migrateProfiles(context: context)
        try migrateOutputs(context: context)
        try migrateTasks(context: context)
        try migratePillars(context: context)
        try context.save()
    }

    private static func deduplicateCatalog(destinations: [PublishingDestination], formats: [PublishingFormat], context: ModelContext) throws {
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let socialAccounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>())
        for kind in BuiltInDestinationKind.allCases {
            let matches = destinations.filter { $0.builtInKind == kind }.sorted { $0.createdAt < $1.createdAt }
            guard let keeper = matches.first else { continue }
            for duplicate in matches.dropFirst() {
                for format in formats where format.destinationID == duplicate.id { format.destinationID = keeper.id }
                for output in outputs where output.destinationID == duplicate.id { output.destinationID = keeper.id }
                for account in socialAccounts where account.destinationID == duplicate.id { account.destinationID = keeper.id }
                context.delete(duplicate)
            }
        }
    }

    private static func migrateProfiles(context: ModelContext) throws {
        for profile in try context.fetch(FetchDescriptor<CreatorProfile>()) where profile.selectedDestinationIDs.isEmpty {
            profile.selectedDestinationIDs = Array(Set(profile.selectedPlatforms.map { PublishingCatalog.identifiers(for: $0).destination }))
                .sorted { $0.uuidString < $1.uuidString }
        }
    }

    private static func migrateOutputs(context: ModelContext) throws {
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let durationByBrief = Dictionary(uniqueKeysWithValues: briefs.map { ($0.id, $0.durationSeconds) })
        for output in try context.fetch(FetchDescriptor<PlatformOutput>()) {
            let ids = PublishingCatalog.identifiers(for: output.platform)
            if output.destinationID == nil { output.destinationID = ids.destination }
            if output.formatID == nil { output.formatID = ids.format }
            if output.durationSeconds <= 0 { output.durationSeconds = durationByBrief[output.briefID] ?? 45 }
        }
    }

    private static func migrateTasks(context: ModelContext) throws {
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for task in tasks {
            task.priority = task.priority.normalized
            if let parentID = task.parentTaskID, let parent = byID[parentID] {
                task.lane = parent.lane
            } else if task.pillarID != nil || (task.briefID == nil && [.planning, .creatorBusiness].contains(task.kind)) {
                task.lane = .pillar
            } else {
                task.lane = .production
            }
        }
    }

    private static func migratePillars(context: ModelContext) throws {
        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let active = pillars.filter { !$0.isArchived }
        guard let anchor = active
            .filter({ $0.parentPillarID == nil || $0.role == .anchor })
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first ?? active.sorted(by: { $0.createdAt < $1.createdAt }).first else { return }

        anchor.role = .anchor
        anchor.parentPillarID = nil
        for pillar in active where pillar.id != anchor.id {
            pillar.role = .supporting
            pillar.parentPillarID = anchor.id
        }
        for pillar in pillars where pillar.isArchived && pillar.id != anchor.id {
            pillar.role = .supporting
        }
    }
}
