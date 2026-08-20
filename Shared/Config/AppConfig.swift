import Foundation

/// App-wide constants shared by the main app and the Share Extension.
///
/// The values here must match the capabilities you configure in Xcode
/// (see `SETUP.md`): the App Group id, and the Keychain access group.
enum AppConfig {

    // MARK: Identifiers

    /// App Group that lets the app and the Share Extension read/write the
    /// same SwiftData store. Must be enabled on BOTH targets in Xcode and
    /// match the `.entitlements` files.
    static let appGroupID = "group.com.jobtrack.shared"

    /// Keychain access group so the API key is reachable from both targets.
    /// In Xcode this is `<TeamID>.com.jobtrack.shared`; the `$(AppIdentifierPrefix)`
    /// wildcard in the entitlements resolves the team prefix at build time,
    /// so here we store only the suffix and let the Keychain layer prepend it.
    static let keychainAccessGroupSuffix = "com.jobtrack.shared"

    /// Keychain service/account under which the Anthropic API key is stored.
    static let apiKeyKeychainAccount = "anthropic.api.key"

    // MARK: Claude

    /// Claude model used for every API call (parsing, matching, letters).
    /// Change here to switch models globally.
    static let claudeModel = "claude-sonnet-4-6"

    /// Anthropic Messages API endpoint.
    static let claudeEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Anthropic API version header value.
    static let claudeAPIVersion = "2023-06-01"

    /// Request timeout (seconds) for Claude calls.
    static let requestTimeout: TimeInterval = 60

    // MARK: French job-board APIs (legal alternatives to LinkedIn/Indeed)

    /// Default keyword filter applied to the France Travail / Adzuna searches.
    static let defaultFeedQuery = "nucléaire"

    /// Keychain accounts for the France Travail (ex-Pôle Emploi) API credentials.
    static let franceTravailClientIDAccount = "francetravail.client.id"
    static let franceTravailClientSecretAccount = "francetravail.client.secret"

    /// Keychain accounts for the Adzuna API credentials.
    static let adzunaAppIDAccount = "adzuna.app.id"
    static let adzunaAppKeyAccount = "adzuna.app.key"

    /// France Travail OAuth2 (client_credentials) token endpoint.
    static let franceTravailTokenEndpoint = URL(
        string: "https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=%2Fpartenaire"
    )!
    /// France Travail "Offres d'emploi v2" search endpoint.
    static let franceTravailSearchEndpoint = URL(
        string: "https://api.francetravail.io/partenaire/offresdemploi/v2/offres/search"
    )!
    /// OAuth scope required for the offers API.
    static let franceTravailScope = "api_offresdemploiv2 o2dsoffre"

    /// Adzuna France search endpoint (page 1).
    static let adzunaSearchBase = "https://api.adzuna.com/v1/api/jobs/fr/search/1"
}
