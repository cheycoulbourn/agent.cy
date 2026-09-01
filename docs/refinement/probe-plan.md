# L5 · Production probe plan (runs only after gate G-prod)

Target: `https://agentcy-production.up.railway.app`. **No request in this plan has been sent.** The L5 pass was static only, per the lane brief.

## Preconditions before a single request goes out

1. Chey confirms she owns the Railway service and the Anthropic workspace behind it, and says go.
2. Chey names the window. Every probe runs inside one contiguous 30-minute window so anything anomalous in Railway metrics is attributable.
3. Chey provides, or approves the creation of, **one disposable invite code** used for nothing else. Probes P4–P9 consume it. It is revoked from `INVITE_CODES` afterwards.
4. `DAILY_COST_LIMIT_MICROS`, `SHORT_WINDOW_LIMIT` and `DAILY_OPERATION_LIMIT` are read out of Railway first, so I know the real ceilings before I approach them.
5. A Railway deploy log tail is open for the whole window.

## Budget

**58 HTTP requests total.** Nothing in this plan reaches Anthropic, so the incremental provider spend is zero — every probe either fails authentication before `reserveOperation`, or is a non-AI route.

| Probe | Route | Requests |
|---|---|---|
| P1 | `GET /healthz` | 2 |
| P2 | `GET /healthz`, `POST /v1/installations/redeem` | 3 |
| P3 | `OPTIONS` + `POST` on two routes | 4 |
| P4 | `POST /v1/installations/redeem` | 13 |
| P5 | `POST /v1/accounts/apple/sign-in` | 13 |
| P6 | `POST /v1/installations/redeem` | 2 |
| P7 | `POST /v1/inspiration/extract` | 8 |
| P8 | `POST /v1/telemetry/events` | 4 |
| P9 | `POST /v1/webhooks/revenuecat` | 3 |
| P10 | `POST /v1/ai/ideas` (oversized body) | 2 |
| P11 | `POST /v1/bridge/notifications` | 2 |
| P12 | `POST /v1/privacy/delete` | 2 |

---

## P1 — Baseline and response headers (2 requests)

```
GET /healthz
GET /healthz    (repeat, to see whether an edge cache is in front)
```

Verifies **L5-18**: which of `strict-transport-security`, `x-frame-options`, `content-security-policy` and `cache-control` Railway's edge adds versus what the app sets, and confirms `x-content-type-options` / `referrer-policy` survive the edge. Also confirms the deployed build responds at all and records its `timestamp` for the log correlation.

Safety: read-only. No state change.

## P2 — Body-limit and error-shape sanity (3 requests)

```
GET  /healthz
POST /v1/installations/redeem      body: {}                       -> expect 400 invalid_input
POST /v1/installations/redeem      body: <not JSON>               -> expect 400
```

Verifies that error responses on the live build carry no stack, no upstream body, and no field beyond `{ code, message, retryable, ... }` — the deployed counterpart to `server/src/errors.ts:52` and `server/src/app.ts:1131`. Confirms the invalid-input path does not consume the disposable invite.

Safety: no valid code is sent, so no invite can be burned.

## P3 — CORS and preflight (4 requests)

```
OPTIONS /v1/installations/redeem   Origin: https://example.invalid
POST    /v1/installations/redeem   Origin: https://example.invalid, body: {}
OPTIONS /v1/telemetry/events       Origin: https://example.invalid
POST    /v1/telemetry/events       Origin: https://example.invalid, body: {}
```

Verifies that no `access-control-allow-origin` is returned by the app or by Railway's edge, i.e. the deliberate no-CORS posture in the clean-checks list actually holds in production.

Safety: read-only in effect; both POSTs fail validation or auth.

## P4 — Invite rate limit and X-Forwarded-For (13 requests)

This is the live confirmation of **L5-05**.

```
1..11:  POST /v1/installations/redeem  body: {"inviteCode":"probe-invalid-<n>"}
        no X-Forwarded-For
        -> expect 429 with retry-after once n exceeds SHORT_WINDOW_LIMIT
12:     POST /v1/installations/redeem  body: {"inviteCode":"probe-invalid-12"}
        X-Forwarded-For: 203.0.113.12
        -> if this returns 401 rather than 429, the limiter is bypassed
13:     POST /v1/installations/redeem  body: {"inviteCode":"probe-invalid-13"}
        X-Forwarded-For: 203.0.113.13
        -> confirms each forged value gets its own fresh bucket
```

Every code is deliberately invalid and cannot match a seeded hash, so nothing is redeemed. Request 12 is the whole point: locally I proved `request.ip` follows the left-most forwarded address (`evidence/security/trustproxy-xff-spoof.txt`); this checks whether Railway's edge overwrites or appends the header in practice.

Safety: 13 failed redemptions. They leave no durable record — `redeemInvite` throws before writing. Expect a burst of 401/429 in the logs; that is the intended signal.

Rollback: none needed. If P4 shows the bypass, do not proceed to P5 until Chey decides whether to keep probing; the finding is already confirmed.

## P5 — Apple sign-in rate limit (13 requests)

Same shape as P4 against `POST /v1/accounts/apple/sign-in` with a syntactically valid but unsigned `identityToken`, so `AppleIdentityVerifier.verify` rejects it before any account is touched.

Verifies the second consumer of the shared limiter, and confirms that a failed Apple verification returns exactly one generic `installation_invalid` with no issuer, audience or JWKS detail leaked.

Safety: no valid Apple token is used, so no account is created or linked. This does cause 13 outbound JWKS lookups from the proxy to Apple; `createRemoteJWKSet` caches, so expect one.

## P6 — One-use invite redemption and idempotency (2 requests)

```
1: POST /v1/installations/redeem  {"inviteCode":"<disposable>","redemptionAttemptId":"<uuid-A>"}
   -> expect 201 with installationId + credential; record both
2: POST /v1/installations/redeem  {"inviteCode":"<disposable>","redemptionAttemptId":"<uuid-B>"}
   -> expect 401: a second attempt id must not re-redeem
```

Verifies the one-use property and that `redemptionAttemptId` replay is scoped to the original attempt (`server/src/store.ts:302-319`). Also captures the `access` value and `promotionalEntitlementEndsAt` in the response, which tells us whether `PILOT_COMPED_ACCESS` is actually set in production (**L5-22**) without reading the Railway dashboard.

Safety: this consumes the disposable invite. That is its purpose. The resulting installation is the credential for P7–P12 and is erased in P12.

Rollback: P12 erases it; afterwards remove the code from `INVITE_CODES`.

## P7 — Extract route has no quota (8 requests)

Confirms **L5-11**.

```
1..6: POST /v1/inspiration/extract
      Authorization: Bearer <probe credential>
      {"canonicalUrl":"https://www.instagram.com/p/PROBE000000/"}
      (a deliberately non-existent shortcode)
7:    same, with a non-Instagram URL   -> expect 400 invalid_input
8:    same, with no Authorization      -> expect 401
```

Six identical calls in quick succession establish whether any short-window limit applies. Using a non-existent shortcode means Instagram returns 404 and the extractor throws `upstream_unavailable` — the proxy still performs the outbound fetch, which is what the finding is about, but no real creator's post is scraped.

Safety: 18 outbound requests from the proxy to Instagram for a shortcode that does not exist. Below any plausible Instagram rate limit. Requests 7 and 8 confirm the validation and auth boundaries still hold.

## P8 — Telemetry ingestion limits (4 requests)

Confirms **L5-09** without abusing it.

```
1: POST /v1/telemetry/events  1 valid appOpened event      -> expect 202 {accepted:1}
2: POST /v1/telemetry/events  100 valid events (max)       -> expect 202 {accepted:100}
3: repeat request 2 immediately                            -> checks for any rate limit
4: POST /v1/telemetry/events  installationId != mine       -> expect 400
```

Requests 2 and 3 write 200 rows and trigger 200 full state-file rewrites. That is enough to measure the latency curve — compare the response time of request 1 against request 3 — without meaningfully growing the volume. Request 4 confirms the cross-installation guard at `server/src/app.ts:410`.

Safety: 201 telemetry rows, all attached to the probe installation, all removed by P12's erase. **Hard stop: do not send more than these four requests.** If request 3's latency is materially worse than request 1's, that is the finding confirmed; escalating the volume is not necessary and risks the shared volume.

Rollback: P12 (`/v1/privacy/delete`) removes every telemetry row for this installation.

## P9 — Webhook authentication (3 requests)

```
1: POST /v1/webhooks/revenuecat  no Authorization                    -> expect 401
2: POST /v1/webhooks/revenuecat  Authorization: Bearer wrong-secret  -> expect 401
3: POST /v1/webhooks/revenuecat  Authorization: Bearer <64 random>   -> expect 401
```

Verifies the webhook fails closed in production and tells us nothing about whether the secret is set (**L5-21**) — which is exactly the point: if an unset secret and a wrong secret are indistinguishable from outside, the only fix is the startup guard.

Safety: no valid signature is ever constructed, and I will not be given the real secret. No entitlement can be mutated.

## P10 — Body limit on an AI route (2 requests)

```
1: POST /v1/ai/ideas  Authorization: Bearer <probe credential>
   body: 200 KB of valid-shaped JSON (over the 128 KB limit)
   -> expect an SSE stream ending in error code payload_too_large
2: POST /v1/ai/ideas  no Authorization, small body
   -> expect an SSE stream ending in error code installation_invalid
```

Verifies that the oversized-body path in `setErrorHandler` (`server/src/app.ts:559-571`) works on the live build, and — importantly — that request 1 is rejected by Fastify's body limit **before** `reserveOperation`, so it consumes no allowance and reaches no provider. Request 2 confirms authentication precedes everything on the AI routes.

Safety: neither request reaches Anthropic. Zero provider spend. Confirm this by checking that the probe installation's allowance is unchanged afterwards.

**Do not send any AI request that would succeed.** No probe in this plan generates content.

## P11 — Bridge notification endpoint (2 requests)

```
1: POST /v1/bridge/notifications  no Authorization              -> expect 401
2: POST /v1/bridge/notifications  Authorization: Bearer <random 64>  -> expect 401
```

Confirms the capability check is the only gate and that an unregistered capability is rejected. **I will not register a push capability or send a real notification**, so **L5-08**'s rate-limit gap stays a static finding. Confirming it live would mean pushing repeated alerts to a real device, which is not worth it — the code path at `server/src/app.ts:239-270` has no limiter to find.

Safety: no APNs traffic is generated.

## P12 — Erase, and confirm what survives (2 requests)

Confirms **L5-06** and cleans up everything P6–P10 created.

```
1: POST /v1/privacy/delete  Authorization: Bearer <probe credential>
   {"requestId":"<uuid>","installationId":"<probe installation id>"}
   -> expect 200; record the `retained` array verbatim
2: POST /v1/inspiration/extract  Authorization: Bearer <probe credential>
   -> expect 401: the credential must be dead immediately
```

Request 1's `retained` array is compared against `PRIVACY.md`'s Erase All Data list. The push-token retention in L5-06 cannot be observed from outside — it needs a Railway shell or a state-file read, which is a separate ask — so record request 1's response and verify the token retention against the state file only if Chey wants that access granted.

Safety: this is the cleanup step and must run even if earlier probes are cut short. Request 2 is the proof the probe credential no longer works.

---

## Global safety rules

- **Serial only.** One request at a time, minimum 500 ms apart except inside P4, P5 and P7 where the burst is the measurement. Never concurrent.
- **One disposable identity.** Every authenticated probe uses the P6 credential and nothing else. No real creator installation is touched.
- **No successful AI generation.** Nothing in this plan reaches Anthropic. If any probe unexpectedly returns an SSE `result` event, stop the whole run immediately and report it.
- **No writes to another installation.** P8 request 4 is the only cross-installation attempt and it is expected to fail with 400; if it succeeds, stop immediately — that is a new blocker.
- **Stop conditions.** Abort the run and report if: `/healthz` fails twice, any 5xx appears outside the expected `upstream_unavailable` shape, response latency exceeds 10 s on a non-AI route, or Railway shows a restart. The `restartPolicyMaxRetries: 10` in `railway.json` means repeated crashes eventually stop the service; do not get anywhere near that.
- **Rollback.** The only durable changes are the P6 invite redemption and the P8 telemetry rows, both undone by P12. If P12 cannot run, the residue is one dead installation record and ~201 content-free telemetry rows that age out within 30 days — record the installation id so it can be erased later.
- **Evidence.** Capture full request and response headers plus bodies for every probe into `docs/refinement/evidence/security/probe-<n>-<route>.txt`. Redact the probe credential and the invite code from every captured file before writing it.
- **What this plan deliberately does not do.** No attempt to brute-force a real invite, no attempt to read another installation's data, no volumetric load, no APNs traffic, no Instagram scraping of a real creator's post, and no probe of the Anthropic key. If any of those become necessary, they are a separate ask with separate approval.
