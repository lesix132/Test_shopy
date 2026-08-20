import Foundation

/// A single item captured by the Share Extension, awaiting import by the app.
struct PendingImport: Codable, Identifiable {
    let id: UUID
    let rawText: String
    let sourceURL: String?
    let capturedAt: Date

    init(id: UUID = UUID(), rawText: String, sourceURL: String?, capturedAt: Date = .now) {
        self.id = id
        self.rawText = rawText
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt
    }
}

/// File-based hand-off between the Share Extension and the main app.
///
/// The extension writes one JSON file per shared item into the App Group's
/// `Inbox/` directory; the app drains them into SwiftData on launch/foreground.
/// Using files (rather than both processes writing the SQLite store) avoids
/// cross-process contention and change-notification gaps.
enum ImportInbox {

    private static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// Called by the Share Extension to queue a captured item.
    static func enqueue(_ item: PendingImport) throws {
        guard let inboxURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        let fileURL = inboxURL.appending(path: "\(item.id.uuidString).json")
        let data = try JSONEncoder().encode(item)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Called by the app: returns all pending items and removes them from disk.
    @discardableResult
    static func drain() -> [PendingImport] {
        guard let inboxURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: inboxURL,
                includingPropertiesForKeys: nil
              ) else { return [] }

        var items: [PendingImport] = []
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let item = try? decoder.decode(PendingImport.self, from: data) {
                items.append(item)
            }
            try? FileManager.default.removeItem(at: file)
        }
        return items.sorted { $0.capturedAt < $1.capturedAt }
    }
}
