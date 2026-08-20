import Foundation

/// Persists the user's feed sources in the App Group `UserDefaults`, falling
/// back to standard defaults if the group isn't available. Seeds with
/// `FeedSource.defaults` on first launch.
struct FeedSourceStore {

    private let key = "feed.sources.v1"
    private let defaults: UserDefaults

    init() {
        self.defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    /// Current sources, seeding built-ins the first time and merging in any new
    /// built-in API sources (France Travail, Adzuna) added in later versions.
    func load() -> [FeedSource] {
        guard let data = defaults.data(forKey: key),
              var sources = try? JSONDecoder().decode([FeedSource].self, from: data)
        else {
            save(FeedSource.defaults)
            return FeedSource.defaults
        }
        // Add newly-introduced built-in kinds the user has never seen.
        let existingKinds = Set(sources.map(\.kind))
        let newDefaults = FeedSource.defaults.filter { !existingKinds.contains($0.kind) }
        if !newDefaults.isEmpty {
            sources.insert(contentsOf: newDefaults, at: 0)
            save(sources)
        }
        return sources
    }

    func save(_ sources: [FeedSource]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: key)
    }
}
