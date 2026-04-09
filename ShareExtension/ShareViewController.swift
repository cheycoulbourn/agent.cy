import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let group = DispatchGroup()

        for item in items {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                        if let url = item as? URL {
                            self?.saveInspiration(type: "link", content: url.absoluteString)
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.text.identifier) { [weak self] item, _ in
                        if let text = item as? String {
                            self?.saveInspiration(type: "text", content: text)
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, _ in
                        if let url = item as? URL {
                            self?.saveImageInspiration(from: url)
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveInspiration(type: String, content: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.agentcy"
        ) else { return }

        let pendingDir = containerURL.appendingPathComponent("PendingInspirations", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        let inspiration: [String: Any] = [
            "id": UUID().uuidString,
            "type": type,
            "content": content,
            "note": contentText ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        let filename = "\(UUID().uuidString).json"
        let fileURL = pendingDir.appendingPathComponent(filename)

        if let data = try? JSONSerialization.data(withJSONObject: inspiration) {
            try? data.write(to: fileURL)
        }
    }

    private func saveImageInspiration(from url: URL) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.agentcy"
        ) else { return }

        let mediaDir = containerURL.appendingPathComponent("SharedMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        let imageID = UUID().uuidString
        let destination = mediaDir.appendingPathComponent("\(imageID).jpg")
        try? FileManager.default.copyItem(at: url, to: destination)

        saveInspiration(type: "image", content: destination.lastPathComponent)
    }

    override func configurationItems() -> [Any]! {
        []
    }
}
