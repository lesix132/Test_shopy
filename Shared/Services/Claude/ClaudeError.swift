import Foundation

/// Errors surfaced by the Claude service, mapped to friendly French messages.
enum ClaudeError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case offline
    case timeout
    case server(status: Int, message: String?)
    case decoding
    case emptyResponse
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Aucune clé API Anthropic. Ajoutez-la dans Réglages."
        case .invalidAPIKey:
            return "Clé API invalide. Vérifiez-la dans Réglages."
        case .rateLimited:
            return "Trop de requêtes. Réessayez dans quelques instants."
        case .offline:
            return "Pas de connexion internet."
        case .timeout:
            return "La requête a expiré. Réessayez."
        case .server(let status, let message):
            return "Erreur serveur (\(status)) : \(message ?? "inconnue")."
        case .decoding:
            return "Réponse inattendue de l'API."
        case .emptyResponse:
            return "Réponse vide de l'API."
        case .parsingFailed:
            return "Impossible d'extraire les informations de l'offre."
        }
    }
}
