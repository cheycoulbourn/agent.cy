# PAGE-CAP-02 · Creator feature record · 2026-08-19

Creator request (verbatim intent): add an optional **Platform** choice to the
idea quick action page, and once a platform is chosen, show **Format** with the
formats under that platform. Both stay optional.

## What shipped (build 218)

- `CreativeBrief.preferredDestinationID` / `.preferredFormatID` — new optional
  fields (CloudKit-additive).
- `IdeaPlatformChoicePolicy` (QuickCaptureView.swift) — formats are
  destination-scoped, unarchived, sortOrder-sorted; a format never outlives its
  platform; clearing the platform clears the format.
- `sparkComposer` gains a Platform row (phone `Menu`, Catalyst inline picker)
  and a conditional Format row shown only while a platform is chosen. Both
  `saveIdea()` and the `updateSavedIdeaFromForm()` resume path persist the
  normalized selection.
- `AppModel.ensurePostDraft` honors the tag: developing a platform-tagged idea
  starts the post draft on that platform/format (platform-only tags fall back
  to that platform's first format; untagged ideas keep the profile default).

## Verification

- `PageCap02Tests` (4 tests): scoping/sorting/archival, orphaned-format
  normalization, `createSpark` persistence, `ensurePostDraft` carry-forward —
  RED observed first (missing policy/parameters), then GREEN.
- Full suite 638 iOS tests, 0 failures.
- Runtime replay on the disposable simulator (fixtures): Platform row renders
  under Pillar; choosing Instagram reveals Format listing exactly Reel /
  Carousel / Feed post / Story.

## Open

- Catalyst inline-picker visual replay and an accessibility (AX5) pass on the
  two new rows remain unrecorded.
