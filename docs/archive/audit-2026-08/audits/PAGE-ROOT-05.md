# PAGE-ROOT-05 Audit: Onboarding

- Audit date: 2026-08-18
- Status: `Verified`
- Repair verified: 2026-08-18
- Scope owner: [`OnboardingView`](../../ios/AgentCy/Views/Onboarding/OnboardingView.swift), `AppModel.completeOnboarding`, its `RootDestination.onboarding` entry/exit, and the Settings preview presentation
- Parent program: [`AUD-02`](../APP_AUDIT_QUEUE.md#aud-02-root-identity-restoration-and-workspace-isolation)

## Frozen contract

Onboarding must create the minimum local creator profile and workspace without requiring optional platforms, pillars, notifications, or a computer bridge. Every step must preserve earlier input, start at the top, remain reachable with the keyboard and largest Dynamic Type size, and expose accurate selected and validation states. Completion must either enter the shell once or show an actionable error without losing the draft. Preview mode must be dismissible without writing onboarding data.

`PAGE-ROOT-01` owns entry into onboarding and the profile-driven exit to the shell. `PAGE-ROOT-05` owns the eight-step draft, optional integrations, final persistence, and preview dismissal.

| Step or event | Expected behavior |
| --- | --- |
| 1. Welcome | Require adult confirmation; keep diagnostics consent optional. |
| 2. About you | Require a nonblank name and goal; expose both fields with stable accessible names. |
| 3. Your vibe | Choose both a palette and appearance, or explicitly skip both. |
| 4. Your content | Add, edit, or delete up to four ordered pillars; keep brand partnerships optional. |
| 5. Where you post | Select optional platform formats and validate optional handles before the terminal step. |
| 6. Your AI | Use Agent Cy immediately or choose the optional Claude/Codex bridge; bridge setup may be deferred. |
| 7. Notifications | Configure optional local reminders. If every reminder is off, continue without requesting notification permission. |
| 8. Ready | Summarize the draft, persist once, and exit to the dashboard or walkthrough. A failed completion must show the reason and provide a path back to the responsible field. |
| Back and step change | Preserve draft values and reset the new step to its top without leaving keyboard-driven scroll offset behind. |
| Relaunch after completion | Route directly to the shell from the persisted profile. |
| Preview | Close back to Settings without persistence; preview completion may dismiss into the selected shell destination. |

## Required evidence

- Static: every step and gate, back/skip behavior, optional-state clearing, handle validation, bridge polling, notification authorization, final persistence/rollback, root exit, relaunch, and preview-only behavior.
- Focused tests: persistence, idempotency, invalid required data, optional data, platform handles, reminder settings, failure visibility, step reset, accessibility semantics, and preview isolation.
- Runtime: required gates, every step, optional skips, invalid handle, successful completion, shell exit, relaunch, preview dismissal, dark appearance, largest Dynamic Type, and keyboard-driven step changes.
- Performance: typing and step invalidation, scroll stability, main-thread file work, bridge-poll lifetime, task cancellation, and visible transition hitches.

## Repair verification

The repaired page now owns its completion failures, preserves the draft, and routes the creator back to the responsible step. Step identity resets scroll position, notification authorization is requested only for an enabled reminder, and the page exposes stable field names plus selected-state values. The selected Vibe palette supplies the first-pillar editor's complete color set and preselects its first color. Re-selecting that same palette no longer overwrites an existing custom pillar color.

Completion now clears stale notices before attempting persistence. Invalid-handle coverage exercises the real `AppModel.completeOnboarding` path, proves that no profile is inserted, and proves that recovery resolves to Platforms. The active-workspace preference is written only after the model save succeeds, so a rolled-back setup cannot leave a dangling preference.

| Repaired scenario | Verification result |
| --- | --- |
| Invalid completion | `@bad handle` produced an in-page `Setup couldn’t finish` alert; `Review platforms` returned directly to step 5 with the selected platform and invalid handle intact. Correcting the handle completed into Home. |
| Vibe to first pillar | Selecting `Soft Girl Era` produced its five pastel colors in the first-pillar editor with color 1 selected. A focused policy regression also covers fallback colors and same-palette custom-color preservation. |
| Notifications off | Turning both reminder switches off changed the primary action to `Continue`; advancing showed Ready without a system authorization prompt. |
| Navigation and layout | Ready exposes Back. Each step has a distinct scroll identity; Accessibility XXXL replay advanced from a keyboard-shifted About-you step to the top of Your vibe in a one-column palette layout. |
| Accessibility | The goal editor has a stable name. Platform, YouTube, and format controls expose selected/not-selected values and traits. Pillar colors are uniquely numbered. |
| Persistence and preview | Preview completion remains non-persisting by policy. Successful completion entered Home; the existing file-backed root suite covers profile-driven relaunch. |
| Performance | Bridge-file status is read in a detached utility task, local runtime status stays actor-isolated off main, the polling loop is step-scoped and cancellation-aware, and no visible step hitch was observed in the replay. |

Automated result: **9 PAGE-ROOT-05 regressions passed**, including the real invalid-handle integration path. The full iOS suite passed **562 tests with 0 failures** on the disposable iPhone 17 Pro / iOS 26.5 simulator. The TypeScript baseline also remained green at **140 tests**, with typecheck and production build passing. The `AgentCy Desktop` build passed; only the pre-existing synchronous thumbnail deprecation warnings remained.

`./scripts/verify.sh` still stops before the suites on the already-recorded PAGE-ROOT-03 typography preflight reference in `RootView.swift`. That unrelated wrapper preflight was not changed here; the direct typecheck, test, iOS, and desktop commands above passed.

A read-only Fable 5 code review independently confirmed that the six original defects and bridge-polling risk were fixed. Its two actionable edge cases—same-palette custom-color loss and stale-notice attribution—were added as regressions and repaired before this page was reclassified.

## Evidence log

The trace and disposable replay below record the initial pre-repair reproduction. The repair evidence above is the current result.

### Initial static function trace

| Boundary | Evidence | Result |
| --- | --- | --- |
| Entry and exit | `RootDestination.resolve` selects onboarding only when no profile exists and the account is not waiting for restoration. A successful `context.save()` inserts a completed profile, so RootView's live query swaps to the shell. | Happy-path ownership is deterministic. |
| Step model | The private `Step` enum has eight ordered cases. One `OnboardingDraft` is retained in `@State`; Back, Continue, and Skip mutate the same draft. | Earlier values survive ordinary forward/back movement. |
| Required gates | Adult confirmation gates Welcome; trimmed name and goal gate About you; palette and appearance gate Your vibe. Pillars, platforms, AI, and notifications are optional. | The three intended required gates are enforced before advancing. |
| Optional clearing | Skipping vibe clears both palette and appearance. Skipping notifications disables both reminder categories. Empty pillars and platforms can advance. | Optional setup does not block completion. |
| Persistence | `completeOnboarding` trims and validates the required fields and handles, then inserts one profile, workspace, up to four ordered pillars, selected social accounts, reminder settings, and subscription state before one save. It rolls the context back on save failure. | The service path is transactional and its existing focused tests pass. |
| Final error presentation | Handle validation and save failure set `appModel.notice`. Onboarding's only alert observes `bridgeNotice`; the `appModel.notice` alert exists in `AppShellView`, which is not mounted while onboarding remains active. The Ready controls also omit Back. | A terminal failure is invisible and leaves no in-page recovery path. |
| Notification authorization | The primary title and action depend only on authorization status, not whether either reminder toggle is enabled. | Turning both reminders off still offers and invokes `Turn on notifications`; only the separate Skip action avoids the prompt. |
| Bridge status | While the AI step is active, a view task refreshes every three seconds. `MCPBridgeService.connectionStatus()` resolves the bookmark and reads/decodes a file on the main actor; `refreshBridgeStatus()` also launches a separate task for the local runtime file. | Work is step-bounded but creates a main-thread I/O and body-invalidation risk. |
| Motion | Step slides and press scaling are removed when Reduce Motion is enabled. | No unbounded decorative animation was found. |
| Preview | Preview mode exposes a named Close control, restores the stored appearance on disappearance, bypasses persistence, and dismisses after either final action. | Close dismissal returned to Settings in runtime replay. |

### Initial automated evidence

Focused command:

```sh
xcodebuild -project ios/AgentCy.xcodeproj -scheme AgentCy \
  -destination 'platform=iOS Simulator,id=<PAGE-ROOT-05-disposable-simulator>' \
  -derivedDataPath /tmp/AgentCy-PAGE-ROOT-05-AUDIT-DerivedData \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:AgentCyTests/VoiceExampleTests

xcodebuild -project ios/AgentCy.xcodeproj -scheme AgentCy \
  -destination 'platform=iOS Simulator,id=<PAGE-ROOT-05-disposable-simulator>' \
  -derivedDataPath /tmp/AgentCy-PAGE-ROOT-05-AUDIT-DerivedData \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:AgentCyTests/RootRoutingTests \
  -only-testing:AgentCyTests/DomainTests/testOnboardingOffersFourCuratedColorways \
  -only-testing:AgentCyTests/DomainTests/testOnboardingOffersNativeAndCreatorOwnedAIPaths
```

Result: **27 passed, 0 failed** across 13 onboarding-persistence tests, 12 root-routing tests, and two onboarding-option tests. The focused runs also built the current iOS app successfully.

The existing tests prove correct onboarding entry, profile-driven exit, required-data rejection without partial records, successful profile/workspace/pillar/account/reminder persistence, optional voice deferral, invalid evidence rejection, idempotent completion, and the curated palette/AI choices. They do not mount `OnboardingView`, so terminal error visibility, Back availability, step scroll reset, notification-off authorization, field naming, selected-state semantics, and preview isolation remain uncovered.

### Initial disposable-simulator replay

A disposable iPhone 17 Pro / iOS 26.5 simulator was used only for PAGE-ROOT-05.

| Scenario | Observed result |
| --- | --- |
| Required gates | Welcome stayed disabled until adult confirmation; About you required both fields; Your vibe required palette plus appearance unless skipped. |
| Optional setup | Empty pillars and platforms advanced. Claude/Codex setup exposed `Finish later`. Notification Skip disabled both reminder categories. |
| Invalid handle | `@bad handle` advanced through Ready. `Go to dashboard` left the page unchanged, showed no alert or inline error, and Ready exposed no Back control. |
| Successful completion | A clean path with optional sections skipped entered Home, greeted the persisted creator, and remained in the shell after process relaunch. |
| Preview exit | Settings opened the onboarding preview; `Close onboarding preview` dismissed back to Settings without changing the persisted profile. |
| Accessibility tree | The goal editor appeared only as an unnamed settable Group. Selected Instagram and YouTube-format controls exposed no selected trait/value. All preset color controls announced the identical name `Pillar color`. |
| Notifications off | With both reminder switches off, the primary action still read `Turn on notifications`; Skip was the only no-prompt path. |
| Dark and largest text | Content stayed reachable in the accessibility tree and the clean path completed. Palette cards visually truncated detail text, and keyboard-driven scroll from About you carried into Your vibe so its heading began offscreen. |

### Performance and smoothness

Classification after repair: **No issue observed in replay; residual large-owner profiling remains a general risk signal**.

- The 1,836-line owner mixes eight screen bodies, sheets, bindings, final actions, bridge setup, and custom components. Size alone is not a defect, but every draft mutation invalidates the top-level owner.
- The normal-size step transitions and successful shell exit showed no visible frame hitch in the disposable simulator.
- The single long-lived `ScrollView` retains its offset while only `stepContent` changes identity. After the keyboard shifted About you at Accessibility Extra Extra Extra Large, Your vibe appeared partway down rather than at its heading. This is a confirmed navigation/layout defect, not a measured rendering slowdown.
- Bridge status-file decoding now runs in a detached utility task. Local runtime status stays on its actor, and the polling task is cancellation-aware and scoped to the AI step. Large-owner body invalidation remains worth profiling with production-sized data, but the confirmed main-thread polling cause is closed.
- No media decoding, large collection query, or repeated sort/filter work exists on this page.

## Resolved defects and coverage gaps

1. `DEFECT-ROOT-05-01` — **Resolved**: completion failures use an onboarding-owned alert, preserve the draft, and route to Platforms or Ready; Ready exposes Back.
2. `DEFECT-ROOT-05-02` — **Resolved**: every step recreates the scroll container with a distinct identity.
3. `DEFECT-ROOT-05-03` — **Resolved**: the goal editor has a stable accessible name.
4. `DEFECT-ROOT-05-04` — **Resolved**: platform and YouTube-format selections expose values and selected traits.
5. `DEFECT-ROOT-05-05` — **Resolved**: preset pillar colors have unique positional names and state values.
6. `DEFECT-ROOT-05-06` — **Resolved**: all-reminders-off continues without requesting authorization.
7. `RISK-ROOT-05-01` — **Resolved cause**: bridge-file reads are off-main and polling is structured, step-scoped, and cancellable. Production profiling remains part of the cross-page large-owner risk.
8. `GAP-ROOT-05-01` — **Closed**: nine page regressions cover the state/policy boundaries, including a real invalid-handle persistence failure.

## Classification and closure

PAGE-ROOT-05 is closed as `Verified`. Its eight-step contract, palette handoff, error recovery, consent boundary, accessibility semantics, preview isolation, persistence transaction, and polling lifetime now have direct regression or runtime evidence.
