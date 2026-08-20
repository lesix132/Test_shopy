import Foundation

/// The kind of email Claude should write for an offer.
enum EmailKind: String, Sendable {
    case application   // premier message de candidature
    case followUp      // relance après absence de réponse

    var label: String {
        switch self {
        case .application: return "Candidature"
        case .followUp:    return "Relance"
        }
    }
}

/// A draft email produced by Claude: a subject line and a body.
struct EmailDraft: Sendable, Hashable, Codable {
    var subject: String
    var body: String
}
