import Foundation
import Security

/// Minimal, testable Keychain wrapper. Used to store the Anthropic API key.
///
/// The key is stored as a generic password. When a Keychain access group is
/// configured (see `SETUP.md`), both the app and the Share Extension can read
/// it; if not, it silently falls back to the target's private Keychain.
protocol SecretStore {
    func save(_ value: String, account: String) throws
    func read(account: String) throws -> String?
    func delete(account: String) throws
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataEncoding

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
            return "Erreur Keychain : \(message)"
        case .dataEncoding:
            return "Impossible d'encoder la valeur pour le Keychain."
        }
    }
}

struct KeychainService: SecretStore {

    /// Optional Keychain access group. When nil, the item is stored in the
    /// target's default group. Pass `AppConfig.keychainAccessGroupSuffix`-derived
    /// value only if you configured Keychain Sharing on both targets.
    let accessGroup: String?

    init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataEncoding }

        var query = baseQuery(account: account)
        // Remove any existing item first for a clean upsert.
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Convenience for the API key

extension SecretStore {
    /// Reads the stored Anthropic API key, if any.
    func anthropicAPIKey() -> String? {
        value(AppConfig.apiKeyKeychainAccount)
    }

    /// Reads a stored secret by account, trimmed and nil if empty/absent.
    func value(_ account: String) -> String? {
        (try? read(account: account))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
