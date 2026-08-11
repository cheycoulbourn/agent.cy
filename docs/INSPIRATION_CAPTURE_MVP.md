# Automatic saved-post analysis MVP

Status: implemented in the local app, contracts, proxy, Local Cy, and iOS Share Extension. Automated verification and signed physical-device installation are release gates.

## Product promise

Share a post to **agent.cy** and receive an editable, original post idea without typing.

```mermaid
flowchart LR
    A["Share a post"] --> B["Save and analyze"]
    B --> C["Analyze available video, audio, caption, visuals, and metadata"]
    C --> D["Explain the post and extract key points"]
    D --> E["Create an editable original idea"]
    E --> F["Save to Idea Bank"]
    E --> G["Tag the saved post"]
    F --> H["Develop or schedule filming"]
```

## Experience

1. The Share Extension accepts one HTTPS post link. It also captures host-supplied caption text, a video file, or a thumbnail when the source app provides those representations.
2. The extension stores the payload in the private App Group and closes. It does not run AI or fetch the post.
3. The main app imports the source, enriches supported links with public link metadata, and analyzes every available input.
4. Cy returns what the post is about, key points, reusable mechanics, originality guardrails, suggested tags, and one creator-specific idea.
5. The creator can edit the idea and tags, then explicitly saves the idea. The original post remains in **Saved Posts** with its thumbnail and source link.

No note or other typed input is required. Creating a custom tag and editing generated fields are optional.

## Input truthfulness

The host app controls which `NSItemProvider` representations the Share Extension receives. Agent.cy records the inputs it actually analyzed and displays them as Caption, Audio, Video, On-screen text, and Post details.

If the host supplies a video file, the app:

- Samples frames and classifies visual subjects.
- Reads visible on-screen text.
- Requests speech-recognition permission and transcribes the audio when authorized.
- Derives a thumbnail.
- Deletes the temporary shared video after those derived inputs are stored.

If the host supplies only a URL, the app uses official oEmbed metadata for supported TikTok and YouTube links and Apple link metadata elsewhere. It must not claim it watched the video when no video bytes were available. A source with insufficient content stays saved and shows a retryable analysis state.

Agent.cy does not use an undocumented social-video downloader, platform cookies, or a creator's social login.

## AI contract

Route: `POST /v1/ai/inspiration/shape`

- Prompt version: `inspiration-shape.v3`
- Request schema: `inspiration-shape.request.v3`
- Result schema: `inspiration-shape.result.v3`

The request includes:

- Broad source platform.
- Device-derived `sourceMaterial`: optional title, caption, transcript, visual observations, analyzed-input list, and duration.
- Existing creator context.

The request excludes the source URL, hostname, temporary video, thumbnail bytes, tags, cookies, authorization data, and social identity.

The result includes:

- Content-grounded source summary and one to four key points.
- Hook, structure, and payoff mechanics.
- One original editable idea.
- One suggested existing pillar and originality guardrails.
- Explicit assumptions.

## Persistence

`InspirationSource` stores the source URL as private provenance plus derived title, caption, transcript, visual observations, analyzed-input markers, duration, thumbnail, AI result, selected pillar, and optional linked idea/task IDs.

Legacy inspiration tag IDs remain readable for existing data, but the capture and Saved Posts interfaces use the creator's existing pillars.

The temporary video remains in the private App Group only until device analysis finishes. Privacy erase deletes saved posts, tags, queued envelopes, and staged assets.

## Validation

1. URL and caption extraction is deterministic, removes every URL from caption text, and rejects unsafe URLs.
2. Queue writes are atomic and deduplicate imports.
3. AI requests validate analyzed source material and never serialize the source URL.
4. AI results stage an editable draft without creating a `CreativeBrief`; a brief is created only after Save.
5. A suggested pillar must match an existing pillar ID from creator context or be `null`.
6. Full contracts, server, MCP, iOS, simulator, signed device build, and in-place device installation must pass.

## Platform references

- [Apple Share Extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
- [Apple extension attachment guidance](https://developer.apple.com/documentation/foundation/nsextensionitem/attachments)
- [TikTok oEmbed](https://developers.tiktok.com/doc/embed-videos/)
- [YouTube videos API](https://developers.google.com/youtube/v3/docs/videos)
