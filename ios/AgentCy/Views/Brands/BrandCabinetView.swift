import SwiftData
import SwiftUI
import UIKit

struct BrandCabinetView: View {
    @Environment(AppModel.self) private var appModel
    @Query(sort: \BrandPartner.updatedAt, order: .reverse) private var allPartners: [BrandPartner]
    @Query private var allContacts: [BrandContact]
    @Query private var allBriefs: [CreativeBrief]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var searchText = ""
    @State private var selectedStage: BrandPartnerStage?
    @State private var showPartnerEditor = false

    private var partners: [BrandPartner] {
        allPartners.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            )
        }
    }

    private var filteredPartners: [BrandPartner] {
        partners.filter { partner in
            let matchesStage = selectedStage == nil || partner.stage == selectedStage
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || partner.name.localizedCaseInsensitiveContains(query)
                || partner.socialHandle.localizedCaseInsensitiveContains(query)
                || primaryContact(for: partner)?.name.localizedCaseInsensitiveContains(query) == true
            return matchesStage && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                EditorialHeader(
                    kicker: "Brand cabinet",
                    title: "Who are you building with?",
                    subtitle: "Keep partnerships, follow-ups, and collaboration posts connected."
                )
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x8)
                .padding(.bottom, AgentLayout.pageHeaderToContentSpacing)

                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    HStack(spacing: AgentSpacing.x3) {
                        HStack(spacing: AgentSpacing.x3) {
                            AgentIconView(.search, size: 15)
                                .foregroundStyle(Color.agentSecondary)
                            TextField("Search partners", text: $searchText)
                                .font(.agentBody)
                        }
                        .padding(.horizontal, AgentSpacing.x4)
                        .frame(minHeight: 50)
                        .background(Color.agentCanvas, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }

                        Menu {
                            Button("All stages") { selectedStage = nil }
                            ForEach(BrandPartnerStage.allCases) { stage in
                                Button(stage.title) { selectedStage = stage }
                            }
                        } label: {
                            AgentIconView(.filter, size: 17)
                                .foregroundStyle(Color.agentText)
                                .frame(width: 50, height: 50)
                                .background(Color.agentCanvas, in: .circle)
                                .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
                        }
                        .accessibilityLabel("Filter partners")
                    }

                    SectionRuleHeader(
                        title: selectedStage?.title ?? "Partners",
                        trailing: "\(filteredPartners.count)"
                    )

                    if filteredPartners.isEmpty {
                        VStack(spacing: AgentSpacing.x3) {
                            Text(partners.isEmpty ? "No partners yet." : "No partners match this view.")
                                .font(.agentHeadline)
                            Text("Add a brand when you want to remember a relationship or follow up later.")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AgentSpacing.x12)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredPartners.enumerated()), id: \.element.id) { index, partner in
                                NavigationLink {
                                    BrandPartnerDetailView(partner: partner)
                                } label: {
                                    BrandPartnerRow(
                                        partner: partner,
                                        primaryContact: primaryContact(for: partner),
                                        linkedPostCount: linkedPostCount(for: partner)
                                    )
                                }
                                .buttonStyle(.plain)

                                if index < filteredPartners.count - 1 {
                                    Rectangle()
                                        .fill(Color.agentHairline)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }

                    AgentBlockAddActionButton(title: "Add partner") {
                        showPartnerEditor = true
                    }
                }
                .padding(.horizontal, AgentLayout.pageMargin)
                .padding(.top, AgentSpacing.x6)
                .padding(.bottom, AgentSpacing.x16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.agentSurface)
                .clipShape(.rect(cornerRadius: AgentRadius.floating))
                .agentSurfaceChrome(cornerRadius: AgentRadius.floating)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.agentCanvas)
        .navigationTitle("Brand cabinet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPartnerEditor) {
            BrandPartnerEditorView(workspaceID: appModel.activeWorkspaceID)
        }
    }

    private func primaryContact(for partner: BrandPartner) -> BrandContact? {
        allContacts
            .filter { $0.brandPartnerID == partner.id }
            .sorted { $0.isPrimary && !$1.isPrimary }
            .first
    }

    private func linkedPostCount(for partner: BrandPartner) -> Int {
        allBriefs.filter { $0.brandPartnerID == partner.id }.count
    }
}

private struct BrandPartnerRow: View {
    let partner: BrandPartner
    let primaryContact: BrandContact?
    let linkedPostCount: Int

    var body: some View {
        HStack(spacing: AgentSpacing.x4) {
            BrandPartnerAvatar(partner: partner, size: 44)

            VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                Text(partner.name)
                    .font(.agentHeadline)
                    .foregroundStyle(Color.agentText)
                    .lineLimit(1)
                Text(metadata)
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AgentSpacing.x2)

            VStack(alignment: .trailing, spacing: AgentSpacing.x1) {
                Text(partner.stage.title)
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentText)
                if let followUp = partner.nextFollowUpAt {
                    Text(followUp.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.agentMetadata)
                        .foregroundStyle(Color.actionAccent)
                }
            }

            AgentIconView(.forward, size: 12)
                .foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 70)
        .contentShape(.rect)
    }

    private var metadata: String {
        var pieces = [partner.type.title]
        if let primaryContact, !primaryContact.name.isEmpty { pieces.append(primaryContact.name) }
        if linkedPostCount > 0 { pieces.append("\(linkedPostCount) \(linkedPostCount == 1 ? "post" : "posts")") }
        return pieces.joined(separator: " · ")
    }
}

struct BrandPartnerDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var partner: BrandPartner
    @Query private var allContacts: [BrandContact]
    @Query(sort: \BrandActivity.occurredAt, order: .reverse) private var allActivities: [BrandActivity]
    @Query private var allBriefs: [CreativeBrief]
    @Query private var allOutputs: [PlatformOutput]
    @Query private var allPillars: [Pillar]
    @Query private var allTasks: [CreatorTask]
    @State private var showEditor = false
    @State private var contactEditorRequest: BrandContactEditorRequest?
    @State private var activityEditorRequest: BrandActivityEditorRequest?
    @State private var showPostLinker = false
    @State private var selectedBrief: CreativeBrief?

    private var contacts: [BrandContact] {
        allContacts.filter { $0.brandPartnerID == partner.id }
    }

    private var briefs: [CreativeBrief] {
        allBriefs.filter { $0.brandPartnerID == partner.id }
    }

    private var activities: [BrandActivity] {
        allActivities.filter { $0.brandPartnerID == partner.id }
    }

    private var activityCount: Int {
        if !activities.isEmpty {
            return activities.count
        }
        return partner.lastContactedAt == nil ? 0 : 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentSpacing.x8) {
                HStack(alignment: .center, spacing: AgentSpacing.x4) {
                    BrandPartnerAvatar(partner: partner, size: 64)
                    VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                        MetaLabel(partner.type.title)
                        Text(partner.name)
                            .font(.agentDisplay)
                            .foregroundStyle(Color.agentText)
                    }
                    Spacer()
                    Button { showEditor = true } label: {
                        Text("Edit")
                            .font(.agentSubtext.weight(.semibold))
                            .foregroundStyle(Color.agentText)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x4) {
                    BrandDetailRow(label: "Stage", value: partner.stage.title)
                    BrandDetailRow(
                        label: "Follow up",
                        value: partner.nextFollowUpAt?.formatted(.dateTime.month(.wide).day().year()) ?? "No date"
                    )
                    if !partner.websiteURLString.isEmpty {
                        BrandDetailRow(label: "Website", value: partner.websiteURLString)
                    }
                    if !partner.socialHandle.isEmpty {
                        BrandDetailRow(label: "Social", value: partner.socialHandle)
                    }
                }
                .padding(AgentSpacing.x4)
                .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
                .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)

                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    SectionRuleHeader(title: "Contacts", trailing: "\(contacts.count)")
                    ForEach(contacts) { contact in
                        Button {
                            contactEditorRequest = BrandContactEditorRequest(contactID: contact.id)
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                VStack(alignment: .leading, spacing: AgentSpacing.x1) {
                                    Text(contact.name)
                                        .font(.agentHeadline)
                                    Text([contact.role, contact.email].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.agentMetadata)
                                        .foregroundStyle(Color.agentSecondary)
                                }
                                Spacer()
                                AgentIconView(.forward, size: 14)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    AgentAddActionRow(title: "Add contact") {
                        contactEditorRequest = BrandContactEditorRequest()
                    }
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    SectionRuleHeader(title: "Linked posts", trailing: "\(briefs.count)")
                    if briefs.isEmpty {
                        Text("No collaboration posts yet.")
                            .font(.agentSubtext)
                            .foregroundStyle(Color.agentSecondary)
                            .padding(.vertical, AgentSpacing.x2)
                    } else {
                        VStack(spacing: AgentSpacing.x3) {
                            ForEach(briefs) { brief in
                                let output = preferredOutput(for: brief)
                                AgentPostCard(
                                    title: postTitle(for: brief, output: output),
                                    pillar: pillar(for: brief)?.name ?? "Unfiled",
                                    accent: pillarAccent(for: brief),
                                    status: output?.status ?? .draft,
                                    metadata: output?.platform.title ?? "Post",
                                    timeText: output?.targetDate?.formatted(.dateTime.month(.abbreviated).day()),
                                    statusTextOverride: statusOverride(for: brief, output: output),
                                    isLate: output.map { output in
                                        FinalizedPostPresentation.isMissed(
                                            outputStatus: output.status,
                                            targetDate: output.targetDate
                                        ) || PostWorkDateStatusPolicy.isLate(
                                            workDate: brief.workDate,
                                            briefStatus: brief.status,
                                            outputStatus: output.status
                                        )
                                    } ?? false,
                                    destination: postDestination(for: brief, output: output)
                                )
                            }
                        }
                    }
                    AgentAddActionRow(title: "Link an existing post") { showPostLinker = true }
                    AgentAddActionRow(title: "Create collaboration post") { createCollaborationPost() }
                }

                if !partner.notes.isEmpty {
                    VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                        SectionRuleHeader(title: "Notes")
                        Text(partner.notes)
                            .font(.agentBody)
                            .foregroundStyle(Color.agentText)
                    }
                }

                VStack(alignment: .leading, spacing: AgentSpacing.x3) {
                    SectionRuleHeader(title: "Activity history", trailing: "\(activityCount)")

                    VStack(spacing: 0) {
                        if activities.isEmpty, let lastContactedAt = partner.lastContactedAt {
                            Button {
                                activityEditorRequest = BrandActivityEditorRequest(isLegacyLastContact: true)
                            } label: {
                                BrandActivityRow(
                                    title: BrandActivityKind.reachedOut.title,
                                    note: "",
                                    occurredAt: lastContactedAt
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit or delete this activity")
                        } else if activities.isEmpty {
                            Text("No activity logged yet.")
                                .font(.agentSubtext)
                                .foregroundStyle(Color.agentSecondary)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .padding(.horizontal, AgentSpacing.x4)
                        } else {
                            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                                Button {
                                    activityEditorRequest = BrandActivityEditorRequest(activityID: activity.id)
                                } label: {
                                    BrandActivityRow(
                                        title: activity.title,
                                        note: activity.note,
                                        occurredAt: activity.occurredAt
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edit or delete this activity")

                                if index < activities.count - 1 {
                                    Divider()
                                        .overlay(Color.agentBorder)
                                        .padding(.leading, 31)
                                }
                            }
                        }

                        Divider()
                            .overlay(Color.agentBorder)

                        AgentBlockAddActionButton(title: "Log activity") {
                            activityEditorRequest = BrandActivityEditorRequest()
                        }
                        .padding(.horizontal, AgentSpacing.x3)
                        // The 38pt fill sits inside a 44pt hit area. Nine external
                        // points plus the three internal points yields a 12pt
                        // visible inset, matching the horizontal inset exactly.
                        .padding(.vertical, AgentSpacing.x2 + 1)
                    }
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)

                    HStack(spacing: AgentSpacing.x2) {
                        Text("Added \(partner.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                        Circle()
                            .fill(Color.agentSecondary)
                            .frame(width: 3, height: 3)
                        Text("Updated \(partner.updatedAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                    }
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, AgentSpacing.x1)
                }
            }
            .padding(.horizontal, AgentLayout.pageMargin)
            .padding(.vertical, AgentSpacing.x8)
            .agentBottomNavigationClearance()
        }
        .scrollIndicators(.hidden)
        .background(Color.agentCanvas)
        .navigationTitle("Partner")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            BrandPartnerEditorView(partner: partner, workspaceID: partner.workspaceID)
        }
        .sheet(item: $contactEditorRequest) { request in
            BrandContactEditorView(
                partner: partner,
                contact: request.contactID.flatMap { id in contacts.first { $0.id == id } }
            )
        }
        .sheet(item: $activityEditorRequest) { request in
            BrandActivityEditorView(
                partner: partner,
                activity: request.activityID.flatMap { id in
                    activities.first { $0.id == id }
                },
                legacyOccurredAt: request.isLegacyLastContact ? partner.lastContactedAt : nil
            )
        }
        .sheet(isPresented: $showPostLinker) {
            BrandPostLinkPickerView(partner: partner)
        }
        .navigationDestination(item: $selectedBrief) { brief in
            if let output = preferredOutput(for: brief) {
                PostOutputDetailView(brief: brief, output: output)
            } else {
                IdeaPostDraftView(brief: brief)
            }
        }
    }

    private func createCollaborationPost() {
        let brief = CreativeBrief(title: "New \(partner.name) post", source: .text, status: .spark)
        brief.workspaceID = partner.workspaceID
        brief.ideaBankPlacement = .post
        brief.isBrandCollaboration = true
        brief.brandPartnerID = partner.id
        brief.brandName = partner.name
        let output = PlatformOutput(briefID: brief.id)
        output.workspaceID = partner.workspaceID
        context.insert(brief)
        context.insert(output)
        try? context.save()
        selectedBrief = brief
    }

    private func preferredOutput(for brief: CreativeBrief) -> PlatformOutput? {
        allOutputs
            .filter { $0.briefID == brief.id }
            .sorted { lhs, rhs in
                let lhsIsFinal = PostOutputDetailPolicy.usesFinalizedView(
                    outputStatus: lhs.status,
                    targetDate: lhs.targetDate
                )
                let rhsIsFinal = PostOutputDetailPolicy.usesFinalizedView(
                    outputStatus: rhs.status,
                    targetDate: rhs.targetDate
                )
                if lhsIsFinal != rhsIsFinal { return lhsIsFinal }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    private func pillar(for brief: CreativeBrief) -> Pillar? {
        brief.pillarID.flatMap { id in
            allPillars.first { $0.id == id && !$0.isArchived }
        }
    }

    private func pillarAccent(for brief: CreativeBrief) -> Color {
        guard let pillar = pillar(for: brief) else { return .agentSecondary }
        return Color(agentHex: pillar.resolvedColorHex(in: allPillars))
    }

    private func postTitle(for brief: CreativeBrief, output: PlatformOutput?) -> String {
        guard let output else { return brief.title }
        let override = output.titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? brief.title : override
    }

    private func statusOverride(for brief: CreativeBrief, output: PlatformOutput?) -> String? {
        guard output?.status == .draft || output == nil else { return nil }
        return brief.status == .developing ? "In progress" : "Draft"
    }

    private func postDestination(for brief: CreativeBrief, output: PlatformOutput?) -> AnyView {
        if let output {
            return AnyView(PostOutputDetailView(brief: brief, output: output))
        }
        return AnyView(IdeaPostDraftView(brief: brief))
    }
}

private struct BrandDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentSpacing.x4) {
            MetaLabel(label)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.agentBody)
                .foregroundStyle(Color.agentText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

private struct BrandContactEditorRequest: Identifiable {
    let id = UUID()
    var contactID: UUID?
}

private struct BrandActivityEditorRequest: Identifiable {
    let id = UUID()
    var activityID: UUID?
    var isLegacyLastContact = false
}

private struct BrandActivityRow: View {
    let title: String
    let note: String
    let occurredAt: Date

    var body: some View {
        HStack(alignment: .top, spacing: AgentSpacing.x3) {
            Circle()
                .fill(Color.actionAccent)
                .frame(width: 7, height: 7)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                Text(title)
                    .font(.agentBody.weight(.semibold))
                    .foregroundStyle(Color.agentText)

                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.agentSubtext)
                        .foregroundStyle(Color.agentSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(occurredAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()).uppercased())
                    .font(.agentMetadata)
                    .foregroundStyle(Color.agentSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AgentIconView(.forward, size: 12)
                .foregroundStyle(Color.agentSecondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, AgentSpacing.x4)
        .padding(.vertical, AgentSpacing.x4)
        .contentShape(.rect)
    }
}

struct BrandPartnerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var tasks: [CreatorTask]
    let partner: BrandPartner?
    let workspaceID: UUID?
    @State private var name: String
    @State private var type: BrandPartnerType
    @State private var stage: BrandPartnerStage
    @State private var website: String
    @State private var socialHandle: String
    @State private var notes: String
    @State private var hasFollowUp: Bool
    @State private var followUpDate: Date

    init(partner: BrandPartner? = nil, workspaceID: UUID?) {
        self.partner = partner
        self.workspaceID = workspaceID
        _name = State(initialValue: partner?.name ?? "")
        _type = State(initialValue: partner?.type ?? .brand)
        _stage = State(initialValue: partner?.stage ?? .wishlist)
        _website = State(initialValue: partner?.websiteURLString ?? "")
        _socialHandle = State(initialValue: partner?.socialHandle ?? "")
        _notes = State(initialValue: partner?.notes ?? "")
        _hasFollowUp = State(initialValue: partner?.nextFollowUpAt != nil)
        _followUpDate = State(initialValue: partner?.nextFollowUpAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    MetaLabel("Partner")
                    TextField("Name", text: $name)
                        .font(.agentTitle)
                        .textInputAutocapitalization(.words)

                    BrandEditorPicker(label: "Type", value: type.title) {
                        Picker("Type", selection: $type) {
                            ForEach(BrandPartnerType.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }
                    BrandEditorPicker(label: "Stage", value: stage.title) {
                        Picker("Stage", selection: $stage) {
                            ForEach(BrandPartnerStage.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        Toggle("Set follow-up date", isOn: $hasFollowUp)
                            .font(.agentBody.weight(.semibold))
                            .tint(Color.actionAccent)
                            .frame(minHeight: 52)
                        if hasFollowUp {
                            DatePicker("Follow up", selection: $followUpDate, displayedComponents: .date)
                                .font(.agentBody)
                                .frame(minHeight: 52)
                        }
                    }

                    TextField("Website", text: $website)
                        .font(.agentBody)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("Social handle", text: $socialHandle)
                        .font(.agentBody)
                        .textInputAutocapitalization(.never)

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Notes")
                        TextEditor(text: $notes)
                            .font(.agentBody)
                            .frame(minHeight: 130)
                            .padding(AgentSpacing.x3)
                            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                    }
                }
                .padding(AgentLayout.pageMargin)
            }
            .background(Color.agentCanvas)
            .navigationTitle(partner == nil ? "New partner" : "Edit partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let value = partner ?? BrandPartner(workspaceID: workspaceID, name: name)
        if partner == nil { context.insert(value) }
        value.workspaceID = workspaceID
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.type = type
        value.stage = stage
        value.websiteURLString = website.trimmingCharacters(in: .whitespacesAndNewlines)
        value.socialHandle = socialHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        value.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        value.nextFollowUpAt = hasFollowUp ? Calendar.current.startOfDay(for: followUpDate) : nil
        value.updatedAt = Date()
        BrandPartnershipService.reconcileFollowUpTask(for: value, tasks: tasks, context: context)
        try? context.save()
        dismiss()
    }
}

private struct BrandEditorPicker<PickerContent: View>: View {
    let label: String
    let value: String
    @ViewBuilder let picker: PickerContent

    var body: some View {
        HStack {
            MetaLabel(label)
            Spacer()
            picker
                .labelsHidden()
            Text(value)
                .font(.agentBody)
                .foregroundStyle(Color.agentSecondary)
        }
        .frame(minHeight: 52)
    }
}

private struct BrandContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let partner: BrandPartner
    let contact: BrandContact?
    @State private var name: String
    @State private var role: String
    @State private var email: String
    @State private var phone: String
    @State private var socialHandle: String
    @State private var notes: String

    init(partner: BrandPartner, contact: BrandContact? = nil) {
        self.partner = partner
        self.contact = contact
        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _socialHandle = State(initialValue: contact?.socialHandle ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x5) {
                    TextField("Name", text: $name)
                    TextField("Role", text: $role)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Social handle", text: $socialHandle)
                        .textInputAutocapitalization(.never)

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Notes")
                        TextEditor(text: $notes)
                            .frame(minHeight: 110)
                            .padding(AgentSpacing.x3)
                            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                    }
                }
                .font(.agentBody)
                .padding(AgentLayout.pageMargin)
            }
            .background(Color.agentCanvas)
            .navigationTitle(contact == nil ? "New contact" : "Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(contact == nil ? "Add" : "Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let value = contact ?? BrandContact(
            workspaceID: partner.workspaceID,
            brandPartnerID: partner.id,
            name: name
        )
        if contact == nil { context.insert(value) }
        value.workspaceID = partner.workspaceID
        value.brandPartnerID = partner.id
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        value.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        value.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        value.socialHandle = socialHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        value.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        value.updatedAt = Date()
        partner.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

private struct BrandActivityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BrandActivity.occurredAt, order: .reverse) private var allActivities: [BrandActivity]
    let partner: BrandPartner
    let activity: BrandActivity?
    let legacyOccurredAt: Date?
    @State private var kind: BrandActivityKind
    @State private var customTitle: String
    @State private var note: String
    @State private var occurredAt: Date
    @State private var saveErrorMessage: String?
    @State private var saveErrorTitle = "Activity wasn’t saved"
    @State private var confirmDelete = false

    init(
        partner: BrandPartner,
        activity: BrandActivity? = nil,
        legacyOccurredAt: Date? = nil
    ) {
        self.partner = partner
        self.activity = activity
        self.legacyOccurredAt = legacyOccurredAt
        _kind = State(initialValue: activity?.kind ?? .reachedOut)
        _customTitle = State(initialValue: activity?.customTitle ?? "")
        _note = State(initialValue: activity?.note ?? "")
        _occurredAt = State(initialValue: activity?.occurredAt ?? legacyOccurredAt ?? Date())
    }

    private var canLog: Bool {
        kind != .custom || !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEditing: Bool {
        activity != nil || legacyOccurredAt != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgentSpacing.x6) {
                    VStack(spacing: 0) {
                        Menu {
                            Picker("Activity", selection: $kind) {
                                ForEach(BrandActivityKind.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                        } label: {
                            HStack(spacing: AgentSpacing.x3) {
                                MetaLabel("Activity")
                                Spacer()
                                Text(kind.title)
                                    .font(.agentBody)
                                    .foregroundStyle(Color.agentText)
                                AgentIconView(.expand, size: 12)
                                    .foregroundStyle(Color.agentSecondary)
                            }
                            .frame(minHeight: 52)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        if kind == .custom {
                            Divider().overlay(Color.agentBorder)
                            TextField("What happened?", text: $customTitle)
                                .font(.agentBody)
                                .frame(minHeight: 52)
                        }

                        Divider().overlay(Color.agentBorder)
                        DatePicker("Date", selection: $occurredAt, displayedComponents: .date)
                            .font(.agentBody)
                            .frame(minHeight: 52)
                    }
                    .padding(.horizontal, AgentSpacing.x4)
                    .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.dashboard))
                    .agentSurfaceChrome(cornerRadius: AgentRadius.dashboard)

                    VStack(alignment: .leading, spacing: AgentSpacing.x2) {
                        MetaLabel("Note")
                        TextEditor(text: $note)
                            .font(.agentBody)
                            .frame(minHeight: 130)
                            .padding(AgentSpacing.x3)
                            .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                            .overlay {
                                RoundedRectangle(cornerRadius: AgentRadius.control)
                                    .stroke(Color.agentBorder, lineWidth: 1)
                            }
                    }

                    if isEditing {
                        Button("Delete activity", role: .destructive) {
                            confirmDelete = true
                        }
                        .font(.agentBody.weight(.semibold))
                        .foregroundStyle(Color.agentDestructive)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.agentSurface, in: .rect(cornerRadius: AgentRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentRadius.control)
                                .stroke(Color.agentBorder, lineWidth: 1)
                        }
                    }
                }
                .padding(AgentLayout.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.agentCanvas)
            .navigationTitle(isEditing ? "Edit activity" : "Log activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Log") { saveActivity() }
                        .disabled(!canLog)
                }
            }
        }
        .presentationDetents([.large])
        .alert("Delete activity?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteActivity()
            }
        } message: {
            Text("This removes it from the activity history.")
        }
        .alert(
            saveErrorTitle,
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func saveActivity() {
        let normalizedDate = Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: Date()),
            minute: Calendar.current.component(.minute, from: Date()),
            second: 0,
            of: occurredAt
        ) ?? occurredAt
        let value: BrandActivity
        if let activity {
            value = activity
        } else {
            value = BrandActivity(
                workspaceID: partner.workspaceID,
                brandPartnerID: partner.id,
                kind: kind
            )
            context.insert(value)
        }
        value.workspaceID = partner.workspaceID
        value.brandPartnerID = partner.id
        value.kind = kind
        value.customTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.occurredAt = normalizedDate
        value.updatedAt = Date()
        updateLastActivityDate(including: normalizedDate, excluding: value.id)

        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveErrorTitle = "Activity wasn’t saved"
            saveErrorMessage = "Your activity history could not be updated. Please try again."
        }
    }

    private func deleteActivity() {
        if let activity {
            context.delete(activity)
            updateLastActivityDate(excluding: activity.id)
        } else if legacyOccurredAt != nil {
            partner.lastContactedAt = nil
        }

        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveErrorTitle = "Activity wasn’t deleted"
            saveErrorMessage = "Your activity history could not be updated. Please try again."
        }
    }

    private func updateLastActivityDate(including date: Date? = nil, excluding excludedID: UUID? = nil) {
        var dates = allActivities
            .filter { activity in
                activity.brandPartnerID == partner.id && activity.id != excludedID
            }
            .map(\.occurredAt)
        if let date {
            dates.append(date)
        }
        partner.lastContactedAt = dates.max()
    }
}

private struct BrandPostLinkPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let partner: BrandPartner
    @Query(sort: \CreativeBrief.updatedAt, order: .reverse) private var briefs: [CreativeBrief]

    var body: some View {
        NavigationStack {
            List {
                ForEach(briefs.filter { brief in
                    (brief.workspaceID == partner.workspaceID || brief.workspaceID == nil)
                        && brief.brandPartnerID != partner.id
                        && brief.status != .archived
                }) { brief in
                    Button {
                        brief.brandPartnerID = partner.id
                        brief.brandName = partner.name
                        brief.isBrandCollaboration = true
                        brief.updatedAt = Date()
                        try? context.save()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(brief.title)
                            Text(brief.status.title)
                                .font(.agentMetadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Link a post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

struct BrandPartnerPickerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BrandPartner.name) private var allPartners: [BrandPartner]
    @Query(sort: \CreatorWorkspace.sortOrder) private var workspaces: [CreatorWorkspace]
    @State private var showEditor = false
    let selectedPartnerID: UUID?
    let onSelect: (BrandPartner) -> Void

    private var partners: [BrandPartner] {
        allPartners.filter {
            WorkspaceScope.includes(
                $0.workspaceID,
                activeWorkspaceID: appModel.activeWorkspaceID,
                workspaces: workspaces
            ) && $0.stage != .archived
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(partners) { partner in
                    Button {
                        onSelect(partner)
                        dismiss()
                    } label: {
                        HStack {
                            BrandPartnerAvatar(partner: partner, size: 38)
                            Text(partner.name)
                            Spacer()
                            if selectedPartnerID == partner.id {
                                AgentIconView(.check, size: 13)
                            }
                        }
                    }
                }
                Button("Add a new partner") { showEditor = true }
            }
            .navigationTitle("Choose partner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showEditor) {
                BrandPartnerEditorView(workspaceID: appModel.activeWorkspaceID)
            }
        }
    }
}

struct BrandImportReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var briefs: [CreativeBrief]
    @Query private var outputs: [PlatformOutput]
    @Query private var partners: [BrandPartner]
    @State private var selectedIDs = Set<String>()

    private var suggestions: [BrandImportSuggestion] {
        BrandPartnershipService.importSuggestions(
            briefs: briefs,
            outputs: outputs,
            existingPartners: partners,
            workspaceID: appModel.activeWorkspaceID
        )
    }

    var body: some View {
        List {
            if suggestions.isEmpty {
                Text("No collaboration names are waiting for review.")
            } else {
                ForEach(suggestions) { suggestion in
                    Button {
                        if selectedIDs.contains(suggestion.id) {
                            selectedIDs.remove(suggestion.id)
                        } else {
                            selectedIDs.insert(suggestion.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(suggestion.name)
                                Text("\(suggestion.stage.title) · \(suggestion.briefIDs.count) posts")
                                    .font(.agentMetadata)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedIDs.contains(suggestion.id) {
                                AgentIconView(.check, size: 13)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Review partners")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    for suggestion in suggestions where selectedIDs.contains(suggestion.id) {
                        _ = BrandPartnershipService.importSuggestion(
                            suggestion,
                            workspaceID: appModel.activeWorkspaceID,
                            briefs: briefs,
                            context: context
                        )
                    }
                    try? context.save()
                    dismiss()
                }
                .disabled(selectedIDs.isEmpty)
            }
        }
        .onAppear {
            selectedIDs = Set(suggestions.map(\.id))
        }
    }
}

struct BrandPartnershipSettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: CreatorProfile

    var body: some View {
        SettingsPageShell(
            kicker: "Publishing",
            title: "Brand partnerships",
            subtitle: "Keep partner relationships and collaboration posts in one optional workspace."
        ) {
            Toggle("Show Brand cabinet", isOn: $profile.showsBrandDealsInPostEditor)
                .font(.agentBody.weight(.semibold))
                .tint(Color.actionAccent)
                .frame(minHeight: 52)

            Text("Turning this off hides the cabinet and collaboration fields. Your partner data stays saved.")
                .font(.agentSubtext)
                .foregroundStyle(Color.agentSecondary)

            if profile.showsBrandDealsInPostEditor {
                NavigationLink {
                    BrandCabinetView()
                } label: {
                    SettingsIndexRow(title: "Open Brand cabinet", value: "")
                }
                NavigationLink {
                    BrandImportReviewView()
                } label: {
                    SettingsIndexRow(title: "Review existing collaborations", value: "", isLast: true)
                }
            }
        }
        .onDisappear { try? context.save() }
    }
}

struct BrandPartnerAvatar: View {
    let partner: BrandPartner
    let size: CGFloat

    var body: some View {
        Group {
            if let data = partner.logoImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(monogram)
                    .font(.paperInter(size: size * 0.34, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.agentText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.agentCanvas)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().stroke(Color.agentBorder, lineWidth: 1))
    }

    private var monogram: String {
        partner.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}
