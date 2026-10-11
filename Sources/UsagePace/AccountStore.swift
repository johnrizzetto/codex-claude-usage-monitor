import AppKit
import Foundation
import PaceCore

struct AccountState: Identifiable, Codable {
    var id: Int
    var label: String
    var badge: String? = nil
    var email: String?
    var windows: [UsageWindow] = []
    var updated: Date?
    var connected = false
    var error: String?
    var busy = false
    var signingIn = false
    var isClaude: Bool { id == 2 }
    var provider: String { isClaude ? "CLAUDE" : "CODEX" }
    var menuBadge: String { AccountBadge.title(custom: badge, slot: id) }
    enum CodingKeys: CodingKey { case id, label, badge, email, windows, updated, connected }
}

@MainActor final class AccountStore: ObservableObject {
    @Published var accounts = [AccountState(id: 0, label: "Codex 1"), AccountState(id: 1, label: "Codex 2"), AccountState(id: 2, label: "Claude")]
    @Published var paused = false
    @Published var menuAccount = 0 {
        didSet { UserDefaults.standard.set(menuAccount, forKey: "menuAccount"); onChange?() }
    }
    @Published var menuWindow = MenuWindow.weekly {
        didSet { UserDefaults.standard.set(menuWindow.rawValue, forKey: "menuWindow"); onChange?() }
    }
    private var timer: Timer?
    private var activeClients: [Int: CodexRPC] = [:]
    private var claudeCredential: ClaudeProvider.Credential?
    private var loginTimeouts: [Int: Task<Void, Never>] = [:]
    private var generations = [0, 0, 0]
    var onChange: (() -> Void)?
    private let cache = Locations.root.appendingPathComponent("accounts.json")

    init() {
        let account = UserDefaults.standard.integer(forKey: "menuAccount")
        menuAccount = (0...2).contains(account) ? account : 0
        menuWindow = UserDefaults.standard.string(forKey: "menuWindow").flatMap(MenuWindow.init(rawValue:)) ?? .weekly
        try? Locations.prepare(Locations.root)
        if let data = try? Data(contentsOf: cache), let saved = try? JSONDecoder().decode([AccountState].self, from: data) {
            for row in saved where accounts.indices.contains(row.id) { accounts[row.id] = row }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.paused == false { self?.refreshAll() } }
        }
        refreshAll()
    }
    func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            try? data.write(to: cache, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
        }
        onChange?()
    }
    func rename(_ id: Int, _ label: String) { accounts[id].label = label; save() }
    func renameBadge(_ id: Int, _ value: String) {
        let badge = AccountBadge.normalize(value)
        accounts[id].badge = badge.isEmpty ? nil : badge
        save()
    }
    func refreshAll() { for id in accounts.indices where accounts[id].connected { refresh(id) } }
    func refresh(_ id: Int, allowPrompt: Bool = false) {
        guard !accounts[id].busy, !accounts[id].signingIn else { return }
        accounts[id].busy = true
        let generation = generations[id]
        Task {
            do {
                let email: String?
                let windows: [UsageWindow]
                if id == 2 {
                    do { claudeCredential = try ClaudeProvider.credential(allowPrompt: allowPrompt) }
                    catch {
                        guard let cached = claudeCredential, let expires = cached.expires, expires > Date(), !allowPrompt else { throw error }
                    }
                    guard let credential = claudeCredential else { throw MonitorError.message("Connect your Claude account first.") }
                    (email, windows) = try await ClaudeProvider.usage(credential)
                } else {
                    let client = CodexRPC()
                    activeClients[id] = client
                    defer { client.close(); if activeClients[id] === client { activeClients.removeValue(forKey: id) } }
                    try await client.start(home: Locations.home(id))
                    let result = try await client.request("account/read", ["refreshToken": true])
                    guard let identity = result["account"] as? [String: Any], identity["type"] as? String == "chatgpt" else {
                        throw MonitorError.message("Sign in with your ChatGPT subscription account.")
                    }
                    email = identity["email"] as? String
                    let usage = try await client.request("account/rateLimits/read")
                    windows = try ProviderParser.codex(JSONSerialization.data(withJSONObject: usage))
                }
                guard generation == generations[id] else { return }
                accounts[id].email = email
                accounts[id].windows = windows
                accounts[id].updated = Date()
                accounts[id].connected = true
                accounts[id].error = nil
            } catch {
                guard generation == generations[id] else { return }
                accounts[id].error = error.localizedDescription
            }
            accounts[id].busy = false
            save()
        }
    }
    func connectCodex(_ id: Int) {
        guard !accounts.contains(where: { $0.signingIn }), !accounts[id].busy else {
            accounts[id].error = "Finish the active login or refresh first."; return
        }
        accounts[id].signingIn = true
        accounts[id].error = nil
        let client = CodexRPC()
        activeClients[id] = client
        client.onLogin = { [weak self] success in
            guard let self else { return }
            self.loginTimeouts.removeValue(forKey: id)?.cancel()
            client.close()
            self.activeClients.removeValue(forKey: id)
            self.accounts[id].signingIn = false
            if success {
                self.accounts[id].windows = []
                self.accounts[id].email = nil
                self.accounts[id].updated = nil
                self.accounts[id].connected = true
                self.refresh(id)
            } else { self.accounts[id].error = "Login was not completed. Try again." }
            self.save()
        }
        loginTimeouts[id] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
            self?.cancelLogin(id)
            self?.accounts[id].error = "Login timed out after three minutes. Try again."
        }
        Task {
            do {
                try await client.start(home: Locations.home(id))
                let result = try await client.request("account/login/start", ["type": "chatgpt"])
                guard let text = result["authUrl"] as? String, let url = URL(string: text), url.scheme == "https", url.host == "auth.openai.com" else {
                    throw MonitorError.message("Codex did not return a valid login link.")
                }
                NSWorkspace.shared.open(url)
            } catch {
                cancelLogin(id)
                accounts[id].error = error.localizedDescription
            }
        }
    }
    func cancelLogin(_ id: Int) {
        loginTimeouts.removeValue(forKey: id)?.cancel()
        activeClients.removeValue(forKey: id)?.close()
        accounts[id].signingIn = false
    }
    func connectClaude() {
        guard !accounts[2].busy else { return }
        accounts[2].windows = []
        accounts[2].updated = nil
        accounts[2].email = nil
        accounts[2].connected = true
        refresh(2, allowPrompt: true)
    }
    func signInClaude() {
        do {
            let binary = try Locations.binary("claude")
            let script = Locations.root.appendingPathComponent("claude-login.command")
            let text = "#!/bin/zsh\nexport PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin\nunset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN\n'\(binary.path.replacingOccurrences(of: "'", with: "'\\''"))' auth login --claudeai\n"
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
            accounts[2].error = "Complete the browser login in Terminal, then click Connect Claude."
        } catch { accounts[2].error = error.localizedDescription }
    }
    func disconnect(_ id: Int) {
        generations[id] += 1
        cancelLogin(id)
        accounts[id] = AccountState(id: id, label: accounts[id].label, badge: accounts[id].badge)
        if id == 2 { claudeCredential = nil }
        // Keep provider credentials on disk so disconnect does not revoke or destroy a login.
        save()
    }
    func stop() {
        timer?.invalidate()
        for task in loginTimeouts.values { task.cancel() }
        for client in activeClients.values { client.close() }
    }
}
