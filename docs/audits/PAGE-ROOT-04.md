# PAGE-ROOT-04 Audit: Account Restoration

- Audit date: 2026-08-18
- Repair date: 2026-08-18
- Status: `Verified`
- Scope owner: [`AccountRestoreView`](../../ios/AgentCy/Views/Account/AppleAccountAccessView.swift), its `RootDestination.restoringAccount` entry/exit, and the SwiftData/CloudKit state it waits on
- Parent program: [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation)

## Frozen contract

The account-restoration page must wait for an already linked account's private synced profile without creating a replacement profile. It must distinguish active waiting from unavailable sync, offline delay, and a record that has not arrived; provide a safe recovery path when waiting cannot complete; and leave automatically when the profile becomes available.

`PAGE-ROOT-02` owns Apple authorization. `PAGE-ROOT-01` owns root destination selection. `PAGE-ROOT-04` owns what happens after the linked credential is valid but no local profile exists.

| State or event | Verified behavior |
| --- | --- |
| Entry | Appear only for a valid linked installation with no local profile. |
| Active restore | State what is being restored, expose understandable progress, and avoid creating local replacement data. |
| Offline | Preserve local data and explain that restoration needs a connection. |
| CloudKit unavailable or local-only fallback | Stop claiming that data is arriving and expose an actionable recovery state. |
| Delayed or missing profile | After 15 seconds, stop active progress, explain the delay, and provide retry or account recovery. |
| Profile arrives | Transition once to the app shell without requiring a relaunch or tap. |
| Relaunch while waiting | Return to restoration without creating onboarding data. |
| Relaunch after restoration | Enter the app shell from the persisted profile. |
| Reduce Motion | Keep the status understandable without the continuous rotation. |
| VoiceOver and Dynamic Type | Announce a named restoration status and keep all content reachable at the largest text size. |

The repair defines 15 seconds as PAGE-ROOT-04's explicit active-wait threshold. `Check again` starts one fresh CloudKit check and one fresh bounded wait; it does not poll.

## Required evidence

- Static: root entry predicates, sync/store configuration, waiting state ownership, failure and recovery paths, profile-arrival observation, relaunch, and duplicate-profile prevention.
- Focused tests: waiting, offline, local-only fallback, delayed record, retry, cancellation/account recovery, profile arrival, relaunch, Reduce Motion, and accessibility policy.
- Runtime: standard waiting, delayed waiting, automatic exit, light/dark appearance, Accessibility Extra Extra Extra Large, Reduce Motion, and an unavailable-sync scenario.
- Performance: presentation time, restore-to-shell duration, redraw behavior, polling/query cost, animation cost, memory growth, cancellation, and cleanup.

## Evidence log

### Static function trace

| Boundary | Evidence | Result |
| --- | --- | --- |
| Entry | `RootDestination.resolve` selects restoration only when credential state is resolved, the installation credential is valid, the installation is linked, and no `CreatorProfile` exists (`RootView.swift:13-29`). | Correctly avoids onboarding for the linked/no-profile state. |
| Page state | `AccountRestorePresentation` represents checking, restoring, delayed, offline, and unavailable phases. `AccountRestoreView` owns one attempt counter, one cancelable delay, and page-local recovery state. | Every frozen-contract state has one deterministic presentation. |
| Sync source | Production configuration uses the private CloudKit database. If the CloudKit-backed store fails to open, the app silently reopens the same store local-only and sets `didFallBackToLocalOnlyStore` (`ModelContainerFactory.swift:17-63`). | A real unavailable-sync condition exists. |
| Failure visibility | Root passes `didFallBackToLocalOnlyStore` into the page. The page combines `CKContainer.accountStatus()` with `NWPathMonitor`; live offline state overrides a cached available CloudKit result. | Offline, missing/restricted iCloud, CloudKit errors, and local-only fallback no longer claim restoration is active. |
| Delayed record | A view-scoped task changes checking/restoring to delayed after 15 seconds. `Check again` restarts the task and CloudKit check; `Use a different account` confirms before deleting only the device credential. | Waiting is bounded and both recovery paths are explicit. |
| Automatic exit | Root holds a live `@Query` for `CreatorProfile`; when a profile appears, destination recomputes from `.restoringAccount` to `.app` (`RootView.swift:139-148,223-250`). | The implemented happy-path exit is direct and has no polling loop. |
| Relaunch | File-backed tests prove a persisted profile is present after reopening and routes to the app. | The happy path survives relaunch. |
| Duplicate prevention | The restoration page never invokes onboarding or inserts a profile. | No page-owned duplicate-creation path exists. |
| Motion | The 72-point asterisk rotates only during the active restore phase, stops after 15 seconds or on any degraded state, stops on disappearance, and remains static under Reduce Motion. | Continuous animation is bounded to one active attempt. |
| Accessibility | The decorative indicator is hidden. A stable status element exposes the name `Workspace restoration status`, a phase-specific value, and an identifier; recovery actions use native buttons with hints. Phase changes are announced. | Assistive technology can distinguish active, delayed, offline, and unavailable states and reach recovery. |

### Automated evidence

Focused command:

```sh
xcodebuild test -project AgentCy.xcodeproj -scheme AgentCy \
  -destination 'platform=iOS Simulator,id=<PAGE-ROOT-04-disposable-simulator>' \
  -derivedDataPath /tmp/agentcy-page-root-04-fix-derived \
  -only-testing:AgentCyTests/PageRoot04Tests \
  -only-testing:AgentCyTests/RootRoutingTests
```

Result: **20 passed, 0 failed**: 8 PAGE-ROOT-04 policy/recovery tests plus the existing 12 root-routing tests.

The focused suite proves:

- linked/no-profile routes to restoration rather than onboarding;
- profile arrival changes the pure destination from restoration to the app;
- a persisted profile still routes to the app after reopening the store;
- local-only fallback never claims iCloud restoration is active;
- offline and unavailable states expose retry and account recovery;
- the 15-second threshold ends active progress and continuous motion;
- Reduce Motion keeps the status understandable without rotation;
- live connectivity overrides a cached available CloudKit result;
- recovery deletes the device credential, creates no profile, routes to account access, and publishes only the factual `Signed out of this device` notice;
- debug fixtures cover active, delayed, offline, unavailable, and fallback presentations.

Repository verification: **553 iOS tests passed**, **140 TypeScript tests passed**, TypeScript typecheck and production builds passed, and both iOS and Mac Catalyst builds passed. Existing media/UIWindow deprecation warnings remain outside this page.

The top-level `scripts/verify.sh` wrapper still stops at its pre-existing PAGE-ROOT-03 typography preflight (`.agentBody.monospaced()` in the invitation field). PAGE-ROOT-03 was not reopened or edited here; all compilation, test, and build stages behind that wrapper were run directly and passed.

### Disposable-simulator replay

A disposable iPhone 17 Pro / iOS 26.5 simulator and the page's debug fixtures were used only for PAGE-ROOT-04.

| Scenario | Observed result |
| --- | --- |
| Waiting entry | Active restoration appeared 416 ms after process initialization with one rotating indicator and truthful iCloud copy. |
| Delayed wait | At 15 seconds the rotation stopped, delayed copy replaced active progress, and `Check again` plus `Use a different account` appeared. |
| Retry | `Check again` returned immediately to active restoration and restarted the bounded wait without a relaunch. |
| Profile arrival | The eventual-arrival fixture showed restoration at 391 ms and the app shell at 1,623 ms, a 1,232 ms restore-to-shell transition. No tap or relaunch was required. |
| Unavailable sync | The page stopped claiming data was arriving, named iCloud unavailability, and exposed retry plus account recovery. |
| Account recovery | The confirmation stated that local data stays on-device; confirming returned to account access with the `Signed out` notice. |
| Accessibility tree | The status exposed a stable name and phase-specific value. Delayed/unavailable recovery buttons exposed names and hints. |
| Dark and largest text | Dark contrast remained legible. Content reflowed vertically inside the scroll surface, and both recovery actions remained in the accessibility tree at Accessibility Extra Extra Extra Large. |
| Reduce Motion | Policy and focused tests confirm that active rotation is disabled; spoken VoiceOver and physical-device motion remain release-device checks. |

### Performance and smoothness

Classification: **Verified lightweight page; continuous motion and async work are bounded**.

- The page contains a small scrollable stack, text, native buttons, and one vector indicator. It performs no sorting, media decode, file work, or polling.
- Profile detection belongs to RootView's narrow `@Query<CreatorProfile>`; no repeated fetch loop or timer-driven body invalidation was found.
- Each attempt performs one CloudKit account-status check and one cancelable 15-second sleep. One `NWPathMonitor` runs only while the page is present and is canceled on disappearance.
- The 1.6-second rotation runs only during active restoration and stops at the delayed threshold, on degraded state, on Reduce Motion, or when the page exits.
- Standard, delayed, unavailable, dark, largest-text, retry, recovery, and restore-to-shell replays showed no visible frame hitch or layout instability.
- The measured restore-to-shell path improved from the audit fixture's 1,581 ms to 1,232 ms; this is fixture evidence, not a production latency budget.

## Resolved defects and coverage

1. `DEFECT-ROOT-04-01` resolved: offline, unavailable, delayed, retry, and confirmed account recovery are implemented.
2. `DEFECT-ROOT-04-02` resolved: the existing local-only fallback flag is consumed and never renders active iCloud copy.
3. `DEFECT-ROOT-04-03` resolved: a stable named status exposes phase-specific accessibility values and native recovery controls.
4. `RISK-ROOT-04-01` resolved: continuous rotation is limited to one 15-second active attempt and cleaned up on exit.
5. `GAP-ROOT-04-01` resolved: eight page tests plus root-routing, full-suite, runtime-state, retry, recovery, and reconstruction evidence cover the contract.

## Classification and closure

PAGE-ROOT-04 is closed as `Verified`. Active restoration, live offline detection, CloudKit/account unavailability, local-only fallback, the delayed threshold, retry, safe account recovery, automatic profile arrival, relaunch routing, Dynamic Type, accessibility status, bounded motion, cancellation, and lightweight rendering now have static, automated, and runtime evidence.

`PAGE-ROOT-05` was not opened or audited during this pass.
