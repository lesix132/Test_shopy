import Foundation
import Observation

/// Drives the Feed tab: loads sources, fetches items, filters by keyword, and
/// builds `JobOffer`s from selected items. UI-agnostic and testable.
@MainActor
@Observable
final class FeedViewModel {

    // MARK: State

    private(set) var items: [FeedItem] = []
    private(set) var sources: [FeedSource] = []
    private(set) var failures: [String] = []
    private(set) var isLoading = false
    private(set) var hasLoadedOnce = false

    /// Client-side keyword filter.
    var keyword = ""

    // MARK: Dependencies

    private let service: JobFeedService
    private let store: FeedSourceStore

    init(service: JobFeedService, store: FeedSourceStore = FeedSourceStore()) {
        self.service = service
        self.store = store
        self.sources = store.load()
    }

    // MARK: Derived

    var filteredItems: [FeedItem] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q)
                || $0.company.lowercased().contains(q)
                || $0.location.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
        }
    }

    var hasEnabledSource: Bool { sources.contains { $0.isEnabled } }

    // MARK: Actions

    /// Called when the tab appears; fetches only if we haven't yet.
    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }
        let result = await service.fetch(from: sources)
        items = result.items
        failures = result.failures
    }

    /// Builds a `JobOffer` from a feed item, ready to insert into SwiftData.
    /// The offer is already structured, so it does not need Claude parsing.
    func makeOffer(from item: FeedItem) -> JobOffer {
        JobOffer(
            title: item.title,
            company: item.company,
            location: item.location,
            descriptionText: item.summary,
            sourceURL: item.url,
            dateAdded: .now,
            status: .toProcess,
            tags: [item.sourceName],
            needsParsing: false
        )
    }

    // MARK: Source management

    func addRSSSource(name: String, urlString: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else { return }
        let source = FeedSource(
            name: trimmedName.isEmpty ? trimmedURL : trimmedName,
            urlString: trimmedURL,
            kind: .rss
        )
        sources.append(source)
        persist()
    }

    func toggle(_ source: FeedSource) {
        guard let index = sources.firstIndex(of: source) else { return }
        sources[index].isEnabled.toggle()
        persist()
    }

    func remove(_ source: FeedSource) {
        sources.removeAll { $0.id == source.id }
        persist()
    }

    func resetToDefaults() {
        sources = FeedSource.defaults
        persist()
    }

    private func persist() {
        store.save(sources)
    }
}
