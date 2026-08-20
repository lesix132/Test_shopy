import Foundation
import SwiftData

/// A job offer spotted on LinkedIn and imported manually into JobTrack.
@Model
final class JobOffer {

    /// Stable identifier.
    @Attribute(.unique) var id: UUID

    var title: String
    var company: String
    var location: String

    /// Full offer text.
    var descriptionText: String

    /// Source URL (LinkedIn post / job page), if provided.
    var sourceURL: String?

    var dateAdded: Date

    /// Stored as raw value so SwiftData persists it cleanly.
    var statusRaw: String

    /// Free-form personal notes.
    var notes: String

    /// Tags for organization/filtering.
    var tags: [String]

    /// Optional CV↔offer match score (0–100) computed via Claude.
    var matchScore: Int?

    /// When imported via Share Extension / paste, the untouched captured text.
    /// Kept so the app can (re)parse it with Claude.
    var rawImportText: String?

    /// True until the offer has been parsed/confirmed by the user.
    /// Share-Extension imports start with this = true.
    var needsParsing: Bool

    /// Generated cover letters for this offer.
    @Relationship(deleteRule: .cascade, inverse: \CoverLetter.offer)
    var coverLetters: [CoverLetter]

    init(
        id: UUID = UUID(),
        title: String = "",
        company: String = "",
        location: String = "",
        descriptionText: String = "",
        sourceURL: String? = nil,
        dateAdded: Date = .now,
        status: ApplicationStatus = .toProcess,
        notes: String = "",
        tags: [String] = [],
        matchScore: Int? = nil,
        rawImportText: String? = nil,
        needsParsing: Bool = false
    ) {
        self.id = id
        self.title = title
        self.company = company
        self.location = location
        self.descriptionText = descriptionText
        self.sourceURL = sourceURL
        self.dateAdded = dateAdded
        self.statusRaw = status.rawValue
        self.notes = notes
        self.tags = tags
        self.matchScore = matchScore
        self.rawImportText = rawImportText
        self.needsParsing = needsParsing
        self.coverLetters = []
    }

    /// Type-safe accessor over `statusRaw`.
    var status: ApplicationStatus {
        get { ApplicationStatus(rawValue: statusRaw) ?? .toProcess }
        set { statusRaw = newValue.rawValue }
    }

    /// Best display title, even before parsing.
    var displayTitle: String {
        if !title.isEmpty { return title }
        if let raw = rawImportText, !raw.isEmpty {
            return String(raw.prefix(60))
        }
        return "Offre sans titre"
    }
}
