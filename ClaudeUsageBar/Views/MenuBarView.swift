import SwiftUI

struct MenuBarView: View {
    @ObservedObject var apiService: UsageAPIService
    @ObservedObject var launchService: LaunchAtLoginService
    @ObservedObject var settingsService: SettingsService

    @State private var showingTokenInput = false
    @State private var tokenError: String?
    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if apiService.isSignedIn {
                signedInContent
            } else {
                signedOutContent
            }

            Divider()
                .padding(.vertical, 8)

            settingsSection

            Divider()
                .padding(.vertical, 8)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        .sheet(isPresented: $showingTokenInput) {
            tokenInputSheet
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if let usage = apiService.usageData {
            UsageRowView(title: "Session (5hr)", usage: usage.fiveHour)

            Divider()
                .padding(.vertical, 8)

            UsageRowView(title: "Weekly (7day)", usage: usage.sevenDay)

            Divider()
                .padding(.vertical, 8)

            if let lastUpdated = apiService.lastUpdated {
                Text("Last updated: \(timeAgo(lastUpdated))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if apiService.isLoading {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else if let error = apiService.error {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }

        Button {
            Task {
                await apiService.fetchUsage()
            }
        } label: {
            Label("Refresh Now", systemImage: "arrow.clockwise")
        }
        .disabled(apiService.isLoading)
    }

    @ViewBuilder
    private var signedOutContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("Not signed in")
                .font(.headline)

            Text("Sign in to view your Claude usage")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let syncError = syncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button {
                    syncFromClaudeCode()
                } label: {
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        Text("Sync from Claude Code")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncing)

                Button("Enter Token Manually") {
                    showingTokenInput = true
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func syncFromClaudeCode() {
        isSyncing = true
        syncError = nil
        Task {
            let success = await apiService.syncFromClaudeCode()
            isSyncing = false
            if !success {
                if apiService.error != nil {
                    syncError = "Token validation failed. Is Claude Code logged in?"
                } else {
                    syncError = "No Claude Code token found. Run 'claude login' first."
                }
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        Toggle("Launch at Login", isOn: $launchService.isEnabled)

        HStack {
            Text("Refresh every")
            Spacer()
            Picker("", selection: $settingsService.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }

        if apiService.isSignedIn {
            Button("Sign Out") {
                apiService.signOut()
            }
            .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var tokenInputSheet: some View {
        TokenInputView(
            apiService: apiService,
            isPresented: $showingTokenInput,
            tokenError: $tokenError
        )
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval) / 60

        if minutes < 1 {
            return "just now"
        } else if minutes == 1 {
            return "1 min ago"
        } else {
            return "\(minutes) mins ago"
        }
    }
}

/// Separate view for token input to properly manage secure token memory
struct TokenInputView: View {
    @ObservedObject var apiService: UsageAPIService
    @Binding var isPresented: Bool
    @Binding var tokenError: String?

    @State private var tokenInput = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Sign In to Claude")
                .font(.headline)

            Text("To get your OAuth token:\n1. Run 'claude login' in Terminal\n2. Copy the token from Keychain Access\n   (search for 'Claude Code')")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Use SecureField to prevent shoulder-surfing
            SecureField("OAuth Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)

            if let error = tokenError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    clearAndDismiss()
                }

                Spacer()

                Button("Sign In") {
                    guard !tokenInput.isEmpty else {
                        tokenError = "Please enter a token"
                        return
                    }
                    let token = tokenInput
                    // Clear input immediately after capturing
                    tokenInput = ""
                    Task {
                        let success = await apiService.signIn(withToken: token)
                        if success {
                            clearAndDismiss()
                        } else {
                            tokenError = apiService.error?.localizedDescription ?? "Sign in failed"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenInput.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onDisappear {
            // Clear sensitive data when view disappears
            tokenInput = ""
        }
    }

    private func clearAndDismiss() {
        tokenInput = ""
        tokenError = nil
        isPresented = false
    }
}
