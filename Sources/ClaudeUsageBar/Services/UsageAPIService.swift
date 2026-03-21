import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .unauthorized: return "Session expired. Please sign in again."
        case .rateLimited: return "Rate limited. Will retry automatically."
        case .httpError(let code): return "Server error (\(code))"
        }
    }
}

enum UsageAPIService {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            let decoder = JSONDecoder()
            // Handle ISO8601 dates with fractional seconds (e.g. "2025-11-04T04:59:59.943648+00:00")
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let str = try container.decode(String.self)
                if let date = fmt.date(from: str) { return date }
                // Fallback without fractional seconds
                let fmt2 = ISO8601DateFormatter()
                fmt2.formatOptions = [.withInternetDateTime]
                if let date = fmt2.date(from: str) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(str)")
            }
            return try decoder.decode(UsageResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.httpError(http.statusCode)
        }
    }
}
