import Foundation

enum CreatorWorkspacePreferences {
    static let activeWorkspaceKey = "agentcy.creator.activeWorkspaceID"

    static var activeWorkspaceID: UUID? {
        get {
            UserDefaults.standard.string(forKey: activeWorkspaceKey).flatMap(UUID.init(uuidString:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: activeWorkspaceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeWorkspaceKey)
            }
            InspirationWorkspaceHintStore.save(
                newValue,
                defaults: UserDefaults(suiteName: InspirationSharedContainer.appGroupIdentifier)
            )
        }
    }
}

struct ActiveCreatorIdentity: Equatable, Sendable {
    let name: String
    let avatarImageData: Data?

    var greetingName: String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty ? "there" : cleanName
    }

    static func resolve(
        profile: CreatorProfile?,
        workspaces: [CreatorWorkspace],
        preferredWorkspaceID: UUID?
    ) -> Self {
        let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: preferredWorkspaceID,
            workspaces: workspaces
        )
        let workspace = activeID.flatMap { id in
            workspaces.first(where: { $0.id == id && !$0.isArchived })
        }

        if let workspace, workspace.hasCustomIdentity {
            return Self(
                name: workspace.creatorName.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarImageData: workspace.avatarImageData
            )
        }

        return Self(
            name: profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            avatarImageData: profile?.avatarImageData
        )
    }
}

enum WorkspaceScope {
    static func defaultWorkspace(in workspaces: [CreatorWorkspace]) -> CreatorWorkspace? {
        workspaces
            .filter { !$0.isArchived }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    static func activeWorkspaceID(
        preferredID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> UUID? {
        if let preferredID,
           workspaces.contains(where: { $0.id == preferredID && !$0.isArchived }) {
            return preferredID
        }
        return defaultWorkspace(in: workspaces)?.id
    }

    static func includes(
        _ recordWorkspaceID: UUID?,
        activeWorkspaceID preferredID: UUID?,
        workspaces: [CreatorWorkspace]
    ) -> Bool {
        guard let activeID = activeWorkspaceID(preferredID: preferredID, workspaces: workspaces) else {
            return recordWorkspaceID == nil
        }
        if let recordWorkspaceID { return recordWorkspaceID == activeID }
        return defaultWorkspace(in: workspaces)?.id == activeID
    }
}

/// Saved references are private to one creator workspace. Records without an
/// owner stay hidden until their ownership can be established safely.
enum SavedPostsScopePolicy {
    static func includes(recordWorkspaceID: UUID?, activeWorkspaceID: UUID?) -> Bool {
        guard let recordWorkspaceID, let activeWorkspaceID else { return false }
        return recordWorkspaceID == activeWorkspaceID
    }
}

enum CustomPostStatusPolicy {
    static let maximumLength = 32

    static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let collapsed = rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumLength))
    }

    static func comparisonKey(_ rawValue: String?) -> String? {
        guard let normalized = normalized(rawValue) else { return nil }
        let folded = normalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let invisibleScalars = CharacterSet(
            charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}"
        )
        let comparableScalars = folded.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) &&
                !CharacterSet.controlCharacters.contains(scalar) &&
                !invisibleScalars.contains(scalar)
        }
        let key = String(String.UnicodeScalarView(comparableScalars)).lowercased()
        return key.isEmpty ? nil : key
    }

    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhsKey = comparisonKey(lhs),
              let rhsKey = comparisonKey(rhs)
        else {
            return false
        }
        return lhsKey == rhsKey
    }

    static func displayLabel(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus,
        customStatus: String?,
        ideaBankPlacement: IdeaBankPlacement?
    ) -> String {
        if outputStatus == .posted || briefStatus == .posted { return "Posted" }
        if outputStatus == .scheduled || briefStatus == .scheduled { return "Scheduled" }
        if let customStatus = normalized(customStatus) { return customStatus }
        if ideaBankPlacement == .idea { return "Idea" }
        if briefStatus == .developing { return "In progress" }
        return "Draft"
    }
}

enum ContinueWorkingPostPolicy {
    static func includes(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus,
        customStatus: String?,
        ideaBankPlacement: IdeaBankPlacement?
    ) -> Bool {
        guard briefStatus != .archived,
              briefStatus != .scheduled,
              briefStatus != .posted,
              outputStatus != .scheduled,
              outputStatus != .posted,
              ideaBankPlacement != .idea else {
            return false
        }

        if CustomPostStatusPolicy.normalized(customStatus) != nil {
            return true
        }

        return outputStatus == .draft
    }

    static func displayLabel(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus,
        customStatus: String?,
        ideaBankPlacement: IdeaBankPlacement?
    ) -> String {
        if let customStatus = CustomPostStatusPolicy.normalized(customStatus),
           outputStatus != .scheduled,
           outputStatus != .posted,
           briefStatus != .scheduled,
           briefStatus != .posted {
            return customStatus
        }

        return CustomPostStatusPolicy.displayLabel(
            briefStatus: briefStatus,
            outputStatus: outputStatus,
            customStatus: customStatus,
            ideaBankPlacement: ideaBankPlacement
        )
    }
}

/// The Agenda's "Open posts" view includes every post that still needs to go live.
/// Scheduled posts remain open until they are actually marked as posted.
enum AgendaOpenPostPolicy {
    static func includes(
        briefStatus: BriefStatus,
        outputStatus: PlatformOutputStatus,
        ideaBankPlacement: IdeaBankPlacement?
    ) -> Bool {
        guard briefStatus != .archived,
              briefStatus != .posted,
              outputStatus != .posted,
              ideaBankPlacement != .idea else {
            return false
        }

        return true
    }
}

enum AssistanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case drive
    case collaborate
    case lead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: "I lead"
        case .collaborate: "Work together"
        case .lead: "Cy leads"
        }
    }

    var detail: String {
        switch self {
        case .drive: "Cy waits until you ask."
        case .collaborate: "Cy asks and suggests as you go."
        case .lead: "Cy guides you through the shortest path."
        }
    }
}

enum SparkSource: String, CaseIterable, Codable, Sendable {
    case text
    case voiceTranscript
    case cyDirection
    case repurposedBrief
    case sharedInspiration
}

enum InspirationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case shaping
    case ready
    case failed
    case converted
}

enum VoiceExampleSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case text
    case publicPostText
    case screenshotText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Pasted or dictated"
        case .publicPostText: "Instagram post"
        case .screenshotText: "Screenshot text"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .publicPostText: "link"
        case .screenshotText: "text.viewfinder"
        }
    }
}

enum VoiceSourceRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case ownVoice
    case inspiration

    var id: String { rawValue }
    var title: String { self == .ownVoice ? "Your voice" : "Inspiration" }
    var detail: String {
        self == .ownVoice
            ? "Counts toward the three examples Cy needs to learn your voice."
            : "Guides high-level traits only. Cy will not copy wording."
    }
}

struct VoiceExampleDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var text: String
    var source: VoiceExampleSource
    var sourceURLString: String

    init(
        id: UUID = UUID(),
        text: String = "",
        source: VoiceExampleSource = .text,
        sourceURLString: String = ""
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.sourceURLString = sourceURLString
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isUsableEvidence: Bool { !trimmedText.isEmpty }

    var hasLocalReference: Bool {
        InstagramPostReference.canonicalURL(from: sourceURLString) != nil
    }
}

enum InstagramPostReference {
    static func canonicalURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["instagram.com", "www.instagram.com", "m.instagram.com"].contains(host) else {
            return nil
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2,
              ["p", "reel", "tv"].contains(pathParts[0].lowercased()),
              !pathParts[1].isEmpty else {
            return nil
        }

        components.scheme = "https"
        components.host = "www.instagram.com"
        components.path = "/\(pathParts[0].lowercased())/\(pathParts[1])/"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

enum ContentFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case shortForm
    case longForm

    var id: String { rawValue }
    var title: String { self == .shortForm ? "Short-form" : "Long-form" }
    var durationOptions: [Int] {
        switch self {
        case .shortForm: [30, 60, 90, 180]
        case .longForm: [600, 1_200, 1_800, 2_700, 3_600]
        }
    }
    var defaultDuration: Int { self == .shortForm ? 60 : 600 }
}

enum ContentDurationLabel {
    static func compact(_ seconds: Int) -> String {
        if seconds <= 90 { return "\(seconds) SEC" }
        if seconds == 3_600 { return "1 HR" }
        if seconds.isMultiple(of: 60) { return "\(seconds / 60) MIN" }
        return "\(seconds) SEC"
    }

    static func full(_ seconds: Int) -> String {
        if seconds <= 90 { return "\(seconds) seconds" }
        if seconds == 3_600 { return "1 hour" }
        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return "\(seconds) seconds"
    }
}

enum PublishingFormatKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case shortVideo
    case longVideo
    case nonVideo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shortVideo: "Short video"
        case .longVideo: "Long video"
        case .nonVideo: "Non-video"
        }
    }
    var contentFormat: ContentFormat? {
        switch self {
        case .shortVideo: .shortForm
        case .longVideo: .longForm
        case .nonVideo: nil
        }
    }
    var defaultDurationSeconds: Int? {
        switch self {
        case .shortVideo: 60
        case .longVideo: 600
        case .nonVideo: nil
        }
    }
}

enum BuiltInDestinationKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case instagram
    case tiktok
    case youtube
    case substack
    case pinterest

    var id: String { rawValue }
    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .substack: "Substack"
        case .pinterest: "Pinterest"
        }
    }
}

enum CreatorPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case instagramReels
    case tiktok
    case youtubeShorts
    case youtubeVideo
    case substack
    case pinterest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagramReels: "Instagram Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "YouTube Shorts"
        case .youtubeVideo: "YouTube"
        case .substack: "Substack"
        case .pinterest: "Pinterest"
        }
    }

    var shortTitle: String {
        switch self {
        case .instagramReels: "Reels"
        case .tiktok: "TikTok"
        case .youtubeShorts: "Shorts"
        case .youtubeVideo: "YouTube"
        case .substack: "Substack"
        case .pinterest: "Pinterest"
        }
    }

    var symbol: String {
        switch self {
        case .instagramReels: "camera.aperture"
        case .tiktok: "music.note"
        case .youtubeShorts, .youtubeVideo: "play.rectangle.fill"
        case .substack: "doc.richtext"
        case .pinterest: "pin.fill"
        }
    }

    var format: ContentFormat {
        switch self {
        // Substack letters are the long-form home of the brand; everything
        // else in the short-form lane, including pins, plans like a short.
        case .youtubeVideo, .substack: .longForm
        case .instagramReels, .tiktok, .youtubeShorts, .pinterest: .shortForm
        }
    }

    static func choices(for format: ContentFormat) -> [CreatorPlatform] {
        allCases.filter { $0.format == format }
    }

    /// Catalog format names offered for this platform, in display order. The
    /// first entry is the default. One shared list so review editors and the
    /// post editor never drift apart.
    var catalogFormatChoices: [String] {
        switch self {
        case .instagramReels: ["Reel", "Carousel", "Feed post", "Story"]
        case .tiktok: ["Short video", "Long video"]
        case .youtubeShorts: ["Short"]
        case .youtubeVideo: ["Video"]
        case .substack: ["Letter", "Note"]
        case .pinterest: ["Pin"]
        }
    }

    var catalogDefaultFormat: String { catalogFormatChoices[0] }
}

enum BriefStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case spark
    case developing
    case ready
    case scheduled
    case posted
    case archived

    var id: String { rawValue }
    var title: String {
        switch self {
        case .spark: "Idea"
        case .developing: "In progress"
        case .ready: "Ready"
        case .scheduled: "Scheduled"
        case .posted: "Posted"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .spark: "sparkles"
        case .developing: "bubble.left.and.text.bubble.right"
        case .ready: "checkmark.seal"
        case .scheduled: "calendar"
        case .posted: "paperplane.fill"
        case .archived: "archivebox"
        }
    }
}

/// Explicitly separates saved ideas from post drafts that share the early
/// lifecycle states. `nil` is reserved for stores created before this field
/// existed and is handled by `IdeaBankPlacementPolicy`.
enum IdeaBankPlacement: String, Codable, Sendable {
    case idea
    case post
}

enum IdeaBankPlacementPolicy {
    static func includes(_ brief: CreativeBrief) -> Bool {
        guard brief.status != .archived else { return false }
        switch brief.ideaBankPlacement {
        case .idea:
            return true
        case .post:
            return false
        case nil:
            // Migration-safe fallback for existing creator data.
            return brief.status == .spark || brief.status == .developing
        }
    }
}

enum PlatformOutputStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case ready
    case scheduled
    case posted
}

enum PostRecurrenceFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Does not repeat"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

enum ContentSeriesState: String, CaseIterable, Codable, Identifiable, Sendable {
    case active
    case paused
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .archived: "Archived"
        }
    }
}

enum SeriesEpisodeSlotStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case open
    case converted
    case skipped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Episode needed"
        case .converted: "Episode created"
        case .skipped: "Skipped"
        }
    }
}

struct SeriesTaskTemplateItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var kind: CreatorTaskKind
    var priority: TaskPriority
    var estimatedMinutes: Int?
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        kind: CreatorTaskKind = .planning,
        priority: TaskPriority = .none,
        estimatedMinutes: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.kind = kind
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.sortOrder = sortOrder
    }
}

enum TaskRecurrenceFrequency: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "One time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

enum CreatorTaskKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case planning
    case scripting
    case filming
    case editing
    case publishing
    case creatorBusiness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creatorBusiness: "Creator business"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .planning: "lightbulb"
        case .scripting: "text.page"
        case .filming: "video"
        case .editing: "slider.horizontal.3"
        case .publishing: "paperplane"
        case .creatorBusiness: "briefcase"
        }
    }
}

enum TaskLane: String, CaseIterable, Codable, Identifiable, Sendable {
    case pillar
    case production

    var id: String { rawValue }
    var title: String { self == .pillar ? "Pillar" : "Focus" }
    var shortTitle: String { self == .pillar ? "Pillar" : "Focus" }
}

enum TaskCollection: String, CaseIterable, Identifiable, Sendable {
    case myTasks
    case postTasks

    var id: String { rawValue }
    var title: String { self == .postTasks ? "Post tasks" : "Focus tasks" }
}

enum TaskCollectionPolicy {
    static func collection(briefID: UUID?, platformOutputID: UUID?) -> TaskCollection {
        briefID != nil || platformOutputID != nil ? .postTasks : .myTasks
    }
}

enum TaskCalendarPolicy {
    static func mondayWeekInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: day),
              let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)
        else { return nil }
        return DateInterval(start: monday, end: nextMonday)
    }

    static func contains(
        _ date: Date,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= interval.start && day < interval.end
    }
}

enum TaskListVisibilityPolicy {
    /// Post Tasks stay reachable across weeks. Materialized recurring Focus
    /// Tasks retain a short horizon so future occurrences do not flood the list.
    static func includes(
        collection: TaskCollection,
        focusTaskTemplateID: UUID?,
        recurrence: TaskRecurrenceFrequency,
        recurrenceRootTaskID: UUID?,
        targetDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if collection == .postTasks {
            return true
        }

        if focusTaskTemplateID != nil {
            guard let targetDate,
                  let week = TaskCalendarPolicy.mondayWeekInterval(
                    containing: now,
                    calendar: calendar
                  )
            else { return true }
            return TaskCalendarPolicy.contains(
                targetDate,
                in: week,
                calendar: calendar
            )
        }

        let isRecurring = focusTaskTemplateID != nil ||
            recurrence != .none ||
            recurrenceRootTaskID != nil
        guard isRecurring, let targetDate else { return true }

        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 7, to: today) else {
            return true
        }
        return calendar.startOfDay(for: targetDate) <= horizon
    }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case high
    case urgent
    // Retained only so populated stores decode before the idempotent backfill.
    case low
    case medium

    var id: String { rawValue }
    static var selectableCases: [TaskPriority] { [.none, .high, .urgent] }
    var title: String {
        switch self {
        case .none, .low, .medium: "None"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }
    var normalized: TaskPriority {
        switch self {
        case .low, .medium: .none
        default: self
        }
    }
}

enum BrandPartnerStage: String, CaseIterable, Codable, Identifiable, Sendable {
    case wishlist
    case reachedOut
    case talking
    case workingTogether
    case pastPartner
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wishlist: "Wishlist"
        case .reachedOut: "Reached out"
        case .talking: "Talking"
        case .workingTogether: "Working together"
        case .pastPartner: "Past partner"
        case .archived: "Archived"
        }
    }
}

enum BrandPartnerType: String, CaseIterable, Codable, Identifiable, Sendable {
    case brand
    case agency
    case publicRelations
    case creator
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brand: "Brand"
        case .agency: "Agency"
        case .publicRelations: "PR"
        case .creator: "Creator"
        case .other: "Other"
        }
    }
}

enum BrandActivityKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case reachedOut
    case followedUp
    case receivedReply
    case meetingBooked
    case proposalSent
    case contractSigned
    case deliverableSent
    case paymentReceived
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reachedOut: "Reached out"
        case .followedUp: "Sent a follow-up"
        case .receivedReply: "Received a reply"
        case .meetingBooked: "Booked a meeting"
        case .proposalSent: "Sent a proposal"
        case .contractSigned: "Signed a contract"
        case .deliverableSent: "Sent a deliverable"
        case .paymentReceived: "Received payment"
        case .custom: "Custom"
        }
    }
}

enum DailyFocusKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case planning
    case scripting
    case filming
    case editing
    case publishing
    case community
    case businessAdmin

    // Kept so existing stores migrate without losing earlier focus choices.
    case posting
    case admin
    case custom

    var id: String { rawValue }

    static let selectableCases: [DailyFocusKind] = [
        .planning,
        .scripting,
        .filming,
        .editing,
        .publishing,
        .community,
        .businessAdmin,
    ]

    var title: String {
        switch self {
        case .planning: "Planning"
        case .scripting: "Scripting"
        case .filming: "Filming"
        case .editing: "Editing"
        case .publishing, .posting: "Publishing"
        case .community: "Community"
        case .businessAdmin, .admin: "Business & admin"
        case .custom: "Custom"
        }
    }

    var taskKind: CreatorTaskKind? {
        switch self {
        case .planning: .planning
        case .scripting: .scripting
        case .filming: .filming
        case .editing: .editing
        case .publishing, .posting: .publishing
        case .community, .businessAdmin, .admin: .creatorBusiness
        case .custom: nil
        }
    }

    var directive: String {
        switch self {
        case .planning:
            "Brainstorm your next post and plan the week ahead."
        case .scripting:
            "Write the hook, script, caption, and call to action for what you’re making."
        case .filming:
            "Film the week’s posts that need more production or hands-on execution."
        case .editing:
            "Edit the week’s footage and get each post ready for its final review."
        case .publishing, .posting:
            "Give every post a final check, then schedule or publish it with confidence."
        case .community:
            "Reply to comments and messages, support your community, and build real connection."
        case .businessAdmin, .admin:
            "Handle partnerships, invoices, email, contracts, and the admin that supports your content."
        case .custom:
            "Use this day for the work that matters most."
        }
    }

    var legacyDirective: String {
        switch self {
        case .planning:
            "Choose what to make and map the next steps."
        case .scripting:
            "Write hooks, beats, and calls to action."
        case .filming:
            "Batch record while your setup is ready."
        case .editing:
            "Shape footage into clean, finished cuts."
        case .publishing, .posting:
            "Finish captions, covers, and posting details."
        case .community:
            "Reply, engage, and connect with your audience."
        case .businessAdmin, .admin:
            "Handle the work that keeps your creator business moving."
        case .custom:
            "Use this day for the work that matters most."
        }
    }

    static func combinedTitle(_ kinds: [DailyFocusKind]) -> String {
        let unique = kinds.reduce(into: [DailyFocusKind]()) { values, kind in
            if !values.contains(kind) { values.append(kind) }
        }
        guard let first = unique.first else { return "Rest" }
        guard unique.count > 1 else { return first.title }
        return "\(first.title) & \(unique[1].title.lowercased())"
    }

    static func combinedDirective(_ kinds: [DailyFocusKind]) -> String {
        let unique = kinds.reduce(into: [DailyFocusKind]()) { values, kind in
            if !values.contains(kind) { values.append(kind) }
        }
        guard let first = unique.first else {
            return "No focus is assigned. Use the day however you need."
        }
        guard unique.count > 1 else { return first.directive }

        let firstClause = sentenceClause(first.directive)
        let secondClause = sentenceClause(unique[1].directive, lowercasingFirstCharacter: true)
        return "\(firstClause), then \(secondClause)."
    }

    static func legacyCombinedDirective(_ kinds: [DailyFocusKind]) -> String {
        let unique = kinds.reduce(into: [DailyFocusKind]()) { values, kind in
            if !values.contains(kind) { values.append(kind) }
        }
        guard !unique.isEmpty else { return "Recover, reset, or leave the day open." }
        return unique.prefix(2).map(\.legacyDirective).joined(separator: " ")
    }

    private static func sentenceClause(
        _ sentence: String,
        lowercasingFirstCharacter: Bool = false
    ) -> String {
        let clause = sentence.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        guard lowercasingFirstCharacter, let first = clause.first else { return clause }
        return String(first).lowercased() + String(clause.dropFirst())
    }
}

enum PillarRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case anchor
    case supporting

    var id: String { rawValue }
    var title: String { self == .anchor ? "Anchor pillar" : "Secondary pillar" }
}

enum CompensationType: String, CaseIterable, Codable, Identifiable, Sendable {
    case paid
    case gifted
    case both

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AttachmentOwnerKind: String, Codable, Sendable {
    case referenceFile
    case postMedia
    case collaborationFile
    case moodBoardMedia
}

enum AttachmentKind: String, Codable, Sendable {
    case photo
    case video
    case document
    case other
}

enum AttachmentSyncState: String, Codable, Sendable {
    case localOnly
    case eligible
    case synced
    case failed
}

enum AppearancePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DeviceAppearancePreferences {
    static let storageKey = "agentcy.deviceAppearancePreference"

    static func load(
        defaults: UserDefaults = .standard,
        legacyFallback: AppearancePreference = .system
    ) -> AppearancePreference {
        if let rawValue = defaults.string(forKey: storageKey),
           let preference = AppearancePreference(rawValue: rawValue) {
            return preference
        }

        defaults.set(legacyFallback.rawValue, forKey: storageKey)
        return legacyFallback
    }

    static func save(
        _ preference: AppearancePreference,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(preference.rawValue, forKey: storageKey)
    }
}

enum CreatorVibePalette: String, CaseIterable, Codable, Identifiable, Sendable {
    case grayscale
    case pastel
    case neutral
    case colorful
    case dark
    case midnight
    case soho
    case tooCool
    case scraper

    var id: String { rawValue }
    var title: String {
        switch self {
        case .grayscale: "Stone"
        case .pastel: "Soft Girl Era"
        case .neutral: "Aesthetica"
        case .colorful: "Vivrant Thing"
        case .dark: "(not) Vivrant Thing"
        case .soho: "Soho"
        case .midnight: "Midnight"
        case .tooCool: "Too Cool"
        case .scraper: "Scraper"
        }
    }

    static let fallbackPillarColorHexes = ["9B3A2E", "B47724", "55705B", "416B85", "76506F"]

    var detail: String {
        switch self {
        case .grayscale: "Quiet and minimal"
        case .pastel: "Soft and airy"
        case .neutral: "Grounded and warm"
        case .colorful: "Bright and expressive"
        case .dark: "Deep and moody"
        case .soho: "Editorial and earthy"
        case .midnight: "Smoky and grounded"
        case .tooCool: "Clean and cinematic"
        case .scraper: "Industrial and electric"
        }
    }

    var pillarColorHexes: [String] {
        switch self {
        case .grayscale: ["343434", "5A5A5A", "7C7C7C", "9E9E9E", "C2C2C2"]
        case .pastel: ["F2C6CF", "F4F1E2", "D8EBF9", "FCE6B7", "D7D4B1"]
        case .neutral: ["443A35", "252525", "E4DDCC", "F8F4EE", "C5B49D"]
        case .colorful: ["E45545", "F0A202", "2E8B57", "3973C6", "8D4BC7"]
        case .dark: ["6C3547", "755321", "31594A", "2E4A66", "4F3D66"]
        case .soho: ["895A38", "6B5932", "C2CDD4", "D2C4A2", "E7E6CA", "4F1615"]
        case .midnight: ["0D0502", "4C2421", "B2A998", "CBCAC2", "998368"]
        case .tooCool: ["440607", "1B2345", "E3DFD4", "020202", "4F4439", "64646D"]
        case .scraper: ["F15B3A", "101010", "2A2D2E", "E3E3E3", "E6E2A3", "FEFBFA"]
        }
    }

    static let standardPalettes: [CreatorVibePalette] = [
        .grayscale, .pastel, .neutral, .colorful, .dark, .midnight
    ]

    static let signaturePalettes: [CreatorVibePalette] = [.soho, .tooCool, .scraper]

    /// A deliberately small starting set for onboarding. The full palette
    /// library remains available from Settings after setup.
    static let onboardingPalettes: [CreatorVibePalette] = [
        .pastel, .neutral, .soho, .tooCool
    ]

    static func matchingPalette(for colorHexes: [String]) -> CreatorVibePalette? {
        let colors = colorHexes.map(normalizedColorHex)
        guard !colors.isEmpty else { return nil }
        return allCases.first { palette in
            let paletteColors = palette.pillarColorHexes.map(normalizedColorHex)
            guard colors.count <= paletteColors.count else { return false }
            return Array(paletteColors.prefix(colors.count)) == colors
        }
    }

    private static func normalizedColorHex(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
    }
}

@MainActor
enum PillarPaletteAssignment {
    /// Applies one distinct palette color per active pillar. A collection larger
    /// than the selected palette is left unchanged rather than repeating colors.
    @discardableResult
    static func apply(_ palette: CreatorVibePalette, to pillars: [Pillar]) -> Int {
        let activePillars = pillars.filter { !$0.isArchived }
        let colors = palette.pillarColorHexes
        guard !activePillars.isEmpty,
              activePillars.count <= colors.count
        else { return 0 }
        for (index, pillar) in activePillars.enumerated() {
            pillar.colorHex = colors[index]
        }
        return activePillars.count
    }
}

enum PillarCollectionPolicy {
    static let maximumActiveCount = 6

    static func canCreate(activeCount: Int) -> Bool {
        activeCount < maximumActiveCount
    }
}

enum ConversationContextKind: String, Codable, Sendable {
    case none
    case brief
    case task
    case pillar
    case day
}

enum PillarWeekday: Int, CaseIterable, Codable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var title: String {
        Calendar.current.weekdaySymbols[rawValue - 1]
    }

    var shortTitle: String {
        Calendar.current.shortWeekdaySymbols[rawValue - 1]
    }

    var letter: String {
        String(title.prefix(1)).uppercased()
    }

    static var mondayFirst: [PillarWeekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}

enum SubscriptionAccess: String, CaseIterable, Codable, Sendable {
    case freeJourney
    case trial
    case paid
    case comped
    case expired

    var canCreate: Bool { self != .expired }
    var canUseCy: Bool { self != .expired }
    var canEditExisting: Bool { true }
}

enum ConversationRole: String, Codable, Sendable {
    case creator
    case cy
    case claude
}

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case today
    case tasks
    case pillars
    case ideaBank
    case cy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .today: "Plan"
        case .ideaBank: "Idea Bank"
        default: rawValue.capitalized
        }
    }

    var icon: AgentIcon {
        switch self {
        case .home: .home
        case .today: .calendar
        case .tasks: .tasks
        case .pillars: .pillars
        case .ideaBank: .ideas
        case .cy: .idea
        }
    }
}

enum WeeklyPlanningCue {
    static let lastOpenedStorageKey = "agentcy.cy.weekly-planning.last-opened-week"

    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
    }

    static func shouldPulse(
        on date: Date,
        lastOpenedWeekKey: String,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.component(.weekday, from: date) == 2 &&
            lastOpenedWeekKey != weekKey(for: date, calendar: calendar)
    }
}

enum ReplanChoice: String, CaseIterable, Identifiable, Sendable {
    case move
    case pause
    case archive

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct BriefLifecycleEntry: Identifiable, Equatable, Sendable {
    let status: BriefStatus
    let date: Date

    var id: String { "\(date.timeIntervalSince1970)|\(status.rawValue)" }
}

struct IdeaDirection: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let premise: String
    let opening: String
    let assumption: String
    let suggestedPillarID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        premise: String,
        opening: String,
        assumption: String,
        suggestedPillarID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.premise = premise
        self.opening = opening
        self.assumption = assumption
        self.suggestedPillarID = suggestedPillarID
    }
}

struct BriefDraft: Codable, Equatable, Sendable {
    var title: String
    var premise: String
    var audience: String
    var goal: String
    var takeaway: String
    var durationSeconds: Int
    var spokenHook: String
    var firstFrameText: String
    var scriptBeats: [String]
    var close: String
    var ctaIntent: String
    var filmingGuidance: String
    var editingGuidance: String
    var assumptions: [String]
    var voiceConfidence: Double
}

struct PlatformVariantDraft: Codable, Equatable, Sendable {
    var platform: CreatorPlatform
    var caption: String
    var openingAdjustment: String
    var titleOverride: String
    var cta: String
    var editChanges: String
}

struct ProposedCreatorTask: Codable, Equatable, Sendable {
    var title: String
    var kind: CreatorTaskKind
    var notes: String = ""
    var estimatedMinutes: Int?
    var isRecordingMilestone = false
}

struct BriefProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let briefID: UUID
    var draft: BriefDraft
    var variants: [PlatformVariantDraft]
    var tasks: [ProposedCreatorTask]
    var canonicalBrief: ReadyBriefWire?

    init(id: UUID = UUID(), briefID: UUID, draft: BriefDraft, variants: [PlatformVariantDraft], tasks: [ProposedCreatorTask], canonicalBrief: ReadyBriefWire? = nil) {
        self.id = id
        self.briefID = briefID
        self.draft = draft
        self.variants = variants
        self.tasks = tasks
        self.canonicalBrief = canonicalBrief
    }
}

struct BriefRevisionProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let briefID: UUID
    let sourceUpdatedAt: Date
    let requestedScope: BriefRevisionFieldWire
    let instruction: String
    let changedFields: [BriefRevisionFieldWire]
    let explanation: String
    let baseline: BriefProposal
    var edited: BriefProposal
    let sourceTaskIDs: [UUID]
    let canonicalBrief: ReadyBriefWire

    init(
        id: UUID = UUID(),
        briefID: UUID,
        sourceUpdatedAt: Date,
        requestedScope: BriefRevisionFieldWire,
        instruction: String,
        changedFields: [BriefRevisionFieldWire],
        explanation: String,
        baseline: BriefProposal,
        edited: BriefProposal,
        sourceTaskIDs: [UUID],
        canonicalBrief: ReadyBriefWire
    ) {
        self.id = id
        self.briefID = briefID
        self.sourceUpdatedAt = sourceUpdatedAt
        self.requestedScope = requestedScope
        self.instruction = instruction
        self.changedFields = changedFields
        self.explanation = explanation
        self.baseline = baseline
        self.edited = edited
        self.sourceTaskIDs = sourceTaskIDs
        self.canonicalBrief = canonicalBrief
    }
}

struct VoiceProfileDraft: Codable, Equatable, Sendable {
    var summary: String
    var tone: [String]
    var sentenceStyle: String
    var signatureQualities: [String]
    var phrasesToUse: [String]
    var phrasesToAvoid: [String]
    var guidance: [String]
    var confidence: Double

    init(_ profile: VoiceProfileWire) {
        summary = profile.summary
        tone = profile.tone
        sentenceStyle = profile.sentenceStyle
        signatureQualities = profile.signatureQualities
        phrasesToUse = profile.phrasesToUse
        phrasesToAvoid = profile.phrasesToAvoid
        guidance = profile.guidance
        confidence = profile.confidence
    }

    var wire: VoiceProfileWire {
        VoiceProfileWire(
            summary: summary,
            tone: tone,
            sentenceStyle: sentenceStyle,
            signatureQualities: signatureQualities,
            phrasesToUse: phrasesToUse,
            phrasesToAvoid: phrasesToAvoid,
            guidance: guidance,
            confidence: confidence
        )
    }
}

struct VoiceProfileChangeProposal: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let profileID: UUID
    let sourceVersion: Int
    let sourceUpdatedAt: Date
    let instruction: String
    let baseline: VoiceProfileDraft
    var edited: VoiceProfileDraft
    let assumptions: [String]
    let evidenceNotes: [String]

    init(
        id: UUID = UUID(),
        profileID: UUID,
        sourceVersion: Int,
        sourceUpdatedAt: Date,
        instruction: String,
        baseline: VoiceProfileDraft,
        edited: VoiceProfileDraft,
        assumptions: [String],
        evidenceNotes: [String]
    ) {
        self.id = id
        self.profileID = profileID
        self.sourceVersion = sourceVersion
        self.sourceUpdatedAt = sourceUpdatedAt
        self.instruction = instruction
        self.baseline = baseline
        self.edited = edited
        self.assumptions = assumptions
        self.evidenceNotes = evidenceNotes
    }
}

struct VoiceProfileExtraction: Equatable, Sendable {
    let summary: String
    let traits: String
    let avoid: String
    let canonical: VoiceProfileWire
}

enum AssistanceInitiative: Sendable {
    case quiet
    case contextual
    case proactive
}

struct AssistancePolicy: Sendable {
    let mode: AssistanceMode

    var initiative: AssistanceInitiative {
        switch mode {
        case .drive: .quiet
        case .collaborate: .contextual
        case .lead: .proactive
        }
    }

    func pillarProposalLimit(explicitlyRequested: Bool) -> Int {
        switch mode {
        case .drive: explicitlyRequested ? 3 : 0
        case .collaborate: 1
        case .lead: 3
        }
    }
}

struct OnboardingPillarDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var colorHex = "55705B"
    var assignedWeekdays: Set<PillarWeekday> = []
}

enum OnboardingAIProvider: String, CaseIterable, Codable, Sendable {
    case agentCy
    case claudeOrCodex

    var title: String {
        switch self {
        case .agentCy: "Agent Cy AI"
        case .claudeOrCodex: "Claude or Codex"
        }
    }
}

struct OnboardingDraft: Equatable, Sendable {
    var adultConfirmed = false
    var telemetryConsent = false
    var name = ""
    var goal = ""
    var vibePalette: CreatorVibePalette?
    var appearance: AppearancePreference? = .system
    var platforms: Set<CreatorPlatform> = []
    /// Days per week the creator aims to post. Nil when the step is skipped;
    /// the Consistency card prompts for it later.
    var weeklyPostingGoal: Int?
    // Retained while the Paper-led onboarding flow is migrated so existing
    // onboarding services and saved drafts continue to compile and decode.
    var assistanceMode: AssistanceMode = .collaborate
    var pillars: [OnboardingPillarDraft] = []
    var voiceExamples: [VoiceExampleDraft] = []
    var voiceSummary = ""
    var voiceTraits = ""
    var voiceAvoid = ""
    var voiceProfilePayloadJSON = ""
    var accountHandles: [BuiltInDestinationKind: String] = [:]
    var aiProvider: OnboardingAIProvider = .agentCy
    var brandPartnershipsEnabled = false
    var dailyReminderEnabled = true
    var dailyReminderHour = 9
    var dailyReminderMinute = 0
    var weeklyReminderEnabled = true
    var weeklyReminderWeekday = 2
    var weeklyReminderHour = 9
    var weeklyReminderMinute = 0
}

/// Adopted by creator-owned records that belong to one account workspace.
/// A nil value is intentionally retained for CloudKit migration compatibility
/// and is treated as belonging to the default workspace.
protocol WorkspaceScopedRecord {
    var workspaceID: UUID? { get }
}
