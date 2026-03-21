import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)
}

final class KeychainService {
    static let shared = KeychainService()

    private let appService = "ClaudeUsageBar-token"
    private let account = "oauth-token"

    // Keychain access group - must match entitlements
    // Format: $(AppIdentifierPrefix)bundleIdentifier
    private var accessGroup: String? {
        // In production, this should be set to your actual access group
        // For development without a team, return nil to use default
        return nil
    }

    private init() {}

    /// Reads the full Claude Code credentials JSON from keychain
    private func readClaudeCodeCredentials() -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Fail silently instead of prompting with a password dialog if the item is ACL-protected
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let jsonData = String(data: data, encoding: .utf8)?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        return json
    }

    /// Reads OAuth token directly from Claude Code's keychain entry
    /// This allows automatic token sync without manual copy/paste
    /// Security: Reads directly via Security framework instead of shelling out
    func readClaudeCodeToken() -> String? {
        guard let json = readClaudeCodeCredentials(),
              let claudeAiOauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = claudeAiOauth["accessToken"] as? String,
              isValidTokenFormat(accessToken) else {
            return nil
        }
        return accessToken
    }

    /// Reads the refresh token from Claude Code's keychain entry
    func readClaudeCodeRefreshToken() -> String? {
        guard let json = readClaudeCodeCredentials(),
              let claudeAiOauth = json["claudeAiOauth"] as? [String: Any],
              let refreshToken = claudeAiOauth["refreshToken"] as? String else {
            return nil
        }
        return refreshToken
    }

    /// Updates Claude Code's keychain entry with a refreshed access token and new refresh token.
    /// Preserves all other fields in the credentials JSON.
    func updateClaudeCodeTokens(accessToken: String, refreshToken: String) throws {
        guard var json = readClaudeCodeCredentials(),
              var claudeAiOauth = json["claudeAiOauth"] as? [String: Any] else {
            throw KeychainError.itemNotFound
        }

        claudeAiOauth["accessToken"] = accessToken
        claudeAiOauth["refreshToken"] = refreshToken
        json["claudeAiOauth"] = claudeAiOauth

        guard let updatedData = try? JSONSerialization.data(withJSONObject: json) else {
            throw KeychainError.unexpectedData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let attributes: [String: Any] = [kSecValueData as String: updatedData]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Validates OAuth token format
    private func isValidTokenFormat(_ token: String) -> Bool {
        // Anthropic OAuth tokens start with sk-ant-oat (OAuth Access Token)
        // or sk-ant-ort (OAuth Refresh Token)
        let pattern = "^sk-ant-o[ar]t[0-9]{2}-[A-Za-z0-9_-]+$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(token.startIndex..., in: token)
        return regex.firstMatch(in: token, range: range) != nil
    }

    /// Reads the app's stored OAuth token
    func readAppToken() -> String? {
        guard let data = try? readKeychainData(),
              let token = String(data: data, encoding: .utf8),
              isValidTokenFormat(token) else {
            return nil
        }
        return token
    }

    /// Stores the OAuth token in the app's keychain entry with secure access controls
    func saveAppToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Delete existing item first to ensure clean state
        try? deleteAppToken()

        // Create new item with secure access controls
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Only accessible when device is unlocked, not included in backups
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // Prevent synchronization to iCloud Keychain
            kSecAttrSynchronizable as String: false
        ]

        // Add access group if configured
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Deletes the app's stored OAuth token
    func deleteAppToken() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecAttrAccount as String: account
        ]

        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    private func readKeychainData() throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }
}
