# PAGE-ROOT-02 Audit: Account Access

- Audit date: 2026-08-18
- Status: `Verified`
- Scope owner: [`AccountAccessGate`](../../ios/AgentCy/Views/Account/AppleAccountAccessView.swift), its Apple authorization control, and the state/actions they invoke
- Parent program: [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation)

## Frozen contract

The account-access page must explain why private access is required and offer exactly two starts: continue with Apple or open invitation entry. It must keep the local workspace intact, publish comprehensible progress and failure feedback, prevent duplicate account requests, and leave the page only after credential/account state changes or the user enters the invitation sheet.

`PAGE-ROOT-02` owns presenting and dismissing the invitation sheet. The invitation form, validation, redemption request, and blank/invalid/expired/used/redeemed outcomes belong to `PAGE-ROOT-03`.

| State or event | Expected behavior |
| --- | --- |
| Entry | Root credential resolution is complete and no usable installation credential exists; the page renders without starting account or invitation network work. |
| Idle | Privacy explanation, Sign in with Apple, and invitation-code action are visible and operable. |
| Apple handoff | A fresh cryptographic nonce is attached to the Apple request; credential material remains in memory only. |
| Apple cancellation | Return to idle without showing cancellation as an error. |
| Authorizing | Show immediate progress, disable another Apple attempt, and perform exactly one account request for the completed Apple authorization. |
| Failure | Stay on account access, stop progress, re-enable recovery actions, and present a comprehensible error. |
| Success with no local profile | Persist the returned identity and let root routing exit to `PAGE-ROOT-04` restoration. |
| Success with a local profile | Persist the returned identity and let root routing exit to the app shell. |
| Invitation action | Present `PAGE-ROOT-03` in a navigable sheet; dismissal returns to this page without changing access state. |

## Ownership and exits

| Boundary | Owner |
| --- | --- |
| Page presentation | `RootDestination.accountAccess` and `RootView` |
| Local invitation-sheet state | `AccountAccessGate.showsInvitation` |
| Apple system authorization request and nonce | `AgentAppleAccountButton` and `AppleSignInNonce` |
| Loading, credential/account flags, and notice | `AppModel.authorizeAppleAccount` |
| Account HTTP request and secure identity persistence | `AccountAuthorizationClient` and `InstallationCredentialStoring` |
| Success destination | `PAGE-ROOT-01` root resolver |
| Invitation content and redemption outcome | `PAGE-ROOT-03` |

## Required evidence

- Static: every rendered control, state read, action, error path, service call, persisted field, and exit.
- Focused tests: link versus sign-in selection; idle/loading/success/failure cleanup; cancellation; incomplete Apple response; duplicate attempt prevention; secure persistence; root exit after success.
- Runtime: idle page, invitation sheet round trip, Apple cancellation where the simulator supports it, recoverable authorization error, success routing with and without an existing local profile.
- Accessibility: VoiceOver names/order and dynamic status announcement, Dynamic Type through Accessibility Extra Extra Extra Large, Reduce Motion, 44-point controls, and sheet focus restoration.
- Performance: time from Apple completion to visible loading feedback and request settlement; backend request count per completion; main-thread stalls; body/query/media work; cleanup after failure or page exit.

No approved account-authorization latency threshold is present in the product sources. This audit records measured latency separately from correctness and treats more than one backend request for a single completed Apple authorization as a defect.

## Evidence log

### Static function trace

| Boundary | Evidence | Result |
| --- | --- | --- |
| Root entry and exit | `RootDestination.resolve` enters account access after required credential resolution finds no usable credential (`RootView.swift:20-29`) and renders `AccountAccessGate` (`RootView.swift:223-240`). Account success changes the same root inputs rather than pushing a second route. | Entry and exit ownership match the frozen contract. |
| Idle surface | `AccountAccessGate` is one static `ScrollView` with an editorial explanation, native Apple control, invitation action, and one resolved status region (`AppleAccountAccessView.swift`). | Both starts are explicit; no work begins from `body` or page appearance. Progress and a stale notice cannot compete. |
| Invitation boundary | The local `showsInvitation` Boolean is changed only by the invitation button, and its sheet contains `InstallationInviteGate` in a `NavigationStack` (`AppleAccountAccessView.swift:50-76`). | Presentation belongs here; form validation and redemption belong to `PAGE-ROOT-03`. |
| Apple handoff and cancellation | `AppleAccountAuthorizationPolicy` deterministically validates token, code, and nonce material and classifies only the explicit Apple-cancel error as silent. `AppleSignInNonce` accepts an injected secure-byte boundary for failure and mapping coverage (`AppleAccountAccessView.swift`). | Complete, incomplete, cancellation, non-cancellation, deterministic nonce, digest, and secure-random failure paths are covered without a real Apple account. Signed runtime cancellation remains a release check. |
| Account state machine | `AppModel.authorizeAppleAccount` rejects a duplicate while one request is active, sets and clears `isAuthorizingAccount`, selects link versus sign-in from stored identity presence, publishes credential/account flags, synchronizes subscription access, and maps failure (`AppModel.swift`). | Focused tests prove one request across a suspended interval, route selection, success flags/root exits, and retryable failure cleanup. |
| Transport and persistence | `AccountAuthorizationClient` sends one async JSON POST through the selected endpoint, decodes the identity, and stores it (`APIClient.swift:241-327`). `DeviceOnlyKeychainCredentialStore` uses a device-only Keychain item and mirrors only the bounded shared credential (`APIClient.swift:50-111`). | The client test proves link persistence. Sign-in, failure, and duplicate-call behavior are not covered natively. |
| Error presentation | `AccountAccessStatus.resolve` gives current progress priority over an older notice and renders one identified status element. `AccountAccessStatusView` queues progress/info announcements and gives errors high announcement priority; the error mapper supplies retry-oriented copy. | Visible and assistive recovery feedback share one deterministic semantic state. The announcement policy is unit-tested; a spoken VoiceOver device replay remains a release check. |

### Automated evidence

Commands were run against the current dirty working tree without changing app or test source:

```sh
xcodebuild -project ios/AgentCy.xcodeproj -scheme AgentCy \
  -destination 'platform=iOS Simulator,id=<iPhone-17-Pro-iOS-26.5>' \
  -derivedDataPath <isolated-temp> CODE_SIGNING_ALLOWED=NO test \
  -only-testing:AgentCyTests/LiveContractTests/testAppleAccountLinkPersistsAccountWithoutReplacingTheDeviceCredential -quiet

pnpm --filter @agent-cy/contracts test -- -t 'Apple account authorization contracts'
pnpm --filter @agent-cy/server test -- -t 'Apple account access'
```

Results:

- iOS focused client test: **1 passed, 0 failed, 0 skipped**.
- Contracts package: **39 passed, 0 failed**.
- Server package: **73 passed, 0 failed**.
- The iOS test proves the link request path, bearer preservation, response decoding, and secure-store write. Server tests prove first-device linking, second-device sign-in, unlinked-account rejection, and invalid-Apple-token rejection.
- The original client/contract/server evidence remains green and is supplemented by the focused coverage-repair suite below.

### Coverage repair evidence

The repair added [`PageRoot02Tests`](../../ios/AgentCyTests/PageRoot02Tests.swift) and ran it against an iPhone 17 Pro / iOS 26.5 simulator. Its eight tests cover:

1. one authorization request across a deliberately suspended in-flight interval and duplicate rejection;
2. missing-identity sign-in, linked-identity linking, success publication, both root exits, and retryable failure cleanup;
3. complete versus incomplete Apple credential material and cancellation versus non-cancellation policy;
4. deterministic nonce mapping, SHA-256 output, and secure-random failure preservation; and
5. progress precedence, info/error mapping, and urgent versus queued accessibility announcement policy.

Verification results after the repair:

- PAGE-ROOT-02 focused iOS tests: **8 passed, 0 failed, 0 skipped**.
- Complete iOS suite: **536 passed, 0 failed, 0 skipped**.
- Contracts/MCP/server suites: **136 passed, 0 failed**.
- Workspace typecheck and production TypeScript builds: passed.

### Disposable-simulator replay

A new iPhone 17 Pro / iOS 26.5 simulator was created only for this page, then deleted after replay. The unsigned Debug build used an empty store with the live-access gate enabled.

| Scenario | Observed result |
| --- | --- |
| Idle entry | Account access rendered with the complete explanation and both actions. Root diagnostics presented it at **575.8 ms** from process initialization in this empty-store Debug fixture. |
| Accessibility semantics | The idle replay exposed the native `Continue with Apple` and invitation actions with Button roles and the expected Apple hint. The repaired status is one combined, labeled, identified element before the invitation action; its progress/info/error announcement policy is covered deterministically. Spoken output remains a signed-device release check. |
| Invitation round trip | The invitation sheet opened, exposed its Close action and form, and dismissed back to the unchanged account-access page. Invitation validation was not exercised because it belongs to `PAGE-ROOT-03`. |
| Recoverable Apple failure | The unsigned simulator could not complete the entitlement-backed Apple handoff; the page stayed available and rendered `The connection couldn’t be completed. Your work is saved. Try again.` once, in the dedicated error-colored status region. This verifies visible failure recovery, not production Apple authorization. |
| Appearance | Settled light and dark appearances rendered the page and native Apple control correctly. An immediate screenshot during the appearance transition briefly captured the native Apple label mid-redraw; the settled state was correct. |
| Dynamic Type | Accessibility Extra Extra Extra Large preserved wrapping without horizontal clipping. The screen became intentionally long and remained a scroll surface; controls remained exposed in the accessibility tree. |

Signed Apple cancellation and success were not attempted because the unsigned simulator cannot represent the production entitlement/account environment. Focus restoration and spoken announcement of the inserted notice also remain unverified with VoiceOver enabled.

### Performance and smoothness

Classification: **No page-owned rendering issue observed; authorization smoothness and request-count coverage added**.

- The page body contains static text, one native authorization control, one conditional lightweight status row, and no SwiftData query, media decode, sort/filter/format loop, custom animation, or synchronous file/network call.
- Swift Observation limits redraw dependencies to the account-loading flag and notice read by this surface; the transport is async in `AccountAuthorizationClient`.
- Opening and dismissing the invitation sheet showed no visible hitch in the disposable simulator. Settled appearance changes and Accessibility XXXL layout also showed no page-owned rendering failure.
- The measured **575.8 ms** is process-start-to-page presentation for an empty-store Debug fixture, not account-request latency and not a production budget result.
- The native control disables from `isAuthorizingAccount`, and `authorizeAppleAccount` now has an independent in-flight guard. A suspended authorizer test proves the loading flag stays active and a second attempt does not create a second backend call.
- `AccountAuthorizationDiagnostics` records an Instruments interval from authorization start through settlement, its link/sign-in route, outcome, elapsed milliseconds, and ignored duplicate attempts. This supports device-level latency investigation without adding page work.
- No approved account-authorization latency budget exists, so measured device latency remains observational rather than a pass/fail gate.

### Closed coverage gaps and release boundary

1. `GAP-ROOT-02-01` closed: focused AppModel tests cover sign-in/link selection, in-flight state, success/failure cleanup, and root-exit flags.
2. `GAP-ROOT-02-02` closed: deterministic Apple material, cancellation, nonce, and duplicate-request seams are covered.
3. `A11Y-RISK-ROOT-02-01` closed in code and automated policy coverage: one status element announces queued progress/info and high-priority failures. Spoken-output confirmation stays in the signed-device release checklist.
4. `PERF-RISK-ROOT-02-01` closed: the suspended-client test proves one call and loading continuity; production duration is now instrumented.
5. `RUNTIME-GAP-ROOT-02-01` remains a platform release boundary: replay cancellation and successful Apple account transitions on a signed device. Server contracts and deterministic native seams cover these decisions in CI, so this does not block page coverage closure.

## Classification and closure

PAGE-ROOT-02 is closed as `Verified`. The repair added the missing duplicate-request defect guard, deterministic Apple/AppModel seams, focused state and policy tests, a single announced status region, and duration/request diagnostics. No page-owned heavy rendering path or smoothness regression was found.

`PAGE-ROOT-03` was not opened or audited during this repair.
