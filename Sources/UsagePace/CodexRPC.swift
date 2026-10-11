import AppKit
import Foundation

enum MonitorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum Locations {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsagePace")
    static func home(_ slot: Int) -> URL { root.appendingPathComponent("codex-\(slot + 1)") }
    static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func binary(_ name: String) throws -> URL {
        let candidates = name == "codex" ? [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ] : ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw MonitorError.message("Install the official \(name) CLI, then retry.")
        }
        return URL(fileURLWithPath: path)
    }
}

/// Short-lived provider-owned RPC processes. No inference, tools or threads are started.
@MainActor final class CodexRPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    var onLogin: ((Bool) -> Void)?
    private var closed = false

    func start(home: URL) async throws {
        try Locations.prepare(home)
        process.executableURL = try Locations.binary("codex")
        process.arguments = ["app-server", "-c", "cli_auth_credentials_store=\"file\""]
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = home.path
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env.removeValue(forKey: "OPENAI_API_KEY")
        env.removeValue(forKey: "CODEX_API_KEY")
        env.removeValue(forKey: "CODEX_ACCESS_TOKEN")
        process.environment = env
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self else { return }
                if data.isEmpty { self.close(); return }
                self.receive(data)
            }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.close() } }
        try process.run()
        _ = try await request("initialize", ["clientInfo": ["name": "usage_pace", "title": "Usage Pace", "version": "1.0.0"]])
        try send(["method": "initialized"])
    }
    private func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard !closed else { throw MonitorError.message("Codex connection closed. Retry refresh.") }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, let waiter = self.pending.removeValue(forKey: id) else { return }
                waiter.resume(throwing: MonitorError.message("Codex did not respond within 30 seconds."))
                self.close()
            }
        }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 2_000_000 else { close(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                if json["error"] != nil {
                    // Never echo provider error bodies, which may contain account data.
                    continuation.resume(throwing: MonitorError.message("Codex rejected the request. Reconnect this account if refresh keeps failing."))
                } else { continuation.resume(returning: json["result"] as? [String: Any] ?? [:]) }
            } else if json["method"] as? String == "account/login/completed" {
                onLogin?((json["params"] as? [String: Any])?["success"] as? Bool ?? false)
            }
        }
    }
    func close() {
        guard !closed else { return }
        closed = true
        onLogin = nil
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        let waiters = pending.values
        pending.removeAll()
        for waiter in waiters { waiter.resume(throwing: MonitorError.message("Codex connection closed. Retry refresh.")) }
    }
}
