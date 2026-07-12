# ADR 0005: Paper-led product redesign

## Status

Accepted on 2026-07-12.

## Context

The first Figma board no longer represents the intended product. The creator has developed a fuller Paper prototype covering the visual system, information architecture, planning model, Cy surfaces, and onboarding. The running SwiftUI app already contains valuable local data, lifecycle logic, accessibility behavior, and native liquid-glass controls that must survive the redesign.

## Decision

Use the existing Paper file as the product and design source of truth. Preserve native SwiftUI navigation, liquid-glass controls, local-first SwiftData/private CloudKit storage, explicit acceptance for Cy proposals, and additive migration safety.

Adopt Today, Agenda, Tasks, Pillars, and Spark as the tab structure. Move Library behavior into Spark as Your work. Add lightweight posts, real subtasks, anchor-and-branch pillars with assigned days, and reviewable AI week drafts in staged releases.

Keep connected accounts, analytics, automatic publishing, trends, external inspiration, and a repurpose inbox out of this release. Platform selection and posting status remain manual.

## Consequences

- Paper replaces Figma in implementation documentation; the external Figma file is left untouched.
- Inter and IBM Plex Mono are bundled so the specified typography renders on-device.
- SwiftData changes are additive. Existing field names and entity identities are preserved for CloudKit compatibility.
- Each stage is verified and installed over the existing iPhone app without deleting creator data.
