# Prompt and Contract Rules

## Model policy

- Production model is pinned to `claude-sonnet-5` on the server.
- Idea, voice, and dialogue operations use low effort.
- Brief, revision, rhythm, and task proposals use medium effort.
- There is no silent model fallback.
- Prompts must never claim live trend, algorithm, or virality knowledge.

## Assistance semantics

- Drive waits for explicit instructions and asks before meaningful assumptions.
- Collaborate infers low-risk facts and asks the single highest-value missing question.
- Lead minimizes questions, makes visible assumptions, and returns a complete proposal.
- Every mode requires creator acceptance before persistence.

## Required operations

- Voice profile extraction or update.
- Three idea directions.
- Spark dialogue turn.
- Ready brief composition.
- Scoped brief revision.
- Global chat turn.
- Rhythm proposal.
- Task proposal.

## Contract invariants

- All input and output schemas are versioned.
- The canonical schema source is Zod.
- Swift fixtures decode every canonical result.
- Dialogue returns a full working-state snapshot, not a patch.
- Brief variants contain differences from the master, not duplicate scripts.
- Refusal, max-token, quota, timeout, cancellation, and invalid-generation paths return stable error codes.
- The server does not emit a result until the complete structured payload validates.
- `revisionNumber` is a monotonic request ordinal. The entitlement layer, not the result schema, enforces the three-revision free allowance.
- A scoped revision must retain the brief ID and selected platform set, include the requested scope in `changedFields`, and return a valid recording-milestone shape.
- Teach Cy requires a specific `teachingInstruction`, the currently approved canonical profile, and a result that materially differs from that profile.
- Creator examples carry a confirmed source label: typed text, text from a public post, or screenshot-derived text. Only confirmed text reaches the proxy. Prompts never claim to fetch a post, open a URL, or inspect an image.
- Initial voice-profile extraction requires three confirmed examples, but other creation operations accept an empty example list so examples can be deferred.
- Revision and Teach Cy results are staged locally. Counters settle only after a validated proposal is persisted, and acceptance rejects stale source versions or creator edits.
