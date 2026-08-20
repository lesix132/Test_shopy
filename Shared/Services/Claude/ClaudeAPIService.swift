import Foundation

/// High-level Claude operations used by the app. Kept behind a protocol so
/// ViewModels depend on an abstraction and tests can inject a mock.
protocol ClaudeService {
    /// Extract structured fields (title/company/location/description) from raw text.
    func parseOffer(rawText: String) async throws -> ParsedOffer

    /// Generate a cover letter from a CV and an offer.
    func generateCoverLetter(
        resumeText: String,
        offer: JobOffer,
        tone: LetterTone,
        length: LetterLength,
        extraInstructions: String?
    ) async throws -> String

    /// Compute a 0–100 match score between a CV and an offer.
    func matchScore(resumeText: String, offer: JobOffer) async throws -> Int
}

/// Live implementation calling the Anthropic Messages API.
struct ClaudeAPIService: ClaudeService {

    private let secretStore: SecretStore
    private let session: URLSession

    init(secretStore: SecretStore, session: URLSession = .shared) {
        self.secretStore = secretStore
        self.session = session
    }

    // MARK: - Public operations

    func parseOffer(rawText: String) async throws -> ParsedOffer {
        let system = """
        Tu es un extracteur d'informations d'offres d'emploi. On te donne le \
        texte brut d'une offre (copié depuis LinkedIn ou une page web, parfois \
        bruité). Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, \
        au format exact :
        {"title": "...", "company": "...", "location": "...", "description": "..."}
        - title : l'intitulé du poste.
        - company : le nom de l'entreprise.
        - location : la localisation (ville / pays / remote). Vide si inconnue.
        - description : la description nettoyée de l'offre (missions, profil), \
          sans les boutons ni le bruit de l'interface.
        Si une information est absente, mets une chaîne vide. Ne devine pas.
        """

        let text = try await send(
            system: system,
            userContent: rawText,
            maxTokens: 2048,
            temperature: 0
        )

        guard let parsed = decodeParsedOffer(from: text) else {
            throw ClaudeError.parsingFailed
        }
        return parsed
    }

    func generateCoverLetter(
        resumeText: String,
        offer: JobOffer,
        tone: LetterTone,
        length: LetterLength,
        extraInstructions: String?
    ) async throws -> String {
        let system = """
        Tu es un assistant qui rédige des lettres de motivation en français, \
        personnalisées, honnêtes et crédibles. Tu t'appuies uniquement sur les \
        informations du CV fourni ; tu n'inventes jamais d'expérience, de \
        diplôme ou de compétence. Adopte \(tone.promptHint). Longueur cible : \
        \(length.promptHint). Structure : accroche, adéquation profil/poste, \
        motivation, formule de politesse. Réponds uniquement avec le texte de \
        la lettre, sans commentaire.
        """

        var userContent = """
        === CV ===
        \(resumeText)

        === OFFRE ===
        Intitulé : \(offer.title)
        Entreprise : \(offer.company)
        Lieu : \(offer.location)
        Description :
        \(offer.descriptionText)
        """

        if let extra = extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extra.isEmpty {
            userContent += "\n\n=== INSTRUCTIONS SUPPLÉMENTAIRES ===\n\(extra)"
        }

        let text = try await send(
            system: system,
            userContent: userContent,
            maxTokens: 2048,
            temperature: 0.7
        )
        let letter = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !letter.isEmpty else { throw ClaudeError.emptyResponse }
        return letter
    }

    func matchScore(resumeText: String, offer: JobOffer) async throws -> Int {
        let system = """
        Tu évalues l'adéquation entre un CV et une offre d'emploi. Réponds \
        UNIQUEMENT avec un entier entre 0 et 100 (aucun autre caractère), où \
        100 = adéquation parfaite.
        """
        let userContent = """
        === CV ===
        \(resumeText)

        === OFFRE ===
        \(offer.title) — \(offer.company)
        \(offer.descriptionText)
        """
        let text = try await send(
            system: system,
            userContent: userContent,
            maxTokens: 16,
            temperature: 0
        )
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter(\.isNumber)
        guard let value = Int(digits) else { throw ClaudeError.decoding }
        return min(100, max(0, value))
    }

    // MARK: - Networking

    private func send(
        system: String,
        userContent: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        guard let apiKey = secretStore.anthropicAPIKey() else {
            throw ClaudeError.missingAPIKey
        }

        let payload = ClaudeRequest(
            model: AppConfig.claudeModel,
            maxTokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: userContent)],
            temperature: temperature
        )

        var request = URLRequest(url: AppConfig.claudeEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AppConfig.claudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw ClaudeError.offline
            case .timedOut:
                throw ClaudeError.timeout
            default:
                throw ClaudeError.server(status: -1, message: error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.decoding
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw ClaudeError.invalidAPIKey
        case 429:
            throw ClaudeError.rateLimited
        default:
            let message = try? JSONDecoder()
                .decode(ClaudeAPIErrorEnvelope.self, from: data).error.message
            throw ClaudeError.server(status: http.statusCode, message: message)
        }

        let decoded: ClaudeResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw ClaudeError.decoding
        }

        let text = decoded.text
        guard !text.isEmpty else { throw ClaudeError.emptyResponse }
        return text
    }

    // MARK: - Helpers

    /// Extracts a `ParsedOffer` from a model reply, tolerating stray prose or
    /// code fences around the JSON object.
    private func decodeParsedOffer(from text: String) -> ParsedOffer? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ParsedOffer.self, from: data)
    }
}
