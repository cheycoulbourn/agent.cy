# PAGE-CAP-12 · Creator Session · Audit record

Audited 2026-08-21 after PAGE-CAP-11 against the current working tree. The
central availability flag, phone and desktop entry points, scheduled-post
action, global model route, sheet and overlay presentation, deep-link handling,
floating timer, launch retirement, dormant timer loop, persistence, queries,
and ActivityKit calls were traced separately.

## Contract under test

Creator Session is unfinished and must not be presented in the shipping phone
or desktop app. Attempts to request it must leave presentation and linked-post
request state unchanged. On launch, any stale in-app timer record or Live
Activity from an older enabled build is retired. Completed logs are preserved.
The active/paused/completed/restored timer contract is dormant and must receive
a fresh page audit before the availability flag can be enabled.

## Evidence

| Check | Result |
| --- | --- |
| Central availability flag is disabled | Pass (new focused regression) |
| Model presentation request is a no-op and does not stage linked-post state | Pass (new focused regression) |
| Phone sheet and floating timer require availability | Pass (route trace) |
| Desktop overlay and floating timer require availability | Pass (route trace) |
| Scheduled-post action is absent while unavailable | Pass (route trace) |
| Creator-session deep link performs no presentation | Pass (route trace; URL decoding remains intentionally recognized) |
| Root launch clears a stale creator-session sheet and invokes retirement | Pass (launch trace) |
| Retirement ends all matching Live Activities, records a final log when possible, and clears the active record | Pass (controller trace; isolated ActivityKit replay remains) |
| Existing record, log deduplication, optional title, ordered-mode, scroll-reset, and duration policies | Present in focused unit coverage |
| Availability/model regression gate | Pass (2 tests, 0 failures, iOS 26.5 simulator) |
| App and embedded extensions test build | Pass; existing deprecated frame-extraction warning remains outside this page |

## Findings

1. `GATE-CAP-12-01` — **Pass**: `CreatorSessionFeatureAvailability.isEnabled`
   is a centralized false constant. Every discovered phone, Catalyst,
   scheduled-post, sheet, overlay, floating-timer, model, and deep-link path is
   either hidden, guarded, or ignored. No current product path reaches the
   1,782-line page.
2. `COVER-CAP-12-01` — **Fixed**: the hidden-page contract previously depended
   only on static conditionals. Two regressions now fail if the availability
   flag is opened or if `presentCreatorSession` stages linked-post or sheet
   state while the page is unavailable.
3. `LIFE-CAP-12-01` — **Pass structurally**: root startup removes a stale
   `.creatorSession` presentation and awaits `retireUnavailableFeature`.
   Retirement ends all Creator Session Live Activities, appends one
   deduplicated completion log when an active record exists, and clears the
   active record even if log persistence fails. This favors stopping a
   withheld timer over retaining inaccessible active state.
4. `PERF-CAP-12-01` — **Dormant risk**: if re-enabled, the page owns three
   whole-table SwiftData queries, derives scoped posts by filtering all briefs,
   and updates page state every second while a session runs. The full screen
   can therefore be invalidated on each tick, and ActivityKit plus app-group
   persistence occurs on timer actions. This code cannot currently explain
   normal page scrolling or navigation slowness because it is unreachable.
5. `GAP-CAP-12-01` — **Open before re-enable**: active, paused, interval
   rollover, completion, relaunch restoration, persistence failure, ActivityKit
   denial/interruption, background/foreground, VoiceOver, accessibility text
   sizes, Reduce Motion, Catalyst sizing, energy use, and Release-device frame
   cadence have not been driven through the UI. The controller also suppresses
   save and ActivityKit request failures on several dormant actions.

## Classification and next gate

PAGE-CAP-12 closes as `Hidden`. The unavailable state is regression-pinned and
no current user-facing Creator Session defect was found. Do not enable the flag
until the dormant risks and named runtime states receive a new audit. Next
page: PAGE-PLAN-01 (Agenda engine).
