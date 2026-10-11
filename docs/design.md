# Usage Pace

Native macOS 14+ menu bar app, two independent Codex OAuth profiles and one Claude subscription account. Swift, AppKit, SwiftUI and Foundation only. No web server or third-party runtime.

Each account shows reported 5-hour and weekly utilization, reset countdown, expected usage based on elapsed time, percentage points ahead or behind pace, average burn multiple, and the remaining sustainable allowance per hour. Exhaustion projections use the window average and are labeled estimates. Invalid, absent or expired reset timestamps suppress pacing. Failed refreshes retain the last snapshot with its timestamp and a stale badge.

Codex login and renewal use the installed official Codex app-server, scoped to independent app-owned homes. Claude uses its official login command and reads its existing OAuth credential through macOS Keychain or its native credential file. Background reads never prompt. Codex renewal is delegated to the official CLI. Claude token renewal stays with Claude Code and is not performed by this app. All requests go directly to provider endpoints.

Refresh every five minutes with manual refresh. No local transcript scanning, cost estimates, database, account switching or inference requests. Preferences and nonsecret snapshots live in Application Support. Build an app bundle, run core tests, verify a live account fetch where available, and launch the app.
