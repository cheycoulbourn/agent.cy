import SwiftUI
import UIKit

struct AppShellView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var model = appModel
        TabView(selection: $model.selectedTab) {
            Tab(AppTab.today.title, systemImage: AppTab.today.symbol, value: AppTab.today) {
                NavigationStack { TodayView().rootActions() }
            }
            Tab(AppTab.agenda.title, systemImage: AppTab.agenda.symbol, value: AppTab.agenda) {
                NavigationStack { AgendaView().rootActions() }
            }
            Tab(AppTab.tasks.title, systemImage: AppTab.tasks.symbol, value: AppTab.tasks) {
                NavigationStack { TasksView().rootActions() }
            }
            Tab(AppTab.pillars.title, systemImage: AppTab.pillars.symbol, value: AppTab.pillars) {
                NavigationStack { PillarsView().rootActions() }
            }
            Tab(AppTab.spark.title, systemImage: AppTab.spark.symbol, value: AppTab.spark) {
                NavigationStack { SparkView().rootActions() }
            }
        }
        .tint(.actionAccent)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide keyboard") {
                    dismissKeyboard()
                }
                .fontWeight(.semibold)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isKeyboardVisible {
                Button {
                    appModel.presentedSheet = .askCy
                } label: {
                    Image(systemName: "apple.intelligence")
                }
                .buttonStyle(AgentCyFloatingButtonStyle())
                .padding(.trailing, AgentSpacing.x6)
                .padding(.bottom, 92)
                .accessibilityLabel("Ask Cy")
                .accessibilityHint("Opens your AI creative assistant")
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
            }
        }
        .sheet(item: $model.presentedSheet) { sheet in
            switch sheet {
            case .quickCapture: QuickCaptureView()
            case .askCy: AskCyView()
            case .settings: SettingsView()
            }
        }
        .alert("agent.cy", isPresented: Binding(
            get: { appModel.notice != nil },
            set: { if !$0 { appModel.notice = nil } }
        )) {
            Button("Close") { appModel.notice = nil }
        } message: {
            Text(appModel.notice?.message ?? "")
        }
        .agentScreen()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { isKeyboardVisible = false }
        }
        .task { await appModel.refreshAccess(context: modelContext) }
    }

    @Environment(\.modelContext) private var modelContext

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

#Preview("Loaded creator") {
    let container = PreviewData.makeContainer()
    AppShellView()
        .environment(AppModel(reminderService: PreviewReminderService(), credentialStore: PreviewCredentialStore()))
        .modelContainer(container)
}

private struct RootActionsModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appModel.presentedSheet = .settings
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Profile and settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        appModel.quickCaptureStartsWithIdeas = false
                        appModel.quickCaptureStartsWithTask = false
                        appModel.quickCaptureStartsWithPost = false
                        appModel.quickCaptureStartsRecording = false
                        appModel.quickCapturePillarID = nil
                        appModel.presentedSheet = .quickCapture
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Quick capture")
                }
            }
    }
}

private extension View {
    func rootActions() -> some View { modifier(RootActionsModifier()) }
}
