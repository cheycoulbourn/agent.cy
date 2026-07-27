import Foundation
import SwiftData

struct BrandImportSuggestion: Identifiable, Equatable {
    let id: String
    let name: String
    let stage: BrandPartnerStage
    let briefIDs: [UUID]
}

enum BrandPartnershipService {
    static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func importSuggestions(
        briefs: [CreativeBrief],
        outputs: [PlatformOutput],
        existingPartners: [BrandPartner],
        workspaceID: UUID?
    ) -> [BrandImportSuggestion] {
        let existingNames = Set(existingPartners.map { normalizedName($0.name) })
        let scopedBriefs = briefs.filter {
            ($0.workspaceID == workspaceID || $0.workspaceID == nil)
                && $0.isBrandCollaboration
                && !$0.brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let scopedOutputs = outputs.filter { $0.workspaceID == workspaceID || $0.workspaceID == nil }
        let outputsByBrief = Dictionary(grouping: scopedOutputs, by: \.briefID)
        let grouped = Dictionary(grouping: scopedBriefs) { normalizedName($0.brandName) }

        return grouped.compactMap { key, matchingBriefs in
            guard !key.isEmpty, !existingNames.contains(key), let first = matchingBriefs.first else { return nil }
            let matchingOutputs = matchingBriefs.flatMap { outputsByBrief[$0.id] ?? [] }
            let stage: BrandPartnerStage
            if matchingBriefs.contains(where: { [.developing, .ready, .scheduled].contains($0.status) })
                || matchingOutputs.contains(where: { [.ready, .scheduled].contains($0.status) }) {
                stage = .workingTogether
            } else if matchingBriefs.allSatisfy({ $0.status == .posted || $0.status == .archived })
                || matchingOutputs.contains(where: { $0.status == .posted }) {
                stage = .pastPartner
            } else {
                stage = .talking
            }
            return BrandImportSuggestion(
                id: key,
                name: first.brandName.trimmingCharacters(in: .whitespacesAndNewlines),
                stage: stage,
                briefIDs: matchingBriefs.map(\.id)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func importSuggestion(
        _ suggestion: BrandImportSuggestion,
        workspaceID: UUID?,
        briefs: [CreativeBrief],
        context: ModelContext
    ) -> BrandPartner {
        let partner = BrandPartner(
            workspaceID: workspaceID,
            name: suggestion.name,
            stage: suggestion.stage
        )
        context.insert(partner)
        let briefIDs = Set(suggestion.briefIDs)
        for brief in briefs where briefIDs.contains(brief.id) {
            brief.brandPartnerID = partner.id
            brief.brandName = partner.name
            brief.isBrandCollaboration = true
            brief.updatedAt = Date()
        }
        return partner
    }

    @MainActor
    static func reconcileFollowUpTask(
        for partner: BrandPartner,
        tasks: [CreatorTask],
        context: ModelContext
    ) {
        let openTasks = tasks
            .filter {
                $0.brandPartnerID == partner.id
                    && $0.briefID == nil
                    && $0.platformOutputID == nil
                    && !$0.isCompleted
                    && !$0.isSkipped
            }
            .sorted { $0.createdAt < $1.createdAt }

        guard let followUp = partner.nextFollowUpAt else {
            openTasks.forEach(context.delete)
            return
        }

        let title = "Follow up with \(partner.name)"
        if let first = openTasks.first {
            first.title = title
            first.targetDate = followUp
            first.includesTargetTime = false
            first.kind = .creatorBusiness
            first.priority = .none
            first.workspaceID = partner.workspaceID
            first.brandPartnerID = partner.id
            openTasks.dropFirst().forEach(context.delete)
        } else {
            let task = CreatorTask(
                title: title,
                kind: .creatorBusiness,
                priority: .none,
                targetDate: followUp,
                includesTargetTime: false
            )
            task.workspaceID = partner.workspaceID
            task.brandPartnerID = partner.id
            context.insert(task)
        }
    }
}
