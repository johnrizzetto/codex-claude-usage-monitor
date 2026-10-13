import Foundation
import Security
import LocalAuthentication
import CryptoKit
import PaceCore

enum ClaudeProvider {
    typealias Credential = ClaudeOAuthSession
    static func credential(allowPrompt: Bool, profile: URL? = nil) throws -> Credential {
        let directory = profile ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let file = directory.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: file), let value = decode(data), profile != nil || value.expiresAt.map({ $0 > Date() }) ?? true { return value }
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: profile.map {
                let hash = SHA256.hash(data: Data($0.path.precomposedStringWithCanonicalMapping.utf8)).map { String(format: "%02x", $0) }.joined()
                return "Claude Code-credentials-" + hash.prefix(8)
            } ?? "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let value = decode(data) else {
            throw ClaudeSessionError.accessRequired
        }
        guard profile != nil || value.expiresAt.map({ $0 > Date() }) ?? true else {
            throw ClaudeSessionError.loginRequired
        }
        return value
    }
    private static func decode(_ data: Data) -> Credential? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return Credential(accessToken: token, refreshToken: oauth["refreshToken"] as? String,
                          expiresAt: (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
    }
    static func usage(_ credential: Credential) async throws -> (String?, [UsageWindow]) {
        let data = try await get("https://api.anthropic.com/api/oauth/usage", credential)
        let windows = try ProviderParser.claude(data)
        var email: String?
        if let profileData = try? await get("https://api.anthropic.com/api/oauth/profile", credential),
           let profile = try? JSONSerialization.jsonObject(with: profileData) as? [String: Any] {
            email = (profile["account"] as? [String: Any])?["email"] as? String
        }
        return (email, windows)
    }
    private static func get(_ url: String, _ credential: Credential) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexClaudeUsageMonitor/1.1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MonitorError.message("Claude returned an invalid response.") }
        switch response.statusCode {
        case 200: return data
        case 401: throw ClaudeSessionError.unauthorized
        case 403: throw MonitorError.message("Claude declined usage access. Sign in through Claude Code with profile access.")
        case 429: throw MonitorError.message("Claude rate limited this refresh. Retry in five minutes.")
        default: throw MonitorError.message("Claude usage is unavailable (HTTP \(response.statusCode)).")
        }
    }
}
