import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CoverLetterViewModel {
    var content = ""
    var tone: LetterTone = .formal
    var length: LetterLength = .medium
    var extraInstructions = ""

    var isGenerating = false
    var errorMessage: String?

    private let claude: ClaudeService
    private let offer: JobOffer
    private let resume: Resume?

    /// The letter being edited, if we opened an existing one.
    private(set) var letter: CoverLetter?

    init(claude: ClaudeService, offer: JobOffer, resume: Resume?, existingLetter: CoverLetter? = nil) {
        self.claude = claude
        self.offer = offer
        self.resume = resume
        self.letter = existingLetter
        if let existingLetter {
            content = existingLetter.content
            tone = existingLetter.tone
        }
    }

    var canGenerate: Bool {
        !(resume?.extractedText ?? "").isEmpty && !isGenerating
    }

    var missingResume: Bool {
        (resume?.extractedText ?? "").isEmpty
    }

    /// Generate (or regenerate) the letter via Claude.
    func generate() async {
        guard let resume, !resume.extractedText.isEmpty else {
            errorMessage = "Ajoutez un CV avec du texte extractible avant de générer."
            return
        }
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            content = try await claude.generateCoverLetter(
                resumeText: resume.extractedText,
                offer: offer,
                tone: tone,
                length: length,
                extraInstructions: extraInstructions.isEmpty ? nil : extraInstructions
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Persist the current content as a draft/updated letter.
    func save(into context: ModelContext) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let letter {
            letter.content = trimmed
            letter.tone = tone
        } else {
            // Setting `offer` wires the inverse relationship automatically,
            // so we don't append to `offer.coverLetters` (that would duplicate).
            let newLetter = CoverLetter(content: trimmed, tone: tone, offer: offer)
            context.insert(newLetter)
            letter = newLetter
        }
        try? context.save()
    }

    func setStatus(_ status: LetterStatus, context: ModelContext) {
        letter?.status = status
        try? context.save()
    }

    /// Export the current content to a PDF file in a temporary location.
    func exportPDF() -> URL? {
        let data = PDFService.makePDF(from: content)
        guard !data.isEmpty else { return nil }
        let name = "Lettre-\(offer.company.isEmpty ? "offre" : offer.company)"
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = "Échec de l'export PDF : \(error.localizedDescription)"
            return nil
        }
    }
}
