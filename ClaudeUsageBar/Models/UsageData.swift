import Foundation

struct UsageData: Codable {
    let fiveHour: UsagePeriod
    let sevenDay: UsagePeriod

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct UsagePeriod: Codable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

extension UsagePeriod {
    var timeUntilReset: String {
        let now = Date()
        let interval = resetsAt.timeIntervalSince(now)

        guard interval > 0 else { return "Resetting..." }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var utilizationPercent: Int {
        Int(utilization.rounded())
    }
}
