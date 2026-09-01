# S · Skeptic report

Written in fresh context after the six discovery lanes, against
`docs/refinement/00-contract.md`. I wrote none of the findings and I owe them nothing.
Everything below that says "verified" means I opened the cited file at the cited line, ran
the cited command, or re-derived the cited measurement myself on this machine.

**Headline: 124 findings stand, 8 are weakened, 1 is rejected. I add 10 gaps.**

The six lanes are, collectively, unusually honest. Every `Fix:` line in all 133 findings is
concrete — a grep for `consider|could|might|revisit|later|maybe|possibly|investigate|explore`
across every `- Fix` line in all eight files returns **nothing**. No lane lowered the bar from
rectify to note. No lane copied the archive: `docs/archive/audit-2026-08/` speaks in
`PAGE-xx` ids and "Coverage gap" / "Confirmed defect (fixed)" language that appears nowhere
in this pass, and where a number overlaps (the archive's "12 whole-table queries" on Home)
the surrounding measurements differ, so it was re-derived (the archive says Home is 2,503
lines; L4 measured 2,637, which is what `wc -l` returns today).

**The entitlement question you asked me to check: no lane mistook it for a shipping defect.**
The baseline simulator build was signed `CODE_SIGNING_ALLOWED=NO`, so Keychain and App Group
access fail and a red error appears on first launch. Only L6 touched it, and L6 scoped it
correctly and unprompted — `findings-apple.md:24-28` names the caveat up front, and APPLE-16's
Scope note says outright "the *trigger* I observed is a build artifact, and I am not claiming a
signed build shows this today," resting the finding on the code shape instead. A grep for
`keychain|entitle` across the other seven findings files returns only L4's method notes and
L5's (correct) description of the shared keychain access group. Nothing to correct.

---

## 1. Reconciling the three corrections to `01-page-inventory.md`

L3, L4 and L6 each filed a correction. They do not conflict; L3 and L4 differ only in scope,
and L6's is additive. I re-derived all three from source.

### Header census — corrected

The inventory's header variant **#3 `AgentPageRail`** says *"used only by home
(HomeDashboardView.swift:800). One-off pattern not reused anywhere else."* That is wrong.

```
$ grep -rn "AgentPageRail(" ios/AgentCy --include='*.swift'
ios/AgentCy/Views/Home/HomeDashboardView.swift:797
ios/AgentCy/Views/Tasks/TasksView.swift:686
ios/AgentCy/Views/Feed/SocialGridView.swift:484
ios/AgentCy/Views/Pillars/PillarsView.swift:470
ios/AgentCy/Views/Ideas/IdeaBankView.swift:370
ios/AgentCy/Views/Ideas/SavedPostsLibraryView.swift:234
```

- **L3 says four users** (home, tasks, pillars, idea-bank). Undercount — L3 only checked tab
  roots and missed `feed-grid` and `saved-posts-library`.
- **L4-19 says six adopters** and names `plan-week` as the sole hold-out. **Correct.**
- **L1-14 also says six** ("the other five roots … plus saved-posts-library"). Correct.

**Corrected header count: 8 variants, and variant #3 has 6 adopters, not 1.** The inventory's
"Uncertain — tasks / pillars / idea-bank tab-root headers" entry is resolved: all three use
`AgentPageRail`. The real header story is two shared components (`EditorialHeader` at 19 sites,
`SettingsPageShell` wrapping it for ~18 pushed settings pages at 21 sites), one shared tab-root
rail (`AgentPageRail`, 6 sites), and **one** hold-out (`PlanView.swift:127-158`) — not the
"one shared component used once and four one-offs" the inventory describes. This materially
changes B1's size: L1-14 / L4-19 is one file, not a header system rebuild.

### Close-control census — corrected

Three separate counts are in play and all three are wrong in different directions.

| Source | Claim | Verdict |
|---|---|---|
| `01-page-inventory.md:177` | **ten** distinct implementations | Off by one in each direction — see below |
| `findings-consistency.md` §1 (L1) | **nine** distinct implementations of "leave this screen" | Overcounts: three of the nine are not dismissal controls |
| APPLE-18 | inventory's "1 surface with no visible control" is off by one | **Correct** |
| L3-21 | two more one-off close controls beyond the ten | **Correct on one, correct-with-nuance on the other** |

What I verified myself:

- **APPLE-18 is right.** `installation-invite-gate` *does* have a close control —
  `RootView.swift:495-503`, a plain text `Button("Close")` in `.cancellationAction`, disabled
  while redeeming. So the inventory's family **#10 "no visible control at all" is empty**; that
  surface belongs to family #7 (text "Close"). This matters: it is the surface App Review
  reaches (O-11) and the one a beta tester meets on first launch (APPLE-15).
- **L3-21 is right about `DevelopBriefView.swift:128-135`.** It is a hand-rolled **opaque 44 pt**
  circle — `AgentIconView(.close, size: 16).frame(width: 44, height: 44).background(Color.agentSurface, in: .circle)`
  with **no stroke at all**. It is neither the inventory's #4 (glass hand-roll) nor #5 (40 pt
  opaque *with* a 1 pt `agentBorder`). A genuinely new family.
- **L3-21's `post-reschedule` half is a label correction, not a new family.**
  `AgendaView.swift:3964` is `Button("Close")` on phone; `:3985` is an X labelled "Cancel" on
  desktop. That is one surface split across families #7 and #6, which the inventory recorded
  as #6 only.
- **L1's §1 census overcounts by three.** Its item 2 folds `SocialGridView.swift:452-470` and
  `ResumablePostEditorView.swift:576-586` into the close family, and its item 3 adds
  `CreationHubView.swift:489-497`. I read all three: `SocialGridView:452` is the **feed refresh**
  button, `ResumablePostEditorView:576` is the **Spark** button, and `CreationHubView:489` is an
  **`.add` glyph inside a Quick Add option row** at 40 pt. None of them leaves a screen. L1-02's
  underlying finding (the 44 pt glass geometry is hand-rolled in four files) is sound and
  stands — it is the *census framing* that is wrong, and the merger must not carry "nine
  close-control families" forward.
- L1 also missed the **bare 24 pt checkmark** at `InspirationCaptureViews.swift:211` in its §1
  list, though L1-18 catches it separately and correctly calls it a further family.

**Corrected close-control census — 11 implementations, 4 geometries:**

| # | Implementation | Where | Sites |
|---|---|---|---|
| 1 | `AgentToolbarIconButton` / `AgentToolbarIconLabel` — 44 pt glass, glyph 17 (default), stroke `pureWhite@0.22`, `.buttonStyle(.plain)` | `DesignTokens.swift:286-322` | 43 + 15 refs; canonical |
| 2 | `AgentCircularGlassIconButton` — 48 pt glass, glyph 16, stroke `@0.16`, `AgentPressButtonStyle` | `DesignTokens.swift:917-942` | 6 call sites |
| 3 | `AgentDesktopDetailBackButton` — Catalyst text + chevron rail control | `DesignTokens.swift:390-418` | ~8 surfaces |
| 4 | Hand-rolled 44 pt glass, **plus** a shadow the component lacks | `CreationHubView.swift:214-247` | 1 |
| 5 | Hand-rolled 44 pt glass, same stray shadow, Catalyst-only | `AskCyView.swift:1275-1293` | 1 |
| 6 | Hand-rolled **opaque 44 pt**, `agentSurface`, no stroke | `DevelopBriefView.swift:128-135` | 1 — **new, from L3-21** |
| 7 | Hand-rolled **opaque 40 pt**, `agentSurface` + 1 pt `agentBorder` | `SocialGridView.swift:1041-1051` | 1 — under the 44 pt phone floor |
| 8 | Plain text **"Cancel"** | 49 occurrences | ~13 surfaces |
| 9 | Plain text **"Close"** | 47 occurrences (**not 46** — L1-16 is off by one) | ~4 surfaces, now including `installation-invite-gate` |
| 10 | **"Done"** as the only dismissal | `TasksView.swift:858`, `PostMediaViews.swift:897` | 2 |
| 11 | Bare **24 pt checkmark** `.confirmationAction`, no frame, no button style | `InspirationCaptureViews.swift:211` | 1 |

Family **#12 "no visible control at all" does not exist.** The walkthrough's `Button("Skip tour")`
(`AppShellView.swift:583`) is a further text one-off but is a *skip*, not a dismissal, and I
have left it out; the merger should record it as a twelfth if it wants label completeness.

Geometries in play: **40 pt, 44 pt, 48 pt, and text.** Diameters re-measured by me from L1's own
screenshot with L1's own script (`docs/refinement/evidence/consistency/png_measure_lib.py`):

```
tab-today-light.png, plan-week rail, ground (245,246,243)
  search    diam=44.00 pt  fill=(255,255,255)
  instagram diam=43.33 pt  fill=(255,255,255)
  avatar    diam=45.33 pt  fill=(253,253,251)   <- agentSurface
```

That independently reproduces L1-21's exact numbers, which were **not** in
`evidence/consistency/measurements.txt` (that file holds only three rows). L1-21 stands on
re-derived evidence.

---

## 2. Verdicts by lane

Format: every finding id, then the exceptions in detail. Anything not listed as an exception
**stands as filed**.

### L1 · Design consistency — 22 findings: 20 stand, 2 weakened, 0 rejected

Stands: L1-01, 02, 03, 04, 05, 07, 08, 09, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22.

I verified every L1 blocker and eleven of its twenty-two citations at source:

- **L1-01** — read both components. 44/17/`0.22`/`.plain` vs 48/16/`0.16`/`AgentPressButtonStyle`,
  disabled opacity 0.42 vs 0.34. Exactly as filed. `AgentCircularGlassIconButton` has exactly
  6 call sites. Stands.
- **L1-04 (blocker)** — `grep buttonStyle(.borderedProminent)` returns exactly the six sites
  claimed; `AgendaView.swift:2980-2992` is verbatim as quoted, `.tint(Color.agentPureWhite)`
  with a `pureBlack` glyph. Stands.
- **L1-05 (blocker)** — stands, with the count corrected: I find **nine** solid accent fills, not
  eight, and **eleven** accent glows, not ten. The Where line lists seven fills and the title
  says eight. Missing: `DevelopBriefView.swift:348`
  (`.background(canSend ? Color.cyAccent : …, in: .circle)`) and `CreationHubView.swift:227`
  (see gap G-5).
- **L1-08** — `AgentActionButtonTheme.radius = AgentRadius.control` and `AgentRadius.control = 8`,
  `AgentRadius.button = 10`. One line, ~95 buttons. Stands, and it is the single cheapest
  correction in B1.
- **L1-10 (blocker)** — read `PaperOnboardingPrimaryButtonStyle` (solid `actionAccent` capsule,
  56 pt) and `WalkthroughPrimaryButtonStyle` (solid `cyAccent`/`agentText` capsule + accent
  glow, 48 pt). Both verbatim. Stands.
- **L1-11** — `grep buttonStyle(.plain)` = **234**, `AgentPressButtonStyle()` = **97**. Exact.
- **L1-13, L1-17, L1-18, L1-19** — spot-read; all as filed.

**Weakened:**

- **L1-06 → duplicate of L4-13.** Same 158 sites, same two functions, same file. I confirmed the
  arithmetic independently: `paperInter(` = 137 lines (136 call sites + the declaration),
  `paperMetadata(` = 23 (22 + declaration) = **158 call sites**. Both lanes are right; the
  merger needs one owner. Keep **L4-13** (it carries the code-health framing and the
  gate-hardening follow-through) and cross-reference L1-06 for the seven-levels mapping.
- **L1-14 → duplicate of L4-19.** Same defect, same fix, and L4-19 additionally carries the
  inventory correction. Keep L4-19.

**Back to L1:**

1. Rewrite §1's census on the corrected list in §1 of this report. Three of its nine families
   are not dismissal controls.
2. §2's page × rule matrix **cannot be used to batch** — see gap G-9. Either redefine the CC
   column as conformance-to-canonical or mark the column totals as intra-file only.
3. §6 item 4 (the desktop modal footprint) is not a documentation correction — see gap G-8.
4. Fix the counts in L1-05 (nine fills, eleven glows) and L1-16 (47 × "Close", not 46).

### L2 · Motion — 11 findings: 11 stand, 0 weakened, 0 rejected

Stands: L2M-01 … L2M-11. This is the best-evidenced lane in the pass.

- **L2M-01 (blocker)** — I read `DesignTokens.swift:1644-1680`. `TimelineView(.animation(minimumInterval: 1/30))`
  rotating, scaling **and** animating `shadow(radius: 5 + pulse*4)`, exactly as quoted. The
  `minimumInterval: 1/30` is *why* the evidence file records Home at 30.1 fps and Cy at 60.0 fps
  — Cy carries a second mark, `CyThinkingMark` (`:1685-1707`), whose `TimelineView(.animation)`
  has **no** `minimumInterval` and therefore ticks at display rate. The two numbers corroborate
  each other. The method in `evidence/L2/idle-frames-by-tab.txt` is stated, scripted and
  reproducible.
- **L2M-04 (blocker)** — stands, count corrected. The title says eleven sites; the Where line
  lists sixteen file:line groups, one of which (`AskCyView.swift:1018`) L2M-02 exempts as a
  genuine progress indicator. I confirmed the `CyThinkingMark` half at source: under Reduce
  Motion it still enters `TimelineView` and drives `scaleEffect(0.94 + pulse*0.12)` and
  `opacity(0.68 + pulse*0.32)`. That is a direct breach of a named non-negotiable. Blocker
  confirmed.
- **L2M-03** — `.animation(reduceMotion ? nil : .snappy(duration: 0.32), value: selection)` at
  `AppShellView.swift:849`. Verified. The evidence file's burst-detection awk is shown in full.
- **L2M-08** — I read both shells. Phone: `.transition(.asymmetric(…))` at `:114-117` plus
  `.animation(.easeOut(duration: 0.24), value: appModel.taskCompletionUndo)` at `:159`.
  Desktop: `.transition(.move(edge: .top).combined(with: .opacity))` at `:112` and
  `grep taskCompletionUndo DesktopAppShellView.swift` returns only `109, 110, 1647` — no
  `.animation(…, value:)` anywhere. It pops. Exactly as filed.

**Back to L2:** correct L2M-04's site count (sixteen groups, minus the one L2M-02 exempts) so
the merger sizes the shared-helper change correctly.

### L2 · Heaviness — 8 findings: 6 stand, 1 weakened, 1 rejected

Stands: L2H-01, 02, 03, 04, 05, 06.

- **L2H-01 (blocker)** — read `AppShellView.swift:61-83`: six `NavigationStack`s in one `ZStack`,
  and `appTabLayer` (`:733-741`) sets only `opacity`, `allowsHitTesting`, `accessibilityHidden`
  and `zIndex`. `.opacity(0)` does not prevent layout or body evaluation, so the code is the
  proof. Stands at blocker. One note for the merger: the *measurement* half (shellhome ≈
  shellplan) is consistent-with, not proof-of, and the stated acceptance test ("the two must
  diverge") is weak — after the fix they diverge only if Home is genuinely heavier than Plan,
  which the same data suggests may not be by much. Better proof: instrument first-body counts,
  or measure with a large synthetic store.
- **L2H-02 (blocker)** — I re-ran the census. `@Query` = 251 repo-wide, 245 under `Views/`, 6 in
  `App/RootView.swift`, and `@Query(filter` = **0**. Exact to the finding.
- **L2H-04 (blocker)** — the idle recording is the strongest single piece of evidence in the
  program: four tabs emit 1 frame in 10 s, Home 300 and Cy 599. Method, script path and
  `ffprobe` command all stated. Stands.
- **L2H-06** — verified `AgentCyApp.swift:124-131` runs `refreshReminderSchedule` inside a
  `guard phase == .active` block alongside three other reconciliations. Stands.

**Weakened:**

- **L2H-07 major → minor** (re-escalates after gate G-device). The lane says so itself: *"A
  per-keystroke cost could **not** be isolated on the simulator… This finding therefore rests on
  the code, not on a timing."* The contract's success criterion is explicit — *"Heaviness causes
  are measured before and after, not guessed."* The code defect is real and certain (46 `@State`
  on one 2,374-line view, two workspace filters computed in `body`), but a **major** heaviness
  finding with no measurement is exactly the bar the contract sets. Keep the code fix in B2 if
  it is cheap; do not let it displace a measured item.

**Rejected:**

- **L2H-08 rejected as a heaviness finding.** The lane's own words: *"It costs nothing at
  runtime."* An unreferenced file that never runs is not a heaviness cause. The underlying fact
  (`TodayView` is dead, ten whole-table queries) is filed three times — **L4-02**, **L3-12** and
  here. Keep **L4-02** as the owner; drop this entry so the census does not triple-count one
  deletion.

**Back to L2:** nothing else. The "What could not be measured, and why" section — the failed
`xctrace` runs, the caret-blink contamination, the 34-record fixture floor — is the single best
piece of intellectual honesty in the pass and should survive into the beta-readiness report
verbatim.

### L3 · Cohesion and flows — 22 findings: 20 stand, 2 weakened, 0 rejected

Stands: L3-01 … L3-10, L3-13 … L3-22.

I verified all four blockers at source:

- **L3-01** — `AskCyView.swift:1274` opens `#if targetEnvironment(macCatalyst)` and the entire
  `showsCloseButton` block lives inside it. The `#else` branch (`:1300`) has no close. Verified.
- **L3-02** — `AskCyView.swift:651-659` verbatim, comment and all; `showsConversation`
  (`:2153-2161`) returns `pendingReviews.isEmpty && !showReviewCompletion` on non-Catalyst,
  gating the composer at `:669`. The fix genuinely shipped to the internal form factor only.
- **L3-03** — `grep scenePhase ios/AgentCy` returns 7 reaction sites (5 `.onChange`, 2
  `.task(id:)`), not 6 as the finding says; I opened all five `.onChange` bodies and every one
  is `guard phase == .active else { return }`. The substance — **no `.background` handler
  anywhere in the app** — is exactly right. Blocker stands; the count is off by one.
- **L3-04** — both phone call sites pass `presentsImportedSource: false`
  (`AppShellView.swift:226-228`, `:241-243`); the desktop takes the default `true`
  (`DesktopAppShellView.swift:142`, `:147`), and `AppModel.swift:1112-1119` is what that flag
  gates. `IdeaBankView.swift:253-255` really does compile the inspiration list out on Catalyst.
  The two shells are exact mirror-image mistakes, as claimed.

Spot-checked and confirmed: L3-13 (`MCPBridgeSettingsView.swift:1114` — bare `Button("Deny")`),
L3-17 (`AppTab.today` renders "Plan"; visible in `tab-today-light.png`, whose header reads
"WEEKLY AGENDA"), L3-18, L3-21.

**Weakened:**

- **L3-11 → duplicate of L4-01.** Same flag, same four surfaces. L4-01 is the stronger record —
  it adds that `CreatorSessionActivityWidget` is absent from `AgentCyWidgetBundle.body`, so the
  Live Activity could not render even if the flag flipped. Keep L4-01.
- **L3-12 → duplicate of L4-02.** L4-02 additionally rescues `TodayOutputPresentation` /
  `TodayOutputSection`, which `AgendaView.swift:1387` still uses — deleting the file naively
  breaks the build. Keep L4-02; L3-12's value is the page-purpose answer, not the deletion.

**Back to L3:**

1. `L3-17`'s fix edits `docs/PRD.md:76-77`. The contract reserves *"anything that changes the
   PRD"* for Chey. Split the fix: the `AppTab.today` → `.plan` rename is B3; the PRD edit is
   an owner item.
2. `page-purpose.md` §6 closes with "Filed as L3-11"; the dead route is **L3-18**.
3. Correct L3-03's "six observers" to seven.
4. The three unreproduced findings (L3-03, L3-01/02, L3-07) name exactly what is missing. Those
   fixture requests are the right ask and belong in the Chey list — see §4.

### L4 · Dead code — 10 findings: 10 stand, 0 weakened, 0 rejected

Stands: L4-01 … L4-10.

This lane's method is the most conservative in the pass and it says so: occurrences in comments
and string literals count as references, so the census under-reports. I re-ran the symbol counts
myself:

```
TodayView 1   PlanHeader 3   voiceExampleDrafts 1   proposedPillars 1   acceptPillar 1
addPublishingOutput 1   RecurringPostMaterializer 1   AgentDesktopPrimaryActionButtonStyle 1
agentBriefTitle 1   sectionHeadingSpacing 1   openCy 1   PillarMetrics 1
```

Every one matches. `PlanHeader`'s three hits are the declaration, the `where Actions == EmptyView`
extension, and the call from the dead `TodayView` — exactly as L4-02 describes.

L4-09's three-way split by removal risk — plain struct (delete), SwiftData column (schema
decision, defer with a reason), wire fields (leave) — is the correct shape and I would not
change it. L4-10's finding that the guard sits at the call site for three `PlanRuntimeFixture`
hooks and inside the function for the other three, with the honest note that **no release
behaviour changes today**, is a model of a well-sized minor.

**Back to L4:** nothing. The Periphery gate (G-tools) is correctly argued and correctly escalated
— B4 deletes ~3,500 lines and a false positive there is a build break. See §4.

### L4 · Code health — 13 findings: 13 stand, 0 weakened, 0 rejected

Stands: L4-11 … L4-23.

- **L4-11 (blocker)** — I reproduced it exactly:
  ```
  $ bash scripts/check_inter_typography.sh; echo "EXIT=$?"
  scripts/check_inter_typography.sh: line 14: rg: command not found
  Inter typography check passed.
  EXIT=0
  ```
  and running the same pattern through `grep` returns **exactly the eight** violations the
  finding lists, byte for byte. The root cause diagnosis is right: `rg` in an `if` condition
  suppresses `set -euo pipefail` for that command. Blocker confirmed. **See gap G-2 — the fix
  as written is incomplete.**
- **L4-12** — `command -v pnpm corepack` returns nothing on this machine, `.github/workflows/ci.yml`
  is 52 lines and contains neither `verify.sh` nor `check_inter_typography.sh` nor `pnpm build`.
  Verified.
- **L4-14** — every value in its comparison table is correct against
  `DesignTokens.swift:286-322` and `:917-942`. Its adoption counts (`AgentToolbarIconButton` 43,
  `AgentToolbarIconLabel` 15) reproduce exactly.
- **L4-19** — verified; it is the correct version of the inventory correction (see §1).
- **L4-20** — `evidence/L4/build-warnings.md` shows the commands, the destinations, the
  separate derived-data paths and the full site list. Three clean builds. Its observation that
  `copyCGImage(at:actualTime:)` is a **synchronous blocking frame decode** on the inspiration
  capture path, handed to L2 as a hang candidate, is the most useful thing in the finding.

**Back to L4:** L4-11's fix must add `ios/AgentCyInspirationShare` to `SEARCH_PATHS` (gap G-2),
otherwise the repaired gate still cannot see four raw system fonts in shipping iPhone UI.

### L5 · Security — 25 findings: 25 stand, 0 weakened, 0 rejected

Stands: L5-01 … L5-25.

**The lane did not touch the deployed service.** I checked: `probe-plan.md:3` states "No request
in this plan has been sent," a grep for `railway|agentcy.up|https://api.` across
`evidence/security/` returns nothing, and every artefact is locally produced —
`trustproxy-xff-spoof.txt` is a local Fastify instance, `pnpm-audit.json` is a registry query,
`swift-dependencies.txt` is a repo inventory. Confirmed clean.

All four blockers verified at source:

- **L5-01** — `LocalCyService.connectionConfig()` (`:267-278`) validates only
  `schemaVersion == 1 && token.count >= 32`. No scheme, host, loopback or private-range check
  anywhere in the function. Verified.
- **L5-02** — `PRIVACY.md:11` says "Capture makes no network request." `InspirationShareAPI.swift:112`
  POSTs to `/v1/inspiration/extract` and `:155` to `/v1/ai/inspiration/shape`.
  `ARCHITECTURE.md:35` says the extension "does not link SwiftData, AI, EventKit, notification,
  or CloudKit services." Both false. Verified.
- **L5-03** — `PRIVACY.md:23` says "The proxy does not fetch links."
  `inspiration-extractor.ts:46-50` is `Promise.allSettled([fetchHtml(canonicalUrl),
  fetchHtml(embedUrl), fetchOEmbed(oEmbedUrl)])`. Three fetches. Verified.
- **L5-04** — verified against `ARCHITECTURE.md:33` ("without attachment bytes or credentials").
  Verified.

I also independently confirmed **L5-11**: `app.ts:190-204` calls `authenticate` and then goes
straight to `inspirationExtractor.extract`. No reservation, no quota, no access check.

The **"Checks that came back clean"** section is the most valuable thing L5 produced and should
survive verbatim into the beta-readiness report — Apple identity token validation, installation
credential handling, share-extension transport validation, deep-link allow-listing, the absence
of `NSPredicate(format:)` anywhere, zero third-party SDKs, and the Local Cy runtime's
`allowedTools: []` isolation. Those are the answers a future auditor would otherwise re-derive.

Two caveats to carry, neither of which changes a verdict:

- **L5-05's fix assumes exactly one hop.** `trustProxy: 1` yields the right-most untrusted
  address only if Railway's edge adds exactly one `X-Forwarded-For` entry. If it adds two, every
  request collapses into one rate-limit bucket — worse than today. Add "read the real hop count"
  to P1 in the probe plan before shipping the change.
- **L5-16's fix says `pnpm update fastify --latest`.** The contract reserves *"dependency
  upgrades with breaking changes"* for Chey, and `--latest` can cross a major. Both reachable
  advisories are fixed by patch bumps (`fast-uri` ≥ 4.1.2, `find-my-way` ≥ 9.6.1) reached
  through `fastify`; reword the fix as a pinned patch bump and put the major decision on her
  list. The three MCP-side advisories the lane proposes to accept are correctly reasoned (the
  bridge is stdio-only, `mcp/src/index.ts`) but an acceptance is still hers.

**Back to L5:** the two rewordings above. Nothing else.

### L6 · Apple readiness — 22 findings: 20 stand, 1 weakened, 1 reclassified

Stands: APPLE-01 … APPLE-17, APPLE-21, APPLE-22.

All five blockers verified at source:

- **APPLE-01** — `grep -rni "revoke" server/src/` returns **nothing**. Verified.
- **APPLE-02** — `ios/project.yml:57-63`: the `Release` config carries `APS_ENVIRONMENT: development`,
  `CODE_SIGN_STYLE: Manual`, `PROVISIONING_PROFILE_SPECIFIER: AgentCy Development 2026`. The
  Catalyst target at `:141-142` gets it right, which is what makes it an oversight. Verified.
- **APPLE-03** — read `SubscriptionService.swift:33-73`. `startTrial` and `restore` both throw;
  `SubscriptionServiceFactory.runtime` returns `UnavailableLiveSubscriptionService` for every
  non-DEBUG build. One nuance worth carrying into the report: `.comped` **is** preserved
  (`isVerifiedLocally = state.trialEnd.map { $0 > now } ?? true`), so a promotional tester who
  lands on `.comped` will not be expired. Only `.trial` and `.paid` downgrade. L6 already scoped
  the severity that way ("blocker for App Store submission; major for the promotional cohort"),
  which is the right call.
- **APPLE-04** — the manifest declares exactly one category, and
  `grep systemUptime ios/AgentCy` returns the six sites claimed. Verified.
- **APPLE-05** — the share-extension manifest is `<key>NSPrivacyAccessedAPITypes</key><array/>`.
  Verified. This and APPLE-04 are ITMS upload validations, so they gate everything else in B6.

Also verified: APPLE-06 (`UIBackgroundModes: [audio, remote-notification]` at `project.yml:85-87`),
APPLE-07 (`NSAllowsLocalNetworking` + `NSLocalNetworkUsageDescription` at `:88-90`), APPLE-09
(no `NSPrivacyCollectedDataTypes` key at all, while the share extension declares an empty one),
APPLE-11, APPLE-13 (the tab-bar smear is plainly visible in `tab-today-light.png` too — "Set the
camera" reads through the bar), APPLE-17.

**Weakened:**

- **APPLE-20 — the finding stands at minor; its *conclusion* is withdrawn.** The Catalyst defect
  (`DesktopAppShellView.swift:340`, `.font(.system(size: 15, weight: .medium))`) is real. But the
  sentence *"Dynamic Type support is otherwise in good shape… this is the only one outside
  `DesignTokens.swift`"* rests on `grep -rn "\.system(size:" ios/AgentCy` — the **app target
  only**. The shipped archive also contains `ios/AgentCyInspirationShare`, which has four raw
  `.font(.system(size: 28/36/22/16))` calls and a six-token font family with **no `relativeTo:`
  on any of them**. See gap G-3. The "checked and clear" claim must be re-scoped or it will stop
  someone re-checking.

**Reclassified:**

- **APPLE-18 is a correction, not a finding.** Its body is "L1 owns this, and Apple imposes no
  constraint" plus the `installation-invite-gate` correction. The correction is right and
  valuable (see §1); the finding half has no defect of its own. Counting it as one of 133
  inflates the census. Reclassify as an inventory correction.
- **APPLE-19 stands, count corrected** — see gap G-6. The grep is `Image(systemName:)` only and
  misses four more live sites. "Seven of the twelve are on iPhone surfaces" is arithmetically
  eight of twelve, and twelve of sixteen once the missing forms are counted.

**Back to L6:** re-scope APPLE-20's clear-list claim to the app target; correct APPLE-19's census
and its "seven of twelve"; reclassify APPLE-18.

The **owner-step list (O-1 … O-14)** is the most immediately useful artefact in the whole pass —
it is ordered, it names dependencies (APPLE-01 blocked on O-3, APPLE-03 on O-6, APPLE-09 pairs
with O-5, APPLE-02 with O-4), and O-9's export-compliance answer is already substantiated with a
grep rather than asserted. Carry it into the beta-readiness report unchanged.

---

## 3. Gaps — what every lane missed

Ten, each with evidence I produced.

### G-1 · There are four typography APIs in the shipped binary, not two

L1-06 and L4-13 both name `Font.paperInter` / `Font.paperMetadata` as "a second, undocumented
typography API." There are two more, and no lane found either:

```
ios/AgentCyInspirationShare/InspirationShareDesign.swift:68-73
  static let shareTitle      = Font.custom("InterVariable", size: 26).weight(.semibold)
  static let shareHeadline   = Font.custom("InterVariable", size: 20).weight(.semibold)
  static let shareBody       = Font.custom("InterVariable", size: 16)
  static let shareBodyStrong = Font.custom("InterVariable", size: 16).weight(.semibold)
  static let shareMeta       = Font.custom("InterVariable", size: 12).weight(.semibold)
  static let shareCaption    = Font.custom("InterVariable", size: 14)

$ grep -c 'font(\.agent' ios/AgentCyInspirationShare/ShareViewController.swift
0
$ grep -c 'font(\.widgetInter' ios/AgentCyWidgets/WidgetViews.swift
50
```

`Font.widgetInter(size:weight:)` is a **third** raw-size escape hatch at 50 sites, and the
`share*` family is a **fourth** with its own six sizes (26/20/16/16/12/14) that map onto none of
the seven levels. Neither uses `relativeTo:`. So "tokens only" is failing in four places, not
one, and the fix list in L4-13 covers 16 files out of the ~18 that need it.
**Severity: major. Batch: B1.**

### G-2 · The repaired typography gate would still be blind to the Share Extension

```
# scripts/check_inter_typography.sh:6-12
SEARCH_PATHS=(
  "$ROOT/ios/AgentCy"
  "$ROOT/ios/AgentCyWidgets"
  "$ROOT/ios/AgentCyShared"
  "$ROOT/ios/AgentCyTests"
  "$ROOT/ios/project.yml"
)
```

`ios/AgentCyInspirationShare` is absent. So after L4-11's fix lands, these four still pass:

```
ShareViewController.swift:841   .font(.system(size: 28, weight: .semibold))
ShareViewController.swift:864   .font(.system(size: 36, weight: .medium))
ShareViewController.swift:889   .font(.system(size: 22, weight: .medium))
ShareViewController.swift:905   .font(.system(size: 16, weight: .semibold))
```

L4-11's fix must add the path. **Severity: major (it is the difference between a gate that works
and a gate that appears to). Batch: B4, with L4-11.**

### G-3 · The Share Extension's full-screen UI ignores Dynamic Type entirely

Consequence of G-1: all six `share*` fonts are `Font.custom(_, size:)` with **no `relativeTo:`**,
plus the four raw system fonts in G-2. `ShareViewController.swift` is 946 lines of full-screen
iPhone UI a beta tester reads on the PRD's shared-link ideation path (`PRD.md:54`, the path
L3-04 says produces no visible result). APPLE-20 concluded Dynamic Type is "otherwise in good
shape" from a grep over `ios/AgentCy` alone. A creator at an accessibility text size gets
unscaled 12–26 pt text in the one surface the app does not control the exit from.
**Severity: major. Batch: B1 or B6.**

### G-4 · Nobody audited the two shipping extensions for design consistency at all

L1's matrix is 164 surfaces, every one from `ios/AgentCy`. Between them
`ShareViewController.swift` (946 lines) and `WidgetViews.swift` (1,101 lines) ship
**2,047 lines of iPhone UI a beta tester sees**, carrying the fourth and third typography
families (G-1), seven SF Symbols (G-6), and their own colour and spacing decisions in
`InspirationShareDesign.swift`. L6 caught the SF Symbols and the privacy manifest; nobody
checked close controls, empty states, radii, hit targets, press feedback or appearance.
This is a scope hole, not a finding — but it means "every screen and sheet passes one
design-consistency checklist" is currently untrue of two shipping targets.
**Severity: major, as a scope item for B1.**

### G-5 · A ninth solid accent fill and an eleventh accent glow — on the first-run tour

```swift
// ios/AgentCy/Views/Capture/CreationHubView.swift:222-233 — the Quick Add close control
.background {
    if appModel.walkthroughStep == .quickAdd {
        Circle()
            .fill(Color.cyAccent)                                     // <- solid accent fill
            .shadow(
                color: Color.cyAccent.opacity(closeIsPulsing ? 0.18 : 0.46),  // <- accent glow
                radius: closeIsPulsing ? 14 : 8
            )
            .scaleEffect(closeIsPulsing ? 1.04 : 1)
    }
}
```

L1-05 lists neither site. L1-20 files `:229` as a **neutral** one-off shadow, which mis-sorts it
away from the ban that actually applies. Two named non-negotiables — *"No solid accent fills"*
and design.md's *"No glow — a glow was tried and rejected 2026-08-14"* — broken on the walkthrough,
the surface L1-10 itself calls one of "the first two screens a beta tester sees."

Second site, same class: `DevelopBriefView.swift:348` —
`.background(canSend ? Color.cyAccent : Color.agentSurface, in: .circle)`, a solid accent fill on
the send control. L1-05 lists only its glow at `:353`.
**Severity: blocker, folding into L1-05. Batch: B1.**

### G-6 · The complete SF Symbol census is 16 live sites, not 6 or 12

Both lanes grepped one form. L1-07 grepped `ios/AgentCy` (6 sites, correctly including
`ContentUnavailableView`); APPLE-19 grepped `Image(systemName:)` across all targets (12). Neither
found the union:

```
$ grep -rn 'systemImage:' ios/AgentCy ios/AgentCyWidgets ios/AgentCyInspirationShare ios/AgentCyShared
ios/AgentCy/Views/Shell/AppShellView.swift:458          "calendar.badge.exclamationmark"   (phone, ContentUnavailableView)
ios/AgentCyInspirationShare/ShareViewController.swift:633  Label(…, systemImage: "sparkles")            (phone)
ios/AgentCyInspirationShare/ShareViewController.swift:754  Label(…, systemImage: "arrow.down.circle.fill") (phone)
ios/AgentCyWidgets/PhoneControls.swift:11                  Label("Voice Spark", systemImage: "mic.fill")  (Control Center)
ios/AgentCyShared/CreatorSessionActivity.swift:31          var systemImage: String { … }                  (dies with L4-01)
```

**16 live sites**, of which **12 are on iPhone surfaces** — not APPLE-19's "seven of twelve".
`ios/project.yml:200-202` states the intent explicitly for system surfaces, so `PhoneControls.swift:11`
is in scope by the project's own rule.
**Severity: minor (contract violation, no Apple consequence), folding into L1-07. Batch: B1.**

### G-7 · Creation Hub bypasses the `AgentQuickAddLayout` hard rule

design.md:389-394: *"**Hard design rule — lower phone quick-action controls:** Close, Save, and
companion controls in phone Quick Action sheets sit in the canonical `AgentQuickAddLayout`
header: a 72-point control row placed 12 points below the safe area. Never pin these controls
directly to the safe-area edge or use a one-off negative/top offset. Use
`agentQuickAddHeaderSurface()`."*

```
$ grep -rn "AgentQuickAddLayout\|agentQuickAddHeaderSurface" ios/AgentCy --include='*.swift'
… VoiceSparkView.swift:420          .agentQuickAddHeaderSurface()
… QuickCaptureView.swift:509        .agentQuickAddHeaderSurface()
… SocialGridView.swift:1057         .agentQuickAddHeaderSurface()
… SavedPostsLibraryView.swift:449   .agentQuickAddHeaderSurface()
… CreatorSessionView.swift:320-321, 387-388   (uses the metrics directly)
```

`CreationHubView.mobileHeader` (`:213-247`) hand-builds its own `VStack`/`ZStack` and references
neither. It is **the entry point to every Quick Action sheet in the app**, so its control row
sits at a different height from every sheet it opens. L1-02 catches the hand-rolled *circle*;
nobody checked the *header rule*. **Severity: major. Batch: B1, with L1-02.**

### G-8 · L1 converts a hard-rule violation into a documentation edit

design.md:384-388: *"**Hard design rule — one desktop modal footprint:** every modal launched by
Quick Add and the Settings modal uses the spacious 900 × 860 … **Do not introduce smaller
per-flow modal sizes**; internal scrolling handles content length."*

```
ios/AgentCy/Models/DesktopNavigation.swift:110  workspaceModalMetrics   = 900 × 860
ios/AgentCy/Models/DesktopNavigation.swift:126  cyReviewModalMetrics    = 1180 × 860
ios/AgentCy/Models/DesktopNavigation.swift:137  creationHubMenuMetrics  = 600 × 560   <- smaller
```

L1's §6 item 4 files both as *"design.md corrections — where code and document disagree and code
wins"*, and justifies them because *"both carry explanatory code comments, so both look
deliberate."* A code comment is not Chey's approval. The contract's "code wins" clause settles
**disagreements**; it does not license a rule the document states as *hard* to be overwritten by
the code that breaks it. `cyReviewModalMetrics` at 1180 × 860 is *larger* and does not violate
the "smaller" clause; `creationHubMenuMetrics` at 600 × 560 does. This needs Chey's yes as a named
exception, or Quick Add moves to 900 × 860. **This is the one place a lane lowered the bar, and it
did so by reclassification rather than by hedged language.**

### G-9 · L1's page × rule matrix cannot be used to batch

The CC column is defined as *"close control (**one family per file**)"*. A file that uniformly
uses the *wrong* control therefore passes. Concretely:

```
| voice-recording-detail | Shared/VoiceRecordingDetailPage.swift | · | · | · | · | · | · | · | · | · | ? | – | · |
```

Twelve columns, all clean. But `VoiceRecordingDetailPage.swift:305` and `:313` are two of the six
`AgentCircularGlassIconButton` migrations **L1-01 itself requires**, and `:313` is one of the nine
sites in **L1's own §4 table item 6**. So L1's matrix marks clean a page that two of L1's own
findings say must change. The same shape holds for any single-family file. The column totals
(CC 145 failing) measure intra-file consistency, not conformance, and **understate**. The merger
must batch from L1-01/02/03 and §4, never from §2's totals. The `?` cells compound this — L1 §8
is explicit that `?` means *not checked*, not *passing*, and the HT column is `?` on 150+ rows.
**Severity: methodological. Back to L1.**

### G-10 · Arithmetic that does not survive a recount

Small individually, but they will mis-size batches:

| Claim | Actual | Where |
|---|---|---|
| "eight buttons" with a solid accent fill | 7 in the list, **9** in the code (G-5) | L1-05 |
| 46 × "Close" | **47** | L1-16 |
| 7 × "Done" | **8** occurrences (2 are dismissals) | L1-16 |
| "Eleven animation sites" | Where lists **16** groups, one exempt per L2M-02 | L2M-04 |
| "six [scenePhase] observers" | **7** reaction sites | L3-03 |
| Home has 12 whole-table `@Query` (prose) / 14 (census) | Both true — 12 on the root, 2 in the nested activity centre — but unmarked | L2H-01 vs `findings-heaviness.md` census |
| "Seven of the twelve are on iPhone surfaces" | **8 of 12**, **12 of 16** corrected | APPLE-19 |
| "nine distinct implementations of leave-this-screen" | **11**, and 3 of L1's 9 are not dismissals | L1 §1 |

---

## 4. Items that need Chey

**Gates**

- **G-device — profiling on her iPhone.** The contract's own success criterion ("no hang above
  Instruments' hang threshold on Chey's iPhone in the core journeys") is currently unmeasurable:
  `xctrace record` hung twice on this machine and produced no trace. Needed for L2H-01 through
  L2H-07, L2M-01/02 (battery and thermals), L2M-03 and L2M-09 (feel), and `CyThinkingMark` at
  120 Hz — its `TimelineView(.animation)` has no `minimumInterval`, so ProMotion cost is
  unmeasured. **L2H-07's weakened severity re-escalates on this gate.**
- **G-prod — the production probe.** `probe-plan.md` is 58 requests against
  `agentcy-production.up.railway.app`, correctly held at zero. Needs: ownership confirmation, a
  named 30-minute window, one disposable invite code, and the real ceilings read out of Railway
  first. **Add one item to P1:** read Railway's actual `X-Forwarded-For` hop count, so L5-05's
  `trustProxy: 1` fix is verified rather than assumed.
- **G-tools — two installs.** (a) `brew install peripheryapp/periphery/periphery` before B4
  executes; that batch deletes ~3,500 lines and a false positive is a build break. (b)
  `corepack enable && corepack prepare pnpm@11.7.0 --activate`, without which `scripts/verify.sh`
  cannot run at all on this Mac (verified: `pnpm` and `corepack` are both missing).

**Design decisions**

- **Button metrics.** design.md says 13 pt label / 40 pt min height; the code says
  `.agentHeadline` (18) at 52. "Code wins" would settle a design question rather than record
  one. Pick the number (L1-09, L1 §6.2).
- **The 36 pt onboarding masthead** (`OnboardingView.swift:317`): cap at `.agentDisplay` (32) or
  add an eighth type level (L1-06).
- **Liquid Glass on paper — one decision, not two.** L1-21 asks whether to keep glass and bring
  `ProfileSettingsButton` into line, or to specify the light-mode fallback as `agentSurface`
  explicitly. APPLE-13 independently asks whether every glass surface moves from `.clear` to
  `.regular` (all 13 `glassEffect` sites are `.clear`; zero are `.regular`). These are the same
  token-level decision and must be taken together.
- **The desktop modal exception (G-8):** approve `creationHubMenuMetrics = 600 × 560` as a named
  exception in design.md, or move Quick Add to the 900 × 860 footprint.
- **Consolidation shortlist** (`page-purpose.md` §5, correctly framed as recommendations with
  "what would flip it"): Creator Session, `brand-cabinet` out of beta, `saved-posts-library` into
  `idea-bank`, the desktop `feed-grid` tab, Home's three week-view cards, and the six-tab count
  (APPLE-14). Nothing is removed or hidden without her yes.

**PRD changes**

- L3-17 proposes correcting `PRD.md:76-77` (the PRD's "Today" ships as Home, its "Agenda" ships
  as Plan). APPLE-14's tab count and page-purpose §5's brand-cabinet deferral are also PRD
  changes.

**Security risk acceptances**

- The three MCP-side advisories L5-16 proposes to accept (`hono`, `@hono/node-server`,
  `ip-address`), unreachable because the bridge runs stdio-only.
- `PendingWeekProposal.appliedAt` left in the CloudKit-mirrored schema rather than migrated
  before beta (L4-09b).
- The twelve decoded-but-unread wire fields (L4-09c) — and the one worth acting on:
  `IdeaDirectionWire.whyItFits`, a "why this fits you" explanation the server computes for every
  idea direction and the app throws away.

**Dependency upgrade**

- L5-16's fix says `pnpm update fastify --latest`, which can cross a major. Both *reachable*
  advisories are patch bumps (`fast-uri` ≥ 4.1.2, `find-my-way` ≥ 9.6.1). The major is hers.

**Owner-only App Store work**

- O-1 … O-14 in `findings-apple.md` §2, in order. Two are hard blockers on code:
  **O-3** (the Sign in with Apple `.p8` key — APPLE-01 cannot be fixed without it) and **O-6**
  (the subscription decision — APPLE-03's shape depends on it). **O-8** (a published privacy
  policy URL and a support address) has no repo artefact at all yet.
- **App icon dark and tinted artwork** (APPLE-21) — a code change waiting on artwork.

**Fixtures L3 needs, or its three unreproduced findings stay unreproduced**

- A persistent-store fixture flag (`-agentCyPreviewPersistentData`) **or** an invitation code, for
  L3-03's relaunch survival. `-agentCyPreviewData` builds an in-memory container
  (`AgentCyApp.swift:15-22`), so no fixture launch can demonstrate it today.
- `-agentCyPreviewMCPQueue <type>`, seeding one pending `MCPBridgeChangeRequest`, for L3-01/02's
  real trigger. Flow 5 is currently untestable end to end.
- `-agentCyPreviewCyThread proposedPost`, for L3-07's duplicate-post reproduction.

**Housekeeping**

- `ios/build` (26 GB) and `ios/build-device` (285 MB) sit inside the iCloud-synced repo folder
  (L4-23). A device build lives in `ios/build-device` and may be installed on her phone — confirm
  before deleting.

---

## 5. The ten most important findings, in my order

Ordered by what a beta tester or App Review meets first, weighted by how cheaply it can be
made right.

1. **L5-02 + L5-03 + L5-04 — three published privacy statements that are false.**
   `PRIVACY.md` says the Share Extension makes no network request (it makes two, one a full AI
   call), that the proxy does not fetch links (it fetches three Instagram URLs per share), and
   `MCP_BRIDGE.md` contradicts itself about a live bearer token that is written into iCloud
   Drive. These are what five named testers are asked to trust and what the App Store Connect
   privacy answers are derived from. Fixing the documents is cheap; deciding whether the
   behaviour or the promise changes is Chey's.

2. **APPLE-04 + APPLE-05 — two missing required-reason API declarations.**
   ITMS-91053 stops the *upload*, before review. Nothing else in B6 can be tested until these
   land, and both are a dozen lines of XML. Highest ratio of consequence to effort in the pass.

3. **L3-01 + L3-02 — a modal opens itself over the creator's work, replaces Cy, and cannot be
   closed on iPhone.** A four-second poller raises it; the queue takes the whole conversation
   *and the composer*; the close control is inside `#if targetEnvironment(macCatalyst)`. The fix
   for the second half already shipped — to the internal form factor only.

4. **L3-03 — nothing in the app survives being backgrounded.** No `.background` scene-phase
   handler exists anywhere; four draft-owning surfaces flush only in `onDisappear`, which
   backgrounding and termination do not call. The contract's own success criterion is "the five
   core flows complete and **survive relaunch**." Data loss, not polish.

5. **L2M-01 + L2H-04 — Home and Cy never stop rendering.** 300 frames and 599 frames in ten
   untouched seconds, against 1 frame on every other tab, because a decorative asterisk animates
   a shadow radius forever. This is Chey's "the app feels heavy" with a reproducible number
   attached, and the fix is one component that already has a static branch.

6. **L1-04 + L1-05 + L1-10 + G-5 — four named non-negotiables broken on the first screens.**
   Solid pure-white `.borderedProminent` pucks at six sites, nine solid accent fills, eleven
   accent glows, capsule buttons on onboarding and the walkthrough — on the paywall, the
   first-run tour, day agenda and weekly focus. Three of these carry dated design decisions
   (2026-08-14) that the code contradicts.

7. **L5-01 — the app POSTs the full AI payload and a bearer token to any URL in a file.**
   `connectionConfig()` validates a schema version and a token length and nothing else. The file
   lives in a folder writable by anything on the creator's Mac and by any app granted it in
   Files. One scheme-and-host check closes it.

8. **APPLE-02 — the shipping Release config declares a development APNs environment.**
   One line in `ios/project.yml`. Left as is, every "Claude or Codex sent a proposal"
   notification silently fails for every tester, and the Catalyst target already gets it right
   in the same file.

9. **L2H-01 + L2H-02 — the shell builds all six tab roots on every launch, each running whole-table
   queries.** 1.6–2.5 s between "the model is ready" and "the first screen exists" on a cold
   launch, ~510 ms per tab switch, and `@Query(filter` returns **zero** matches across 251
   declarations. This is the structural half of "heavy", and it is the one whose cost grows with
   Chey's own data.

10. **L4-11 — the typography gate prints "passed" and exits 0 when `rg` is missing.**
    It is masking eight live violations right now, CI runs neither it nor `verify.sh`, and
    `verify.sh` cannot execute on this Mac at all. Last on the list because nothing breaks today
    — first in the batch order, because every consistency fix above it can regress silently
    until this is repaired. Fix it with G-2's missing search path included, or it will keep
    lying about a target it never looks at.

---

## 6. What I could not check

- **The desktop screenshots.** L1 says the Catalyst scheme built and ran and cites three PNGs.
  I confirmed the files exist and I read the code they claim to show, but I did not re-derive
  the Catalyst runtime evidence.
- **L4's three clean builds.** `evidence/L4/build-warnings.md` states the exact commands,
  destinations and derived-data paths; I verified the four warning sites in source but did not
  re-run the builds.
- **L3's XCUITest driver.** It lived in a session scratchpad, not the repo, so the `L3-A*` /
  `L3-B*` accessibility trees cannot be regenerated. The `.txt` and `.png` artefacts exist and
  the code paths they assert are verified independently, so the findings do not depend on it —
  but the probes are not re-runnable, which is the one place the pass leaves less behind than it
  should.
- **Hit targets.** L1 §8 is explicit that the `?` cells mean *not checked*. Across 164 surfaces,
  only 8 were verified. Neither I nor L1 measured the rest.
- **Contrast ratios.** Measured by nobody, in either appearance.
