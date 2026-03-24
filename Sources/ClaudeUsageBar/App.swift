import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        let util = appState.sessionUtilization ?? 0
        // More usage = fewer bars: <50%: 3 bars, 50-80%: 2 bars, >80%: 1 bar
        let bars = util > 80 ? 1 : util > 50 ? 2 : 3
        let color = util > 80 ? "🔴" : util > 50 ? "🟠" : "🟢"
        let barStr = String(repeating: "▪", count: bars)

        return Text("\(color)\(barStr)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .lineSpacing(-2)
    }

    private func barColor(for utilization: Double, barIndex: Int) -> Color {
        // Show bars based on utilization: 1-3 bars filled
        // 0-33%: 1 bar, 33-66%: 2 bars, 66-100%: 3 bars
        let fillThreshold = Double(barIndex) / 3 * 100
        if utilization > fillThreshold {
            return appState.statusColor
        }
        return Color.gray.opacity(0.3)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running when window closes
    }
}
