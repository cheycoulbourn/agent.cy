# L6 · Apple readiness lane

Read `docs/refinement/briefs/_common.md` first. Output: `docs/refinement/findings-apple.md`.

Question: what would get this build rejected or make it a poor App Store or TestFlight citizen, and what must Chey do herself in App Store Connect? iPhone is the shipping target. Mac Catalyst is internal (ADR 0012) and needs no store checks; note only Catalyst issues that would embarrass an internal build.

## Sources

Fetch the current App Review Guidelines (https://developer.apple.com/app-store/review/guidelines/) and the relevant Human Interface Guidelines pages (navigation and modality, sheets, buttons, accessibility, Liquid Glass materials for iOS 26). Read `docs/TESTFLIGHT.md`, `docs/PRIVACY.md`, `ios/project.yml`, every Info.plist and entitlements file, and any `PrivacyInfo.xcprivacy`.

## Checks

- Guideline mapping: Sign in with Apple usage and the invitation-code gate (does review need a demo path? guideline 2.1, 5.1.1); account deletion availability (5.1.1(v)); in-app purchase and the missing RevenueCat purchase/restore flow (3.1.1); subscription disclosure copy; age rating and the 18+ claim; AI-generated content disclosures; permission purpose strings (calendar, microphone, photos, notifications, speech) and whether each request happens in context; background modes; export compliance flag; privacy manifest required-reason APIs; nutrition labels versus `PRIVACY.md`; third-party SDK manifests; App Attest status; launch screen and icon completeness; screenshots and metadata that will be needed.
- HIG mapping for the things Chey cares about: sheet and modal dismissal conventions, close control placement and size, back navigation, tab bar behavior, Dynamic Type support (find text with fixed sizes that ignore it), VoiceOver labels on icon-only controls, hit targets, Reduce Motion, dark mode, Liquid Glass usage correctness on iOS 26.
- TestFlight: what a tester sees on first launch (the invite gate), crash reporting, feedback path, What to Test content, build number hygiene.

## Deliverables

`findings-apple.md` (batch B6) in three lists: (1) rejection risks and blockers with the guideline number, evidence, and fix; (2) owner-only steps Chey must perform in App Store Connect or Xcode accounts, in order; (3) quality items that will not block review but would be noticed by testers. Each item says whether it is code (batch B6) or owner action.
