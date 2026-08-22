import Foundation

/// Advice from Claude on how to tune a CV so it passes an offer's ATS
/// (applicant tracking system) screening more easily. Honest optimisation:
/// surface real keywords to add and phrasing to improve — never invented
/// experience.
struct ResumeAdvice: Sendable, Equatable {
    /// Estimated likelihood (0–100) the CV passes the offer's ATS as-is.
    var atsScore: Int
    /// Estimated ATS score (0–100) of the OPTIMIZED CV. Target: ≥ 80.
    var optimizedAtsScore: Int
    /// Offer keywords already present in the CV.
    var presentKeywords: [String]
    /// Offer keywords missing from the CV (add them if truthful).
    var missingKeywords: [String]
    /// Concrete, actionable edits.
    var suggestions: [String]
    /// A rewritten professional summary / accroche tuned to the offer.
    var optimizedSummary: String
    /// The full CV rewritten in the SAME structure/body as the original,
    /// optimized (honestly) for the offer — used to create a tailored CV copy.
    var optimizedResumeText: String
}

/// Wire format decoded from Claude, mapped to `ResumeAdvice`.
struct ResumeAdviceDTO: Decodable {
    let atsScore: Int?
    let optimizedAtsScore: Int?
    let presentKeywords: [String]?
    let missingKeywords: [String]?
    let suggestions: [String]?
    let optimizedSummary: String?
    let optimizedResume: String?

    enum CodingKeys: String, CodingKey {
        case atsScore = "ats_score"
        case optimizedAtsScore = "optimized_ats_score"
        case presentKeywords = "present_keywords"
        case missingKeywords = "missing_keywords"
        case suggestions
        case optimizedSummary = "optimized_summary"
        case optimizedResume = "optimized_resume"
    }

    func toAdvice() -> ResumeAdvice {
        ResumeAdvice(
            atsScore: min(100, max(0, atsScore ?? 0)),
            optimizedAtsScore: min(100, max(0, optimizedAtsScore ?? atsScore ?? 0)),
            presentKeywords: presentKeywords ?? [],
            missingKeywords: missingKeywords ?? [],
            suggestions: suggestions ?? [],
            optimizedSummary: optimizedSummary ?? "",
            optimizedResumeText: optimizedResume ?? "")
    }
}
