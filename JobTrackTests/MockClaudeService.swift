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
}
