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
        try migrateCreatorWorkspaces(context: context)
        try SeriesMigrationService.run(context: context)
        try migrateDailyFocusCopy(context: context)
        try context.save()
    }

    private static func migrateDailyFocusCopy(context: ModelContext) throws {
        let now = Date()

        for entry in try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>()) {
            let kinds = DailyFocusResolver.normalizedKinds(
                primary: entry.kind,
                secondary: entry.secondaryKind,
                storedTitle: entry.title
            )
            var changed = false

            if entry.hasConfiguredFocusTasks,
               let migrated = DailyFocusTaskDefaults.migratedLegacyDefaultsIfUntouched(
                   entry.focusTaskTemplates,
                   for: kinds
               ) {
                entry.focusTaskTemplates = migrated
                changed = true
            }

            let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty, note == DailyFocusKind.legacyCombinedDirective(kinds) {
                entry.note = ""
                changed = true
            }

            if changed { entry.updatedAt = now }
        }

        for override in try context.fetch(FetchDescriptor<DailyFocusOverride>()) {
            let kinds = DailyFocusResolver.normalizedKinds(
                primary: override.kind,
                secondary: override.secondaryKind,
                storedTitle: override.title
            )
            let note = override.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty, note == DailyFocusKind.legacyCombinedDirective(kinds) else { continue }
            override.note = ""
            override.updatedAt = now
        }
    }

    private static func migrateCreatorWorkspaces(context: ModelContext) throws {
        guard let profile = try context.fetch(FetchDescriptor<CreatorProfile>()).first else { return }
        var workspaces = try context.fetch(FetchDescriptor<CreatorWorkspace>())
        let accounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>())
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }

        if workspaces.isEmpty {
            let preferredAccount = accounts.first(where: \.isPrimary) ?? accounts.first
            let primaryAccountIDs = Set(Dictionary(grouping: accounts, by: \.destinationID).compactMap { _, candidates in
                candidates.first(where: \.isPrimary)?.id ?? candidates.first?.id
            })
            let fallbackName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultWorkspace = CreatorWorkspace(
                profileID: profile.id,
                name: preferredAccount?.label ?? (fallbackName.isEmpty ? "My account" : fallbackName),
                creatorName: fallbackName,
                avatarImageData: profile.avatarImageData,
                hasCustomIdentity: true,
                primarySocialAccountID: preferredAccount?.id,
                sortOrder: 0
            )
            context.insert(defaultWorkspace)
            workspaces.append(defaultWorkspace)

            for account in accounts where primaryAccountIDs.contains(account.id) {
                account.workspaceID = defaultWorkspace.id
            }
            for (index, account) in accounts.filter({ !primaryAccountIDs.contains($0.id) }).enumerated() {
                let workspace = CreatorWorkspace(
                    profileID: profile.id,
                    name: account.label,
                    creatorName: fallbackName,
                    avatarImageData: profile.avatarImageData,
                    hasCustomIdentity: true,
                    primarySocialAccountID: account.id,
                    sortOrder: index + 1
                )
                context.insert(workspace)
                workspaces.append(workspace)
                account.workspaceID = workspace.id
            }
        }

        guard let defaultWorkspace = WorkspaceScope.defaultWorkspace(in: workspaces) else { return }
        for workspace in workspaces where !workspace.hasCustomIdentity {
            workspace.creatorName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.avatarImageData = profile.avatarImageData
            workspace.hasCustomIdentity = true
            workspace.updatedAt = Date()
        }
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var workspaceByID = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })

        for account in accounts where account.workspaceID == nil {
            let workspace = CreatorWorkspace(
                profileID: profile.id,
                name: account.label,
                creatorName: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarImageData: profile.avatarImageData,
                hasCustomIdentity: true,
                primarySocialAccountID: account.id,
                sortOrder: (workspaces.map(\.sortOrder).max() ?? -1) + 1
            )
            context.insert(workspace)
            workspaces.append(workspace)
            workspaceByID[workspace.id] = workspace
            account.workspaceID = workspace.id
        }

        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let outputsByBrief = Dictionary(grouping: outputs, by: \.briefID)
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        for brief in briefs where brief.workspaceID == nil {
            brief.workspaceID = outputsByBrief[brief.id]?
                .compactMap { $0.socialAccountID.flatMap { accountByID[$0]?.workspaceID } }
                .first ?? defaultWorkspace.id
        }
        let briefWorkspaceByID = briefs.reduce(into: [UUID: UUID]()) { result, brief in
            if let workspaceID = brief.workspaceID { result[brief.id] = workspaceID }
        }

        for output in outputs where output.workspaceID == nil {
            output.workspaceID = briefWorkspaceByID[output.briefID] ?? defaultWorkspace.id
        }

        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        for pillar in pillars where pillar.workspaceID == nil { pillar.workspaceID = defaultWorkspace.id }
        let pillarWorkspaceByID = pillars.reduce(into: [UUID: UUID]()) { result, pillar in
            if let workspaceID = pillar.workspaceID { result[pillar.id] = workspaceID }
        }

        for task in try context.fetch(FetchDescriptor<CreatorTask>()) where task.workspaceID == nil {
            task.workspaceID = task.briefID.flatMap { briefWorkspaceByID[$0] }
                ?? task.pillarID.flatMap { pillarWorkspaceByID[$0] }
                ?? defaultWorkspace.id
        }
        for proposal in try context.fetch(FetchDescriptor<PendingBriefProposal>()) where proposal.workspaceID == nil {
            proposal.workspaceID = briefWorkspaceByID[proposal.briefID] ?? defaultWorkspace.id
        }
        for attachment in try context.fetch(FetchDescriptor<CreatorAttachment>()) where attachment.workspaceID == nil {
            attachment.workspaceID = briefWorkspaceByID[attachment.briefID] ?? defaultWorkspace.id
        }
        for entry in try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>()) where entry.workspaceID == nil {
            entry.workspaceID = defaultWorkspace.id
        }
        for override in try context.fetch(FetchDescriptor<DailyFocusOverride>()) where override.workspaceID == nil {
            override.workspaceID = defaultWorkspace.id
        }
        for detail in try context.fetch(FetchDescriptor<DailyFocusDayDetail>()) where detail.workspaceID == nil {
            detail.workspaceID = defaultWorkspace.id
        }
        for proposal in try context.fetch(FetchDescriptor<PendingWeekProposal>()) where proposal.workspaceID == nil {
            proposal.workspaceID = defaultWorkspace.id
        }
        for template in try context.fetch(FetchDescriptor<RhythmTemplate>()) where template.workspaceID == nil {
            template.workspaceID = defaultWorkspace.id
        }
        for plan in try context.fetch(FetchDescriptor<WeekPlan>()) where plan.workspaceID == nil {
            plan.workspaceID = defaultWorkspace.id
        }
        for thread in try context.fetch(FetchDescriptor<ConversationThread>()) where thread.workspaceID == nil {
            thread.workspaceID = defaultWorkspace.id
        }

        if CreatorWorkspacePreferences.activeWorkspaceID.flatMap({ workspaceByID[$0] }) == nil {
            CreatorWorkspacePreferences.activeWorkspaceID = defaultWorkspace.id
        }
    }

    private static func deduplicateCatalog(destinations: [PublishingDestination], formats: [PublishingFormat], context: ModelContext) throws {
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let socialAccounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>())
        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        for kind in BuiltInDestinationKind.allCases {
            let matches = destinations.filter { $0.builtInKind == kind }.sorted { $0.createdAt < $1.createdAt }
            let canonicalID = PublishingCatalog.destinationSeeds.first(where: { $0.2 == kind })?.0
            guard let keeper = matches.first(where: { $0.id == canonicalID }) ?? matches.first else { continue }
            for duplicate in matches where duplicate.id != keeper.id {
                for format in formats where format.destinationID == duplicate.id { format.destinationID = keeper.id }
                for output in outputs where output.destinationID == duplicate.id { output.destinationID = keeper.id }
                for account in socialAccounts where account.destinationID == duplicate.id { account.destinationID = keeper.id }
                for profile in profiles where profile.selectedDestinationIDs.contains(duplicate.id) {
                    profile.selectedDestinationIDs = stableUnion(
                        [],
                        profile.selectedDestinationIDs.map { $0 == duplicate.id ? keeper.id : $0 }
                    )
                }
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
            if output.durationSeconds <= 0 { output.durationSeconds = durationByBrief[output.briefID] ?? ContentFormat.shortForm.defaultDuration }
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
        if destination.vibePalette == nil { destination.vibePalette = source.vibePalette }
        if destination.appearance == .system, source.appearance != .system { destination.appearance = source.appearance }
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
        let accessSource: SubscriptionState
        if keeper.access == .freeJourney,
           let activeEntitlement = sorted.first(where: hasPotentiallyActiveEntitlement) {
            accessSource = activeEntitlement
        } else {
            accessSource = keeper
        }
        keeper.access = accessSource.access
        keeper.trialEnd = [.trial, .comped].contains(accessSource.access)
            ? accessSource.trialEnd
            : nil
        for duplicate in sorted.dropFirst() {
            keeper.freeBriefConsumed = keeper.freeBriefConsumed || duplicate.freeBriefConsumed
            keeper.ideationRequestsUsed = max(keeper.ideationRequestsUsed, duplicate.ideationRequestsUsed)
            keeper.revisionRequestsUsed = max(keeper.revisionRequestsUsed, duplicate.revisionRequestsUsed)
            keeper.teachCyUpdatesUsed = max(keeper.teachCyUpdatesUsed, duplicate.teachCyUpdatesUsed)
            context.delete(duplicate)
        }
    }

    private static func hasPotentiallyActiveEntitlement(_ state: SubscriptionState) -> Bool {
        switch state.access {
        case .paid:
            return true
        case .comped:
            return state.trialEnd.map { $0 > Date() } ?? true
        case .trial:
            return state.trialEnd.map { $0 > Date() } ?? false
        case .freeJourney, .expired:
            return false
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
