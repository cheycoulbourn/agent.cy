import Foundation
import SwiftData

enum PrivacyEraseCompletionReason: Equatable {
    case live
    case resumed
    case localOnlyMissingService
    case localOnlyServerUnavailable
    case localOnlyMissingCredential
}

enum PrivacyErasePauseReason: Equatable {
    case unreadableCredential(String)
    case missingPrivacyService
    case serverDeletionFailed(String)
    case missingCredential
    case localDeletionFailed(String)
    case cleanupFailed(String)
    case credentialDeletionFailed(String)

    var followsLocalDeletion: Bool {
        switch self {
        case .cleanupFailed, .credentialDeletionFailed:
            true
        default:
            false
        }
    }
}

enum PrivacyEraseOutcome: Equatable {
    case notNeeded
    case completed(reason: PrivacyEraseCompletionReason, deletedLocalData: Bool)
    case paused(reason: PrivacyErasePauseReason, deletedLocalData: Bool, credentialPresent: Bool?)
}

@MainActor
protocol ExportArchiveCleaning {
    func removeArchives(currentExportURL: URL?) throws
}

@MainActor
struct LocalExportArchiveCleaner: ExportArchiveCleaning {
    func removeArchives(currentExportURL: URL?) throws {
        let fileManager = FileManager.default
        if let currentExportURL, fileManager.fileExists(atPath: currentExportURL.path) {
            try fileManager.removeItem(at: currentExportURL)
        }
        let candidates = try fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for candidate in candidates
        where candidate.lastPathComponent.hasPrefix("agentcy-export-") && candidate.pathExtension == "zip" {
            try fileManager.removeItem(at: candidate)
        }
    }
}

@MainActor
final class PrivacyEraseCoordinator {
    private let credentialStore: any InstallationCredentialStoring
    private let privacyDeletionService: (any PrivacyDeletionServicing)?
    private let progressStore: any PrivacyEraseProgressStoring
    private let localDataEraser: any LocalCreatorDataErasing
    private let reminderService: any ReminderServicing
    private let calendarSyncService: any CalendarSyncServicing
    private let archiveCleaner: any ExportArchiveCleaning
    private let allowsOfflineErase: Bool

    init(
        credentialStore: any InstallationCredentialStoring,
        privacyDeletionService: (any PrivacyDeletionServicing)?,
        progressStore: any PrivacyEraseProgressStoring,
        localDataEraser: any LocalCreatorDataErasing,
        reminderService: any ReminderServicing,
        calendarSyncService: any CalendarSyncServicing,
        archiveCleaner: any ExportArchiveCleaning = LocalExportArchiveCleaner(),
        allowsOfflineErase: Bool
    ) {
        self.credentialStore = credentialStore
        self.privacyDeletionService = privacyDeletionService
        self.progressStore = progressStore
        self.localDataEraser = localDataEraser
        self.reminderService = reminderService
        self.calendarSyncService = calendarSyncService
        self.archiveCleaner = archiveCleaner
        self.allowsOfflineErase = allowsOfflineErase
    }

    func resumeIfNeeded(context: ModelContext, currentExportURL: URL?) async -> PrivacyEraseOutcome {
        guard let checkpoint = progressStore.checkpoint else { return .notNeeded }
        let identity: InstallationIdentity?
        do {
            identity = try await credentialStore.load()
        } catch {
            return .paused(
                reason: .unreadableCredential(error.localizedDescription),
                deletedLocalData: false,
                credentialPresent: nil
            )
        }
        guard let identity else {
            return .paused(reason: .missingCredential, deletedLocalData: false, credentialPresent: false)
        }
        if identity.installationID != checkpoint.installationID {
            progressStore.clear()
            return .notNeeded
        }
        return await finish(
            checkpoint: checkpoint,
            context: context,
            currentExportURL: currentExportURL,
            completionReason: .resumed,
            credentialPresent: true
        )
    }

    func eraseAll(context: ModelContext, currentExportURL: URL?) async -> PrivacyEraseOutcome {
        let checkpoint = progressStore.checkpoint
        let identity: InstallationIdentity?
        do {
            identity = try await credentialStore.load()
        } catch {
            return .paused(
                reason: .unreadableCredential(error.localizedDescription),
                deletedLocalData: false,
                credentialPresent: nil
            )
        }

        if let savedCheckpoint = checkpoint {
            guard let identity else {
                return .paused(reason: .missingCredential, deletedLocalData: false, credentialPresent: false)
            }
            if identity.installationID != savedCheckpoint.installationID {
                progressStore.clear()
            } else {
                return await finish(
                    checkpoint: savedCheckpoint,
                    context: context,
                    currentExportURL: currentExportURL,
                    completionReason: .resumed,
                    credentialPresent: true
                )
            }
        }

        guard let identity else {
            guard allowsOfflineErase else {
                return .paused(reason: .missingCredential, deletedLocalData: false, credentialPresent: false)
            }
            return await finish(
                checkpoint: nil,
                context: context,
                currentExportURL: currentExportURL,
                completionReason: .localOnlyMissingCredential,
                credentialPresent: false,
                shouldDeleteCredential: false
            )
        }

        guard let privacyDeletionService else {
            guard allowsOfflineErase else {
                return .paused(reason: .missingPrivacyService, deletedLocalData: false, credentialPresent: true)
            }
            return await finish(
                checkpoint: nil,
                installationID: identity.installationID,
                context: context,
                currentExportURL: currentExportURL,
                completionReason: .localOnlyMissingService,
                credentialPresent: true
            )
        }

        do {
            _ = try await privacyDeletionService.deleteServerMetadata(for: identity)
            progressStore.markServerDeleted(installationID: identity.installationID)
        } catch {
            guard allowsOfflineErase else {
                return .paused(
                    reason: .serverDeletionFailed(error.localizedDescription),
                    deletedLocalData: false,
                    credentialPresent: true
                )
            }
            return await finish(
                checkpoint: nil,
                installationID: identity.installationID,
                context: context,
                currentExportURL: currentExportURL,
                completionReason: .localOnlyServerUnavailable,
                credentialPresent: true
            )
        }

        return await finish(
            checkpoint: progressStore.checkpoint,
            installationID: identity.installationID,
            context: context,
            currentExportURL: currentExportURL,
            completionReason: .live,
            credentialPresent: true
        )
    }

    private func finish(
        checkpoint: PrivacyEraseCheckpoint?,
        installationID: UUID? = nil,
        context: ModelContext,
        currentExportURL: URL?,
        completionReason: PrivacyEraseCompletionReason,
        credentialPresent: Bool,
        shouldDeleteCredential: Bool = true
    ) async -> PrivacyEraseOutcome {
        let resolvedInstallationID = checkpoint?.installationID ?? installationID
        var deletedLocalData = false
        if checkpoint?.phase != .localDataDeleted {
            do {
                try await localDataEraser.eraseAll(context: context)
            } catch {
                context.rollback()
                return .paused(
                    reason: .localDeletionFailed(error.localizedDescription),
                    deletedLocalData: false,
                    credentialPresent: credentialPresent
                )
            }
            deletedLocalData = true
            if let resolvedInstallationID {
                progressStore.markLocalDataDeleted(installationID: resolvedInstallationID)
            }
        }

        await reminderService.cancelAll()
        do {
            try calendarSyncService.disconnect()
        } catch {
            return .paused(
                reason: .cleanupFailed("Calendar cleanup failed: \(error.localizedDescription)"),
                deletedLocalData: deletedLocalData,
                credentialPresent: credentialPresent
            )
        }
        await AIOperationIDRegistry.shared.removeAll()
        do {
            try archiveCleaner.removeArchives(currentExportURL: currentExportURL)
        } catch {
            return .paused(
                reason: .cleanupFailed("Export cleanup failed: \(error.localizedDescription)"),
                deletedLocalData: deletedLocalData,
                credentialPresent: credentialPresent
            )
        }

        if shouldDeleteCredential {
            do {
                try await credentialStore.delete()
            } catch {
                return .paused(
                    reason: .credentialDeletionFailed(error.localizedDescription),
                    deletedLocalData: deletedLocalData,
                    credentialPresent: true
                )
            }
        }
        progressStore.clear()
        return .completed(reason: completionReason, deletedLocalData: deletedLocalData)
    }
}
