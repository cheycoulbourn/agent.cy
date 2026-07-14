import Foundation
import SwiftData

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

        let object: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "schemaVersion": 10,
            "profiles": profiles.map { [
                "id": $0.id.uuidString,
                "name": $0.name,
                "goal": $0.goal,
                "platforms": $0.selectedPlatforms.map(\.rawValue),
                "assistanceMode": $0.assistanceMode.rawValue
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
                    "postedAt": output.postedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
                ] as [String: Any]
            },
            "tasks": tasks.map { task in
                [
                    "id": task.id.uuidString,
                    "briefID": task.briefID?.uuidString ?? NSNull(),
                    "parentTaskID": task.parentTaskID?.uuidString ?? NSNull(),
                    "title": task.title,
                    "kind": task.kind.rawValue,
                    "priority": task.priority.rawValue,
                    "notes": task.notes,
                    "estimatedMinutes": task.estimatedMinutes ?? NSNull(),
                    "isCompleted": task.isCompleted,
                    "targetDate": task.targetDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "dailyFocusDate": task.dailyFocusDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                    "dailyFocusTitle": task.dailyFocusTitle ?? NSNull(),
                    "dailyFocusTemplateEntryID": task.dailyFocusTemplateEntryID?.uuidString ?? NSNull(),
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
            "reminderSettings": reminders.map { ["id": $0.id.uuidString, "dailyEnabled": $0.dailyEnabled, "dailyHour": $0.dailyHour, "weeklyEnabled": $0.weeklyEnabled, "weeklyWeekday": $0.weeklyWeekday, "weeklyHour": $0.weeklyHour] as [String: Any] },
            "subscriptionStates": subscriptions.map { ["id": $0.id.uuidString, "access": $0.access.rawValue, "trialEnd": $0.trialEnd.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(), "freeBriefConsumed": $0.freeBriefConsumed, "ideationRequestsUsed": $0.ideationRequestsUsed, "revisionRequestsUsed": $0.revisionRequestsUsed, "teachCyUpdatesUsed": $0.teachCyUpdatesUsed] as [String: Any] }
            ,"publishingDestinations": destinations.map { ["id": $0.id.uuidString, "name": $0.name, "builtInKind": $0.builtInKindRaw, "isArchived": $0.isArchived] as [String: Any] }
            ,"publishingFormats": formats.map { ["id": $0.id.uuidString, "destinationID": $0.destinationID.uuidString, "name": $0.name, "kind": $0.kind.rawValue, "isArchived": $0.isArchived] as [String: Any] }
            ,"socialAccounts": socialAccounts.map { ["id": $0.id.uuidString, "profileID": $0.profileID.uuidString, "destinationID": $0.destinationID.uuidString, "label": $0.label, "profileURL": $0.profileURLString, "isPrimary": $0.isPrimary, "isArchived": $0.isArchived] as [String: Any] }
            ,"dailyFocusTemplates": focusTemplates.map { ["id": $0.id.uuidString, "weekday": $0.weekday.rawValue, "kind": $0.kind.rawValue, "title": $0.title, "note": $0.note] as [String: Any] }
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
            ,"attachments": attachments.map { ["id": $0.id.uuidString, "briefID": $0.briefID.uuidString, "fileName": $0.fileName, "kind": $0.kind.rawValue, "contentType": $0.uniformTypeIdentifier, "byteCount": $0.byteCount] as [String: Any] }
        ]

        let json = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let markdown = makeMarkdown(briefs: briefs, outputs: outputs, tasks: tasks)
        var entries: [StoredZIP.Entry] = [
            .init(path: "agentcy-export.json", data: json),
            .init(path: "briefs.md", data: Data(markdown.utf8))
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
        var lines = ["# agent.cy brief export", "", "Exported \(Date().formatted(date: .long, time: .shortened))", ""]
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
                    let parentLine = "- [\(task.isCompleted ? "x" : " ")] \(task.title) (\(task.kind.title))"
                    let childLines = allBriefTasks
                        .filter { $0.parentTaskID == task.id }
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map { "  - [\($0.isCompleted ? "x" : " ")] \($0.title)" }
                    return [parentLine] + childLines
                }
            if !briefTasks.isEmpty {
                lines += ["### Tasks"] + briefTasks + [""]
            }
        }
        return lines.joined(separator: "\n")
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
