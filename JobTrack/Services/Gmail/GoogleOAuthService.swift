import Foundation
import CryptoKit
import Security
import AuthenticationServices

enum GmailError: LocalizedError {
    case notConfigured        // no client id
    case notConnected         // no tokens
    case userCancelled
    case authFailed(String)
    case network(String)
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Aucun identifiant OAuth Google. Ajoute-le dans Réglages."
        case .notConnected:  return "Compte Gmail non connecté. Connecte-toi dans Réglages."
        case .userCancelled: return "Connexion annulée."
        case .authFailed(let m): return "Échec de l'authentification : \(m)"
        case .network(let m):    return "Erreur réseau : \(m)"
        case .sendFailed(let m): return "Envoi impossible : \(m)"
        }
    }
}

/// Google OAuth 2.0 with PKCE for installed apps (no client secret, no backend).
/// Presents the Google consent screen via `ASWebAuthenticationSession` and
/// stores the resulting tokens in the Keychain.
@MainActor
final class GoogleOAuthService: NSObject {

    private let secretStore: SecretStore
    private let session: URLSession
    /// Strong reference so the auth session isn't deallocated mid-flow.
    private var authSession: ASWebAuthenticationSession?

    init(secretStore: SecretStore, session: URLSession = .shared) {
        self.secretStore = secretStore
        self.session = session
    }

    // MARK: State

    var isConnected: Bool {
        secretStore.value(AppConfig.gmailRefreshTokenAccount) != nil
    }

    var connectedAddress: String? {
        secretStore.value(AppConfig.gmailAddressAccount)
    }

    var clientID: String? {
        secretStore.value(AppConfig.gmailClientIDAccount)
    }

    /// The reversed-client-id URL scheme Google iOS clients redirect to.
    private func redirectScheme(for clientID: String) -> String {
        // 123-abc.apps.googleusercontent.com → com.googleusercontent.apps.123-abc
        if let range = clientID.range(of: ".apps.googleusercontent.com") {
            let prefix = String(clientID[clientID.startIndex..<range.lowerBound])
            return "com.googleusercontent.apps.\(prefix)"
        }
        return "com.googleusercontent.apps.\(clientID)"
    }

    // MARK: Connect / disconnect

    func connect() async throws {
        guard let clientID = clientID else { throw GmailError.notConfigured }

        let scheme = redirectScheme(for: clientID)
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.codeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(url: AppConfig.googleAuthEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: AppConfig.gmailScopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        let callbackURL = try await authenticate(url: components.url!, scheme: scheme)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GmailError.authFailed("code manquant")
        }

        try await exchangeCode(code, clientID: clientID, redirectURI: redirectURI, verifier: verifier)
        try? await fetchAndStoreAddress()
    }

    func disconnect() {
        try? secretStore.delete(account: AppConfig.gmailAccessTokenAccount)
        try? secretStore.delete(account: AppConfig.gmailRefreshTokenAccount)
        try? secretStore.delete(account: AppConfig.gmailTokenExpiryAccount)
        try? secretStore.delete(account: AppConfig.gmailAddressAccount)
    }

    // MARK: Tokens

    /// A valid access token, refreshing if needed.
    func validAccessToken() async throws -> String {
        guard let clientID = clientID else { throw GmailError.notConfigured }
        guard let refresh = secretStore.value(AppConfig.gmailRefreshTokenAccount) else {
            throw GmailError.notConnected
        }
        if let token = secretStore.value(AppConfig.gmailAccessTokenAccount),
           let expiryString = secretStore.value(AppConfig.gmailTokenExpiryAccount),
           let expiry = ISO8601DateFormatter().date(from: expiryString),
           expiry.timeIntervalSinceNow > 60 {
            return token
        }
        return try await refreshAccessToken(refresh, clientID: clientID)
    }

    // MARK: - Private

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(
                url: url, callbackURLScheme: scheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GmailError.userCancelled)
                    } else {
                        continuation.resume(throwing: GmailError.authFailed(error.localizedDescription))
                    }
                } else {
                    continuation.resume(throwing: GmailError.authFailed("réponse vide"))
                }
            }
            webSession.presentationContextProvider = self
            webSession.prefersEphemeralWebBrowserSession = false
            self.authSession = webSession
            if !webSession.start() {
                continuation.resume(throwing: GmailError.authFailed("session non démarrée"))
            }
        }
    }

    private func exchangeCode(
        _ code: String, clientID: String, redirectURI: String, verifier: String
    ) async throws {
        let params = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let token = try await postToken(params)
        store(token)
    }

    private func refreshAccessToken(_ refresh: String, clientID: String) async throws -> String {
        let params = [
            "refresh_token": refresh,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ]
        let token = try await postToken(params)
        store(token, keepingRefresh: refresh)
        return token.accessToken
    }

    private func postToken(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: AppConfig.googleTokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "erreur"
                throw GmailError.authFailed(message)
            }
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch let error as GmailError {
            throw error
        } catch {
            throw GmailError.network(error.localizedDescription)
        }
    }

    private func store(_ token: TokenResponse, keepingRefresh: String? = nil) {
        try? secretStore.save(token.accessToken, account: AppConfig.gmailAccessTokenAccount)
        if let refresh = token.refreshToken ?? keepingRefresh {
            try? secretStore.save(refresh, account: AppConfig.gmailRefreshTokenAccount)
        }
        let expiry = Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 3600))
        try? secretStore.save(ISO8601DateFormatter().string(from: expiry),
                              account: AppConfig.gmailTokenExpiryAccount)
    }

    private func fetchAndStoreAddress() async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(AppConfig.gmailAPIBase)/profile")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        if let email = try? JSONDecoder().decode(Profile.self, from: data).emailAddress {
            try? secretStore.save(email, account: AppConfig.gmailAddressAccount)
        }
    }

    // MARK: PKCE helpers

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    // MARK: DTOs

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct Profile: Decodable {
        let emailAddress: String?
    }
}

// MARK: - Presentation anchor

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
            #elseif os(macOS)
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #else
            return ASPresentationAnchor()
            #endif
        }
    }
}

private extension Data {
    /// Base64URL without padding, as required by PKCE.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
