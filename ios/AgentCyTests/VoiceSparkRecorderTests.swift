#if !targetEnvironment(macCatalyst)
import AVFoundation
@testable import AgentCy
import XCTest

@MainActor
final class VoiceSparkRecorderTests: XCTestCase {
    func testAudioSessionConfigurationUsesOnlyRecordingCompatibleOptions() {
        XCTAssertEqual(VoiceSparkAudioConfiguration.category, .record)
        XCTAssertEqual(VoiceSparkAudioConfiguration.mode, .default)
        XCTAssertTrue(VoiceSparkAudioConfiguration.options.contains(.allowBluetoothHFP))
        XCTAssertFalse(VoiceSparkAudioConfiguration.options.contains(.duckOthers))
        XCTAssertFalse(VoiceSparkAudioConfiguration.options.contains(.mixWithOthers))
    }

    func testRecorderProducesAACMonoAudioForSpeechRecognition() {
        let settings = VoiceSparkAudioConfiguration.makeRecorderSettings()

        XCTAssertEqual(settings[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(settings[AVSampleRateKey] as? Int, 44_100)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }

    func testRecordingDetailSaveActivatesOnlyAfterARealTitleChange() {
        XCTAssertFalse(VoiceRecordingDetailTitlePolicy.hasChanges(
            current: "  Sunday reset  ",
            saved: "Sunday reset"
        ))
        XCTAssertTrue(VoiceRecordingDetailTitlePolicy.hasChanges(
            current: "Sunday reset ritual",
            saved: "Sunday reset"
        ))
        XCTAssertEqual(VoiceRecordingDetailTitlePolicy.normalized("  New title\n"), "New title")
    }

    func testRecordingDetailDeleteLetsOwningPostHandleTheSingleNavigationPop() {
        XCTAssertEqual(
            VoiceRecordingDetailNavigationPolicy.decision(for: .delete),
            VoiceRecordingDetailNavigationDecision(
                dismissesDetail: false,
                deletesRecording: true
            )
        )
        XCTAssertEqual(
            VoiceRecordingDetailNavigationPolicy.decision(for: .back),
            VoiceRecordingDetailNavigationDecision(
                dismissesDetail: true,
                deletesRecording: false
            )
        )
    }

    func testSwipeDeleteBlocksRecordingActionsDuringAndAfterHorizontalReveal() {
        XCTAssertTrue(AgentSwipeDeleteInteractionPolicy.isHorizontalIntent(
            CGSize(width: -24, height: 4)
        ))
        XCTAssertFalse(AgentSwipeDeleteInteractionPolicy.isHorizontalIntent(
            CGSize(width: 4, height: 24)
        ))
        XCTAssertFalse(AgentSwipeDeleteInteractionPolicy.blocksContent(
            isRevealed: false,
            isHorizontalDragActive: false,
            isReleaseSuppressed: false
        ))
        XCTAssertTrue(AgentSwipeDeleteInteractionPolicy.blocksContent(
            isRevealed: false,
            isHorizontalDragActive: true,
            isReleaseSuppressed: false
        ))
        XCTAssertTrue(AgentSwipeDeleteInteractionPolicy.blocksContent(
            isRevealed: true,
            isHorizontalDragActive: false,
            isReleaseSuppressed: false
        ))
        XCTAssertTrue(AgentSwipeDeleteInteractionPolicy.blocksContent(
            isRevealed: false,
            isHorizontalDragActive: false,
            isReleaseSuppressed: true
        ))
    }

    func testRecordingDownloadNameUsesTitleDateAndPostWithoutEmoji() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 16
        )))

        XCTAssertEqual(
            VoiceRecordingExportNaming.fileName(
                title: "🎙️ Sunday / reset",
                recordedAt: date,
                postTitle: "✨ No scroll Sundays",
                calendar: calendar
            ),
            "Sunday reset - 2026-08-16 - No scroll Sundays.m4a"
        )
        XCTAssertEqual(
            VoiceRecordingExportNaming.fileName(
                title: nil,
                recordedAt: date,
                postTitle: nil,
                calendar: calendar
            ),
            "Voice recording - 2026-08-16.m4a"
        )
    }

    func testRecordingStorePersistsOriginalAudioAndConnection() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("capture.m4a")
        let audio = Data("full-resolution-audio".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try audio.write(to: source)
        let workspaceID = UUID()
        let briefID = UUID()

        let saved = try VoiceSparkRecordingStore.save(
            temporaryURL: source,
            workspaceID: workspaceID,
            transcript: "A useful thought",
            durationSeconds: 12.4,
            rootURL: root
        )

        XCTAssertEqual(try VoiceSparkRecordingStore.audioData(for: saved, rootURL: root), audio)
        XCTAssertEqual(try VoiceSparkRecordingStore.load(rootURL: root), [saved])
        XCTAssertNil(saved.title)

        let legacyCompatibleData = try JSONEncoder().encode(saved)
        XCTAssertNil(try JSONDecoder().decode(VoiceSparkRecording.self, from: legacyCompatibleData).title)

        let titled = try VoiceSparkRecordingStore.updateTitle(
            recordingID: saved.id,
            title: "  Sunday reset  ",
            rootURL: root
        )
        XCTAssertEqual(titled.title, "Sunday reset")
        XCTAssertEqual(try VoiceSparkRecordingStore.load(rootURL: root).first?.title, "Sunday reset")

        let connected = try VoiceSparkRecordingStore.connect(
            recordingID: saved.id,
            briefID: briefID,
            briefTitle: "Linked idea",
            placement: .idea,
            rootURL: root
        )

        XCTAssertEqual(connected.linkedBriefID, briefID)
        XCTAssertEqual(connected.linkedBriefTitle, "Linked idea")
        XCTAssertEqual(connected.linkedPlacement, .idea)

        try VoiceSparkRecordingStore.remove(recordingID: saved.id, rootURL: root)
        XCTAssertTrue(try VoiceSparkRecordingStore.load(rootURL: root).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(saved.fileName).path))
    }

    func testRecordingStoreClearsOnlyRequestedWorkspace() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("capture.m4a")
        try Data("audio".utf8).write(to: source)
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()
        let first = try VoiceSparkRecordingStore.save(
            temporaryURL: source,
            workspaceID: firstWorkspaceID,
            transcript: "First",
            durationSeconds: 3,
            rootURL: root
        )
        let second = try VoiceSparkRecordingStore.save(
            temporaryURL: source,
            workspaceID: secondWorkspaceID,
            transcript: "Second",
            durationSeconds: 4,
            rootURL: root
        )

        try VoiceSparkRecordingStore.clear(workspaceID: firstWorkspaceID, rootURL: root)

        XCTAssertEqual(try VoiceSparkRecordingStore.load(rootURL: root), [second])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.fileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(second.fileName).path))
    }

    func testPostVoiceRecordingPolicyFindsBriefLevelAudioWithoutPlatformOutput() {
        let briefID = UUID()
        let voiceRecording = CreatorAttachment(
            ownerKind: .referenceFile,
            briefID: briefID,
            fileName: "voice-spark.m4a",
            kind: .other,
            uniformTypeIdentifier: "public.mpeg-4-audio",
            byteCount: 42,
            localRelativePath: "",
            cloudData: Data("audio".utf8),
            syncState: .synced
        )
        let referenceDocument = CreatorAttachment(
            ownerKind: .referenceFile,
            briefID: briefID,
            fileName: "brief.pdf",
            kind: .document,
            uniformTypeIdentifier: "com.adobe.pdf",
            byteCount: 12,
            localRelativePath: ""
        )
        let collaborationAudio = CreatorAttachment(
            ownerKind: .collaborationFile,
            briefID: briefID,
            fileName: "interview.m4a",
            kind: .other,
            uniformTypeIdentifier: "public.mpeg-4-audio",
            byteCount: 18,
            localRelativePath: ""
        )
        let anotherPostRecording = CreatorAttachment(
            ownerKind: .referenceFile,
            briefID: UUID(),
            fileName: "another.m4a",
            kind: .other,
            uniformTypeIdentifier: "public.mpeg-4-audio",
            byteCount: 20,
            localRelativePath: ""
        )

        let recordings = PostVoiceRecordingPolicy.recordings(
            from: [referenceDocument, collaborationAudio, anotherPostRecording, voiceRecording],
            briefID: briefID
        )

        XCTAssertEqual(recordings.map(\.id), [voiceRecording.id])
        XCTAssertNil(voiceRecording.platformOutputID)
        XCTAssertEqual(PostVoiceRecordingPolicy.displayTitle(voiceRecording), "Voice recording")

        voiceRecording.displayTitle = "Sunday reset"
        XCTAssertEqual(PostVoiceRecordingPolicy.displayTitle(voiceRecording), "Sunday reset")
    }

    func testVoiceSparkContentStaysUnfiledAndLinkedPostFinishesWithoutCreatingSeparateIdea() {
        let workspaceID = UUID()
        let unlinked = VoiceSparkRecording(
            id: UUID(),
            workspaceID: workspaceID,
            createdAt: Date(),
            durationSeconds: 5,
            transcript: "Unlinked",
            fileName: "unlinked.m4a",
            linkedBriefID: nil,
            linkedBriefTitle: nil,
            linkedPlacement: nil
        )
        var linkedPost = unlinked
        linkedPost.id = UUID()
        linkedPost.fileName = "linked.m4a"
        linkedPost.linkedBriefID = UUID()
        linkedPost.linkedBriefTitle = "Post"
        linkedPost.linkedPlacement = .post

        XCTAssertNil(VoiceSparkSessionPolicy.capturedContentPillarID)
        XCTAssertTrue(VoiceSparkSessionPolicy.shouldCreateSeparateIdea(for: [unlinked]))
        XCTAssertFalse(VoiceSparkSessionPolicy.shouldCreateSeparateIdea(for: [linkedPost]))
        XCTAssertTrue(VoiceSparkSessionPolicy.shouldOpenPost(afterConnectingTo: .post))
        XCTAssertFalse(VoiceSparkSessionPolicy.shouldOpenPost(afterConnectingTo: .idea))
        XCTAssertTrue(VoiceSparkSessionPolicy.canSave(
            autoLinksToPost: true,
            transcript: "",
            recordingCount: 1,
            isBusy: false
        ))
        XCTAssertFalse(VoiceSparkSessionPolicy.canSave(
            autoLinksToPost: true,
            transcript: "Typed notes only",
            recordingCount: 0,
            isBusy: false
        ))
        XCTAssertTrue(VoiceSparkSessionPolicy.canSave(
            autoLinksToPost: false,
            transcript: "An unlinked thought",
            recordingCount: 0,
            isBusy: false
        ))

        let linkedIdea = VoiceSparkRecording(
            id: UUID(),
            workspaceID: workspaceID,
            createdAt: Date(),
            durationSeconds: 4,
            transcript: "Linked idea",
            fileName: "idea.m4a",
            linkedBriefID: UUID(),
            linkedBriefTitle: "Idea",
            linkedPlacement: .idea
        )
        XCTAssertEqual(
            VoiceSparkSessionPolicy.libraryRecordings(
                from: [linkedPost, unlinked, linkedIdea],
                workspaceID: workspaceID
            ).map(\.id),
            [unlinked.id, linkedIdea.id]
        )
        XCTAssertTrue(VoiceSparkSessionPolicy.shouldShowFreshActions(
            for: unlinked.id,
            sessionRecordingIDs: [unlinked.id],
            autoLinksToPost: false
        ))
        XCTAssertFalse(VoiceSparkSessionPolicy.shouldShowFreshActions(
            for: unlinked.id,
            sessionRecordingIDs: [],
            autoLinksToPost: false
        ))
        XCTAssertFalse(VoiceSparkSessionPolicy.shouldShowFreshActions(
            for: unlinked.id,
            sessionRecordingIDs: [unlinked.id],
            autoLinksToPost: true
        ))

        let current = VoiceSparkSessionPolicy.currentRecordings(
            from: [unlinked, linkedPost],
            sessionRecordingIDs: [linkedPost.id],
            workspaceID: workspaceID
        )
        XCTAssertEqual(current, [linkedPost])
        XCTAssertEqual(
            VoiceSparkSessionPolicy.actionRecordings(
                from: [unlinked, linkedIdea],
                selected: linkedIdea.id,
                sessionRecordingIDs: [unlinked.id]
            ),
            [linkedIdea]
        )
        XCTAssertEqual(
            VoiceSparkSessionPolicy.actionRecordings(
                from: [unlinked, linkedIdea],
                selected: unlinked.id,
                sessionRecordingIDs: [unlinked.id]
            ),
            [unlinked]
        )
    }

    func testConnectRecordingListsOnlyOpenPostsInAgendaOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 17,
            hour: 12
        )))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        let upcomingBrief = CreativeBrief(title: "Upcoming", status: .developing)
        upcomingBrief.ideaBankPlacement = .post
        upcomingBrief.workDate = tomorrow
        let upcomingOutput = PlatformOutput(briefID: upcomingBrief.id, status: .draft)

        let pastBrief = CreativeBrief(title: "Past", status: .developing)
        pastBrief.ideaBankPlacement = .post
        pastBrief.workDate = yesterday
        let pastOutput = PlatformOutput(briefID: pastBrief.id, status: .draft)

        let undatedBrief = CreativeBrief(title: "Undated", status: .developing)
        undatedBrief.ideaBankPlacement = .post
        let undatedOutput = PlatformOutput(briefID: undatedBrief.id, status: .draft)

        let idea = CreativeBrief(title: "Idea", status: .developing)
        idea.ideaBankPlacement = .idea
        let ideaOutput = PlatformOutput(briefID: idea.id, status: .draft)

        let scheduledBrief = CreativeBrief(title: "Scheduled", status: .scheduled)
        scheduledBrief.ideaBankPlacement = .post
        let scheduledOutput = PlatformOutput(briefID: scheduledBrief.id, status: .scheduled)

        let posts = VoiceSparkConnectPostPolicy.posts(
            briefs: [pastBrief, idea, undatedBrief, scheduledBrief, upcomingBrief],
            outputs: [ideaOutput, scheduledOutput, undatedOutput, pastOutput, upcomingOutput],
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(posts.map(\.brief.id), [
            upcomingBrief.id,
            pastBrief.id,
            undatedBrief.id,
        ])
        XCTAssertEqual(posts.map(\.dateKind), [.work, .work, nil])
    }

    func testConnectRecordingUsesPostDateWhenWorkAndScheduledDatesShareADay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 9
        )))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 18,
            hour: 18
        )))
        let brief = CreativeBrief(title: "Same day", status: .developing)
        brief.ideaBankPlacement = .post
        brief.workDate = morning
        let output = PlatformOutput(briefID: brief.id, status: .draft)
        output.targetDate = evening

        let post = try XCTUnwrap(VoiceSparkConnectPostPolicy.posts(
            briefs: [brief],
            outputs: [output],
            now: morning,
            calendar: calendar
        ).first)

        XCTAssertEqual(post.date, evening)
        XCTAssertEqual(post.dateKind, .post)
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-spark-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
#endif
