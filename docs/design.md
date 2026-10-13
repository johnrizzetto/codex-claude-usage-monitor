# Codex Claude Usage Monitor

Native macOS 14+ menu bar app, two independent Codex OAuth profiles and one Claude subscription account. Swift, AppKit, SwiftUI and Foundation only. No web server or third-party runtime.

Each account shows reported 5-hour and weekly utilization, reset countdown, expected usage based on elapsed time, percentage points ahead or behind pace, average burn multiple, and the remaining sustainable allowance per hour. Exhaustion projections use the window average and are labeled estimates. Invalid, absent or expired reset timestamps suppress pacing. Failed refreshes retain the last snapshot with its timestamp and a stale badge.

Codex login and renewal use the installed official Codex app-server, scoped to independent app-owned homes. Claude can bootstrap a dedicated monitor login through the official CLI in an isolated configuration directory. The monitor session is cached in its own Keychain item and renewed directly through OAuth. Shared Claude Code logins remain read-only. Background reads and writes never prompt. All requests go directly to provider endpoints.

Refresh every five minutes while healthy, with bounded retries, wake/unlock recovery, manual Keychain approval, common-mode run-loop scheduling and a stuck-task watchdog. Recent cached readings are labeled and old readings still suppress pacing. No local transcript scanning, cost estimates, database, account switching or inference requests. Preferences and nonsecret snapshots live in Application Support.
