import Foundation
import Security
import LocalAuthentication
import PaceCore

enum ClaudeSessionError: LocalizedError, Equatable {
    case accessRequired, loginRequired, unauthorized, renewalUnavailable, renewalTemporary
    var errorDescription: String? {
        switch self {
        case .accessRequired: return "Claude credentials need Keychain approval. Click Refresh, or finish signing in and click Connect Claude."
        case .loginRequired: return "Claude needs a new login. Use Keep Claude signed in, then Connect Claude after the browser login."
        case .unauthorized: return "Claude rejected this session. Sign in again to reconnect."
        case .renewalUnavailable: return "This Claude login cannot renew automatically. Use Keep Claude signed in to create a monitor session."
        case .renewalTemporary: return "Claude renewal is temporarily unavailable. Automatic refresh will retry."
        }
    }
}

/// Renews only the monitor's independent session. Shared Claude Code credentials are read-only.
@MainActor final class ClaudeSessionManager {
    static let profile = Locations.root.appendingPathComponent("claude-profile")
    private static let service = "com.johnrizzetto.usagepace.claude.session"
    private var memory: ClaudeOAuthSession?
    private var epoch = 0
    var warning: String?
    var persistent: Bool { UserDefaults.standard.bool(forKey: "managedClaudeSession") }
    func invalidate(clearSession: Bool = true) {
        epoch += 1
        if clearSession { memory = nil; warning = nil }
    }
    func clearMemory() { invalidate() }
    func beginLogin() {
        UserDefaults.standard.set(true, forKey: "importClaudeProfile")
        clearMemory()
    }
    func usage(allowPrompt: Bool) async throws -> (String?, [UsageWindow]) {
        let expectedEpoch = epoch
        var managed = false
        let importing = UserDefaults.standard.bool(forKey: "importClaudeProfile")
        var session: ClaudeOAuthSession
        if importing {
            guard allowPrompt else { throw ClaudeSessionError.accessRequired }
            session = try ClaudeProvider.credential(allowPrompt: true, profile: Self.profile)
            managed = true
            memory = session
        } else if persistent {
            session = try memory ?? readCache(allowPrompt: allowPrompt)
            managed = true
            memory = session
        } else {
            managed = false
            do { session = try ClaudeProvider.credential(allowPrompt: allowPrompt) }
            catch {
                guard !allowPrompt, let cached = memory, cached.expiresAt.map({ $0 > Date() }) == true else { throw error }
                session = cached
            }
            memory = session
        }
        if managed && session.refreshBody == nil { throw ClaudeSessionError.renewalUnavailable }
        if importing {
            // Adopt the bootstrap once, before any rotation or usage request. A failed usage
            // request must not cause the next attempt to re-import an obsolete refresh token.
            guard persist(session, allowPrompt: allowPrompt) else { throw ClaudeSessionError.accessRequired }
            UserDefaults.standard.set(true, forKey: "managedClaudeSession")
            UserDefaults.standard.set(false, forKey: "importClaudeProfile")
        }
        if managed && session.needsRenewal(at: Date()) { session = try await renew(session, allowPrompt: allowPrompt, epoch: expectedEpoch) }
        let result: (String?, [UsageWindow])
        do { result = try await ClaudeProvider.usage(session) }
        catch ClaudeSessionError.unauthorized where managed {
            // Revocation/rotation recovery is bounded to one renewal and one usage retry.
            session = try await renew(session, allowPrompt: allowPrompt, epoch: expectedEpoch)
            result = try await ClaudeProvider.usage(session)
        }
        guard epoch == expectedEpoch else { throw CancellationError() }
        if managed {
            memory = session
            persist(session, allowPrompt: allowPrompt)
            UserDefaults.standard.set(true, forKey: "managedClaudeSession")
            UserDefaults.standard.set(false, forKey: "importClaudeProfile")
        }
        return result
    }
    private func renew(_ session: ClaudeOAuthSession, allowPrompt: Bool, epoch expectedEpoch: Int) async throws -> ClaudeOAuthSession {
        guard let body = session.refreshBody else { throw ClaudeSessionError.renewalUnavailable }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeSessionError.renewalTemporary }
        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401 { throw ClaudeSessionError.loginRequired }
            throw ClaudeSessionError.renewalTemporary
        }
        let renewed = try session.applyingRefresh(data, at: Date())
        guard epoch == expectedEpoch else { throw CancellationError() }
        memory = renewed
        // Keep a rotated token in memory even if a locked Keychain delays persistence.
        persist(renewed, allowPrompt: allowPrompt)
        return renewed
    }
    private func query(allowPrompt: Bool) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.service, kSecAttrAccount as String: "monitor",
                kSecUseAuthenticationContext as String: context]
    }
    private func readCache(allowPrompt: Bool) throws -> ClaudeOAuthSession {
        var query = query(allowPrompt: allowPrompt)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            throw ClaudeSessionError.accessRequired
        }
        return try JSONDecoder().decode(ClaudeOAuthSession.self, from: data)
    }
    @discardableResult private func persist(_ session: ClaudeOAuthSession, allowPrompt: Bool) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        let query = query(allowPrompt: allowPrompt)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        warning = status == errSecSuccess ? nil : "Claude is connected, but Keychain could not save renewal. Unlock your Mac and click Refresh before quitting the app."
        return status == errSecSuccess
    }
}
