import Foundation
import SwiftData
import UIKit

enum PublishedPostThumbnailPolicy {
    static let generatedFileNamePrefix = "published-thumbnail-"

    static func isGeneratedLinkThumbnail(_ attachment: CreatorAttachment) -> Bool {
        attachment.ownerKind == .postMedia &&
            attachment.fileName.hasPrefix(generatedFileNamePrefix)
    }

    static func taskKey(output: PlatformOutput) -> String {
        "\(output.status.rawValue):\(output.publishedURLString.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

@MainActor
struct PublishedPostThumbnailHydrator {
    private let metadataService: any PostLinkMetadataFetching

    init(metadataService: any PostLinkMetadataFetching = PostLinkMetadataService()) {
        self.metadataService = metadataService
    }

    @discardableResult
    func hydrate(
        brief: CreativeBrief,
        output: PlatformOutput,
        context: ModelContext
    ) async -> CreatorAttachment? {
        guard output.status == .posted,
              let descriptor = LivePostURLPolicy.descriptor(from: output.publishedURLString),
              canUseLinkedThumbnail(for: output, context: context)
        else { return nil }

        guard let metadata = try? await metadataService.fetch(
                  url: descriptor.url,
                  platform: descriptor.sourcePlatform
              ),
              let thumbnailData = metadata.thumbnailData,
              UIImage(data: thumbnailData) != nil,
              canUseLinkedThumbnail(for: output, context: context)
        else { return nil }

        let attachment: CreatorAttachment
        if let existing = generatedThumbnail(for: output, context: context) {
            existing.cloudData = thumbnailData
            existing.previewData = thumbnailData
            existing.byteCount = Int64(thumbnailData.count)
            existing.updatedAt = Date()
            existing.syncState = .synced
            attachment = existing
        } else {
            let created = CreatorAttachment(
                ownerKind: .postMedia,
                briefID: brief.id,
                platformOutputID: output.id,
                fileName: "\(PublishedPostThumbnailPolicy.generatedFileNamePrefix)\(output.id.uuidString.prefix(8)).jpg",
                kind: .photo,
                uniformTypeIdentifier: "public.image",
                byteCount: Int64(thumbnailData.count),
                localRelativePath: "",
                cloudData: thumbnailData,
                previewData: thumbnailData,
                isCoverOnly: true,
                syncState: .synced
            )
            created.workspaceID = output.workspaceID ?? brief.workspaceID
            context.insert(created)
            attachment = created
        }

        output.coverAttachmentID = attachment.id
        do {
            try context.save()
            return attachment
        } catch {
            return nil
        }
    }

    private func canUseLinkedThumbnail(
        for output: PlatformOutput,
        context: ModelContext
    ) -> Bool {
        postMedia(for: output, context: context).allSatisfy(
            PublishedPostThumbnailPolicy.isGeneratedLinkThumbnail
        )
    }

    private func generatedThumbnail(
        for output: PlatformOutput,
        context: ModelContext
    ) -> CreatorAttachment? {
        postMedia(for: output, context: context).first(
            where: PublishedPostThumbnailPolicy.isGeneratedLinkThumbnail
        )
    }

    private func postMedia(
        for output: PlatformOutput,
        context: ModelContext
    ) -> [CreatorAttachment] {
        let outputID = output.id
        return ((try? context.fetch(FetchDescriptor<CreatorAttachment>(
            predicate: #Predicate { $0.platformOutputID == outputID }
        ))) ?? []).filter { $0.ownerKind == .postMedia }
    }
}

enum SavedPostThumbnailHydrationPolicy {
    static func taskKey(workspaceKey: String, missingSourceIDs: [UUID]) -> String {
        let sourceKey = missingSourceIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(workspaceKey):\(sourceKey)"
    }
}

@MainActor
struct SavedPostThumbnailHydrator {
    private let metadataService: any PostLinkMetadataFetching

    init(metadataService: any PostLinkMetadataFetching = PostLinkMetadataService()) {
        self.metadataService = metadataService
    }

    @discardableResult
    func hydrate(
        source: InspirationSource,
        context: ModelContext
    ) async -> Bool {
        guard source.thumbnailData == nil,
              let url = URL(string: source.canonicalURLString),
              let metadata = try? await metadataService.fetch(
                  url: url,
                  platform: source.platform
              ),
              let thumbnailData = metadata.thumbnailData,
              UIImage(data: thumbnailData) != nil,
              source.thumbnailData == nil
        else { return false }

        source.thumbnailData = thumbnailData
        do {
            try context.save()
            return true
        } catch {
            return false
        }
    }
}
