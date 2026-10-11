# Usage Pace Implementation Plan

Goal: show three subscription accounts and pacing in one native Mac popover.

1. Test pacing arithmetic, expired and missing resets, and provider payload parsing. Implement PaceCore models and parsers, then run the complete Swift test suite.
2. Implement bounded Codex app-server transport and isolated OAuth account homes. Implement Claude credential reads with explicit Keychain consent and direct read-only quota fetches. Keep all raw credentials out of diagnostics and snapshot storage.
3. Implement account store, per-account errors, five-minute refresh and cancellation. Build SwiftUI cards, elapsed-time markers, pacing differences, budget per hour and reset countdowns.
4. Package and ad-hoc sign a menu-bar-only app. Smoke-test launch and account reads, measure resource use, and provide the app and source paths.

Review focus: zero usage, expired resets, missing limits, different account identities, failed or revoked credentials, login timeout, quitting with child processes, and stale projections.
