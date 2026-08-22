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
    /// Keep only France-based offers (seeded from the profile).
    var franceOnly: Bool = true
    /// Optional region filter.
    var regionFilter: FrenchRegion?
    /// Which segment is shown: job offers or employment news.
    var category: FeedCategory = .jobs

    // MARK: AI (translation & analysis) caches

    private(set) var translations: [String: TranslatedText] = [:]
    private(set) var analyses: [String: FeedAnalysis] = [:]
    private(set) var translating: Set<String> = []
    private(set) var analyzing: Set<String> = []
    /// Whether the whole visible feed is being auto-analyzed/translated.
    private(set) var isBatchProcessing = false
    var lastAIError: String?

    // MARK: Dependencies

    private let service: JobFeedService
    private let claude: ClaudeService
    private let store: FeedSourceStore

    init(
        service: JobFeedService,
        claude: ClaudeService,
        store: FeedSourceStore = FeedSourceStore(),
        profileStore: ProfileStore = ProfileStore()
    ) {
        self.service = service
        self.claude = claude
        self.store = store
        self.sources = store.load()
        self.franceOnly = profileStore.load().franceOnly
    }

    /// Region detected from an item's location, if any.
    func region(for item: FeedItem) -> FrenchRegion? {
        FrenchRegion.detect(from: item.location)
    }

    // MARK: Derived

    var filteredItems: [FeedItem] {
        var result = items.filter { $0.category == category }

        // Geographic filters only make sense for job offers (news has no place).
        if category == .jobs {
            if franceOnly {
                result = result.filter { FrenchRegion.isLikelyFrance($0.location) }
            }
            if let regionFilter {
                result = result.filter { FrenchRegion.detect(from: $0.location) == regionFilter }
            }
        }

        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(q)
                    || $0.company.lowercased().contains(q)
                    || $0.location.lowercased().contains(q)
                    || $0.summary.lowercased().contains(q)
            }
        }
        return result
    }

    /// Regions present in the currently fetched items (for the filter menu).
    var availableRegions: [FrenchRegion] {
        let set = Set(items.compactMap { FrenchRegion.detect(from: $0.location) })
        return FrenchRegion.allCases.filter { set.contains($0) }
    }

    var hasEnabledSource: Bool {
        sources.contains { $0.isEnabled && $0.category == category }
    }

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
    /// If the item was analyzed/translated, that enrichment is carried over.
    func makeOffer(from item: FeedItem) -> JobOffer {
        let analysis = analyses[item.id]
        let translation = translations[item.id]

        var tags = [item.sourceName]
        tags.append(contentsOf: analysis?.tags ?? [])
        if let region = FrenchRegion.detect(from: item.location) {
            tags.append(region.rawValue)
        }

        let description = [translation?.summary, analysis?.summaryFR, item.summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? item.summary

        let offer = JobOffer(
            title: translation?.title.nilIfEmpty ?? item.title,
            company: item.company,
            location: item.location,
            descriptionText: description,
            sourceURL: item.url,
            dateAdded: .now,
            status: .toProcess,
            tags: Array(Set(tags)).sorted(),
            matchScore: analysis?.matchScore,
            needsParsing: false
        )
        return offer
    }

    // MARK: AI actions

    /// Translate one item's title/summary to French (cached).
    func translate(_ item: FeedItem) async {
        guard translations[item.id] == nil, !translating.contains(item.id) else { return }
        translating.insert(item.id)
        defer { translating.remove(item.id) }
        do {
            translations[item.id] = try await claude.translateToFrench(
                title: item.title, summary: item.summary
            )
        } catch {
            lastAIError = (error as? ClaudeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Analyze one item (French summary, tags, optional match score) — cached.
    func analyze(_ item: FeedItem, resumeText: String?) async {
        guard analyses[item.id] == nil, !analyzing.contains(item.id) else { return }
        analyzing.insert(item.id)
        defer { analyzing.remove(item.id) }
        do {
            analyses[item.id] = try await claude.analyzeFeedItem(
                title: item.title, company: item.company,
                summary: item.summary, resumeText: resumeText
            )
        } catch {
            lastAIError = (error as? ClaudeError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Auto-process the whole visible feed: translate + analyze every item.
    /// Runs sequentially to stay within API rate limits.
    func autoProcessAll(resumeText: String?) async {
        guard !isBatchProcessing else { return }
        isBatchProcessing = true
        defer { isBatchProcessing = false }
        for item in filteredItems {
            // News items aren't scored against a CV — just translate them.
            if category == .jobs {
                await analyze(item, resumeText: resumeText)
            }
            await translate(item)
        }
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

    /// Update the keyword filter of an API source (France Travail / Adzuna).
    func updateQuery(_ source: FeedSource, to query: String) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].query = query.nilIfEmpty
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

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
