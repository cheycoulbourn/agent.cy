# ADR 0011: Paper-led navigation and publishing catalog

Status: accepted, 2026-07-13.

Paper is the editable product and visual source of truth. The app uses Today, Agenda, Tasks, Pillars, and Cy as its five native liquid-glass tabs. A separate `+` chip opens the creation hub. Contextual Cy entry points may still open sheets, but there is no global floating Cy button.

Posts and tasks are distinct records and never duplicate one another automatically. Tasks are grouped into Pillar tasks and Production lanes. Publishing is represented by additive `PublishingDestination` and `PublishingFormat` models; legacy platform raw values remain dual-written for CloudKit and old-build compatibility.

There is one active anchor pillar. Other active pillars are supporting pillars with independent colors and weekdays. Existing fields and legacy rhythm models remain intact for migration compatibility.

All schema changes are additive and are backfilled idempotently at launch. Before a TestFlight build ships, every new CloudKit record type and field must be exercised in a development-signed CloudKit-enabled device build and promoted to the Production schema.
