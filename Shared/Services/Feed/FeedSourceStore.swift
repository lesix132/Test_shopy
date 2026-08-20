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

    /// Current sources, seeding built-ins the first time.
    func load() -> [FeedSource] {
        guard let data = defaults.data(forKey: key),
              let sources = try? JSONDecoder().decode([FeedSource].self, from: data)
        else {
            save(FeedSource.defaults)
            return FeedSource.defaults
        }
        return sources
    }

    func save(_ sources: [FeedSource]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: key)
    }
}
