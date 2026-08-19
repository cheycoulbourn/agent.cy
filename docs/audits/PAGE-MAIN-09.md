# PAGE-MAIN-09 Audit: Activity center

- Audit date: 2026-08-18
- Status: `Coverage gap` — no reproduced defects; recorded gaps remain
- Scope owner: `NotificationActivityCenterView` in [`HomeDashboardView.swift`](../../ios/AgentCy/Views/Home/HomeDashboardView.swift) (lines ~2110–2505), presented as the shell's activity sheet from the Home bell
- Evidence: [`docs/audits/evidence/PAGE-MAIN-09/`](evidence/PAGE-MAIN-09/)

## Frozen contract

Activity shows the active workspace's notification records without changing unrelated reminders. Unread state is visible (dot, weight, bell badge); records split into a priority-sorted "Needs attention" section and "Earlier"; filters are All/Unread crossed with content (All/Posts/Tasks); Mark all read applies only to the currently content-filtered set; opening a record marks it read, dismisses the sheet, and routes to the related work; read/unread toggle and archive act on one record with real error surfaces.

| State | Expected behavior |
| --- | --- |
| Empty | Honest per-filter empty copy ("You're caught up", "Nothing unread", per-content variants). |
| Unread | Accent dot, heavier title, bell badge with count. |
| Filters | All/Unread counts truthful; content filter menu (posts/tasks). |
| Mark all read | Clears only the filtered set; bell badge clears; Unread shows "Nothing unread". |
| Row open | Marks read, dismisses, routes via `AgentNotificationRouteStore`. |
| Stale target | Route consumption owned by the shell's requested-route policy (PAGE-ROOT-06 clause). |

## Function and exit trace

| Area | Source | Exit |
| --- | --- | --- |
| Visibility | workspace scope + `AgentActivityPresentationPolicy.isVisible` (availability window, archived) | — |
| Sections | `needsAttention` (kind/read/resolved policy, priority-sorted) vs `earlier` | — |
| Row | unread dot, title/body/reason, resolved marker | open → mark read + dismiss + route |
| Context menu | Mark read/unread, Archive (destructive) | `AgentActivityCenterService` with error notices |
| Options menu | Mark all read (disabled when none unread) | — |

## Runtime replay record

Disposable simulator, `-agentCyPreviewHomeState unreadActivity` fixture, driven replay (2026-08-18), all assertions passing: bell badge showed the unread count; unread record listed under "Needs attention" (`100`); Unread filter (`101`); options menu (`102`, items render out-of-tree — coordinate-driven, same harness note as PAGE-MAIN-08); Mark all read cleared the badge and produced "Nothing unread" (`103`–`104`, verdict `105`); opening the row dismissed the sheet and routed to the seeded task (`106`).

## Remaining runtime coverage gap

- Per-record mark-unread/archive context-menu actions (out-of-tree menu; coordinate pass not yet scripted), stale-target routing, posts/tasks content filter with mixed records, VoiceOver/accessibility sizes, Catalyst popover filter, and workspace-switch replay.

## Performance and smoothness

Small surface; derived filter chains (`visibleRecords` → `contentFiltered` → sections) recompute per body pass over a whole-table record query — acceptable at notification volumes; no new PERF risk beyond the shared retained-shell context.

## Defects and classification

1. No reproduced defects; the replayed contract held throughout.
2. `GAP-MAIN-09-01` — **Open**: per-record menu actions, stale-target route, content-filter mix, accessibility, Catalyst, workspace switch.

## Classification and next gate

PAGE-MAIN-09 closes as `Coverage gap` (2026-08-18) with no source changes. Reclassify when `GAP-MAIN-09-01` replays are recorded.

## Creator feature record · 2026-08-19 · Clear all

Creator request: "give me a clear all option as well for the notifications."

- `AgentActivityRecord.clearedAt` — new optional field (CloudKit-additive). Deletion could not work here: `reconcile` re-seeds any notification whose live condition still holds (the zombie mechanism from the cross-account investigation). Clearing hides without deleting; `apply` resets `clearedAt` only when a genuinely new occurrence resets record state.
- `AgentActivityPresentationPolicy.isVisible` now takes `clearedAt`; both the sheet and the bell badge respect it.
- `AgentActivityCenterService.clearAll` marks the given records cleared and read; the options menu gains "Clear all" beside "Mark all read", scoped to the active content filter like Mark all read.
- Tests: `PageMain09Tests` +2 (visibility, clear-and-read semantics); full suite 638/0.
- Runtime replay (activityMix fixture): All 5 / Unread 3 → Clear all → All 0 / Unread 0, "You're caught up", badge gone.
