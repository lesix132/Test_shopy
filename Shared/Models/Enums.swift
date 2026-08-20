import Foundation

/// Where an offer sits in your application pipeline.
enum ApplicationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case toProcess          // à traiter
    case applied            // candidature envoyée
    case interview          // entretien
    case rejected           // refus
    case accepted           // accepté

    var id: String { rawValue }

    /// User-facing French label.
    var label: String {
        switch self {
        case .toProcess: return "À traiter"
        case .applied:   return "Candidature envoyée"
        case .interview: return "Entretien"
        case .rejected:  return "Refus"
        case .accepted:  return "Accepté"
        }
    }

    /// SF Symbol used in badges.
    var systemImage: String {
        switch self {
        case .toProcess: return "tray"
        case .applied:   return "paperplane"
        case .interview: return "person.2.wave.2"
        case .rejected:  return "xmark.circle"
        case .accepted:  return "checkmark.seal"
        }
    }
}

/// Lifecycle of a generated cover letter.
enum LetterStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft       // brouillon
    case finalized   // finalisée
    case sent        // envoyée

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft:     return "Brouillon"
        case .finalized: return "Finalisée"
        case .sent:      return "Envoyée"
        }
    }
}

/// Desired tone for cover-letter generation.
enum LetterTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case formal        // formel
    case direct        // direct
    case enthusiastic  // enthousiaste

    var id: String { rawValue }

    var label: String {
        switch self {
        case .formal:       return "Formel"
        case .direct:       return "Direct"
        case .enthusiastic: return "Enthousiaste"
        }
    }

    /// Instruction fragment injected into the Claude prompt.
    var promptHint: String {
        switch self {
        case .formal:       return "un ton formel et professionnel"
        case .direct:       return "un ton direct, concis et factuel"
        case .enthusiastic: return "un ton enthousiaste et chaleureux, sans excès"
        }
    }
}

/// Desired length for cover-letter generation.
enum LetterLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short    // courte
    case medium   // moyenne
    case long     // longue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short:  return "Courte"
        case .medium: return "Moyenne"
        case .long:   return "Longue"
        }
    }

    var promptHint: String {
        switch self {
        case .short:  return "environ 150 mots"
        case .medium: return "environ 300 mots"
        case .long:   return "environ 450 mots"
        }
    }
}
