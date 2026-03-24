import Foundation

enum SettingsService {
    private static let refreshIntervalKey = "com.jonathansela.ClaudeUsageBar.refreshInterval"

    static func saveRefreshInterval(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: refreshIntervalKey)
    }

    static func readRefreshInterval() -> Int {
        let saved = UserDefaults.standard.integer(forKey: refreshIntervalKey)
        return saved > 0 ? saved : 10 // Default to 10 minutes
    }
}
