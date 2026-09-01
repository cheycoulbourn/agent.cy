# L6 · Apple readiness findings (batch B6)

Lane L6. Written against `docs/refinement/00-contract.md` and `docs/refinement/briefs/L6-apple-readiness.md`.
Shipping target: iPhone. Mac Catalyst is internal per ADR 0012, so Catalyst appears here only where an
internal build would embarrass.

## How this pass was run

- Read `ios/project.yml`, every Info.plist, every entitlements file, all three `PrivacyInfo.xcprivacy`
  files, `ios/ExportOptions-TestFlight.plist`, `scripts/archive_testflight.sh`, `docs/TESTFLIGHT.md`,
  `docs/PRIVACY.md`, and the account, subscription, permission, and privacy-deletion code paths in
  `ios/AgentCy/` plus `server/src/`.
- Fetched the current App Review Guidelines (https://developer.apple.com/app-store/review/guidelines/)
  on 2026-09-01 and quote guideline numbers from that fetch.
- The HIG pages (navigation and modality, sheets, buttons, accessibility, materials) render client-side
  and returned only their titles to WebFetch. Every HIG-shaped finding below is therefore carried by a
  screenshot I captured or a `file:line` excerpt, never by a citation I could not verify.
- Runtime evidence: `agent.cy.app` (Debug simulator build from the baseline run) on **iPhone 17 Pro**,
  iOS 26.5, light and dark, screenshots under `docs/refinement/evidence/apple/`.
- `docs/refinement/01-page-inventory.md` did not exist when this lane started, so most findings were
  written against view types and files. It landed (commit `430e83b`) before I finished, so the
  surface-shaped findings below were reconciled to its slugs, and APPLE-18 was cut back to defer to it.

**Caveat that affects one finding only.** The baseline simulator app is signed with no entitlements
(`codesign -d --entitlements` returns an empty set), so App Group and Keychain access fail inside the
simulator (`container_create_or_lookup_app_group_path_by_app_group_identifier: client is not entitled`,
observed twice at launch). That is a build artifact, not a shipping defect, and APPLE-16 is scoped
accordingly. No other finding depends on it.

---

## 1. Rejection risks and blockers

### APPLE-01 Deleting an agent.cy account never revokes the Sign in with Apple token
- Where: `server/src/app.ts:431` (`/v1/privacy/delete`), `server/src/apple-identity.ts:8`
- Evidence: the deletion handler runs `repository.eraseInstallation(...)`, clears the idempotency cache,
  and returns a retention receipt. Nothing in `server/src/` calls `https://appleid.apple.com/auth/revoke`
  — `grep -rni "revoke" server/src/` returns no match, and `grep -rn "client_secret\|auth/token" server/src/`
  returns nothing. The client collects `credential.authorizationCode`
  (`ios/AgentCy/Views/Account/AppleAccountAccessView.swift:585-597`) and ships it to the proxy, but the
  only server-side mention is the type declaration `readonly authorizationCode: string;` — it is never
  exchanged or stored.
- Guideline: 5.1.1(v). Apple requires apps that offer Sign in with Apple to call the token revocation
  endpoint when the account is deleted. This is a standing, commonly enforced rejection reason.
- Severity: blocker
- Fix: on `/v1/privacy/delete`, exchange the stored Apple `authorizationCode` at
  `https://appleid.apple.com/auth/token` for a refresh token, then `POST /auth/revoke` with the app's
  Sign in with Apple client secret before erasing the installation. That means persisting the
  authorization code (or its refresh token) at redemption time in `apple-identity.ts`, and adding
  `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and the `.p8` private key to the Railway configuration. Revoke
  failure must not block local erasure — log it content-free and retry.
- Batch: B6 (code, server) — depends on owner step O-3
- Status: open

### APPLE-02 The shipping iPhone Release config declares a development APNs environment
- Where: `ios/project.yml:57-60`
- Evidence:
  ```
  57          Release:
  58            CODE_SIGN_STYLE: Manual
  59            PROVISIONING_PROFILE_SPECIFIER: AgentCy Development 2026
  60            APS_ENVIRONMENT: development
  ```
  which flows into `aps-environment: "$(APS_ENVIRONMENT)"` (`ios/project.yml:108`,
  `ios/AgentCy/Support/AgentCy.entitlements`). The Mac Catalyst target gets this right in the same
  file — `ios/project.yml:141-142` reads `Release: / APS_ENVIRONMENT: production` — which is what makes
  the iPhone value read as an oversight rather than a choice. `scripts/archive_testflight.sh:27-32`
  overrides `CODE_SIGN_STYLE=Automatic` but does **not** override `APS_ENVIRONMENT`, so the archive
  carries `development`.
- Guideline: 2.1 (app completeness — a shipped feature that does not work). An App Store distribution
  profile does not carry the development aps-environment, so the export either fails signing or ships a
  build whose device tokens point at the APNs sandbox. The MCP bridge push path
  (`ios/AgentCy/App/AgentCyApplicationDelegate.swift:141-175`) then registers tokens that production
  APNs will reject, so every "Claude or Codex sent a proposal" notification silently fails for testers.
- Severity: blocker
- Fix: set `APS_ENVIRONMENT: production` in the `AgentCy` Release config and drop
  `PROVISIONING_PROFILE_SPECIFIER` / `CODE_SIGN_STYLE: Manual` from that config so the archive resolves
  an App Store profile. Same edit for `AgentCyWidgets` Release (`ios/project.yml:222-224`). Keep Debug
  on `development`.
- Batch: B6 (code)
- Status: open

### APPLE-03 A shipped build has no way to buy or restore anything, and actively expires paid access
- Where: `ios/AgentCy/Services/SubscriptionService.swift:33-61`
- Evidence:
  ```swift
  struct UnavailableLiveSubscriptionService: SubscriptionServicing {
      let offering = SubscriptionOffering(monthlyPrice: "$8.99", trialDays: 14, isPromotionalCohort: false)
      let supportsPurchases = false
      ...
      case .trial, .paid:
          isVerifiedLocally = false
      }
      guard !isVerifiedLocally, state.access != .expired else { return }
      state.access = .expired
  ```
  `startTrial` and `restore` both `throw SubscriptionServiceError.appStoreVerificationUnavailable`.
  `SubscriptionServiceFactory.runtime` returns this service for every non-DEBUG build
  (`SubscriptionService.swift:65-73`). `SubscriptionAccess.canCreate` and `.canUseCy` are both
  `self != .expired` (`ios/AgentCy/Models/DomainTypes.swift:1339-1340`), so an expired creator loses
  creation and Cy entirely. The Access page suppresses the purchase button and prints
  "Paid plans arrive in an upcoming release. Your invite covers access until then."
  (`ios/AgentCy/Views/Settings/SettingsSubpages.swift:2159-2163`). The server side is already built —
  `server/src/app.ts:470` handles the RevenueCat webhook — only the client is missing.
- Guidelines: 3.1.1 (unlocking functionality must use in-app purchase; the invite code is currently the
  only unlock mechanism, which reads as a license key) and 2.1 (advertised subscription with no
  purchase path). `docs/TESTFLIGHT.md` already states "The current iOS app does not contain the
  production RevenueCat SDK purchase and restore flow."
- Severity: blocker for an App Store submission; major for the promotional TestFlight cohort, where
  every tester should land on `.comped` and never see `.expired`
- Fix: land the RevenueCat client integration (offerings, purchase, restore, `supportsPurchases = true`)
  before any paid submission. Until then, make the promotional path safe: `UnavailableLiveSubscriptionService.refresh`
  must never downgrade a server-granted state it cannot verify — return early instead of writing
  `.expired`, and let `LifecycleService` own expiry from the server-supplied `trialEnd`.
- Batch: B6 (code) + owner step O-6
- Status: open

### APPLE-04 The privacy manifest omits the System Boot Time required-reason API
- Where: `ios/AgentCy/Support/PrivacyInfo.xcprivacy`
- Evidence: the manifest declares exactly one category:
  ```xml
  <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
  <array><string>CA92.1</string><string>1C8F.1</string></array>
  ```
  but the app calls `ProcessInfo.processInfo.systemUptime` in six places —
  `ios/AgentCy/App/RootView.swift:56`, `RootView.swift:63`,
  `ios/AgentCy/ViewModels/AppModel.swift:106`, `:118`, `:145`, `:164` — which is on Apple's
  required-reason list under `NSPrivacyAccessedAPICategorySystemBootTime`. Those calls are live in the
  shipped binary (the `RootLaunch` milestones they emit are visible in the launch log I captured:
  `[com.agentcy.app:RootLaunch] milestone=credential_status_resolved elapsed_ms=411.2`).
- Guideline: this is an App Store Connect upload validation (ITMS-91053, "Missing API declaration"),
  so it stops the build before review rather than during it.
- Severity: blocker
- Fix: add to `ios/AgentCy/Support/PrivacyInfo.xcprivacy`:
  ```xml
  <dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array><string>35F9.1</string></array>
  </dict>
  ```
  35F9.1 is "measure the amount of time that has elapsed between events that occurred within the app",
  which is exactly what `RootLaunchDiagnostics` does.
- Batch: B6 (code)
- Status: open

### APPLE-05 The Share Extension's privacy manifest declares no accessed APIs but reads App Group defaults
- Where: `ios/AgentCyInspirationShare/PrivacyInfo.xcprivacy`
- Evidence: the manifest is
  ```xml
  <key>NSPrivacyAccessedAPITypes</key>
  <array/>
  ```
  while the extension constructs `UserDefaults(suiteName:)` at
  `ios/AgentCyInspirationShare/ShareViewController.swift:275` and `:338`, and pulls in
  `ios/AgentCyShared/InspirationShareTransport.swift:615-621`, which reads and writes the same suite.
  `AgentCyWidgets` declares `1C8F.1` for the identical pattern
  (`ios/AgentCyWidgets/PrivacyInfo.xcprivacy`), so the omission is inconsistent within the same archive.
- Guideline: ITMS-91053 upload validation, same as APPLE-04.
- Severity: blocker
- Fix: replace the empty array with the UserDefaults category and reason `1C8F.1` (app group container
  access), matching the widget manifest.
- Batch: B6 (code)
- Status: open

### APPLE-06 `UIBackgroundModes: audio` is declared but nothing plays or records in the background
- Where: `ios/project.yml:85-87`, `ios/AgentCy/Support/Info.plist`
- Evidence: the only audio session work in the app is foreground-scoped.
  `ios/AgentCy/Views/Capture/VoiceSparkView.swift:47-52` sets `.record` and calls `setActive(true)`,
  and `:165` deactivates on stop; playback sites
  (`VoiceSparkView.swift:230-236`, `ios/AgentCy/Views/Shared/VoiceRecordingDetailPage.swift:141-149`,
  `ios/AgentCy/Views/Brief/PostMediaViews.swift:91-99`) each set `.playback` then deactivate.
  `grep -rn "beginBackgroundTask" ios/AgentCy` returns nothing, and there is no interruption or
  route-change handling that a background-audio app would need. The whole recorder is compiled out on
  Catalyst (`VoiceSparkView.swift:1`, `#if !targetEnvironment(macCatalyst)`), and the Catalyst target
  correctly declares only `remote-notification` (`ios/project.yml:170-171`).
- Guideline: 2.5.4 — "Multitasking apps may only use background services for their intended purposes."
  Declaring the audio background mode without background audio is a routine reviewer question and a
  common rejection.
- Severity: major (blocker if review asks and there is no answer)
- Fix: remove `audio` from `UIBackgroundModes` at `ios/project.yml:86`, leaving `remote-notification`
  (which private CloudKit mirroring genuinely needs). If Voice Spark should keep recording when the
  creator leaves the app, that is a feature decision for Chey and needs interruption handling before
  the mode can be justified.
- Batch: B6 (code)
- Status: open

### APPLE-07 The iPhone build ships an ATS exception and a Local Network purpose string for a capability it never uses
- Where: `ios/project.yml:88-90`
- Evidence:
  ```
  88        NSAppTransportSecurity:
  89          NSAllowsLocalNetworking: true
  90        NSLocalNetworkUsageDescription: "Allow agent.cy to reach Local Cy on your Mac while both devices are on the same network."
  ```
  No code performs local-network discovery or connection: `grep -rn "NWConnection\|NWBrowser\|NWListener\|NetService" ios/`
  returns nothing, there is no `NSBonjourServices` key, and the only non-HTTPS URL in the app is
  `URL(string: "http://127.0.0.1:3000")` at `ios/AgentCy/Services/APIClient.swift:137`, which is inside
  `#if DEBUG` and is loopback (loopback needs no local-network permission). Local Cy does not use the
  network at all — it exchanges files through an iCloud Drive folder, as the app's own copy says:
  "Claude or Codex reads a limited snapshot from the iCloud Drive folder you chose"
  (`ios/AgentCy/Views/Settings/MCPBridgeSettingsView.swift:157`).
- Guideline: 2.5.1 (use APIs as intended) and 5.1.1 (request only the data and access you need). An
  unjustified ATS exception invites a reviewer request for justification, and the purpose string means
  iOS can raise a local-network prompt the creator has no reason to see.
- Severity: major
- Fix: delete lines 88-90 from the `AgentCy` target in `ios/project.yml`. Delete the equivalent
  `NSAllowsLocalNetworking` / `NSLocalNetworkUsageDescription` from the Catalyst target
  (`ios/project.yml:172-174`) in the same pass; it has the same non-use. Also drop
  `NSSpeechRecognitionUsageDescription` from the Catalyst target (`ios/project.yml:176`) — speech
  recognition only runs in the iOS-only Voice Spark and the iOS-only Share Extension.
- Batch: B6 (code)
- Status: open

### APPLE-08 The real account-deletion control is called "Erase all data"; a different control that deletes only a workspace is called "Delete account"
- Where: `ios/AgentCy/Views/Settings/SettingsSubpages.swift:438` and `:2263-2312`
- Evidence: the control literally labelled **"Delete account"** deletes one content workspace, is inside
  an overflow menu, and only exists when the creator has more than one workspace:
  ```swift
  if activeWorkspaces.count > 1 {
      Menu {
          Button(role: .destructive) { pendingDeletion = ... } label: {
              AgentIconLabel(title: "Delete account", icon: .trash)
  ```
  (`SettingsSubpages.swift:430-438`). Its confirmation says "This permanently deletes its posts, pillars,
  ideas, tasks, weekly focus, and Cy conversations" (`:487`) — content only, nothing about the agent.cy
  account. The control that actually deletes the account is `EraseDataSettingsView`, kicker "Your data",
  title **"Erase all data"** (`:2266-2270`), which is the only path to
  `appModel.eraseAll(context:)` -> `PrivacyEraseCoordinator` -> `POST /v1/privacy/delete`
  (`ios/AgentCy/Services/PrivacyDeletionService.swift:210`).
- Guideline: 5.1.1(v) — "If your app supports account creation, you must also offer account deletion
  within the app." Apple's review expectation is that the option is easy to find and unambiguously
  labelled. Two differently-scoped destructive actions, one of them mislabelled, is exactly the pattern
  that draws a rejection, and the correctly-scoped one is not named for what it does.
- Severity: major
- Fix: rename the workspace control to "Delete workspace" (and its dialog to match — it is a workspace,
  not an account), then surface account deletion under its own name: an explicit "Delete account" row
  in Settings that routes to `EraseDataSettingsView`, whose title becomes "Delete account and erase data".
  Shared copy change; sites are `SettingsSubpages.swift:438`, `:478-487`, `:2266-2270`, `:2312-2318`,
  and the Settings index entry in `ios/AgentCy/Views/Settings/SettingsView.swift`.
- Batch: B6 (code)
- Status: open

### APPLE-09 The main privacy manifest declares no collected data types, so nutrition labels cannot be checked against PRIVACY.md
- Where: `ios/AgentCy/Support/PrivacyInfo.xcprivacy`
- Evidence: the file contains `NSPrivacyAccessedAPITypes` and `NSPrivacyTracking` but no
  `NSPrivacyCollectedDataTypes` key at all — not even an empty array. The Share Extension manifest does
  declare `<key>NSPrivacyCollectedDataTypes</key><array/>`, so the app is the odd one out.
  `docs/PRIVACY.md` documents real collection: a keyed hash of the Apple subject identifier, a
  device-only installation credential, "content-free request metadata and consented product events…
  retained for 30 days", invite redemption records, and entitlement history. `docs/TESTFLIGHT.md:6`
  requires that "the privacy manifests match the archived binary".
- Guideline: 5.1.2 and the App Privacy requirement. This is what App Store Connect diffs the nutrition
  labels against; a silent manifest means the labels Chey types in have nothing to agree with.
- Severity: major
- Fix: add `NSPrivacyCollectedDataTypes` to the app manifest describing what the proxy actually receives
  — at minimum `NSPrivacyCollectedDataTypeOtherUserContent` (linked, not used for tracking, purpose
  `NSPrivacyCollectedDataTypePurposeAppFunctionality`) for the material sent to Cy, and
  `NSPrivacyCollectedDataTypeOtherDiagnosticData` for the content-free request metadata. Then answer the
  App Store Connect App Privacy questionnaire from the same list (owner step O-5) so the two match.
- Batch: B6 (code) + owner step O-5
- Status: open

### APPLE-10 Calendar integration asks for full access while the app and its privacy doc describe write-only behaviour
- Where: `ios/AgentCy/Services/CalendarSyncService.swift:181`, `ios/project.yml:91`
- Evidence: `func requestFullAccess() async throws -> Bool { try await eventStore.requestFullAccessToEvents() }`
  and the only declared string is `NSCalendarsFullAccessUsageDescription: "Allow agent.cy to add
  scheduled posts and tasks to your chosen calendar."` — a purpose string that describes writing.
  `docs/PRIVACY.md` states "agent.cy does not import unrelated calendar events". The one thing that
  genuinely needs full access is the calendar picker (`CalendarSyncService.availableCalendars()` calls
  `eventStore.calendars(for: .event)`, which write-only access does not permit).
- Guideline: 5.1.1 — request the minimum access, and make the purpose string match the request. A
  full-access prompt whose text only mentions adding events is a reviewer question, and the mismatch
  between the string and the scope is the part that reads badly.
- Severity: minor (major if review asks and the answer is "for the picker")
- Fix: keep full access, since the picker needs it, but make the purpose string honest about the scope:
  "agent.cy needs calendar access to list your calendars so you can choose one, and to add and update
  the posts and tasks you schedule. It never reads your other events." Edit `ios/project.yml:91` and
  `ios/project.yml:175` together.
- Batch: B6 (code)
- Status: open

### APPLE-11 Release configs pin Development provisioning profiles on the app and the widget
- Where: `ios/project.yml:58-59` and `:223-224`
- Evidence: both Release configs carry `CODE_SIGN_STYLE: Manual` and
  `PROVISIONING_PROFILE_SPECIFIER: AgentCy Development 2026` / `AgentCy Widgets Development 2026`.
  `scripts/archive_testflight.sh:32` passes `CODE_SIGN_STYLE=Automatic` on the command line, so archiving
  works today, but the specifier stays set and Xcode will fight it: automatic signing with an explicit
  profile specifier resolves inconsistently, and archiving from the Xcode UI (which is what
  `docs/TESTFLIGHT.md:33` tells Chey to do for the upload) does not get the command-line override.
- Severity: minor (it makes APPLE-02 harder to notice and harder to fix cleanly)
- Fix: remove `CODE_SIGN_STYLE` and `PROVISIONING_PROFILE_SPECIFIER` from both Release configs and let
  the base `CODE_SIGN_STYLE: Automatic` stand. Fold into the APPLE-02 edit.
- Batch: B6 (code)
- Status: open

---

## 2. Owner-only steps (App Store Connect and Xcode accounts), in order

These cannot be done from the repo. Order matters — later steps depend on earlier ones.

**O-1 · Apple Account and agreements.** In Xcode, Settings > Accounts, add the Apple Account that owns
team `2S27MSM8G8` and download signing assets. In App Store Connect, accept any pending Paid
Applications and Program License agreements. Nothing below can be uploaded until agreements are current.
*Owner action. Source: `docs/TESTFLIGHT.md:7`.*

**O-2 · App record and identifiers.** Create the `com.agentcy.app` app record. Confirm the app, the
widget extension `com.agentcy.app.widgets`, the share extension `com.agentcy.app.inspiration-share`, the
CloudKit container `iCloud.com.agentcy.app`, the App Group `group.com.agentcy.app`, and the keychain
group `com.agentcy.shared` all sit on team `2S27MSM8G8`.
*Owner action.*

**O-3 · Sign in with Apple key.** In the developer portal, create a Sign in with Apple key and a
Services/App ID client secret, then put `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and the `.p8` private key into
Railway. **APPLE-01 cannot be fixed in code without this.**
*Owner action. Blocks APPLE-01.*

**O-4 · APNs production.** Create or confirm the production APNs key for the bundle ID so the
`APS_ENVIRONMENT: production` change in APPLE-02 has something to authenticate against.
*Owner action. Pairs with APPLE-02.*

**O-5 · App Privacy answers.** Complete the App Privacy questionnaire from `docs/PRIVACY.md`, declaring:
the keyed hash of the Apple subject identifier (identifiers, app functionality, linked, not tracking);
user content sent to the AI provider (app functionality, linked, not tracking); content-free request
metadata and consented product events (diagnostics/usage, app functionality). Then confirm the answers
match `PrivacyInfo.xcprivacy` after APPLE-09 lands.
*Owner action. Pairs with APPLE-09.*

**O-6 · Subscription decision.** Decide whether the first external cohort is promotional-only. If yes,
create no App Store subscription products yet and say so in review notes — the app must then show no
purchasable subscription anywhere (see APPLE-03). If a paid pilot is wanted, create the auto-renewable
subscription group, product, price, localized display name, and the review screenshot, and do not submit
until the RevenueCat client flow ships.
*Owner action. Pairs with APPLE-03.*

**O-7 · Age rating.** Complete the age rating questionnaire. Two questions need deliberate answers:
the app produces AI-generated content on request, and it stores creator-authored content. There is no
"18+" claim anywhere in the codebase (`grep -rni "18+\|adults only" ios/ docs/` returns nothing outside
this lane's brief), so do not select one unless Chey intends an adult rating — an unjustified high
rating restricts the app for no reason, and an understated one is a rejection.
*Owner action.*

**O-8 · Privacy policy and support URLs.** App Store Connect requires a reachable privacy policy URL and
a support URL. The repo has `docs/PRIVACY.md` but no published policy page and no support address —
`grep -rni "privacy policy\|support@" ios/AgentCy/Views` returns nothing, so neither exists in the app
either. Publish a policy page derived from `docs/PRIVACY.md` and a support contact, then enter both.
*Owner action.*

**O-9 · Export compliance.** `ITSAppUsesNonExemptEncryption` is already `false` in every target's
Info.plist. I verified this is currently correct: the app uses only HTTPS, `CryptoKit.SHA256`
(`AppleAccountAccessView.swift:672`), `SecRandomCopyBytes`, and the Keychain —
`grep -rn "AES\|ChaChaPoly\|SealedBox\|CCCrypt\|SymmetricKey" ios/AgentCy ios/AgentCyShared` returns
nothing. Confirm the "uses exempt encryption" answer once in App Store Connect; it then carries forward.
*Owner action, already substantiated.*

**O-10 · CloudKit production schema.** Promote the exercised development schema to Production before any
external tester gets a build. External TestFlight builds run against the production container.
*Owner action. Source: `docs/TESTFLIGHT.md:11`.*

**O-11 · Review access.** App Review will hit the invitation gate on first launch, so guideline 2.1's
demo-account requirement applies. Provide, in App Store Connect review notes: an unredeemed invitation
code, a note that "I have an invitation code" is the second button on the first screen, and a working
test Apple Account if the reviewer needs to test the Sign in with Apple path. Confirm the Railway proxy
is up and the invite code is live at submission time.
*Owner action.*

**O-12 · Screenshots and metadata.** 6.9" iPhone screenshots (the app is portrait-only and iPhone-only,
so one size class), name, subtitle, description, keywords, and promotional text. The description must
disclose that content is generated by an AI provider, matching `PRIVACY.md`'s public wording.
*Owner action.*

**O-13 · TestFlight setup.** Beta contact info, beta description, feedback email, and testing notes.
Internal group first, then the external five-creator group with **What to Test** written. Note the
deployment target is iOS 26.0 (`ios/project.yml:5`, `:11`) — every tester needs an iOS 26 device or they
cannot install, and TestFlight will not tell them why in advance. Say so in the invitation.
*Owner action.*

**O-14 · Build number.** `CURRENT_PROJECT_VERSION` is `229` (`ios/project.yml:14`) against
`MARKETING_VERSION 0.1.0`. History is monotonic (139 -> 158 -> 170 -> 227 -> 229) so hygiene is fine;
increment before each upload as `docs/TESTFLIGHT.md:19` says. `docs/TESTFLIGHT.md:22` still shows
`BUILD_NUMBER=136` as its example, which is now stale and misleading — worth updating when B6 lands.
*Owner action + a one-line doc fix in B6.*

---

## 3. Quality items testers will notice (no review block)

### APPLE-12 The Sign in with Apple button turns black-on-black when the appearance changes while the app runs
- Where: `account-access-gate`, `ios/AgentCy/Views/Account/AppleAccountAccessView.swift:614`,
  iPhone, dark appearance
- Evidence: `.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)`. `SignInWithAppleButton`
  is a `UIViewRepresentable` whose style is fixed when the view is made and is not re-applied on a
  `colorScheme` change. Captured both ways on iPhone 17 Pro:
  - `docs/refinement/evidence/apple/first-launch-gate-dark-coldstart.png` — launched while dark: white
    button, correct.
  - `docs/refinement/evidence/apple/first-launch-gate-dark.png` — launched light, then switched to dark
    at runtime: the button stays black on the near-black `agentSurface` card, visible only by its edge.
  - `docs/refinement/evidence/apple/first-launch-gate-light.png` — light baseline.
  A tester on the system's automatic Light/Dark schedule hits this without doing anything.
- Severity: major — it is the only control on the first screen, and Apple's Sign in with Apple design
  requirements call for a clearly visible button with adequate contrast against its background
- Fix: force the representable to rebuild when the appearance changes by keying it —
  `.id(colorScheme)` on the `SignInWithAppleButton`, which is the smallest correct change here.
- Batch: B6 (code)
- Status: open

### APPLE-13 Clear Liquid Glass on the tab bar lets page content smear through the bar
- Where: phone tab bar (shell chrome, captured over the `home` tab root),
  `ios/AgentCy/Views/Shell/AppShellView.swift:809-811`, iPhone, light appearance
- Evidence: `docs/refinement/evidence/apple/tabbar-glass-legibility.png` (cropped from
  `home-light.png`, y 2280-2620 of the 1206x2622 capture). The task row behind the bar is legible
  *through* it: "THE ONE JOB IDEA TEST · TODAY · NONE" reads clearly along the bar's top edge, and a
  smeared strip of the row beneath it sits inside the bar between the calendar and tasks icons,
  competing with the glyphs. Every glass surface in the app uses the clear variant —
  `grep -rno "glassEffect([^)]*" ios/AgentCy` returns 10 x `.clear.interactive(`, 2 x `.clear, in: .rect(...)`,
  1 x `.clear, in: .circle`, and zero uses of `.regular`. Apple's clear variant is for glass over
  media you control, and expects a dimming layer beneath it; `.regular` is the variant that adapts to
  arbitrary content behind it.
- Severity: major (visible on the default first screen)
- Fix: shared change. Use `.regular` for chrome that floats over arbitrary scrolling content — the tab
  bar (`AppShellView.swift:809`), `AgentToolbarIconLabel` (`ios/AgentCy/Design/DesignTokens.swift:314`),
  `AgentCircularGlassIconButton` (`DesignTokens.swift:928`), and `AgentPhonePostActionButton`
  (`DesignTokens.swift:975`). Keep `.clear` only where the app owns the backdrop. Because it changes
  every glass control at once, it should land as one token-level decision recorded in `design.md`
  alongside L1's close-control work rather than as scattered edits.
- Batch: B6 (code, shared — coordinate with L1)
- Status: open

### APPLE-14 Six icon-only tabs with no labels and no tab-bar container for VoiceOver
- Where: phone tab bar (shell chrome; the six tab roots are `home`, `plan-week`, `tasks`, `pillars`,
  `idea-bank`, `cy` in `01-page-inventory.md:11-16`), `ios/AgentCy/Models/DomainTypes.swift:1350-1357`,
  `ios/AgentCy/Views/Shell/AppShellView.swift:762-810`
- Evidence: `AppTab.allCases` is `home, today, tasks, pillars, ideaBank, cy` — six — plus a separate
  Create accessory, all visible in `docs/refinement/evidence/apple/tabbar-glass-legibility.png`. No tab
  renders its `title`; only the icon is drawn (`AppShellView.swift:885`). Apple's iPhone guidance is
  three to five tabs, and UIKit's own tab bar collapses past five into More, which a custom bar does
  not do. Per-tab VoiceOver is handled well — `.accessibilityLabel(tab.title)`,
  `.accessibilityHint(...)`, `.accessibilityAddTraits(.isSelected)` at `AppShellView.swift:801-805` —
  but the enclosing `HStack` has no `.accessibilityElement(children: .contain)` and no tab-bar trait
  (`grep -n "isTabBar\|accessibilityElement" AppShellView.swift` finds one hit, at line 649, elsewhere),
  so VoiceOver reads six loose buttons in scroll order instead of a tab group with position.
- Severity: minor
- Fix: wrap the tab `HStack` in `.accessibilityElement(children: .contain)` so VoiceOver treats it as one
  container. Whether six tabs should become five is a consolidation question that belongs to Chey and
  to L3's flow work, not to this lane — flagging it, not deciding it.
- Batch: B6 (code) for the container; the tab count is a Chey decision
- Status: open

### APPLE-15 The first screen a new tester sees is written for a returning creator
- Where: `account-access-gate` and `installation-invite-gate`,
  `ios/AgentCy/Views/Account/AppleAccountAccessView.swift:19-59`, iPhone, both appearances
- Evidence: `docs/refinement/evidence/apple/first-launch-gate-light.png`. On a clean install the gate
  leads with "Pick up where you left off." and "Sign in to connect this device to your existing
  workspace." The invitation path — the only one a beta tester can actually use — is a secondary button
  below the card, explained by fine print at the bottom: "New here? Use the invitation code you
  received." The external cohort is five invited creators, none of whom has an existing workspace, and
  App Review will land here too (see O-11).
- Severity: minor
- Fix: lead with the invitation for a device that has never held a credential, and demote sign-in to the
  secondary position; swap the emphasis back once `hasLinkedAccount` has ever been true on the device.
  Copy change plus a branch on `appModel.hasInstallationCredential` in `AccountAccessGate`.
- Batch: B6 (code)
- Status: open

### APPLE-16 A Keychain read failure is shown as a red error on the first screen before the creator has done anything
- Where: `account-access-gate`, `ios/AgentCy/ViewModels/AppModel.swift:503-530`
- Evidence:
  ```swift
  } catch {
      hasInstallationCredential = false
      hasLinkedAccount = false
      presentCreatorError(error, action: "The connection")
  }
  ```
  which renders through `CreatorFacingErrorMapper.swift:116-121` as "The connection couldn't be
  completed. Your work is saved. Try again." and is displayed by `AccountAccessStatus.resolve`
  (`AppleAccountAccessView.swift:81-92`) as an urgent, `agentDestructive`-coloured line under the
  sign-in card. **Scope note:** I reproduced this on the entitlement-free baseline simulator build
  (`first-launch-gate-light.png`, `first-launch-gate-dark.png`, `first-launch-gate-dark-coldstart.png` —
  it appears on every cold launch, both appearances), where `SecItemCopyMatching` cannot succeed because
  the build carries no entitlements. So the *trigger* I observed is a build artifact, and I am not
  claiming a signed build shows this today. The defect is the code shape: `load()` already maps
  `errSecItemNotFound` to `nil` (`ios/AgentCy/Services/APIClient.swift:59`), so anything reaching that
  `catch` is an unexpected Keychain or decode failure — and the app's response is to greet a first-time
  creator with a red error about a connection they have not attempted. Any real cause (a restored
  device whose stored blob no longer decodes, a provisioning change, a Keychain read during a locked
  state) produces the same first impression.
- Severity: minor
- Fix: on the launch path, treat a failed credential read as "no credential" — set the flags, log
  content-free, and leave `notice` alone. Surface a Keychain error only after the creator taps Continue
  with Apple or Connect Cy. Separately, `AccountAccessGate` should show only account-scoped notices
  rather than whatever `appModel.notice` happens to hold.
- Batch: B6 (code)
- Status: open

### APPLE-17 Two forever-looping animations keep running when Reduce Motion is switched on mid-session
- Where: `ios/AgentCy/Views/Shell/AppShellView.swift:722-726`,
  `ios/AgentCy/Views/Capture/CreationHubView.swift:269-273`
- Evidence: both read
  ```swift
  .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { isExpanded = true }
  }
  ```
  The guard is evaluated once, at appear. Turning Reduce Motion on afterwards never cancels the running
  `repeatForever`. The rest of the app gets this right: the other five `repeatForever` sites read
  `reduceMotion ? nil : ...` inside `.animation(...)` (`DesignTokens.swift:1628`,
  `SettingsSubpages.swift:2119`, `QuickCaptureView.swift:89`, `AppleAccountAccessView.swift:533`,
  `AskCyView.swift:1020`) and re-evaluate, and `CyWeeklyPlanningPulse` (`AppShellView.swift:897-916`)
  branches on the environment value so it stops correctly.
- Severity: minor
- Fix: at both sites, drive the flag from `.onChange(of: reduceMotion, initial: true)` instead of
  `.onAppear`, setting the animated state back to its rest value when Reduce Motion turns on — the
  pattern `AccountRestoreView` already uses at `AppleAccountAccessView.swift:466-468`.
- Batch: B6 (code) — overlaps L2's motion lane
- Status: open

### APPLE-18 Close-control variants: no Apple-side constraint, so the choice is L1's alone
- Where: app-wide; see `docs/refinement/01-page-inventory.md:177-190`
- Evidence: I found two glass geometries in the shared components —
  `AgentToolbarIconLabel` is a 44x44 circle with a 17 pt glyph and an `agentPureWhite.opacity(0.22)`
  hairline (`ios/AgentCy/Design/DesignTokens.swift:304-322`); `AgentCircularGlassIconButton` is a 48x48
  circle with a 16 pt glyph and a `0.16` hairline (`DesignTokens.swift:917-941`). The page inventory,
  which swept all 164 surfaces rather than just the shared components, found **ten** distinct close
  implementations, including a hand-rolled non-glass 40x40 opaque circle used only by
  `day-agenda-add-live-post` (`SocialGridView.swift:1038-1051`). Its count supersedes mine and I am not
  restating it — with one correction below.
- Severity: minor, from this lane's angle only
- Fix: L1 owns picking one close control. The only thing L6 adds is the constraint check, and there
  isn't one: every geometry in play clears Apple's 44 pt minimum target, and Apple has no opinion
  between 44 pt and 48 pt or between glass and opaque. So nothing in App Review or the HIG constrains
  L1's choice — it is purely a design-system decision.
- **Correction to `01-page-inventory.md`:** that document's row for `installation-invite-gate`
  (`01-page-inventory.md:166`) and its variant list (`:190`) both say the surface has "no toolbar item"
  and is "swipe-only". That is wrong. `InstallationInviteGate` does have a close control —
  `ios/AgentCy/App/RootView.swift:495-503`:
  ```swift
  .toolbar {
      ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
              appModel.resetInstallationInviteState()
              dismiss()
          }
          .disabled(appModel.isRedeemingInvite)
      }
  }
  ```
  It is a plain *text* "Close" button rather than the glass X, which makes it a further variant rather
  than an absence — and it matters here because this is the surface App Review reaches (O-11) and the
  one a beta tester uses on first launch (APPLE-15). L1 and the merger should treat the inventory's
  "1 surface with no visible control at all" count as off by one.
- Batch: B6 — defer to L1
- Status: open

### APPLE-19 SF Symbols appear in shipped UI, including on iPhone surfaces
- Where: twelve sites
- Evidence: `grep -rn "Image(systemName:" ios/AgentCy ios/AgentCyWidgets ios/AgentCyInspirationShare`
  returns 12 hits — iPhone Share Extension: `ShareViewController.swift:840`, `:863`, `:888`, `:904`;
  iPhone widgets: `WidgetViews.swift:186`, `:204`, `:217`; iPhone app: `PillarsView.swift:2264`;
  Catalyst: `MCPDesktopReviewView.swift:110`, `:152`, `:477`, `DesktopAppShellView.swift:339`. The
  contract's non-negotiable is "No SF Symbols in shipped UI; icons go through `AgentIcon`", and
  `ios/project.yml:200-202` states the intent explicitly: "Live Activities use the same licensed Nucleo
  assets as the app so system surfaces never fall back to an SF Symbol for app actions." Seven of the
  twelve are on iPhone surfaces a beta tester will see.
- Severity: minor (contract violation; no Apple-side consequence)
- Fix: route each through `AgentIconView`, adding any missing `AgentIcon` cases (chevron-left,
  chevron-right, eyedropper, checkmark, link, link-badge-plus, mic, waveform). Owned by L1's
  consistency lane; recorded here because the Catalyst four are exactly the "embarrasses an internal
  build" case my brief asks about.
- Batch: B6 — defer to L1
- Status: open

### APPLE-20 One Catalyst control uses a fixed font size that ignores Dynamic Type
- Where: `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:339-340`
- Evidence: `Image(systemName: appearanceCycleSymbol).font(.system(size: 15, weight: .medium))`. Every
  other font in the app goes through the semantic tokens in `DesignTokens.swift:599-680`, which all use
  `.custom(..., relativeTo:)` and so scale — `agentBody` is `relativeTo: .body`, `agentTitle` is
  `relativeTo: .title2`, and so on. `grep -rn "\.system(size:" ios/AgentCy` returns 11 hits, and this is
  the only one outside `DesignTokens.swift`; the ten inside it are `UIFont(name: "InterVariable")`
  fallbacks that only execute if the bundled font fails to load. So Dynamic Type support is otherwise
  in good shape.
- Severity: minor (Catalyst only)
- Fix: replace with `.agentInter(size: 15, weight: .medium, relativeTo: .subheadline)`.
- Batch: B6 (code)
- Status: open

### APPLE-21 The app icon has no dark or tinted variant
- Where: `ios/AgentCy/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Evidence: the set contains a single universal 1024x1024 entry, `agentcy-app-icon.png`. I verified the
  file is valid for submission — `sips` reports `samplesPerPixel: 3`, `hasAlpha: no`, sRGB, 1024x1024,
  and the PNG header is colour type 2, so there is no alpha channel to trip the store's icon check.
  What is missing is the `appearances` entries for dark and tinted, so on a Home Screen set to dark or
  tinted the system shows the light icon unchanged.
- Severity: minor
- Fix: add `"appearances": [{"appearance": "luminosity", "value": "dark"}]` and `"tinted"` entries with
  artwork to match, or supply an Icon Composer `.icon` asset. Needs artwork from Chey, so it is a code
  change waiting on an owner input rather than a pure B6 item.
- Batch: B6 (code) + artwork from Chey
- Status: open

### APPLE-22 The Catalyst Release config asks for a production APNs environment it cannot sign
- Where: `ios/project.yml:141-142` against `:136`
- Evidence: the Catalyst Debug config pairs `APS_ENVIRONMENT: development` with
  `PROVISIONING_PROFILE_SPECIFIER: AgentCy Mac Catalyst Development 2026`, but the Release config sets
  `APS_ENVIRONMENT: production` while inheriting the base `CODE_SIGN_STYLE: Automatic` with no
  distribution profile. A Development profile does not carry the production aps-environment, so a
  Release archive of the internal desktop build fails to sign. This is the mirror image of APPLE-02 and
  the reason that finding is worth fixing carefully rather than by copying the Mac values across.
- Severity: minor (Catalyst is internal per ADR 0012; it only bites when someone archives the desktop app)
- Fix: since the desktop build is internal and development-signed, set the Catalyst Release
  `APS_ENVIRONMENT` to `development` to match the profile actually in use, or add a Mac distribution
  profile if Chey wants a signed internal Release archive. Her call which.
- Batch: B6 (code)
- Status: open

---

## Checked and clear

Recorded so the next pass does not redo them.

- **Permission timing.** Every permission is requested in context, not at launch. Microphone at the
  moment recording starts (`VoiceSparkView.swift:41`), speech recognition after a recording exists and
  only to transcribe it (`:84`, `:160`), calendar when the creator connects one
  (`CalendarSyncService.swift:181`), notifications when reminders are enabled
  (`AppModel.swift:1000`, `:1022`) or when bridge push is turned on
  (`MCPBridgeSettingsView.swift:335`). Remote-notification registration only happens if authorization
  already exists (`AgentCyApplicationDelegate.swift:141-148`) — it never provokes a prompt.
- **Photos.** No `NSPhotoLibraryUsageDescription` is needed and none is declared. Every picker is
  SwiftUI `PhotosPicker` (`SettingsSubpages.swift:257`, `:742`, `PostMediaViews.swift:745`, `:771`,
  `:858`, `:873`, `ResumablePostEditorView.swift:1864`, `ScheduledPostDetailView.swift`), which runs out
  of process and requires no usage string. No camera use anywhere.
- **Export compliance.** `ITSAppUsesNonExemptEncryption: false` is correct — see O-9 for the evidence.
- **App icon file validity.** 1024x1024, sRGB, no alpha. Only the appearance variants are missing (APPLE-21).
- **Launch screen.** `UILaunchScreen` with an empty `UIColorName` is a valid empty launch screen
  declaration and produces the system background; no storyboard is needed.
- **Third-party SDK manifests.** There are none to check —
  `grep -c "XCRemoteSwiftPackageReference" ios/AgentCy.xcodeproj/project.pbxproj` returns 0 and
  `ios/project.yml` declares no packages, so the app has no third-party SDKs and no signature
  requirements to satisfy.
- **App Attest.** Not present (`grep -rn "DCAppAttest\|DeviceCheck" ios/` returns nothing), which
  matches `docs/TESTFLIGHT.md:45`: required before the paid production pilot, not before the
  promotional TestFlight cohort. Not a finding for this beta.
- **Hidden features.** The fixture launch arguments are DEBUG-gated at the call site
  (`AgentCyApp.swift:13-24`, `:36-50`), so no demo mode is reachable in a Release build. `PreviewData.swift`
  itself is still compiled into Release but is unreachable — that is dead weight for L4, not a 2.3.1 risk.
- **Crash reporting.** No third-party crash SDK and no MetricKit. TestFlight's own crash collection via
  Xcode Organizer covers the beta; nothing needs to ship in the binary.
- **Dynamic Type.** Handled properly. All ten semantic font tokens use `relativeTo:`
  (`DesignTokens.swift:599-680`), and the accessibility sizes get real layout responses — stacked
  metadata and raised line limits in `TasksView.swift:378-383` and `PillarsView.swift:116-129`, and
  deliberate clamps only on fixed-geometry chrome (`HomeDashboardView.swift:2101`,
  `TasksView.swift:664`, `CreatorAvatar.swift:42`). APPLE-20 is the single exception.
- **Reduce Motion.** Broadly honoured — 40 references to `accessibilityReduceMotion` against 32
  `withAnimation` calls, with the shared press feedback and shell transitions all branching on it.
  APPLE-17 is the only gap.
- **Tab hit targets.** Each tab is 46x46 inside a 58 pt bar (`AppShellView.swift:766-770`, `:779`), and
  the Create button is 56x56 (`:825`) — all above the 44 pt minimum.
- **User-generated content (1.2).** Does not apply. Content is single-creator and local; there is no
  social feed, no sharing between users, and no third-party content surface, so the filtering,
  reporting, and blocking requirements are not triggered.

---

## Summary

| Severity | Count | Findings |
| --- | --- | --- |
| Blocker | 5 | APPLE-01, 02, 03, 04, 05 |
| Major | 6 | APPLE-06, 07, 08, 09, 12, 13 |
| Minor | 11 | APPLE-10, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22 |

Owner steps: 14 (O-1 … O-14). APPLE-01 is blocked on O-3; APPLE-03 is blocked on O-6; APPLE-09 pairs
with O-5; APPLE-02 pairs with O-4.
