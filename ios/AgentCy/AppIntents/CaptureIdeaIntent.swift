import AppIntents
import Foundation
import SwiftData

struct CaptureIdeaPillarEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pillar")
    static let defaultQuery = CaptureIdeaPillarQuery()

    static let unfiled = CaptureIdeaPillarEntity(
        id: "unfiled",
        name: "No pillar",
        context: "Save without filing"
    )

    let id: String
    let name: String
    let context: String

    var pillarID: UUID? {
        id == Self.unfiled.id ? nil : UUID(uuidString: id)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(context)"
        )
    }
}

struct CaptureIdeaPillarQuery: EntityQuery {
    func entities(for identifiers: [CaptureIdeaPillarEntity.ID]) async throws -> [CaptureIdeaPillarEntity] {
        let store = CaptureIdeaShortcutStore(modelContainer: ModelContainerFactory.shared)
        return try await store.pillarEntities(for: identifiers)
    }

    func suggestedEntities() async throws -> [CaptureIdeaPillarEntity] {
        let store = CaptureIdeaShortcutStore(modelContainer: ModelContainerFactory.shared)
        return try await store.activePillarEntities()
    }
}

struct CaptureIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Idea"
    static let description = IntentDescription(
        "Ask for an idea and a pillar, then save the idea privately in agent.cy."
    )

    @Parameter(
        title: "Idea",
        description: "The thought you want to remember.",
        requestValueDialog: "What's your idea?"
    )
    var idea: String

    @Parameter(
        title: "Pillar",
        description: "Where this idea belongs.",
        requestValueDialog: "What pillar is this related to?"
    )
    var pillar: CaptureIdeaPillarEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$idea) to \(\.$pillar)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = CaptureIdeaShortcutStore(modelContainer: ModelContainerFactory.shared)
        let outcome = try await store.save(idea: idea, pillarID: pillar.pillarID)

        switch outcome {
        case .saved(let title):
            let destination = pillar.pillarID == nil ? "Idea Bank" : pillar.name
            return .result(dialog: "Saved \(title) to \(destination).")
        case .empty:
            return .result(dialog: "Tell me the idea you want to save.")
        case .creationUnavailable:
            return .result(dialog: "Open agent.cy to restore creation access, then try again.")
        }
    }
}

struct AgentCyAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIdeaIntent(),
            phrases: [
                "Capture an idea in \(.applicationName)",
                "Save an idea in \(.applicationName)",
                "Add an idea to \(.applicationName)"
            ],
            shortTitle: "Capture Idea",
            systemImageName: "lightbulb"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .orange }
}

enum CaptureIdeaShortcutSaveOutcome: Equatable, Sendable {
    case saved(title: String)
    case empty
    case creationUnavailable
}

@ModelActor
actor CaptureIdeaShortcutStore {
    func activePillarEntities() throws -> [CaptureIdeaPillarEntity] {
        let workspaces = try modelContext.fetch(FetchDescriptor<CreatorWorkspace>())
        let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        let pillars = try modelContext.fetch(
            FetchDescriptor<Pillar>(sortBy: [SortDescriptor(\Pillar.createdAt)])
        ).filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
        }
        return [.unfiled] + pillars
            .filter { !$0.isArchived }
            .map { pillarEntity(for: $0, among: pillars) }
    }

    func pillarEntities(for identifiers: [String]) throws -> [CaptureIdeaPillarEntity] {
        guard !identifiers.isEmpty else { return [] }
        let requested = Set(identifiers)
        return try activePillarEntities().filter { requested.contains($0.id) }
    }

    func save(idea: String, pillarID: UUID?) throws -> CaptureIdeaShortcutSaveOutcome {
        let cleanIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIdea.isEmpty else { return .empty }

        let states = try modelContext.fetch(FetchDescriptor<SubscriptionState>())
        guard AccessPolicy.allows(.createSpark, state: states.first) else {
            return .creationUnavailable
        }

        let workspaces = try modelContext.fetch(FetchDescriptor<CreatorWorkspace>())
        let activeID = WorkspaceScope.activeWorkspaceID(
            preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
            workspaces: workspaces
        )
        var resolvedPillarID: UUID?
        if let pillarID {
            let pillars = try modelContext.fetch(FetchDescriptor<Pillar>())
            resolvedPillarID = pillars.contains {
                $0.id == pillarID && !$0.isArchived &&
                    WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: activeID, workspaces: workspaces)
            }
                ? pillarID
                : nil
        }

        let title = Self.title(from: cleanIdea)
        let brief = CreativeBrief(title: title, premise: cleanIdea, source: .text)
        brief.workspaceID = activeID
        brief.ideaBankPlacement = .idea
        brief.pillarID = resolvedPillarID
        modelContext.insert(brief)
        try modelContext.save()
        return .saved(title: title)
    }

    private func pillarEntity(for pillar: Pillar, among pillars: [Pillar]) -> CaptureIdeaPillarEntity {
        let context: String
        if let parentID = pillar.parentPillarID,
           let parent = pillars.first(where: { $0.id == parentID && !$0.isArchived }) {
            context = "Branch of \(parent.name)"
        } else {
            context = "Pillar"
        }
        return CaptureIdeaPillarEntity(
            id: pillar.id.uuidString,
            name: pillar.name,
            context: context
        )
    }

    private static func title(from idea: String) -> String {
        let words = idea
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(7)
            .joined(separator: " ")
        guard let first = words.first else { return "Untitled idea" }
        return String(first).uppercased() + words.dropFirst()
    }
}
