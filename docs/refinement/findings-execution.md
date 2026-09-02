# Findings raised during execution

Defects discovered while the batches run, outside the six discovery lanes. Same format and rules as the lane files.

### EXEC-01 Desktop app crashed with a SwiftUI environment assertion during sheet presentation
- Where: Chey's installed desktop build 0.1.0 (229), `~/Applications/agent.cy.app`, 2026-09-02 09:15:25
- Evidence: `docs/refinement/evidence/B1/task-2/desktop-crash-2026-09-02-091525.ips` — EXC_BREAKPOINT/SIGTRAP, `_assertionFailure` inside `EnvironmentValues.subscript.getter` reached from `DynamicBody.updateValue` (a view reading an `@Environment` value or object that is not installed at that point in the hierarchy). It fired about 60 s after a second Catalyst instance with the same bundle id was launched with `-agentCyPreviewData` (Task 2 fix round 1); shared `UserDefaults` for `com.agentcy.app` is the plausible trigger, but a view that can crash on an environment read is a defect regardless of the trigger. App frames are listed in the ledger; the installed build has no dSYM on this Mac, so symbol names inside the app image are unavailable.
- Severity: blocker (crash of the desktop app in normal use)
- Fix: identify the sheet whose content reads an environment object not provided by its presenter (candidates: any `.sheet` hosted from the desktop shell that reads `@Environment(AppModel.self)` or a custom `EnvironmentKey` without a default); provide it at the presentation site or give the key a safe default. Reproduce first with the Task 43 fixtures.
- Batch: B3
- Status: open
