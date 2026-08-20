import Foundation

/// One job posting fetched from a *public, legitimate* source (RSS or a public
/// JSON job API). This is NOT persisted — it's a transient item shown in the
/// Feed tab until the user chooses to save it into their JobOffer pipeline.
struct FeedItem: Identifiable, Hashable, Sendable {
    /// Stable id: source name + the item's guid/url, so the same posting from
    /// the same source dedupes across refreshes.
    let id: String
    let title: String
    let company: String
    let location: String
    let summary: String
    let url: String?
    let publishedAt: Date?
    let sourceName: String
}

/// A user-configurable feed source. Ships with a few public defaults and the
/// user can add their own RSS/Atom URLs (e.g. a company career-page feed).
struct FeedSource: Identifiable, Hashable, Codable, Sendable {

    /// How the source's payload is parsed / fetched.
    enum Kind: String, Codable, Sendable {
        case rss            // generic RSS/Atom (universal)
        case remotiveJSON   // Remotive public JSON API (https://remotive.com/api)
        case franceTravail  // France Travail (ex-Pôle Emploi) official API
        case adzuna         // Adzuna France public API
    }

    var id: UUID
    var name: String
    var urlString: String
    var kind: Kind
    var isEnabled: Bool
    /// Keyword filter for keyword-based API sources (France Travail, Adzuna).
    /// Ignored by RSS/JSON feed sources.
    var query: String?

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        kind: Kind = .rss,
        isEnabled: Bool = true,
        query: String? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.kind = kind
        self.isEnabled = isEnabled
        self.query = query
    }

    var url: URL? { URL(string: urlString) }

    /// True for API sources that need credentials (entered in Réglages).
    var requiresCredentials: Bool {
        kind == .franceTravail || kind == .adzuna
    }

    /// True for keyword-based API sources whose `query` is used.
    var usesQuery: Bool { requiresCredentials }

    /// Built-in public sources that permit programmatic access.
    /// All are *public job boards* — none is LinkedIn or Indeed, none requires
    /// scraping. The France/Indeed alternatives (France Travail, Adzuna) are
    /// disabled until you add their free API keys in Réglages.
    static let defaults: [FeedSource] = [
        FeedSource(
            name: "France Travail",
            urlString: "https://francetravail.io",
            kind: .franceTravail,
            isEnabled: false,
            query: AppConfig.defaultFeedQuery
        ),
        FeedSource(
            name: "Adzuna France",
            urlString: "https://www.adzuna.fr",
            kind: .adzuna,
            isEnabled: false,
            query: AppConfig.defaultFeedQuery
        ),
        FeedSource(
            name: "Remotive (remote)",
            urlString: "https://remotive.com/api/remote-jobs?limit=50",
            kind: .remotiveJSON
        ),
        FeedSource(
            name: "We Work Remotely",
            urlString: "https://weworkremotely.com/remote-jobs.rss",
            kind: .rss
        ),
    ]
}

/// Aggregated result of a feed fetch: the items plus any per-source failures,
/// so the UI can show fetched jobs even when one source is unreachable.
struct FeedFetchResult: Sendable {
    var items: [FeedItem]
    var failures: [String]

    static let empty = FeedFetchResult(items: [], failures: [])
}

/// A feed item's title/summary translated to French by Claude.
struct TranslatedText: Sendable, Hashable, Codable {
    var title: String
    var summary: String
}

/// Claude's automatic analysis of a feed item: a short French summary,
/// suggested tags, and (when a CV is available) a 0–100 match score.
struct FeedAnalysis: Sendable, Hashable, Codable {
    var summaryFR: String
    var tags: [String]
    var matchScore: Int?
}
