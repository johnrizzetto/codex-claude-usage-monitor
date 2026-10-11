# Usage Pace

[![Build](https://github.com/johnrizzetto/usage-pace/actions/workflows/ci.yml/badge.svg)](https://github.com/johnrizzetto/usage-pace/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-187653)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-202620)](#requirements)

**See how far ahead or behind you are against your AI usage limits.**

Usage Pace is a small native Mac menu bar app for Codex and Claude subscriptions. Pick an account and a 5-hour or weekly window. The menu bar shows a quota bar and a signed difference from perfect pacing, colored green, yellow or red.

[Website and interactive demo](https://johnrizzetto.github.io/usage-pace/) · [Download](https://github.com/johnrizzetto/usage-pace/releases/latest) · [Report a bug](https://github.com/johnrizzetto/usage-pace/issues/new/choose)

![Usage Pace example with illustrative account data](docs/assets/preview.svg)

## What it does

- Monitors two independent Codex/ChatGPT account profiles and one Claude account.
- Shows provider-reported usage and reset timestamps, with pacing for each available window.
- Lets you choose the account and window shown in the menu bar. The choice survives restarts.
- Shows `+20%` when usage is 20 percentage points ahead of perfect pacing, or `-20%` when it is behind.
- Displays remaining allowance per hour and an estimate of when you would hit the limit at the window's average consumption rate.
- Refreshes every five minutes, with manual refresh, pause and launch-at-login controls.
- Runs without a Dock icon, web server, transcript scanning or third-party libraries.

## Requirements

- macOS 14 or later. This is a Mac app, not a Windows or Linux app.
- The official Codex CLI, or a supported installation of the ChatGPT desktop app that bundles it.
- The official Claude Code CLI for Claude account login and token renewal.
- Subscription accounts that expose usage information. An API key alone does not provide subscription usage limits.
- Xcode Command Line Tools to build from source. Full Xcode is not required.

The app discovers CLIs in standard Homebrew and local install locations. Provider integrations may change. A missing window is shown as unavailable, never guessed or replaced with another account's quota.

## Installation

### Download an app

Choose the build matching your Mac from [Releases](https://github.com/johnrizzetto/usage-pace/releases/latest), unzip it and move **Usage Pace.app** to Applications. Release checksums are included alongside the downloads.

These builds are ad-hoc signed, not Apple Developer ID signed or notarized. macOS may decline to open a downloaded app. Building from source is an alternative. Only run a build whose source and origin you trust.

### Build from source

Install Xcode Command Line Tools if they are not already installed, then run:

```sh
git clone https://github.com/johnrizzetto/usage-pace.git
cd usage-pace
./test.sh
./build.sh
open "dist/Usage Pace.app"
```

To install your build in your user Applications folder:

```sh
mkdir -p "$HOME/Applications"
ditto "dist/Usage Pace.app" "$HOME/Applications/Usage Pace.app"
open "$HOME/Applications/Usage Pace.app"
```

## Connect your accounts

**Codex:** click the menu bar meter, then **Sign in with ChatGPT** on each Codex card. Choose the intended account in your browser and complete one login at a time. Each slot has an independent app-owned Codex profile. It does not switch the account used by your regular Codex app or terminal.

**Claude:** click **Connect Claude** to read your existing Claude Code OAuth login. macOS may ask for access to the `Claude Code-credentials` Keychain item. If you need to sign in, click **Sign in**, finish the official Claude Code flow in Terminal and your browser, then click **Connect Claude** again. Claude Code owns token renewal. Open it to renew an expired login, then refresh the monitor.

Click an account name to rename it. At the top of the popover, use the **Menu bar** selectors to choose the displayed account and **5 hours** or **Weekly**. Hover over the meter for the selected account and precise pacing details.

## How pacing works

Perfect pacing spreads the quota evenly over the provider's current window:

```text
window start = reset time - window duration
expected usage = elapsed time / window duration × 100
menu bar difference = usage percentage - expected usage
```

| Usage | Window elapsed | Menu bar | Meaning |
| --- | --- | --- | --- |
| 20% | 40% | -20% | You have used less than the paced allowance. |
| 40% | 40% | +0% | You are on pace. |
| 60% | 40% | +20% | You have used more than the paced allowance. |

The signed number is a **percentage-point difference**, not a relative speed multiplier. The bar's fill is quota used, and its marker is time elapsed.

| Color | Rule |
| --- | --- |
| Green | On pace, behind pace, or no more than 3 percentage points ahead. |
| Yellow | More than 3 and up to 15 points ahead. |
| Red | More than 15 points ahead, or the limit has been reached. |
| Gray | Pacing is stale, unavailable or outside a valid reset window. |

The thresholds are display tolerances, not provider enforcement rules. Remaining allowance per hour is remaining quota divided by hours until reset. The exhaustion estimate assumes your average consumption across the current window continues. It cannot predict the cost of your next task.

## Privacy and credentials

Usage requests go directly to OpenAI or Anthropic. The app has no analytics, tracking server, model requests or browser scraping. The public website is a separate static demo hosted on GitHub Pages; it does not connect to your accounts.

App data lives in `~/Library/Application Support/UsagePace/`:

| Location | Contents |
| --- | --- |
| `codex-1/` and `codex-2/` | OAuth credentials managed and renewed by the official Codex CLI. These are plaintext files inside directories restricted to your user, not encrypted by this app. |
| `accounts.json` | Account labels, emails, usage snapshots, timestamps and connection state. No tokens. Treat this as personal data. |
| `claude-login.command` | A generated command invoking the official Claude login. No credentials. |
| macOS preferences | Your selected account and window, stored with UserDefaults. |

Claude OAuth credentials stay in Claude Code's native Keychain or credential file. Background Keychain reads do not prompt. The app never writes Claude credentials. Codex token renewal is delegated to the official CLI, scoped to the app's own account homes.

**Disconnect** removes an account from the monitor but retains its provider credentials. To remove app-owned Codex credentials, disconnect first and remove the relevant `codex-1` or `codex-2` folder through **Open app data folder**. This does not revoke tokens upstream. Use the provider's account controls for revocation. Never upload app data, tokens, credential files or unredacted account screenshots to an issue.

## Troubleshooting

- **Only a weekly window appears:** that is what the provider currently reported for the account. The app does not invent a 5-hour limit.
- **Gray `?%`:** reconnect or refresh. Missing resets, expired windows, provider errors and data older than ten minutes suppress pacing.
- **Claude login expired:** open Claude Code to renew it, then refresh. Reconnect if macOS requires a fresh Keychain grant after an app rebuild.
- **CLI not found:** install the official CLI in a supported location, then retry.
- **Launch at login does not work:** install the app in Applications and retry the setting. This uses macOS login-item services.
- **An issue persists:** open a bug report with macOS version, app version, provider, selected window and a sanitized description. Do not attach credentials or `accounts.json`.

## Development

```sh
./test.sh                     # Native pacing and parsing checks
./build.sh                    # Release app bundle and ad-hoc signature
swift build --disable-sandbox  # Development build
```

The dependency-free test harness runs with Command Line Tools, which do not bundle XCTest. CI runs the checks and app build on Apple silicon and Intel macOS runners. GitHub Actions are pinned to commit IDs, permissions are scoped to each workflow, and Dependabot maintains action versions.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and the [architecture](docs/design.md). Public builds have not been independently security-audited. Live provider compatibility and OAuth consent still need manual testing. Tests do not certify the provider endpoints.

## Credits and license

Provider behavior was researched against the MIT-licensed [CodexBar](https://github.com/steipete/CodexBar) documentation and public source. No CodexBar source code is bundled.

Usage Pace is independent of OpenAI and Anthropic. Codex, ChatGPT and Claude belong to their respective owners.

[MIT License](LICENSE), copyright John Rizzetto.
