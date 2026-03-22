import Foundation
import Combine
import CryptoKit
import AppKit

enum APIError: Error, LocalizedError {
    case noToken
    case invalidResponse
    case httpError(statusCode: Int)
    case networkError(Error)
    case certificatePinningFailed
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "Not signed in"
        case .invalidResponse:
            return "Unable to connect. Please try again."
        case .httpError(let code):
            if code == 401 {
                return "Session expired. Please sign in again."
            } else if code >= 500 {
                return "Service temporarily unavailable."
            }
            return "Unable to fetch usage data."
        case .networkError:
            return "Network connection failed."
        case .certificatePinningFailed:
            return "Secure connection could not be established."
        case .rateLimited:
            return "Too many attempts. Please wait a moment."
        }
    }
}

/// URLSession delegate that implements certificate pinning for api.anthropic.com
final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {
    // SHA-256 hashes of the Subject Public Key Info (SPKI) for Anthropic's certificate chain
    // Include both leaf and intermediate CA pins for redundancy during cert rotation
    //
    // To obtain these pins, run:
    // openssl s_client -connect api.anthropic.com:443 -servername api.anthropic.com 2>/dev/null | \
    //   openssl x509 -pubkey -noout | \
    //   openssl pkey -pubin -outform der | \
    //   openssl dgst -sha256 -binary | base64
    //
    // UPDATE THESE HASHES when Anthropic rotates certificates
    // Last updated: March 2026
    private let pinnedPublicKeyHashes: Set<String> = [
        // api.anthropic.com leaf certificate (CN=api.anthropic.com)
        "60QDDZy98CjK1XTBTlPbInyzJzi+817KvW+usCk6r+o=",
        // Google Trust Services WE1 intermediate CA (backup pin for cert rotation)
        "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",
    ]

    private let pinnedHosts: Set<String> = ["api.anthropic.com"]

    // Certificate pinning enabled for MITM protection
    // If connection fails after cert rotation, update the pins above
    private let enforcePinning = true

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              pinnedHosts.contains(challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust against system CAs first
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // If pinning is enforced and we have pins, verify against them
        if enforcePinning && !pinnedPublicKeyHashes.isEmpty {
            let certificateCount = SecTrustGetCertificateCount(serverTrust)

            var foundMatch = false
            for index in 0..<certificateCount {
                guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index),
                      let publicKey = SecCertificateCopyKey(certificate),
                      let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                    continue
                }

                // Compute SHA-256 hash of the public key
                let hash = SHA256.hash(data: publicKeyData)
                let hashBase64 = Data(hash).base64EncodedString()

                if pinnedPublicKeyHashes.contains(hashBase64) {
                    foundMatch = true
                    break
                }
            }

            guard foundMatch else {
                // Certificate chain doesn't match any pinned keys
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}

/// Simple rate limiter with exponential backoff
actor RateLimiter {
    private var failureCount = 0
    private var lastFailureTime: Date?
    private let maxFailures = 5
    private let baseDelay: TimeInterval = 2.0

    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
    }

    func recordSuccess() {
        failureCount = 0
        lastFailureTime = nil
    }

    func shouldAllowAttempt() -> Bool {
        guard failureCount >= maxFailures, let lastFailure = lastFailureTime else {
            return true
        }

        // Exponential backoff: 2^(failures-maxFailures) * baseDelay, capped at 5 minutes
        let backoffMultiplier = min(pow(2.0, Double(failureCount - maxFailures)), 150.0)
        let requiredDelay = baseDelay * backoffMultiplier
        let elapsed = Date().timeIntervalSince(lastFailure)

        return elapsed >= requiredDelay
    }

    func reset() {
        failureCount = 0
        lastFailureTime = nil
    }
}

@MainActor
final class UsageAPIService: ObservableObject {
    static let shared = UsageAPIService()

    @Published var usageData: UsageData?
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var error: APIError?
    @Published var isSignedIn = false
    @Published var isSyncedFromClaudeCode = false

    private let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var refreshTimer: Timer?
    private let urlSession: URLSession
    private let rateLimiter = RateLimiter()
    private var isRefreshingToken = false
    private var rateLimitedUntil: Date?
    /// In-memory token cache — avoids reading from keychain on every poll,
    /// which prevents login-keychain-password popups when the keychain is locked after sleep.
    private var cachedToken: String?

    private init() {
        // Create URLSession with certificate pinning delegate
        let delegate = PinnedURLSessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        checkAuthStatus()
        SettingsService.shared.onRefreshIntervalChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.restartAutoRefresh()
            }
        }

        // Refresh token and re-fetch after wake from sleep
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Stop the timer so it doesn't race with this wake handler and cause a 429
                self.stopAutoRefresh()
                // Give the network 3 seconds to come up, then force a refresh
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                // Clear rate-limit cooldown after the wait so the timer can't re-set it during sleep
                self.rateLimitedUntil = nil
                let freshToken = await self.refreshClaudeCodeToken()
                await self.fetchUsageInternal(token: freshToken)
                // Restart periodic refresh — skip immediate fetch since we just fetched above
                self.startAutoRefresh(fetchImmediately: false)
            }
        }
    }

    private func restartAutoRefresh() {
        if refreshTimer != nil {
            startAutoRefresh()
        }
    }

    func checkAuthStatus() {
        // Prefer our own cached token, then our own keychain, then Claude Code's keychain as last resort
        if cachedToken != nil || KeychainService.shared.readAppToken() != nil {
            isSignedIn = true
            isSyncedFromClaudeCode = false
        } else if KeychainService.shared.readClaudeCodeToken() != nil {
            isSignedIn = true
            isSyncedFromClaudeCode = true
        } else {
            isSignedIn = false
            isSyncedFromClaudeCode = false
        }
    }

    func startAutoRefresh() {
        startAutoRefresh(fetchImmediately: true)
    }

    private func startAutoRefresh(fetchImmediately: Bool) {
        stopAutoRefresh()

        if fetchImmediately {
            Task { await fetchUsage() }
        }

        let interval = SettingsService.shared.refreshInterval.seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func fetchUsage() async {
        await fetchUsageInternal(token: nil)
    }

    private func fetchUsageInternal(token overrideToken: String?) async {
        // Skip if we're still in a 429 rate-limit cooldown
        if let until = rateLimitedUntil, Date() < until {
            return
        }

        // Resolve token: in-memory cache → our own keychain → Claude Code's keychain (bootstrap only).
        // The memory cache is the key: after the first successful fetch the token lives in memory,
        // so subsequent polls never touch the keychain and never trigger the password popup.
        let token: String
        let usingClaudeCodeToken: Bool
        if let override = overrideToken {
            token = override
            usingClaudeCodeToken = true
        } else if let cached = cachedToken {
            token = cached
            usingClaudeCodeToken = false
        } else if let appToken = KeychainService.shared.readAppToken() {
            token = appToken
            usingClaudeCodeToken = false
        } else if let claudeCodeToken = KeychainService.shared.readClaudeCodeToken() {
            // One-time bootstrap from Claude Code's keychain. Cache refresh token immediately so
            // after the first token refresh we never need Claude Code's keychain again.
            if let refreshToken = KeychainService.shared.readClaudeCodeRefreshToken() {
                try? KeychainService.shared.saveRefreshedTokens(
                    accessToken: claudeCodeToken,
                    refreshToken: refreshToken
                )
            }
            token = claudeCodeToken
            usingClaudeCodeToken = true
        } else {
            error = .noToken
            isSignedIn = false
            isSyncedFromClaudeCode = false
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 429 {
                    // Respect Retry-After header; default to 60s
                    let retryAfter: TimeInterval
                    if let header = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                       let seconds = TimeInterval(header) {
                        retryAfter = seconds
                    } else {
                        retryAfter = 60
                    }
                    rateLimitedUntil = Date().addingTimeInterval(retryAfter)
                    throw APIError.rateLimited
                }
                if httpResponse.statusCode == 401 && overrideToken == nil {
                    // Token expired — try to refresh via stored refresh token
                    if let freshToken = await refreshClaudeCodeToken() {
                        await fetchUsageInternal(token: freshToken)
                        return
                    }
                    // Refresh failed — require re-login
                    isSignedIn = false
                    isSyncedFromClaudeCode = false
                    cachedToken = nil
                    try? KeychainService.shared.deleteAppToken()
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let usage = try decoder.decode(UsageData.self, from: data)
            self.usageData = usage
            self.lastUpdated = Date()
            self.isSignedIn = true
            self.isSyncedFromClaudeCode = usingClaudeCodeToken
            self.cachedToken = token  // cache so subsequent polls skip keychain entirely

        } catch let apiError as APIError {
            self.error = apiError
        } catch {
            self.error = .networkError(error)
        }

        isLoading = false
    }

    /// Refreshes the OAuth access token using the stored refresh token.
    /// Stores refreshed tokens in our own keychain — never touches Claude Code's keychain.
    @discardableResult
    private func refreshClaudeCodeToken() async -> String? {
        guard !isRefreshingToken else { return nil }
        isRefreshingToken = true
        defer { isRefreshingToken = false }

        guard let refreshToken = KeychainService.shared.readRefreshToken() else {
            return nil
        }

        let refreshURL = URL(string: "https://claude.ai/api/auth/oauth/token")!
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "claude_code_cli"
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String,
                  let newRefreshToken = json["refresh_token"] as? String else {
                return nil
            }

            // Store in our own keychain — never write to Claude Code's keychain (triggers ACL prompts)
            try? KeychainService.shared.saveRefreshedTokens(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken
            )
            return newAccessToken
        } catch {
            return nil
        }
    }

    /// Validates a token by making an API call, then stores it only if valid
    func signIn(withToken token: String) async -> Bool {
        // Check rate limiting
        guard await rateLimiter.shouldAllowAttempt() else {
            error = .rateLimited
            return false
        }

        isLoading = true
        error = nil

        // Validate the token first by making an API call
        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                await rateLimiter.recordFailure()
                throw APIError.httpError(statusCode: httpResponse.statusCode)
            }

            // Token is valid - now save it
            try KeychainService.shared.saveAppToken(token)
            await rateLimiter.recordSuccess()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let usage = try decoder.decode(UsageData.self, from: data)
            self.usageData = usage
            self.lastUpdated = Date()
            self.isSignedIn = true
            self.isLoading = false

            return true

        } catch let apiError as APIError {
            self.error = apiError
            self.isLoading = false
            return false
        } catch {
            await rateLimiter.recordFailure()
            self.error = .networkError(error)
            self.isLoading = false
            return false
        }
    }

    /// Attempts to sync token from Claude Code and sign in
    func syncFromClaudeCode() async -> Bool {
        guard let token = KeychainService.shared.readClaudeCodeToken() else {
            return false
        }

        isLoading = true
        error = nil

        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw APIError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let usage = try decoder.decode(UsageData.self, from: data)
            self.usageData = usage
            self.lastUpdated = Date()
            self.isSignedIn = true
            self.isSyncedFromClaudeCode = true
            self.isLoading = false

            return true

        } catch let apiError as APIError {
            self.error = apiError
            self.isLoading = false
            return false
        } catch {
            self.error = .networkError(error)
            self.isLoading = false
            return false
        }
    }

    func signOut() {
        cachedToken = nil
        try? KeychainService.shared.deleteAppToken()
        usageData = nil
        lastUpdated = nil
        isSignedIn = false
        isSyncedFromClaudeCode = false
        stopAutoRefresh()
        Task {
            await rateLimiter.reset()
        }
    }
}
