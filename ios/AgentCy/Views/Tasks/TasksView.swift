import SwiftData
import SwiftUI

struct TasksView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case open = "Open"
        case completed = "Completed"
        case all = "All"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CreatorTask.createdAt, order: .reverse) private var tasks: [CreatorTask]
    @State private var filter: Filter = .open

    private var filtered: [CreatorTask] {
        switch filter {
        case .open: tasks.filter { !$0.isCompleted }
        case .completed: tasks.filter(\.isCompleted)
        case .all: tasks
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Task filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AgentSpacing.x6)
            .padding(.vertical, AgentSpacing.x4)

            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(filter == .completed ? "Nothing completed yet" : "No tasks yet", systemImage: "checkmark.circle")
                } description: {
                    Text(filter == .completed ? "Completed tasks will appear here." : "Add one clear next step.")
                } actions: {
                    Button("Add a task") {
                        appModel.quickCaptureStartsWithTask = true
                        appModel.presentedSheet = .quickCapture
                    }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            } else {
                List {
                    ForEach(filtered) { task in
                        TaskRow(task: task)
                            .listRowBackground(Color.agentCanvas)
                            .listRowSeparatorTint(Color.agentBorder)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Tasks")
        .agentScreen()
    }
}

private struct TaskRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let task: CreatorTask

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            Button { appModel.toggleTask(task, context: context) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.agentSuccess : Color.agentSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")
            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(task.title)
                    .font(.agentBody)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.agentSecondary : Color.agentText)
                HStack {
                    Label(task.kind.title, systemImage: task.kind.symbol)
                    if let target = task.targetDate { Text("·"); Text(target, style: .relative) }
                }
                .font(.agentMono)
                .foregroundStyle(Color.agentSecondary)
            }
            Spacer()
            if !task.isCompleted {
                Menu {
                    ForEach(ReplanChoice.allCases) { choice in
                        Button(choice.title, role: choice == .archive ? .destructive : nil) {
                            appModel.replan(task: task, choice: choice, context: context)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Replan task")
            }
        }
        .padding(.vertical, AgentSpacing.x1)
    }
}
