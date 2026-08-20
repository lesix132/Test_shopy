import Foundation
import Observation

/// Drives the "Relances" tab: generates AI application/follow-up emails and
/// holds the current draft for editing. Follow-up date logic lives on `JobOffer`.
@MainActor
@Observable
final class FollowUpsViewModel {

    private let claude: ClaudeService

    /// Current AI-generated draft being reviewed, if any.
    var draft: EmailDraft?
    /// The offer the current draft belongs to.
    var draftOfferID: UUID?
    var draftKind: EmailKind = .followUp
    var isGenerating = false
    var errorMessage: String?

    init(claude: ClaudeService) {
        self.claude = claude
    }

    func generate(
        kind: EmailKind,
        offer: JobOffer,
        resumeText: String?,
        tone: LetterTone = .formal
    ) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            draft = try await claude.generateEmail(
                kind: kind, offer: offer, resumeText: resumeText, tone: tone)
            draftOfferID = offer.id
            draftKind = kind
        } catch let error as ClaudeError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearDraft() {
        draft = nil
        draftOfferID = nil
        errorMessage = nil
    }
}
