# PAGE-ROOT-01 Audit: Root Resolver

- Audit date: 2026-08-18
- Status: `Verified`
- Scope owner: [`RootDestination.resolve`](../../ios/AgentCy/App/RootView.swift) and the root selection inputs that feed it
- Parent program: [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation)

## Frozen contract

The root resolver must select exactly one destination. It must not show invitation or onboarding before required stored credential/account state is resolved.

| Condition | Expected destination |
| --- | --- |
| Installation invitation is not required; profile is absent | `onboarding` |
| Installation invitation is not required; profile exists | `app` |
| Invitation is required; credential status is unresolved | `launch` |
| Invitation is required; status resolved; usable credential is absent | `accountAccess` |
| Invitation is required; usable credential exists; profile absent; account unlinked | `onboarding` |
| Invitation is required; usable credential exists; profile absent; account linked | `restoringAccount` |
| Invitation is required; usable credential and profile exist | `app` |

The `launch` destination is a transient canvas, not a separate user workflow. `PAGE-ROOT-01` ends after selecting a destination. Account redemption, restoration copy/recovery, onboarding steps, and shell behavior belong to later page contracts.

## Inputs and ownership

| Input | Owner | Meaning |
| --- | --- | --- |
| `hasProfile` | SwiftData `@Query<CreatorProfile>` in `RootView` | At least one local/private creator profile is currently visible to the app. |
| `requiresInstallationInvite` | `AgentCyApp` construction and `AppModel` immutable configuration | Live-AI builds require the private installation gate; local preview builds do not. |
| `isInstallationCredentialStatusResolved` | `AppModel.refreshInstallationCredentialStatus` | The credential/erase-recovery check has finished for this launch. |
| `hasInstallationCredential` | `AppModel.refreshInstallationCredentialStatus` | A stored installation identity exists and its optional credential expiry is in the future. |
| `hasLinkedAccount` | Stored `InstallationIdentity.accountID` | The installation is linked to an account whose private profile may still be arriving. |

## Required evidence

- Static: every decision branch and every producer of the five inputs.
- Focused tests: the complete truth-table partitions, including invitation-disabled builds.
- Runtime: onboarding, account access, restoring account, and app destinations; launch must remain transient and must not flash the wrong destination.
- Persistence: profile arrival changes restoration to app; relaunch preserves the correct destination.
- Performance: time from process start to the first non-`launch` destination, repeated startup work, and any main-thread stall before credential resolution.

No approved launch-time threshold is present in the product sources. This audit will record measured behavior separately from contract correctness instead of inventing a pass threshold.

## Evidence log

### Static function trace

| Boundary | Evidence | Result |
| --- | --- | --- |
| Pure resolver | `RootDestination.resolve` in `RootView.swift:13-30` applies the frozen precedence: unresolved required credential, missing credential, missing profile, then app. | All seven frozen truth-table rows agree with the implementation. |
| Profile input | `RootView.swift:140-147` treats any queried `CreatorProfile` as a present profile. | Presence is the implemented contract. Whether an incomplete profile should count belongs to onboarding/product review. |
| Credential inputs | `AppModel.refreshInstallationCredentialStatus` in `AppModel.swift:302-330` resumes an interrupted privacy erase, bypasses the gate for local preview, loads Keychain identity, rejects expired credentials, derives linked-account state, and fails closed on load error. | Producers match the resolver inputs. A credential-load error routes to account access after publishing a notice. |
| Persistence gate | `PrivacyEraseCoordinator.resumeIfNeeded` in `PrivacyEraseCoordinator.swift:92-118` can hold credential resolution while an interrupted erase is resumed or paused. | Correctly remains upstream of destination selection; runtime checkpoint replay is not covered here. |
| Store creation | `ModelContainerFactory.make` in `ModelContainerFactory.swift:10-57` opens/migrates the store synchronously and retries local-only after a CloudKit-configured failure. | Root cannot present before this work completes. |
| App bootstrap | `AgentCyApp.init` in `AgentCyApp.swift:11-103` opens the container, runs `StoreBootstrapService`, migrates MCP fields, creates services, and fetches appearance/workspaces before constructing `RootView`. | Main-thread startup risk is now bounded by launch milestones; realistic large-store profiling remains. |
| Root launch task | `RootView.swift:167-200` performs legacy cleanup and recurrence/post repair before calling `refreshInstallationCredentialStatus` at line 184. Share, widget, calendar, MCP, reminder, and route work follows it. | The blank `launch` destination inherits all pre-credential work. |
| Repeated activation work | `AgentCyApp.swift:112-119` again reconciles focus tasks and refreshes widget/share/MCP/reminder state when the scene becomes active. | Potential duplicate startup work requires profiling and call-count evidence. |

The expensive signals are concrete full-store operations, not file-size guesses: `StoreBootstrapService.run` fetches, seeds, deduplicates, and migrates multiple model families (`StoreBootstrapService.swift:77-102`); legacy title cleanup fetches every task (`AppModel.swift:3202-3209`); focus recurrence fetches all workspaces, templates, and tasks and saves (`FocusTaskRecurrenceService.swift:27-127`); the one-time post repairs fetch several complete record families (`PostTaskScheduleRepairService.swift:17-71,88-150`).

### Focused automated evidence

Command run against an isolated Derived Data directory:

```sh
xcodebuild -project ios/AgentCy.xcodeproj -scheme AgentCy \
  -destination 'platform=iOS Simulator,id=E91882E0-A16C-40D2-84FB-7BB85A54AA5D' \
  -derivedDataPath <isolated-temp> CODE_SIGNING_ALLOWED=NO test \
  -only-testing:AgentCyTests/RootRoutingTests -quiet
```

Result after the coverage repair: **12 tests passed, 0 failed, 0 skipped** on iPhone 17 Pro / iOS 26.4. The suite now covers:

- invitation-disabled onboarding and app routes;
- unresolved required-credential states without an onboarding/access flash;
- missing, valid-unlinked, valid-linked, and expired credentials;
- Keychain-load failure through `AppModel` into fail-closed account access;
- linked/no-profile restoration changing to app when a profile arrives;
- file-backed profile persistence preserving the app destination after store reopen;
- parsing the deterministic restoration runtime fixture.

The complete Debug suite then passed **528 tests, 0 failed, 0 skipped** on iPhone 17 Pro / iOS 26.5 with isolated Derived Data.

### Disposable-simulator replay

A new iPhone 17 Pro / iOS 26.5 simulator was created solely for this page and the unsigned test build was installed without altering an existing simulator. The disposable simulator was deleted after evidence capture.

| Scenario | Expected | Observed |
| --- | --- | --- |
| Local preview, empty file-backed store | `onboarding` | Onboarding step 1 rendered. Pass. |
| Live-AI gate, empty file-backed store | `accountAccess` | Account access rendered. Pass. The visible Keychain error notice is consistent with the unsigned build lacking production entitlements; this harness cannot classify it as a product defect. |
| Debug seeded, in-memory store | `app` | Phone app shell/Home rendered. Pass. |
| Linked identity, profile absent | `restoringAccount` | A Debug-only in-memory linked-identity fixture rendered the restoration page. Pass. |
| Restoring identity, then profile arrival | `app` | The deterministic fixture inserted the arriving profile after restoration; `@Query` changed the root to the phone shell. Pass. |
| Restored profile after store reopen | `app` | The focused file-backed test saved a completed profile, reopened the store, and resolved to app. Pass. |

### Performance and smoothness

Classification: **Performance risk** (`PERF-RISK-01`), not a measured production regression.

- `RootLaunchDiagnostics` now emits Instruments signposts and timestamped unified-log milestones for process initialization, store readiness, bootstrap completion, app-model readiness, root-task start, pre-credential completion, credential resolution, and every presented destination. It records no creator data.
- A clean empty-store account-access replay reached `launch` at 188.2 ms, resolved its credential state at 198.9 ms, and presented account access at 232.6 ms from the diagnostics start.
- The restoration fixture reached `launch` at 236.8 ms, completed pre-credential work at 246.5 ms, resolved the credential at 250.5 ms, and presented restoration at 275.7 ms. The intentionally delayed fixture profile arrived and the app destination presented at 1,519.7 ms.
- A seeded in-memory app-shell replay presented app at 482.9 ms; store creation plus preview seeding reached `store_ready` at 128.4 ms. This remains a debug fixture, not a production large-store benchmark.
- The launch surface is only an unlabelled solid canvas (`RootView.swift:225-227`). Any slow store migration, recurrence repair, interrupted erase, or Keychain read is therefore perceived as an empty/frozen app rather than visible progress.
- There is still no approved launch budget or realistic large production-store fixture. `PERF-RISK-01` therefore stays open even though the measured fixtures did not reproduce a launch regression.

## Classification and closure

No root-routing contract defect was reproduced. `PAGE-ROOT-01` is closed as `Verified`: its truth table, credential failure boundaries, restoration transition, file-backed relaunch, reachable runtime destinations, and launch milestones now have direct evidence.

Residual evidence outside this page closure:

1. `PERF-RISK-01` remains open until a launch budget is approved and cold/warm launches are profiled with realistic small and large production stores.
2. The repository-wide Release simulator build is currently blocked by a pre-existing Swift concurrency error in `RecurringPostSchedule.swift:576`; the complete Debug build and 528-test suite pass, and no root file produced a Release diagnostic.
