import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
protocol ExportServicing {
    func makeArchive(context: ModelContext) throws -> URL
}

@MainActor
struct LocalExportService: ExportServicing {
    func makeArchive(context: ModelContext) throws -> URL {
        let profiles = try context.fetch(FetchDescriptor<CreatorProfile>())
        let voiceExamples = try context.fetch(FetchDescriptor<VoiceExample>())
        let voiceProfiles = try context.fetch(FetchDescriptor<VoiceProfile>())
        let briefs = try context.fetch(FetchDescriptor<CreativeBrief>())
        let pendingProposals = try context.fetch(FetchDescriptor<PendingBriefProposal>())
        let pendingVoiceProposals = try context.fetch(FetchDescriptor<PendingVoiceProfileProposal>())
        let outputs = try context.fetch(FetchDescriptor<PlatformOutput>())
        let tasks = try context.fetch(FetchDescriptor<CreatorTask>())
        let pillars = try context.fetch(FetchDescriptor<Pillar>())
        let rhythmTemplates = try context.fetch(FetchDescriptor<RhythmTemplate>())
        let weekPlans = try context.fetch(FetchDescriptor<WeekPlan>())
        let threads = try context.fetch(FetchDescriptor<ConversationThread>())
        let messages = try context.fetch(FetchDescriptor<ConversationMessage>())
        let reminders = try context.fetch(FetchDescriptor<ReminderSettings>())
        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionState>())
        let destinations = try context.fetch(FetchDescriptor<PublishingDestination>())
        let formats = try context.fetch(FetchDescriptor<PublishingFormat>())
        let socialAccounts = try context.fetch(FetchDescriptor<CreatorSocialAccount>())
        let focusTemplates = try context.fetch(FetchDescriptor<DailyFocusTemplateEntry>())
        let focusOverrides = try context.fetch(FetchDescriptor<DailyFocusOverride>())
        let focusDayDetails = try context.fetch(FetchDescriptor<DailyFocusDayDetail>())
        let weekProposals = try context.fetch(FetchDescriptor<PendingWeekProposal>())
        let attachments = try context.fetch(FetchDescriptor<CreatorAttachment>())
        let brandPartners = try context.fetch(FetchDescriptor<BrandPartner>())
        let brandContacts = try context.fetch(FetchDescriptor<BrandContact>())
        let brandActivities = try context.fetch(FetchDescriptor<BrandActivity>())

        let object: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "schemaVersion": 15,
            "profiles": profiles.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "goal": $0.goal,
                "platforms": $0.selectedPlatforms.map(\.rawValue),
                "assistanceMode": $0.assistanceMode.rawValue,
                "customCyQuickPrompts": $0.customCyQuickPrompts ?? [],
                "showsHookInPostEditor": $0.showsHookInPostEditor,
                "showsBrandDealsInPostEditor": $0.showsBrandDealsInPostEditor,
                "showsMoodBoardsInPostEditor": $0.showsMoodBoardsInPostEditor
            ] },
            "voiceExamples": voiceExamples.map {
                [
                    "id": $0.id.uuidString,
                    "profileID": $0.profileID.uuidString,
                    "text": $0.text,
                    "sortOrder": $0.sortOrder,
                    "source": $0.source.rawValue,
                    "sourceURL": $0.sourceURL?.absoluteString ?? NSNull(),
                    "creatorConfirmed": $0.creatorConfirmed,
                    "createdAt": ISO8601DateFormatter().string(from: $0.createdAt),
                    "updatedAt": ISO8601DateFormatter().string(from: $0.updatedAt)
                ] as [String: Any]
            },
            "voiceProfiles": voiceProfiles.map { ["id": $0.id.uuidString, "profileID": $0.profileID.uuidString, "summary": $0.summary, "traits": $0.traitsText, "avoid": $0.avoidText, "version": $0.version, "isApproved": $0.isApproved, "canonicalPayloadJSON": $0.canonicalPayloadJSON, "evidenceFingerprint": $0.evidenceFingerprint] as [String: Any] },
            "briefs": briefs.map { brief in
                [
                    "id": brief.id.uuidString,
                    "title": brief.title,
                    "premise": brief.premise,
                    "notes": brief.notes,
                    "audience": brief.audience,
                    "goal": brief.creativeGoal,
                    "takeaway": brief.takeaway,
                    "durationSeconds": brief.durationSeconds,
                    "spokenHook": brief.spokenHook,
                    "firstFrameText": brief.firstFrameText,
                    "scriptBeats": brief.scriptBeats,
                    "close": brief.close,
                    "ctaIntent": brief.ctaIntent,
                    "filmingGuidance": brief.filmingGuidance,
                    "editingGuidance": brief.editingGuidance,
                    "assumptions": brief.assumptions,
                    "voiceConfidence": brief.voiceConfidence,
                    "source": brief.source.rawValue,
                    "status": brief.status.rawValue,
                    "brandCollaboration": brief.isBrandCollaboration,
                    "brandPartnerID": brief.brandPartnerID?.uuidString ?? NSNull(),
                    "brandName": brief.brandName,
                    "compensationType": brief.compensationType.rawValue,
                    "compensationAmount": brief.compensationAmount ?? NSNull(),
                    "compensationCurrencyCode": brief.compensationCurrencyCode,
                    "hasNetTerms": brief.brandHasNetTerms,
                    "netTermsDays": brief.brandNetTermsDays,
                    "giftedProduct": brief.giftedProductDescription,
                    "moodBoardEnabled": brief.moodBoardEnabled,
                    "moodBoardURL": brief.moodBoardURLString,
                    "workDate": brief.workDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "includesWorkTime": brief.includesWorkTime,
                    "agendaDate": brief.agendaDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "lifecycleHistory": brief.lifecycleHistory.map {
                        [
                            "status": $0.status.rawValue,
                            "date": ISO8601DateFormatter().string(from: $0.date)
                        ]
                    },
                    "readyBriefPayloadJSON": brief.readyBriefPayloadJSON
                ] as [String: Any]
            },
            "pendingBriefProposals": pendingProposals.map { proposal in
                let payloadData = Data(proposal.payloadJSON.utf8)
                let payload = (try? JSONSerialization.jsonObject(with: payloadData)) ?? proposal.payloadJSON
                return [
                    "id": proposal.id.uuidString,
                    "briefID": proposal.briefID.uuidString,
                    "proposalKind": proposal.proposalKindRaw,
                    "createdAt": ISO8601DateFormatter().string(from: proposal.createdAt),
                    "updatedAt": ISO8601DateFormatter().string(from: proposal.updatedAt),
                    "payload": payload
                ] as [String: Any]
            },
            "pendingVoiceProfileProposals": pendingVoiceProposals.map { proposal in
                let payloadData = Data(proposal.payloadJSON.utf8)
                let payload = (try? JSONSerialization.jsonObject(with: payloadData)) ?? proposal.payloadJSON
                return [
                    "id": proposal.id.uuidString,
                    "profileID": proposal.profileID.uuidString,
                    "sourceVersion": proposal.sourceVersion,
                    "proposalKind": proposal.proposalKindRaw,
                    "createdAt": ISO8601DateFormatter().string(from: proposal.createdAt),
                    "updatedAt": ISO8601DateFormatter().string(from: proposal.updatedAt),
                    "payload": payload
                ] as [String: Any]
            },
            "platformOutputs": outputs.map { output in
                [
                    "id": output.id.uuidString,
                    "briefID": output.briefID.uuidString,
                    "platform": output.platform.rawValue,
                    "destinationID": output.destinationID?.uuidString ?? NSNull(),
                    "formatID": output.formatID?.uuidString ?? NSNull(),
                    "socialAccountID": output.socialAccountID?.uuidString ?? NSNull(),
                    "caption": output.caption,
                    "openingAdjustment": output.openingAdjustment,
                    "titleOverride": output.titleOverride,
                    "cta": output.cta,
                    "editChanges": output.editChanges,
                    "status": output.status.rawValue,
                    "seriesName": output.seriesName,
                    "recurrence": output.recurrence.rawValue,
                    "recurrenceWeekdays": output.recurrenceWeekdays.map(\.rawValue).sorted(),
                    "recurrenceMonthDay": output.recurrenceMonthDay ?? NSNull(),
                    "recurrenceEndDate": output.recurrenceEndDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "includesTargetTime": output.includesTargetTime,
                    "seriesRootOutputID": output.seriesRootOutputID?.uuidString ?? NSNull(),
                    "targetDate": output.targetDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "postedAt": output.postedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "publishedURL": output.publishedURLString
                ] as [String: Any]
            },
            "tasks": tasks.map { task in
                [
                    "id": task.id.uuidString,
                    "briefID": task.briefID?.uuidString ?? NSNull(),
                    "brandPartnerID": task.brandPartnerID?.uuidString ?? NSNull(),
                    "parentTaskID": task.parentTaskID?.uuidString ?? NSNull(),
                    "title": task.title,
                    "kind": task.kind.rawValue,
                    "priority": task.priority.rawValue,
                    "notes": task.notes,
                    "estimatedMinutes": task.estimatedMinutes ?? NSNull(),
                    "isCompleted": task.isCompleted,
                    "isSkipped": task.isSkipped,
                    "skippedAt": task.skippedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "targetDate": task.targetDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "includesTargetTime": task.includesTargetTime,
                    "dailyFocusDate": task.dailyFocusDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "dailyFocusTitle": task.dailyFocusTitle ?? NSNull(),
                    "dailyFocusTemplateEntryID": task.dailyFocusTemplateEntryID?.uuidString ?? NSNull(),
                    "focusTaskTemplateID": task.focusTaskTemplateID?.uuidString ?? NSNull(),
                    "isFocusTemplateCustomized": task.isFocusTemplateCustomized,
                    "recurrence": task.recurrence.rawValue,
                    "recurrenceRootTaskID": task.recurrenceRootTaskID?.uuidString ?? NSNull(),
                    "completedAt": task.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "recordingMilestoneEmitted": task.recordingMilestoneEmitted,
                    "isRecordingMilestoneDesignated": task.isRecordingMilestoneDesignated
                ] as [String: Any]
            },
            "pillars": pillars.map {
                [
                    "id": $0.id.uuidString,
                    "parentPillarID": $0.parentPillarID?.uuidString ?? NSNull(),
                    "name": $0.name,
                    "detail": $0.detail,
                    "colorHex": $0.colorHex,
                    "assignedWeekdays": $0.assignedWeekdays.map(\.rawValue).sorted(),
                    "isArchived": $0.isArchived
                ] as [String: Any]
            },
            "rhythmTemplates": rhythmTemplates.map { ["id": $0.id.uuidString, "name": $0.name, "entries": $0.entriesText, "isActive": $0.isActive] as [String: Any] },
            "weekPlans": weekPlans.map { ["id": $0.id.uuidString, "weekStart": ISO8601DateFormatter().string(from: $0.weekStart), "rhythmEntries": $0.rhythmEntriesText, "notes": $0.notes] },
            "conversationThreads": threads.map { ["id": $0.id.uuidString, "briefID": $0.briefID?.uuidString ?? NSNull(), "title": $0.title, "turnCount": $0.turnCount] as [String: Any] },
            "conversationMessages": messages.map { ["id": $0.id.uuidString, "threadID": $0.threadID.uuidString, "role": $0.role.rawValue, "text": $0.text, "createdAt": ISO8601DateFormatter().string(from: $0.createdAt)] },
            "reminderSettings": reminders.map {
                [
                    "id": $0.id.uuidString,
                    "masterEnabled": $0.masterEnabled,
                    "dailyEnabled": $0.dailyEnabled,
                    "dailyHour": $0.dailyHour,
                    "dailyMinute": $0.dailyMinute,
                    "weeklyEnabled": $0.weeklyEnabled,
                    "weeklyWeekday": $0.weeklyWeekday,
                    "weeklyHour": $0.weeklyHour,
                    "weeklyMinute": $0.weeklyMinute,
                    "postRemindersEnabled": $0.postRemindersEnabled,
                    "missedPostRemindersEnabled": $0.missedPostRemindersEnabled,
                    "taskRemindersEnabled": $0.taskRemindersEnabled,
                    "draftPrepRemindersEnabled": $0.draftPrepRemindersEnabled,
                    "accessRemindersEnabled": $0.accessRemindersEnabled,
                    "draftPrepHour": $0.draftPrepHour,
                    "draftPrepMinute": $0.draftPrepMinute,
                    "dateOnlyDeadlineHour": $0.dateOnlyDeadlineHour,
                    "dateOnlyDeadlineMinute": $0.dateOnlyDeadlineMinute,
                    "quietHoursEnabled": $0.quietHoursEnabled,
                    "quietHoursStartHour": $0.quietHoursStartHour,
                    "quietHoursStartMinute": $0.quietHoursStartMinute,
                    "quietHoursEndHour": $0.quietHoursEndHour,
                    "quietHoursEndMinute": $0.quietHoursEndMinute,
                    "showNotificationTitles": $0.showNotificationTitles,
                ] as [String: Any]
            },
            "subscriptionStates": subscriptions.map { ["id": $0.id.uuidString, "access": $0.access.rawValue, "trialEnd": $0.trialEnd.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(), "freeBriefConsumed": $0.freeBriefConsumed, "ideationRequestsUsed": $0.ideationRequestsUsed, "revisionRequestsUsed": $0.revisionRequestsUsed, "teachCyUpdatesUsed": $0.teachCyUpdatesUsed] as [String: Any] }
            ,"publishingDestinations": destinations.map { ["id": $0.id.uuidString, "name": $0.name, "builtInKind": $0.builtInKindRaw, "isArchived": $0.isArchived] as [String: Any] }
            ,"publishingFormats": formats.map { ["id": $0.id.uuidString, "destinationID": $0.destinationID.uuidString, "name": $0.name, "kind": $0.kind.rawValue, "isArchived": $0.isArchived] as [String: Any] }
            ,"socialAccounts": socialAccounts.map { ["id": $0.id.uuidString, "profileID": $0.profileID.uuidString, "destinationID": $0.destinationID.uuidString, "label": $0.label, "profileURL": $0.profileURLString, "isPrimary": $0.isPrimary, "isArchived": $0.isArchived] as [String: Any] }
            ,"dailyFocusTemplates": focusTemplates.map { ["id": $0.id.uuidString, "weekday": $0.weekday.rawValue, "kind": $0.kind.rawValue, "title": $0.title, "note": $0.note, "focusTasks": $0.focusTaskTemplates.map { ["id": $0.id.uuidString, "focusKind": $0.focusKind.rawValue, "title": $0.title, "priority": $0.priority.rawValue, "sortOrder": $0.sortOrder] }] as [String: Any] }
            ,"dailyFocusOverrides": focusOverrides.map { ["id": $0.id.uuidString, "date": ISO8601DateFormatter().string(from: $0.date), "isCleared": $0.isCleared, "title": $0.title] as [String: Any] }
            ,"dailyFocusDayDetails": focusDayDetails.map {
                [
                    "id": $0.id.uuidString,
                    "date": ISO8601DateFormatter().string(from: $0.date),
                    "note": $0.note,
                    "reminderEnabled": $0.reminderEnabled,
                    "reminderDate": $0.reminderDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
                ] as [String: Any]
            }
            ,"pendingWeekProposals": weekProposals.map { ["id": $0.id.uuidString, "weekStart": ISO8601DateFormatter().string(from: $0.weekStart), "status": $0.statusRaw, "payloadJSON": $0.payloadJSON] as [String: Any] }
            ,"attachments": attachments.map { ["id": $0.id.uuidString, "briefID": $0.briefID.uuidString, "platformOutputID": $0.platformOutputID?.uuidString ?? NSNull(), "ownerKind": $0.ownerKind.rawValue, "fileName": $0.fileName, "kind": $0.kind.rawValue, "contentType": $0.uniformTypeIdentifier, "byteCount": $0.byteCount] as [String: Any] }
            ,"brandPartners": brandPartners.map {
                [
                    "id": $0.id.uuidString,
                    "workspaceID": $0.workspaceID?.uuidString ?? NSNull(),
                    "name": $0.name,
                    "type": $0.type.rawValue,
                    "stage": $0.stage.rawValue,
                    "website": $0.websiteURLString,
                    "socialHandle": $0.socialHandle,
                    "notes": $0.notes,
                    "nextFollowUpAt": $0.nextFollowUpAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "lastContactedAt": $0.lastContactedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
                ] as [String: Any]
            }
            ,"brandContacts": brandContacts.map {
                [
                    "id": $0.id.uuidString,
                    "workspaceID": $0.workspaceID?.uuidString ?? NSNull(),
                    "brandPartnerID": $0.brandPartnerID.uuidString,
                    "name": $0.name,
                    "role": $0.role,
                    "email": $0.email,
                    "phone": $0.phone,
                    "preferredChannel": $0.preferredChannel,
                    "socialHandle": $0.socialHandle,
                    "notes": $0.notes,
                    "isPrimary": $0.isPrimary
                ] as [String: Any]
            }
            ,"brandActivities": brandActivities.map {
                [
                    "id": $0.id.uuidString,
                    "workspaceID": $0.workspaceID?.uuidString ?? NSNull(),
                    "brandPartnerID": $0.brandPartnerID.uuidString,
                    "kind": $0.kind.rawValue,
                    "title": $0.title,
                    "note": $0.note,
                    "occurredAt": ISO8601DateFormatter().string(from: $0.occurredAt),
                    "createdAt": ISO8601DateFormatter().string(from: $0.createdAt),
                    "updatedAt": ISO8601DateFormatter().string(from: $0.updatedAt)
                ] as [String: Any]
            }
        ]

        let json = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let markdown = makeMarkdown(briefs: briefs, outputs: outputs, tasks: tasks)
        var entries: [StoredZIP.Entry] = [
            .init(path: "agentcy-export.json", data: json),
            .init(path: "posts.md", data: Data(markdown.utf8)),
            .init(
                path: "brand-cabinet.md",
                data: Data(
                    makeBrandMarkdown(
                        partners: brandPartners,
                        contacts: brandContacts,
                        activities: brandActivities,
                        briefs: briefs
                    ).utf8
                )
            )
        ]
        for attachment in attachments {
            if let data = attachment.cloudData {
                let fileName = archiveSafeFileName(attachment.fileName)
                entries.append(.init(path: "attachments/\(attachment.id.uuidString)-\(fileName)", data: data))
            }
        }
        let archive = StoredZIP.make(entries: entries)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentcy-export-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("zip")
        try archive.write(to: destination, options: .atomic)
        return destination
    }

    private func archiveSafeFileName(_ rawName: String) -> String {
        let normalized = rawName.replacingOccurrences(of: "\\", with: "/")
        let leaf = normalized.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        let sanitized = String(leaf.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(sanitized.prefix(120))
        return limited.isEmpty || limited == "." || limited == ".." ? "attachment" : limited
    }

    private func makeMarkdown(briefs: [CreativeBrief], outputs: [PlatformOutput], tasks: [CreatorTask]) -> String {
        var lines = ["# agent.cy post export", "", "Exported \(Date().formatted(date: .long, time: .shortened))", ""]
        for brief in briefs.sorted(by: { $0.createdAt > $1.createdAt }) {
            lines += [
                "## \(brief.title)",
                "",
                "**Status:** \(brief.status.title)  ",
                "**Premise:** \(brief.premise)",
                brief.notes.isEmpty ? "" : "**Notes:** \(brief.notes)",
                "",
                "### Hook",
                brief.spokenHook,
                "",
                "### Script beats"
            ]
            lines += brief.scriptBeats.map { "- \($0)" }
            lines += ["", "### Close", brief.close, ""]
            let variants = outputs.filter { $0.briefID == brief.id }
            for output in variants {
                lines += ["#### \(output.platform.title)", output.caption, ""]
            }
            let allBriefTasks = tasks.filter { $0.briefID == brief.id }
            let briefTasks = allBriefTasks
                .filter { $0.parentTaskID == nil }
                .sorted { $0.sortOrder < $1.sortOrder }
                .flatMap { task in
                    let skipped = task.isSkipped ? " · Skipped" : ""
                    let parentLine = "- [\(task.isCompleted ? "x" : " ")] \(task.title) (\(task.kind.title)\(skipped))"
                    let childLines = allBriefTasks
                        .filter { $0.parentTaskID == task.id }
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map { "  - [\($0.isCompleted ? "x" : " ")] \($0.title)\($0.isSkipped ? " (Skipped)" : "")" }
                    return [parentLine] + childLines
                }
            if !briefTasks.isEmpty {
                lines += ["### Tasks"] + briefTasks + [""]
            }
        }
        return lines.joined(separator: "\n")
    }

    private func makeBrandMarkdown(
        partners: [BrandPartner],
        contacts: [BrandContact],
        activities: [BrandActivity],
        briefs: [CreativeBrief]
    ) -> String {
        var lines = [
            "# agent.cy brand cabinet",
            "",
            "Exported \(Date().formatted(date: .long, time: .shortened))",
            ""
        ]
        for partner in partners.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) {
            lines += [
                "## \(partner.name)",
                "",
                "**Stage:** \(partner.stage.title)  ",
                "**Type:** \(partner.type.title)  "
            ]
            if let followUp = partner.nextFollowUpAt {
                lines.append("**Next follow-up:** \(followUp.formatted(date: .long, time: .omitted))  ")
            }
            if !partner.websiteURLString.isEmpty {
                lines.append("**Website:** \(partner.websiteURLString)  ")
            }
            if !partner.socialHandle.isEmpty {
                lines.append("**Social:** \(partner.socialHandle)  ")
            }

            let partnerActivities = activities
                .filter { $0.brandPartnerID == partner.id }
                .sorted { $0.occurredAt > $1.occurredAt }
            if !partnerActivities.isEmpty {
                lines += ["", "### Activity"]
                lines += partnerActivities.map { activity in
                    let note = activity.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    return "- \(activity.occurredAt.formatted(date: .long, time: .omitted)) · \(activity.title)"
                        + (note.isEmpty ? "" : " — \(note)")
                }
            }

            let partnerContacts = contacts.filter { $0.brandPartnerID == partner.id }
            if !partnerContacts.isEmpty {
                lines += ["", "### Contacts"]
                lines += partnerContacts.map { contact in
                    let details = [contact.role, contact.email, contact.phone].filter { !$0.isEmpty }
                    return "- \(contact.name)\(details.isEmpty ? "" : " · \(details.joined(separator: " · "))")"
                }
            }

            let linkedPosts = briefs.filter { $0.brandPartnerID == partner.id }
            if !linkedPosts.isEmpty {
                lines += ["", "### Linked posts"]
                lines += linkedPosts.map { "- \($0.title) · \($0.status.title)" }
            }
            if !partner.notes.isEmpty {
                lines += ["", "### Notes", partner.notes]
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

}

struct MarkdownFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.agentMarkdown] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension UTType {
    static var agentMarkdown: UTType {
        UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    }
}

/// A single-post handoff designed to paste cleanly into Notion or an AI chat.
/// It intentionally omits internal identifiers and empty sections.
@MainActor
enum PostMarkdownExporter {
    static func makeDocument(
        brief: CreativeBrief,
        outputs: [PlatformOutput],
        tasks: [CreatorTask],
        pillar: Pillar?,
        destinations: [PublishingDestination],
        formats: [PublishingFormat],
        socialAccounts: [CreatorSocialAccount],
        attachments: [CreatorAttachment],
        exportedAt: Date = Date()
    ) -> MarkdownFileDocument {
        MarkdownFileDocument(text: makeMarkdown(
            brief: brief,
            outputs: outputs,
            tasks: tasks,
            pillar: pillar,
            destinations: destinations,
            formats: formats,
            socialAccounts: socialAccounts,
            attachments: attachments,
            exportedAt: exportedAt
        ))
    }

    static func makeMarkdown(
        brief: CreativeBrief,
        outputs: [PlatformOutput],
        tasks: [CreatorTask],
        pillar: Pillar?,
        destinations: [PublishingDestination],
        formats: [PublishingFormat],
        socialAccounts: [CreatorSocialAccount],
        attachments: [CreatorAttachment],
        exportedAt: Date = Date()
    ) -> String {
        let relatedOutputs = outputs
            .filter { $0.briefID == brief.id }
            .sorted { $0.createdAt < $1.createdAt }
        let relatedTasks = tasks
            .filter { $0.briefID == brief.id }
            .sorted { lhs, rhs in
                if lhs.parentTaskID == nil, rhs.parentTaskID != nil { return true }
                if lhs.parentTaskID != nil, rhs.parentTaskID == nil { return false }
                return lhs.sortOrder < rhs.sortOrder
            }
        let relatedAttachments = attachments.filter { $0.briefID == brief.id }
        let title = clean(brief.title).isEmpty ? "Untitled post" : clean(brief.title)
        let premise = clean(brief.premise)
        let notes = clean(brief.notes)

        var lines: [String] = ["# \(title)", ""]
        if !premise.isEmpty {
            lines += premise.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }
            lines.append("")
        }

        lines += ["## Overview", ""]
        lines.append("- **Status:** \(overallStatus(brief: brief, outputs: relatedOutputs))")
        if let pillar, !clean(pillar.name).isEmpty {
            lines.append("- **Pillar:** \(clean(pillar.name))")
        }
        if let workDate = brief.workDate {
            lines.append("- **Work date:** \(dateLabel(workDate, includesTime: brief.includesWorkTime))")
        }
        if brief.durationSeconds > 0 {
            lines.append("- **Duration:** \(durationLabel(brief.durationSeconds))")
        }
        if !brief.audience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- **Audience:** \(clean(brief.audience))")
        }
        if !brief.creativeGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- **Goal:** \(clean(brief.creativeGoal))")
        }
        if !brief.takeaway.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- **Takeaway:** \(clean(brief.takeaway))")
        }
        lines.append("")

        appendSection("Hook", text: brief.spokenHook, to: &lines)
        appendSection("First-frame text", text: brief.firstFrameText, to: &lines)

        let scriptBeats = brief.scriptBeats.map(clean).filter { !$0.isEmpty }
        if !scriptBeats.isEmpty {
            lines += ["## Script", ""]
            for (index, beat) in scriptBeats.enumerated() {
                lines.append("\(index + 1). \(beat)")
            }
            lines.append("")
        }

        appendSection("Ending", text: brief.close, to: &lines)
        appendSection("Call to action", text: brief.ctaIntent, to: &lines)
        appendSection("Notes", text: notes, to: &lines)

        if !relatedOutputs.isEmpty {
            lines += ["## Platform versions", ""]
            for output in relatedOutputs {
                let destination = destinations.first { $0.id == output.destinationID }
                let format = formats.first { $0.id == output.formatID }
                let account = socialAccounts.first { $0.id == output.socialAccountID }
                let platformTitle = platformLabel(output: output, destination: destination, format: format)
                lines += ["### \(platformTitle)", ""]
                lines.append("- **Status:** \(outputStatusTitle(output.status))")
                if let targetDate = output.targetDate {
                    lines.append("- **Publish:** \(dateLabel(targetDate, includesTime: output.includesTargetTime))")
                }
                if output.durationSeconds > 0 {
                    lines.append("- **Duration:** \(durationLabel(output.durationSeconds))")
                }
                if let account, !clean(account.label).isEmpty {
                    lines.append("- **Account:** \(clean(account.label))")
                }
                if output.recurrence != .none {
                    lines.append("- **Series:** \(seriesLabel(output))")
                }
                lines.append("")

                appendSubsection("Platform title", text: output.titleOverride, to: &lines)
                appendSubsection("Caption", text: output.caption, to: &lines)
                appendSubsection("Opening adjustment", text: output.openingAdjustment, to: &lines)
                appendSubsection("Platform CTA", text: output.cta, to: &lines)
                appendSubsection("Edit notes", text: output.editChanges, to: &lines)
                if !clean(output.publishedURLString).isEmpty {
                    lines += ["#### Published link", "", clean(output.publishedURLString), ""]
                }
            }
        }

        let productionItems = [
            ("Filming", brief.filmingGuidance),
            ("Editing", brief.editingGuidance)
        ].filter { !clean($0.1).isEmpty }
        if !productionItems.isEmpty {
            lines += ["## Production", ""]
            for item in productionItems {
                lines += ["### \(item.0)", "", clean(item.1), ""]
            }
        }

        appendBrandCollaboration(brief: brief, attachments: relatedAttachments, to: &lines)
        appendTasks(relatedTasks, to: &lines)
        appendAttachments(relatedAttachments, to: &lines)

        lines += [
            "---",
            "Exported from agent.cy on \(exportedAt.formatted(date: .long, time: .shortened)).",
            ""
        ]
        return collapseBlankLines(lines).joined(separator: "\n")
    }

    static func defaultFileName(for brief: CreativeBrief) -> String {
        let rawTitle = clean(brief.title).isEmpty ? "agentcy-post" : clean(brief.title)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let sanitized = String(rawTitle.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
            .lowercased()
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(String((trimmed.isEmpty ? "agentcy-post" : trimmed).prefix(80))).md"
    }

    private static func appendSection(_ title: String, text: String, to lines: inout [String]) {
        let text = clean(text)
        guard !text.isEmpty else { return }
        lines += ["## \(title)", "", text, ""]
    }

    private static func appendSubsection(_ title: String, text: String, to lines: inout [String]) {
        let text = clean(text)
        guard !text.isEmpty else { return }
        lines += ["#### \(title)", "", text, ""]
    }

    private static func appendTasks(_ tasks: [CreatorTask], to lines: inout [String]) {
        let topLevel = tasks.filter { $0.parentTaskID == nil }
        guard !topLevel.isEmpty else { return }
        lines += ["## Tasks", ""]
        for task in topLevel {
            var metadata: [String] = [task.kind.title]
            if task.priority.normalized != .none { metadata.append(task.priority.title) }
            if task.isSkipped { metadata.append("Skipped") }
            if let targetDate = task.targetDate {
                metadata.append(dateLabel(targetDate, includesTime: task.includesTargetTime))
            }
            let suffix = metadata.isEmpty ? "" : " — \(metadata.joined(separator: " · "))"
            lines.append("- [\(task.isCompleted ? "x" : " ")] \(clean(task.title))\(suffix)")
            for child in tasks.filter({ $0.parentTaskID == task.id }) {
                lines.append("  - [\(child.isCompleted ? "x" : " ")] \(clean(child.title))")
            }
        }
        lines.append("")
    }

    private static func appendBrandCollaboration(
        brief: CreativeBrief,
        attachments: [CreatorAttachment],
        to lines: inout [String]
    ) {
        guard brief.isBrandCollaboration else { return }
        lines += ["## Brand collaboration", ""]
        if !clean(brief.brandName).isEmpty { lines.append("- **Partner:** \(clean(brief.brandName))") }
        lines.append("- **Compensation:** \(compensationLabel(brief))")
        if brief.brandHasNetTerms { lines.append("- **Payment terms:** Net \(brief.brandNetTermsDays)") }
        if !clean(brief.giftedProductDescription).isEmpty {
            lines.append("- **Gifted product:** \(clean(brief.giftedProductDescription))")
        }
        if !clean(brief.promoCode).isEmpty { lines.append("- **Promo code:** \(clean(brief.promoCode))") }
        if !clean(brief.promoLinkString).isEmpty { lines.append("- **Promo link:** \(clean(brief.promoLinkString))") }
        let collaborationFiles = attachments.filter { $0.ownerKind == .collaborationFile }
        if !collaborationFiles.isEmpty {
            lines.append("- **Files:** \(collaborationFiles.map(\.fileName).joined(separator: ", "))")
        }
        lines.append("")
    }

    private static func appendAttachments(_ attachments: [CreatorAttachment], to lines: inout [String]) {
        let visible = attachments.filter { $0.ownerKind != .collaborationFile }
        guard !visible.isEmpty else { return }
        lines += ["## Assets", ""]
        for attachment in visible {
            let label: String = switch attachment.ownerKind {
            case .referenceFile: "Reference"
            case .postMedia: "Post media"
            case .moodBoardMedia: "Mood board"
            case .collaborationFile: "Collaboration file"
            }
            lines.append("- **\(label):** \(attachment.fileName)")
        }
        lines.append("")
    }

    private static func compensationLabel(_ brief: CreativeBrief) -> String {
        let paid: String = if let amount = brief.compensationAmount {
            amount.formatted(.currency(code: brief.compensationCurrencyCode.isEmpty ? "USD" : brief.compensationCurrencyCode))
        } else {
            "Paid"
        }
        return switch brief.compensationType {
        case .paid: paid
        case .gifted: "Gifted"
        case .both: "\(paid) + gifted"
        }
    }

    private static func overallStatus(brief: CreativeBrief, outputs: [PlatformOutput]) -> String {
        if !outputs.isEmpty {
            if outputs.allSatisfy({ $0.status == .posted }) { return "Posted" }
            if outputs.contains(where: { $0.status == .scheduled }) { return "Scheduled" }
            if outputs.contains(where: { $0.status == .ready }) { return "Ready" }
            return "Draft"
        }
        return brief.status == .scheduled ? "Scheduled" : brief.status.title
    }

    private static func outputStatusTitle(_ status: PlatformOutputStatus) -> String {
        switch status {
        case .draft: "Draft"
        case .ready: "Ready"
        case .scheduled: "Scheduled"
        case .posted: "Posted"
        }
    }

    private static func platformLabel(
        output: PlatformOutput,
        destination: PublishingDestination?,
        format: PublishingFormat?
    ) -> String {
        switch (destination, format) {
        case let (.some(destination), .some(format)): "\(destination.name) · \(format.name)"
        case let (.some(destination), .none): destination.name
        case let (.none, .some(format)): format.name
        case (.none, .none): output.platform.title
        }
    }

    private static func seriesLabel(_ output: PlatformOutput) -> String {
        let name = clean(output.seriesName)
        return name.isEmpty ? output.recurrence.title : "\(name) · \(output.recurrence.title)"
    }

    private static func durationLabel(_ seconds: Int) -> String {
        seconds < 120 ? "\(seconds) seconds" : "\(seconds / 60) minutes"
    }

    private static func dateLabel(_ date: Date, includesTime: Bool) -> String {
        if includesTime {
            return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseBlankLines(_ lines: [String]) -> [String] {
        lines.reduce(into: [String]()) { result, line in
            guard !(line.isEmpty && result.last?.isEmpty == true) else { return }
            result.append(line)
        }
    }
}

private enum StoredZIP {
    struct Entry {
        let path: String
        let data: Data
    }

    static func make(entries: [Entry]) -> Data {
        struct CentralRecord {
            let entry: Entry
            let checksum: UInt32
            let offset: UInt32
        }

        var archive = Data()
        var centralRecords: [CentralRecord] = []
        for entry in entries {
            let name = Data(entry.path.utf8)
            let checksum = CRC32.checksum(entry.data)
            let offset = UInt32(archive.count)
            archive.appendLE(UInt32(0x04034B50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(checksum)
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt16(name.count))
            archive.appendLE(UInt16(0))
            archive.append(name)
            archive.append(entry.data)
            centralRecords.append(.init(entry: entry, checksum: checksum, offset: offset))
        }

        let centralOffset = UInt32(archive.count)
        for record in centralRecords {
            let name = Data(record.entry.path.utf8)
            archive.appendLE(UInt32(0x02014B50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(record.checksum)
            archive.appendLE(UInt32(record.entry.data.count))
            archive.appendLE(UInt32(record.entry.data.count))
            archive.appendLE(UInt16(name.count))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt32(0))
            archive.appendLE(record.offset)
            archive.append(name)
        }
        let centralSize = UInt32(archive.count) - centralOffset
        archive.appendLE(UInt32(0x06054B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(centralRecords.count))
        archive.appendLE(UInt16(centralRecords.count))
        archive.appendLE(centralSize)
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0))
        return archive
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
