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
        let configuration: ModelConfiguration

        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) {
            let storeURL = groupURL.appending(path: "JobTrack.sqlite")
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // App Group not available — use the default local store.
            assertionFailure("App Group \(AppConfig.appGroupID) is not configured; "
                             + "data will not be shared with the Share Extension.")
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
