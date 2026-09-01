# Process: design review

**Draft.** Written by job M from what lanes L1 and L2 actually had to check. Job F finalizes it after
the batches ship, and it becomes a repo-local Claude skill.

## When it runs

On every change that alters a rendered surface, before it merges — and on every new surface, without
exception. Also as a **sweep** over one page at a time when a batch lands, because the defects that
mattered most this pass were not in any single diff: they were the same control built eleven
different ways over months.

## Who runs it

A **fresh-context reviewer** who has not seen the design being defended, with a booted simulator and
a Catalyst build. It captures its own screenshots. It does not accept the author's.

## Inputs

- The diff and the surfaces it touches, named with the slugs in `docs/refinement/01-page-inventory.md`.
- `design.md` — canonical — and `ios/AgentCy/Design/DesignTokens.swift`.
- `docs/refinement/00-contract.md`'s non-negotiables.
- `scripts/check_design_review.sh` and `scripts/check_inter_typography.sh`, run by the reviewer.
- The simulator ("iPhone 17 Pro") and the "AgentCy Desktop" scheme, both appearances.

## Checklist

Run the lint first; it covers rows 1–5 mechanically and exists precisely because these five kept
coming back. **The lint is necessary and not sufficient** — it cannot see geometry or hierarchy.

| # | Row | Rule | Motivated by |
|---|---|---|---|
| 1 | **IC** icon source | No `Image(systemName:)`, no `systemImage:`, anywhere in any shipped target. Everything through `AgentIcon`. | L1-07, APPLE-19, **G-6** (the union is 16 live sites, 12 on iPhone — each lane grepped one form and missed the other) |
| 2 | **TY** type | Every text element maps to one of the seven levels. No `Font.custom(_, size:)`, no `.font(.system`, no `.caption`, and never without `relativeTo:`. | L4-13 (158 sites), **G-1** (four typography APIs in the binary, not two), **G-3** (the 946-line share sheet ignores Dynamic Type entirely) |
| 3 | **RA** radii | Only `AgentRadius`. Buttons are 10 pt. | L1-12 (eight off-scale radii at ~60 sites), L1-08 (the whole family was 2 pt off the contract) |
| 4 | **AC** accent | No solid accent fill. No accent glow. Ever. | L1-05, **G-5** (a ninth fill and eleventh glow, on the first-run tour) |
| 5 | **BT** buttons | No `.borderedProminent`, no capsule button, no bespoke style outside the shared family. | L1-04 (six identical solid-white pucks), L1-10 (the first two screens a tester sees) |
| 6 | **CC** close control | One glass circle, one diameter, one glyph size — and the *right* one, not merely one per file. | L1-01/02/03, L4-14, L3-21, **G-9** |
| 7 | **HD** header | A tab root uses `AgentPageRail`; a pushed page uses `EditorialHeader` / `SettingsPageShell`; a desktop drill-down uses `AgentDesktopDetailRail`. | L4-19, L1-19 |
| 8 | **SP** spacing | The 4-pt scale. Optical nudges under 8 pt on marks and badges are allowed **and must be named as such**. | L1-22 |
| 9 | **PF** press | Every control that draws its own background or glyph uses `AgentPressButtonStyle`, not bare `.plain`. | L1-11 (234 against 97) |
| 10 | **HT** hit targets | ≥ 44 pt on phone, ≥ 40 pt on desktop. **Measure it; do not eyeball it.** | L1-18, L1-03 |
| 11 | **ES** empty state | Every list screen uses `AgentEmptyState`, with a second sentence naming the action. | L1-17, L4-16 |
| 12 | **SH** elevation | Shadows only through `agentSurfaceChrome(role:)`. No animated shadow, ever. | L1-20, L2M-01 |
| 13 | **CP** copy | "Cancel" discards; the glass X leaves a read-only surface; "Done" is never a dismissal. | L1-16 (49/47/8 for one job) |
| 14 | **MO** motion | One of the five `AgentMotion` entries or nothing. No `repeatForever` in decoration. Reduce Motion honored — and re-evaluated, not just checked once at appear. | L2M-04, L2M-05, L2M-02, APPLE-17 |
| 15 | **ID** idle | The surface produces no frames when untouched. | L2M-01, L2H-04 |
| 16 | **CN** contrast | Text and glyphs meet contrast in both appearances. Measured off the capture. | Nobody measured this in the pre-beta pass; it is a known hole |

### The counting rule that must not be repeated

**Never batch or judge from a "one family per file" matrix.** L1's page × rule matrix marked
`voice-recording-detail` clean on all twelve columns while two of L1's *own* findings required that
file to change — because a file that uniformly uses the *wrong* control passes a per-file consistency
test. Every row above is **conformance to the canonical thing**, not internal consistency (**G-9**).

And `?` means *not checked*, never *passing*. The HT row was `?` on 150+ of 164 surfaces last time;
a review that leaves a row unchecked says so in its output.

### Scope rule

The review covers **every shipped target**, not just `ios/AgentCy`. `ShareViewController.swift` (946
lines) and `WidgetViews.swift` (1,101 lines) are 2,047 lines of iPhone UI a beta tester sees, and no
lane audited either for design consistency (**G-4**). If a target compiles into the archive, it is in
scope.

## Evidence required per finding

```
### <one-sentence defect>
- Where: <page slug + form factor + appearance>, <file:line>
- Evidence: <screenshot path under docs/refinement/evidence/design/>, and a measurement where the
  defect is geometric
- Severity: blocker | major | minor
- Fix: <concrete change, naming the shared component or token>
```

**Four screenshots per visible change, minimum:** phone light, phone dark, desktop light, desktop
dark. A change reviewed on one form factor is not reviewed. *(L1-04's solid white Save puck is
merely wrong in light and is the brightest object on the screen in dark; APPLE-12's Sign in with
Apple button is only broken when the appearance changes **at runtime**, so a cold-start capture in
each appearance would have missed it entirely.)*

**Geometry is measured, not judged.** `docs/refinement/evidence/consistency/png_measure_lib.py` and
`measure-close-controls.py` read diameters and interior fills straight out of a PNG; they are how
"44.00 pt / (255,255,255)" beside "45.33 pt / (253,253,251)" became a fact instead of an impression.
Use them.

**Reduce Motion and Dynamic Type are separate captures**, not assertions. So is the largest
accessibility text size on any surface with fixed-size text — that is how **G-3** would have been
caught.

## Fix, don't note

**Threshold: a token swap, a component substitution, a copy change, or a radius/padding/size
correction — anything under ~20 lines in files already in the diff — is fixed in the review.** These
are the overwhelming majority of design findings and scheduling them is how eleven close controls
happened.

Escalate rather than fix:

- introducing or deleting a **shared component or token** (it needs the site list),
- anything design.md states as a **hard rule** — the code does not get to overrule it by drifting
  (**G-8**: a per-flow desktop modal size was filed as a documentation correction because it "carried
  an explanatory code comment"; a code comment is not approval), and
- anything the contract reserves for Chey: the palette, removing or hiding a page, a button metric
  design.md and the code disagree on.

## Output format

```
## Design review — <surface or task> — <date>

Lint: design PASS/FAIL · typography PASS/FAIL
Captures: phone light/dark ✓ · desktop light/dark ✓ · Reduce Motion ✓ · largest text size ✓
Rows checked: IC TY RA AC BT CC HD SP PF HT ES SH CP MO ID CN   (mark each ✓ / ✗n / – / ?)
Verdict: approve | approve with fixes applied | changes requested

Fixed in review (N):
Findings (N):
Rows left `?` and why (N):
```

A row left `?` with no reason is a failed review, not a passed one.
