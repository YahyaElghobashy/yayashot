import AppKit

extension MediaGalleryItem {
    func open(cloud: Bool) -> String? {
        if cloud, let cloudURL {
            return NSWorkspace.shared.open(cloudURL) ? nil : "Couldn’t open the link. Try again or copy it."
        }
        guard hasLocalFile else { return "This file was moved or deleted. Refresh the gallery." }
        PreviewOverlay.shared.show(url: previewURL, automaticallyDismiss: false)
        return nil
    }

    /// Move every owned file before changing history. A failure keeps metadata available for retry.
    func deleteLocal(history: HistoryStore = .shared, edits: ScreenshotHistoryStore = .shared,
                     trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let previewURL = previewURL
        let urls = Self.deletionTargets(deletionURLs)
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try trash(url)
        }
        try edits.forgetLocalItems(ids: Set([historyID].compactMap { $0 }))
        try history.forgetLocalRecords(ids: Set(captureIDs))
        for url in urls { PreviewOverlay.shared.remove(url) }
        PreviewOverlay.shared.remove(localURL)
        PreviewOverlay.shared.remove(previewURL)
        RecordingProjectStore.shared.reload()
    }

    static func deletionTargets(_ urls: [URL]) -> [URL] {
        let unique = Dictionary(urls.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }).values.sorted { $0.path.count < $1.path.count }
        return unique.reduce(into: [URL]()) { targets, url in
            if !targets.contains(where: { url.path.hasPrefix($0.path + "/") }) { targets.append(url) }
        }
    }

    /// YayaShot has no cloud storage. Links saved by an earlier upstream
    /// install are only forgotten locally; nothing is sent anywhere.
    func deleteCloud() async throws {
        guard let cloudURL else { return }
        try ScreenshotHistoryStore.shared.forgetCloudLink(cloudURL.absoluteString)
        try HistoryStore.shared.forgetCloudLink(cloudURL.absoluteString)
    }
}
