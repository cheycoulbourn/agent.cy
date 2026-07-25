import SwiftData
import SwiftUI

struct WeeklyFocusSetupView: View {
    private struct DraftSnapshot: Equatable {
        let assignments: [[DailyFocusKind]]
        let taskTemplates: [[DailyFocusTaskTemplateDefinition]]
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTemplates: [DailyFocusTemplateEntry]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var assignments: [PillarWeekday: [DailyFocusKind]] = [:]
    @State private var taskTemplates: [PillarWeekday: [DailyFocusTaskTemplateDefinition]] = [:]
    @State private var didLoad = false
    @State private var savedSnapshot: DraftSnapshot?

    private var templates: [DailyFocusTemplateEntry] {
        allTemplates.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: "Weekly focus",
                        title: "Batch your week.",
                        subtitle: "Choose up to two focuses per day. Unassigned days are Rest."
                    )

                    AgentInsetSurface {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                MetaLabel("Repeats every week")
                                Spacer()
                                MetaLabel("Up to 2 per day")
                            }
                            .padding(.bottom, AgentSpacing.x4)

                            ForEach(Array(PillarWeekday.mondayFirst.enumerated()), id: \.element) { index, day in
                                NavigationLink {
                                    WeeklyFocusDaySelectionView(
                                        day: day,
                                        selection: assignmentBinding(for: day),
                                        taskTemplates: taskTemplateBinding(for: day),
                                        saveChanges: persistChanges
                                    )
                                } label: {
                                    HStack(spacing: AgentSpacing.x4) {
                                        Text(day.letter)
                                            .font(.agentMetadata)
                                            .frame(width: 28, height: 28)
                                            .background(Color.agentCanvas, in: .circle)

                                        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                            Text(day.title)
                                                .font(.agentBody.weight(.semibold))
                                            Text(DailyFocusKind.combinedTitle(assignments[day] ?? []))
                                                .font(.agentSubtext)
                                                .foregroundStyle(Color.agentSecondary)
                                        }

                                        Spacer()
                                        AgentIconView(.forward, size: 14)
                                    }
                                    .foregroundStyle(Color.agentText)
                                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .top) {
                                    if index > 0 {
                                        Rectangle().fill(Color.agentHairline).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }

                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Weekly focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
                if hasChanges {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: saveAndDismiss) {
                            AgentIconView(.check, size: 15)
                                .foregroundStyle(Color.agentPureBlack)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(Color.agentPureWhite)
                        .accessibilityLabel("Save weekly focus")
                        .accessibilityHint("Saves your weekly focuses and recurring tasks")
                    }
                }
            }
            .onAppear(perform: load)
            .agentScreen()
        }
        .agentKeyboardDismissal()
    }

    private func assignmentBinding(for day: PillarWeekday) -> Binding<[DailyFocusKind]> {
        Binding(
            get: { assignments[day] ?? [] },
            set: { assignments[day] = Array($0.prefix(2)) }
        )
    }

    private func taskTemplateBinding(
        for day: PillarWeekday
    ) -> Binding<[DailyFocusTaskTemplateDefinition]> {
        Binding(
            get: { taskTemplates[day] ?? [] },
            set: { taskTemplates[day] = $0 }
        )
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        for day in PillarWeekday.mondayFirst {
            guard let template = templates.first(where: { $0.weekday == day && $0.isActive }) else {
                assignments[day] = []
                continue
            }
            assignments[day] = DailyFocusResolver.normalizedKinds(
                primary: template.kind,
                secondary: template.secondaryKind,
                storedTitle: template.title
            )
            taskTemplates[day] = template.hasConfiguredFocusTasks
                ? template.focusTaskTemplates
                : DailyFocusTaskDefaults.definitions(for: assignments[day] ?? [])
        }
        savedSnapshot = currentSnapshot
    }

    private var currentSnapshot: DraftSnapshot {
        DraftSnapshot(
            assignments: PillarWeekday.mondayFirst.map { Array((assignments[$0] ?? []).prefix(2)) },
            taskTemplates: PillarWeekday.mondayFirst.map { taskTemplates[$0] ?? [] }
        )
    }

    private var hasChanges: Bool {
        guard didLoad, let savedSnapshot else { return false }
        return currentSnapshot != savedSnapshot
    }

    private func saveAndDismiss() {
        if persistChanges() {
            dismiss()
        }
    }

    @discardableResult
    private func persistChanges() -> Bool {
        let saved = appModel.saveWeeklyFocus(
            assignments,
            taskTemplates: taskTemplates,
            context: context
        )
        if saved {
            savedSnapshot = currentSnapshot
        }
        return saved
    }
}

private struct WeeklyFocusDaySelectionView: View {
    let day: PillarWeekday
    @Binding var selection: [DailyFocusKind]
    @Binding var taskTemplates: [DailyFocusTaskTemplateDefinition]
    let saveChanges: () -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: day.title,
                    title: selection.isEmpty ? "Rest." : DailyFocusKind.combinedTitle(selection) + ".",
                    subtitle: "Choose up to two kinds of work for \(day.title)s."
                )

                VStack(alignment: .leading, spacing: 0) {
                    focusRow(
                        title: "Rest",
                        directive: DailyFocusKind.combinedDirective([]),
                        isSelected: selection.isEmpty,
                        showsDivider: false
                    ) {
                        selection = []
                        taskTemplates = []
                    }

                    ForEach(DailyFocusKind.selectableCases) { kind in
                        focusRow(
                            title: kind.title,
                            directive: kind.directive,
                            isSelected: selection.contains(kind),
                            showsDivider: true
                        ) {
                            toggle(kind)
                        }
                        .disabled(!selection.contains(kind) && selection.count == 2)
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel)

                if selection.count == 2 {
                    Text("Two focuses selected. Remove one to choose another.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                    if selection.isEmpty {
                        Button("Set \(day.title) to Rest") {
                            if saveChanges() { dismiss() }
                        }
                            .buttonStyle(AgentPrimaryButtonStyle())
                    } else {
                        NavigationLink {
                            WeeklyFocusTaskTemplateEditor(
                                day: day,
                                focusKinds: selection,
                                taskTemplates: $taskTemplates,
                                saveChanges: saveChanges,
                                finishDay: { dismiss() }
                            )
                        } label: {
                            AgentIconLabel(title: "Next: recurring tasks", icon: .arrowRight)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AgentPrimaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x12)
        }
        .navigationTitle(day.title)
        .navigationBarTitleDisplayMode(.inline)
        .agentScreen()
    }

    private func focusRow(
        title: String,
        directive: String,
        isSelected: Bool,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title)
                        .font(.agentBody.weight(.semibold))
                    Text(directive)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSelected {
                    AgentIconView(.check, size: 14)
                        .frame(width: 24, height: 24)
                        .padding(.trailing, AgentSpacing.x1)
                }
            }
            .foregroundStyle(Color.agentText)
            .padding(.vertical, AgentSpacing.x3)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ kind: DailyFocusKind) {
        if let index = selection.firstIndex(of: kind) {
            selection.remove(at: index)
            taskTemplates.removeAll { $0.focusKind == kind }
        } else if selection.count < 2 {
            selection.append(kind)
            taskTemplates = DailyFocusTaskDefaults.addingDefaults(for: kind, to: taskTemplates)
        }
    }
}

private struct WeeklyFocusTaskTemplateEditor: View {
    let day: PillarWeekday
    let focusKinds: [DailyFocusKind]
    @Binding var taskTemplates: [DailyFocusTaskTemplateDefinition]
    let saveChanges: () -> Bool
    let finishDay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: "Repeats every \(day.title)",
                    title: "Set the next steps.",
                    subtitle: "These tasks repeat every week."
                )

                ForEach(focusKinds) { kind in
                    AgentInsetSurface {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                MetaLabel(kind.title)
                                Spacer()
                                let count = definitions(for: kind).count
                                MetaLabel("\(count) \(count == 1 ? "task" : "tasks")")
                            }
                            .padding(.bottom, AgentSpacing.x3)

                            ForEach(definitions(for: kind)) { definition in
                                if let binding = binding(for: definition.id) {
                                    focusTaskRow(binding)
                                }
                            }

                            AgentAddActionRow(title: "Add task") {
                                addTask(for: kind)
                            }
                            .padding(.top, AgentSpacing.x2)
                        }
                    }
                }

                Button("Save \(day.title)") {
                    taskTemplates.removeAll {
                        $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    guard saveChanges() else { return }
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        finishDay()
                    }
                }
                .buttonStyle(AgentPrimaryButtonStyle())
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, AgentSpacing.x12)
        }
        .navigationTitle("Recurring tasks")
        .navigationBarTitleDisplayMode(.inline)
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private func definitions(for kind: DailyFocusKind) -> [DailyFocusTaskTemplateDefinition] {
        taskTemplates
            .filter { $0.focusKind == kind }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func binding(
        for id: UUID
    ) -> Binding<DailyFocusTaskTemplateDefinition>? {
        guard let index = taskTemplates.firstIndex(where: { $0.id == id }) else { return nil }
        return $taskTemplates[index]
    }

    private func focusTaskRow(
        _ definition: Binding<DailyFocusTaskTemplateDefinition>
    ) -> some View {
        HStack(spacing: AgentSpacing.x3) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(priorityColor(definition.wrappedValue.priority), lineWidth: 1.25)
                .frame(width: 19, height: 19)

            TextField("", text: definition.title, axis: .vertical)
                .font(.agentBody)
                .lineLimit(1...2)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

            Menu {
                ForEach(TaskPriority.selectableCases) { priority in
                    Button(priority.title) {
                        definition.wrappedValue.priority = priority
                    }
                }
                Divider()
                Button("Remove task", role: .destructive) {
                    taskTemplates.removeAll { $0.id == definition.wrappedValue.id }
                }
            } label: {
                AgentIconView(.more, size: 14)
                    .foregroundStyle(Color.agentText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Task options")
        }
        .padding(.vertical, AgentSpacing.x1)
    }

    private func addTask(for kind: DailyFocusKind) {
        let nextOrder = (definitions(for: kind).map(\.sortOrder).max() ?? -1) + 1
        taskTemplates.append(DailyFocusTaskTemplateDefinition(
            focusKind: kind,
            title: "",
            sortOrder: nextOrder
        ))
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority.normalized {
        case .urgent: Color.agentDestructive
        case .high: Color.agentPriorityHigh
        default: Color.agentBorder
        }
    }
}

struct DailyFocusDetailView: View {
    let date: Date

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var allTemplates: [DailyFocusTemplateEntry]
    @Query private var allOverrides: [DailyFocusOverride]
    @Query(sort: \CreatorTask.createdAt) private var allTasks: [CreatorTask]
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var allBriefs: [CreativeBrief]
    @Query(sort: \PlatformOutput.createdAt) private var allOutputs: [PlatformOutput]
    @Query private var allSavedDetails: [DailyFocusDayDetail]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var detailRecord: DailyFocusDayDetail?
    @State private var note = ""
    @State private var reminderEnabled = false
    @State private var reminderDate = Date()
    @State private var didLoad = false

    private var templates: [DailyFocusTemplateEntry] { scoped(allTemplates) }
    private var overrides: [DailyFocusOverride] { scoped(allOverrides) }
    private var tasks: [CreatorTask] { scoped(allTasks) }
    private var briefs: [CreativeBrief] { scoped(allBriefs) }
    private var outputs: [PlatformOutput] { scoped(allOutputs) }
    private var savedDetails: [DailyFocusDayDetail] { scoped(allSavedDetails) }
    private func scoped<T: WorkspaceScopedRecord>(_ values: [T]) -> [T] {
        values.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    @State private var showFocusEditor = false

    private var focus: ResolvedDailyFocus? {
        DailyFocusResolver.resolve(date: date, templates: templates, overrides: overrides)
    }

    private var title: String { focus?.title ?? "Rest" }
    private var directive: String {
        focus?.note.isEmpty == false
            ? (focus?.note ?? "")
            : DailyFocusKind.combinedDirective(focus?.kinds ?? [])
    }
    private var activeBriefs: [CreativeBrief] { briefs.filter { $0.status != .archived } }
    private var activeBriefIDs: Set<UUID> { Set(activeBriefs.map(\.id)) }
    private var dayOutputs: [PlatformOutput] {
        outputs.filter {
            activeBriefIDs.contains($0.briefID) &&
                $0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true
        }
    }
    private var dayTasks: [CreatorTask] {
        tasks
            .filter {
                $0.parentTaskID == nil &&
                    !$0.isSkipped &&
                    AgendaContentVisibility.includesTask(
                        briefID: $0.briefID,
                        activeBriefIDs: activeBriefIDs
                    ) &&
                    taskBelongsToDay($0)
            }
            .sorted(by: sortTasks)
    }
    private var myTasks: [CreatorTask] {
        dayTasks.filter {
            TaskCollectionPolicy.collection(
                briefID: $0.briefID,
                platformOutputID: $0.platformOutputID
            ) == .myTasks
        }
    }
    private var reminderIsAvailable: Bool {
        Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
                    title: title + ".",
                    subtitle: "Your focus for this day."
                )

                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Plan")
                        Text(directive)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if focus?.durationMinutes != nil || focus?.time != nil {
                        Rectangle()
                            .fill(Color.agentHairline)
                            .frame(height: 1)

                        HStack(spacing: AgentSpacing.x8) {
                            if let duration = focus?.durationMinutes {
                                detailValue(label: "Duration", value: "\(duration) min")
                            }
                            if let time = focus?.time {
                                detailValue(
                                    label: "Starts",
                                    value: time.formatted(date: .omitted, time: .shortened)
                                )
                            }
                        }
                    }

                    Rectangle().fill(Color.agentHairline).frame(height: 1)

                    AgentMultilineField(
                        label: "Notes",
                        placeholder: "",
                        text: $note,
                        lineLimit: 2...5
                    )

                    Rectangle().fill(Color.agentHairline).frame(height: 1)

                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        Toggle("Reminder", isOn: $reminderEnabled)
                            .font(.agentBody.weight(.semibold))
                            .tint(.actionAccent)
                            .disabled(!reminderIsAvailable)

                        if reminderEnabled {
                            DatePicker(
                                "Time",
                                selection: $reminderDate,
                                displayedComponents: .hourAndMinute
                            )
                            .font(.agentSubtext)
                        } else if !reminderIsAvailable {
                            Text("Reminders are available for today and upcoming days.")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                        }
                    }

                    MetaLabel("Changes save automatically")
                }
                .padding(AgentSpacing.x6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel)

                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    focusTaskCollection(
                        title: TaskCollection.myTasks.title,
                        tasks: myTasks,
                        emptyMessage: "No tasks planned."
                    )

                    AgentAddActionRow(title: "Add task", action: addFocusTask)
                }
                .padding(AgentSpacing.x6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                .agentSurfaceChrome(cornerRadius: AgentRadius.panel)
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .agentBottomNavigationClearance()
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showFocusEditor = true }
            }
        }
        .sheet(isPresented: $showFocusEditor) {
            DailyFocusEditorView(date: date)
        }
        .onAppear(perform: loadDetails)
        .onChange(of: note) { _, _ in persistDetails(scheduleReminder: false) }
        .onChange(of: reminderEnabled) { _, _ in persistDetails(scheduleReminder: true) }
        .onChange(of: reminderDate) { _, _ in persistDetails(scheduleReminder: reminderEnabled) }
        .onDisappear { persistDetails(scheduleReminder: reminderEnabled) }
        .agentScreen()
        .agentKeyboardDismissal()
    }

    private func detailValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AgentSpacing.x1) {
            MetaLabel(label)
            Text(value)
                .font(.agentSubtext.weight(.semibold))
                .foregroundStyle(Color.agentText)
        }
    }

    @ViewBuilder
    private func focusTaskCollection(
        title: String,
        tasks collectionTasks: [CreatorTask],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MetaLabel(title)
                Spacer()
                MetaLabel("\(collectionTasks.filter(\.isCompleted).count) of \(collectionTasks.count)")
            }
            .padding(.bottom, AgentSpacing.x3)

            if collectionTasks.isEmpty {
                Text(emptyMessage)
                    .font(.agentSubtext)
                    .foregroundStyle(Color.agentSecondary)
                    .padding(.vertical, AgentSpacing.x3)
            } else {
                let groups = dueDateGroups(for: collectionTasks)
                if groups.count > 1 {
                    ForEach(groups) { group in
                        taskGroupHeader(group)
                        taskRows(group.tasks)
                    }
                } else {
                    taskRows(collectionTasks)
                }
            }
        }
    }

    private func taskRows(_ collectionTasks: [CreatorTask]) -> some View {
        ForEach(collectionTasks) { task in
            TaskRow(
                task: task,
                allTasks: tasks,
                linkedPostTitle: linkedPostTitle(for: task)
            )
        }
    }

    private func taskGroupHeader(_ group: TaskDueDateGroup) -> some View {
        HStack {
            MetaLabel(group.title)
            Spacer()
            MetaLabel("\(group.tasks.count)")
        }
        .padding(.top, AgentSpacing.x4)
        .padding(.bottom, AgentSpacing.x2)
    }

    private func dueDateGroups(for collectionTasks: [CreatorTask]) -> [TaskDueDateGroup] {
        Dictionary(grouping: collectionTasks) { task in
            task.targetDate.map(Calendar.current.startOfDay(for:))
        }
        .map { TaskDueDateGroup(day: $0.key, tasks: $0.value.sorted(by: sortTasks)) }
        .sorted { lhs, rhs in
            switch (lhs.day, rhs.day) {
            case let (left?, right?): left < right
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): false
            }
        }
    }

    private func sortTasks(_ lhs: CreatorTask, _ rhs: CreatorTask) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        let rank: (CreatorTask) -> Int = { task in
            task.priority.normalized == .urgent ? 0 : (task.priority.normalized == .high ? 1 : 2)
        }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        if (lhs.targetDate ?? .distantFuture) != (rhs.targetDate ?? .distantFuture) {
            return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func taskBelongsToDay(_ task: CreatorTask) -> Bool {
        if task.dailyFocusDate.map({ Calendar.current.isDate($0, inSameDayAs: date) }) == true ||
            task.targetDate.map({ Calendar.current.isDate($0, inSameDayAs: date) }) == true {
            return true
        }
        if let outputID = task.platformOutputID,
           dayOutputs.contains(where: { $0.id == outputID }) {
            return true
        }
        return task.briefID.map { briefID in
            dayOutputs.contains(where: { $0.briefID == briefID })
        } == true
    }

    private func linkedPostTitle(for task: CreatorTask) -> String? {
        let output = task.platformOutputID.flatMap { outputID in
            outputs.first { $0.id == outputID }
        }
        let briefID = task.briefID ?? output?.briefID
        guard let briefID,
              let brief = activeBriefs.first(where: { $0.id == briefID }) else { return nil }
        let override = output?.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? brief.title : override
    }

    private func loadDetails() {
        guard !didLoad else { return }
        didLoad = true
        detailRecord = savedDetails.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        note = detailRecord?.note ?? ""
        reminderEnabled = detailRecord?.reminderEnabled ?? false
        reminderDate = detailRecord?.reminderDate ?? defaultReminderDate
    }

    private var defaultReminderDate: Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Date().addingTimeInterval(30 * 60)
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func persistDetails(scheduleReminder: Bool) {
        guard didLoad else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detailRecord != nil || !trimmedNote.isEmpty || reminderEnabled else { return }

        let item = detailRecord ?? DailyFocusDayDetail(date: date)
        if item.modelContext == nil {
            item.workspaceID = appModel.resolvedWorkspaceID(context: context)
            context.insert(item)
            detailRecord = item
        }
        item.note = trimmedNote
        item.reminderEnabled = reminderEnabled
        item.reminderDate = reminderEnabled ? reminderDate : nil
        item.updatedAt = Date()
        try? context.save()
        WidgetSnapshotService.refresh(context: context)

        guard scheduleReminder else { return }
        Task { @MainActor in
            await appModel.applyFocusReminder(item, focusTitle: title, context: context)
            reminderEnabled = item.reminderEnabled
        }
    }

    private func addFocusTask() {
        appModel.setQuickCaptureMode(.task)
        appModel.quickCaptureTargetDate = date
        appModel.quickCaptureTaskLane = .production
        appModel.quickCaptureTaskFocus = DailyFocusTaskAssignment(
            date: date,
            title: title,
            taskKind: focus?.kinds.first?.taskKind ?? .planning,
            templateEntryID: focus?.templateEntryID
        )
        appModel.quickCapturePillarID = nil
        appModel.presentedSheet = .quickCapture
    }
}

struct DailyFocusEditorView: View {
    private enum Scope: Hashable {
        case date
        case recurring
    }

    private struct DraftSnapshot: Equatable {
        let selection: [DailyFocusKind]
        let note: String
        let scope: Scope
        let includeDuration: Bool
        let durationMinutes: Int
        let includeTime: Bool
        let startMinutes: Int
    }

    let date: Date
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTemplates: [DailyFocusTemplateEntry]
    @Query private var allOverrides: [DailyFocusOverride]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var selection: [DailyFocusKind] = []
    @State private var note = ""
    @State private var scope: Scope
    @State private var includeDuration = false
    @State private var durationMinutes = 60
    @State private var includeTime = false
    @State private var startTime = Date()
    @State private var detailsExpanded = false
    @State private var didLoad = false
    @State private var savedSnapshot: DraftSnapshot?

    private var templates: [DailyFocusTemplateEntry] {
        allTemplates.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }
    private var overrides: [DailyFocusOverride] {
        allOverrides.filter {
            WorkspaceScope.includes($0.workspaceID, activeWorkspaceID: appModel.activeWorkspaceID, workspaces: workspaces)
        }
    }

    private var weekday: PillarWeekday {
        PillarWeekday(rawValue: Calendar.current.component(.weekday, from: date)) ?? .monday
    }

    init(date: Date, defaultsToRecurring: Bool = false) {
        self.date = date
        _scope = State(initialValue: defaultsToRecurring ? .recurring : .date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: date.formatted(.dateTime.month(.abbreviated).day()),
                        title: selection.isEmpty ? "Rest." : DailyFocusKind.combinedTitle(selection) + ".",
                        subtitle: "Use this date once, or update every \(weekday.title)."
                    )

                    Picker("Apply focus", selection: $scope) {
                        Text("This date").tag(Scope.date)
                        Text("Every \(weekday.title)").tag(Scope.recurring)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 0) {
                        focusRow(title: "Rest", directive: DailyFocusKind.combinedDirective([]), kind: nil, showsDivider: false)
                        ForEach(DailyFocusKind.selectableCases) { kind in
                            focusRow(title: kind.title, directive: kind.directive, kind: kind, showsDivider: true)
                                .disabled(!selection.contains(kind) && selection.count == 2)
                        }
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.panel)

                    DisclosureGroup("Add details", isExpanded: $detailsExpanded) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            AgentMultilineField(
                                label: "Note",
                                placeholder: "",
                                text: $note,
                                lineLimit: 2...4
                            )

                            Toggle("Add duration", isOn: $includeDuration)
                                .toggleStyle(.switch)
                                .tint(Color.agentFocusControl)
                                .frame(maxWidth: .infinity)
                                .padding(.trailing, AgentSpacing.x1)
                            if includeDuration {
                                Stepper("\(durationMinutes) minutes", value: $durationMinutes, in: 15...480, step: 15)
                            }

                            Toggle("Add start time", isOn: $includeTime)
                                .toggleStyle(.switch)
                                .tint(Color.agentFocusControl)
                                .frame(maxWidth: .infinity)
                                .padding(.trailing, AgentSpacing.x1)
                            if includeTime {
                                DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                            }
                        }
                        .font(.agentBody)
                        .padding(.top, AgentSpacing.x4)
                    }
                    .font(.agentHeadline)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AgentToolbarIconButton(title: "Close", icon: .close) { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
                if hasChanges {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: save) {
                            AgentIconView(.check, size: 15)
                                .foregroundStyle(Color.agentPureBlack)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(Color.agentPureWhite)
                        .accessibilityLabel("Save focus")
                    }
                }
            }
            .onAppear(perform: load)
            .agentScreen()
        }
        .agentKeyboardDismissal()
    }

    private func focusRow(
        title: String,
        directive: String,
        kind: DailyFocusKind?,
        showsDivider: Bool
    ) -> some View {
        let isSelected = kind.map(selection.contains) ?? selection.isEmpty
        return Button {
            if let kind {
                toggle(kind)
            } else {
                selection = []
                note = ""
            }
        } label: {
            HStack(spacing: AgentSpacing.x4) {
                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                    Text(title).font(.agentBody.weight(.semibold))
                    Text(directive)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSelected {
                    AgentIconView(.check, size: 14)
                        .frame(width: 24, height: 24)
                        .padding(.trailing, AgentSpacing.x1)
                }
            }
            .foregroundStyle(Color.agentText)
            .padding(.vertical, AgentSpacing.x3)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle().fill(Color.agentHairline).frame(height: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ kind: DailyFocusKind) {
        let previousSelection = selection
        if let index = selection.firstIndex(of: kind) {
            selection.remove(at: index)
        } else if selection.count < 2 {
            selection.append(kind)
        }
        if selection != previousSelection {
            note = ""
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let focus = DailyFocusResolver.resolve(date: date, templates: templates, overrides: overrides) else {
            savedSnapshot = currentSnapshot
            return
        }
        selection = Array(focus.kinds.prefix(2))
        note = storedCustomNote
        durationMinutes = focus.durationMinutes ?? 60
        includeDuration = focus.durationMinutes != nil
        startTime = focus.time ?? Date()
        includeTime = focus.time != nil
        detailsExpanded = !note.isEmpty || includeDuration || includeTime
        savedSnapshot = currentSnapshot
    }

    private var currentSnapshot: DraftSnapshot {
        let calendar = Calendar.current
        return DraftSnapshot(
            selection: selection,
            note: note,
            scope: scope,
            includeDuration: includeDuration,
            durationMinutes: durationMinutes,
            includeTime: includeTime,
            startMinutes: calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
        )
    }

    private var hasChanges: Bool {
        guard didLoad, let savedSnapshot else { return false }
        return currentSnapshot != savedSnapshot
    }

    private var storedCustomNote: String {
        let calendar = Calendar.current
        if let item = overrides.first(where: { calendar.isDate($0.date, inSameDayAs: date) && !$0.isCleared }) {
            return [.custom, .posting, .admin].contains(item.kind) ? "" : item.note
        }
        guard let template = templates.first(where: { $0.weekday == weekday && $0.isActive }) else { return "" }
        return [.custom, .posting, .admin].contains(template.kind) ? "" : template.note
    }

    private func save() {
        let calendar = Calendar.current
        let minutes = includeTime
            ? calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
            : nil
        let title = DailyFocusKind.combinedTitle(selection)
        let now = Date()

        if scope == .recurring {
            let entry = templates.first(where: { $0.weekday == weekday })
                ?? DailyFocusTemplateEntry(weekday: weekday, kind: .custom, title: "Rest")
            if entry.modelContext == nil {
                entry.workspaceID = appModel.resolvedWorkspaceID(context: context)
                context.insert(entry)
            }
            entry.kind = selection.first ?? .custom
            entry.secondaryKind = selection.count > 1 ? selection[1] : nil
            entry.title = title
            entry.note = selection.isEmpty ? "" : note.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.durationMinutes = selection.isEmpty || !includeDuration ? nil : durationMinutes
            entry.startMinutesFromMidnight = selection.isEmpty ? nil : minutes
            entry.isActive = !selection.isEmpty
            entry.updatedAt = now

            overrides
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .forEach(context.delete)
        } else {
            let item = overrides.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
                ?? DailyFocusOverride(date: date)
            if item.modelContext == nil {
                item.workspaceID = appModel.resolvedWorkspaceID(context: context)
                context.insert(item)
            }
            item.templateEntryID = templates.first(where: { $0.weekday == weekday })?.id
            item.kind = selection.first ?? .custom
            item.secondaryKind = selection.count > 1 ? selection[1] : nil
            item.title = title
            item.note = selection.isEmpty ? "" : note.trimmingCharacters(in: .whitespacesAndNewlines)
            item.durationMinutes = selection.isEmpty || !includeDuration ? nil : durationMinutes
            item.startMinutesFromMidnight = selection.isEmpty ? nil : minutes
            item.isCleared = selection.isEmpty
            item.updatedAt = now
        }

        do {
            try context.save()
            if scope == .recurring {
                try FocusTaskRecurrenceService.reconcile(
                    context: context,
                    workspaceID: appModel.resolvedWorkspaceID(context: context)
                )
                appModel.queueCalendarSync(context: context)
            }
            WidgetSnapshotService.refresh(context: context)
            dismiss()
        } catch {
            appModel.presentCreatorError(error, action: "The focus")
        }
    }
}
