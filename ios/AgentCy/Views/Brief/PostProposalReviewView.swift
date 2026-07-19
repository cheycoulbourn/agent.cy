import SwiftData
import SwiftUI

struct PostProposalReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let brief: CreativeBrief
    @State private var proposal: BriefProposal
    @State private var confirmDiscard = false
    @State private var showDetails = false
    @State private var showPlatforms = false
    @State private var showTasks = false
    private let revisionProposal: BriefRevisionProposal?

    private var contentFormat: ContentFormat {
        proposal.variants.contains { $0.platform == .youtubeVideo } ? .longForm : .shortForm
    }

    init(brief: CreativeBrief, initialProposal: BriefProposal) {
        self.brief = brief
        revisionProposal = nil
        _proposal = State(initialValue: initialProposal)
    }

    init(brief: CreativeBrief, revisionProposal: BriefRevisionProposal) {
        self.brief = brief
        self.revisionProposal = revisionProposal
        _proposal = State(initialValue: revisionProposal.edited)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    EditorialHeader(
                        kicker: revisionProposal == nil ? "Draft post" : "Post revision",
                        title: revisionProposal == nil ? "Review your post." : "Review the changes.",
                        subtitle: "Edit anything. Nothing changes until you accept."
                    )

                    if let revisionProposal {
                        CyCallout(heading: .madeThisForYou) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                MetaLabel("Changed · \(revisionProposal.requestedScope.title)")
                                Text(revisionProposal.explanation).font(.agentBody)
                            }
                        }
                    }

                    BriefField(label: "Post title", text: $proposal.draft.title)
                    AgentDurationPicker(seconds: $proposal.draft.durationSeconds, format: contentFormat)
                    BriefField(label: "Hook", text: $proposal.draft.spokenHook)

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Script (optional)")
                        ForEach(proposal.draft.scriptBeats.indices, id: \.self) { index in
                            AgentMultilineField(
                                label: "Beat \(index + 1)",
                                placeholder: "",
                                text: $proposal.draft.scriptBeats[index],
                                lineLimit: 2...8
                            )
                        }
                    }
                    BriefField(label: "Call to action", text: $proposal.draft.ctaIntent)

                    DisclosureGroup(isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            BriefField(label: "Premise", text: $proposal.draft.premise)
                            BriefField(label: "Audience", text: $proposal.draft.audience)
                            BriefField(label: "Goal", text: $proposal.draft.goal)
                            BriefField(label: "Takeaway", text: $proposal.draft.takeaway)
                            BriefField(label: "On-screen text", text: $proposal.draft.firstFrameText)
                            BriefField(label: "How to film", text: $proposal.draft.filmingGuidance)
                            BriefField(label: "How to edit", text: $proposal.draft.editingGuidance)
                        }
                        .padding(.top, AgentSpacing.x4)
                    } label: {
                        BriefDisclosureLabel(title: "Post details", detail: "Audience, filming, edit")
                    }

                    if !proposal.variants.isEmpty {
                        DisclosureGroup(isExpanded: $showPlatforms) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                                ForEach(proposal.variants.indices, id: \.self) { index in
                                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                        Text(proposal.variants[index].platform.title).font(.agentHeadline)
                                        BriefField(label: "Caption", text: $proposal.variants[index].caption)
                                        BriefField(label: "Platform title", text: $proposal.variants[index].titleOverride)
                                        BriefField(label: "Opening", text: $proposal.variants[index].openingAdjustment)
                                        BriefField(label: "Call to action", text: $proposal.variants[index].cta)
                                        BriefField(label: "Edit", text: $proposal.variants[index].editChanges)
                                    }
                                }
                            }
                            .padding(.top, AgentSpacing.x4)
                        } label: {
                            BriefDisclosureLabel(title: "Platforms", detail: "\(proposal.variants.count)")
                        }
                    }

                    if !proposal.tasks.isEmpty {
                        DisclosureGroup(isExpanded: $showTasks) {
                            VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                ForEach(proposal.tasks.indices, id: \.self) { index in
                                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                                        TextField("Task", text: $proposal.tasks[index].title)
                                            .agentSingleLineSubmit()
                                            .font(.agentBody)
                                        Picker("Kind", selection: $proposal.tasks[index].kind) {
                                            ForEach(CreatorTaskKind.allCases) { Text($0.title).tag($0) }
                                        }
                                        AgentMultilineField(
                                            label: "Notes",
                                            placeholder: "",
                                            text: $proposal.tasks[index].notes,
                                            lineLimit: 2...5
                                        )
                                        TextField("Minutes", value: estimatedMinutesBinding(index), format: .number)
                                            .agentSingleLineSubmit()
                                            .keyboardType(.numberPad)
                                        Toggle("Marks filming complete", isOn: recordingMilestoneBinding(index))
                                            .disabled(proposal.tasks[index].kind != .filming)
                                    }
                                    .padding(AgentSpacing.x4)
                                    .background(Color.agentSurface)
                                    .clipShape(.rect(cornerRadius: AgentRadius.control))
                                    .overlay(RoundedRectangle(cornerRadius: AgentRadius.control).stroke(Color.agentBorder, lineWidth: 1))
                                }
                            }
                            .padding(.top, AgentSpacing.x4)
                        } label: {
                            BriefDisclosureLabel(title: "Tasks", detail: "\(proposal.tasks.count)")
                        }
                    }

                    Button {
                        if var revisionProposal {
                            revisionProposal.edited = proposal
                            appModel.acceptRevision(revisionProposal, for: brief, context: context)
                        } else {
                            appModel.acceptProposal(proposal, for: brief, context: context)
                        }
                        dismiss()
                    } label: {
                        AgentIconLabel(
                            title: revisionProposal == nil ? "Use this post" : "Use these changes",
                            icon: .check
                        )
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())

                    Button(revisionProposal == nil ? "Discard post" : "Keep current post", role: revisionProposal == nil ? .destructive : nil) {
                        confirmDiscard = true
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(AgentSpacing.x6)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .alert("Discard this post?", isPresented: $confirmDiscard) {
                if revisionProposal == nil {
                    Button("Discard post", role: .destructive) {
                        appModel.discardProposal(for: brief, context: context)
                        dismiss()
                    }
                } else {
                    Button("Keep current post") {
                        appModel.discardRevision(for: brief, context: context)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .agentScreen()
        }
        .agentKeyboardDismissal()
    }

    private func estimatedMinutesBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { proposal.tasks[index].estimatedMinutes ?? 15 },
            set: { proposal.tasks[index].estimatedMinutes = max(5, min($0, 480)) }
        )
    }

    private func recordingMilestoneBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { proposal.tasks[index].isRecordingMilestone },
            set: { enabled in
                if enabled {
                    for taskIndex in proposal.tasks.indices {
                        proposal.tasks[taskIndex].isRecordingMilestone = false
                    }
                }
                proposal.tasks[index].isRecordingMilestone = enabled
            }
        )
    }
}
