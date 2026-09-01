# Agent.cy App Behavior Map

This document is the durable behavior contract behind the [App Behavior Map in Paper](https://app.paper.design/file/01KZXJTBBVJ33MD84G0HKB2HRX/1F-0). Paper is the visual index. This file records intended outcomes, current implementation owners, state boundaries, evidence, and unresolved drift. The exhaustive atomic surface inventory and one-page-at-a-time review protocol live in the [Page Contract Ledger](APP_PAGE_CONTRACTS.md).

## How to read the map

### Source hierarchy

1. Product contract: accepted product decisions, [PRD](PRD.md), and accepted [ADRs](adr/).
2. Design contract: the active Paper file, [Paper implementation guide](PAPER_IMPLEMENTATION.md), and repository design tokens.
3. Implementation: route enums, SwiftUI entry views, state owners, services, persistence, TypeScript contracts, and server handlers.
4. Evidence: automated tests plus a dated simulator, device, or live-system replay.

When sources disagree, the map shows both and records `Drift`. Drift is not automatically a defect. A failure becomes `Confirmed defect` only after the intended contract is resolved and the behavior is reproduced.

### Evidence badges

| Badge | Meaning |
| --- | --- |
| `C` | A governing product or design contract was found. |
| `B` | The current implementation path was traced. |
| `T` | Automated coverage was found. This does not prove the test currently passes. |
| `V` | The complete behavior was replayed and verified in the current audit cycle. |
| `Δ` | Sources conflict or a product decision remains open. |
| `Hidden` | Code remains present but the feature is intentionally unavailable. |
| `Deferred` | The capability is explicitly outside the current product boundary. |

## Stable contract identifiers

Paper, this document, the audit queue, regression tests, and future issues use the same identifiers:

- `ROOT-*`: launch, identity, account restoration, and workspace selection.
- `NAV-*`: primary platform navigation, overlays, settings targets, and deep links.
- `FLOW-*`: user journeys and lifecycle behavior.
- `DATA-*`: persistence owners and synchronization boundaries.
- `SYS-*`: extension, widget, local bridge, server, and external-service boundaries.
- `AUD-*`: bounded review programs in [APP_AUDIT_QUEUE.md](APP_AUDIT_QUEUE.md).

## Product topology

### Root and platform selection

| ID | Surface | Intended outcome | Entry and exit | Required states | Current owner | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| `ROOT-01` | Launch resolution | Never show invitation or onboarding before stored credential/account state resolves. | `RootDestination`: `launch`, `accountAccess`, `restoringAccount`, `onboarding`, or `app`. | unresolved, credential missing, profile missing, linked profile restoring, ready | [`RootView`](../ios/AgentCy/App/RootView.swift) | `C B T` |
| `ROOT-02` | Account access | Redeem or recover an authorized installation without exposing creator content. | Root gate → invitation/account controls → root resolution. | idle, redeeming, invalid/used invitation, offline, linked | [`AppleAccountAccessView`](../ios/AgentCy/Views/Account/AppleAccountAccessView.swift) | `C B T` |
| `ROOT-03` | Onboarding | Create the minimum local creator profile and enter the workspace without requiring optional integrations. | Root gate → eight steps → app shell. | new, partial, validation error, optional steps skipped, complete | [`OnboardingView`](../ios/AgentCy/Views/Onboarding/OnboardingView.swift) | `C B T` |
| `ROOT-04` | Account restoration | Wait for a linked account's private synced profile instead of starting a second profile. | Root gate → restoring → app shell or recoverable failure. | waiting, restored, offline, unavailable | [`RootView`](../ios/AgentCy/App/RootView.swift) | `C B T` |
| `ROOT-05` | Active workspace | Scope every creator-owned record and reset route stacks when the workspace changes. | Root/app settings → selected workspace → platform shell. | default, switched, delayed legacy record, no active workspace | [`AppModel`](../ios/AgentCy/ViewModels/AppModel.swift) | `C B T` |

### Primary navigation

The canonical iPhone information architecture exposes six persistent tab stacks: Home, Plan, Tasks, Pillars, Idea Bank, and Cy. The maintained internal Catalyst shell adds Feed and Saved Posts as independent sidebar destinations but remains outside the v1 customer shipping promise under ADR 0012. The older five-tab Paper guide was corrected on 2026-08-18.

| ID | Surface | Intended outcome | Main exits | Current owner | Evidence |
| --- | --- | --- | --- | --- | --- |
| `NAV-M01` | Home | Give the creator a warm daily launch: focus, content going live, tasks, and quick capture. | Creation Hub, post/task detail, settings, other tabs. | [`HomeDashboardView`](../ios/AgentCy/Views/Home/HomeDashboardView.swift) | `C B T` |
| `NAV-M02` | Plan / Agenda | Place posts by output target date and show production tasks separately by day/week. | Day agenda, scheduling picker, post detail, task detail, Feed. | [`PlanView`](../ios/AgentCy/Views/Plan/PlanView.swift), [`AgendaView`](../ios/AgentCy/Views/Agenda/AgendaView.swift) | `C B T Δ` |
| `NAV-M03` | Tasks | Show all top-level brief-linked and standalone creator work with independent completion. | Task detail, parent/subtask editing, deletion, linked post. | [`TasksView`](../ios/AgentCy/Views/Tasks/TasksView.swift) | `C B T` |
| `NAV-M04` | Pillars | Manage one active anchor plus supporting branches and browse their ideas/work. | Pillar detail, idea detail, post detail, new pillar. | [`PillarsView`](../ios/AgentCy/Views/Pillars/PillarsView.swift) | `C B T` |
| `NAV-M05` | Idea Bank | Search/filter creator work, create new work, and open Saved Posts. | Idea detail, Saved Posts, Find three ideas, Creation Hub. | [`IdeaBankView`](../ios/AgentCy/Views/Ideas/IdeaBankView.swift) | `C B T Δ` |
| `NAV-M06` | Cy | Hold global context-aware conversation and display explicit proposals. | Referenced brief, Create this post, proposal review, close/other tabs. | [`AskCyView`](../ios/AgentCy/Views/Cy/AskCyView.swift) | `C B T` |
| `NAV-D01` | Desktop shell | Provide a maintained internal pre-release planning surface with sidebar navigation, center workspace, and optional utility rail. Catalyst is excluded from the v1 customer shipping promise. | Home, Agenda, Feed, Tasks, Pillars, Idea Bank, Saved Posts, Cy sheet. | [`DesktopAppShellView`](../ios/AgentCy/Views/Shell/DesktopAppShellView.swift) | `C B T` |
| `NAV-D02` | Feed | Show the manual social-grid view and open individual posts. | Post detail, filter/account selection. | [`SocialGridView`](../ios/AgentCy/Views/Feed/SocialGridView.swift) | `B T Δ` |
| `NAV-D03` | Saved Posts | Browse imported inspiration scoped to the active workspace. | Saved Post detail, shape idea, deletion. | [`SavedPostsLibraryView`](../ios/AgentCy/Views/Ideas/SavedPostsLibraryView.swift) | `C B T` |

### Global overlays and detail surfaces

| ID | Surface | Purpose and exits | Required states | Evidence |
| --- | --- | --- | --- | --- |
| `NAV-O01` | Creation Hub | Choose Idea, Post, Task, or Cy ideation without mutating content before selection. | available modes, expired access, dismissed | `C B T` |
| `NAV-O02` | Quick Capture | Create one idea, lightweight post, or task with explicit optional context. | blank, validating, saving, recoverable error, saved | `C B T` |
| `NAV-O03` | Voice Spark | Record locally, recover from permission/storage/interruption states, and hand off text. | permission unknown/denied, recording, paused, saved, failed | `C B T` |
| `NAV-O04` | Settings | Navigate profile, assistance, appearance, destinations/accounts, voice, notifications, calendar, access, export, reset, erase, and bridge setup. | available, access-limited, disconnected integration, destructive confirmation | `C B T` |
| `NAV-O05` | Weekly Focus | Configure a flexible weekly focus without punitive overdue behavior. | empty, configured, editing, current week, changed week | `C B T` |
| `NAV-O06` | Task detail | Edit one top-level task and its independently completable subtasks. | standalone, linked, recurring, completed, deleted | `C B T` |
| `NAV-O07` | Pillar detail | Edit anchor/branch properties and browse ideas, scheduled, and posted work. | anchor, branch, missing parent fallback, archived | `C B T` |
| `NAV-O08` | Idea detail | Edit a Spark, develop it, schedule a lightweight post, or archive it. | Spark, Developing, Ready, archived, expired access | `C B T` |
| `NAV-O09` | Post detail/editor | Edit the master brief, platform outputs, tasks, series, media, target dates, and posting progress. | Spark through Archived, unsaved changes, output-specific state, recoverable service error | `C B T` |
| `NAV-O10` | Saved Post detail | Show safe imported source metadata and shape one original idea without false viewing claims. | imported, analyzing, analyzed, duplicate, failed, deleted | `C B T` |
| `NAV-O11` | Brand Cabinet | Manage local partnership references and link relevant briefs. | empty, partner, contact/activity editor, linked post | `B T Δ` |
| `NAV-O12` | Creator Session | Run a local creation timer and optional Live Activity without affecting content state. | disabled, active, paused, completed, restored | `B T Hidden` |
| `NAV-O13` | Series review | Review series, episode roster/detail/revision, and atomic bundle approval. | proposed, revised, partially selected, approved, denied | `B T Δ` |

### External entries and requested destinations

| ID | Entry | Route contract | Expected result | Evidence |
| --- | --- | --- | --- | --- |
| `NAV-E01` | Widget / URL | `today`, `agenda(day)`, `tasks`, `pillars`, `ideaBank`, `brief(id)` | Clear stale route state, select the correct tab, and open the requested day/object. | `B T` |
| `NAV-E02` | Quick deep link | `quickIdea`, `quickPost`, `quickTask` | Reset capture context and open the requested mode. | `B T` |
| `NAV-E03` | Phone feature route store | `voiceSpark` is active; `creatorSession` remains a reserved disabled case | Consume Voice Spark after app activation; ignore Creator Session while its availability gate is off. | `B T Δ` |
| `NAV-E04` | Notification | day, week, Cy week, brief, draft, task, access, MCP review | Select the correct surface and preserve the requested object/mode. | `B T` |
| `NAV-E05` | Requested settings | notifications, access, MCP bridge, switch account, add account | Open Settings and push the requested destination once. | `B T` |
| `NAV-E06` | Share Extension | one HTTPS URL or URL-bearing text | Atomically queue one bounded envelope; import once after a SwiftData commit. | `C B T` |

## Core journey contracts

### `FLOW-01`: Capture to accepted brief

Inputs converge on one creator-owned direction:

- Quick Idea creates a text Spark.
- Quick Post creates a lightweight Spark-backed post without advancing the lifecycle.
- Voice Spark stores/transcribes locally and hands text into capture/development.
- A shared HTTPS link creates a safe Saved Post, then one editable original idea.
- Find three ideas produces three temporary Cy directions; only an explicitly saved direction persists.

First substantive development enters `Developing`. Cy dialogue is capped at eight turns and keeps Compose now available. Generated content remains a proposal with Accept, Edit, and Dismiss. Acceptance creates or updates one complete editable `CreativeBrief`; structured proposal fields must not collapse to title-only fallback data.

### `FLOW-02`: Master and output lifecycle

`Spark → Developing → Ready → Scheduled → Posted → Archived`

- Creator acceptance enters Ready.
- A target date on a selected `PlatformOutput` enters Scheduled.
- The first Posted output enters Posted and displays `x of y posted`.
- Removing the final Posted state returns to Scheduled when a target remains, otherwise Ready.
- Archive is manual.
- CreatorTask completion never silently changes the master lifecycle.

### `FLOW-03`: Plan to publish

- `CreativeBrief`/`PlatformOutput` own content placement on Agenda.
- `CreatorTask` owns production scheduling, priority, lane, and completion.
- Missed targets require an explicit Move, Pause, or Archive choice.
- EventKit receives a one-way projection for scheduled/posted outputs and dated top-level tasks.
- Notifications and widgets route into the same canonical app state; they do not own content.
- Publishing remains manual. Each output independently owns target date, status, account, caption adjustments, URL, and deletion.

### `FLOW-04`: Identity, access, and AI setup

- Onboarding uses Welcome, About you, Your vibe, Your content, Where you post, Your AI, Notifications, and Ready.
- Installation identity is device-specific; Sign in with Apple is an optional service identity.
- Agent Cy AI uses request-scoped server calls. Claude/Codex uses a creator-selected local folder and MCP bridge.
- Both paths keep generated mutations pending until explicit creator approval.
- Expired access blocks new work and new Cy operations while preserving editing/completion/export/erase for existing content.

## Data and service boundaries

| ID | Owner | May contain | May not contain / do | Flow |
| --- | --- | --- | --- | --- |
| `DATA-LOCAL` | SwiftData | Creator profiles/workspaces, briefs, outputs, tasks, pillars, ideas, inspiration, conversations, settings records. | Cross-workspace leakage or destructive migration. | SwiftUI/AppModel ↔ services ↔ SwiftData. |
| `DATA-SYNC` | Private CloudKit | Creator-owned records mirrored from the shipping schema. | Public/shared creator content or destructive schema evolution. | SwiftData ↔ private CloudKit. |
| `DATA-DEVICE` | App Group/UserDefaults/Keychain | Import envelopes, widget snapshots/intents, device preferences, installation credential. | Full creator database, AI credentials, or unbounded attachments. | Extension/widget/intent ↔ main app. |
| `DATA-CALENDAR` | EventKit + device preferences | Selected calendar ID and projected events. | Reverse mutation of creator data from calendar edits. | Agent.cy → EventKit. |
| `SYS-MCP` | Selected Files folder + local stdio server | Versioned content snapshot and narrowly scoped queued proposals. | Attachments, credentials, deletion, publish, archive, erase, or raw database access. | App → snapshot → MCP → pending review → explicit approval. |
| `SYS-REMOTE` | Fastify proxy | Hashed identity, access/quota state, schemas/prompts, content-free telemetry, request-scoped creator text. | Durable creator-content storage. | App → HTTPS/SSE → validated Anthropic result → visible proposal. |

## Drift register

| ID | Conflict | Evidence | Decision required |
| --- | --- | --- | --- |
| `DRIFT-01` | **Resolved 2026-08-18:** Catalyst is an actively maintained internal pre-release surface, excluded from the iPhone-only v1 customer shipping promise. | [ADR 0012](adr/0012-catalyst-maintained-internal-scope.md), [PRD](PRD.md), [`RootView`](../ios/AgentCy/App/RootView.swift), [`DesktopNavigation`](../ios/AgentCy/Models/DesktopNavigation.swift) | Desktop correctness and isolation remain maintained; customer launch or parity requires a later product decision. |
| `DRIFT-02` | **Resolved 2026-08-18:** the canonical phone IA is Home, Plan, Tasks, Pillars, Idea Bank, and Cy. Feed and Saved Posts remain desktop destinations owned by the Catalyst contract. | [Paper guide](PAPER_IMPLEMENTATION.md), [`AppTab`](../ios/AgentCy/Models/DomainTypes.swift), [`AppShellView`](../ios/AgentCy/Views/Shell/AppShellView.swift) | Decision recorded in the behavior map, page ledger, and Paper guide. |
| `DRIFT-03` | The Paper guide links to a different Paper file than the active design-system file used by this map. | [Paper guide](PAPER_IMPLEMENTATION.md), [active Paper file](https://app.paper.design/file/01KZXJTBBVJ33MD84G0HKB2HRX/1F-0) | Confirm the canonical Paper file before editing the guide. |
| `DRIFT-04` | Brand-deal management is deferred in the PRD, while Brand Cabinet is implemented and designed. | [PRD](PRD.md), [`BrandCabinetView`](../ios/AgentCy/Views/Brands/BrandCabinetView.swift) | Define whether the cabinet is in scope, experimental, or hidden. |
| `DRIFT-05` | Creator Session code, deep links, widgets, and Live Activity remain present while centralized availability currently hides the feature. | [`CreatorSessionView`](../ios/AgentCy/Views/Capture/CreatorSessionView.swift), [`PhoneFeatureLaunchIntent`](../ios/AgentCyShared/PhoneFeatureLaunchIntent.swift) | Keep `Hidden`, remove later, or return it through a separately approved redesign. |
| `DRIFT-06` | Series review artboards and implementation exist without a settled product boundary in the current PRD. | Active Paper Mobile App page and series code in the brief editor | Define current, experimental, or deferred status before behavioral QA. |

## Maintenance protocol

1. Resolve product drift before filing behavior defects against the affected surface.
2. Audit one surface family or journey at a time; trace every state mutation in that call path.
3. Record reproduction evidence and add an externally observable regression test before patching.
4. Update this contract, Paper, and [APP_AUDIT_QUEUE.md](APP_AUDIT_QUEUE.md) together when a decision changes behavior.
5. Mark `V` only with a dated runtime replay; a passing helper test is insufficient for view lifecycle, navigation, or persistence claims.
