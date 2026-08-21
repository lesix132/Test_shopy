import Foundation

/// One requirement/criterion of an offer, compared against the candidate.
struct PageMatchLine: Sendable, Hashable, Identifiable {
    let id = UUID()
    let criterion: String
    let matches: Bool
    let score: Int
    let comment: String
}

/// The full match analysis of a page (offer) against the profile + CV.
struct PageMatchAnalysis: Sendable {
    let overallScore: Int
    let summary: String
    let lines: [PageMatchLine]
}

/// Wire format decoded from Claude, then mapped to `PageMatchAnalysis`.
struct PageMatchDTO: Decodable {
    let overallScore: Int
    let summary: String?
    let lines: [Line]

    struct Line: Decodable {
        let criterion: String
        let matches: Bool
        let score: Int?
        let comment: String?
    }

    enum CodingKeys: String, CodingKey {
        case overallScore = "overall_score"
        case summary, lines
    }

    /// Maps to the domain model (clamping scores, generating ids).
    func toAnalysis() -> PageMatchAnalysis {
        PageMatchAnalysis(
            overallScore: min(100, max(0, overallScore)),
            summary: summary ?? "",
            lines: lines.map {
                PageMatchLine(
                    criterion: $0.criterion,
                    matches: $0.matches,
                    score: min(100, max(0, $0.score ?? ($0.matches ? 80 : 20))),
                    comment: $0.comment ?? "")
            })
    }
}
