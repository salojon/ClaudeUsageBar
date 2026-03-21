import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var sessionUtilization: Double?
    @Published var sessionResetsAt: Date?
    @Published var weeklyUtilization: Double?
    @Published var weeklyResetsAt: Date?
    @Published var lastUpdated: Date?
    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var launchAtLogin: Bool = false

    // No cached token — always read fresh from Claude Code's Keychain so we
    // automatically pick up any token Claude Code refreshes behind the scenes.
    private var manualToken: String?   // only set when user pastes a token manually
    private var refreshTimer: Timer?

    var statusColor: Color {
        let max = Swift.max(sessionUtilization ?? 0, weeklyUtilization ?? 0)
        if max > 80 { return .red }
        if max > 50 { return .orange }
        return .green
    }

    init() {
        launchAtLogin = LaunchAtLoginService.isEnabled
        manualToken = KeychainService.readAppToken()
        isSignedIn = currentToken != nil
        if isSignedIn {
            Task { await fetchUsage() }
        }
        startTimer()
    }

    /// Always returns the freshest available token.
    /// Prefers Claude Code's Keychain (auto-refreshed by Claude Code) over a manually stored token.
    private var currentToken: String? {
        KeychainService.readClaudeCodeToken() ?? manualToken
    }

    func signIn(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manualToken = trimmed
        KeychainService.saveAppToken(trimmed)
        isSignedIn = true
        error = nil
        Task { await fetchUsage() }
    }

    func signOut() {
        manualToken = nil
        KeychainService.deleteAppToken()
        isSignedIn = false
        sessionUtilization = nil
        sessionResetsAt = nil
        weeklyUtilization = nil
        weeklyResetsAt = nil
        lastUpdated = nil
        error = nil
    }

    func fetchUsage() async {
        // Read fresh token every time — Claude Code refreshes it automatically
        guard let token = currentToken else {
            isSignedIn = false
            return
        }
        isSignedIn = true
        isLoading = true
        error = nil
        do {
            let usage = try await UsageAPIService.fetchUsage(token: token)
            sessionUtilization = usage.fiveHour.utilization
            sessionResetsAt = usage.fiveHour.resetsAt
            weeklyUtilization = usage.sevenDay.utilization
            weeklyResetsAt = usage.sevenDay.resetsAt
            lastUpdated = Date()
        } catch APIError.unauthorized {
            // Token truly invalid — try one more fresh read in case Claude Code
            // just refreshed it between our read and the API call
            if let freshToken = currentToken, freshToken != token {
                _ = try? await UsageAPIService.fetchUsage(token: freshToken)
            } else {
                error = "Session expired. Please run `claude login` in Terminal."
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLoginService.setEnabled(enabled)
        launchAtLogin = LaunchAtLoginService.isEnabled
    }

    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isSignedIn else { return }
                await self.fetchUsage()
            }
        }
    }
}
