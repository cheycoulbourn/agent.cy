# PAGE-CAP-03 · Cy Pro access · Audit record

Audited 2026-08-19 (evening pass), static review + existing unit coverage
(649 iOS tests, 0 failures at audit time).

## Contract under test

Explain unavailable Cy creation and preserve the draft when routing to
Access. Required states: free/trial/expired, dismiss, return.
Performance concerns: sheet transition and state retention.

## What holds

- `CyProUpsellView` renders only for `.upgradeRequired`, with the message,
  benefit rows, primary "Access" routing, and a secondary dismiss. The
  rotating mark honors Reduce Motion.
- Draft preservation is structural: Access presents as a sheet *over* the
  quick capture sheet (`showAccess`), so the composer's state never leaves
  memory during the round trip.
- Unit coverage in `ServiceTests` pins the outcome mapping: a consumed free
  allowance produces `requiresUpgrade: true`; a provider-credit failure does
  NOT offer an upgrade (an upgrade cannot fix server credits); failed
  generations do not consume the free allowance; and
  `CyIdeaRequestPhase.failure(requiresUpgrade: true)` maps to
  `.upgradeRequired`.

## Findings

1. No defects reproduced or identified statically.
2. `GAP-CAP-03-01` — **Open**: the upsell is unreachable with current
   preview fixtures (needs a consumed freeJourney subscription state), so
   visual replay of free/trial/expired variants, VoiceOver, and the Access
   round-trip remains unrecorded. A `-agentCyPreviewAccessState` fixture
   would close most of this gap.

## Classification and next gate

PAGE-CAP-03 closes as `Coverage gap` — contract logic is unit-pinned and the
draft-retention guarantee is structural; reclassify when `GAP-CAP-03-01`
replays are recorded. Next page: PAGE-CAP-04 (Voice Spark).
