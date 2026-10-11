# Contributing

Small, focused pull requests are welcome. Open an issue before adding a provider, changing authentication or introducing a dependency.

## Local checks

Use macOS 14 or later with Xcode Command Line Tools:

```sh
./test.sh
./build.sh
```

Include meaningful tests when changing pacing, parsing or error handling. Use synthetic fixtures only. Manually check the menu bar in light and dark appearances, the saved account/window selection, missing limits and stale data.

## Project rules

- Keep the app native and small. Avoid adding a server, telemetry or third-party runtime.
- Treat missing usage and reset timestamps as unavailable. Never substitute another account's quota.
- Keep Codex profiles isolated. Delegate token renewal to the official credential owner.
- Never log raw credentials or provider error bodies. Background Keychain reads must remain noninteractive.
- Do not run model requests to test quota access or start a usage window.
- Protect account identity when reconnecting, disconnecting or discarding old asynchronous results.
- Keep UI copy plain. Explain pacing in percentage points and label projections as estimates.
- Keep release claims accurate about supported architectures, signing and notarization.
- Do not commit local account data, emails, screenshots of real accounts, `.env` files, OAuth files or private keys.

## Pull requests

Explain the problem, resulting behavior and verification. Keep unrelated formatting and refactoring out of the change. CI must pass. Maintainers may ask for screenshots with synthetic data for UI changes.

For security concerns, use the private reporting process in [SECURITY.md](SECURITY.md). Do not open a public issue containing a secret.
