import Foundation

/// Whether a feed item/source is a job posting or an employment-news article.
enum FeedCategory: String, Codable, Sendable, Hashable {
    case jobs   // offres d'emploi
    case news   // actualités de l'emploi
}

/// One item fetched from a *public, legitimate* source (RSS or a public JSON
/// job API) — either a job posting or an employment-news article. This is NOT
/// persisted; it's a transient item shown in the Feed tab. Job items can be
/// saved into the JobOffer pipeline; news items are opened in the browser.
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
    /// Job posting vs. news article. Defaults to `.jobs` so existing call sites
    /// (and the job-API decoders) keep compiling unchanged.
    var category: FeedCategory = .jobs
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
    /// Job board vs. employment-news feed. Decoded with a default so sources
    /// saved by older versions (no `category` key) load as `.jobs`.
    var category: FeedCategory

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        kind: Kind = .rss,
        isEnabled: Bool = true,
        query: String? = nil,
        category: FeedCategory = .jobs
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.kind = kind
        self.isEnabled = isEnabled
        self.query = query
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, urlString, kind, isEnabled, query, category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        urlString = try c.decode(String.self, forKey: .urlString)
        kind = try c.decode(Kind.self, forKey: .kind)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        query = try c.decodeIfPresent(String.self, forKey: .query)
        // Missing in stores written before news feeds existed → treat as jobs.
        category = try c.decodeIfPresent(FeedCategory.self, forKey: .category) ?? .jobs
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
    ] + newsDefaults

    /// Built-in employment-news feeds. They use Google News RSS search endpoints,
    /// which are public, return standard RSS, aggregate many French outlets, and
    /// are refreshed continuously — so the "Actualités" tab stays up to date.
    static let newsDefaults: [FeedSource] = [
        FeedSource(
            name: "Emploi & recrutement",
            urlString: "https://news.google.com/rss/search?q="
                + "emploi%20recrutement%20%22offre%20d%27emploi%22"
                + "&hl=fr&gl=FR&ceid=FR:fr",
            kind: .rss,
            category: .news
        ),
        FeedSource(
            name: "Marché du travail",
            urlString: "https://news.google.com/rss/search?q="
                + "%22march%C3%A9%20du%20travail%22%20emploi%20ch%C3%B4mage"
                + "&hl=fr&gl=FR&ceid=FR:fr",
            kind: .rss,
            category: .news
        ),
        FeedSource(
            name: "Conseils carrière",
            urlString: "https://news.google.com/rss/search?q="
                + "%22recherche%20d%27emploi%22%20CV%20entretien%20d%27embauche"
                + "&hl=fr&gl=FR&ceid=FR:fr",
            kind: .rss,
            category: .news
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
