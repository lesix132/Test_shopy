import Foundation
@testable import JobTrack

/// Test double for `ClaudeService`. Demonstrates the service is fully isolated
/// and injectable.
final class MockClaudeService: ClaudeService {
    var parseResult: Result<ParsedOffer, Error> = .success(
        ParsedOffer(title: "Ingénieur", company: "ACME", location: "Paris", description: "Desc")
    )
    var letterResult: Result<String, Error> = .success("Madame, Monsieur, …")
    var scoreResult: Result<Int, Error> = .success(87)

    private(set) var parseCallCount = 0
    private(set) var letterCallCount = 0

    func parseOffer(rawText: String) async throws -> ParsedOffer {
        parseCallCount += 1
        return try parseResult.get()
    }

    func generateCoverLetter(
        resumeText: String,
        offer: JobOffer,
        tone: LetterTone,
        length: LetterLength,
        extraInstructions: String?
    ) async throws -> String {
        letterCallCount += 1
        return try letterResult.get()
    }

    func matchScore(resumeText: String, offer: JobOffer) async throws -> Int {
        try scoreResult.get()
    }

    var translateResult: Result<TranslatedText, Error> = .success(
        TranslatedText(title: "Ingénieur", summary: "Résumé en français")
    )
    var analysisResult: Result<FeedAnalysis, Error> = .success(
        FeedAnalysis(summaryFR: "Résumé", tags: ["swift"], matchScore: 80)
    )

    func translateToFrench(title: String, summary: String) async throws -> TranslatedText {
        try translateResult.get()
    }

    func analyzeFeedItem(
        title: String,
        company: String,
        summary: String,
        resumeText: String?
    ) async throws -> FeedAnalysis {
        try analysisResult.get()
    }

    var emailResult: Result<EmailDraft, Error> = .success(
        EmailDraft(subject: "Candidature", body: "Madame, Monsieur, …")
    )
    var matchResult: Result<PageMatchAnalysis, Error> = .success(
        PageMatchAnalysis(overallScore: 72, summary: "Bon profil global.",
                          lines: [PageMatchLine(criterion: "Swift", matches: true,
                                                score: 90, comment: "Maîtrisé")])
    )

    func analyzePageMatch(
        pageText: String,
        profile: String?,
        resumeText: String?
    ) async throws -> PageMatchAnalysis {
        try matchResult.get()
    }

    var extractProfileResult: Result<ExtractedProfile, Error> = .success(
        ExtractedProfile(fullName: "Jean Dupont", email: "jean@example.com",
                         phone: "0600000000", headline: "Ingénieur", city: "Lyon",
                         summary: "5 ans d'expérience.")
    )

    func extractProfile(resumeText: String) async throws -> ExtractedProfile {
        try extractProfileResult.get()
    }

    func generateEmail(
        kind: EmailKind,
        offer: JobOffer,
        resumeText: String?,
        senderProfile: String?,
        tone: LetterTone
    ) async throws -> EmailDraft {
        try emailResult.get()
    }

    var adviceResult: Result<ResumeAdvice, Error> = .success(
        ResumeAdvice(atsScore: 68, presentKeywords: ["Swift"],
                     missingKeywords: ["Sûreté"], suggestions: ["Quantifie tes résultats."],
                     optimizedSummary: "Ingénieur avec 5 ans d'expérience…",
                     optimizedResumeText: "CV optimisé complet…"))

    func tailorResume(resumeText: String, offer: JobOffer) async throws -> ResumeAdvice {
        try adviceResult.get()
    }
}
