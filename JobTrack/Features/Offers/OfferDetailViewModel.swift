import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class OfferDetailViewModel {
    var isScoring = false
    var errorMessage: String?

    // ATS résumé optimisation
    var isTailoring = false
    var advice: ResumeAdvice?

    private let claude: ClaudeService

    init(claude: ClaudeService) {
        self.claude = claude
    }

    /// Target ATS score the optimized CV should reach.
    static let targetATS = 80

    /// Optimize the CV for this offer, iterating until the optimized CV reaches
    /// the target ATS score (≥ 80) or a max number of passes — feeding each
    /// improved CV back in. Keeps the best result.
    func tailorResume(for offer: JobOffer, resume: Resume?) async {
        guard let resume, !resume.extractedText.isEmpty else {
            errorMessage = "Ajoutez d'abord un CV avec du texte extractible."
            return
        }
        errorMessage = nil
        isTailoring = true
        defer { isTailoring = false }

        var currentCV = resume.extractedText
        var best: ResumeAdvice?
        do {
            for _ in 0..<3 {
                let result = try await claude.tailorResume(resumeText: currentCV, offer: offer)
                if best == nil || result.optimizedAtsScore > best!.optimizedAtsScore {
                    best = result
                }
                if result.optimizedAtsScore >= Self.targetATS { break }
                let next = result.optimizedResumeText.trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty || next == currentCV { break }  // no further progress
                currentCV = next  // re-optimize the improved CV
            }
            advice = best
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
