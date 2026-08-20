import Foundation

/// Fetches job postings from public, legitimate sources (RSS/Atom feeds and
/// public JSON job APIs). Behind a protocol so ViewModels depend on an
/// abstraction and tests can inject a mock.
///
/// This service deliberately never touches LinkedIn's personal feed: LinkedIn's
/// Terms of Service forbid automated reading of it and expose no public API for
/// it. Only sources the user explicitly configures (public job boards) are hit.
protocol JobFeedService {
    /// Fetches and aggregates items from all enabled sources. Individual source
    /// failures are collected rather than failing the whole fetch.
    func fetch(from sources: [FeedSource]) async -> FeedFetchResult
}

/// Live implementation using `URLSession`.
struct JobFeedNetworkService: JobFeedService {

    private let session: URLSession
    private let secretStore: SecretStore

    init(secretStore: SecretStore, session: URLSession = .shared) {
        self.secretStore = secretStore
        self.session = session
    }

    func fetch(from sources: [FeedSource]) async -> FeedFetchResult {
        let enabled = sources.filter { $0.isEnabled && $0.url != nil }
        guard !enabled.isEmpty else { return .empty }

        // Fetch every source concurrently.
        let results = await withTaskGroup(
            of: Result<[FeedItem], FeedSourceError>.self
        ) { group -> [Result<[FeedItem], FeedSourceError>] in
            for source in enabled {
                group.addTask { await fetchOne(source) }
            }
            var collected: [Result<[FeedItem], FeedSourceError>] = []
            for await value in group { collected.append(value) }
            return collected
        }

        var items: [FeedItem] = []
        var failures: [String] = []
        for result in results {
            switch result {
            case .success(let fetched): items.append(contentsOf: fetched)
            case .failure(let error):   failures.append(error.message)
            }
        }

        // Dedupe by id, then sort newest-first (undated items last).
        var seen = Set<String>()
        let deduped = items.filter { seen.insert($0.id).inserted }
        let sorted = deduped.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
        return FeedFetchResult(items: sorted, failures: failures)
    }

    // MARK: - Per-source fetch

    private func fetchOne(_ source: FeedSource) async -> Result<[FeedItem], FeedSourceError> {
        // Credential-based API sources run their own request flow.
        if source.requiresCredentials {
            return await fetchAPI(source)
        }

        guard let url = source.url else {
            return .failure(FeedSourceError(source: source.name, reason: "URL invalide"))
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("JobTrack/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(FeedSourceError(source: source.name,
                                                reason: "HTTP \(http.statusCode)"))
            }

            let items: [FeedItem]
            switch source.kind {
            case .rss:          items = RSSFeedParser.parse(data: data, sourceName: source.name)
            case .remotiveJSON: items = try RemotiveDecoder.decode(data: data, sourceName: source.name)
            }
            return .success(items)
        } catch {
            return .failure(FeedSourceError(source: source.name, reason: friendly(error)))
        }
    }

    /// Handles France Travail / Adzuna, reading credentials from the Keychain.
    private func fetchAPI(_ source: FeedSource) async -> Result<[FeedItem], FeedSourceError> {
        let query = source.query ?? AppConfig.defaultFeedQuery
        do {
            switch source.kind {
            case .franceTravail:
                guard let id = secretStore.value(AppConfig.franceTravailClientIDAccount),
                      let secret = secretStore.value(AppConfig.franceTravailClientSecretAccount) else {
                    return .failure(FeedSourceError(source: source.name,
                                                    reason: "clés manquantes (Réglages)"))
                }
                let items = try await FranceTravailClient.fetch(
                    query: query,
                    credentials: .init(clientID: id, clientSecret: secret),
                    sourceName: source.name, session: session)
                return .success(items)

            case .adzuna:
                guard let id = secretStore.value(AppConfig.adzunaAppIDAccount),
                      let key = secretStore.value(AppConfig.adzunaAppKeyAccount) else {
                    return .failure(FeedSourceError(source: source.name,
                                                    reason: "clés manquantes (Réglages)"))
                }
                let items = try await AdzunaClient.fetch(
                    query: query,
                    credentials: .init(appID: id, appKey: key),
                    sourceName: source.name, session: session)
                return .success(items)

            default:
                return .failure(FeedSourceError(source: source.name, reason: "type non géré"))
            }
        } catch let error as FeedSourceError {
            return .failure(error)
        } catch {
            return .failure(FeedSourceError(source: source.name, reason: friendly(error)))
        }
    }

    private func friendly(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorNotConnectedToInternet: return "hors ligne"
        case NSURLErrorTimedOut:               return "délai dépassé"
        default:                               return ns.localizedDescription
        }
    }
}

/// A failure attributed to a specific source.
struct FeedSourceError: Error, Sendable {
    let source: String
    let reason: String
    var message: String { "\(source) : \(reason)" }
}
