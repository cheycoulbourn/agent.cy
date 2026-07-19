import SwiftData
import SwiftUI

struct IdeaPostDraftView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let brief: CreativeBrief
    let preferredOutput: PlatformOutput?
    let suggestedTargetDate: Date?
    @Query private var outputs: [PlatformOutput]
    @State private var createdOutput: PlatformOutput?
    @State private var showDevelopment = false
    @State private var creationFailed = false

    init(brief: CreativeBrief, output: PlatformOutput? = nil, suggestedTargetDate: Date? = nil) {
        self.brief = brief
        preferredOutput = output
        self.suggestedTargetDate = suggestedTargetDate
        let briefID = brief.id
        _outputs = Query(
            filter: #Predicate<PlatformOutput> { $0.briefID == briefID },
            sort: \PlatformOutput.createdAt
        )
    }

    private var draftOutput: PlatformOutput? {
        preferredOutput
            ?? outputs.first(where: {
                PostDraftResumePolicy.shouldResume(
                    briefStatus: brief.status,
                    outputStatus: $0.status
                )
            })
            ?? outputs.first
            ?? createdOutput
    }

    var body: some View {
        Group {
            if let draftOutput {
                ResumablePostEditorView(
                    brief: brief,
                    output: draftOutput,
                    suggestedTargetDate: suggestedTargetDate,
                    isAlreadyInIdeaBank: true,
                    onSpark: { showDevelopment = true }
                )
            } else if creationFailed {
                ScrollView {
                    VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                        Text("Couldn’t open this idea.")
                            .font(.agentHeadline)
                        Button("Try again") { createDraft() }
                            .buttonStyle(AgentSecondaryButtonStyle())
                    }
                    .padding(AgentLayout.pageMargin)
                }
            } else {
                ProgressView("Opening your draft…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle(brief.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard draftOutput == nil else { return }
            createDraft()
        }
        .sheet(isPresented: $showDevelopment) {
            DevelopBriefView(brief: brief, output: draftOutput)
        }
        .agentScreen()
    }

    private func createDraft() {
        creationFailed = false
        createdOutput = appModel.ensurePostDraft(for: brief, context: context)
        creationFailed = createdOutput == nil
    }
}
