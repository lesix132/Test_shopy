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
}
