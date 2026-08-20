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

    init(
        id: UUID = UUID(),
        name: String,
        pdfData: Data,
        extractedText: String,
        dateUpdated: Date = .now,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pdfData = pdfData
        self.extractedText = extractedText
        self.dateUpdated = dateUpdated
        self.isDefault = isDefault
    }
}
