# PAGE-MAIN-10 Audit: Cy conversation history

- Audit date: 2026-08-18
- Status: `Coverage gap` — no reproduced defects; recorded gaps remain
- Scope owner: `CyConversationHistoryView` + `CyConversationTranscriptView` in [`AskCyView.swift`](../../ios/AgentCy/Views/Cy/AskCyView.swift); thread lifecycle handlers (`openThreadFromHistory`, `deleteThreadFromHistory`) on the Cy root
- Evidence: [`docs/audits/evidence/PAGE-MAIN-10/`](evidence/PAGE-MAIN-10/)

## Frozen contract

History lists the active workspace's conversation threads (workspace-scoped since the PAGE-MAIN-06 repair), newest first, with a Current marker on the open thread, honest empty copy, and per-thread transcript access. Opening a thread makes it current and returns to the conversation; deleting a thread requires confirmation, permanently removes the thread and its messages, and must never disturb a different active thread.

## Runtime replay record

Disposable simulator, driven replay (2026-08-18), all assertions passing: thread listed with Current marker (`110`); current transcript offers "Return to conversation" and lands back on the composer (`111`); two threads listed after New conversation (`112`); "Continue conversation" from the older transcript restores it as active (`113`); transcript ••• menu → Delete conversation → confirmation dialog with permanent-removal copy (`114`–`115`, coordinate-driven — menu/dialog render outside the XCUITest tree, same harness note as PAGE-MAIN-08/09); after confirming, the deleted thread vanishes from history while the active thread survives untouched (`116`–`117`).

One probe correction recorded honestly: the Current marker's accessibility label is "Current" (visually uppercased); the first run asserted the visual string.

## Remaining runtime coverage gap

`GAP-MAIN-10-01`: deleting the CURRENT thread (new-thread fallback path), delete-error surface, VoiceOver/accessibility sizes, Reduce Motion, workspace-switch while the sheet is open, and Catalyst presentation.

## Performance and smoothness

History previews filter `allMessages` per row (`messages.filter { $0.threadID == thread.id }` inside `ForEach`) — linear per row over the whole message table; acceptable at conversation counts, recorded under the PAGE-MAIN-06 `PERF-RISK-02` umbrella rather than as a new risk.

## Classification and next gate

PAGE-MAIN-10 closes as `Coverage gap` (2026-08-18) with no source changes. Transcript read-only behavior doubles as initial PAGE-MAIN-11 evidence (`111`, `113`). Reclassify when `GAP-MAIN-10-01` replays are recorded.
