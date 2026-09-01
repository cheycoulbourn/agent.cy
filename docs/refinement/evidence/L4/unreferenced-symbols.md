# L4 unreferenced-symbol census — produced 2026-09-01

Method: every top-level and type-member declaration in the four app targets was extracted with a brace-depth scanner
(declarations inside function bodies excluded), then every identifier occurrence across all `.swift`, `.plist`,
`.entitlements`, `.json` and `ios/project.yml` in the six target directories was indexed. A symbol is listed here
when the ONLY occurrence of its name anywhere is its own declaring line. Occurrences inside comments and string
literals count as references, so this list under-reports rather than over-reports.

Totals: 13043 declarations scanned across 163 files; 742 with zero references (73 outside AgentCyTests).

Test-target zero-ref entries are almost all `func testX()` run by the XCTest runtime and are excluded below.

| file:line | kind | symbol | declaring line |
|---|---|---|---|
| `ios/AgentCy/App/AgentCyApp.swift:5` | struct | `AgentCyApp` | `struct AgentCyApp: App {` |
| `ios/AgentCy/App/AgentCyApp.swift:6` | prop | `applicationDelegate` | `@UIApplicationDelegateAdaptor(AgentCyApplicationDelegate.self) private var applicationDelegate` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:7` | prop | `defaultQuery` | `static let defaultQuery = CaptureIdeaPillarQuery()` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:23` | prop | `displayRepresentation` | `var displayRepresentation: DisplayRepresentation {` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:37` | func | `suggestedEntities` | `func suggestedEntities() async throws -> [CaptureIdeaPillarEntity] {` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:63` | prop | `parameterSummary` | `static var parameterSummary: some ParameterSummary {` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:85` | struct | `AgentCyAppShortcuts` | `struct AgentCyAppShortcuts: AppShortcutsProvider {` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:87` | prop | `appShortcuts` | `static var appShortcuts: [AppShortcut] {` |
| `ios/AgentCy/AppIntents/CaptureIdeaIntent.swift:100` | prop | `shortcutTileColor` | `static var shortcutTileColor: ShortcutTileColor { .orange }` |
| `ios/AgentCy/Design/DesignTokens.swift:33` | prop | `sectionHeadingSpacing` | `static let sectionHeadingSpacing: CGFloat = AgentSpacing.x2` |
| `ios/AgentCy/Design/DesignTokens.swift:85` | case | `radioSelected` | `case radioSelected = "agent-icon-radio-selected"` |
| `ios/AgentCy/Design/DesignTokens.swift:632` | prop | `agentBriefTitle` | `static var agentBriefTitle: Font {` |
| `ios/AgentCy/Design/DesignTokens.swift:1255` | struct | `AgentDesktopPrimaryActionButtonStyle` | `struct AgentDesktopPrimaryActionButtonStyle: ButtonStyle {` |
| `ios/AgentCy/Models/DomainTypes.swift:1341` | prop | `canEditExisting` | `var canEditExisting: Bool { true }` |
| `ios/AgentCy/Models/DomainTypes.swift:1669` | prop | `voiceSummary` | `var voiceSummary = ""` |
| `ios/AgentCy/Models/DomainTypes.swift:1670` | prop | `voiceTraits` | `var voiceTraits = ""` |
| `ios/AgentCy/Models/DomainTypes.swift:1671` | prop | `voiceAvoid` | `var voiceAvoid = ""` |
| `ios/AgentCy/Models/DomainTypes.swift:1672` | prop | `voiceProfilePayloadJSON` | `var voiceProfilePayloadJSON = ""` |
| `ios/AgentCy/Models/PersistenceModels.swift:1250` | prop | `isBranch` | `var isBranch: Bool { parentPillarID != nil }` |
| `ios/AgentCy/Models/PersistenceModels.swift:1466` | prop | `appliedAt` | `var appliedAt: Date?` |
| `ios/AgentCy/Models/PersistenceModels.swift:1834` | prop | `versionIdentifier` | `static let versionIdentifier = Schema.Version(1, 0, 0)` |
| `ios/AgentCy/Models/PersistenceModels.swift:1839` | prop | `schemas` | `static var schemas: [any VersionedSchema.Type] { [AgentCySchemaV1.self] }` |
| `ios/AgentCy/Services/APIClient.swift:559` | case | `installationShortWindow` | `case installationShortWindow` |
| `ios/AgentCy/Services/APIClient.swift:561` | case | `globalDailySpend` | `case globalDailySpend` |
| `ios/AgentCy/Services/APIClient.swift:562` | case | `providerRateLimit` | `case providerRateLimit` |
| `ios/AgentCy/Services/APIWireModels.swift:194` | prop | `whyItFits` | `let whyItFits: String` |
| `ios/AgentCy/Services/APIWireModels.swift:288` | case | `answerQuestion` | `case answerQuestion` |
| `ios/AgentCy/Services/APIWireModels.swift:290` | case | `reviewWorkingState` | `case reviewWorkingState` |
| `ios/AgentCy/Services/APIWireModels.swift:311` | prop | `readyToCompose` | `let readyToCompose: Bool` |
| `ios/AgentCy/Services/APIWireModels.swift:312` | prop | `missingFields` | `let missingFields: [SparkDevelopmentFieldWire]` |
| `ios/AgentCy/Services/APIWireModels.swift:345` | case | `planWeek` | `case planWeek` |
| `ios/AgentCy/Services/CreatorFacingErrorMapper.swift:10` | prop | `postNotFound` | `static let postNotFound = "Post not found. It may have been moved or deleted."` |
| `ios/AgentCy/Services/LocalCyService.swift:152` | func | `isRemoteAvailable` | `func isRemoteAvailable() async -> Bool {` |
| `ios/AgentCy/Services/LocalCyService.swift:322` | func | `removeRequest` | `private func removeRequest(requestID: UUID) throws {` |
| `ios/AgentCy/Services/MCPBridgeService.swift:616` | prop | `sourceOfTruth` | `let sourceOfTruth: String?` |
| `ios/AgentCy/Services/MCPBridgeService.swift:617` | prop | `syncDirection` | `let syncDirection: String?` |
| `ios/AgentCy/Services/MCPBridgeService.swift:618` | prop | `externalWritesRequireApproval` | `let externalWritesRequireApproval: Bool?` |
| `ios/AgentCy/Services/RecurringPostSchedule.swift:815` | func | `isPartOfSeries` | `static func isPartOfSeries(_ output: PlatformOutput) -> Bool {` |
| `ios/AgentCy/Services/RecurringPostSchedule.swift:939` | enum | `RecurringPostMaterializer` | `enum RecurringPostMaterializer {` |
| `ios/AgentCy/Services/RecurringPostSchedule.swift:940` | func | `createFutureOccurrences` | `static func createFutureOccurrences(` |
| `ios/AgentCy/Services/VoiceSparkRecordingStore.swift:154` | func | `updateTranscript` | `static func updateTranscript(` |
| `ios/AgentCy/ViewModels/AppModel.swift:659` | func | `voiceExampleDrafts` | `func voiceExampleDrafts(context: ModelContext) -> [VoiceExampleDraft] {` |
| `ios/AgentCy/ViewModels/AppModel.swift:838` | func | `isVoiceProfileStale` | `func isVoiceProfileStale(_ voiceProfile: VoiceProfile, context: ModelContext) -> Bool {` |
| `ios/AgentCy/ViewModels/AppModel.swift:2912` | func | `noteManualDevelopment` | `func noteManualDevelopment(of brief: CreativeBrief, context: ModelContext) {` |
| `ios/AgentCy/ViewModels/AppModel.swift:3846` | func | `createRepurposedSpark` | `func createRepurposedSpark(from brief: CreativeBrief, context: ModelContext) -> CreativeBrief? {` |
| `ios/AgentCy/ViewModels/AppModel.swift:3885` | func | `proposedPillars` | `func proposedPillars(context: ModelContext) -> [Pillar] {` |
| `ios/AgentCy/ViewModels/AppModel.swift:3900` | func | `acceptPillar` | `func acceptPillar(_ proposal: Pillar, context: ModelContext) {` |
| `ios/AgentCy/ViewModels/AppModel.swift:3936` | func | `ensureCurrentWeek` | `func ensureCurrentWeek(context: ModelContext) -> WeekPlan {` |
| `ios/AgentCy/ViewModels/AppModel.swift:3940` | func | `saveWeekToTemplate` | `func saveWeekToTemplate(_ plan: WeekPlan, context: ModelContext) {` |
| `ios/AgentCy/ViewModels/AppModel.swift:4320` | func | `addPublishingOutput` | `func addPublishingOutput(` |
| `ios/AgentCy/Views/Agenda/AgendaView.swift:2254` | prop | `needsRescheduling` | `var needsRescheduling: Bool {` |
| `ios/AgentCy/Views/Capture/CreatorSessionView.swift:1340` | prop | `fullScreenTimerContentWidth` | `private var fullScreenTimerContentWidth: CGFloat {` |
| `ios/AgentCy/Views/Capture/QuickCaptureView.swift:988` | prop | `cyIdeaPrompt` | `private var cyIdeaPrompt: some View {` |
| `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1539` | func | `lockedTaskValue` | `private func lockedTaskValue(label: String, value: String) -> some View {` |
| `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1691` | prop | `headerTitle` | `private var headerTitle: String {` |
| `ios/AgentCy/Views/Capture/QuickCaptureView.swift:1700` | prop | `headerSubtitle` | `private var headerSubtitle: String {` |
| `ios/AgentCy/Views/Pillars/PillarsView.swift:2298` | struct | `PillarMetrics` | `private struct PillarMetrics {` |
| `ios/AgentCy/Views/Pillars/PillarsView.swift:2313` | prop | `postedCount` | `var postedCount: Int {` |
| `ios/AgentCy/Views/Pillars/PillarsView.swift:2330` | case | `terracotta` | `case terracotta = "9B3A2E"` |
| `ios/AgentCy/Views/Pillars/PillarsView.swift:2331` | case | `ochre` | `case ochre = "B47724"` |
| `ios/AgentCy/Views/Pillars/PillarsView.swift:2334` | case | `plum` | `case plum = "76506F"` |
| `ios/AgentCy/Views/Settings/MCPDesktopReviewView.swift:666` | prop | `editingPayloadBinding` | `private var editingPayloadBinding: Binding<MCPBridgeRequestPayload>? {` |
| `ios/AgentCy/Views/Shared/VoiceRecordingDetailPage.swift:208` | prop | `transferRepresentation` | `static var transferRepresentation: some TransferRepresentation {` |
| `ios/AgentCy/Views/Shell/DesktopAppShellView.swift:1559` | func | `openCy` | `private func openCy() {` |
| `ios/AgentCy/Views/Tasks/TasksView.swift:2463` | func | `textFieldDidBeginEditing` | `func textFieldDidBeginEditing(_ textField: UITextField) {` |
| `ios/AgentCy/Views/Tasks/TasksView.swift:2467` | func | `textFieldDidEndEditing` | `func textFieldDidEndEditing(_ textField: UITextField) {` |
| `ios/AgentCy/Views/Tasks/TasksView.swift:2471` | func | `textFieldShouldReturn` | `func textFieldShouldReturn(_ textField: UITextField) -> Bool {` |
| `ios/AgentCy/Views/Today/TodayView.swift:4` | struct | `TodayView` | `struct TodayView: View {` |
| `ios/AgentCyWidgets/AgentCyWidgets.swift:14` | prop | `caseDisplayRepresentations` | `static let caseDisplayRepresentations: [WidgetTaskLane: DisplayRepresentation] = [` |
| `ios/AgentCyWidgets/AgentCyWidgets.swift:33` | func | `getSnapshot` | `func getSnapshot(in context: Context, completion: @escaping (AgentCyWidgetEntry) -> Void) {` |
| `ios/AgentCyWidgets/AgentCyWidgets.swift:40` | func | `getTimeline` | `func getTimeline(in context: Context, completion: @escaping (Timeline<AgentCyWidgetEntry>) -> Void) {` |
| `ios/AgentCyWidgets/AgentCyWidgets.swift:234` | struct | `AgentCyWidgetBundle` | `struct AgentCyWidgetBundle: WidgetBundle {` |
| `ios/AgentCyWidgets/CreatorSessionLiveActivity.swift:85` | struct | `CreatorSessionActivityWidget` | `struct CreatorSessionActivityWidget: Widget {` |
