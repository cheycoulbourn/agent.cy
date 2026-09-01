# PAGE-WORK-01 · Idea draft · Audit record

Audited 2026-08-24 against the current working tree. Spark/Developing,
new/existing content, unsaved back/save, invalid title, archive, finalized stale
route, expired access, output handoff, persistence failure, and typing-work paths
were traced separately.

## Contract under test

Idea Draft edits one saved Spark without turning it into a post as a side effect.
Title, thought, and pillar stay local while typing. Save and Back persist valid
changes once; failure keeps the creator on the page with the draft intact.
Archive is explicit and atomic. Build with Cy may read an existing output for
context but does not create one. Turn into a post is the only action on this
page that may create the first `PlatformOutput` and hand off to PAGE-WORK-02.
Archived work is read-only, finalized work does not reopen as an idea, and
expired access retains existing editing while blocking new planning/Cy work.

## Evidence

| Check | Result |
| --- | --- |
| Idea form uses creator-visible notes with premise fallback | Pass (new focused regression) |
| Save changes only title/thought/pillar and preserves lifecycle, placement, and dates | Pass (new focused regression) |
| Invalid and injected failed saves leave the stored idea unchanged | Pass (new focused regression) |
| Archive commits form + lifecycle together and restores all fields on failure | Pass (new focused regression) |
| Spark/Developing, finalized, and archived route states stay separate | Pass (new focused regression) |
| Expired access retains existing edits but blocks schedule/dialogue/compose | Pass (new focused regression) |
| Existing scheduled output is returned without status or brief mutation | Pass; watched fail before repair |
| Explicit Idea Draft replay requires its own launch argument | Pass (new focused regression) |
| PAGE-WORK-01 plus capture, Idea Bank, planning, domain, inspiration-lifecycle, and root-routing regressions | 250 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through the combined test build |
| `AgentCy Desktop` Mac Catalyst build | Pass |
| Phone editor | Pass: back/options, title, thought, scoped pillar, Build with Cy, and post handoff render in [`idea-draft.png`](evidence/PAGE-WORK-01/idea-draft.png) |

## Findings

1. `BOUNDARY-WORK-01-01` — **Fixed**: opening an idea immediately created a
   platform output and rendered the 4,800-line PAGE-WORK-02 editor. Viewing a
   Spark therefore mutated its data model before the creator chose a post
   workflow. Idea Draft is now a bounded title/thought/pillar editor. Output
   creation occurs only behind Turn into a post.
2. `LIFECYCLE-WORK-01-01` — **Fixed**: `ensurePostDraft` forced any existing
   output to `.draft`, including scheduled/ready output reached through a stale
   route. It now returns existing output unchanged. Fetch failure returns a
   truthful error without inserting a possible duplicate.
3. `SAVE-WORK-01-01` — **Fixed**: the previous editor mutated live SwiftData
   fields while typing, saved again from `onDisappear`, swallowed save errors,
   and could close with an invalid blank title. The page now buffers a value
   form, owns Back, validates before dismissal, performs one explicit save, and
   restores the stored object after any persistence failure.
4. `ARCHIVE-WORK-01-01` — **Fixed**: the mapped Idea Draft contract had no
   archive action; only permanent post deletion was exposed through the reused
   post editor. Idea Draft now confirms Archive and commits edited idea fields
   plus archived lifecycle/history as one recoverable mutation.
5. `ROUTE-WORK-01-01` — **Fixed**: archived and finalized briefs could enter a
   mutable post editor or an indefinite creation-retry state. Spark/Developing,
   finalized, and archived statuses now have explicit editor, post, and
   read-only destinations. No route resurrects archived work.
6. `ACCESS-WORK-01-01` — **Pinned**: expired access continues to permit edits
   and archive of existing work. New scheduling and hosted Cy generation remain
   unavailable. Build with Cy can still open so an existing conversation is
   readable; its dialogue/compose service boundary enforces entitlement.
7. `ATOMIC-WORK-01-01` — **Fixed**: failed first-output creation deleted the
   inserted output but left notes, duration, and updated time changed in memory.
   Those brief fields are now restored on failure, so a later unrelated save
   cannot persist a handoff the page reported as failed.
8. `PERF-WORK-01-01` — **Fixed structurally**: Idea Draft previously inherited
   eleven live model collections, media preview work, thumbnail hydration,
   keyboard notifications, and the entire post form. It now has zero `@Query`
   collections and no media/network/background work. Pillars, workspaces, and
   one optional output are fetched once on entry; keystrokes update local state
   only. PAGE-WORK-02 retains its separate performance risk.
9. `GAP-WORK-01-01` — **Open**: driven taps through save/back/archive/build/post
   handoffs, a real failing SwiftData store rather than injected persistence,
   stale finalized/archived phone fixtures, VoiceOver, additional accessibility
   text sizes, Catalyst pointer/keyboard interaction, and Release-device typing
   and handoff latency remain.

## Performance and smoothness

The repaired page no longer constructs the post editor or subscribes to any
live collection while the creator types. One entry load performs bounded
pillar/workspace/output fetches; archived state performs none. Save/archive
refresh widgets once, and only the explicit post handoff creates an output.
Debug phone scrolling showed no visible stall. Release profiling should still
measure first-entry fetches with production-sized stores, TextEditor body
updates, keyboard transitions, widget-refresh latency, and the PAGE-WORK-02
handoff separately.

## Classification and next gate

PAGE-WORK-01 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-WORK-02 (Resumable post editor), beginning with contract validation
while preserving the one-page-at-a-time audit boundary.
