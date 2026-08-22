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
        var changed = false

        // Add newly-introduced built-in kinds the user has never seen.
        let existingKinds = Set(sources.map(\.kind))
        let newDefaults = FeedSource.defaults.filter {
            $0.category == .jobs && !existingKinds.contains($0.kind)
        }
        if !newDefaults.isEmpty {
            sources.insert(contentsOf: newDefaults, at: 0)
            changed = true
        }

        // Seed the employment-news feeds for users who upgraded from a version
        // that had none. Only when the user has zero news source, so removing
        // one later isn't undone on the next launch.
        if !sources.contains(where: { $0.category == .news }) {
            sources.append(contentsOf: FeedSource.newsDefaults)
            changed = true
        }

        // Seed the big-employer presets (Orano, EDF…) the first time they appear.
        let existingNames = Set(sources.map(\.name))
        let newCompanies = FeedSource.companyDefaults.filter { !existingNames.contains($0.name) }
        if !newCompanies.isEmpty {
            sources.append(contentsOf: newCompanies)
            changed = true
        }

        if changed { save(sources) }
        return sources
    }

    func save(_ sources: [FeedSource]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: key)
    }
}
