# ADR 0004: Local SwiftData store in the simulator

- Status: accepted
- Date: 2026-07-11

## Context

Device builds mirror the SwiftData store through the private `iCloud.com.agentcy.app` CloudKit container. Unsigned simulator builds do not have a usable iCloud entitlement. Forcing private mirroring in that environment triggers a CloudKit setup trap before the first screen appears.

## Decision

Use the stable `AgentCyStore` configuration name in every environment. On iPhone devices it uses the private CloudKit database. In the simulator it uses the same local SwiftData schema and store identity with CloudKit disabled. CloudKit sync validation remains a signed real-device test.

## Consequences

- Local simulator development and unit-test builds launch without production signing.
- The simulator remains a valid offline and UI test environment.
- Private CloudKit mirroring must be verified on signed devices, including the planned two-device deletion test.
- This is a compile-time platform boundary, not an error fallback to a second store.

