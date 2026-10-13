import Foundation

@main struct PacingTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        guard condition() else { print("FAIL: \(name)"); exit(1) }
    }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
    static func main() throws {
        expect(AccountBadge.normalize("cp") == "CP", "custom badges normalize to uppercase")
        expect(AccountBadge.normalize(" per! ") == "PER!", "badge formatting preserves visible symbols")
        expect(AccountBadge.normalize("🧠CP") == "🧠CP", "emoji and text can share a badge")
        expect(AccountBadge.normalize("👨‍👩‍👧‍👦ABCX") == "👨‍👩‍👧‍👦ABC", "joined emoji count as one visible character")
        expect(AccountBadge.normalize("🇺🇸👍🏽ABX") == "🇺🇸👍🏽AB", "flags and skin tones remain intact")
        expect(AccountBadge.normalize("A\nB\tC") == "ABC", "control characters cannot enter a badge")
        expect(AccountBadge.normalize("personal") == "PERS", "badge width is capped at four characters")
        expect(AccountBadge.title(custom: nil, slot: 0) == "C1", "older accounts retain their default badge")
        expect(AccountBadge.title(custom: "", slot: 2) == "CL", "clearing restores the Claude default")
        expect(AccountBadge.title(custom: "CP", slot: 0) == "CP", "custom badge replaces default identity marker")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        expect(RefreshPolicy.retryDelay(failures: 1) == 30, "first failed refresh retries after thirty seconds")
        expect(RefreshPolicy.retryDelay(failures: 9) == 300, "refresh retries remain bounded")
        let session = ClaudeOAuthSession(accessToken: "fixture", refreshToken: "a+b&c", expiresAt: now.addingTimeInterval(200))
        expect(session.needsRenewal(at: now), "session renews before token expiry")
        expect(String(data: session.refreshBody!, encoding: .utf8)!.contains("a%2Bb%26c"), "refresh token form encoding preserves reserved characters")
        let renewed = try session.applyingRefresh(Data(#"{"access_token":"new-fixture","expires_in":3600}"#.utf8), at: now)
        expect(renewed.refreshToken == session.refreshToken, "refresh response may retain the existing refresh token")
        expect(!renewed.needsRenewal(at: now), "renewed session has a new expiry")
        let rotated = try session.applyingRefresh(Data(#"{"access_token":"new-fixture","refresh_token":"rotated-fixture","expires_in":3600}"#.utf8), at: now)
        expect(rotated.refreshToken == "rotated-fixture", "rotating refresh tokens are retained")
        do { _ = try session.applyingRefresh(Data(#"{"access_token":"","expires_in":-1}"#.utf8), at: now); expect(false, "invalid renewal is rejected") }
        catch { expect(true, "invalid renewal is rejected") }
        let window = UsageWindow(name: "5 hours", used: 60, duration: 18_000, reset: now.addingTimeInterval(10_800))
        let pace = window.pacing(at: now)!
        expect(close(pace.expected, 40), "expected quota is proportional to elapsed time")
        expect(close(pace.delta, 20), "60% usage at 40% elapsed is 20 points ahead")
        expect(close(pace.multiplier, 1.5), "average pacing multiplier")
        expect(close(pace.allowedPerHour, 13.3333), "remaining sustainable allowance")
        expect(close(pace.exhaustsIn!, 4_800), "estimated exhaustion at average burn")
        let weekly = UsageWindow(name: "Weekly", used: 20, duration: 604_800, reset: now.addingTimeInterval(302_400)).pacing(at: now)!
        expect(close(weekly.delta, -30), "weekly under pace")
        expect(close(weekly.multiplier, 0.4), "weekly pacing multiplier")
        expect(weekly.exhaustsIn! > weekly.remaining, "under pace lasts past reset")
        expect(UsageWindow(name: "Weekly", used: 80, duration: 604_800, reset: now).pacing(at: now) == nil, "expired window never fabricates fresh quota")
        expect(UsageWindow(name: "5 hours", used: 20, duration: 18_000, reset: nil).pacing(at: now) == nil, "missing reset suppresses pace")
        expect(UsageWindow(name: "5 hours", used: 20, duration: 18_000, reset: now.addingTimeInterval(20_000)).pacing(at: now) == nil, "impossible reset suppresses pace")
        expect(UsageWindow(name: "5 hours", used: -5, duration: 18_000, reset: now.addingTimeInterval(9_000)).pacing(at: now) == nil, "negative utilization is invalid")
        expect(UsageWindow(name: "5 hours", used: .nan, duration: 18_000, reset: now.addingTimeInterval(9_000)).pacing(at: now) == nil, "NaN cannot produce pace")
        let empty = UsageWindow(name: "5 hours", used: 0, duration: 18_000, reset: now.addingTimeInterval(18_000)).pacing(at: now)!
        expect(empty.exhaustsIn == nil, "zero usage has no exhaustion forecast")
        let full = UsageWindow(name: "5 hours", used: 100, duration: 18_000, reset: now.addingTimeInterval(9_000)).pacing(at: now)!
        expect(full.exhaustsIn == 0 && full.allowedPerHour == 0, "exhausted quota has no allowance")
        expect(PaceSignal.evaluate(window, at: now, stale: false) == .red, "20 points ahead is red")
        let onPace = UsageWindow(name: "5 hours", used: 42, duration: 18_000, reset: now.addingTimeInterval(10_800))
        let warning = UsageWindow(name: "5 hours", used: 50, duration: 18_000, reset: now.addingTimeInterval(10_800))
        expect(PaceSignal.evaluate(onPace, at: now, stale: false) == .green, "small pacing tolerance remains green")
        expect(PaceSignal.evaluate(warning, at: now, stale: false) == .yellow, "10 points ahead is yellow")
        expect(PaceSignal.evaluate(window, at: now, stale: true) == .unavailable, "stale data never claims a live pacing color")
        expect(PaceSignal.evaluate(nil, at: now, stale: false) == .unavailable, "missing selected window is neutral")
        expect(MenuWindow.weekly.select(from: [window]) == nil, "weekly selection never falls back to five hours")
        expect(MenuWindow.fiveHour.select(from: [window]) == window, "selected window matches provider duration")
        let nearlyResetFull = UsageWindow(name: "Weekly", used: 100, duration: 604_800, reset: now.addingTimeInterval(60))
        expect(PaceSignal.evaluate(nearlyResetFull, at: now, stale: false) == .red, "exhausted limits stay red even near reset")
        let codex = Data(#"{"rateLimits":{"primary":{"usedPercent":45,"windowDurationMins":300,"resetsAt":1800010800},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1800302400}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":60,"windowDurationMins":300,"resetsAt":1800010800}}}}"#.utf8)
        let parsed = try ProviderParser.codex(codex)
        expect(parsed.count == 1 && parsed[0].used == 60, "main Codex bucket wins over legacy bucket")
        expect(parsed[0].duration == 18_000, "Codex provider duration is used")
        let legacy = try ProviderParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":45,"windowDurationMins":300,"resetsAt":1800010800},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1800302400}}}"#.utf8))
        expect(legacy.count == 2 && legacy[1].name == "Weekly", "legacy Codex bucket remains supported")
        let weeklyOnly = try ProviderParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1800302400},"secondary":null}}"#.utf8))
        expect(weeklyOnly.count == 1 && weeklyOnly[0].name == "Weekly", "a provider weekly-only plan does not invent a five-hour limit")
        let claude = try ProviderParser.claude(Data(#"{"five_hour":null,"seven_day":{"utilization":37.5,"resets_at":"2027-01-18T12:00:00Z"}}"#.utf8))
        expect(claude.count == 1 && claude[0].used == 37.5, "null Claude windows remain unavailable")
        expect(claude[0].duration == 604_800 && claude[0].reset != nil, "Claude weekly reset is parsed")
        let fractional = try ProviderParser.claude(Data(#"{"five_hour":{"utilization":42,"resets_at":"2027-01-18T12:00:00.123Z"}}"#.utf8))
        expect(fractional[0].reset != nil, "fractional ISO timestamps are supported")
        for text in ["{}", #"{"five_hour":{"utilization":-5}}"#, #"{"five_hour":{"utilization":101}}"#] {
            do { _ = try ProviderParser.claude(Data(text.utf8)); expect(false, "invalid Claude response is rejected") }
            catch { expect(true, "invalid Claude response is rejected") }
        }
        do { _ = try ProviderParser.codex(Data("{}".utf8)); expect(false, "empty Codex response is rejected") }
        catch { expect(true, "empty Codex response is rejected") }
        print("PASS: \(checks) pacing and provider parsing checks")
    }
}
