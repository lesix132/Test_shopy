import Foundation
import SwiftData

/// Builds the SwiftData `ModelContainer` backed by the shared App Group
/// container, so the main app and the Share Extension read/write the same store.
enum SharedModelContainer {

    /// The full SwiftData schema for JobTrack.
    static let schema = Schema([
        JobOffer.self,
        Resume.self,
        CoverLetter.self,
    ])

    /// Creates (or opens) the shared container.
    ///
    /// Falls back to a default (non–App Group) location only if the App Group
    /// container URL can't be resolved — this keeps the app usable in previews
    /// or if the capability isn't configured yet, though the Share Extension
    /// then won't share data.
    static func make() -> ModelContainer {
        let storeURL = resolveStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // The most common cause is a store left by a previous version whose
            // schema no longer matches (a migration that can't be done
            // automatically). Reset the local store once and retry so the app
            // launches instead of crashing. Existing local data is discarded.
            print("⚠️ ModelContainer failed (\(error)); resetting local store.")
            deleteStore(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    /// The store location: the App Group container when available (so the Share
    /// Extension shares data), otherwise Application Support.
    private static func resolveStoreURL() -> URL {
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) {
            return groupURL.appending(path: "JobTrack.sqlite")
        }
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base.appending(path: "JobTrack.sqlite")
    }

    /// Removes the SwiftData store and its sidecar files.
    private static func deleteStore(at url: URL) {
        let fm = FileManager.default
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            try? fm.removeItem(atPath: path)
        }
    }
}
