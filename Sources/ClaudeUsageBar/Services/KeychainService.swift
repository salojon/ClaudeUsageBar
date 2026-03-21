import Security
import Foundation

enum KeychainService {
    private static let appService = "ClaudeUsageBar"
    private static let appAccount = "oauth-token"
    private static let claudeCodeService = "Claude Code-credentials"

    // MARK: - App's own token storage

    static func readAppToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecAttrAccount as String: appAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func saveAppToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        deleteAppToken()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecAttrAccount as String: appAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteAppToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: appService,
            kSecAttrAccount as String: appAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Read Claude Code's OAuth token

    static func readClaudeCodeToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8) else { return nil }

        // Claude Code stores credentials as JSON: { "claudeAiOauth": { "accessToken": "..." } }
        struct Credentials: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
            }
            let claudeAiOauth: OAuth
        }

        return try? JSONDecoder().decode(Credentials.self, from: jsonData).claudeAiOauth.accessToken
    }
}
