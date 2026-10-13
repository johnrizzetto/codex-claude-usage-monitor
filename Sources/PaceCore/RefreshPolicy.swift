import Foundation

public enum RefreshPolicy {
    public static func retryDelay(failures: Int) -> TimeInterval {
        min(300, 30 * pow(2, Double(max(0, min(4, failures - 1)))))
    }
    public static func nextAttempt(success: Bool, failures: Int, at now: Date) -> Date {
        now.addingTimeInterval(success ? 300 : retryDelay(failures: failures))
    }
}

public struct ClaudeOAuthSession: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }
    public func needsRenewal(at now: Date) -> Bool {
        expiresAt.map { $0.timeIntervalSince(now) <= 300 } ?? true
    }
    public func applyingRefresh(_ data: Data, at now: Date) throws -> ClaudeOAuthSession {
        struct Response: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard !response.access_token.isEmpty, response.expires_in.isFinite, response.expires_in > 0,
              response.expires_in <= 31_536_000 else { throw CocoaError(.coderInvalidValue) }
        return ClaudeOAuthSession(accessToken: response.access_token, refreshToken: response.refresh_token ?? refreshToken,
                                  expiresAt: now.addingTimeInterval(response.expires_in))
    }
    public var refreshBody: Data? {
        guard let refreshToken, !refreshToken.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = [("grant_type", "refresh_token"), ("refresh_token", refreshToken),
                     ("client_id", "9d1c250a-e61b-44d9-88ed-5944d1962f5e")]
        return Data(pairs.map { $0.0 + "=" + ($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").utf8)
    }
}
