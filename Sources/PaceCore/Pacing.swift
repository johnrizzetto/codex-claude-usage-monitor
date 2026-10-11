import Foundation

public enum MenuWindow: String, CaseIterable {
    case fiveHour, weekly
    public var duration: TimeInterval { self == .fiveHour ? 18_000 : 604_800 }
    public var label: String { self == .fiveHour ? "5 hours" : "Weekly" }
    public func select(from windows: [UsageWindow]) -> UsageWindow? {
        windows.first { $0.duration == duration }
    }
}

public enum PaceSignal: Equatable {
    case unavailable, green, yellow, red
    public static func evaluate(_ window: UsageWindow?, at now: Date, stale: Bool) -> PaceSignal {
        guard !stale, let window, let pace = window.pacing(at: now) else { return .unavailable }
        if window.used >= 100 || pace.delta > 15 { return .red }
        return pace.delta > 3 ? .yellow : .green
    }
}

public struct UsageWindow: Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let used: Double
    public let duration: TimeInterval
    public let reset: Date?
    public init(name: String, used: Double, duration: TimeInterval, reset: Date?) {
        self.name = name; self.used = used; self.duration = duration; self.reset = reset
    }
    public func pacing(at now: Date) -> Pacing? {
        guard used.isFinite, (0...100).contains(used), duration > 0,
              let reset, reset > now else { return nil }
        let remaining = reset.timeIntervalSince(now)
        guard remaining <= duration + 1 else { return nil }
        let elapsed = max(0, duration - remaining)
        let expected = elapsed / duration * 100
        let multiplier = expected > 0 ? used / expected : 0
        let exhausts: Double? = used >= 100 ? 0 : (used > 0 && elapsed > 60 ? (100 - used) / (used / elapsed) : nil)
        return Pacing(expected: expected, delta: used - expected, multiplier: multiplier,
                      allowedPerHour: (100 - used) / (remaining / 3600), remaining: remaining,
                      exhaustsIn: exhausts, elapsed: elapsed)
    }
}

public struct Pacing {
    public let expected: Double
    public let delta: Double
    public let multiplier: Double
    public let allowedPerHour: Double
    public let remaining: TimeInterval
    public let exhaustsIn: TimeInterval?
    public let elapsed: TimeInterval
}

public enum ProviderParser {
    public enum ParseError: LocalizedError {
        case unavailable
        public var errorDescription: String? { "The provider did not return valid usage windows." }
    }
    private struct CodexResponse: Decodable {
        var rateLimits: CodexBucket?
        var rateLimitsByLimitId: [String: CodexBucket]?
    }
    private struct CodexBucket: Decodable { var primary: CodexWindow?; var secondary: CodexWindow? }
    private struct CodexWindow: Decodable {
        var usedPercent: Double
        var windowDurationMins: Double?
        var resetsAt: Double?
    }
    private struct ClaudeResponse: Decodable { var five_hour: ClaudeWindow?; var seven_day: ClaudeWindow? }
    private struct ClaudeWindow: Decodable { var utilization: Double?; var resets_at: String? }

    public static func codex(_ data: Data) throws -> [UsageWindow] {
        let response = try JSONDecoder().decode(CodexResponse.self, from: data)
        let bucket = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let windows = [bucket?.primary, bucket?.secondary].compactMap { $0 }.compactMap { window -> UsageWindow? in
            guard (0...100).contains(window.usedPercent) else { return nil }
            let duration = (window.windowDurationMins ?? 0) * 60
            let name = duration == 18_000 ? "5 hours" : duration == 604_800 ? "Weekly" : duration > 0 ? "\(Int(duration / 3600)) hours" : "Usage"
            return UsageWindow(name: name, used: window.usedPercent, duration: duration,
                               reset: window.resetsAt.map { Date(timeIntervalSince1970: $0) })
        }
        guard !windows.isEmpty else { throw ParseError.unavailable }
        return windows
    }
    public static func claude(_ data: Data) throws -> [UsageWindow] {
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let windows = [("5 hours", 18_000.0, response.five_hour), ("Weekly", 604_800.0, response.seven_day)].compactMap { name, duration, window -> UsageWindow? in
            guard let used = window?.utilization, (0...100).contains(used) else { return nil }
            let reset = window?.resets_at.flatMap { text -> Date? in
                let formatter = ISO8601DateFormatter()
                if let result = formatter.date(from: text) { return result }
                formatter.formatOptions.insert(.withFractionalSeconds)
                return formatter.date(from: text)
            }
            return UsageWindow(name: name, used: used, duration: duration, reset: reset)
        }
        guard !windows.isEmpty else { throw ParseError.unavailable }
        return windows
    }
}
