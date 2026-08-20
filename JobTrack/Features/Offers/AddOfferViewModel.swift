import Foundation
import Observation
import SwiftData

/// Drives the "add offer" flow: paste/OCR raw text, parse with Claude,
/// then confirm/edit before saving. All Claude access goes through the
/// injected `ClaudeService` so it is testable.
@MainActor
@Observable
final class AddOfferViewModel {

    // Editable fields (bound to the confirmation form).
    var title = ""
    var company = ""
    var location = ""
    var descriptionText = ""
    var sourceURL = ""
    var notes = ""
    var tags: [String] = []

    // Raw capture + flow state.
    var rawText = ""
    var isParsing = false
    var isRunningOCR = false
    var errorMessage: String?
    /// True once we have fields to review (after parsing or manual entry).
    var hasContent = false

    private let claude: ClaudeService

    init(claude: ClaudeService) {
        self.claude = claude
    }

    /// Prefill from a Share-Extension / inbox item.
    func load(from offer: JobOffer) {
        title = offer.title
        company = offer.company
        location = offer.location
        descriptionText = offer.descriptionText
        sourceURL = offer.sourceURL ?? ""
        notes = offer.notes
        tags = offer.tags
        rawText = offer.rawImportText ?? ""
        hasContent = true
    }

    /// Ask Claude to extract structured fields from `rawText`.
    func parseWithClaude() async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = nil
        isParsing = true
        defer { isParsing = false }

        do {
            let parsed = try await claude.parseOffer(rawText: text)
            title = parsed.title
            company = parsed.company
            location = parsed.location
            descriptionText = parsed.description.isEmpty ? text : parsed.description
            hasContent = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Fall back to letting the user edit the raw text manually.
            if descriptionText.isEmpty { descriptionText = text }
            hasContent = true
        }
    }

    /// Run OCR on a pasted screenshot, then optionally parse.
    func runOCR(on imageData: Data) async {
        errorMessage = nil
        isRunningOCR = true
        defer { isRunningOCR = false }
        do {
            let text = try await OCRService.recognizeText(inImageData: imageData)
            rawText = text
            hasContent = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Skip AI and just review the raw text manually.
    func useRawTextManually() {
        if descriptionText.isEmpty {
            descriptionText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        hasContent = true
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Persist a new offer. If `existing` is provided (inbox item), update it.
    func save(into context: ModelContext, existing: JobOffer? = nil) {
        let offer = existing ?? JobOffer()
        offer.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.descriptionText = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.notes = notes
        offer.tags = tags
        offer.needsParsing = false
        let url = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.sourceURL = url.isEmpty ? nil : url
        if !rawText.isEmpty { offer.rawImportText = rawText }

        if existing == nil {
            context.insert(offer)
        }
        try? context.save()
    }
}
