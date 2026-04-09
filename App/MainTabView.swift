import SwiftUI

enum Tab: String, CaseIterable {
    case home
    case ideas
    case create
    case calendar
    case agent

    var title: String {
        switch self {
        case .home: "Home"
        case .ideas: "Ideas"
        case .create: "Create"
        case .calendar: "Calendar"
        case .agent: "Agent Cy"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .ideas: "lightbulb"
        case .create: "plus.circle.fill"
        case .calendar: "calendar"
        case .agent: "sparkles"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .ideas: "lightbulb.fill"
        case .create: "plus.circle.fill"
        case .calendar: "calendar"
        case .agent: "sparkles"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @State private var showCreateSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Group {
                    switch tab {
                    case .home:
                        DashboardView()
                    case .ideas:
                        IdeasView()
                    case .create:
                        Color.clear
                    case .calendar:
                        ContentCalendarView()
                    case .agent:
                        AgentChatView()
                    }
                }
                .tabItem {
                    Label(
                        tab.title,
                        systemImage: selectedTab == tab ? tab.selectedIcon : tab.icon
                    )
                }
                .tag(tab)
            }
        }
        .tint(.brandBlack)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .create {
                showCreateSheet = true
                selectedTab = .home
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            QuickCaptureView()
        }
    }
}

#Preview {
    MainTabView()
}
