# PAGE-PLAN-03 · Post search · Audit record

Audited 2026-08-21 against the current working tree. Workspace and archived
scoping, broken links, searchable fields, ordering, empty/no-match states,
canonical detail routing, query ownership, and per-keystroke work were traced
separately.

## Contract under test

Post search finds active posts in the current workspace by creator-facing post
text, pillar, configured destination/format, or platform. Empty query shows all
eligible posts; a non-match explains how to recover. Archived, foreign, and
broken-linked records never appear. Selecting a result opens that exact output's
canonical detail without rewriting plan state.

## Evidence

| Check | Result |
| --- | --- |
| Active-workspace output remains; archived, foreign, and broken links are removed | Pass (new focused regression) |
| Configured format and raw platform remain searchable when destination exists | Pass (new focused regression) |
| Explicit preview route/query require their own arguments | Pass (new focused regression) |
| PAGE-MAIN-02 / PAGE-PLAN-02 / PAGE-PLAN-03 focused suite | 21 tests, 0 failures on iPhone 17 Pro / iOS 26.5 simulator |
| App plus embedded extensions build | Pass through focused test build |
| `AgentCy Desktop` Mac Catalyst build | Pass; existing frame-extraction deprecation warning is outside this page |
| All-posts, matching-query, and no-match phone states | Pass |
| Result destination | Pass structurally: exact `brief` and `output` route to `PostOutputDetailView` |

## Findings

1. `SEARCH-PLAN-03-01` — **Fixed**: when an output had a destination, search
   indexed only that display label. Its configured format and raw platform were
   silently lost, so valid creator queries returned no result. Search now keeps
   destination, format, and platform as independent searchable fields while the
   card retains its concise destination-first metadata.
2. `PERF-PLAN-03-01` — **Fixed deterministically, profiling still open**: the
   view recomputed `results` for count, emptiness, and row iteration. Every pass
   rebuilt workspace subsets and then linearly searched briefs, pillars,
   destinations, and formats for every output. One projection now resolves the
   workspace once, builds duplicate-safe indexes once, filters once, and hands
   the same result array to the complete body.
3. `SCOPE-PLAN-03-01` — **Pass**: archived briefs, foreign-workspace records,
   output records whose brief is missing, and archived pillars do not leak.
   An archived pillar leaves an otherwise valid post visibly `Unfiled` rather
   than hiding the post.
4. `ORDER-PLAN-03-01` — **Improved**: target date or brief update remains the
   primary descending sort. Output creation time and stable identity now break
   ties, preventing row order from jumping between redraws.
5. `GAP-PLAN-03-01` — **Open**: the truly empty-store state, interactive clear,
   close, result tap, VoiceOver, accessibility text sizes, Catalyst interaction,
   and Release-device typing traces remain.

## Performance and smoothness

This compact page still observes six whole-table SwiftData queries. The fixed
projection changes the former repeated output-by-brief linear scans into one
indexed pass, but live search intentionally rescans eligible text after every
keystroke. A production-sized Release trace should measure keystroke-to-result
latency, allocation volume from joined search text, body invalidations from the
six observed tables, scroll frame cadence, and whether predicate-backed fetches
or a cached normalized search index become necessary.

## Classification and next gate

PAGE-PLAN-03 closes as `Confirmed defect (fixed)` + `Coverage gap`. The next
page is PAGE-PLAN-04 (Schedule existing work).
