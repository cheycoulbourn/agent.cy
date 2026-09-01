# L1 · Design consistency lane

Read `docs/refinement/briefs/_common.md` first. Output: `docs/refinement/findings-consistency.md`.

Question you answer: does every surface look like it belongs to the same app, by the rules in `design.md`? Chey's own example: "were all of the close buttons the same Liquid Glass X, and is it perfectly round on every single page?" Answer that literally, then generalize.

## Method

1. Read `design.md` end to end and `ios/AgentCy/Design/DesignTokens.swift`. Extract the checkable rules into a checklist (close control, header pattern, the seven type levels, the 4-pt spacing scale, radii, button family, accent discipline, icon source, flat lists, empty states, dividers on tinted surfaces, both appearances, both form factors, hit targets).
2. For every surface in the inventory, check the list statically by reading the view. Record a page × rule matrix (rows = slugs, columns = rules, cells = pass / fail / n.a. with file:line for each fail).
3. Run mechanical sweeps across `ios/AgentCy` and cite counts and sites: `Image(systemName:` (SF Symbols), `.font(.system(`, `.font(.` sizes not from the seven levels, `RoundedRectangle(cornerRadius:` / `.cornerRadius(` / `.clipShape(` with literal radii, `Capsule()` on buttons, `Color(` and `.opacity(` literals off the palette, `.padding(` with values outside 4/8/12/16/20/24/32/48/64, `.shadow(` outside `agentSurfaceChrome`, hard-coded strings that vary in capitalization for the same action (Cancel/Done/Save/Close), `.buttonStyle(` variants.
4. Capture screenshots of at least the six tab roots plus every sheet kind the inventory lists as having a distinct close control, in light and dark, on the iPhone simulator. If the Catalyst app can be built under the scratchpad derived data, capture the same on desktop; if not, say so and check desktop statically.
5. Group failures into shared fixes: which single shared component or token change closes the most rows at once. Name every call site each shared fix would replace.

## Deliverables in the findings file

- The close-control census verdict, in one paragraph Chey can read: how many variants exist, which is canonical per design.md, and where the others live.
- The page × rule matrix.
- Findings (L1-01 …) each with a fix and the batch (B1).
- A "shared components to introduce or unify" list ordered by number of sites closed.
- A "design.md corrections" list where code and document disagree and code should win.
