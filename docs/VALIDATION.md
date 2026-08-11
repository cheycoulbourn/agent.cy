# Validation Protocol

## Cohort

- Founder plus five eligible external creators.
- Four consecutive weeks.
- External testers receive a four-week promotional TestFlight entitlement.
- An informational paywall appears on day 14; no TestFlight purchase is treated as real revenue.

## Eligibility

- Adult English-speaking solo creator.
- Already publishes short-form content.
- Can provide three genuine voice examples during onboarding or later in the study.
- Agrees to content-free behavioral telemetry for the formal study.

## Success

At least four of five external creators must:

- Be active in three of four weeks.
- Create at least three briefs.

Across the cohort, at least 60 percent of briefs must reach `recording_completed` or Posted.

## Hard rethink gate

Revisit the product wedge before adding features if:

- Fewer than three testers return in week three, or
- Fewer than 40 percent of briefs reach recording or Posted.

## Instrumentation

Allowed events include onboarding steps, voice-example completion, app-open day, AI operation outcome, proposal accept/edit/dismiss, lifecycle transition, recording milestone, output posted, error class, paywall view, trial intent, and entitlement state.

No event may contain creator text, prompts, generated content, captions, URLs, or pillar names.

## Link-first inspiration validation

On a signed physical-device build, verify Instagram, TikTok, YouTube/Shorts, Safari, and Notes. Record the exact `NSItemProvider` representations each host supplies. Confirm Photos movie shares remain unsupported, capture works offline, duplicate imports create no extra source or Spark, and the extension performs no network request.

Inspect a saved-post shaping request and content-free logs to prove the URL, hostname, thumbnail bytes, temporary video, tags, and credentials never enter AI requests, logs, or telemetry. Confirm that only the declared device-derived title, caption, transcript, visual observations, analyzed-input markers, duration, and creator context enter the AI request. Verify VoiceOver, Accessibility Extra Extra Extra Large, Reduce Motion, speech-permission denial, low storage, extension termination, app restart, privacy erase, and workspace reset.

## Paid pilot

After behavioral validation and App Store release readiness, recruit five new eligible creators. Each receives the first free brief, then a 14-day trial that renews at $8.99 per month.
