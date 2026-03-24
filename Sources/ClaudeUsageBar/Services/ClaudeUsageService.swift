import Foundation

struct UsageData {
    let sessionUtilization: Double
    let sessionResetsAt: Date?
    let weeklyUtilization: Double
    let weeklyResetsAt: Date?
}

enum ClaudeUsageService {
    static func fetchUsage() async throws -> UsageData {
        // Run `claude usage` command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "usage"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // Suppress errors

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ClaudeUsageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read command output"])
        }

        return try parseOutput(output)
    }

    private static func parseOutput(_ output: String) throws -> UsageData {
        let lines = output.components(separatedBy: .newlines)

        var sessionPercent: Double?
        var weeklyPercent: Double?
        var sessionReset: String?
        var weeklyReset: String?

        var isSessionSection = false
        var isWeeklySection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect sections
            if trimmed.contains("Current session") && !trimmed.contains("week") {
                isSessionSection = true
                isWeeklySection = false
                continue
            } else if trimmed.contains("Current week") {
                isSessionSection = false
                isWeeklySection = true
                continue
            }

            // Parse percentages (e.g., "22% used" or "35% used")
            if trimmed.contains("% used") {
                if let percentStr = trimmed.components(separatedBy: "%").first,
                   let percent = Double(percentStr.trimmingCharacters(in: .whitespaces)) {
                    if isSessionSection {
                        sessionPercent = percent
                    } else if isWeeklySection {
                        weeklyPercent = percent
                    }
                }
            }

            // Parse reset times (e.g., "Resets 4pm (Asia/Jerusalem)" or "Resets Mar 27 at 5pm (Asia/Jerusalem)")
            if trimmed.hasPrefix("Resets") {
                if isSessionSection {
                    sessionReset = trimmed
                } else if isWeeklySection {
                    weeklyReset = trimmed
                }
            }
        }

        guard let session = sessionPercent, let weekly = weeklyPercent else {
            throw NSError(domain: "ClaudeUsageService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not parse usage percentages"])
        }

        return UsageData(
            sessionUtilization: session,
            sessionResetsAt: parseResetTime(sessionReset),
            weeklyUtilization: weekly,
            weeklyResetsAt: parseResetTime(weeklyReset)
        )
    }

    private static func parseResetTime(_ resetLine: String?) -> Date? {
        guard resetLine != nil else { return nil }

        // Try to extract time information and parse it
        // Format examples: "Resets 4pm (Asia/Jerusalem)" or "Resets Mar 27 at 5pm (Asia/Jerusalem)"
        // For now, we'll just return nil - the UI will show "Resets in X hours"
        return nil
    }
}
