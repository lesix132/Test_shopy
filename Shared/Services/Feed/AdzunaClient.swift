import Foundation

/// Credentials for the Adzuna API, read from Keychain.
struct AdzunaCredentials: Sendable {
    let appID: String
    let appKey: String
}

/// Fetches French job offers from the Adzuna public API — a legal aggregator
/// covering many job boards, used here as an alternative to LinkedIn/Indeed.
enum AdzunaClient {

    static func fetch(
        query: String,
        credentials: AdzunaCredentials,
        sourceName: String,
        session: URLSession
    ) async throws -> [FeedItem] {
        var components = URLComponents(string: AppConfig.adzunaSearchBase)!
        var items: [URLQueryItem] = [
            .init(name: "app_id", value: credentials.appID),
            .init(name: "app_key", value: credentials.appKey),
            .init(name: "results_per_page", value: "50"),
            .init(name: "content-type", value: "application/json"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(.init(name: "what", value: trimmed)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedSourceError(source: "Adzuna", reason: "réponse invalide")
        }
        guard (200..<300).contains(http.statusCode) else {
            let reason = http.statusCode == 401 || http.statusCode == 403
                ? "clés refusées (HTTP \(http.statusCode))"
                : "HTTP \(http.statusCode)"
            throw FeedSourceError(source: "Adzuna", reason: reason)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (decoded.results ?? []).map { job in
            FeedItem(
                id: "\(sourceName)#\(job.id ?? UUID().uuidString)",
                title: job.title ?? "Offre",
                company: job.company?.displayName ?? "",
                location: job.location?.displayName ?? "",
                summary: job.description ?? "",
                url: job.redirectURL,
                publishedAt: Self.date(from: job.created),
                sourceName: sourceName
            )
        }
    }

    private static let iso = ISO8601DateFormatter()
    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return iso.date(from: string)
    }

    // MARK: DTOs

    private struct SearchResponse: Decodable {
        let results: [Job]?
    }

    private struct Job: Decodable {
        let id: String?
        let title: String?
        let description: String?
        let created: String?
        let redirectURL: String?
        let company: NamedField?
        let location: NamedField?

        enum CodingKeys: String, CodingKey {
            case id, title, description, created, company, location
            case redirectURL = "redirect_url"
        }
    }

    /// Adzuna nests `{ "display_name": "…" }` under `company` and `location`.
    private struct NamedField: Decodable {
        let displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
}
