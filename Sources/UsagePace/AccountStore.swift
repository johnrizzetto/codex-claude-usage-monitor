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
    var authenticationRequired = false
    var isClaude: Bool { id == 2 }
    var provider: String { isClaude ? "CLAUDE" : "CODEX" }
    var menuBadge: String { AccountBadge.title(custom: badge, slot: id) }
    func stale(at now: Date) -> Bool { authenticationRequired || updated.map { now.timeIntervalSince($0) > 600 } ?? true }
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
    private let claudeSession = ClaudeSessionManager()
    private var nextAttempts = [Date.distantPast, Date.distantPast, Date.distantPast]
    private var failures = [0, 0, 0]
    private var refreshTasks: [Int: Task<Void, Never>] = [:]
    private var refreshStarted: [Int: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    var claudePersistent: Bool { claudeSession.persistent }
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
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDue() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeRefreshing(afterWake: true) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeRefreshing(afterWake: true) }
        })
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
    func refreshAll(allowPrompt: Bool = false) { for id in accounts.indices where accounts[id].connected { refresh(id, allowPrompt: allowPrompt) } }
    private func refreshDue() {
        guard !paused else { return }
        for id in accounts.indices where accounts[id].connected && Date() >= nextAttempts[id] { refresh(id) }
    }
    func resumeRefreshing(afterWake: Bool = false) {
        // Sleep time is not evidence that an active request is hung; allow its response to settle after wake.
        if afterWake { for id in accounts.indices where accounts[id].busy { refreshStarted[id] = Date() } }
        if !paused { refreshAll() }
    }
    func refresh(_ id: Int, allowPrompt: Bool = false) {
        if accounts[id].busy, let started = refreshStarted[id], Date().timeIntervalSince(started) > 90 {
            cancelRefresh(id)
            accounts[id].error = "Previous refresh timed out. Retrying."
        }
        guard !accounts[id].busy, !accounts[id].signingIn else { return }
        accounts[id].busy = true
        refreshStarted[id] = Date()
        let generation = generations[id]
        refreshTasks[id] = Task {
            do {
                let email: String?
                let windows: [UsageWindow]
                if id == 2 {
                    (email, windows) = try await claudeSession.usage(allowPrompt: allowPrompt)
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
                accounts[id].error = id == 2 ? claudeSession.warning : nil
                accounts[id].authenticationRequired = false
                failures[id] = 0
                nextAttempts[id] = RefreshPolicy.nextAttempt(success: true, failures: 0, at: Date())
            } catch {
                guard generation == generations[id] else { return }
                accounts[id].error = error.localizedDescription
                accounts[id].authenticationRequired = error is ClaudeSessionError && !(error as? ClaudeSessionError == .renewalTemporary)
                failures[id] += 1
                nextAttempts[id] = RefreshPolicy.nextAttempt(success: false, failures: failures[id], at: Date())
                if claudeSession.persistent, let auth = error as? ClaudeSessionError, auth == .loginRequired || auth == .renewalUnavailable || auth == .unauthorized {
                    nextAttempts[id] = .distantFuture
                }
            }
            accounts[id].busy = false
            refreshStarted.removeValue(forKey: id)
            refreshTasks.removeValue(forKey: id)
            save()
        }
    }
    private func cancelRefresh(_ id: Int, clearClaudeSession: Bool = false) {
        generations[id] += 1
        refreshTasks.removeValue(forKey: id)?.cancel()
        refreshStarted.removeValue(forKey: id)
        activeClients.removeValue(forKey: id)?.close()
        accounts[id].busy = false
        if id == 2 { claudeSession.invalidate(clearSession: clearClaudeSession) }
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
            try Locations.prepare(ClaudeSessionManager.profile)
            cancelRefresh(2, clearClaudeSession: true)
            claudeSession.beginLogin()
            let script = Locations.root.appendingPathComponent("claude-login.command")
            let profile = ClaudeSessionManager.profile.path.replacingOccurrences(of: "'", with: "'\\''")
            let text = "#!/bin/zsh\nexport PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin\nunset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN CLAUDE_SECURESTORAGE_CONFIG_DIR\nexport CLAUDE_CONFIG_DIR='\(profile)'\n'\(binary.path.replacingOccurrences(of: "'", with: "'\\''"))' auth login --claudeai\n"
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
            accounts[2].error = "Complete the monitor's Claude browser login in Terminal, then click Connect Claude to enable automatic renewal."
        } catch { accounts[2].error = error.localizedDescription }
    }
    func disconnect(_ id: Int) {
        cancelRefresh(id, clearClaudeSession: true)
        cancelLogin(id)
        accounts[id] = AccountState(id: id, label: accounts[id].label, badge: accounts[id].badge)
        if id == 2 { claudeSession.clearMemory() }
        // Keep provider credentials on disk so disconnect does not revoke or destroy a login.
        save()
    }
    func stop() {
        timer?.invalidate()
        for task in refreshTasks.values { task.cancel() }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for task in loginTimeouts.values { task.cancel() }
        for client in activeClients.values { client.close() }
    }
}
