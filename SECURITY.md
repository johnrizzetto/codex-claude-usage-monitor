# Security

## Supported releases

Security fixes target the latest release. Update before reporting a problem.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/johnrizzetto/usage-pace/security/advisories/new). Describe the affected version, reproduction steps, impact and a suggested fix if you have one. Never include live tokens, full credentials or someone else's account data.

If private reporting is unavailable, open a public issue asking for a private contact method without including the vulnerability details or any sensitive data. No response-time SLA is promised for this volunteer project.

## Credential boundaries

Codex OAuth files are managed by the official CLI inside separate app-owned homes with user-only directory permissions. They are not encrypted by Usage Pace. Claude credentials are read from the native Claude Code store. The app requests Keychain interaction only for explicit user actions and does not refresh or overwrite Claude's tokens.

The app sends bearer tokens to provider endpoints for read-only quota and identity requests. It does not make inference requests, scan transcripts or upload usage to an application server. Local snapshots contain emails and usage history despite containing no tokens.

Release apps are ad-hoc signed and not notarized. Build from source if you prefer to review and compile the code yourself. CI verifies compilation and pacing/parser behavior, not the safety or continued availability of provider OAuth endpoints.
