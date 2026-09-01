# Decision packet — gate H1

Ten minutes. Nineteen decisions, five security risk acceptances, four authorizations, fourteen
Apple owner steps, and the ten findings I would fix first. Everything here is blocking: the plan has
placeholder tasks waiting on each one, and none of them can be decided from the repo.

---

## 1. The plan in one paragraph

Six lanes and a skeptic produced 125 standing findings plus ten gaps the lanes missed; four were
duplicates, so **121 distinct defects** enter **113 tasks** across six batches, in the contract's
priority order. B1 makes every screen use one close control, one header, one button family and the
type tokens — including the two shipping extensions nobody had audited. B2 gives the app one motion
vocabulary and stops Home and Cy rendering 300 and 599 frames in ten untouched seconds. B3 makes the
five core flows finish, say what happened, and survive being backgrounded — which nothing in the app
does today. B4 removes ~3,500 lines of unreferenced code and repairs the two gates that would have
caught the drift. B5 fixes four security blockers, three of them published privacy statements that
are false. B6 clears what stops the archive uploading and what App Review would meet first. Eight
findings are deferred with written reasons; nothing is deferred silently.

| Batch | Subject | Tasks | What it makes true |
|---|---|---|---|
| **B1** | Design consistency | **27** (1–27) | One 44 pt glass close control everywhere, one button family at 10 pt corners, no solid accent fills or glows, tokens only — on phone and desktop, light and dark. Answers your close-button question directly. |
| **B2** | Motion and heaviness | **15** (28–42) | Five durations and two curves instead of fourteen and four; Reduce Motion honored at every site; all six tabs idle when untouched; the shell builds one tab, not six. |
| **B3** | Cohesion and flows | **17** (43–59) | Every capture path lands somewhere; the Cy sheet can be closed on iPhone; every draft survives backgrounding; a shared link is acknowledged. |
| **B4** | Dead code | **16** (60–75) | ~3,500 lines and 17 assets gone; the typography gate stops printing "passed" when it greps nothing; CI runs the same gate as `verify.sh`. |
| **B5** | Security | **22** (76–97) | The app stops POSTing your content to any URL in a file; `PRIVACY.md` becomes true; the server's rate limits and spend ceilings become real. |
| **B6** | Apple readiness | **16** (98–113) | The archive passes ITMS validation; production APNs; account deletion is called account deletion; the first screen is written for someone new. |

---

## 2. Decisions

### DEC-01 · Liquid Glass on the paper canvas

- **Question:** Does the glass stay clear (and the avatar join it), or do we specify the light-mode
  fallback as an opaque `agentSurface` disc — and does every glass surface move from `.clear` to
  `.regular`?
- **Recommendation:** move every glass surface to `.regular`, and give `ProfileSettingsButton` the
  same geometry and material as the toolbar control. `.regular` is the variant Apple designed to adapt
  to arbitrary content behind it; `.clear` expects a dimming layer and media you own.
- **Strongest alternative:** accept that glass reads as opaque on paper and specify the light-mode
  fill explicitly as `agentSurface` + the 0.5 pt stroke, so it is a chosen colour rather than a
  system artefact.
- **Tradeoff:** `.regular` is slightly more opaque and less "iOS 26"; the explicit-fill route gives up
  the material entirely on light backgrounds but is completely predictable.
- **Evidence:** measured on `tab-today-light.png` — the plan-week search and feed circles are
  44.00 pt filled `(255,255,255)` on a `(245,246,243)` canvas, while the avatar 30 pt away is
  45.33 pt filled `(253,253,251)`. Three circles in one rail, two whites, two diameters. And on
  `home`, the task row behind the tab bar reads *through* it — "THE ONE JOB IDEA TEST · TODAY · NONE"
  is legible along the bar's top edge (`evidence/apple/tabbar-glass-legibility.png`).
- **Confidence:** high that it must change; medium on which way.
- **Flips it:** seeing both on your phone in bright sunlight. This is the one decision I would ask you
  to make with the device in your hand rather than from a screenshot.
- **Unblocks:** Task 25 (closes L1-21, APPLE-13).

### DEC-02 · The button metric

- **Question:** Is a primary button 40 pt tall with a 13 pt label (what design.md says) or 52 pt with
  an 18 pt label (what the code does)?
- **Recommendation:** 44 pt with a 15 pt label. Neither number is currently honored — the family has
  six minimum heights and two label sizes — and 40 is below the phone tap-target floor while 52/18 is
  visibly heavier than the quiet, bordered treatment the rest of the app uses.
- **Strongest alternative:** keep 52/18 and rewrite design.md, on the grounds that "code wins".
- **Tradeoff:** 44/15 is a change you will see on every screen at once; 52/18 is free but locks in a
  size chosen by drift rather than by decision.
- **Confidence:** medium. This is a taste question and I have no evidence that settles it.
- **Flips it:** you looking at one screen at each size.
- **Unblocks:** Task 26 (closes L1-09 and the second design.md correction).

### DEC-03 · The desktop modal footprints

- **Question:** Do the two off-spec desktop modal sizes become named exceptions in design.md, or do
  they move to the one 900 × 860 footprint the hard rule states?
- **Recommendation:** approve `cyReviewModalMetrics = 1180 × 860` as a named exception (the Cy review
  workspace genuinely needs the width) and move `creationHubMenuMetrics = 600 × 560` to 900 × 860.
- **Strongest alternative:** approve both as named exceptions.
- **Tradeoff:** the Quick Add choice card at 900 × 860 is a lot of empty space for six options; the
  rule's value is that there is no per-flow sizing conversation ever again.
- **Evidence:** `DesktopNavigation.swift:110, 126, 137`; design.md:384-388 states this as a **hard**
  rule and says "do not introduce smaller per-flow modal sizes". L1 filed both as documentation
  corrections because "both carry explanatory code comments, so both look deliberate" — a code comment
  is not your approval, which is why this is here.
- **Confidence:** high that it needs deciding; medium on the split.
- **Flips it:** seeing the Quick Add card at both sizes side by side.
- **Unblocks:** Task 27 (closes G-8).

### DEC-04 · The 36 pt onboarding masthead

- **Question:** Does the onboarding headline cap at `.agentDisplay` (32 pt), or does the type scale
  gain an eighth level?
- **Recommendation:** cap at 32. Seven levels is the rule; one screen is not worth an eighth.
- **Strongest alternative:** add a `.agentMasthead` level at 36 for first-run surfaces only.
- **Tradeoff:** onboarding loses a little presence; the scale keeps its integrity.
- **Evidence:** `OnboardingView.swift:317` is the only 36 pt text in the app, reached through the
  `paperInter` escape hatch Task 8 deletes.
- **Confidence:** high.
- **Flips it:** the capped version reading as timid on the first screen.
- **Unblocks:** the last site in Task 8.

### DEC-05 · Creator Session

- **Question:** Does the Creator Session family come out of the binary, or does it get a ship date?
- **Recommendation:** remove it. 2,520 lines across four files behind
  `static let isEnabled = false`, seven statically-false gates, a deep-link case that routes nowhere,
  and a Live Activity that **could not render even if you flipped the flag** — `CreatorSessionActivityWidget`
  is absent from `AgentCyWidgetBundle.body`, which lists twelve other widgets. It also distorts every
  census taken across the app (it supplies four of the six sites of the 48 pt close control B1
  unifies) and it is why `UIBackgroundModes: audio` and `NSSupportsLiveActivities` are declared,
  both of which are App Review questions.
- **Strongest alternative:** keep it, register the widget now so the flag is actually flippable, and
  exclude the family explicitly from future censuses.
- **Tradeoff:** removing it discards real, finished work; keeping it ships four unreachable surfaces
  and two Info.plist declarations to five testers and to App Review.
- **Confidence:** high on the analysis; the call is yours because it is a feature.
- **Flips it:** you intending the session timer to be in the beta story.
- **Unblocks:** Task 74 (closes L4-01, L3-11, L3-22) and half of Task 101.

### DEC-06 · `brand-cabinet`

- **Question:** Does brand-deal management ship to the five beta testers, or stay behind its setting,
  default off?
- **Recommendation:** behind its setting, default off, out of the beta story. The PRD explicitly
  defers brand-deal management, and the family is seven surfaces plus a settings page.
- **Strongest alternative:** ship it on — it works, and a creator with a brand deal will look for it.
- **Tradeoff:** a working, opt-in feature goes unused for the pilot; the alternative adds seven
  surfaces to everything the beta has to be good at.
- **Confidence:** medium-high.
- **Flips it:** putting brand deals in the beta story — which is also a PRD change (DEC-11).

### DEC-07 · `saved-posts-library`

- **Question:** Does the saved-posts library stay a page, or become a filter inside `idea-bank`?
- **Recommendation:** merge it into `idea-bank` as a filter. It is a filtered view of records the
  Idea Bank already lists, and the phone already models it that way — while the **desktop promotes it
  to a sidebar tab and compiles the Idea Bank's own inspiration list out**, which is exactly backwards.
- **Strongest alternative:** keep it, and give it the thing that would justify it — a real per-item
  analysis review queue with retry.
- **Tradeoff:** multi-select delete and link capture have to move; the alternative is a feature build.
- **Confidence:** medium-high.
- **Flips it:** wanting that review queue in the beta.

### DEC-08 · The desktop `feed-grid` tab

- **Question:** Does the desktop keep a sidebar tab for the feed grid, or push it from `plan-week`
  like the phone?
- **Recommendation:** demote it. The grid is read-only and single-platform; the desktop shell carries
  eight sidebar destinations against the phone's six, and this is one of the two extras.
- **Strongest alternative:** keep it — desktop planners have the room.
- **Tradeoff:** one extra click on desktop, against one IA instead of two.
- **Confidence:** medium-high.
- **Flips it:** the grid becoming the bulk live-URL entry point.

### DEC-09 · Home's three week views

- **Question:** Do Home's `weekAhead`, `nextWeek` and `weekAtAGlance` cards trim to one?
- **Recommendation:** trim to one. Three renderings of the same seven days that `plan-week` already
  owns, plus `recentlyPosted`, which is `feed-grid` in miniature.
- **Strongest alternative:** keep them and let testers arrange their own Home.
- **Tradeoff:** removes cards a creator may have deliberately ordered.
- **Confidence:** medium — this one is a preference question and I have no usage data.
- **Flips it:** testers arranging a Home that is not a mirror of Plan.

### DEC-10 · Six tabs

- **Question:** Do the six phone tabs stay six?
- **Recommendation:** yes, keep six. `page-purpose.md` §4 checked the set against the PRD and it
  matches one-for-one; the problems are vocabulary, not structure. Apple's guidance is three to five,
  but it is guidance, not a rule, and no lane found an Apple-side consequence. Bring the **desktop**
  from eight to six (DEC-07, DEC-08) so there is one IA.
- **Strongest alternative:** fold `pillars` under `idea-bank` to reach five.
- **Tradeoff:** six icon-only tabs with no labels is a lot to learn on first launch; five would be
  kinder but breaks the PRD's mapping.
- **Confidence:** high on keeping six, high on fixing the desktop.
- **Unblocks:** Task 113. (The VoiceOver container fix ships regardless, in Task 106.)

### DEC-11 · The PRD's vocabulary

- **Question:** May the plan correct `docs/PRD.md`?
- **Recommendation:** yes. The PRD's "Today" ships as Home, its "Agenda" ships as Plan, and the enum
  case for Plan is literally `.today` — three names for two pages, which makes every routing call site
  read backwards. Also correct the navigation list's *Platforms* entry, which has no tab and correctly
  ships as a section inside the post editor. Fold in whatever DEC-06 and DEC-10 decide.
- **Strongest alternative:** rename the shipped pages to match the PRD instead.
- **Tradeoff:** renaming the document is free; renaming the pages changes what testers see.
- **Confidence:** high.
- **Unblocks:** Task 59. (The `AppTab.today` → `.plan` code rename is Task 57 and does not wait.)

### DEC-12 · What the Share Extension is allowed to do

- **Question:** `PRIVACY.md:11` says the Share Extension makes no network request; it makes two, one a
  full AI call. Does the document change, or does the code?
- **Recommendation:** the document. The extension's two calls are what makes a shared link useful
  before the app is ever opened, and its transport validation is genuinely good (HTTPS-only
  canonicalisation, credential-rejection, a 2,048-character cap, traversal-proof filenames).
- **Strongest alternative:** move both calls back into the main app's drain path so the promise
  becomes true — which is the stronger privacy position and is what the architecture document also
  claims today.
- **Tradeoff:** honest documentation now, versus a stricter boundary that costs a round trip and a
  delay before the creator sees anything.
- **Evidence:** `InspirationShareAPI.swift:112` POSTs to `/v1/inspiration/extract`, `:155` to
  `/v1/ai/inspiration/shape`, both authenticated with the shared-keychain installation credential;
  `InspirationShareMediaAnalyzer.swift:23` downloads CDN bytes. `ARCHITECTURE.md:35` separately claims
  the extension "does not link ... AI ... services".
- **Confidence:** high on the facts, medium on which way you want it.
- **Flips it:** wanting to answer "no" to the App Store Connect data-collection question for the
  extension.
- **Unblocks:** Task 95. Task 77 ships the honest document either way.

### DEC-13 · Local Cy for the beta

- **Question:** Does Local Cy ship to testers over cleartext HTTP with mitigations and a disclosure,
  or does it wait for TLS?
- **Recommendation:** ship it with the Task 87 mitigations — bind to the private LAN address instead
  of `0.0.0.0`, reject non-RFC1918 remotes, HMAC each body, and say plainly in Settings > AI that it
  sends your content over your local network in the clear.
- **Strongest alternative:** generate a self-signed certificate at install time and pin its SPKI, and
  do not ship Local Cy until then.
- **Tradeoff:** a real capability now with a disclosed residual risk, versus a multi-day change with
  its own trust and rotation failure modes.
- **Evidence:** `install-local-cy.mjs:63-70` writes `http://<host>.local:49321` plus a 32-byte token;
  `local-cy-http-server.ts:38` binds `0.0.0.0`; the iPhone reaches it through the ATS exception. On a
  café network any device on the same segment can read the content and take the token, and `.local`
  resolution is spoofable. The code comment at `:34-37` already knows.
- **Confidence:** high.
- **Flips it:** a tester intending to use Local Cy on a shared or public network.
- **Unblocks:** Tasks 96 and 102. If it stays cleartext, this becomes RISK-02.

### DEC-14 · The Fastify major upgrade

- **Question:** Do we cross a Fastify major, or stay on patch bumps?
- **Recommendation:** stay on patch bumps. Both **reachable** advisories are closed by patch versions
  reached through Fastify — `fast-uri` ≥ 4.1.2 and `find-my-way` ≥ 9.6.1 — and neither is currently
  exploitable here (the app validates with Zod, not JSON Schema `format: uri`, and Fastify is not
  configured for HTTP/2).
- **Strongest alternative:** take the major now, while there are five testers rather than five hundred.
- **Tradeoff:** a major before beta is a risk you do not need; a major after beta is a risk with users
  attached.
- **Confidence:** high for now.
- **Note:** the finding originally said `pnpm update fastify --latest`, which can cross a major on its
  own. Task 90 pins the patches instead.

### DEC-15 · 26 GB of build output in the iCloud folder

- **Question:** May `ios/build` (26 GB) and `ios/build-device` (285 MB) be deleted?
- **Recommendation:** yes — but confirm first, because a device build lives in `ios/build-device` and
  may be the copy installed on your phone.
- **Tradeoff:** none beyond that one copy; both are untracked and correctly gitignored.
- **Evidence:** the repo is under `~/Documents`, which is iCloud-synced, and the briefs already warn
  that derived data inside the repo breaks signing — which is why every lane built elsewhere.
- **Confidence:** high.
- **Unblocks:** Task 75.

### DEC-16 · `whyItFits`

- **Question:** The server computes a "why this fits you" explanation for every idea direction and the
  app throws it away. Surface it, or leave it?
- **Recommendation:** surface it in `idea-bank`'s direction rows. It is already paid for, already
  decoded (`APIWireModels.swift:194`), and it is the kind of thing that makes a suggestion feel
  addressed to you rather than generated.
- **Strongest alternative:** leave it; it is a feature, and the contract's non-goals include new
  features.
- **Tradeoff:** it is a genuinely new surface, which is scope; it is also two lines of view code.
- **Confidence:** medium — I think it is worth it, but it is a feature and therefore yours.

### DEC-17 · Voice Spark in the background

- **Question:** Should Voice Spark keep recording when the creator leaves the app?
- **Recommendation:** no. Remove `UIBackgroundModes: audio` — nothing in the app plays or records in
  the background today (no `beginBackgroundTask`, no interruption or route-change handling), and
  declaring the mode without using it is a routine App Review question and a common rejection.
- **Strongest alternative:** keep the mode and build the background recorder, with interruption
  handling, before submission.
- **Tradeoff:** a creator who walks away mid-thought loses the recording, against a feature build plus
  an App Review justification.
- **Confidence:** high.
- **Unblocks:** Task 101.

### DEC-18 · The Catalyst Release APNs environment

- **Question:** Does the internal desktop build's Release config declare `development` (matching the
  profile actually in use), or do we get a Mac distribution profile?
- **Recommendation:** set it to `development`. Catalyst is internal per ADR 0012; the Release config
  currently asks for `production` while inheriting automatic signing with no distribution profile, so
  a Release archive of the desktop app cannot sign.
- **Strongest alternative:** add a Mac distribution profile, if you want a signed internal archive.
- **Tradeoff:** none beyond the archive you cannot currently make.
- **Confidence:** high.

### DEC-19 · One chrome contract for the post editor

- **Question:** `ResumablePostEditorView` is constructed at fifteen sites, each configuring its own
  chrome — so "the post editor" looks and closes differently depending on which door you used. Does it
  get one chrome contract?
- **Recommendation:** yes — route every site through `PostOutputDetailView` and give the editor two
  named modes rather than fifteen ad-hoc ones. The MCP "edit before approval" context genuinely needs
  a different close semantic; nothing else does.
- **Strongest alternative:** leave it; each site knows what it needs.
- **Tradeoff:** one of the fifteen contexts loses a bespoke affordance, and this is a larger change
  than anything else in B3.
- **Confidence:** medium-high.
- **Note:** the smallest piece of this — the feed grid bypassing the router entirely
  (`SocialGridView.swift:928`), so a scheduled output with a developing brief opens a different page
  from the grid than from every other list — is fixed in Task 58 regardless.

---

## 3. Security risk acceptances

Each needs your explicit yes; the contract reserves accepting any security risk for you.

### RISK-01 · Three unreachable MCP-side advisories

- **Accept:** `hono`, `@hono/node-server` and `ip-address` advisories in the MCP bridge's tree.
- **Why it is acceptable:** they come only through `@modelcontextprotocol/sdk`'s HTTP transport and
  `express-rate-limit`; the bridge runs **stdio-only** (`mcp/src/index.ts`) and never starts those
  servers, so no code path reaches them at runtime.
- **Alternative:** force an SDK bump.
- **Tradeoff:** an SDK bump on the bridge for advisories that cannot fire.
- **Confidence:** high. **Flips it:** the bridge ever gaining an HTTP transport.

### RISK-02 · Local Cy's cleartext LAN transport (only if DEC-13 ships it)

- **Accept:** after Task 87's mitigations, the request body is still readable by anything on the same
  L2 segment that the Mac's private address is on.
- **Why it is acceptable:** the mitigations remove the two exploitable paths — a listener elsewhere on
  the network and replay — and the surface is opt-in, disclosed in Settings > AI and in `PRIVACY.md`.
- **Alternative:** DEC-13's TLS route, which removes the residual entirely.
- **Confidence:** medium. **Flips it:** any tester who will use Local Cy on a network they do not own.

### RISK-03 · The bridge push capability stays in an iCloud-synced folder

- **Accept:** after Task 78 moves it out of `snapshot.json` into a `0600` file and makes it revocable,
  the capability still lives in a folder iCloud syncs and other processes running as you can read.
- **Why it is acceptable:** it is revocable, notification-only (it cannot read or write creator data),
  and Task 83 caps what it can do to 20 pushes per 10 minutes with a bounded, prefixed subject.
- **Alternative:** move the capability into the Keychain and have the bridge fetch it — which breaks
  the file-exchange model the bridge is built on.
- **Confidence:** high. **Flips it:** the capability ever gaining a read or write scope.

### RISK-04 · `trustProxy: 1` assumes one Railway hop

- **Accept:** shipping `trustProxy: 1` before the production probe reads Railway's real
  `X-Forwarded-For` hop count.
- **Why it matters:** if Railway's edge adds **two** entries rather than one, every request collapses
  into a single rate-limit bucket — worse than today's spoofable key.
- **Alternative:** hold Task 80 until AUTH-02's P1 reads the count (one request). **This is what I
  recommend** — the probe's first phase is two requests and costs nothing.
- **Confidence:** high that it must be read; the risk only exists if you ship before reading.

### RISK-05 · `PendingWeekProposal.appliedAt` stays in the schema

- **Accept:** a stored SwiftData column that is never written and never read stays in the
  CloudKit-mirrored schema through the beta.
- **Why it is acceptable:** dropping a stored property from a mirrored `@Model` is a schema change and
  `AgentCySchemaV1` is still at version 1.0.0 — a migration before beta costs more than the column.
- **Alternative:** wire it into the proposal-apply path, which it was clearly meant for.
- **Confidence:** high. **Flips it:** any other reason to cut a V2 schema before beta, in which case
  it goes along for free.

---

## 4. Authorizations

### AUTH-01 · Profiling on your iPhone (gate G-device)

- **Unlocks:** the contract's own success criterion — "no hang above Instruments' hang threshold on
  Chey's iPhone in the core journeys" — which is **currently unmeasurable**. `xctrace record` was run
  twice on this Mac, wrote 52 KB, and hung both times; there is no top-app-frames table in this pass.
  Every heaviness number we have comes from the app's own os_log milestones and from frame counting on
  a simulator with a 34-record fixture, so every figure is a floor.
- **What it settles:** L2H-01 … L2H-06 at real data volume; L2M-01/02 in battery and thermal terms;
  the tab-switch and swipe-to-delete *feel*; `CyThinkingMark` at 120 Hz, whose timeline has no
  minimum interval so its ProMotion cost is unmeasured; and **L2H-07, which re-escalates from minor to
  major on this gate** and brings a deferred task back with it.
- **Ask:** one session with the phone connected, before B2 and again after — Tasks 42 and 40.

### AUTH-02 · The production probe (gate G-prod)

- **Unlocks:** live confirmation of five security findings against the deployed Railway service, none
  of which was touched this pass — correctly; `probe-plan.md:3` records that no request has been sent.
- **Budget: 58 HTTP requests**, across twelve phases. **Nothing in the plan reaches Anthropic, so
  incremental provider spend is zero.** The only durable changes are one redeemed invite and ~201
  content-free telemetry rows, both undone by phase P12's erase.
- **Needs from you:** confirmation that you own `agentcy-production.up.railway.app`, a named
  30-minute window, one disposable invite code, and the real ceilings read out of Railway first.
- **One addition to phase P1:** read Railway's actual `X-Forwarded-For` hop count, so RISK-04 is
  settled rather than assumed.

### AUTH-03 · `brew install peripheryapp/periphery/periphery`

- **Unlocks:** B4. That batch deletes ~3,500 lines, and a false positive is a build break. L4's census
  is deliberately conservative — occurrences in comments and string literals count as references — but
  a second, independent tool before deleting is cheap insurance. Task 60 gates Tasks 61–68 on it.

### AUTH-04 · `corepack enable && corepack prepare pnpm@11.7.0 --activate`

- **Unlocks:** `scripts/verify.sh` running at all on this Mac. Neither `pnpm` nor `corepack` is
  installed, so the script dies at line 13 — and because the typography gate runs at line 11 and
  always returned "passed", `verify.sh` currently reports success for eleven lines and then stops.
  Task 73.

---

## 5. Apple owner-only steps, in order

These cannot be done from the repo, and later ones depend on earlier ones.

| # | Step | Note |
|---|---|---|
| **O-1** | Apple Account and agreements | Add the account owning team `2S27MSM8G8` in Xcode; accept pending Paid Applications and Program License agreements. **Nothing below can be uploaded until agreements are current.** |
| **O-2** | App record and identifiers | Create `com.agentcy.app`; confirm the widget, share extension, CloudKit container, App Group and keychain group all sit on the same team. |
| **O-3** | Sign in with Apple key | Create the key and client secret; put `APPLE_TEAM_ID`, `APPLE_KEY_ID` and the `.p8` into Railway. **Hard blocker on code: APPLE-01 / Task 110 cannot be fixed without it.** |
| **O-4** | APNs production key | So the `APS_ENVIRONMENT: production` change in Task 100 has something to authenticate against. |
| **O-5** | App Privacy answers | Complete the questionnaire from the **corrected** `PRIVACY.md` (Task 77), then confirm it matches the manifest from Task 99. |
| **O-6** | Subscription decision | Promotional-only first cohort → create no products and say so in review notes. Paid pilot → create the subscription group, product, price, display name and review screenshot, and do not submit until the RevenueCat client flow ships. **Hard blocker on code: APPLE-03 / Task 111's shape depends on this.** |
| **O-7** | Age rating | Two questions need deliberate answers: the app generates AI content on request, and stores creator content. There is no "18+" claim anywhere in the codebase — do not select one unless you intend an adult rating. |
| **O-8** | Privacy policy and support URLs | **No repo artefact exists at all.** `docs/PRIVACY.md` is not a published page, and there is no support address anywhere in the app. Both are required fields. |
| **O-9** | Export compliance | Already substantiated: `ITSAppUsesNonExemptEncryption: false` is correct — HTTPS, `CryptoKit.SHA256`, `SecRandomCopyBytes` and the Keychain only, verified by grep. Confirm once; it carries forward. |
| **O-10** | CloudKit production schema | Promote the exercised development schema to Production **before any external tester gets a build** — external TestFlight runs against the production container. |
| **O-11** | Review access | App Review hits the invitation gate on first launch, so guideline 2.1's demo-account requirement applies: supply an unredeemed invite code, a note that "I have an invitation code" is the second button, and a test Apple Account. Confirm the proxy is up and the code is live at submission. |
| **O-12** | Screenshots and metadata | 6.9" iPhone only (portrait, iPhone-only). The description must disclose AI-generated content, matching `PRIVACY.md`. |
| **O-13** | TestFlight setup | Internal group first, then the external five. **The deployment target is iOS 26.0** — every tester needs an iOS 26 device or they cannot install, and TestFlight will not warn them. Say so in the invitation. |
| **O-14** | Build number | `CURRENT_PROJECT_VERSION` is 229; history is monotonic. Increment before each upload. (`TESTFLIGHT.md`'s stale `BUILD_NUMBER=136` example is fixed in Task 109.) |

Also owner-supplied: **app icon dark and tinted artwork** (Task 112) — a code change waiting on art.

---

## 6. The ten I would fix first

Ordered by what a beta tester or App Review meets first, weighted by how cheaply it can be made right.

1. **APPLE-04 + APPLE-05 — two missing required-reason API declarations stop the *upload*.**
   ITMS-91053 fires before review; nothing else in B6 can be tested until they land, and both are a
   dozen lines of XML. Highest ratio of consequence to effort in the pass. *(I put these first, ahead
   of the privacy documents: they are the gate everything else queues behind.)*
2. **L5-02 + L5-03 + L5-04 — three published privacy statements are false.** The Share Extension makes
   two network calls it is documented not to make (one a full AI call), the proxy fetches three
   Instagram URLs per share while `PRIVACY.md` says it fetches none, and a live bearer token is
   written into iCloud Drive against a documented "no credentials" promise. This is what five named
   testers are asked to trust and what your App Store privacy answers are derived from.
3. **L3-01 + L3-02 — a modal opens itself over the creator's work, replaces Cy, and cannot be closed
   on iPhone.** A four-second poller raises it; the queue takes the whole conversation *and* the
   composer; the close control sits inside `#if targetEnvironment(macCatalyst)`. The fix for the
   second half already shipped — to the internal form factor only.
4. **L3-03 — nothing in the app survives being backgrounded.** There is no `.background` scene-phase
   handler anywhere; four draft-owning surfaces flush only in `onDisappear`, which backgrounding and
   termination do not call. This is data loss, not polish, and it is the contract's own criterion.
5. **L2M-01 + L2H-04 — Home and Cy never stop rendering.** 300 and 599 frames in ten untouched
   seconds, against 1 frame on every other tab, because a decorative asterisk animates a shadow radius
   forever. This is "the app feels heavy" with a reproducible number attached, and the fix is one
   component that already has a static branch.
6. **L1-04 + L1-05 + L1-10 + G-5 — four named non-negotiables broken on the first screens.** Six
   solid pure-white pucks, nine solid accent fills, eleven accent glows, capsule buttons on onboarding
   and the walkthrough — on the paywall, the first-run tour, day agenda and weekly focus. Three of
   these contradict dated decisions in your own design document.
7. **L5-01 — the app POSTs your full AI payload and a bearer token to any URL in a file.**
   `connectionConfig()` validates a schema version and a token length and nothing else. The file lives
   in a folder writable by anything on your Mac and by any app you grant it in Files. One
   scheme-and-host check closes it.
8. **APPLE-02 — the shipping Release config declares a development APNs environment.** One line.
   Left as is, every "Claude or Codex sent a proposal" notification silently fails for every tester —
   and the Catalyst target already gets it right in the same file.
9. **L2H-01 + L2H-02 — the shell builds all six tab roots on every launch, each running whole-table
   queries.** 1.6–2.5 s between "the model is ready" and "the first screen exists" on a cold launch,
   ~510 ms per tab switch, and `@Query(filter` returns **zero** matches across 251 declarations. This
   is the structural half of "heavy", and it is the one whose cost grows with your own data.
10. **L4-11 — the typography gate prints "passed" and exits 0 when its tool is missing.** It is
    masking eight live violations right now, CI runs neither it nor `verify.sh`, and `verify.sh`
    cannot execute on this Mac at all. Last on the list because nothing breaks today — **first in the
    task order**, because every consistency fix above it can regress silently until it is repaired.

*My order differs from the skeptic's only at the top: the two privacy-manifest lines stop the upload
before anything else can be tested, so they precede the privacy documents rather than follow them.*
