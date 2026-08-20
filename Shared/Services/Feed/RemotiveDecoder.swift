import Foundation

/// Decodes the Remotive public JSON API (https://remotive.com/api/remote-jobs)
/// into `FeedItem`s. Remotive publishes an open, documented JSON endpoint.
enum RemotiveDecoder {

    static func decode(data: Data, sourceName: String) throws -> [FeedItem] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.jobs.map { job in
            FeedItem(
                id: "\(sourceName)#\(job.id)",
                title: job.title,
                company: job.companyName,
                location: job.candidateRequiredLocation ?? "",
                summary: job.description.strippingHTMLBasic,
                url: job.url,
                publishedAt: Self.date(from: job.publicationDate),
                sourceName: sourceName
            )
        }
    }

    private static let iso = ISO8601DateFormatter()

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        // Remotive uses "2024-01-31T12:00:00" (no zone) and sometimes full ISO.
        if let d = iso.date(from: string) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: string)
    }

    // MARK: DTOs

    private struct Payload: Decodable {
        let jobs: [Job]
    }

    private struct Job: Decodable {
        let id: Int
        let title: String
        let companyName: String
        let candidateRequiredLocation: String?
        let url: String
        let description: String
        let publicationDate: String?

        enum CodingKeys: String, CodingKey {
            case id, title, url, description
            case companyName = "company_name"
            case candidateRequiredLocation = "candidate_required_location"
            case publicationDate = "publication_date"
        }
    }
}

private extension String {
    /// Lightweight tag/entity stripping for JSON HTML descriptions.
    var strippingHTMLBasic: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
