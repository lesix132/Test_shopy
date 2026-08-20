import Foundation

/// Credentials for the France Travail (ex-Pôle Emploi) API, read from Keychain.
struct FranceTravailCredentials: Sendable {
    let clientID: String
    let clientSecret: String
}

/// Fetches offers from the France Travail "Offres d'emploi v2" API.
///
/// This is the official, public French public-employment API — a legal
/// alternative to scraping LinkedIn/Indeed. Flow: OAuth2 client-credentials
/// token, then a keyword search.
enum FranceTravailClient {

    static func fetch(
        query: String,
        credentials: FranceTravailCredentials,
        sourceName: String,
        session: URLSession
    ) async throws -> [FeedItem] {
        let token = try await accessToken(credentials: credentials, session: session)
        return try await search(query: query, token: token, sourceName: sourceName, session: session)
    }

    // MARK: OAuth token

    private static func accessToken(
        credentials: FranceTravailCredentials,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: AppConfig.franceTravailTokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            .init(name: "grant_type", value: "client_credentials"),
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "client_secret", value: credentials.clientSecret),
            .init(name: "scope", value: AppConfig.franceTravailScope),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedSourceError(source: "France Travail", reason: "réponse invalide")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedSourceError(source: "France Travail",
                                  reason: "authentification refusée (HTTP \(http.statusCode))")
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data).accessToken,
              !token.isEmpty else {
            throw FeedSourceError(source: "France Travail", reason: "jeton d'accès manquant")
        }
        return token
    }

    // MARK: Search

    private static func search(
        query: String,
        token: String,
        sourceName: String,
        session: URLSession
    ) async throws -> [FeedItem] {
        var components = URLComponents(url: AppConfig.franceTravailSearchEndpoint,
                                       resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [.init(name: "range", value: "0-49")]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(.init(name: "motsCles", value: trimmed)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedSourceError(source: "France Travail", reason: "réponse invalide")
        }
        // 200 = full result, 206 = partial content (both valid), 204 = no result.
        if http.statusCode == 204 { return [] }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw FeedSourceError(source: "France Travail", reason: "HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (decoded.resultats ?? []).map { offer in
            FeedItem(
                id: "\(sourceName)#\(offer.id ?? UUID().uuidString)",
                title: offer.intitule ?? "Offre",
                company: offer.entreprise?.nom ?? "",
                location: offer.lieuTravail?.libelle ?? "",
                summary: offer.description ?? "",
                url: offer.origineOffre?.urlOrigine,
                publishedAt: Self.date(from: offer.dateCreation),
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

    private struct TokenResponse: Decodable {
        let accessToken: String?
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    private struct SearchResponse: Decodable {
        let resultats: [Offer]?
    }

    private struct Offer: Decodable {
        let id: String?
        let intitule: String?
        let description: String?
        let dateCreation: String?
        let entreprise: Entreprise?
        let lieuTravail: LieuTravail?
        let origineOffre: OrigineOffre?

        struct Entreprise: Decodable { let nom: String? }
        struct LieuTravail: Decodable { let libelle: String? }
        struct OrigineOffre: Decodable { let urlOrigine: String? }
    }
}
