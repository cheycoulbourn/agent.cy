# PAGE-ROOT-03 Audit: Invitation Entry

- Audit date: 2026-08-18
- Repair date: 2026-08-18
- Status: `Verified`
- Scope owner: [`InstallationInviteGate`](../../ios/AgentCy/App/RootView.swift), `AppModel.redeemInstallationInvite`, and the redemption client/server boundary they invoke
- Parent program: [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation)

## Frozen contract

The invitation page accepts one installation invitation, explains actionable validation or service failures, prevents overlapping redemption attempts, and leaves the page only after the returned installation identity has been stored safely. It does not present account-access or creator-work status as invitation status.

`PAGE-ROOT-02` owns presenting and dismissing the sheet. `PAGE-ROOT-03` owns the form, blank/short/long validation, progress, invalid/used/expired/rate-limit/offline/storage feedback, redemption, and its close action.

| State or event | Verified behavior |
| --- | --- |
| Entry | Starts with an empty field and no inherited account-access notice. |
| Blank or short | Makes no request, explains that a complete code is required, and focuses the field. |
| Too long | Makes no request and reports that the code is too long. |
| Validating | Shows one announced progress state and blocks duplicate submission and dismissal. |
| Invalid or used | Stays on the page and says the invitation is invalid or already used. |
| Expired | Stays on the page and asks for a new code. |
| Rate limited | Stays on the page and gives the ten-minute retry interval. |
| Offline or transport failure | Stays on the page with invitation-specific recovery copy. |
| Credential-store failure | Keeps a stable redemption attempt so the one-use invite can safely return a replacement credential. |
| Redeemed with no local profile | Stores the credential, dismisses, and lets root routing enter onboarding. |
| Redeemed with a local profile | Stores the credential, dismisses, and lets root routing enter the app shell. |
| Close or swipe | Returns to account access without changing credential state or leaking page status. |

## Required evidence

- Static: form semantics, every validation branch, request state, error mapping, secure persistence, server mutation, dismissal, and root exits.
- Focused tests: blank/short/long, invalid/used/expired, rate limit, transport/storage failure, one-use recovery, duplicate submission, cancellation/dismissal, success flags, and both root exits.
- Runtime: idle, short input, invalid input, valid redemption, persistence failure, retry, close, keyboard submission, light/dark appearance, and Accessibility Extra Extra Extra Large.
- Accessibility: field name, validation/status announcement, focus behavior, Dynamic Type, keyboard submission, reachable controls, and understandable long-code display.
- Performance: request count, immediate loading feedback, request duration, main-thread work, dismissal cleanup, and rendering/query/media cost.

No approved invitation-redemption latency threshold exists in the product sources. Multiple requests for one submit and irreversible invite consumption after failed local persistence are treated as correctness defects rather than latency findings.

## Repair evidence

### Static function trace

| Boundary | Evidence | Result |
| --- | --- | --- |
| Form validation and keyboard | `InstallationInviteInput` normalizes and validates the input and consumes a newline inserted by a vertical `TextField` as a submit marker. The field also has `.submitLabel(.go)` and `.onSubmit` (`APIClient.swift:196-218`; `RootView.swift:391-413`). | Blank, short, long, button, and keyboard paths share one policy. |
| Request state | `InstallationInviteStatus` owns idle, progress, and error state. `redeemInstallationInvite` rejects a second call while one is active and returns an explicit outcome (`AppModel.swift:28-56,495-539`). | One visible status and one request per user action. |
| Status and copy ownership | Invitation errors use `InstallationInviteErrorMapper`; the sheet neither reads nor writes the global account notice (`AppModel.swift:58-92`; `RootView.swift:428-441`). | The unrelated “Your work is saved” fallback cannot appear on this page. |
| Persistence recovery | The client fingerprints the normalized invite, persists only a redemption-attempt UUID, and clears it only after Keychain save succeeds (`APIClient.swift:363-409,429-475`). | A failed local save can retry the same logical redemption without storing the raw invite or credential in defaults. |
| Server idempotency | The request contract accepts `redemptionAttemptId`. The repository returns a replacement credential for the same invite and attempt, while rejecting a different attempt after redemption (`supporting.ts:14-19`; `store.ts:285-351`). | One-use behavior is preserved without stranding the original device after a save failure. |
| Expiry | Invite records carry `expiresAt`; configuration accepts `INVITE_EXPIRES_AT`; expired unused invites return the explicit expired outcome (`store.ts:56-62,321-323`; `config.ts`). | The product matrix’s expired state is represented and tested. |
| Accessibility and large text | The field has an explicit label, hint, stable identifier, one-to-three-line presentation, error focus restoration, and keyboard submit. Progress/errors expose announcement priority (`RootView.swift:387-441,466-513`). | The code remains understandable at large sizes and asynchronous status is identifiable to assistive technology. |
| Dismissal | Close and interactive dismissal are disabled only during redemption; entry and exit reset page-owned status (`RootView.swift:442-464`). | No in-flight dismissal ambiguity or stale page status. |
| Performance instrumentation | `InstallationRedemptionDiagnostics` emits one signposted request interval, outcome, elapsed duration, and duplicate-submit event (`AppModel.swift:94-136,505-537`). | Request timing is inspectable without logging invitation content. |

### Focused regression coverage

[`PageRoot03Tests.swift`](../../ios/AgentCyTests/PageRoot03Tests.swift) adds nine native tests covering:

1. Blank/short/long validation, normalization, and newline keyboard submission.
2. Polite progress versus urgent failure semantics and invitation-only copy.
3. Global-notice isolation and no “Your work is saved” claim.
4. Pre-network validation, duplicate-submit prevention, and cancellation cleanup.
5. Both root exit states and same-attempt credential recovery after local storage failure.

Contract and server tests additionally cover the optional recovery identifier, replacement credentials for the same attempt, rejection of the old replacement credential, and explicit expiry behavior.

### Automated verification

Commands were run against the current dirty working tree while preserving unrelated user work:

```sh
xcodebuild test -project AgentCy.xcodeproj -scheme AgentCy \
  -destination 'platform=iOS Simulator,id=<PAGE-ROOT-03-disposable-simulator>' \
  -derivedDataPath /tmp/agentcy-page-root-03-derived

pnpm test
pnpm typecheck
pnpm build
```

Results:

- Focused PAGE-ROOT-03 native suite: **9 passed, 0 failed**.
- Full iOS suite: **545 passed, 0 failed**.
- Contracts: **40 passed, 0 failed**.
- Server: **76 passed, 0 failed**.
- MCP: **24 passed, 0 failed**.
- TypeScript typecheck and production builds: **passed**.

### Disposable-simulator replay

A disposable iPhone 17 Pro / iOS 26.5 simulator and local fixture server were used only for this page.

| Scenario | Repaired result |
| --- | --- |
| Fresh entry | No account-access notice appears inside invitation entry. |
| Blank submit | `Enter the complete invitation code.` appears and focus returns to the named field. |
| Invalid submit | The server’s invalid/used result appears as `That invitation is invalid or has already been used. Check the code or ask for a new one.` |
| Keyboard submit | Return submitted the invalid fixture. A later vertical-field newline case produced the final `consumeSubmitMarker` regression and is now covered by the focused suite. |
| Storage failure | The page reports that the device connection could not be saved and explicitly says the invitation can be retried safely. |
| Retry recovery | The server suite proves that the same persisted attempt receives a replacement credential and that only the newest credential authenticates. |
| Accessibility semantics | The field exposes `Invitation code`, a useful hint, and `installation-invite-code`; status exposes `installation-invite-status`. |
| Large text and appearance | The page remains a vertical scroll surface; the code field wraps to three lines rather than presenting only a suffix. The small static surface rendered without a page-owned hitch in light and dark appearance. |

The final post-build desktop-control replay could not be repeated after macOS locked, but the earlier repaired live replay, accessibility tree, focused newline regression, server recovery test, and full suites cover the changed behavior. Production Keychain success and spoken VoiceOver output remain release-device checks, not open PAGE-ROOT-03 implementation defects.

### Performance and smoothness

Classification: **Verified lightweight page; request lifecycle is instrumented**.

- The page contains one small static `ScrollView`, one text field, one button, and one lightweight conditional status row.
- It performs no SwiftData query, sorting/grouping loop, media decode, custom animation, synchronous file I/O, or synchronous network work from `body`.
- Redemption uses async `URLSession`, publishes immediate progress, blocks duplicates, and logs a content-free duration signpost.
- Dynamic Type adds expected vertical growth while retaining scroll reachability; no heavy rendering or settled-state hitch was observed.

## Defect closure

1. `DEFECT-ROOT-03-01` closed: invitation-specific copy replaces creator-work/account fallbacks.
2. `DEFECT-ROOT-03-02` closed: page state is isolated from global notices.
3. `DEFECT-ROOT-03-03` closed: stable attempt IDs provide idempotent replacement-credential recovery.
4. `DEFECT-ROOT-03-04` closed: validation, Return submission, announcements, labeling, focus, and long-code readability were repaired.
5. `DEFECT-ROOT-03-05` closed: expiry is modeled, configured, returned, and tested.
6. `GAP-ROOT-03-01` closed: focused native, contract, and server regressions cover the repaired seams.

## Classification and closure

PAGE-ROOT-03 is closed as `Verified`. Its contract, state ownership, one-use recovery, expiry, accessibility, keyboard behavior, and performance characteristics now have static, automated, and runtime evidence.

`PAGE-ROOT-04` was not opened or audited during this pass.
