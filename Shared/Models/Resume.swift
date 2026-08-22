import Foundation
import SwiftData

/// A stored CV. Multiple versions are supported (généraliste, spécialisé, …).
@Model
final class Resume {

    @Attribute(.unique) var id: UUID

    /// Human label, e.g. "CV généraliste" or "CV Data Engineer".
    var name: String

    /// The original PDF bytes.
    @Attribute(.externalStorage) var pdfData: Data

    /// Text extracted from the PDF (PDFKit), used as Claude context.
    var extractedText: String

    var dateUpdated: Date

    /// Whether this is the default CV used for generation when none is chosen.
    var isDefault: Bool

    // MARK: Tailored copies (CV optimisé pour une offre)

    /// If this CV is an AI-optimized copy, the id of the original it derives from.
    /// Optional keeps SwiftData lightweight migration working.
    var sourceResumeID: UUID?
    /// The offer this copy was tailored for, e.g. "Ingénieur sûreté — Orano".
    var tailoredForOffer: String?
    /// Short explanation of what was changed and why.
    var tailoringReason: String?

    /// True when this CV is an AI-optimized derivative of another.
    var isTailored: Bool { sourceResumeID != nil }

    init(
        id: UUID = UUID(),
        name: String,
        pdfData: Data,
        extractedText: String,
        dateUpdated: Date = .now,
        isDefault: Bool = false,
        sourceResumeID: UUID? = nil,
        tailoredForOffer: String? = nil,
        tailoringReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pdfData = pdfData
        self.extractedText = extractedText
        self.dateUpdated = dateUpdated
        self.isDefault = isDefault
        self.sourceResumeID = sourceResumeID
        self.tailoredForOffer = tailoredForOffer
        self.tailoringReason = tailoringReason
    }
}
