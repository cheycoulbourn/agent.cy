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
        try deduplicateSingletonData(context: context)

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
        }

        let legacyTasks = tasks.filter { $0.bootstrapVersion < 1 }
        for task in legacyTasks where task.parentTaskID == nil {
            if task.pillarID != nil || (task.briefID == nil && [.planning, .creatorBusiness].contains(task.kind)) {
                task.lane = .pillar
            } else {
                task.lane = .production
            }
        }
        for task in legacyTasks where task.parentTaskID != nil {
            if let parentID = task.parentTaskID, let parent = byID[parentID] {
                task.lane = parent.lane
            } else if task.pillarID != nil || (task.briefID == nil && [.planning, .creatorBusiness].contains(task.kind)) {
                task.lane = .pillar
            } else {
                task.lane = .production
            }
        }
        for task in legacyTasks {
            task.bootstrapVersion = 1
        }
    }

    private static func migratePillars(context: ModelContext) throws {
        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let active = pillars.filter { !$0.isArchived }
        let legacy = pillars.filter { $0.bootstrapVersion < 1 }
        guard !legacy.isEmpty else { return }
        let establishedAnchor = active
            .filter({ $0.parentPillarID == nil && $0.role == .anchor })
            .sorted(by: stablePillarOrder)
            .first
        let legacyAnchor = legacy
            .filter({ !$0.isArchived && $0.parentPillarID == nil })
            .sorted(by: stablePillarOrder)
            .first
        guard let anchor = establishedAnchor ?? legacyAnchor else {
            for pillar in legacy {
                if pillar.isArchived { pillar.role = .supporting }
                pillar.bootstrapVersion = 1
            }
            return
        }

        if anchor.bootstrapVersion < 1 {
            anchor.role = .anchor
            anchor.parentPillarID = nil
        }
        let activeIDs = Set(active.map(\.id))
        for pillar in legacy where !pillar.isArchived && pillar.id != anchor.id {
            pillar.role = .supporting
            if pillar.parentPillarID.map({ !activeIDs.contains($0) }) ?? true {
                pillar.parentPillarID = anchor.id
            }
        }
        for pillar in legacy where pillar.isArchived && pillar.id != anchor.id {
            pillar.role = .supporting
        }
        for pillar in legacy {
            pillar.bootstrapVersion = 1
        }
    }

    /// CloudKit does not support unique constraints. These models are logical
    /// singletons (or, for week plans, one record per week), so simultaneous
    /// device creation is resolved here with stable application-level rules.
    private static func deduplicateSingletonData(context: ModelContext) throws {
        try deduplicateCreatorProfiles(context: context)
        deduplicateSubscriptions(try context.fetch(FetchDescriptor<SubscriptionState>()), context: context)
        deduplicateReminders(try context.fetch(FetchDescriptor<ReminderSettings>()), context: context)
        deduplicateRhythmTemplates(try context.fetch(FetchDescriptor<RhythmTemplate>()), context: context)
        deduplicateWeekPlans(try context.fetch(FetchDescriptor<WeekPlan>()), context: context)
    }

    private static func deduplicateCreatorProfiles(context: ModelContext) throws {
        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
            .sorted(by: preferredProfileOrder)
        guard let keeper = profiles.first, profiles.count > 1 else { return }

        let examples = try context.fetch(FetchDescriptor<VoiceExample>())
        let voiceProfiles = try context.fetch(FetchDescriptor<VoiceProfile>())
        let pendingVoiceProfiles = try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>())
        let socialAccounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>())

        for duplicate in profiles.dropFirst() {
            mergeMissingProfileValues(from: duplicate, into: keeper)
            for example in examples where example.profileID == duplicate.id { example.profileID = keeper.id }
            for profile in voiceProfiles where profile.profileID == duplicate.id { profile.profileID = keeper.id }
            for proposal in pendingVoiceProfiles where proposal.profileID == duplicate.id { proposal.profileID = keeper.id }
            for account in socialAccounts where account.profileID == duplicate.id { account.profileID = keeper.id }
            context.delete(duplicate)
        }
    }

    private static func preferredProfileOrder(_ lhs: CreatorProfile, _ rhs: CreatorProfile) -> Bool {
        let lhsScore = profileCompleteness(lhs)
        let rhsScore = profileCompleteness(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func profileCompleteness(_ profile: CreatorProfile) -> Int {
        var score = profile.onboardingCompleted ? 100 : 0
        score += profile.adultConfirmed ? 20 : 0
        score += profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 10
        score += profile.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 10
        score += profile.avatarImageData == nil ? 0 : 5
        score += profile.selectedDestinationIDs.isEmpty ? 0 : 3
        return score
    }

    private static func mergeMissingProfileValues(from source: CreatorProfile, into destination: CreatorProfile) {
        if destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { destination.name = source.name }
        if destination.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { destination.goal = source.goal }
        if destination.avatarImageData == nil { destination.avatarImageData = source.avatarImageData }
        destination.selectedDestinationIDs = stableUnion(destination.selectedDestinationIDs, source.selectedDestinationIDs)
        destination.selectedPlatforms = stableUnion(destination.selectedPlatforms, source.selectedPlatforms)
        destination.adultConfirmed = destination.adultConfirmed || source.adultConfirmed
        destination.onboardingCompleted = destination.onboardingCompleted || source.onboardingCompleted
        destination.createdAt = min(destination.createdAt, source.createdAt)
    }

    private static func stableUnion<Element: Hashable>(_ existing: [Element], _ additions: [Element]) -> [Element] {
        var seen = Set(existing)
        return existing + additions.filter { seen.insert($0).inserted }
    }

    private static func deduplicateSubscriptions(_ states: [SubscriptionState], context: ModelContext) {
        let sorted = states.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let keeper = sorted.first else { return }
        for duplicate in sorted.dropFirst() {
            keeper.freeBriefConsumed = keeper.freeBriefConsumed || duplicate.freeBriefConsumed
            keeper.ideationRequestsUsed = max(keeper.ideationRequestsUsed, duplicate.ideationRequestsUsed)
            keeper.revisionRequestsUsed = max(keeper.revisionRequestsUsed, duplicate.revisionRequestsUsed)
            keeper.teachCyUpdatesUsed = max(keeper.teachCyUpdatesUsed, duplicate.teachCyUpdatesUsed)
            context.delete(duplicate)
        }
    }

    private static func deduplicateReminders(_ settings: [ReminderSettings], context: ModelContext) {
        let sorted = settings.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for duplicate in sorted.dropFirst() { context.delete(duplicate) }
    }

    private static func deduplicateRhythmTemplates(_ templates: [RhythmTemplate], context: ModelContext) {
        let sorted = templates.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for duplicate in sorted.dropFirst() { context.delete(duplicate) }
    }

    private static func deduplicateWeekPlans(_ plans: [WeekPlan], context: ModelContext, calendar: Calendar = .current) {
        let grouped = Dictionary(grouping: plans) { plan in
            calendar.dateInterval(of: .weekOfYear, for: plan.weekStart)?.start ?? calendar.startOfDay(for: plan.weekStart)
        }
        for (weekStart, matches) in grouped {
            let sorted = matches.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let keeper = sorted.first else { continue }
            keeper.weekStart = weekStart
            for duplicate in sorted.dropFirst() {
                if keeper.rhythmEntriesText.isEmpty { keeper.rhythmEntriesText = duplicate.rhythmEntriesText }
                if keeper.notes.isEmpty { keeper.notes = duplicate.notes }
                context.delete(duplicate)
            }
        }
    }

    private static func stablePillarOrder(_ lhs: Pillar, _ rhs: Pillar) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
