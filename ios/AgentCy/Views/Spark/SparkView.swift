import SwiftData
import SwiftUI

struct SparkView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @Query(sort: \Pillar.createdAt) private var pillars: [Pillar]
    @Query(sort: \PlatformOutput.createdAt, order: .reverse) private var outputs: [PlatformOutput]
    @State private var search = ""
    @State private var status: BriefStatus?

    private var filteredBriefs: [CreativeBrief] {
        briefs.filter { brief in
            let matchesSearch = search.isEmpty ||
                brief.title.localizedStandardContains(search) ||
                brief.premise.localizedStandardContains(search) ||
                brief.notes.localizedStandardContains(search)
            return matchesSearch && (status == nil || brief.status == status)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: "Idea Bank",
                    title: "Let’s make something.",
                    subtitle: "Capture something new or ask Cy for three directions."
                )

                captureSection
                workSection
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Idea Bank")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search your work")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("All work") { status = nil }
                    ForEach(BriefStatus.allCases) { item in
                        Button(item.title) { status = item }
                    }
                } label: {
                    Label("Filter Your work", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .agentScreen()
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x3) {
            SectionRuleHeader(title: "Start")

            SparkActionButton(
                title: "Create",
                detail: "Write an idea, plan a post, or add a task.",
                symbol: "plus"
            ) {
                openCapture()
            }

            SparkActionButton(
                title: "Find three ideas",
                detail: "Get three directions grounded in your work.",
                symbol: "sparkles"
            ) {
                openCapture(ideas: true)
            }
        }
    }

    @ViewBuilder
    private var workSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(
                title: status.map { "Your work · \($0.title)" } ?? "Your work",
                trailing: "\(filteredBriefs.count)"
            )

            if filteredBriefs.isEmpty {
                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    Text(briefs.isEmpty ? "Your ideas and posts will appear here." : "No work matches this search.")
                        .font(.agentBody)
                        .foregroundStyle(Color.agentSecondary)
                    if !search.isEmpty || status != nil {
                        Button("Clear filters") {
                            search = ""
                            status = nil
                        }
                        .buttonStyle(AgentCompactSecondaryButtonStyle())
                    }
                }
                .padding(.vertical, AgentSpacing.x4)
            } else {
                ForEach(filteredBriefs) { brief in
                    NavigationLink {
                        if brief.status == .spark || brief.status == .developing {
                            IdeaPostDraftView(brief: brief)
                        } else if let output = outputs.first(where: {
                            $0.briefID == brief.id && PostOutputDetailPolicy.usesFinalizedView(
                                outputStatus: $0.status,
                                targetDate: $0.targetDate
                            )
                        }) {
                            PostOutputDetailView(brief: brief, output: output)
                        } else {
                            BriefDetailView(brief: brief)
                        }
                    } label: {
                        EditorialRow {
                            HStack(spacing: AgentSpacing.x3) {
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(brief.title)
                                        .font(.agentHeadline)
                                        .foregroundStyle(Color.agentText)
                                    if let pillarName = pillarName(for: brief) {
                                        Text(pillarName)
                                            .font(.agentSubtext)
                                            .foregroundStyle(Color.agentSecondary)
                                            .lineLimit(1)
                                    }
                                    MetaLabel("\(brief.status.title) · \(brief.updatedAt.formatted(.relative(presentation: .named)))")
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.agentSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openCapture(ideas: Bool = false) {
        appModel.quickCaptureTargetDate = nil
        appModel.quickCapturePillarID = nil
        appModel.quickCaptureStartsWithTask = false
        appModel.quickCaptureStartsWithPost = false
        appModel.quickCaptureStartsWithIdeas = ideas
        appModel.presentedSheet = .quickCapture
    }

    private func pillarName(for brief: CreativeBrief) -> String? {
        guard let pillarID = brief.pillarID,
              let pillar = pillars.first(where: { $0.id == pillarID && !$0.isArchived }) else {
            return nil
        }
        return pillar.name
    }
}

private struct SparkActionButton: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x4) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title).font(.agentHeadline)
                    Text(detail).font(.agentSubtext).foregroundStyle(Color.agentSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(Color.agentSecondary)
            }
            .foregroundStyle(Color.agentText)
            .padding(AgentSpacing.x4)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: AgentRadius.panel).stroke(Color.agentBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}
