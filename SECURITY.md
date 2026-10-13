# Security

## Supported releases

Security fixes target the latest release. Update before reporting a problem.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/johnrizzetto/codex-claude-usage-monitor/security/advisories/new). Describe the affected version, reproduction steps, impact and a suggested fix if you have one. Never include live tokens, full credentials or someone else's account data.

If private reporting is unavailable, open a public issue asking for a private contact method without including the vulnerability details or any sensitive data. No response-time SLA is promised for this volunteer project.

## Credential boundaries

Codex OAuth files are managed by the official CLI inside separate app-owned homes with user-only directory permissions. They are not encrypted by Codex Claude Usage Monitor. A dedicated Claude monitor session is stored in an app-owned Keychain item and renewed directly through OAuth. Bootstrap login uses the official CLI with a separate configuration directory. Shared Claude Code credentials remain read-only and are never refreshed or overwritten by this app. Keychain interaction is requested only for explicit user actions.

The app sends bearer tokens to provider endpoints for read-only quota and identity requests. It does not make inference requests, scan transcripts or upload usage to an application server. Local snapshots contain emails and usage history despite containing no tokens.

Release apps are ad-hoc signed and not notarized. Build from source if you prefer to review and compile the code yourself. CI verifies compilation and pacing/parser behavior, not the safety or continued availability of provider OAuth endpoints.
