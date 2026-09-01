# L5 · Security findings (batch B5)

Pass date: 2026-09-01. Branch `refinement/pre-beta`. Scope authorised by Chey: static review of the iOS app, the Fastify proxy (`server/`), the MCP bridge (`mcp/`), and registry dependency scanning. No request was sent to the deployed Railway service; those live checks are in `probe-plan.md` and wait for gate G-prod.

Evidence for this pass lives in `docs/refinement/evidence/security/`:

- `code-excerpts.txt` — verbatim excerpts backing each finding.
- `pnpm-audit.json`, `pnpm-audit-summary.txt` — `npx -y pnpm@11.7.0 audit` at the repo root.
- `trustproxy-xff-spoof.txt` — a Fastify probe I ran locally proving `request.ip` is caller-controlled under the server's `trustProxy` setting.
- `swift-dependencies.txt` — the Swift package inventory (empty) and how it was verified.

Fix ownership is marked **client**, **server**, **bridge**, or **docs**.

---

## Blockers

### L5-01 The iOS app sends the creator's full AI payload and bearer token to any URL written into `cy-connection.json`
- Where: `ios/AgentCy/Services/LocalCyService.swift:267` (`connectionConfig()`), used at `ios/AgentCy/Services/LocalCyService.swift:207` and `:245`
- Evidence: `docs/refinement/evidence/security/code-excerpts.txt` §4. `connectionConfig()` decodes `baseURL` from `cy-connection.json` in the creator-selected bridge folder and validates only `schemaVersion == 1` and `token.count >= 32`. `performDirect` then POSTs `encoder.encode(envelope)` — the complete request-scoped creator context — to `connection.baseURL` with `Authorization: Bearer <token>`. There is no scheme, host, loopback, or private-range check. The contract schema (`contracts/src/local-cy.ts:80`) accepts any `http://` or `https://` URL, and the app does not even apply that. The folder is normally `iCloud Drive/agent.cy MCP`, which is writable by anything on the creator's Mac and by any app granted that folder in Files.
- Severity: blocker
- Fix (client): validate `baseURL` in `connectionConfig()` before any request — require `http` only for `127.0.0.1`, `::1`, `localhost`, an RFC1918/`fe80::` literal, or a single-label `*.local` host, and require `https` for anything else; reject a URL with a user, password, query, or fragment. Mirror the check in `contracts/src/local-cy.ts:80` so the runtime and the schema agree. Also refuse a `baseURL` whose host changed since the last successful handshake without an explicit re-confirmation in Settings > AI.
- Batch: B5
- Status: open

### L5-02 `PRIVACY.md` states the Share Extension makes no network request; it makes two, one of which is a full AI request
- Where: `docs/PRIVACY.md:11`, `docs/ARCHITECTURE.md:35` versus `ios/AgentCyInspirationShare/ShareViewController.swift:394` and `:255`
- Evidence: `code-excerpts.txt` §1. `InspirationShareAPIClient.extract` (`ios/AgentCyInspirationShare/InspirationShareAPI.swift:112`) POSTs the canonical URL to `/v1/inspiration/extract`, and `.shape` (`:155`) POSTs the creator context and derived source material to `/v1/ai/inspiration/shape`, both authenticated with the installation credential loaded from the shared keychain group. `InspirationShareMediaDownloader` (`ios/AgentCyInspirationShare/InspirationShareMediaAnalyzer.swift:23`) additionally downloads video and thumbnail bytes from Instagram CDN hosts. `ARCHITECTURE.md:35` separately claims the extension "does not link ... AI ... services".
- Severity: blocker — a published privacy statement that is false about network behaviour
- Fix (docs, then client): rewrite `PRIVACY.md:11` and `ARCHITECTURE.md:35` to describe what the extension actually does — one authenticated extract call, one authenticated AI shaping call, and CDN media fetches limited to `*.cdninstagram.com` / `*.fbcdn.net` — and state that the credential is shared with the extension through keychain access group `2S27MSM8G8.com.agentcy.shared`. Then reconcile the App Store Connect privacy answers with the corrected text. If the intent was genuinely a no-network capture, the alternative fix is to move both calls back into the main app's drain path; that is a product decision for Chey, not a doc edit.
- Batch: B5
- Status: open

### L5-03 `PRIVACY.md` states the proxy does not fetch links; the proxy fetches three Instagram URLs per shared post
- Where: `docs/PRIVACY.md:23` versus `server/src/app.ts:190` and `server/src/inspiration-extractor.ts:46`
- Evidence: `code-excerpts.txt` §2. `/v1/inspiration/extract` calls `PublicPostExtractor.extract`, which issues `Promise.allSettled` over the post page, the `/embed/captioned/` page, and the oEmbed endpoint using a spoofed mobile Safari user agent. The creator's source URL therefore leaves the device, reaches the proxy, and is used to originate outbound requests from the proxy's IP. `PRIVACY.md:23` also says "source URLs are never included in AI requests" — that half is true of `/v1/ai/inspiration/shape`, but the same sentence's "The proxy does not fetch links" is false.
- Severity: blocker — a published privacy statement that is false about server behaviour
- Fix (docs, then server): replace the sentence in `PRIVACY.md:23` with an accurate description: the proxy fetches only `instagram.com`, `www.instagram.com` and `m.instagram.com` public pages for a link the creator explicitly shared, discards page HTML after extraction, and never stores the URL. State that the extraction request is content-scoped and short-lived. Add a retention sentence covering what the extract route does and does not log. The extractor's host allow-listing (`server/src/inspiration-extractor.ts:238`, `:80`, `:127`, `:357`) is sound and should stay as-is.
- Batch: B5
- Status: open

### L5-04 The MCP snapshot carries a live bearer capability token into the creator's iCloud Drive, against a documented "no credentials" promise
- Where: `ios/AgentCy/Services/MCPBridgeService.swift:697`, `contracts/src/mcp.ts:22` and `:232`, versus `docs/ARCHITECTURE.md:33` and `docs/MCP_BRIDGE.md` ("Privacy boundary")
- Evidence: `code-excerpts.txt` §3. `McpBridgeSnapshotSchema.notification` is a `McpBridgePushCapability` with a 32–512 character `token`, and the app writes the whole snapshot to `snapshot.json` in the chosen folder. On macOS that lands unencrypted in `~/Library/Mobile Documents/com~apple~CloudDocs/agent.cy MCP/`, syncs through iCloud, and is readable by every process running as the creator. `MCP_BRIDGE.md` contradicts itself inside one document: the privacy boundary says credentials are not copied into the snapshot, the "Review delivery" section says the capability is written into `snapshot.json`.
- Severity: blocker — a false privacy claim, plus a bearer credential stored in a sync-and-share location
- Fix (client + server + docs): move the capability out of `snapshot.json` into its own `push-capability.json` written with `0600` semantics, and correct `ARCHITECTURE.md:33` and the `MCP_BRIDGE.md` privacy boundary to say the bridge folder holds one revocable, notification-only capability. Add server-side revocation: `/v1/bridge/notifications/register` should invalidate the prior `bridgeNotificationCapabilityHash` and the app should re-register on every erase, sign-out, and bridge disconnect. Pair this with L5-08 so a leaked capability cannot be abused at volume.
- Batch: B5
- Status: open

---

## Major

### L5-05 `trustProxy: true` makes every per-IP rate limit bypassable with one header
- Where: `server/src/app.ts:154`, consumed at `server/src/app.ts:275` and `:365` via `enforceInviteRedemptionRateLimit` (`server/src/app.ts:1178`)
- Evidence: `docs/refinement/evidence/security/trustproxy-xff-spoof.txt`. I started a Fastify 5 instance with the same `trustProxy: true` setting and sent requests with a forged `X-Forwarded-For`; `request.ip` came back as `203.0.113.9` and then `198.51.100.1`, exactly the attacker-supplied values. `trustProxy: true` trusts the entire chain, so the left-most forwarded address wins and the caller controls the rate-limit key. Invitation redemption and Apple sign-in are the only two routes protected by that limiter.
- Severity: major
- Fix (server): change `trustProxy: true` to `trustProxy: 1` in `server/src/app.ts:148-155` so exactly one hop (Railway's edge) is trusted and `request.ip` becomes the right-most untrusted address. Add a regression test asserting that a request with `x-forwarded-for: 1.2.3.4, 5.6.7.8` resolves to `5.6.7.8`, not `1.2.3.4`. Production invite codes are already ≥20 characters across ≥3 classes (`server/src/config.ts:226-243`), so this is a throughput and abuse control, not an immediate credential-guessing exposure.
- Batch: B5
- Status: open

### L5-06 Erase All Data leaves the APNs device token and bridge capability hash on the proxy
- Where: `server/src/store.ts:751` (`eraseInstallation`) versus `docs/PRIVACY.md:57`
- Evidence: `code-excerpts.txt` §6. `eraseInstallation` nulls `tokenHash`, sets `deletedAt`, and clears quota events, cost events, telemetry, reservations and operations. It never clears `pushDeviceToken`, `pushPlatform`, `bridgeNotificationCapabilityHash`, `accountId` or `allowanceCounts` (fields declared at `server/src/store.ts:32-45`). `PRIVACY.md` lists "Installation-linked proxy metadata" among the things Erase All Data removes, and names only the invite tombstone, free-brief consumption and entitlement history as retained. An APNs device token is a durable per-device identifier and is not any of those three.
- Severity: major
- Fix (server): in `eraseInstallation`, set `pushDeviceToken = null`, `pushPlatform = null`, `pushShowTitles = true`, `bridgeNotificationCapabilityHash = null` and `accountId = null`. Keep `allowanceCounts` — it is the content-free free-journey integrity record the comment describes — and add it to the `retained` list returned by `/v1/privacy/delete` (`server/src/app.ts:451`) so the response and `PRIVACY.md` agree. Extend the existing erase test to assert every push field is null afterwards.
- Batch: B5
- Status: open

### L5-07 Erase All Data removes only `snapshot.json` from the bridge folder and leaves creator content plus the Local Cy token behind
- Where: `ios/AgentCy/Services/PrivacyEraseCoordinator.swift:252`
- Evidence: `code-excerpts.txt` §7. The coordinator removes `snapshot.json` and then calls `MCPBridgePreferences.disconnect()`, which only clears the bookmark from `UserDefaults`. `mcp/src/workspace.ts:79-89` and `:92-99` create and populate `requests/`, `responses/`, `episode-revisions/`, `cy-requests/`, `cy-responses/`, `cy-processing/`, `cy-connection.json`, `cy-runtime.json`, `bridge-status.json` and `push-status.json` in the same folder. `cy-requests/*.json` contains complete AI request payloads written by `ios/AgentCy/Services/LocalCyService.swift:280`, and `cy-connection.json` holds the Local Cy bearer token. All of that survives an erase, in iCloud Drive.
- Severity: major
- Fix (client): replace the single-file removal with a best-effort sweep of every path the bridge owns — the six directories, the five status/connection files, and `snapshot.json` — before `MCPBridgePreferences.disconnect()`. Keep it best-effort (the folder may be offline) but report a paused erase if the folder is reachable and removal fails, matching the existing `cleanupFailed` path. Document in `MCP_BRIDGE.md` that Erase All Data clears the bridge folder's agent.cy contents.
- Batch: B5
- Status: open

### L5-08 `/v1/bridge/notifications` has no rate limit and renders caller-supplied text into the push alert
- Where: `server/src/app.ts:239-270`, body built at `server/src/app.ts:1227`
- Evidence: `code-excerpts.txt` §8. The route authenticates on the bridge capability alone, then calls `bridgePushSender.send` with a body containing `request.subject` verbatim (`"${request.subject}" ${change} and needs your review.`) whenever `pushShowTitles` is true. `McpBridgeNotificationRequestSchema` (`contracts/src/mcp.ts:35-42`) allows a 1–500 character `subject` and `pendingCount` up to 10,000. There is no reservation, no quota, no short-window limit and no per-installation cap. Combined with L5-04 (the capability sits in an iCloud-synced file), anyone who reads that file can push unlimited alerts with attacker-chosen text under the agent.cy name.
- Severity: major
- Fix (server): apply a per-installation window limit to this route (reuse the `enforceInviteRedemptionRateLimit` shape, keyed on `installation.id`, e.g. 20 per 10 minutes) and return `429` with `retry-after` beyond it. Cap the rendered subject at ~60 characters, strip control characters and newlines, and never let it be the whole body — prefix it with a fixed agent.cy sentence so a spoofed subject cannot impersonate a system message. Sites touched: `server/src/app.ts:239`, `server/src/app.ts:1227`, `contracts/src/mcp.ts:35`.
- Batch: B5
- Status: open

### L5-09 `/v1/telemetry/events` is unbounded and rewrites the whole state file once per event
- Where: `server/src/app.ts:401-429`, `server/src/store.ts:735` (`appendTelemetry`), `server/src/store.ts:245` (`transact`), `server/src/store.ts:196` (`JsonFileStateBackend.save`)
- Evidence: `code-excerpts.txt` §9. The route authenticates and then loops `for (const event of parsed.data.events) await repository.appendTelemetry(...)`. Each `appendTelemetry` is its own `transact`, and each `transact` does a `structuredClone` of the entire state plus a full `writeFile` + `rename` of `agent-cy-state.json`. The schema permits 100 events per request (`contracts/src/supporting.ts:192`) inside the 128 KB body limit, and there is no rate limit, no per-installation cap, and no cap on `state.telemetry.length` — only a 30-day age purge. `SETUP.md` specifies one replica on one `/data` volume, so this is the whole store.
- Severity: major
- Fix (server): batch the loop into a single `repository.appendTelemetryBatch(events, cutoff)` transaction; add a per-installation window limit on the route; and add a hard cap on `state.telemetry` (drop-oldest above, say, 200,000 rows) alongside the existing age purge. Longer term this is the argument for moving telemetry out of the single JSON document, but the batching plus caps are enough before beta.
- Batch: B5
- Status: open

### L5-10 A failed generation refunds every quota and spend counter, so provider spend has no effective ceiling per installation
- Where: `server/src/app.ts:794-820`, `server/src/store.ts:700-707` (`settleOperation`)
- Evidence: `code-excerpts.txt` §10. On any non-success outcome the handler settles with `failureCostMicros = 0`, and `settleOperation` then splices the matching entry out of `state.quotaEvents`. The result is that a request which reached Anthropic, consumed input and output tokens, and then failed schema validation (`server/src/app.ts:730`), the integrity check (`:737`) or the model-identity check (`:717`) consumes no short-window count, no daily operation count, no free allowance and nothing against `dailyCostLimitMicros`. An authenticated installation can therefore drive unbounded real Anthropic spend serially, limited only by the one-concurrent-operation guard.
- Severity: major
- Fix (server): keep the allowance refund (that promise is correct and creator-facing) but stop refunding the abuse controls. Record the real `providerResult` token cost in `costEvents` whenever the provider actually returned tokens, even on a failed outcome, and leave the `quotaEvent` in place for every outcome except `cancelled` before the provider call started. Add a test asserting that ten consecutive `generation_invalid` outcomes consume ten short-window slots and their true cost.
- Batch: B5
- Status: open

### L5-11 `/v1/inspiration/extract` is exempt from every quota, rate limit and entitlement check
- Where: `server/src/app.ts:190-204`, `authenticate` at `server/src/app.ts:869`
- Evidence: `code-excerpts.txt` §11. The handler calls `authenticate` and nothing else — no `reserveOperation`, no `enforceInviteRedemptionRateLimit`, no access check. `authenticate` itself only matches a token hash and requires `deletedAt === null`; it never inspects `installation.access`, so an `expired` installation passes. Each accepted call makes the proxy issue three outbound Instagram requests, each with a 10 second timeout and up to 2 MB of response body (`server/src/inspiration-extractor.ts:12`, `:14`).
- Severity: major
- Fix (server): put the extract route behind the same per-installation short-window limiter used elsewhere (a small allowance, e.g. 15 per 10 minutes), and reject an installation whose `access` is `expired`. Add a single-flight guard keyed on `installationId + canonicalUrl` so a retry storm from the share sheet cannot multiply outbound fetches. The URL canonicalisation and host allow-listing already in the extractor need no change.
- Batch: B5
- Status: open

### L5-12 Local Cy carries the creator's prompt payload and bearer token over cleartext HTTP bound to every interface
- Where: `mcp/scripts/install-local-cy.mjs:63-70`, `mcp/src/local-cy-http-server.ts:38`, `ios/project.yml` (`NSAppTransportSecurity: NSAllowsLocalNetworking: true`)
- Evidence: `code-excerpts.txt` §5. The installer writes `baseURL: http://<LocalHostName>.local:49321` and a 32-byte token into `cy-connection.json`. `LocalCyHTTPServer.start` binds `0.0.0.0`. The iPhone reaches it through the ATS local-networking exception. Every request body is the complete request-scoped creator context and every request carries `Authorization: Bearer <token>` in clear. On a shared network (a café, a co-working space, a hotel), any device on the same L2 segment can read the content and capture the token, and mDNS name resolution for `<host>.local` is spoofable. The code comment at `mcp/src/local-cy-http-server.ts:34-37` acknowledges this; `PRIVACY.md` does not mention it at all.
- Severity: major
- Fix (bridge + docs, and it interacts with L5-01): bind the HTTP listener to the Mac's current private LAN address rather than `0.0.0.0`, and reject a request whose remote address is not in an RFC1918/link-local range. Add a per-request HMAC over the body using the shared token so a passive listener cannot replay. Longer term, generate a self-signed certificate at install time and pin its SPKI in `cy-connection.json` so the transport can move to `https`. Whatever is shipped, add a plain sentence to `PRIVACY.md` and the Settings > AI screen: Local Cy sends your content over your local network in the clear; use it on networks you trust.
- Batch: B5
- Status: open

### L5-13 `.dockerignore` excludes only a root-level `.env`, so `server/.env` would be baked into a locally built image
- Where: `.dockerignore` lines 4–5, `Dockerfile:18`
- Evidence: `code-excerpts.txt` §12. The ignore file uses root-anchored `.env` and `.env.*`, which under Docker's pattern matching cover `./.env` only. `COPY server ./server` at `Dockerfile:18` therefore copies `server/.env` if one exists. `SETUP.md` instructs developers to create exactly that file ("Copy `server/.env.example` to `server/.env`"), and `.gitignore` confirms it is expected to exist locally. The same file already uses `**/node_modules` and `**/dist`, so the nested form was known and simply not applied to secrets. Railway builds from git, where `.env` is not tracked, so the live image is not currently affected — a local `docker build` is.
- Severity: major
- Fix (server): change the two lines to `**/.env` and `**/.env.*` (keeping `!**/.env.example` if the example is wanted in the image, which it is not — leave it excluded). Add `.claude`, `.agents` and `mcp` to the ignore list too; none of them belong in the server image.
- Batch: B5
- Status: open

### L5-14 The production container runs as root
- Where: `Dockerfile:1-26`
- Evidence: `code-excerpts.txt` §12. There is no `USER` directive anywhere in the file, so `CMD ["node", "server/dist/index.js"]` runs as uid 0. The attached `/data` volume — which holds every installation record, hashed credential, entitlement and telemetry row — is therefore created and written by root, and any code-execution bug in the process runs with full container privileges. `store.ts` writing state at mode `0600` (`server/src/store.ts:201`) is the only file-level control.
- Severity: major
- Fix (server): add `RUN mkdir -p /data && chown -R node:node /data /app` and `USER node` before `CMD` in the `Dockerfile`. Verify on Railway that the mounted volume's ownership survives — if the mount lands root-owned, add a tiny entrypoint that `chown`s once and drops privileges, rather than reverting to root.
- Batch: B5
- Status: open

### L5-15 The Share Extension's privacy manifest declares no accessed-API types while the extension uses `UserDefaults`
- Where: `ios/AgentCyInspirationShare/PrivacyInfo.xcprivacy` versus `ios/AgentCyInspirationShare/ShareViewController.swift:275`, `:338` and `ios/AgentCyShared/InspirationShareTransport.swift:615-627`
- Evidence: `code-excerpts.txt` §13. The extension's manifest has `<key>NSPrivacyAccessedAPITypes</key><array/>`, but `ShareViewController` constructs `UserDefaults(suiteName: InspirationSharedContainer.appGroupIdentifier)` in two places and `InspirationWorkspaceHintStore` reads and writes it. The main app (`ios/AgentCy/Support/PrivacyInfo.xcprivacy`) and the widget extension both correctly declare `NSPrivacyAccessedAPICategoryUserDefaults` with reasons `CA92.1` / `1C8F.1`; the share extension was missed.
- Severity: major — App Store Connect rejects uploads with an incomplete required-reason declaration
- Fix (client): add the `NSPrivacyAccessedAPICategoryUserDefaults` entry with reason `CA92.1` to `ios/AgentCyInspirationShare/PrivacyInfo.xcprivacy`. While there, re-derive all three manifests against the final binaries — this is already listed as an open release gate in `SETUP.md`, and L5-02 changes what the extension actually does, which may change the collected-data answers.
- Batch: B5
- Status: open

### L5-16 Three high-severity advisories sit in the deployed server's dependency tree
- Where: `server/package.json` (`fastify: ^5.6.2`), transitive
- Evidence: `docs/refinement/evidence/security/pnpm-audit-summary.txt` and `pnpm-audit.json`, produced by `npx -y pnpm@11.7.0 audit` at the repo root on 2026-09-01. Seventeen advisories total. In the production server tree: `fast-uri@4.1.0` and `fast-uri@3.1.3` (GHSA-v2hh-gcrm-f6hx and GHSA-7p8r-x3mc-p8w7, host confusion via a backslash authority delimiter, fixed in 4.1.2 / 3.1.5) and `find-my-way@9.6.0` (GHSA-c96f-x56v-gq3h, HTTP/2 DDoS, fixed in 9.6.1), all reached through `fastify`. The remaining production-tree advisories (`hono`, `@hono/node-server`, `ip-address`) come only through `mcp > @modelcontextprotocol/sdk`'s HTTP transport and `express-rate-limit`; the bridge runs stdio only (`mcp/src/index.ts`) and never starts those servers, so they are not reachable at runtime. The dev-only advisories are `nanoid` and `postcss` under the test toolchain.
- Severity: major
- Fix (server): run `pnpm update fastify --latest` in `server/`, re-run `pnpm audit`, and re-run `server`'s vitest suite. Neither reachable advisory is currently exploitable in this deployment — the app validates with Zod rather than JSON Schema `format: uri`, and Fastify is not configured for HTTP/2 (`server/src/app.ts:148`) — but they are high severity in a production tree and the upgrade is a patch bump. For the MCP-side advisories, record them as accepted (see risk acceptances) rather than forcing an SDK bump.
- Batch: B5
- Status: open

### L5-17 The documented MCP tool boundary lists 15 tools; the bridge registers 32
- Where: `docs/MCP_BRIDGE.md` ("MCP tools") versus `mcp/src/server.ts:32-778`
- Evidence: `code-excerpts.txt` §14. The document lists 8 read and 7 write tools. `mcp/src/server.ts` registers 32, including `scheduling_preflight`, `list_social_accounts`, `list_series`, `list_episode_slots`, `list_episode_revisions`, `get_episode_revision`, `list_brand_partners`, `set_post_work_date`, `reschedule_post`, `mark_posted`, `create_series`, `create_series_episode`, `resubmit_series_episode`, `add_post_task`, `create_brand_partner`, `update_brand_partner` and `make_anchor_pillar`. I verified the boundary itself still holds: every write tool routes through `queuedResult` → `workspace.queueRequest` (`mcp/src/server.ts:812`, `mcp/src/workspace.ts:111`), no tool deletes, archives, publishes, erases, reads attachment bytes or touches the database, and every id parameter is `z.string().uuid()` so the `join()` calls in `readReceipt` and `readEpisodeRevision` cannot traverse.
- Severity: major — the security boundary is right but undocumented, so nobody can review it against the document
- Fix (docs): regenerate the tool list in `MCP_BRIDGE.md` from `mcp/src/server.ts` and keep them in sync with a test that asserts the documented set equals the registered set. Explicitly note that `mark_posted` records a status the creator already published elsewhere and does not publish anything, since "publish" is named in the not-exposed list.
- Batch: B5
- Status: open

---

## Minor

### L5-18 Responses carry only two security headers, and credential-bearing responses are not marked no-store
- Where: `server/src/app.ts:167-171`
- Evidence: the `onSend` hook sets `x-content-type-options: nosniff` and `referrer-policy: no-referrer` and nothing else. `/v1/installations/redeem` (`server/src/app.ts:318`) and `/v1/accounts/apple/sign-in` (`:382`) return the raw installation credential in the JSON body with no `cache-control`. SSE responses do set `no-cache, no-store` (`server/src/sse.ts:12`), so the gap is the JSON routes. There is no `strict-transport-security`, `x-frame-options` or `content-security-policy`. No CORS plugin is registered, which is the correct default — a browser cannot read these JSON responses cross-origin.
- Severity: minor
- Fix (server): extend the `onSend` hook with `strict-transport-security: max-age=31536000; includeSubDomains`, `x-frame-options: DENY`, `content-security-policy: default-src 'none'`, and `cache-control: no-store` on every response. Leave CORS unregistered and add a comment saying that is deliberate.
- Batch: B5
- Status: open

### L5-19 The export archive is written to the temporary directory without an explicit protection class and is not deleted after sharing
- Where: `ios/AgentCy/Services/ExportService.swift:410-413`
- Evidence: `try archive.write(to: destination, options: .atomic)` into `FileManager.default.temporaryDirectory`. The archive contains every post, script, note and creator-added reference file. It inherits the container default rather than declaring one, and only `LocalExportArchiveCleaner` (`ios/AgentCy/Services/PrivacyEraseCoordinator.swift:43`) removes it, which runs on erase — so between an export and an erase the full archive sits on disk indefinitely.
- Severity: minor
- Fix (client): write with `[.atomic, .completeFileProtection]`, and remove the archive when the share sheet is dismissed rather than waiting for an erase. Keep the existing sweep as the backstop.
- Batch: B5
- Status: open

### L5-20 Nothing caps the size or count of the App Group import queue
- Where: `ios/AgentCyShared/InspirationShareTransport.swift:313-318`, `:352`, `:500`
- Evidence: `InspirationSharedAssetKind.video.maximumBytes` is 250 MB and `thumbnail` is 10 MB, enforced per file, and `InspirationImportQueueStore.maximumEnvelopeBytes` is 128 KB per envelope. Nothing bounds how many envelopes or staged assets accumulate in `IncomingInspiration/`. `InspirationShareMediaDownloader.downloadVideo` (`ios/AgentCyInspirationShare/InspirationShareMediaAnalyzer.swift:29`) also downloads the whole response to disk before the size check, and `expectedLength` returns `0` when the CDN omits `Content-Length` (`:66-69`), so an oversized body is fully written before `stageFile` rejects it.
- Severity: minor — creator-initiated, but a repeated failing share can fill the device
- Fix (client): cap the queue directory at, say, 40 envelopes and 1 GB of assets, evicting oldest-first on enqueue; and stream the video download with a running byte counter that aborts past `maximumBytes` rather than relying on `expectedContentLength`.
- Batch: B5
- Status: open

### L5-21 `REVENUECAT_WEBHOOK_SECRET` is not required in production
- Where: `server/src/config.ts:290`, consumed at `server/src/app.ts:474-482`
- Evidence: the secret is read as `environment.REVENUECAT_WEBHOOK_SECRET` with no production guard, unlike the four hash secrets, which throw when missing (`server/src/config.ts:109-120`). The webhook fails closed — an unset secret makes every call throw `installation_invalid` — so this is not an auth bypass. The risk is silent: entitlement projection stops working with no startup error, and the comparison itself is correctly timing-safe (`server/src/app.ts:1117`).
- Severity: minor
- Fix (server): throw at startup when `NODE_ENV=production` and `REVENUECAT_WEBHOOK_SECRET` is unset or shorter than 32 characters, and require it to differ from the four hash secrets, matching the existing uniqueness checks at `server/src/config.ts:155-179`.
- Batch: B5
- Status: open

### L5-22 `PILOT_COMPED_ACCESS` defaults to true in production, and boot promotes every existing free journey to comped
- Where: `server/src/config.ts:284-288`, `server/src/app.ts:135-143`
- Evidence: `pilotCompedAccess: boolean(environment.PILOT_COMPED_ACCESS, production, "PILOT_COMPED_ACCESS")` — the fallback is `production`, so an unset variable means comped in production. On every boot `promoteActiveFreeJourneysToComped` then upgrades every non-deleted `freeJourney` installation to `comped` with a fresh 28-day window (`server/src/store.ts:433`). The comment at `server/src/config.ts:282-283` says this is deliberate for the pilot, and `SETUP.md` says to set it explicitly. It is still a fail-open default on an access control, and the promotion re-extends the window on each restart.
- Severity: minor — intentional for the pilot, but it should not be the default
- Fix (server): invert the default to `false` and require `PILOT_COMPED_ACCESS=true` to be set explicitly in production, so removing the variable revokes rather than grants. Make `promoteActiveFreeJourneysToComped` idempotent — skip any installation that already has a `promotionalEntitlementEndsAt` — so a redeploy does not silently extend the cohort.
- Batch: B5
- Status: open

### L5-23 The bridge installer passes a user-supplied path through `cmd.exe` on Windows
- Where: `mcp/src/installer.ts:104-112` and `:161-166`
- Evidence: `registerClient` builds `--env AGENTCY_WORKSPACE_DIR=${workspace}` and `run()` calls `execFileSync(command, commandArgs, { shell: process.platform === "win32" })`. With `shell: true` the arguments are re-parsed by `cmd.exe`, so a `--workspace` value containing `&` or `"` becomes command text. `workspace` comes from the operator's own `--workspace` flag or `AGENTCY_WORKSPACE_DIR`, so this is self-injection, not a remote vector.
- Severity: minor
- Fix (bridge): drop `shell: true` and resolve the client executable explicitly (`claude.cmd` / `codex.cmd` on Windows) so arguments are passed as a real argv. Same change in `commandExists` (`:98`) and `removeClient` (`:118`).
- Batch: B5
- Status: open

### L5-24 Failure diagnostics log full error descriptions at `privacy: .public`
- Where: `ios/AgentCy/ViewModels/AppModel.swift:2366-2368`, `ios/AgentCy/Services/ModelContainerFactory.swift:41`
- Evidence: `Logger(...).error("findIdeaSuggestions failed: \(String(describing: error), privacy: .public)")`. The comment above it says no creator content is logged, and I confirmed the reachable error types are `URLError`, `AgentCyAPIError.server` (server-authored strings) and `CancellationError` — none of which carry creator text today. Every other logging site I checked is content-free and correctly marks only enumerated outcomes public (`ios/AgentCy/ViewModels/AppModel.swift:125`, `:170`, `ios/AgentCy/App/RootView.swift:69`, `ios/AgentCy/Views/Home/HomeDashboardView.swift:1680`). The exposure is that a future error type carrying creator text would leak into the unified log by default.
- Severity: minor
- Fix (client): map the error to a stable, enumerated diagnostic identifier the way `server/src/provider.ts:135` (`safeDiagnosticIdentifier`) does, and log that as public; keep the raw description at `privacy: .private`. Same treatment for `ModelContainerFactory.swift:41`.
- Batch: B5
- Status: open

### L5-25 A queued bridge request with a nil `workspaceId` is shown in whatever workspace happens to be active
- Where: `ios/AgentCy/Services/MCPBridgeService.swift:746-750`
- Evidence: `if let requestWorkspaceID = header.workspaceId, requestWorkspaceID != workspaceID { return nil }` — the filter only applies when the request carries an id. `mcp/src/workspace.ts:151` sets `workspaceId: snapshot?.workspaceId ?? undefined`, so any request queued before a snapshot exists has none. `ARCHITECTURE.md:31` states nil workspace identifiers "remain visible only in the default workspace"; here they are visible in every workspace.
- Severity: minor — the folder is the creator's own, so this is cross-workspace confusion rather than cross-account leakage
- Fix (client): treat a nil `workspaceId` as belonging to the default workspace only, matching the SwiftData `WorkspaceScope.includes` rule the rest of the app uses, and have the bridge refuse to queue a write when no snapshot exists so the id is always present.
- Batch: B5
- Status: open

---

## Checks that came back clean

Recorded so the next pass does not re-derive them.

- **Apple identity token validation** (`server/src/apple-identity.ts:32-57`): `jwtVerify` against Apple's remote JWKS with `issuer` pinned to `https://appleid.apple.com`, `audience` pinned to the configured client ids, `algorithms: ["RS256"]`, and expiry enforced by `jose`. The nonce is compared as `sha256(input.nonce)` against `payload.nonce` with `timingSafeEqual` after a length check. Key rotation is handled by `createRemoteJWKSet`. Any failure collapses to one generic `installation_invalid`.
- **Installation credential handling** (`server/src/identity.ts`, `ios/AgentCy/Services/APIClient.swift:51-112`): 32 random bytes, base64url, stored only as an HMAC-SHA256; rotation across `PREVIOUS_INSTALLATION_HASH_SECRETS` with rehash-on-verify (`server/src/app.ts:893`). On device it is a `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `kSecAttrSynchronizable: false`, and `delete()` removes both the app item and the shared-group copy.
- **Share extension transport validation** (`ios/AgentCyShared/InspirationShareTransport.swift`): HTTPS-only canonicalisation with user/password rejection, `localhost`/`.local`/IPv4-literal rejection, 2,048-character URL cap, tracking-parameter stripping, per-field length caps on enqueue, a 128 KB envelope cap, filename validation that rejects traversal and dotfiles (`:457`), and `completeUntilFirstUserAuthentication` protection on the directory and every file.
- **Deep links, widgets and App Intents**: `AgentCyDeepLink.init(url:)` (`ios/AgentCyShared/AgentCyWidgetSnapshot.swift:412`) is a strict host allow-list returning `nil` for anything unknown, path matching is exact, and `brief` requires a parseable UUID. `RootView.openWidgetDestination` (`ios/AgentCy/App/RootView.swift:259`) only sets navigation state; no route mutates data. No `associated-domains` entitlement, so there are no universal links to validate.
- **SwiftData predicate injection**: there is no `NSPredicate(format:)` anywhere in `ios/`. Every search path filters in memory with `localizedStandardContains` (`TasksView.swift:1280`, `IdeaBankView.swift:154`, `SavedPostsLibraryView.swift:224`, `PlanView.swift:390`), and `#Predicate` uses are typed closures over identifiers.
- **Third-party SDKs**: none. See `evidence/security/swift-dependencies.txt`.
- **Committed secrets**: a repo-wide scan for `sk-ant-*`, `AKIA*` and PEM private-key headers (excluding `node_modules` and `.git`) returned nothing. Only `server/.env.example` exists.
- **Local Cy runtime prompt isolation** (`mcp/src/local-cy-runtime.ts:239-247`): `allowedTools: []`, `settingSources: []`, `strictMcpConfig: true`, `persistSession: false`, and a system prompt that explicitly treats synced creator content as untrusted — with a code comment stating prompt text is not the enforcement mechanism. The proxy's Anthropic path carries the same untrusted-input framing (`server/src/provider.ts:106`).
- **MCP path handling**: every id-addressed read (`readReceipt`, `readEpisodeRevision`) is reached only through a `z.string().uuid()` input schema (`mcp/src/server.ts:347`, `:782`), and `writeJsonAtomically` writes at mode `0600`.
- **Error normalisation**: `asAppError` (`server/src/errors.ts:52`) collapses every unknown error into one generic `upstream_unavailable` message; no stack, prompt, or upstream body reaches the client. `safeFieldIssues` (`server/src/app.ts:1159`) truncates Zod paths to 12 components and messages to 300 characters and caps the list at 20. Provider diagnostics (`server/src/provider.ts:135`) allow-list the characters in any identifier written to stderr. Fastify's own logger is disabled (`server/src/app.ts:149`) and `requestIdHeader: false`.
- **Erase of App Group data** (`ios/AgentCy/Services/PrivacyDeletionService.swift:149-165`): `inspirationQueueStore.removeAll()`, `InspirationShareCreatorSnapshotStore.delete()`, `InspirationWorkspaceHintStore.save(nil, ...)`, `VoiceSparkRecordingStore.clearAll()` and `AgentCyWidgetSnapshotStore.delete()` all run, and the SwiftData sweep is derived from `AgentCySchema.types` so a new model cannot be missed. This part of the `PRIVACY.md` erase list holds; L5-06 and L5-07 are the parts that do not.
- **Security-scoped bookmarks** (`ios/AgentCy/Services/MCPBridgePreferences:86-127`): created and resolved with matching options, staleness re-bookmarked, `startAccessingSecurityScopedResource` always balanced by a `defer`.
- **Release configuration gating**: `APIConfiguration.validatedBaseURL` (`ios/AgentCy/Services/APIClient.swift:166`) requires HTTPS unless the host is loopback *and* the build is DEBUG; every `-agentCyPreview*` fixture path and `PreviewCredentialStore` is behind `#if DEBUG` (`ios/AgentCy/App/AgentCyApp.swift:14-51`, `ios/AgentCy/App/RootView.swift:151`). The only ATS exception in either target is `NSAllowsLocalNetworking`; there is no `NSAllowsArbitraryLoads`.
- **CORS**: no CORS plugin is registered on the proxy, so no cross-origin browser context can read a response. That is the right default and should stay.

---

## Risk acceptances for Chey

Things I recommend accepting rather than fixing before beta, each with the reason. Nothing here is fixed unless you say so.

1. **`hono`, `@hono/node-server` and `ip-address` advisories in the MCP tree.** They arrive through `@modelcontextprotocol/sdk`'s streamable-HTTP transport and `express-rate-limit`. The agent.cy bridge is stdio-only (`mcp/src/index.ts`) and never constructs those servers, so the vulnerable code never runs. Bumping the SDK to reach them risks a breaking change in the tool surface right before beta. Re-check at the next SDK upgrade.

2. **`nanoid` and `postcss` advisories.** Dev-only, inside the test toolchain. No production path.

3. **App Attest is not implemented.** `SETUP.md` already lists it as an open gate: the request contract has an optional field, the app generates no assertion, and the proxy verifies none. That means a leaked installation credential is usable from any client, not just a genuine agent.cy build. For an invite-only beta with a known cohort and a per-installation quota, I would accept this and schedule App Attest before the paid production pilot, exactly as `SETUP.md` says.

4. **The global daily spend ceiling is very low.** `DAILY_COST_LIMIT_MICROS` defaults to 1,000,000 micros — roughly one dollar of Sonnet usage per day across all installations at the estimator in `server/src/app.ts:993`. That is a safety property, not a vulnerability, but it will look like an outage to testers. Decide the real number before beta rather than discovering it. (Fixing L5-10 makes this ceiling actually binding, which is the point.)

5. **The one-concurrent-operation guard and the idempotency cache are in-process.** `activeInstallations` and `idempotencyCache` (`server/src/app.ts:126-127`) live in memory, so they are correct only at one replica. `SETUP.md` already mandates one replica for the JSON repository. Accept for beta; it becomes a real fix when the store moves off a single JSON document.

6. **Local Cy is opt-in and off by default.** If L5-12 is not fixed before beta, I would accept it *only* alongside the L5-01 fix (which is not optional) and a one-line warning on the Settings > AI screen. Without L5-01 it should not ship at all.

7. **Debug builds point at the production proxy.** `ios/project.yml` sets `AGENTCY_API_BASE_URL` to the Railway production URL in both Debug and Release for all three targets. That is convenient and it is what `SETUP.md` describes, but it means a development build writes into production state. Accept if you are deliberately testing against production; otherwise point Debug at a preview environment.
