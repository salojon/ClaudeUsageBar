import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.bar.fill")
            if appState.isSignedIn, let util = appState.sessionUtilization {
                Text("\(Int(util.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundColor(appState.isSignedIn ? appState.statusColor : .secondary)
    }
}
