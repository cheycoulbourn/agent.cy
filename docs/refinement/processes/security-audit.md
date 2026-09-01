# Process: security audit

**Draft.** Written by job M from what lane L5 had to check. Job F finalizes it after the batches ship.

## When it runs

- **Full pass:** before any external cohort grows, and whenever a network boundary changes — a new
  route, outbound fetch, credential, or file the app writes outside its container.
- **Targeted pass:** on any diff touching `server/`, `mcp/`, `contracts/`, `ios/AgentCy/Services/`,
  `ios/AgentCyShared/`, `Dockerfile`, `.dockerignore`, or a `PrivacyInfo.xcprivacy`.
- **Documents:** whenever `PRIVACY.md`, `ARCHITECTURE.md` or `MCP_BRIDGE.md` changes, **or whenever the
  code they describe changes** — the direction that actually failed. Three of this pass's four blockers
  were documents that had drifted behind the code (**L5-02**, **L5-03**, **L5-04**).

## Who runs it

A **fresh-context subagent** with read access to the whole repo. It does **not** touch the deployed
service — live probing is separate, budgeted and owner-authorized (see below).

## Inputs

- `docs/PRIVACY.md`, `docs/ARCHITECTURE.md`, `docs/MCP_BRIDGE.md`, `docs/SETUP.md`.
- `server/src/`, `mcp/src/`, `contracts/src/`, `ios/AgentCy/Services/`, `ios/AgentCyShared/`,
  `Dockerfile`, `.dockerignore`, `server/.env.example`, `ios/project.yml`.
- The previous audit's **"Checks that came back clean"** section, so it is not re-derived.

## Checklist

**A. Documents versus behaviour.** For every claim in the three documents about what does or does not
happen, find the code and cite it.
1. Every "does not X" sentence is grepped. *(L5-02: "Capture makes no network request" — it makes two,
   one a full AI call. L5-03: "The proxy does not fetch links" — three fetches per share. L5-04: "no
   credentials in the snapshot" — a live bearer token, in iCloud Drive, and the document contradicts
   itself two sections later.)*
2. Every "erase removes X" list matches what the erase path clears, on both sides. *(L5-06:
   `eraseInstallation` never clears `pushDeviceToken` or the bridge capability hash. L5-07: the client
   removes `snapshot.json` and leaves ten other paths, including full AI request payloads and the
   Local Cy bearer token.)*
3. Every documented boundary list matches the registered set. *(L5-17: the document lists 15 MCP
   tools; the bridge registers 32. The boundary held — every write queues, nothing deletes or
   publishes — but nobody could review it against the document.)*

**B. Outbound requests and destinations.**
4. Every URL the app or server requests is validated before use — scheme, host, and no embedded
   credentials, query or fragment. *(L5-01: `connectionConfig()` validated a schema version and a
   token length, then POSTed the full creator context and a bearer token to whatever URL sat in a file
   anything on the Mac could write.)*
5. Every outbound server fetch is host-allow-listed and size- and time-bounded. *(The extractor's
   allow-listing is correct; **L5-11** is that the route reaching it had no limiter at all.)*
6. Any cleartext transport binds to a specific private address, rejects non-private remotes, and is
   disclosed to the creator in words. *(L5-12: Local Cy binds `0.0.0.0` and carries prompts and a
   bearer token in clear over the LAN; the code comment knew, the privacy document did not.)*

**C. Server abuse controls.** Per route: authentication, authorization, rate limit, quota, body cap,
and what a failure refunds.
7. Is the rate-limit key attacker-controlled? *(L5-05: `trustProxy: true` trusts the whole chain, so
   `request.ip` is whatever the caller sends.)*
8. Is any route exempt from every control? *(L5-11: `/v1/inspiration/extract` calls `authenticate` and
   nothing else, and `authenticate` never inspects `installation.access`, so an expired installation
   passes.)*
9. Does a failure refund the abuse controls as well as the creator-facing allowance? *(L5-10: a
   request that reached the provider and consumed tokens refunded everything, so spend had no ceiling.)*
10. Does any route write per-item rather than per-batch to a whole-file store? *(L5-09: one
    `structuredClone` and one full file rewrite **per telemetry event**, up to 100 per request, with
    no cap on total rows.)*
11. Is caller-supplied text rendered into anything read as coming from us? *(L5-08: the push alert
    interpolated a 500-character caller-supplied subject verbatim, on an unrate-limited route
    authenticated by a capability that sat in iCloud Drive.)*

**D. Secrets, containers, and configuration.**
12. Fail-closed defaults: does an unset variable grant or revoke? *(L5-22: `PILOT_COMPED_ACCESS`
    defaults to `production`, so removing it **grants** comped access, and boot re-promotes the whole
    cohort with a fresh 28-day window on every restart. L5-21: the RevenueCat webhook secret is not
    required in production, so entitlement projection silently stops with no startup error.)*
13. Ignore-file patterns are nested, not root-anchored, and the container declares a non-root `USER`.
    *(L5-13: `.env` / `.env.*` cover `./.env` only, while `COPY server ./server` would bake in
    `server/.env`, which SETUP.md tells developers to create. L5-14: no `USER` directive at all.)*
14. A repo-wide scan for `sk-ant-*`, `AKIA*` and PEM private-key headers, excluding `node_modules`/`.git`.

**E. Client-side storage and logging.**
15. Anything written outside the app container declares a protection class and is cleaned up, and
    queues have size and count caps. *(L5-19: the export archive — every post, script, note and
    reference file — sits in the temporary directory with no explicit class until an erase. L5-20:
    downloads must stream against a byte counter, not a `Content-Length` the CDN may omit.)*
16. `privacy: .public` appears only on enumerated values, never on an error description. *(L5-24: no
    reachable error type carries creator text today; the exposure is the next one.)*
17. Identifier scoping matches the app's own rule. *(L5-25: a queued bridge request with a nil
    workspace id shows in whatever workspace is active, while `ARCHITECTURE.md` says such records
    "remain visible only in the default workspace".)*

**F. Privacy manifests.** Every required-reason API a target's sources call is declared in that
target's manifest, and `NSPrivacyCollectedDataTypes` exists and matches `PRIVACY.md`. *(L5-15 /
APPLE-05: the share extension declared an empty array while calling `UserDefaults(suiteName:)` twice.
APPLE-04: six undeclared `systemUptime` calls. APPLE-09: no collected-types key in the app at all.)*

**G. Dependencies.** `pnpm audit`, then **reachability** per advisory, then a fix that does not cross a
major without the owner's yes. *(L5-16: both reachable advisories were patch bumps; three others were
unreachable because the bridge runs stdio-only. The original fix said `--latest`, which can cross a
major — a reserved decision.)*

## Evidence required per finding

```
### <one-sentence defect>
- Where: <file:line>, and the route or entry point that reaches it
- Evidence: <verbatim excerpt, or the local probe you ran and its output>
- Reachability: <who can trigger it, from where, with what>
- Severity: blocker | major | minor
- Fix (client | server | bridge | docs): <concrete change>
```

**Reachability is not optional.** An advisory in a tree nothing starts, and a bug behind a gate
nothing opens, are different from a live route — saying which is what let this pass accept three
advisories honestly instead of forcing an SDK bump. Locally-produced probes are the preferred
evidence: the `trustProxy` finding rests on a local Fastify instance and a forged header, not on the
docs.

## The production probe

**Never as part of an audit.** A live probe needs confirmation the owner owns the service, a named
window, a written request budget, a disposable credential, and a rollback for every durable change.
`docs/refinement/probe-plan.md` is the template — 58 requests, twelve phases, per-phase hard stops.
**Record "no request has been sent" until one has**, so a later reader can tell the difference.

## Fix, don't note

**Threshold: a fix under ~30 lines, in code the audit already read, with a test, is made in the audit
and reported as fixed.** Document corrections are always made — a false published privacy statement is
not a finding to schedule, it is a sentence to rewrite today. Escalate instead: anything changing what
the product *does* rather than what it *says* (moving the extension's network calls, say), any risk
acceptance, and any dependency upgrade crossing a major.

## Output format

```
## Security audit — <scope> — <date>
Blockers: N · Major: N · Minor: N · Accepted (with ids): N
Deployed service touched: no | yes (authorization, window, request count)

<findings, blockers first, in the block format above>
## Checks that came back clean   <one line each, with the file:line or command that proves it>
## Not checked                   <one line each, and why>
```

The **"Checks that came back clean"** section is required. This pass's version — Apple identity token
validation, installation credential handling, share-extension transport validation, deep-link
allow-listing, the absence of `NSPredicate(format:)` anywhere, zero third-party SDKs, and the Local Cy
runtime's `allowedTools: []` isolation — is the most reusable thing the lane produced: it is the list
the next auditor would otherwise re-derive from scratch.
