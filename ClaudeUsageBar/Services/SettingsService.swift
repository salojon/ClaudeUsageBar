import Foundation
import Combine

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }
}

@MainActor
final class SettingsService: ObservableObject {
    static let shared = SettingsService()

    private let refreshIntervalKey = "refreshInterval"

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: refreshIntervalKey)
            onRefreshIntervalChanged?()
        }
    }

    var onRefreshIntervalChanged: (() -> Void)?

    private init() {
        let storedValue = UserDefaults.standard.integer(forKey: refreshIntervalKey)
        if storedValue > 0, let interval = RefreshInterval(rawValue: storedValue) {
            refreshInterval = interval
        } else {
            refreshInterval = .tenMinutes
        }
    }
}
