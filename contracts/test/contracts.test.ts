import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  AiSseSequenceSchema,
  AssistanceModeSchema,
  ChatTurnResultSchema,
  ComposeBriefResultSchema,
  CreatorContextSchema,
  IdeasResultSchema,
  PlatformSchema,
  PrivacyDeleteRequestSchema,
  ReviseBriefRequestSchema,
  ReviseBriefResultSchema,
  RevenueCatWebhookRequestSchema,
  RhythmProposalResultSchema,
  SparkTurnResultSchema,
  TasksProposalResultSchema,
  TelemetryEventsRequestSchema,
  VoiceProfileRequestSchema,
  VoiceProfileResultSchema,
  VoiceExampleSchema,
} from "../src/index.js";

const operationId = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";

const voiceProfile = {
  summary: "Warm, direct teaching grounded in small concrete moments.",
  tone: ["warm", "plainspoken"],
  sentenceStyle: "Short declarative sentences followed by one practical example.",
  signatureQualities: ["specific", "encouraging"],
  phrasesToUse: ["start here"],
  phrasesToAvoid: ["you must"],
  guidance: ["Prefer one concrete next move over a long checklist."],
  confidence: 0.8,
} as const;

const creatorContext = {
  name: "Maya",
  primaryGoal: "Publish two useful short-form videos each week.",
  selectedPlatforms: ["instagramReels", "tiktok", "youtubeShorts"],
  voiceExamples: [
    {
      exampleId: "33333333-3333-4333-8333-333333333331",
      order: 0,
      source: "text",
      text: "The fastest way to make this harder is to ask one post to do five jobs.",
      creatorConfirmed: true,
    },
    {
      exampleId: "33333333-3333-4333-8333-333333333332",
      order: 1,
      source: "publicPostText",
      text: "Start with the moment that made you care, then explain the lesson.",
      creatorConfirmed: true,
    },
    {
      exampleId: "33333333-3333-4333-8333-333333333333",
      order: 2,
      source: "screenshotText",
      text: "A smaller promise is often more useful because people can act on it today.",
      creatorConfirmed: true,
    },
  ],
  voiceProfile,
  pillars: [],
  librarySummaries: [],
} as const;

const metadata = {
  schemaVersion: "1",
  promptVersion: "voice-profile.v1",
  operationId,
  appBuild: "1.0.0 (1)",
  assistanceMode: "collaborate",
  creatorContext,
} as const;

function readFixture(name: string): unknown {
  return JSON.parse(
    readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"),
  ) as unknown;
}

const composeFixture = readFixture("compose-brief-result.json");

describe("wire enums", () => {
  it("accepts the exact PRD values", () => {
    expect(AssistanceModeSchema.parse("drive")).toBe("drive");
    expect(AssistanceModeSchema.parse("collaborate")).toBe("collaborate");
    expect(AssistanceModeSchema.parse("lead")).toBe("lead");
    expect(PlatformSchema.parse("instagramReels")).toBe("instagramReels");
    expect(PlatformSchema.parse("tiktok")).toBe("tiktok");
    expect(PlatformSchema.parse("youtubeShorts")).toBe("youtubeShorts");
  });

  it("rejects renamed wire values", () => {
    expect(AssistanceModeSchema.safeParse("leadMe").success).toBe(false);
    expect(PlatformSchema.safeParse("instagram_reels").success).toBe(false);
  });
});

describe("AI contracts", () => {
  it("allows creator examples to be deferred", () => {
    expect(
      CreatorContextSchema.safeParse({
        ...creatorContext,
        voiceExamples: [],
        voiceProfile: undefined,
      }).success,
    ).toBe(true);
  });

  it("requires three confirmed examples for initial voice extraction", () => {
    const request = {
      ...metadata,
      creatorContext: {
        ...creatorContext,
        voiceExamples: creatorContext.voiceExamples.slice(0, 2),
      },
      intent: "onboarding",
    };
    expect(VoiceProfileRequestSchema.safeParse(request).success).toBe(false);
  });

  it("accepts mixed confirmed text sources without accepting source artifacts", () => {
    expect(
      VoiceProfileRequestSchema.safeParse({
        ...metadata,
        intent: "onboarding",
      }).success,
    ).toBe(true);

    const example = creatorContext.voiceExamples[0];
    expect(
      VoiceExampleSchema.safeParse({ ...example, source: "unknown" }).success,
    ).toBe(false);
    expect(
      VoiceExampleSchema.safeParse({ ...example, creatorConfirmed: false }).success,
    ).toBe(false);
    expect(
      VoiceExampleSchema.safeParse({
        ...example,
        url: "https://example.com/post",
      }).success,
    ).toBe(false);
    expect(
      VoiceExampleSchema.safeParse({
        ...example,
        image: "base64-image-data",
      }).success,
    ).toBe(false);
  });

  it("limits combined creator-example text to 40 KB", () => {
    const oversizedExamples = creatorContext.voiceExamples.map(
      (example, index) => ({
        ...example,
        text: String(index).repeat(14_000),
      }),
    );
    expect(
      CreatorContextSchema.safeParse({
        ...creatorContext,
        voiceExamples: oversizedExamples,
      }).success,
    ).toBe(false);
  });

  it("requires the current profile for Teach Cy", () => {
    const { voiceProfile: _voiceProfile, ...withoutProfile } = creatorContext;
    const request = {
      ...metadata,
      creatorContext: withoutProfile,
      intent: "teachCy",
      teachingInstruction: "Keep my short sentence rhythm.",
    };
    expect(VoiceProfileRequestSchema.safeParse(request).success).toBe(false);
  });

  it("requires a specific instruction for Teach Cy", () => {
    const request = {
      ...metadata,
      intent: "teachCy",
    };
    expect(VoiceProfileRequestSchema.safeParse(request).success).toBe(false);
    expect(
      VoiceProfileRequestSchema.safeParse({
        ...request,
        teachingInstruction: "Keep my short sentence rhythm.",
      }).success,
    ).toBe(true);
  });

  it("requires exactly three idea directions", () => {
    const direction = {
      directionId: "one",
      title: "One direction",
      premise: "A focused premise.",
      opening: "A concrete opening.",
      whyItFits: "It matches the creator goal.",
      assumedTakeaway: "One useful takeaway.",
      assumptions: [],
    };
    expect(
      IdeasResultSchema.safeParse({ ideas: [direction, direction] }).success,
    ).toBe(false);
    expect(
      IdeasResultSchema.safeParse({ ideas: [direction, direction, direction] })
        .success,
    ).toBe(true);
  });

  it("returns a full spark working-state snapshot and rejects patches", () => {
    const valid = {
      assistantMessage: "The idea is ready to compose.",
      focusedQuestion: null,
      recommendedNextStep: "composeNow",
      readyToCompose: true,
      missingFields: [],
      workingState: {
        premise: "Show how to narrow a rough idea.",
        audience: "Emerging solo creators.",
        creativeGoal: "Help them make the next decision.",
        proofOrStory: "A note that carried three different lessons.",
        desiredTakeaway: "Choose one audience and takeaway.",
        constraints: ["Film at a desk"],
      },
    };
    expect(SparkTurnResultSchema.safeParse(valid).success).toBe(true);
    expect(
      SparkTurnResultSchema.safeParse({
        ...valid,
        workingState: { premise: "Only a patch" },
      }).success,
    ).toBe(false);
  });

  it("decodes the canonical ready-brief JSON fixture", () => {
    expect(ComposeBriefResultSchema.safeParse(composeFixture).success).toBe(true);
  });

  it("decodes every canonical AI result fixture used by Swift", () => {
    const fixtures = [
      [VoiceProfileResultSchema, "voice-profile-result.json"],
      [IdeasResultSchema, "ideas-result.json"],
      [SparkTurnResultSchema, "spark-turn-result.json"],
      [ComposeBriefResultSchema, "compose-brief-result.json"],
      [ReviseBriefResultSchema, "revise-brief-result.json"],
      [ChatTurnResultSchema, "chat-turn-result.json"],
      [RhythmProposalResultSchema, "rhythm-proposal-result.json"],
      [TasksProposalResultSchema, "tasks-proposal-result.json"],
    ] as const;

    for (const [schema, fixtureName] of fixtures) {
      expect(schema.safeParse(readFixture(fixtureName)).success, fixtureName).toBe(
        true,
      );
    }
  });

  it("keeps the revision ordinal separate from the free allowance", () => {
    const brief = (composeFixture as { brief: unknown }).brief;
    const request = {
      ...metadata,
      promptVersion: "revise-brief.v1",
      brief,
      revisionNumber: 4,
      scope: "spokenHook",
      instruction: "Make the hook more concrete.",
    };
    expect(ReviseBriefRequestSchema.safeParse(request).success).toBe(true);
    expect(
      ReviseBriefRequestSchema.safeParse({ ...request, revisionNumber: 10_001 })
        .success,
    ).toBe(false);
  });
});

describe("SSE contract", () => {
  it("accepts meta, phase, validated result, done", () => {
    const events = [
      {
        event: "meta",
        data: {
          operationId,
          requestId,
          operation: "composeBrief",
          schemaVersion: "1",
          model: "claude-sonnet-5",
          startedAt: "2026-07-11T14:00:00Z",
        },
      },
      {
        event: "phase",
        data: { operationId, phase: "generating" },
      },
      {
        event: "result",
        data: {
          operationId,
          payload: { operation: "composeBrief", result: composeFixture },
        },
      },
      {
        event: "done",
        data: {
          operationId,
          status: "succeeded",
          completedAt: "2026-07-11T14:00:05Z",
        },
      },
    ];

    expect(AiSseSequenceSchema.safeParse(events).success).toBe(true);
  });

  it("rejects mismatched operation IDs and terminal statuses", () => {
    const events = [
      {
        event: "meta",
        data: {
          operationId,
          requestId,
          operation: "ideas",
          schemaVersion: "1",
          model: "claude-sonnet-5",
          startedAt: "2026-07-11T14:00:00Z",
        },
      },
      {
        event: "error",
        data: {
          operationId: "99999999-9999-4999-8999-999999999999",
          error: {
            code: "entitlement_required",
            message: "Start a trial to ask Cy for another direction.",
            retryable: false,
          },
        },
      },
      {
        event: "done",
        data: {
          operationId,
          status: "succeeded",
          completedAt: "2026-07-11T14:00:01Z",
        },
      },
    ];

    expect(AiSseSequenceSchema.safeParse(events).success).toBe(false);
  });
});

describe("supporting contracts", () => {
  it("rejects content-bearing or arbitrary telemetry fields", () => {
    const request = {
      installationId: "44444444-4444-4444-8444-444444444444",
      events: [
        {
          eventId: "55555555-5555-4555-8555-555555555555",
          occurredAt: "2026-07-11T14:00:00Z",
          appBuild: "1.0.0 (1)",
          name: "recordingCompleted",
          properties: { caption: "Creator content must not be accepted" },
        },
      ],
    };
    expect(TelemetryEventsRequestSchema.safeParse(request).success).toBe(false);
  });

  it("uses strict privacy-delete payloads", () => {
    const request = {
      requestId,
      installationId: "44444444-4444-4444-8444-444444444444",
      appBuild: "1.0.0 (1)",
      scope: "serverMetadata",
      confirmation: "ERASE",
    };
    expect(PrivacyDeleteRequestSchema.safeParse(request).success).toBe(true);
    expect(
      PrivacyDeleteRequestSchema.safeParse({ ...request, prompt: "secret" })
        .success,
    ).toBe(false);
  });

  it("rejects unknown RevenueCat webhook fields", () => {
    const webhook = {
      api_version: "1.0",
      event: {
        id: "event-id",
        type: "INITIAL_PURCHASE",
        event_timestamp_ms: 1_783_779_600_000,
        app_user_id: "installation-pseudonym",
        original_app_user_id: "installation-pseudonym",
        aliases: [],
        product_id: "agent_cy_monthly",
        entitlement_ids: ["pro"],
        period_type: "TRIAL",
        purchased_at_ms: 1_783_779_600_000,
        expiration_at_ms: 1_784_989_200_000,
        environment: "SANDBOX",
        store: "APP_STORE",
        transaction_id: "transaction-id",
        original_transaction_id: "original-transaction-id",
        subscriber_attributes: {
          creatorNote: { updated_at_ms: 1_783_779_600_000, value: "discard me" },
        },
      },
    };
    const parsed = RevenueCatWebhookRequestSchema.safeParse(webhook);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.event).not.toHaveProperty("subscriber_attributes");
    }
    expect(
      RevenueCatWebhookRequestSchema.safeParse({ ...webhook, body: "content" })
        .success,
    ).toBe(false);
  });
});
