# Process: Apple readiness

**Draft.** Written by job M from what lane L6 had to check. Job F finalizes it after the batches ship.

## When it runs

- **Before every TestFlight upload**, in full. It is short, and the two items that matter most stop the
  *upload*, not the review — running it late costs a whole cycle.
- **On any diff touching** `ios/project.yml`, an `Info.plist`, an `*.entitlements`, a
  `PrivacyInfo.xcprivacy`, `ios/ExportOptions-TestFlight.plist`, `scripts/archive_testflight.sh`, the
  account or subscription paths, any permission request, or `PRIVACY.md` (the App Privacy answers are
  derived from it).

## Who runs it, and on what

A **fresh-context subagent** for the repo half. The App Store Connect half is owner-only; the job there
is to hand the owner an ordered list, not to pretend it can be automated. Inputs:

- `ios/project.yml`, the generated Info.plists, every entitlements file, all three
  `PrivacyInfo.xcprivacy`, `ios/ExportOptions-TestFlight.plist`, `scripts/archive_testflight.sh`,
  `docs/TESTFLIGHT.md`, `docs/PRIVACY.md`, `docs/adr/0012-catalyst-maintained-internal-scope.md`.
- The current App Review Guidelines, **fetched at run time and quoted by number** — never from memory.
- A simulator, for the first-launch captures.

## Checklist — A gates everything else
### A. Upload validations
1. **Every required-reason API a target's sources call is declared in that target's privacy manifest.**
   Grep per target for `systemUptime`, `UserDefaults`, `stat`/file-timestamp, disk-space and
   active-keyboard APIs, and diff against the manifest. *(APPLE-04: six live `systemUptime` calls,
   `NSPrivacyAccessedAPICategorySystemBootTime` undeclared. APPLE-05 / L5-15: the share extension
   declared `<array/>` while constructing `UserDefaults(suiteName:)` twice — and the widget extension
   declared the identical pattern correctly, in the same archive.)* **ITMS-91053 stops the upload
   before review. Both are a dozen lines of XML.**
2. **`NSPrivacyCollectedDataTypes` exists in every manifest and matches `PRIVACY.md`.** *(APPLE-09: the
   app has no such key at all — not even an empty array — so there is nothing for App Store Connect to
   diff the nutrition labels against.)*

### B. Signing and capabilities
3. Release configs resolve a distribution profile, and `APS_ENVIRONMENT` matches it. *(APPLE-02: the
   iPhone Release config declared `development` while the Catalyst target in the same file declared
   `production`; `archive_testflight.sh` overrides `CODE_SIGN_STYLE` but not `APS_ENVIRONMENT`, so the
   archive carried it, and every bridge push would silently fail for every tester. APPLE-11, APPLE-22:
   the mirror-image problems on the other configs.)*
4. **Every declared capability is used.** For each `UIBackgroundModes` entry, ATS exception and
   usage-description string: find the code, or delete the declaration. *(APPLE-06: `audio` declared
   with no background audio anywhere — no `beginBackgroundTask`, no interruption handling; guideline
   2.5.4. APPLE-07: an ATS local-networking exception and a Local Network purpose string with no
   `NWConnection`/`NWBrowser`/`NetService` and no Bonjour key — iOS could raise a prompt the creator
   has no reason to see.)* And **every string describes the access actually requested** *(APPLE-10:
   full calendar access — correctly, the picker needs it — behind a string that only mentions adding
   events).*

### C. Account and commerce — the standing rejection reasons
5. **Sign in with Apple + account deletion ⇒ token revocation.** Grep the server for
   `appleid.apple.com/auth/revoke`. *(APPLE-01: `grep -rni "revoke" server/src/` returns nothing; the
   client collects `authorizationCode`, the server declares the field and never exchanges it.
   Guideline 5.1.1(v), commonly enforced.)*
6. **Account deletion is findable and unambiguously labelled.** *(APPLE-08: the control labelled
   "Delete account" deletes one workspace and hides in an overflow menu that only appears with more
   than one workspace; the one that deletes the account is called "Erase all data".)*
7. **Anything the app advertises can be bought, and nothing expires access the server granted.**
   *(APPLE-03: `UnavailableLiveSubscriptionService` advertises "$8.99 / 14-day trial", throws on both
   `startTrial` and `restore`, and writes `.expired` — removing creation and Cy — for any state it
   cannot verify locally. Guidelines 3.1.1 and 2.1. `.comped` is preserved; `.trial` and `.paid` are
   not.)*
8. **Review can get in.** If first launch is gated, the review notes carry a working credential and the
   path to it. *(O-11: App Review lands on the invitation gate.)*

### D. First impressions and HIG-shaped quality
9. **Capture the first screen on a clean install: light, dark, and dark reached by switching appearance
   at runtime.** *(APPLE-12: `SignInWithAppleButton`'s style is fixed when the representable is made, so
   a runtime appearance change leaves a black button on a near-black card, invisible except at its edge
   — two cold-start captures would have missed it.)*
10. The first screen is written for someone new, and no error appears before the creator has done
    anything. *(APPLE-15: it leads with "Pick up where you left off" for five invited creators, none of
    whom has a workspace. APPLE-16: a Keychain read failure renders a red "The connection couldn't be
    completed" under the sign-in card.)*
11. Chrome floating over arbitrary scrolling content uses a material that adapts to it. *(APPLE-13:
    every glass surface is `.clear`, none `.regular`; page content reads *through* the tab bar on the
    default first screen.)*
12. Dynamic Type: no fixed font size, `relativeTo:` on every custom font, **in every shipped target**.
    *(APPLE-20 found one Catalyst site and concluded the rest was "in good shape" from a grep over the
    app target alone; **G-3** found the 946-line share sheet has six custom fonts with no `relativeTo:`
    and four raw system fonts on top.)*
13. VoiceOver: containers are containers, not loose buttons. *(APPLE-14: six icon-only tabs, each
    correctly labelled, in an `HStack` with no `.accessibilityElement(children: .contain)`.)*
14. Reduce Motion is re-evaluated, not checked once *(APPLE-17: two `repeatForever` loops guard on
    `reduceMotion` inside `.onAppear`, so turning it on mid-session never cancels them)*; and the app
    icon is 1024×1024, sRGB, **no alpha**, with dark and tinted appearance entries *(APPLE-21: the file
    is submission-valid; only the variants are missing)*.

### E. Housekeeping
16. Export compliance still correct — re-grep for `AES|ChaChaPoly|SealedBox|CCCrypt|SymmetricKey`
    before asserting `ITSAppUsesNonExemptEncryption: false` *(O-9; substantiated, not asserted)*; build
    number monotonic and incremented; `TESTFLIGHT.md`'s examples not stale.
17. Deployment target versus tester devices — **iOS 26.0**, and TestFlight will not tell a tester on
    iOS 25 why the install failed. Say it in the invitation. *(O-13.)*

## Evidence required per finding

```
### <one-sentence defect>
- Where: <file:line>, or <page slug + form factor + appearance>
- Evidence: <verbatim excerpt, plist key, or screenshot path under docs/refinement/evidence/apple/>
- Guideline: <number, quoted from the guidelines fetched this run> — or "no Apple constraint"
- Severity: blocker (stops upload or review) | major (a reviewer will ask) | minor
- Fix: <concrete change>  ·  Owner: repo | App Store Connect (O-n)
```

Two rules the pre-beta pass got right and this process keeps:

- **Say "no Apple constraint" out loud when that is the answer.** APPLE-18's whole value was
  establishing that Apple has no opinion between a 44 pt and a 48 pt close control, so the design lane
  could decide freely. A pass that only reports problems cannot do that.
- **Scope a finding to what you observed.** APPLE-16's trigger was an entitlement-free simulator build
  — a build artifact — and the lane said so and rested the defect on the code shape instead. Any
  finding observed on a build signed `CODE_SIGNING_ALLOWED=NO` carries that caveat, or is not a
  finding.

## Fix, don't note
**Threshold: any `ios/project.yml`, Info.plist, entitlements or privacy-manifest edit, and any copy
change — all under ~20 lines — is made in the pass and reported as fixed.** These are the cheapest
fixes in the program and the ones with the highest consequence; scheduling them is how a Release config
ends up declaring a development APNs environment. Escalate rather than fix:

- anything needing an App Store Connect action or a key only the owner can create (O-3's `.p8`, O-4's
  APNs key, O-5's privacy answers, O-6's subscription products, O-8's published policy URL);
- anything needing artwork;
- a **feature** decision hiding inside a capability (should Voice Spark record in the background? if
  yes, the `audio` mode stays and needs interruption handling first);
- the tab count, the palette, and anything else the contract reserves.

## Output format
```
## Apple readiness — <build or task> — <date>
Guidelines fetched: <date>   Archive validated: yes/no
Upload blockers (A): N   <- if non-zero, stop; nothing else is testable
Review blockers (B–C): N   ·   Quality items (D): N
Owner steps outstanding: O-n, O-n, …  (in dependency order, with what each blocks)

<findings, in the block format above>
## Checked and clear   <one line each, with the excerpt or grep that proves it>
```

The **owner-step list is the deliverable**, more than the findings are: ordered, with dependencies
named (APPLE-01 blocked on O-3, APPLE-03 on O-6, APPLE-09 paired with O-5, APPLE-02 with O-4), and with
the ones that have no repo artefact at all — a published privacy policy URL, a support address — called
out as such.
