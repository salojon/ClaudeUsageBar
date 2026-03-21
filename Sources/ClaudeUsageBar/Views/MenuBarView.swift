import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isSignedIn {
                usageContent
            } else {
                SignInView()
            }
        }
    }

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle")
                    .foregroundColor(.secondary)
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                if appState.isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button {
                        Task { await appState.fetchUsage() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
                }
            }
            .padding(.bottom, 10)

            Divider()
                .padding(.bottom, 12)

            // Error banner
            if let error = appState.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(6)
                .padding(.bottom, 10)
            }

            // Session usage
            UsageRowView(
                title: "Session",
                subtitle: "5-hour window",
                utilization: appState.sessionUtilization,
                resetsAt: appState.sessionResetsAt
            )

            Divider()
                .padding(.vertical, 10)

            // Weekly usage
            UsageRowView(
                title: "Weekly",
                subtitle: "7-day window",
                utilization: appState.weeklyUtilization,
                resetsAt: appState.weeklyResetsAt
            )

            Divider()
                .padding(.vertical, 10)

            // Last updated
            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }

            Divider()
                .padding(.bottom, 10)

            // Launch at Login toggle
            Toggle("Launch at Login", isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.setLaunchAtLogin($0) }
            ))
            .font(.callout)
            .padding(.bottom, 8)

            // Sign Out + Quit
            HStack {
                Button("Sign Out") {
                    appState.signOut()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .font(.callout)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .font(.callout)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
