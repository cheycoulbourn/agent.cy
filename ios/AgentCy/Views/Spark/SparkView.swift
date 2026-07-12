import SwiftData
import SwiftUI

struct SparkView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
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
                    kicker: "Spark",
                    title: "Make something.",
                    subtitle: "Start with an idea, a post, or three directions from Cy."
                )

                captureSection
                workSection
            }
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x16)
        }
        .navigationTitle("Spark")
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
                title: "New idea",
                detail: "Type or shape a rough thought.",
                symbol: "lightbulb"
            ) {
                openCapture()
            }

            SparkActionButton(
                title: "New post",
                detail: "Plan a title, platform, and posting day.",
                symbol: "calendar.badge.plus"
            ) {
                openCapture(post: true)
            }

            SparkActionButton(
                title: "Find three angles",
                detail: "Get three directions grounded in your work.",
                symbol: "sparkles"
            ) {
                openCapture(ideas: true)
            }

            SparkActionButton(
                title: "Record an idea",
                detail: "Capture your words on-device.",
                symbol: "mic"
            ) {
                openCapture(recording: true)
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
                        BriefDetailView(brief: brief)
                    } label: {
                        EditorialRow {
                            HStack(spacing: AgentSpacing.x3) {
                                Image(systemName: brief.status.symbol)
                                    .foregroundStyle(Color.actionAccent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(brief.title)
                                        .font(.agentHeadline)
                                        .foregroundStyle(Color.agentText)
                                    if !brief.premise.isEmpty {
                                        Text(brief.premise)
                                            .font(.agentSubtext)
                                            .foregroundStyle(Color.agentSecondary)
                                            .lineLimit(2)
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

    private func openCapture(post: Bool = false, ideas: Bool = false, recording: Bool = false) {
        appModel.quickCaptureTargetDate = nil
        appModel.quickCaptureStartsWithTask = false
        appModel.quickCaptureStartsWithPost = post
        appModel.quickCaptureStartsWithIdeas = ideas
        appModel.quickCaptureStartsRecording = recording
        appModel.presentedSheet = .quickCapture
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
