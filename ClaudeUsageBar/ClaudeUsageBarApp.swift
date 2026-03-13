import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var apiService = UsageAPIService.shared
    @StateObject private var launchService = LaunchAtLoginService.shared
    @StateObject private var settingsService = SettingsService.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(apiService: apiService, launchService: launchService, settingsService: settingsService)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)

            if let usage = apiService.usageData {
                Text("\(usage.fiveHour.utilizationPercent)/\(usage.sevenDay.utilizationPercent)")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .onAppear {
            apiService.startAutoRefresh()
        }
    }

    private var statusIcon: String {
        guard apiService.isSignedIn else {
            return "clock"
        }

        guard apiService.usageData != nil else {
            return "clock"
        }

        return "clock"
    }

    private var statusColor: Color {
        guard apiService.isSignedIn, let usage = apiService.usageData else {
            return .secondary
        }

        let maxUsage = max(usage.fiveHour.utilization, usage.sevenDay.utilization)

        if maxUsage >= 90 {
            return .red
        } else if maxUsage >= 70 {
            return .orange
        } else {
            return .green
        }
    }
}
