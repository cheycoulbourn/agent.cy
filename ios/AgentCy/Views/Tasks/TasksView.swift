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
        let topLevel = tasks.filter { $0.parentTaskID == nil }
        switch filter {
        case .open: return topLevel.filter { !$0.isCompleted }
        case .completed: return topLevel.filter(\.isCompleted)
        case .all: return topLevel
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
                        appModel.quickCaptureStartsWithPost = false
                        appModel.quickCaptureStartsRecording = false
                        appModel.quickCapturePillarID = nil
                        appModel.presentedSheet = .quickCapture
                    }
                        .buttonStyle(AgentCompactPrimaryButtonStyle())
                }
            } else {
                List {
                    ForEach(filtered) { task in
                        TaskRow(task: task, allTasks: tasks)
                            .listRowBackground(Color.agentCanvas)
                            .listRowSeparatorTint(Color.agentBorder)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    appModel.deleteTask(task, context: context)
                                }
                            }
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

struct TaskRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    let task: CreatorTask
    let allTasks: [CreatorTask]

    private var subtasks: [CreatorTask] { allTasks.filter { $0.parentTaskID == task.id } }
    private var completedSubtasks: Int { subtasks.filter(\.isCompleted).count }

    var body: some View {
        HStack(alignment: .center, spacing: AgentSpacing.x3) {
            Button { appModel.toggleTask(task, context: context) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.agentSuccess : Color.agentSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                    Label(task.kind.title, systemImage: task.kind.symbol)
                        .font(.agentMono)
                        .foregroundStyle(Color.agentSecondary)
                    Text(task.title)
                        .font(.agentHeadline)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? Color.agentSecondary : Color.agentText)

                    HStack(alignment: .top, spacing: AgentSpacing.x2) {
                        TaskAttribute(title: "Status", value: task.isCompleted ? "Done" : "Open")
                        TaskAttribute(title: "Date", value: dateText)
                        TaskAttribute(
                            title: "Priority",
                            value: task.priority.title,
                            valueColor: priorityColor
                        )
                    }

                    if !subtasks.isEmpty {
                        Text("\(completedSubtasks) of \(subtasks.count) steps")
                            .font(.agentMono)
                            .foregroundStyle(Color.agentSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
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
        .padding(.vertical, AgentSpacing.x2)
    }

    private var dateText: String {
        guard let targetDate = task.targetDate else { return "None" }
        if Calendar.current.isDateInToday(targetDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(targetDate) { return "Tomorrow" }
        return targetDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: Color.agentSecondary
        case .medium: Color.agentText
        case .high: Color.actionAccent
        }
    }
}

private struct TaskAttribute: View {
    let title: String
    let value: String
    var valueColor: Color = .agentText

    var body: some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            Text(title.uppercased())
                .font(.agentMono)
                .foregroundStyle(Color.agentSecondary)
            Text(value)
                .font(.agentBody)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TaskDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: CreatorTask
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query private var briefs: [CreativeBrief]
    @State private var showAddSubtask = false
    @State private var confirmDelete = false

    private var subtasks: [CreatorTask] {
        allTasks.filter { $0.parentTaskID == task.id }.sorted {
            if $0.sortOrder == $1.sortOrder { return $0.createdAt < $1.createdAt }
            return $0.sortOrder < $1.sortOrder
        }
    }
    private var completedCount: Int { subtasks.filter(\.isCompleted).count }
    private var linkedBrief: CreativeBrief? { task.briefID.flatMap { id in briefs.first { $0.id == id } } }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Next action", text: $task.title, axis: .vertical)
                Picker("Kind", selection: Binding(get: { task.kind }, set: { task.kind = $0 })) {
                    ForEach(CreatorTaskKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                Picker("Priority", selection: Binding(get: { task.priority }, set: { task.priority = $0 })) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                TextField("Notes", text: $task.notes, axis: .vertical)
            }

            Section("Timing") {
                Toggle("Add a flexible target", isOn: hasTarget)
                    .tint(.actionAccent)
                if task.targetDate != nil {
                    DatePicker("Target", selection: targetDate, displayedComponents: [.date, .hourAndMinute])
                }
                Stepper("Estimate: \(task.estimatedMinutes ?? 15) min", value: estimate, in: 5...480, step: 5)
            }

            if let linkedBrief {
                Section("Content") {
                    NavigationLink(linkedBrief.title) { BriefDetailView(brief: linkedBrief) }
                }
            }

            Section {
                if subtasks.isEmpty {
                    Text("Break this task into small, independently completable steps.")
                        .foregroundStyle(Color.agentSecondary)
                } else {
                    ProgressView(value: Double(completedCount), total: Double(subtasks.count)) {
                        Text("\(completedCount) of \(subtasks.count) complete")
                    }
                    .tint(.actionAccent)
                    ForEach(subtasks) { subtask in
                        HStack(spacing: AgentSpacing.x3) {
                            Button { appModel.toggleTask(subtask, context: context) } label: {
                                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(subtask.isCompleted ? Color.agentSuccess : Color.agentSecondary)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            TextField("Subtask", text: Bindable(subtask).title)
                                .strikethrough(subtask.isCompleted)
                        }
                    }
                }
                Button("Add a subtask", systemImage: "plus") { showAddSubtask = true }
            } header: {
                Text("Subtasks")
            }

            Section {
                Button(task.isCompleted ? "Mark task open" : "Complete task", systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle") {
                    appModel.toggleTask(task, context: context)
                }
                Button("Delete task", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
        .sheet(isPresented: $showAddSubtask) {
            NewSubtaskView(parent: task)
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                appModel.deleteTask(task, context: context)
                dismiss()
            }
        } message: {
            Text("Its subtasks will also be deleted.")
        }
        .agentScreen()
    }

    private var hasTarget: Binding<Bool> {
        Binding(
            get: { task.targetDate != nil },
            set: { task.targetDate = $0 ? (task.targetDate ?? Date()) : nil }
        )
    }

    private var targetDate: Binding<Date> {
        Binding(get: { task.targetDate ?? Date() }, set: { task.targetDate = $0 })
    }

    private var estimate: Binding<Int> {
        Binding(get: { task.estimatedMinutes ?? 15 }, set: { task.estimatedMinutes = $0 })
    }
}

private struct NewSubtaskView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let parent: CreatorTask
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Subtask") {
                    TextField("Small next step", text: $title, axis: .vertical)
                }
            }
            .navigationTitle("New subtask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        if appModel.createSubtask(title: title, parent: parent, context: context) != nil { dismiss() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
