# S · Skeptic

You run in fresh context after the six discovery lanes. You did not write any of their findings and you owe them nothing. Output: `docs/refinement/skeptic-report.md`.

Read `docs/refinement/00-contract.md`, `docs/refinement/01-page-inventory.md`, then every findings file, census, matrix, page-purpose, flow-map, and probe plan under `docs/refinement/`. You may read the code and the evidence directory to check claims. You may open `docs/archive/audit-2026-08/` only to detect copying.

## Questions to ask of every lane

- Is every finding backed by evidence produced in this pass: a file:line that actually says what the finding claims, a measurement with the method stated, or a screenshot that exists on disk? Open a sample of at least a third of each lane's citations and all of its blockers.
- Did the lane copy a claim from the archive instead of re-checking it? Compare wording and citations.
- Is each heaviness cause measured, not inferred from file size or line count?
- Did the close-control and header claims come from the full inventory, on both form factors and both appearances?
- Is the consolidation option set broad enough that a missed alternative would not change the recommendation? Did the lane recommend anything the contract reserves for Chey?
- Did any lane lower the bar from rectify to note: findings with vague fixes, "consider", "could", "revisit later"?
- Did any lane invent a priority Chey did not state, or drop the phone or the desktop counterpart?
- Did the security lane send any request to the deployed service? (It must not have.)
- Where does a lane sound confident without proving anything?
- What did every lane miss? Spend real time on this: pick five surfaces from the inventory at random and check them yourself against design.md, motion standards, and the flow map. Report what the lanes did not catch.

## Output

For each lane: a verdict per finding (stands / weakened to <severity> / rejected, with the reason and the evidence you checked), the gaps you found with your own evidence, and what must go back to the lane. Then a short list of items that need Chey (device profiling, production probe, tool install, consolidation choices, risk acceptances). Then the ten most important findings across all lanes, in your order, with one line each on why. Do not modify any findings file; the merger will apply your verdicts.
