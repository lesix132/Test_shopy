import Foundation
import SwiftData

/// A cover letter generated for a specific `JobOffer`.
@Model
final class CoverLetter {

    @Attribute(.unique) var id: UUID

    /// The letter body (editable).
    var content: String

    var dateGenerated: Date

    /// Stored raw values for SwiftData.
    var statusRaw: String
    var toneRaw: String

    /// The offer this letter belongs to.
    var offer: JobOffer?

    init(
        id: UUID = UUID(),
        content: String,
        dateGenerated: Date = .now,
        status: LetterStatus = .draft,
        tone: LetterTone = .formal,
        offer: JobOffer? = nil
    ) {
        self.id = id
        self.content = content
        self.dateGenerated = dateGenerated
        self.statusRaw = status.rawValue
        self.toneRaw = tone.rawValue
        self.offer = offer
    }

    var status: LetterStatus {
        get { LetterStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var tone: LetterTone {
        get { LetterTone(rawValue: toneRaw) ?? .formal }
        set { toneRaw = newValue.rawValue }
    }
}
