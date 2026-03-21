import SwiftUI

struct SignInView: View {
    @EnvironmentObject var appState: AppState
    @State private var manualToken = ""
    @State private var showManual = false
    @State private var isAttempting = false
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Claude Usage")
                .font(.headline)

            Text("Sign in to view your usage limits")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                attemptAutoSignIn()
            } label: {
                HStack {
                    if isAttempting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "key.fill")
                    }
                    Text("Use Claude Code Session")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAttempting)

            if let err = localError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Divider()

            if showManual {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste your OAuth access token:")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("sk-ant-oat01-...", text: $manualToken, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(2...4)
                    HStack {
                        Button("Sign In") {
                            appState.signIn(token: manualToken)
                        }
                        .buttonStyle(.bordered)
                        .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    Text("Run `claude login` in Terminal to get a token.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Button("Enter token manually") {
                    showManual = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 280)
    }

    private func attemptAutoSignIn() {
        isAttempting = true
        localError = nil
        if let token = KeychainService.readClaudeCodeToken() {
            appState.signIn(token: token)
        } else {
            localError = "No active Claude Code session found.\nRun `claude login` in Terminal first."
            showManual = true
        }
        isAttempting = false
    }
}
