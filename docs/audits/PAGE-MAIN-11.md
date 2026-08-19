# PAGE-MAIN-11 Audit: Cy transcript

- Audit date: 2026-08-19
- Status: `Coverage gap` — no reproduced defects; recorded gaps remain
- Scope owner: `CyConversationTranscriptView` in [`AskCyView.swift`](../../ios/AgentCy/Views/Cy/AskCyView.swift), reached from the conversation-history sheet
- Evidence: [`docs/audits/evidence/PAGE-MAIN-11/`](evidence/PAGE-MAIN-11/)

## Frozen contract

The transcript is a read-only view of one historical thread: title, date/count metadata, message list, and a single primary exit — "Return to conversation" for the current thread, "Continue conversation" for another (which makes it current). It must never start a generation or mutate messages; the only mutation it can trigger is the confirmed, permanent delete owned by PAGE-MAIN-10.

| State | Expected behavior |
| --- | --- |
| Empty thread | "No messages were saved in this conversation." with the primary exit. |
| Populated | Messages render with the day divider and truthful count metadata. |
| Current vs other | Button title switches Return/Continue; Continue re-activates the thread. |
| Read-only | No composer or send affordance is reachable anywhere in the transcript. |

## Runtime replay record

Disposable simulator, driven replay (2026-08-19), all assertions passing: empty-thread transcript shows the honest copy (`140`); populated transcript renders the message with metadata (`141`); the composer and Send are unreachable in both states (hittability-checked — the retained Cy root keeps its composer mounted behind the sheet, so element existence alone is a false signal; recorded as a harness note). Current-thread "Return to conversation" and other-thread "Continue conversation" behavior was verified in the PAGE-MAIN-10 replay (`111`, `113`).

## Remaining runtime coverage gap

`GAP-MAIN-11-01`: long-transcript scrolling with heavy markdown, archived-thread open path, VoiceOver/accessibility sizes, Reduce Motion, and Catalyst presentation.

## Performance and smoothness

Transcript rows re-run markdown parsing per render inside a `LazyVStack`; long threads remain a `PERF-RISK-02` measurement item. No new risk recorded.

## Classification and next gate

PAGE-MAIN-11 closes as `Coverage gap` (2026-08-19) with no source changes. This completes the PAGE-MAIN family (01–11): every main-tab page now has an audit record, with all reproduced defects repaired and runtime-verified. Next page selection returns to the queue (capture/plan/work families).
