# Process: code review

**Draft.** Written by job M from what the pre-beta lanes actually had to check. Job F finalizes it
after the batches ship, and it becomes a repo-local Claude skill.

## When it runs

On every change before it merges. Also on every task in `refinement-plan.md` before that task is
marked done — the plan's acceptance check is the *product* check; this is the *code* check, and both
must pass.

## Who runs it

A **fresh-context reviewer** — a subagent with no memory of writing the code, given only the inputs
below. This is not optional politeness. Two of this pass's findings exist because the author of a
fix could not see it: `AskCyView.swift:652-654` carries a comment recording that the MCP queue
defect was already found and fixed, and it shipped to Catalyst only (**L3-02**); the same file's
close control sits inside `#if targetEnvironment(macCatalyst)` (**L3-01**).

## Inputs

- The diff, and the full text of every file it touches (not just the hunks — **L4-06**'s ten dead
  members and **L4-03**'s nine dead methods all sit in files that were being edited).
- `docs/refinement/00-contract.md`, `design.md`, `docs/ARCHITECTURE.md`.
- The task's entry in `refinement-plan.md`, if it has one.
- `scripts/verify.sh` output and `scripts/check_design_review.sh` output, both run by the reviewer,
  not pasted by the author.

## Checklist

**Gates first.** A gate that cannot run must exit non-zero.

1. `scripts/verify.sh` completes. If it dies, say where, and do not review further until it runs.
   *(L4-12: it dies at line 13 on any Mac without pnpm, having reported success for eleven lines.)*
2. `scripts/check_inter_typography.sh` and `scripts/check_design_review.sh` exit 0, and the reviewer
   confirms they actually grepped something. *(L4-11: the gate printed "passed" and exited 0 with its
   tool missing, masking eight live violations. G-2: it did not search the Share Extension at all.)*
3. Three clean builds — iOS simulator, `build-for-testing`, Mac Catalyst — with **zero new warnings**.
   *(L4-20: fourteen warnings across three schemes; the Catalyst-only one shows that scheme is not
   built warning-clean as often as iOS.)*

**Correctness and reach.**

4. Does the change land on **both form factors**? Name the phone site and the desktop site, or say why
   one does not exist. *(L3-04: the two shells are exact mirror-image mistakes — the phone suppresses
   the import acknowledgement, the desktop compiles out the list it acknowledges into. L2M-08: the
   undo toast animates on phone and pops on desktop.)*
5. Is any behaviour gated on `#if targetEnvironment(macCatalyst)`? If so, is the gate load-bearing, or
   is it a fix that only reached one platform? *(L3-01, L3-02.)*
6. Does anything the change writes survive backgrounding and relaunch? Draft state written only in
   `onDisappear` does not. *(L3-03: there is no `.background` scene-phase handler in the app.)*
7. Every new persisted decision has a persistent test, not an in-memory one. *(L3-07: the "Create this
   post" chip's done-state is a `@State Set<UUID>` while its sibling task chip queries the store, so
   one Cy answer can produce two posts after a relaunch.)*

**Duplication and reuse.** Before adding a helper, grep for it.

8. Is this a new copy of something that exists? *(L4-18: twelve private trim-to-nil helpers under
   four names, and they are **not equivalent** — half trim, half do not. L4-15: five "Today /
   Tomorrow" implementations, one pinning `Locale(identifier: "en_US")`. L4-22: 41 inline
   `ISO8601DateFormatter()` allocations in one file. L4-17: four treatments of a 1 pt rule.)*
9. Does it hand-roll a shared component? *(L1-02, L4-14: four files re-typed the canonical glass
   circle and two had already drifted by adding a shadow the component lacks. L4-19: one tab root
   hand-rebuilt the page rail six others get from `AgentPageRail`.)*
10. Does it declare a design API outside `Design/`? *(L4-13: `Font.paperInter` lived at the bottom of
    a 2,370-line page file and 158 sites in fifteen other files depended on it.)*

**Dead on arrival.**

11. Is every symbol the change adds reachable? A feature behind a hardcoded `false` is not.
    *(L4-01: 2,520 lines behind `static let isEnabled = false`, whose Live Activity was not even
    registered in the widget bundle, so the flag could not have been flipped. L4-02: a complete
    443-line page whose only reference is its own declaration.)*
12. Is any fixture or preview code reachable in Release? *(L4-10: a 485-line fixture file with no
    `#if DEBUG` anywhere, and three fixture hooks guarded inconsistently with their own siblings.)*

**Cost.**

13. Does a new `@Query` carry a `#Predicate`? *(L2H-02: `@Query(filter` returned **zero** matches
    across 251 declarations; scoping happened in Swift after fetching the whole table.)*
14. Does a new view compute a collection inside `body`? *(L2H-07, L2H-01.)*
15. Does the change add a `.task`, `.onAppear` or `.onChange` that duplicates work another site
    already owns? *(L2H-06: `refreshReminderSchedule` ran three times per cold launch from three
    different `.task` bodies.)*

**Files.**

16. Does the change push a file over 2,000 lines, or add to one already over? Say so; the split
    proposals are in `findings-codehealth.md` L4-21. *(Fifteen files hold ~42% of the repo.)*

## Evidence required per finding

A review finding without evidence is a suggestion and is ignored. Each one carries:

```
### <one-sentence defect>
- Where: <file:line>
- Evidence: <the excerpt you read, the command you ran and its output, or the build log line>
- Severity: blocker | major | minor
- Fix: <the concrete change>
```

"Evidence" means something the reviewer produced in this review. A memory of a past defect, a link to
an archived audit, or "this looks like" is not evidence. The pre-beta pass held to this and it is why
the skeptic could verify it.

## Fix, don't note

**Threshold: if the fix is under ~30 lines and touches files already in the diff, the reviewer makes
it and says so.** Anything larger becomes a finding with a named owner and an id.

Two exceptions where the reviewer must *not* fix and must escalate instead:

- a change to a **SwiftData `@Model`'s stored properties** (CloudKit-mirrored; a schema change —
  L4-09b), and
- anything the contract reserves for Chey: removing or hiding a page, a PRD change, accepting a
  security risk, a breaking dependency upgrade.

## Output format

```
## Code review — <branch or task>

Gates:  verify.sh PASS/FAIL · typography PASS/FAIL · design lint PASS/FAIL · builds 3/3, N warnings
Verdict: approve | approve with fixes applied | changes requested

Fixed in review (N):
- <one line each, with file:line>

Findings (N):
<the finding blocks above, blockers first>

Not checked:
- <anything the reviewer could not verify, and why>
```

The **"Not checked"** section is mandatory and may not be empty without a sentence saying why. The
single most useful thing the discovery pass produced was L2's honest list of what could not be
measured; a review that claims complete coverage is a review nobody can build on.
