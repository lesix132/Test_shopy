import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class OfferDetailViewModel {
    var isScoring = false
    var errorMessage: String?

    private let claude: ClaudeService

    init(claude: ClaudeService) {
        self.claude = claude
    }

    /// Compute a CV↔offer match score via Claude and store it on the offer.
    func computeMatchScore(for offer: JobOffer, resume: Resume?, context: ModelContext) async {
        guard let resume, !resume.extractedText.isEmpty else {
            errorMessage = "Ajoutez d'abord un CV avec du texte extractible."
            return
        }
        errorMessage = nil
        isScoring = true
        defer { isScoring = false }
        do {
            let score = try await claude.matchScore(resumeText: resume.extractedText, offer: offer)
            offer.matchScore = score
            try? context.save()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
