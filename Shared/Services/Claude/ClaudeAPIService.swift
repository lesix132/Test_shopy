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

    /// Translate a feed item's title and summary to French.
    func translateToFrench(title: String, summary: String) async throws -> TranslatedText

    /// Analyze a feed item: French summary, tags, and (if a CV is given) a
    /// 0–100 match score.
    func analyzeFeedItem(
        title: String,
        company: String,
        summary: String,
        resumeText: String?
    ) async throws -> FeedAnalysis

    /// Analyze the current page's text against the candidate's profile + CV,
    /// returning an overall score and a per-criterion match breakdown.
    func analyzePageMatch(
        pageText: String,
        profile: String?,
        resumeText: String?
    ) async throws -> PageMatchAnalysis

    /// Write an application or follow-up email (subject + body) for an offer,
    /// personalized with the sender's profile (memory).
    func generateEmail(
        kind: EmailKind,
        offer: JobOffer,
        resumeText: String?,
        senderProfile: String?,
        tone: LetterTone
    ) async throws -> EmailDraft
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

    func translateToFrench(title: String, summary: String) async throws -> TranslatedText {
        // Already French? Still safe to send; Claude returns it unchanged.
        let system = """
        Tu es un traducteur professionnel. Traduis en français le titre et le \
        résumé d'une offre d'emploi. Si le texte est déjà en français, renvoie-le \
        tel quel. Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour :
        {"title": "...", "summary": "..."}
        Conserve le sens, garde les noms propres et les technologies inchangés.
        """
        let userContent = """
        Titre : \(title)
        Résumé : \(summary)
        """
        let text = try await send(
            system: system,
            userContent: userContent,
            maxTokens: 1024,
            temperature: 0
        )
        guard let result: TranslatedText = decodeJSON(from: text) else {
            throw ClaudeError.decoding
        }
        return result
    }

    func analyzeFeedItem(
        title: String,
        company: String,
        summary: String,
        resumeText: String?
    ) async throws -> FeedAnalysis {
        let wantsScore = (resumeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let system = """
        Tu analyses une offre d'emploi pour un candidat. Réponds UNIQUEMENT avec \
        un objet JSON valide, sans texte autour, au format exact :
        {"summary_fr": "...", "tags": ["...", "..."], "match_score": \(wantsScore ? "0-100" : "null")}
        - summary_fr : un résumé clair en français (2 à 3 phrases : poste, missions clés, profil recherché).
        - tags : 3 à 6 mots-clés courts (technologies, secteur, séniorité).
        - match_score : \(wantsScore
            ? "un entier de 0 à 100 estimant l'adéquation entre le CV fourni et l'offre."
            : "la valeur null (aucun CV fourni).")
        """
        var userContent = """
        === OFFRE ===
        Intitulé : \(title)
        Entreprise : \(company)
        Description :
        \(summary)
        """
        if wantsScore, let resumeText {
            userContent += "\n\n=== CV ===\n\(resumeText)"
        }
        let text = try await send(
            system: system,
            userContent: userContent,
            maxTokens: 1024,
            temperature: 0
        )
        guard let dto: FeedAnalysisDTO = decodeJSON(from: text) else {
            throw ClaudeError.decoding
        }
        let score = dto.matchScore.map { min(100, max(0, $0)) }
        return FeedAnalysis(
            summaryFR: dto.summaryFr,
            tags: dto.tags ?? [],
            matchScore: wantsScore ? score : nil
        )
    }

    func generateEmail(
        kind: EmailKind,
        offer: JobOffer,
        resumeText: String?,
        senderProfile: String?,
        tone: LetterTone
    ) async throws -> EmailDraft {
        let intent: String
        switch kind {
        case .application:
            intent = """
            Rédige un e-mail de candidature concis et professionnel pour postuler \
            à cette offre. Mets en avant l'adéquation entre le profil et le poste.
            """
        case .followUp:
            intent = """
            Rédige un e-mail de relance poli et bref : le candidat a déjà postulé \
            mais n'a pas eu de réponse. Rappelle sa candidature, réaffirme son \
            intérêt, et demande courtoisement des nouvelles. N'invente pas de dates.
            """
        }
        let system = """
        Tu rédiges des e-mails en français pour une recherche d'emploi. \(intent) \
        Adopte \(tone.promptHint). Ne mens jamais et ne t'appuie que sur le CV \
        fourni. Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour :
        {"subject": "...", "body": "..."}
        Le body se termine par une formule de politesse et un espace pour la \
        signature. N'inclus pas de champs À/De.
        """
        var userContent = """
        === OFFRE ===
        Intitulé : \(offer.title)
        Entreprise : \(offer.company)
        Lieu : \(offer.location)
        Description :
        \(offer.descriptionText)
        """
        if let senderProfile, !senderProfile.trimmingCharacters(in: .whitespaces).isEmpty {
            userContent += "\n\n=== EXPÉDITEUR (utilise ces infos pour la signature) ===\n\(senderProfile)"
        }
        if let resumeText, !resumeText.trimmingCharacters(in: .whitespaces).isEmpty {
            userContent += "\n\n=== CV ===\n\(resumeText)"
        }

        let text = try await send(
            system: system,
            userContent: userContent,
            maxTokens: 1536,
            temperature: 0.6
        )
        guard let draft: EmailDraft = decodeJSON(from: text),
              !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeError.decoding
        }
        return draft
    }

    func analyzePageMatch(
        pageText: String,
        profile: String?,
        resumeText: String?
    ) async throws -> PageMatchAnalysis {
        let system = """
        Tu compares une offre d'emploi (texte d'une page web) au profil d'un \
        candidat. Identifie les principaux critères/exigences de l'offre \
        (compétences, expérience, diplômes, localisation, langues…) et, pour \
        CHAQUE critère, dis s'il correspond au candidat et donne un pourcentage. \
        Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour :
        {"overall_score": 0-100, "summary": "...", "lines": [
          {"criterion": "...", "matches": true, "score": 0-100, "comment": "..."}
        ]}
        - overall_score : adéquation globale (0-100).
        - summary : une phrase de synthèse en français.
        - lines : un élément par critère (6 à 12 max), comment court en français.
        Base-toi uniquement sur les infos fournies ; n'invente rien.
        """
        var userContent = "=== PAGE / OFFRE ===\n\(pageText.prefix(6000))"
        if let profile, !profile.trimmingCharacters(in: .whitespaces).isEmpty {
            userContent += "\n\n=== PROFIL ===\n\(profile)"
        }
        if let resumeText, !resumeText.trimmingCharacters(in: .whitespaces).isEmpty {
            userContent += "\n\n=== CV ===\n\(resumeText)"
        }
        let text = try await send(
            system: system,
            userContent: userContent,
            maxTokens: 2048,
            temperature: 0
        )
        guard let dto: PageMatchDTO = decodeJSON(from: text) else {
            throw ClaudeError.decoding
        }
        return dto.toAnalysis()
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
        decodeJSON(from: text)
    }

    /// Extracts and decodes any JSON object from a model reply, tolerating
    /// stray prose or code fences around the `{ … }`.
    private func decodeJSON<T: Decodable>(from text: String) -> T? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Wire format for `analyzeFeedItem` (snake_case from the model).
private struct FeedAnalysisDTO: Decodable {
    let summaryFr: String
    let tags: [String]?
    let matchScore: Int?

    enum CodingKeys: String, CodingKey {
        case summaryFr = "summary_fr"
        case tags
        case matchScore = "match_score"
    }
}
