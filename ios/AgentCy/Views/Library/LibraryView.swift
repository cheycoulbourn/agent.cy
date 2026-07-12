import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]
    @State private var search = ""
    @State private var status: BriefStatus?

    private var filtered: [CreativeBrief] {
        briefs.filter { brief in
            (search.isEmpty || brief.title.localizedStandardContains(search) || brief.premise.localizedStandardContains(search)) &&
            (status == nil || brief.status == status)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(briefs.isEmpty ? "No briefs yet" : "No matches", systemImage: "books.vertical")
                } description: {
                    Text(briefs.isEmpty ? "Your saved ideas and videos will appear here." : "Try another search or filter.")
                }
            } else {
                List(filtered) { brief in
                    NavigationLink {
                        BriefDetailView(brief: brief)
                    } label: {
                        VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                            HStack {
                                Text(brief.title).font(.agentHeadline)
                                Spacer()
                                Image(systemName: brief.status.symbol).foregroundStyle(Color.actionAccent)
                            }
                            Text(brief.premise).font(.agentBody).foregroundStyle(Color.agentSecondary).lineLimit(2)
                            MetaLabel("\(brief.status.title) · \(brief.updatedAt.formatted(.relative(presentation: .named)))")
                        }
                        .padding(.vertical, AgentSpacing.x2)
                    }
                    .listRowBackground(Color.agentCanvas)
                    .listRowSeparatorTint(Color.agentBorder)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("All") { status = nil }
                    ForEach(BriefStatus.allCases) { item in
                        Button(item.title) { status = item }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .agentScreen()
    }
}
