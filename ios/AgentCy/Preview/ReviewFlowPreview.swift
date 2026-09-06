#if DEBUG
import SwiftData
import SwiftUI

/// In-memory review routes for repeatable UI checks without a bridge account.
struct ReviewFlowPreview: View {
    @Environment(\.modelContext) private var context
    @State private var brief: CreativeBrief?
    @State private var request: MCPBridgeChangeRequest?
    @State private var showsDevelopment = true
    @State private var approvedBrief: CreativeBrief?
    @State private var approvedOutput: PlatformOutput?
    let showsEpisode: Bool

    var body: some View {
        NavigationStack {
            if let approvedBrief, let approvedOutput {
                ResumablePostEditorView(brief: approvedBrief, output: approvedOutput, onSpark: {})
            } else if showsEpisode, let request {
                #if targetEnvironment(macCatalyst)
                MCPDesktopReviewView(requests: [request], onClose: {}, onQueueChanged: {}, approveRequests: approvePreview)
                    .frame(minWidth: 960, minHeight: 640)
                #else
                MCPBridgeRequestReviewView(request: request, approve: { try approvePreview([$0], context) }, decline: { _, _ in })
                #endif
            } else if let brief {
                VStack(spacing: AgentSpacing.x4) {
                    Text(brief.title).font(.agentTitle)
                    Button("Open post review") { showsDevelopment = true }
                        .buttonStyle(AgentQuietSecondaryButtonStyle())
                }
                .sheet(isPresented: $showsDevelopment) {
                    DevelopBriefView(brief: brief)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard brief == nil else { return }
            let record = CreativeBrief(title: "Review fixture post", premise: "Original post remains unchanged")
            context.insert(record)
            let proposal = Self.proposal(for: record)
            context.insert(PendingBriefProposal(briefID: record.id, payloadJSON: String(decoding: try! JSONEncoder().encode(proposal), as: UTF8.self)))
            let pillar = try? context.fetch(FetchDescriptor<Pillar>()).first
            let series = ContentSeries(name: "Review fixture series", pillarID: pillar?.id)
            let workspaces = (try? context.fetch(FetchDescriptor<CreatorWorkspace>())) ?? []
            let workspaceID = WorkspaceScope.activeWorkspaceID(
                preferredID: CreatorWorkspacePreferences.activeWorkspaceID,
                workspaces: workspaces
            )
            series.workspaceID = workspaceID
            context.insert(series)
            request = MCPBridgeChangeRequest(
                schemaVersion: 1, id: UUID(), createdAt: Date(), source: "preview", workspaceId: workspaceID,
                type: "createSeriesEpisode",
                payload: MCPBridgeRequestPayload(title: "Review fixture episode", premise: "A clear episode premise", notes: "Original notes", pillarId: pillar?.id, platform: CreatorPlatform.instagramReels.rawValue, hook: "Original hook", caption: "Original caption", callToAction: "Original call to action", targetDate: Date().addingTimeInterval(172_800), seriesId: series.id, episodeNumber: 1, workDate: Date().addingTimeInterval(86_400))
            )
            try? context.save()
            brief = record
        }
    }

    /// Exercises the real request application against this fixture's in-memory
    /// store, without accepting a live bridge file or exporting widget data.
    private func approvePreview(_ requests: [MCPBridgeChangeRequest], _ context: ModelContext) throws {
        for request in requests { try MCPBridgeService.apply(request, context: context) }
        try context.save()
        let seriesID = request?.payload.seriesId
        approvedBrief = try context.fetch(FetchDescriptor<CreativeBrief>()).first { $0.seriesID == seriesID }
        let briefID = approvedBrief?.id
        approvedOutput = try context.fetch(FetchDescriptor<PlatformOutput>()).first { $0.briefID == briefID }
    }

    static func proposal(for brief: CreativeBrief) -> BriefProposal {
        BriefProposal(briefID: brief.id, draft: BriefDraft(
            title: "Proposed post title", premise: "A proposed premise", audience: "Creators",
            goal: "Make the next step clear", takeaway: "Start smaller", durationSeconds: 45,
            spokenHook: "Start here.", firstFrameText: "START HERE", scriptBeats: ["Name the friction"],
            close: "Take one step.", ctaIntent: "Save this", filmingGuidance: "Face camera",
            editingGuidance: "Keep it light", assumptions: [], voiceConfidence: 0.8
        ), variants: [], tasks: [])
    }
}
#endif
