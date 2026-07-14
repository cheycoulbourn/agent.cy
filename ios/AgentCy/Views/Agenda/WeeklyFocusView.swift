import SwiftData
import SwiftUI

struct WeeklyFocusSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var templates: [DailyFocusTemplateEntry]
    @State private var assignments: [PillarWeekday: [DailyFocusKind]] = [:]
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                    EditorialHeader(
                        kicker: "Weekly focus",
                        title: "Batch your week.",
                        subtitle: "Choose up to two focuses for each day. Empty days stay Rest."
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
                                        selection: assignmentBinding(for: day)
                                    )
                                } label: {
                                    HStack(spacing: AgentSpacing.x4) {
                                        Text(day.letter)
                                            .font(.agentMono)
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
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
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

                    Button("Save weekly focus", systemImage: "checkmark") {
                        if appModel.saveWeeklyFocus(assignments, context: context) {
                            dismiss()
                        }
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
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
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
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
        }
    }
}

private struct WeeklyFocusDaySelectionView: View {
    let day: PillarWeekday
    @Binding var selection: [DailyFocusKind]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                EditorialHeader(
                    kicker: day.title,
                    title: selection.isEmpty ? "Rest." : DailyFocusKind.combinedTitle(selection) + ".",
                    subtitle: "Choose up to two kinds of work to batch on \(day.title)s."
                )

                VStack(alignment: .leading, spacing: 0) {
                    focusRow(
                        title: "Rest",
                        directive: DailyFocusKind.combinedDirective([]),
                        isSelected: selection.isEmpty,
                        showsDivider: false
                    ) {
                        selection = []
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

                if selection.count == 2 {
                    Text("Two focuses selected. Remove one to choose another.")
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                }

                    Button("Use for \(day.title)") { dismiss() }
                        .buttonStyle(AgentPrimaryButtonStyle())
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
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
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
        } else if selection.count < 2 {
            selection.append(kind)
        }
    }
}

struct DailyFocusDetailView: View {
    let date: Date

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var templates: [DailyFocusTemplateEntry]
    @Query private var overrides: [DailyFocusOverride]
    @Query(sort: \CreatorTask.createdAt) private var tasks: [CreatorTask]
    @Query private var savedDetails: [DailyFocusDayDetail]
    @State private var detailRecord: DailyFocusDayDetail?
    @State private var note = ""
    @State private var reminderEnabled = false
    @State private var reminderDate = Date()
    @State private var didLoad = false

    private var focus: ResolvedDailyFocus? {
        DailyFocusResolver.resolve(date: date, templates: templates, overrides: overrides)
    }

    private var title: String { focus?.title ?? "Rest" }
    private var directive: String {
        focus?.note.isEmpty == false
            ? (focus?.note ?? "")
            : DailyFocusKind.combinedDirective(focus?.kinds ?? [])
    }
    private var focusTasks: [CreatorTask] {
        tasks
            .filter {
                $0.parentTaskID == nil &&
                    $0.lane == .production &&
                    (
                        $0.dailyFocusDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ||
                        ($0.dailyFocusDate == nil && $0.targetDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true)
                    )
            }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                return (lhs.targetDate ?? .distantFuture) < (rhs.targetDate ?? .distantFuture)
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
                        MetaLabel("Direction")
                        Text(directive)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let focus, !focus.kinds.isEmpty {
                        Rectangle()
                            .fill(Color.agentHairline)
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            MetaLabel(focus.kinds.count == 1 ? "Focus area" : "Focus areas")
                            ForEach(focus.kinds) { kind in
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(kind.title)
                                        .font(.agentSubtext.weight(.semibold))
                                    Text(kind.directive)
                                        .font(.agentSubtext)
                                        .foregroundStyle(Color.agentSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
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
                }
                .padding(AgentSpacing.x6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        MetaLabel("Focus tasks")
                        Spacer()
                        MetaLabel("\(focusTasks.filter(\.isCompleted).count) of \(focusTasks.count)")
                    }
                    .padding(.bottom, AgentSpacing.x3)

                    if focusTasks.isEmpty {
                        Text("No focus tasks planned for this day.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .padding(.vertical, AgentSpacing.x3)
                    } else {
                        ForEach(focusTasks) { task in
                            HStack(spacing: AgentSpacing.x2) {
                                Button {
                                    appModel.toggleTask(task, context: context)
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.agentBorder, lineWidth: 1.25)
                                        .background(
                                            task.isCompleted ? Color.agentText : Color.clear,
                                            in: .rect(cornerRadius: 4)
                                        )
                                        .overlay {
                                            if task.isCompleted {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(Color.agentCanvas)
                                            }
                                        }
                                        .frame(width: 19, height: 19)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(task.isCompleted ? "Mark focus task open" : "Complete focus task")

                                NavigationLink {
                                    TaskDetailView(task: task)
                                } label: {
                                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                        Text(task.title)
                                            .font(.agentSubtext.weight(.semibold))
                                            .foregroundStyle(task.isCompleted ? Color.agentSecondary : Color.agentText)
                                            .strikethrough(task.isCompleted)
                                            .lineLimit(2)
                                        HStack(spacing: AgentSpacing.x2) {
                                            MetaLabel(task.kind.title)
                                            if let targetDate = task.targetDate {
                                                MetaLabel(targetDate.formatted(date: .omitted, time: .shortened))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }

                            if task.id != focusTasks.last?.id {
                                Rectangle().fill(Color.agentHairline).frame(height: 1)
                            }
                        }
                    }

                    AgentAddActionRow(title: "Add task", action: addFocusTask)
                        .padding(.top, AgentSpacing.x3)
                }
                .padding(AgentSpacing.x6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.panel))

                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    AgentMultilineField(
                        label: "Notes",
                        placeholder: "Add context for this focus day",
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
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.top, AgentSpacing.x6)
            .padding(.bottom, 120)
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
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
        appModel.quickCaptureStartsWithTask = true
        appModel.quickCaptureStartsWithPost = false
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

    let date: Date
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var templates: [DailyFocusTemplateEntry]
    @Query private var overrides: [DailyFocusOverride]
    @State private var selection: [DailyFocusKind] = []
    @State private var note = ""
    @State private var scope: Scope
    @State private var includeDuration = false
    @State private var durationMinutes = 60
    @State private var includeTime = false
    @State private var startTime = Date()
    @State private var detailsExpanded = false
    @State private var didLoad = false

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

                    DisclosureGroup("Add details", isExpanded: $detailsExpanded) {
                        VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                            AgentMultilineField(
                                label: "Note",
                                placeholder: "Optional note",
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

                    Button(scope == .recurring ? "Save every \(weekday.title)" : "Save this date") {
                        save()
                    }
                    .buttonStyle(AgentPrimaryButtonStyle())
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
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
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
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
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
            return
        }
        selection = Array(focus.kinds.prefix(2))
        note = storedCustomNote
        durationMinutes = focus.durationMinutes ?? 60
        includeDuration = focus.durationMinutes != nil
        startTime = focus.time ?? Date()
        includeTime = focus.time != nil
        detailsExpanded = !note.isEmpty || includeDuration || includeTime
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
            if entry.modelContext == nil { context.insert(entry) }
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
            if item.modelContext == nil { context.insert(item) }
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
            WidgetSnapshotService.refresh(context: context)
            dismiss()
        } catch {
            appModel.notice = .error("Focus could not be saved: \(error.localizedDescription)")
        }
    }
}
