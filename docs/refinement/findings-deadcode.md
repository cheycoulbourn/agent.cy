# L4 · Dead code findings (batch B4)

Lane L4, code health. Produced 2026-09-01 on branch `refinement/pre-beta`. Every finding below carries evidence
produced in this pass; nothing was seeded from `docs/archive/audit-2026-08/`.

## Method

1. **Symbols.** A brace-depth scanner extracted every top-level and type-member declaration (type, func, init,
   enum case, stored/computed property) across `ios/AgentCy`, `ios/AgentCyShared`, `ios/AgentCyWidgets`,
   `ios/AgentCyInspirationShare` and `ios/AgentCyTests` — 13,043 declarations in 163 files. Declarations inside
   function bodies were skipped (local variables are not API). Every identifier occurrence in all `.swift`,
   `.plist`, `.entitlements`, `.json` files plus `ios/project.yml` was then indexed, and a symbol was flagged when
   its declaring line is the only place its name appears anywhere. Occurrences in comments and string literals
   count as references, so the census under-reports rather than over-reports. Result: 742 zero-reference
   declarations, 73 of them outside the test target. Scripts and the full table:
   `docs/refinement/evidence/L4/extract-declarations.py`, `docs/refinement/evidence/L4/count-references.py`,
   `docs/refinement/evidence/L4/unreferenced-symbols.md`.
2. **Excluded by rule** per the brief: SwiftUI `body`, `#Preview`, `@main`, protocol requirements (AppIntents
   `defaultQuery`/`displayRepresentation`/`parameterSummary`/`appShortcuts`/`suggestedEntities`, `TimelineProvider`
   `getSnapshot`/`getTimeline`, `Transferable.transferRepresentation`, `AppEnum.caseDisplayRepresentations`,
   `VersionedSchema.versionIdentifier`, `SchemaMigrationPlan.schemas`, `UITextFieldDelegate` callbacks,
   `@UIApplicationDelegateAdaptor`), Codable keys, and SwiftData model properties. Model and wire fields are
   reported separately in L4-09.
3. **Assets.** Every imageset and colorset in `ios/AgentCy/Resources/Assets.xcassets` was diffed against the
   `AgentIcon` raw values and against every string literal in code.
4. **Builds.** Three clean builds under `<scratch>/L4/DD` and `<scratch>/L4/DDMac` — separate derived data from the
   path named in `_common.md`, so no other lane was disturbed: iOS simulator, `build-for-testing`, and Mac
   Catalyst. All three succeeded. See `docs/refinement/evidence/L4/build-warnings.md`.

Anything I could not confirm from the call graph alone is marked **verify by build after removal**.

---

### L4-01 A 2,520-line Creator Session feature ships in the binary behind a hardcoded `isEnabled = false`, and its Live Activity is not registered at all

- Where: `ios/AgentCyShared/CreatorSessionActivity.swift:10-12`; feature code in
  `ios/AgentCy/Views/Capture/CreatorSessionView.swift` (1,782 lines),
  `ios/AgentCy/Views/Capture/ActiveCreatorSessionFloatingTimer.swift` (104),
  `ios/AgentCyShared/CreatorSessionActivity.swift` (451),
  `ios/AgentCyWidgets/CreatorSessionLiveActivity.swift` (183). Inventory pages `creator-session`,
  `creator-session-overlay-desktop`, `creator-session-floating-timer`.
- Evidence:
  ```swift
  // ios/AgentCyShared/CreatorSessionActivity.swift:10
  enum CreatorSessionFeatureAvailability {
      static let isEnabled = false
  }
  ```
  Every gate reads that constant and is therefore statically false: `RootView.swift:176`, `AppModel.swift:370`,
  `AppShellView.swift:98`, `AppShellView.swift:174`, `DesktopAppShellView.swift:121`,
  `DesktopAppShellView.swift:134`, `ScheduledPostDetailView.swift:228`.
  `ios/AgentCyTests/WidgetTests.swift:82` asserts `XCTAssertFalse(CreatorSessionFeatureAvailability.isEnabled)`, so
  the off state is pinned by a test.
  Separately, `CreatorSessionActivityWidget` (`ios/AgentCyWidgets/CreatorSessionLiveActivity.swift:85`) is absent
  from `AgentCyWidgetBundle.body` (`ios/AgentCyWidgets/AgentCyWidgets.swift:233-249`, which lists twelve other
  widgets). `CreatorSessionView.swift:173` calls `Activity.request(...)`, so if the flag were flipped the Live
  Activity would have no registered configuration to render. `Info.plist` still declares
  `NSSupportsLiveActivities: true` and `UIBackgroundModes: [audio, remote-notification]`
  (`ios/project.yml:87-90, 104`).
  Line counts: 1782 + 104 + 451 + 183 = 2,520.
- Severity: major
- Fix: **Chey's decision** — the contract reserves "removing or hiding a page without Chey's yes." Recommend
  deleting the four files, the seven `CreatorSessionFeatureAvailability` gates, `WidgetTests.swift:82`, and the
  `NSSupportsLiveActivities` plus `UIBackgroundModes: audio` entries in `ios/project.yml` (keeping
  `remote-notification`, which CloudKit mirroring needs). Dropping background audio also removes an App Review
  question about a capability the app does not use. If the feature is being kept for a later release instead,
  register `CreatorSessionActivityWidget()` in `AgentCyWidgetBundle.body` now so the flag can be flipped without
  shipping a Live Activity that cannot render, and record the deferral in the beta-readiness report.
- Batch: B4
- Status: open

### L4-02 `TodayView` (443 lines) and `PlanHeader` are unreachable — the only reference to each is its own declaration

- Where: `ios/AgentCy/Views/Today/TodayView.swift:4`, `ios/AgentCy/Views/Plan/PlanView.swift:550`
- Evidence:
  ```
  $ grep -rn "TodayView" ios --include='*.swift' --include='*.yml' | grep -v build-device
  ios/AgentCy/Views/Today/TodayView.swift:4:struct TodayView: View {
  ```
  One hit, the declaration. `TodayView` is a complete tab-root-shaped screen — ten `@Query` properties, a focus
  section, three post sections, two task collections, a quick-capture sheet and a confirmation dialog — presented
  from nowhere. `PlanHeader` dies with it:
  ```
  $ grep -rn "PlanHeader" ios --include='*.swift'
  ios/AgentCy/Views/Plan/PlanView.swift:550:struct PlanHeader<Actions: View>: View {
  ios/AgentCy/Views/Plan/PlanView.swift:608:extension PlanHeader where Actions == EmptyView {
  ios/AgentCy/Views/Today/TodayView.swift:162:        PlanHeader(
  ```
  Its only caller is the dead view. `TodayOutputPresentation` and `TodayOutputSection` (same file, lines 451 and
  445) are **not** dead — `AgendaView.swift:1387` calls `TodayOutputPresentation.section`.
- Severity: major
- Fix: move `TodayOutputSection` and `TodayOutputPresentation` (20 lines) into `ios/AgentCy/Services/` beside the
  other presentation policies, then delete `ios/AgentCy/Views/Today/TodayView.swift` and `PlanHeader` with its
  `where Actions == EmptyView` extension (`PlanView.swift:550-620`). Removes roughly 510 lines. Verify by build
  after removal.
- Batch: B4
- Status: open

### L4-03 `AppModel` carries nine never-called methods (106 lines) inside a 4,990-line file

- Where: `ios/AgentCy/ViewModels/AppModel.swift`
- Evidence: each name appears exactly once in the whole repo, on its own `func` line.

  | line span | symbol | lines |
  |---|---|---|
  | 659-672 | `voiceExampleDrafts(context:)` | 14 |
  | 838-843 | `isVoiceProfileStale(_:context:)` | 6 |
  | 2912-2916 | `noteManualDevelopment(of:context:)` | 5 |
  | 3846-3848 | `createRepurposedSpark(from:context:)` | 3 |
  | 3885-3898 | `proposedPillars(context:)` | 14 |
  | 3900-3914 | `acceptPillar(_:context:)` | 15 |
  | 3936-3938 | `ensureCurrentWeek(context:)` | 3 |
  | 3940-3953 | `saveWeekToTemplate(_:context:)` | 14 |
  | 4320-4351 | `addPublishingOutput(...)` | 32 |

  ```
  $ for f in voiceExampleDrafts isVoiceProfileStale noteManualDevelopment createRepurposedSpark \
             proposedPillars acceptPillar ensureCurrentWeek saveWeekToTemplate addPublishingOutput; do
      printf "%-24s %s\n" "$f" "$(grep -rn "\b$f\b" ios --include='*.swift' | grep -v build-device | wc -l)"
    done
  voiceExampleDrafts       1
  isVoiceProfileStale      1
  noteManualDevelopment    1
  createRepurposedSpark    1
  proposedPillars          1
  acceptPillar             1
  ensureCurrentWeek        1
  saveWeekToTemplate       1
  addPublishingOutput      1
  ```
  None is a protocol requirement: `AppModel` is a concrete `@Observable` class and no protocol it adopts declares
  these. `proposedPillars` / `acceptPillar` are the remains of an AI pillar-proposal flow; `voiceExampleDrafts` and
  `isVoiceProfileStale` pair with the dead `OnboardingDraft` voice fields in L4-09 — one removed onboarding step,
  cut in two places.
- Severity: major
- Fix: delete all nine. Verify by build after removal — they take a `ModelContext` and run SwiftData fetches, so a
  compile is the cheapest confirmation nothing reaches them through a key path.
- Batch: B4
- Status: open

### L4-04 Three design-token symbols in `DesignTokens.swift` are never used, including an entire button style

- Where: `ios/AgentCy/Design/DesignTokens.swift:33`, `:632`, `:1255`
- Evidence: one repo-wide hit each — the declaration.
  - `:1255` `struct AgentDesktopPrimaryActionButtonStyle: ButtonStyle` — a whole unused button style, and the only
    "primary action" style in the token file. Nothing adopts it.
  - `:33` `static let sectionHeadingSpacing: CGFloat = AgentSpacing.x2` on `AgentLayout`.
  - `:632` `static var agentBriefTitle: Font` — one of the sixteen semantic font tokens, the only one with zero
    call sites (the other fifteen are used across 921 `.font(.agent…)` sites).
- Severity: minor
- Fix: delete all three. Before deleting `AgentDesktopPrimaryActionButtonStyle`, confirm with the design lane (B1)
  that it is not the intended landing place for desktop primary actions; if it is, the fix is to adopt it rather
  than remove it.
- Batch: B4, or B1 if the button style is adopted instead
- Status: open

### L4-05 Nine unreferenced symbols in the model and service layer, including a whole second recurrence materializer

- Where: as listed
- Evidence: one repo-wide hit each.

  | file:line | symbol | note |
  |---|---|---|
  | `ios/AgentCy/Services/RecurringPostSchedule.swift:939` | `enum RecurringPostMaterializer` | whole type dead |
  | `ios/AgentCy/Services/RecurringPostSchedule.swift:940` | `RecurringPostMaterializer.createFutureOccurrences(...)` | its only member |
  | `ios/AgentCy/Services/RecurringPostSchedule.swift:815` | `PostSeriesDeletionPolicy.isPartOfSeries(_:)` | |
  | `ios/AgentCy/Services/VoiceSparkRecordingStore.swift:154` | `updateTranscript(...)` | |
  | `ios/AgentCy/Services/LocalCyService.swift:152` | `LocalCyAIClient.isRemoteAvailable()` | |
  | `ios/AgentCy/Services/LocalCyService.swift:322` | `LocalCyAIClient.removeRequest(requestID:)` | `private`, so conclusively unreachable |
  | `ios/AgentCy/Services/CreatorFacingErrorMapper.swift:10` | `static let postNotFound` | an error string never shown |
  | `ios/AgentCy/Models/DomainTypes.swift:1341` | `SubscriptionAccess.canEditExisting` | `var canEditExisting: Bool { true }` — a constant nothing reads |
  | `ios/AgentCy/Models/PersistenceModels.swift:1250` | `Pillar.isBranch` | computed, not schema: `var isBranch: Bool { parentPillarID != nil }` |

  `RecurringPostMaterializer` is the notable one: `RecurringPostSchedule.swift` is the live recurrence engine, and
  this enum is a second, unwired materializer sitting inside the same file.
- Severity: minor
- Fix: delete all nine. `Pillar.isBranch` is computed, not a stored SwiftData field, so removing it is not a schema
  change. Before deleting `LocalCyAIClient.removeRequest` — a `private` request-queue cleanup path that was never
  wired — confirm with the security lane that queued local-AI requests are cleaned up some other way; if they are
  not, this is a leak whose fix is already written and should be called rather than deleted.
- Batch: B4
- Status: open

### L4-06 Ten unreferenced members inside view files, four of them in `QuickCaptureView`

- Where: as listed
- Evidence: one repo-wide hit each. Every entry is `private` or a `private struct`, so "no other occurrence of the
  name" is conclusive — nothing outside the file could reach them.

  | file:line | symbol |
  |---|---|
  | `ios/AgentCy/Views/Capture/QuickCaptureView.swift:988` | `private var cyIdeaPrompt: some View` |
  | `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1539` | `private func lockedTaskValue(label:value:)` |
  | `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1691` | `private var headerTitle: String` |
  | `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1700` | `private var headerSubtitle: String` |
  | `ios/AgentCy/Views/Capture/CreatorSessionView.swift:1340` | `private var fullScreenTimerContentWidth: CGFloat` |
  | `ios/AgentCy/Views/Pillars/PillarsView.swift:2298` | `private struct PillarMetrics` |
  | `ios/AgentCy/Views/Pillars/PillarsView.swift:2313` | `PillarMetrics.postedCount` |
  | `ios/AgentCy/Views/Agenda/AgendaView.swift:2254` | `AgendaOutputState.needsRescheduling` |
  | `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:666` | `private var editingPayloadBinding: Binding<MCPBridgeRequestPayload>?` |
  | `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:1559` | `private func openCy()` |

  `QuickCaptureView`'s `headerTitle` / `headerSubtitle` pair is the tell that this page once had a custom header
  and now gets one elsewhere; the strings are stranded. `DesktopAppShellView.openCy()` is a dead navigation action
  on the desktop shell.
- Severity: minor
- Fix: delete all ten. `PillarMetrics` and `postedCount` go together — the struct has no reachable members left.
  `CreatorSessionView.fullScreenTimerContentWidth` disappears with L4-01 if that file goes. Verify by build after
  removal.
- Batch: B4
- Status: open

### L4-07 Seven imagesets ship unreferenced, and five `AgentIcon` cases have no call sites

- Where: `ios/AgentCy/Resources/Assets.xcassets`, `ios/AgentCy/Design/DesignTokens.swift:85` and the `AgentIcon`
  enum body
- Evidence: the catalog holds 60 `agent-icon-*.imageset` folders; the `AgentIcon` enum declares 58 distinct raw
  values.
  ```
  $ comm -23 <imageset names> <AgentIcon raw values>
  agent-icon-feed
  agent-icon-move-vertical
  ```
  Neither name appears in any source file. (The only `agent-icon-move-vertical` hit is inside
  `ios/build/DeviceInstall/.../GeneratedAssetSymbols.swift`, an untracked build artifact.)
  Five further cases exist in the enum but are never constructed. These had to be disambiguated by hand, because a
  plain `grep '\.send'` also matches SwiftUI's `SubmitLabel.send` and `grep messages` matches an unrelated
  property assignment:
  ```
  $ for c in messages send camera music radioSelected; do printf -- "--- %s\n" "$c"
      grep -rnE "AgentIcon\.${c}\b|AgentIconView\(\.${c}\b|\(\.${c}[,)]|: \.${c}\b" \
        ios/AgentCy ios/AgentCyShared ios/AgentCyWidgets ios/AgentCyInspirationShare --include='*.swift' \
        | grep -v 'DesignTokens.swift.*case '; done
  --- messages
  --- send
  ios/AgentCy/Views/Cy/AskCyView.swift:1706:   .submitLabel(.send)     <- SwiftUI SubmitLabel, not AgentIcon
  --- camera
  --- music
  --- radioSelected
  ```
  So the seven unreferenced imagesets are `agent-icon-feed`, `agent-icon-move-vertical`, `agent-icon-messages`,
  `agent-icon-send`, `agent-icon-camera`, `agent-icon-music`, `agent-icon-radio-selected`.
  `radioSelected` is worth the design lane's attention: `radioEmpty` is used but its selected partner is not, so
  some radio control draws its selected state another way.
- Severity: minor
- Fix: delete the five dead `AgentIcon` cases (`messages`, `send`, `camera`, `music`, `radioSelected`) and all
  seven imageset folders. `Assets.xcassets` is a build input of three targets — `AgentCy`, `AgentCyMac`, and
  `AgentCyWidgets` via `ios/project.yml:204-206` — so this shrinks the widget extension too; re-run
  `xcodegen generate` and build all three. If the design lane wants `radioSelected` kept, the fix is to adopt it in
  the radio control rather than delete it.
- Batch: B4; `radioSelected` may move to B1
- Status: open

### L4-08 All ten colorsets in the asset catalog are unreferenced — nothing in the app can read them

- Where: `ios/AgentCy/Resources/Assets.xcassets/{AccentColor, ActionAccent, AgentBorder, AgentCanvas,
  AgentDestructive, AgentSecondary, AgentSuccess, AgentSurface, AgentText, CyAccent}.colorset`
- Evidence: the project turns off generated asset symbols, so a colorset is reachable only through a string lookup,
  and there are none.
  ```
  # ios/project.yml:17-19
  # Design tokens are programmatic so simulator/source builds and the asset
  # catalog share one semantic API without generated Color redeclarations.
  ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS: NO

  $ grep -rnE 'Color\("|UIColor\(named:|Image\("' ios/AgentCy ios/AgentCyShared ios/AgentCyWidgets \
      ios/AgentCyInspirationShare --include='*.swift'
  ios/AgentCyWidgets/CreatorSessionLiveActivity.swift:78:   Image("agent-icon-stop")
  ```
  One string asset lookup in the whole app, and it is an image. Each colorset name also returns zero hits
  individually. `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` is set nowhere in `ios/project.yml` or the
  generated `ios/AgentCy.xcodeproj/project.pbxproj`, so not even `AccentColor` is picked up by convention. The real
  tokens are programmatic — `Color.agentHairline` and its siblings are built from `AgentColorPalette` through
  `adaptive(light:dark:)` at `ios/AgentCy/Design/DesignTokens.swift:472`.
- Severity: minor
- Fix: delete all ten colorsets, then re-run `xcodegen generate` and build all three catalog-consuming targets.
  Keep `AppIcon.appiconset` — it *is* referenced, through `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
  (`project.pbxproj:1689, 1785, 1835, 1863`). Beyond the bytes, these stale colorsets are a consistency trap:
  anyone opening the catalog sees a colour system that no longer matches `DesignTokens.swift`.
- Batch: B4
- Status: open

### L4-09 Unused model and wire fields: four dead `OnboardingDraft` voice fields, one unwritten SwiftData column, and twelve decoded-but-unread payload fields

- Where: `ios/AgentCy/Models/DomainTypes.swift:1669-1672`, `ios/AgentCy/Models/PersistenceModels.swift:1466`,
  `ios/AgentCy/Services/APIWireModels.swift`, `ios/AgentCy/Services/APIClient.swift`,
  `ios/AgentCy/Services/MCPBridgeService.swift`
- Evidence: split by kind, because the removal risk differs for each:

  **(a) Plain-struct fields, safe to delete.** `OnboardingDraft` is declared `struct OnboardingDraft: Equatable,
  Sendable` (`DomainTypes.swift:1653`) — not `@Model`, not `Codable` — so nothing persists it:
  ```swift
  // DomainTypes.swift:1664-1672
  // Retained while the Paper-led onboarding flow is migrated so existing
  // onboarding services and saved drafts continue to compile and decode.
  var assistanceMode: AssistanceMode = .collaborate
  var pillars: [OnboardingPillarDraft] = []
  var voiceExamples: [VoiceExampleDraft] = []
  var voiceSummary = ""
  var voiceTraits = ""
  var voiceAvoid = ""
  var voiceProfilePayloadJSON = ""
  ```
  `voiceSummary`, `voiceTraits`, `voiceAvoid` and `voiceProfilePayloadJSON` each have exactly one repo-wide hit,
  their own declaration. The comment justifies them by saying saved drafts must "continue to decode," but the type
  is not `Codable`, so that reason no longer holds.

  **(b) SwiftData schema field — needs a migration decision, not a deletion.**
  ```swift
  // PersistenceModels.swift:1457-1466
  @Model
  final class PendingWeekProposal {
      ...
      var appliedAt: Date?     // never written, never read
  }
  ```
  Zero references. The class is a *pending* proposal carrying a `statusRaw`, so `appliedAt` was meant to record
  when a proposal was applied and was never wired.

  **(c) Wire-model fields decoded from the server and never read.** Twelve, each with one repo-wide hit:
  `IdeaDirectionWire.whyItFits` (`APIWireModels.swift:194`), `SparkTurnResultWire.readyToCompose` (`:311`) and
  `.missingFields` (`:312`), the enum cases `SparkRecommendedNextStepWire.answerQuestion` (`:288`) and
  `.reviewWorkingState` (`:290`), `ChatProposedActionKindWire.planWeek` (`:345`),
  `AIQuotaScopeWire.installationShortWindow` / `.globalDailySpend` / `.providerRateLimit`
  (`APIClient.swift:559, 561, 562`), and `MCPBridgeExternalPlanContext.sourceOfTruth` / `.syncDirection` /
  `.externalWritesRequireApproval` (`MCPBridgeService.swift:616-618`).
- Severity: minor
- Fix:
  (a) delete the four `OnboardingDraft` voice fields together with the two `AppModel` voice methods in L4-03.
  (b) leave `PendingWeekProposal.appliedAt` in the schema and record it in the beta-readiness report as a decision.
  Dropping a stored property from a CloudKit-mirrored `@Model` is a schema change and `AgentCySchemaV1` is still at
  `Schema.Version(1, 0, 0)` (`PersistenceModels.swift:1834`) — not worth a migration before beta. Either wire it in
  `AppModel`'s proposal-apply path or drop it in a deliberate V2.
  (c) leave the wire fields — the decoder needs the non-optional ones and the enum cases are values the server can
  legitimately send. Raise `whyItFits` with the design lane, though: the server computes a "why this fits you"
  explanation for every idea direction and the app throws it away.
- Batch: B4 for (a); (b) and (c) are deferrals with reasons, for the beta-readiness report
- Status: open

### L4-10 Preview-fixture code ships in Release: a 485-line fixture file with no `DEBUG` guard, plus three fixture hooks guarded inconsistently with their own siblings

- Where: `ios/AgentCy/Preview/PreviewData.swift`, `ios/AgentCy/Views/Plan/PlanView.swift:14-52`,
  `ios/AgentCy/Services/APIClient.swift:114`
- Evidence: a `#if` condition-stack scanner walked all four app targets and classified every line mentioning
  `agentCyPreview` or `PreviewData` by whether a live `#if DEBUG` encloses it — 35 guarded, 19 not. Four of the 19,
  in `PostMediaViews.swift`, are false positives (`makePreviewData` there is real media-thumbnail generation).

  **(a) The fixture file itself is unguarded.** `ios/AgentCy/Preview/PreviewData.swift` opens at line 6 with a bare
  `enum PreviewData {` and contains no `#if DEBUG` anywhere in its 485 lines. `ios/project.yml:28-31` adds the
  whole `AgentCy` directory to the `AgentCy` and `AgentCyMac` targets excluding only
  `Support/AgentCy.entitlements`, so all 485 lines of seeded creator profiles, pillars, briefs and tasks compile
  into Release on both form factors. Its callers *are* guarded (`AgentCyApp.swift:13-24` wraps `PreviewData.seed`
  in `#if DEBUG`; `AppShellView.swift:931` sits in a `#Preview`), so release behaviour does not change — but the
  fixture data and its launch-argument parsing ship.

  **(b) Three hooks are unguarded while three siblings in the same enum are guarded.**
  ```swift
  // ios/AgentCy/Views/Plan/PlanView.swift:14-52
  enum PlanRuntimeFixture {
      static func requestsDailyFocusDetail(arguments: [String]) -> Bool {
          arguments.contains("-agentCyPreviewDailyFocusDetail")           // <- no guard
      }
      static func requestsDailyFocusEditor(arguments: [String]) -> Bool {
          #if DEBUG
          arguments.contains("-agentCyPreviewDailyFocusEditor")
          #else
          false
          #endif
      }
      ... requestsEpisodeSlotActions, requestsAddLivePost: both guarded the same way ...
      static func requestsPostSearch(arguments: [String]) -> Bool {
          arguments.contains("-agentCyPreviewPostSearch")                 // <- no guard
      }
      static func postSearchQuery(arguments: [String]) -> String? { ... }  // <- no guard
  }
  ```
  I traced all three call sites and every one is itself inside `#if DEBUG` — `AppShellView.swift:230-236`,
  `PlanView.swift:82-87`, `PlanView.swift:425-430` — so **no release behaviour changes today**. The defect is that
  the guard lives at the call site for three of them and inside the function for the other three, so the next
  caller added in release code silently gets a live fixture hook.

  **(c)** `actor PreviewCredentialStore: InstallationCredentialStoring` (`APIClient.swift:114`) is likewise
  unguarded and ships in Release. Its users are `AgentCyApp.swift:39` (guarded), `AppShellView.swift:933` and
  `RootView.swift:571` (both `#Preview`), and `AgentCyTests`.
- Severity: minor
- Fix: wrap `ios/AgentCy/Preview/PreviewData.swift` in one file-level `#if DEBUG` / `#endif`, and move the three
  unguarded `PlanRuntimeFixture` bodies to the same `#if DEBUG … #else false #endif` shape their siblings already
  use — that makes the guard uniform inside the enum and lets the `#if DEBUG` at the three call sites go away.
  Leave `PreviewCredentialStore` where it is: `AgentCyTests` links the app target in Debug and needs it, and a
  Debug-only guard is enough; flag it to the security lane so a fake credential store is never mistaken for the
  real one. After the change, confirm the Release configuration of both schemes still compiles.
- Batch: B4
- Status: open

---

## Not dead — checked and cleared

Recorded so a later pass does not reopen them.

- **Every `.swift` file in `ios/` belongs to a target.** `ios/project.yml` adds source directories wholesale, and
  `find ios -name '*.swift'` outside the six target directories returns nothing. `ios/AgentCyMac` holds no Swift of
  its own; it compiles `AgentCy` + `AgentCyShared` (`ios/project.yml:113-117`). `AgentCyInspirationShare`
  deliberately takes only three of the seven `AgentCyShared` files (`ios/project.yml:243-246`) — an extension
  keeping its binary small, not an orphan.
- **`PillarColorOption.terracotta` / `.ochre` / `.plum`** (`PillarsView.swift:2330-2334`) look dead to a name
  search, but the enum is `CaseIterable` and the colour chooser iterates `allCases`. Alive.
- **The AppIntents surface** (`CaptureIdeaIntent.swift`) is alive through system discovery:
  `AgentCyAppShortcuts: AppShortcutsProvider`, `defaultQuery`, `parameterSummary`, `appShortcuts`,
  `shortcutTileColor`, `displayRepresentation`, `suggestedEntities`. The single
  `warning: Metadata extraction skipped. No AppIntents.framework dependency found.` in the build log is against
  `AgentCyInspirationShare`, which declares no intents; `ExtractAppIntentsMetadata` runs cleanly for the `AgentCy`
  target (`build-ios.log:1709`).
- **`AgentCyWidgetBundle`, `AgentCyApp`** — `@main` entry points. **`getSnapshot` / `getTimeline`,
  `caseDisplayRepresentations`, `transferRepresentation`, `versionIdentifier`, `schemas`, and the three
  `UITextFieldDelegate` callbacks in `TasksView.Coordinator`** — protocol requirements. All excluded by the brief.
- **`ios/build/` (26 GB) and `ios/build-device/` (285 MB)** are untracked and covered by `.gitignore:18-19`. Not
  repo dead weight, but see L4-23 in `findings-codehealth.md`.

## Gate G-tools · Periphery

A network install of [Periphery](https://github.com/peripheryapp/periphery) would materially improve accuracy, and
I did not install it.

**Expected gain.** Periphery drives the Swift compiler's index store, so it resolves what a name-based census
cannot: protocol witnesses, `@objc` and dynamic dispatch, generic specializations, redundant `public` access
levels, unused function *parameters*, and enum cases reached only through `allCases`. Concretely it would
(a) confirm or clear the ten "verify by build after removal" entries above without a delete-and-compile cycle,
(b) catch dead symbols this census misses because their names collide with a live symbol elsewhere — the
`AgentIcon.send` vs `SubmitLabel.send` collision in L4-07 is exactly that class, and I had to disambiguate five
icon cases by hand, and (c) report unused parameters and over-broad access levels, which I did not attempt at all.

**Cost.** One `brew install peripheryapp/periphery/periphery`, then
`periphery scan --project ios/AgentCy.xcodeproj --schemes AgentCy --targets AgentCy,AgentCyShared,AgentCyWidgets,AgentCyInspirationShare`
— a full index build, roughly the cost of the clean build already run here.

**Recommendation.** Worth it before executing B4, because that batch deletes roughly 3,500 lines and a false
positive there is a build break rather than a silent bug. Needs Chey's yes for the network install.
