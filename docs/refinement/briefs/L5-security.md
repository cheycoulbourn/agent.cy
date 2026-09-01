# L5 · Security lane

Read `docs/refinement/briefs/_common.md` first. Outputs: `docs/refinement/findings-security.md`, `docs/refinement/probe-plan.md`.

Scope authorized by Chey: static review of the iOS app, the Fastify server (`server/`), the MCP bridge (`mcp/`), and dependency scanning (network allowed for registry audits). NOT authorized in this pass: any request to the deployed Railway service. Write the probe plan instead; it runs only after gate G-prod.

Read `docs/PRIVACY.md`, `docs/ARCHITECTURE.md`, `docs/SETUP.md`, `docs/MCP_BRIDGE.md`. Privacy claims in those documents are promises to users; every claim you can check against code is a check.

## iOS

Keychain and installation credential handling; App Group container contents and what the share extension writes (bounds, validation, canonicalization of URLs, size caps); deep links, URL schemes, universal links, App Intents and widget URL handling (unknown or malformed routes); ATS and Info.plist exceptions; logging of creator content (os_log, print, telemetry payloads); export and erase completeness against the stored data; CloudKit scope and workspace isolation predicates; MCP bridge folder access (security-scoped bookmarks, path traversal in queued requests, snapshot contents, credential absence); local Cy runtime and the Claude share-sheet handoff; third-party SDKs and what they collect; SwiftData predicate injection from search text.

## Server

Invite redemption (one-use, timing), Apple identity token validation (issuer, audience, nonce, expiry, key rotation), HMAC of the Apple subject (key source, rotation), installation credential issuance and revocation, per-route auth, quotas and rate limits (bypasses, concurrency), Zod validation on every input, SSE lifecycle and error normalization (no stack or prompt leakage), security headers, CORS, request size limits, secret loading (`config.ts`), logging redaction versus `PRIVACY.md`, `Dockerfile` and `railway.json` (user, exposed ports, persisted `/data` permissions), Anthropic key handling and spend controls, telemetry content-freedom.

## MCP bridge

Tool inventory versus the documented boundary (no delete, publish, archive, erase, raw database); request queue validation; path handling; what the snapshot exposes; how the bridge authenticates to the app; push endpoint (`bridge-push.ts`).

## Dependencies

Run `npx -y pnpm@11.7.0 audit` at the repo root and record the output under `docs/refinement/evidence/security/`. List Swift package dependencies from `ios/project.yml` and the resolved versions file, with known-advisory checks by name.

## Deliverables

- `findings-security.md` (batch B5): each finding with severity (blocker = exploitable or a false privacy claim; major = weakness with a plausible path; minor = hardening), evidence, fix, and whether the fix is client, server, or bridge. End with a "risk acceptances for Chey" list: anything you recommend accepting rather than fixing before beta, with the reason.
- `probe-plan.md`: exact requests you would send to the deployed proxy after G-prod, what each verifies, the request budget needed, and the rollback or safety notes. No requests are sent in this pass.
