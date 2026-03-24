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
    @Published var refreshInterval: Int = 10 {
        didSet {
            SettingsService.saveRefreshInterval(refreshInterval)
            restartTimer()
        }
    }

    private var manualToken: String?
    private var refreshTimer: Timer?
    private var retryTimer: Timer?

    var statusColor: Color {
        let max = Swift.max(sessionUtilization ?? 0, weeklyUtilization ?? 0)
        if max > 80 { return .red }
        if max > 50 { return .orange }
        return .green
    }

    init() {
        launchAtLogin = LaunchAtLoginService.isEnabled
        refreshInterval = SettingsService.readRefreshInterval()

        // Try to read stored or Claude Code token
        if let savedToken = KeychainService.readAppToken() {
            manualToken = savedToken
            isSignedIn = true
        } else if KeychainService.readClaudeCodeToken() != nil {
            isSignedIn = true
        } else {
            isSignedIn = false
        }

        startTimer()

        // Fetch on startup after a brief delay (allows app to fully initialize)
        if isSignedIn {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second delay
                await self.fetchUsage()
            }
        }
    }

    /// Prefer personal API key, then app's stored token, then Claude Code's token
    private var currentToken: String? {
        KeychainService.readAPIKey() ?? manualToken ?? KeychainService.readClaudeCodeToken()
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
        // Prevent rapid-fire requests (enforce 1 hour minimum between fetches)
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 3600 {
            return
        }

        isLoading = true
        error = nil

        do {
            // Try OAuth token first (from Claude Code keychain)
            if let token = KeychainService.readClaudeCodeToken() {
                let usage = try await UsageAPIService.fetchUsage(token: token)
                sessionUtilization = usage.fiveHour.utilization
                sessionResetsAt = usage.fiveHour.resetsAt
                weeklyUtilization = usage.sevenDay.utilization
                weeklyResetsAt = usage.sevenDay.resetsAt
                lastUpdated = Date()
                isSignedIn = true
                error = nil
            } else if let token = manualToken ?? KeychainService.readAppToken() {
                let usage = try await UsageAPIService.fetchUsage(token: token)
                sessionUtilization = usage.fiveHour.utilization
                sessionResetsAt = usage.fiveHour.resetsAt
                weeklyUtilization = usage.sevenDay.utilization
                weeklyResetsAt = usage.sevenDay.resetsAt
                lastUpdated = Date()
                isSignedIn = true
                error = nil
            } else {
                isSignedIn = false
                error = "No token found. Run 'claude login' first."
            }
        } catch APIError.rateLimited {
            // Just show a message, don't clear previous data
            error = "Rate limited. Last update: \(formatLastUpdate())"
        } catch let err {
            error = "Unable to fetch: \(err.localizedDescription)"
        }
        isLoading = false
    }

    private func formatLastUpdate() -> String {
        guard let lastUpdated else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLoginService.setEnabled(enabled)
        launchAtLogin = LaunchAtLoginService.isEnabled
    }

    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(refreshInterval * 60), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isSignedIn else { return }
                await self.fetchUsage()
            }
        }
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        startTimer()
    }

    private func startRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchUsage()
            }
        }
    }
}
