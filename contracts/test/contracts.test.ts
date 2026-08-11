import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  AiSseSequenceSchema,
  AiErrorSchema,
  AssistanceModeSchema,
  ChatTurnResultSchema,
  ComposeBriefResultSchema,
  CreatorContextSchema,
  DurationSecondsSchema,
  IdeasResultSchema,
  AppleAccountAuthorizationRequestSchema,
  AppleAccountAuthorizationResultSchema,
  InspirationShapeRequestSchema,
  InspirationShapeResultSchema,
  McpBridgeSnapshotSchema,
  McpBridgeChangeRequestSchema,
  normalizeAiOperationResult,
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
  SelectedDestinationsSchema,
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
  taskSummaries: [],
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

describe("Apple account authorization contracts", () => {
  const request = {
    identityToken: "header.payload.signature",
    authorizationCode: "single-use-authorization-code",
    nonce: "a-raw-nonce-with-at-least-thirty-two-characters",
    appBuild: "1.0.0 (1)",
    platform: "macCatalyst",
  } as const;

  it("accepts the minimum credential exchange without profile data", () => {
    expect(AppleAccountAuthorizationRequestSchema.parse(request)).toEqual(request);
    expect(AppleAccountAuthorizationRequestSchema.safeParse({
      ...request,
      email: "creator@example.com",
      fullName: "Creator Name",
    }).success).toBe(false);
  });

  it("returns an account link and a device-specific installation credential", () => {
    const result = {
      accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      installationId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      credential: "device-specific-credential-that-is-long-enough",
      access: "paid",
    } as const;

    expect(AppleAccountAuthorizationResultSchema.parse(result)).toEqual(result);
  });
});

describe("wire enums", () => {
  it("accepts the exact PRD values", () => {
    expect(AssistanceModeSchema.parse("drive")).toBe("drive");
    expect(AssistanceModeSchema.parse("collaborate")).toBe("collaborate");
    expect(AssistanceModeSchema.parse("lead")).toBe("lead");
    expect(PlatformSchema.parse("instagramReels")).toBe("instagramReels");
    expect(PlatformSchema.parse("tiktok")).toBe("tiktok");
    expect(PlatformSchema.parse("youtubeShorts")).toBe("youtubeShorts");
    expect(PlatformSchema.parse("youtubeVideo")).toBe("youtubeVideo");
    expect(DurationSecondsSchema.parse(3_600)).toBe(3_600);
    expect(DurationSecondsSchema.parse(480)).toBe(480); // Existing saved work remains compatible.
  });

  it("rejects renamed wire values", () => {
    expect(AssistanceModeSchema.safeParse("leadMe").success).toBe(false);
    expect(PlatformSchema.safeParse("instagram_reels").success).toBe(false);
  });
});

describe("inspiration shaping contracts", () => {
  const request = {
    schemaVersion: "inspiration-shape.request.v3",
    promptVersion: "inspiration-shape.v3",
    operationId,
    appBuild: "1.0.0 (1)",
    assistanceMode: "collaborate",
    creatorContext: {
      ...creatorContext,
      voiceExamples: [],
      librarySummaries: [],
      taskSummaries: [],
    },
    sourcePlatform: "instagram",
    sourceMaterial: {
      title: "A practical filming reset",
      caption: "The hook creates tension before revealing a practical reset.",
      transcript: "I made filming easier by shrinking one setup decision.",
      visualObservations: ["Direct-to-camera opening followed by a desk demonstration."],
      analyzedInputs: ["caption", "audioTranscript", "videoFrames"],
      durationSeconds: 45,
    },
  } as const;

  it("accepts analyzed post material but rejects source URL fields", () => {
    expect(InspirationShapeRequestSchema.parse(request).sourceMaterial.caption).toContain("tension");
    expect(InspirationShapeRequestSchema.safeParse({
      ...request,
      sourceURL: "https://www.instagram.com/reel/private-source/",
    }).success).toBe(false);
  });

  it("requires one original idea and one to three guardrails", () => {
    const result = {
      sourceSummary: "The post demonstrates how one smaller setup decision reduces filming friction.",
      keyPoints: ["Name the tension first.", "Demonstrate one practical reset."],
      interpretedMechanic: {
        hookPattern: "Open with a contradiction",
        structurePattern: "Tension, reset, practical example",
        payoffPattern: "A smaller action the viewer can try",
      },
      originalityGuardrails: [
        "Use a firsthand example from the creator's own process.",
        "Do not reuse source wording or story details.",
      ],
      idea: {
        title: "The reset that made starting easier",
        premise: "Show how one smaller setup decision reduced creative friction.",
        audience: "Solo creators who delay filming while perfecting the plan",
        takeaway: "Reduce the setup until the first take feels possible.",
        spokenHook: "The plan was not what kept me from filming.",
        firstFrameText: "MAKE THE FIRST TAKE EASIER",
        filmingApproach: "Talking head with one original desk-setup demonstration.",
        recommendedFormat: "45-second vertical video",
        durationSeconds: 45,
      },
      suggestedPillarId: null,
      assumptions: ["The creator has a firsthand setup change to demonstrate."],
    };

    expect(InspirationShapeResultSchema.parse(result).idea.durationSeconds).toBe(45);
    expect(InspirationShapeResultSchema.safeParse({
      ...result,
      originalityGuardrails: [],
    }).success).toBe(false);
    expect(InspirationShapeResultSchema.safeParse({
      ...result,
      originalityGuardrails: ["One", "Two", "Three", "Four"],
    }).success).toBe(false);
  });
});

describe("MCP bridge contracts", () => {
  it("keeps captions and hooks in structured post-draft fields", () => {
    const request = {
      schemaVersion: 1,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      createdAt: "2026-07-15T21:30:00Z",
      source: "codex",
      type: "createPostDraft",
      payload: {
        title: "A slower Asheville day",
        hook: "Come spend a slow day in Asheville with me.",
        caption: "Asheville, slowly.",
        notes: "Use the arrival footage first.",
      },
    };

    const parsed = McpBridgeChangeRequestSchema.parse(request);
    if (parsed.type !== "createPostDraft") {
      throw new Error("Expected a createPostDraft proposal");
    }

    expect(parsed.payload.hook).toBe(request.payload.hook);
    expect(parsed.payload.caption).toBe(request.payload.caption);
    expect(parsed.payload.notes).toBe("Use the arrival footage first.");
  });

  it("keeps creation and scheduling in one dated post proposal", () => {
    const parsed = McpBridgeChangeRequestSchema.parse({
      schemaVersion: 1,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      createdAt: "2026-07-18T12:00:00Z",
      source: "codex",
      type: "createPostDraft",
      payload: {
        title: "A soft weekend in Charlotte",
        platform: "instagramReels",
        format: "Reel",
        targetDate: "2026-07-20T04:00:00Z",
        includesTargetTime: false,
      },
    });

    if (parsed.type !== "createPostDraft") {
      throw new Error("Expected a createPostDraft proposal");
    }
    expect(parsed.payload.targetDate).toBe("2026-07-20T04:00:00Z");
    expect(parsed.payload.includesTargetTime).toBe(false);
  });

  it("rejects posting dates hidden only in notes and non-catalog formats", () => {
    const base = {
      schemaVersion: 1,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      createdAt: "2026-07-18T12:00:00Z",
      source: "codex",
      type: "createPostDraft",
    } as const;

    expect(McpBridgeChangeRequestSchema.safeParse({
      ...base,
      payload: {
        title: "A soft weekend in Charlotte",
        notes: "Intended publish date: Monday, July 20.",
      },
    }).success).toBe(false);

    expect(McpBridgeChangeRequestSchema.safeParse({
      ...base,
      payload: {
        title: "A soft weekend in Charlotte",
        format: "Instagram Reel with a quiet travel diary opening",
      },
    }).success).toBe(false);
  });

  it("keeps format and call to action out of freeform post notes", () => {
    const request = {
      schemaVersion: 1,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      createdAt: "2026-07-15T21:30:00Z",
      source: "codex",
      type: "updatePost",
      payload: {
        postId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        format: "Reel",
        callToAction: "Save this for your next slow trip.",
        notes: "STRUCTURE\n1. Open on the road.\n\nSTORIES\n1. Share the arrival.",
      },
    };

    const parsed = McpBridgeChangeRequestSchema.parse(request);
    if (parsed.type !== "updatePost") {
      throw new Error("Expected an updatePost proposal");
    }

    expect(parsed.payload.format).toBe("Reel");
    expect(parsed.payload.callToAction).toBe("Save this for your next slow trip.");
    expect(parsed.payload.notes).not.toContain("CALL TO ACTION");
    expect(parsed.payload.notes).not.toContain("FORMAT");
  });

  it("accepts nil Swift optionals that JSONEncoder omits", () => {
    const snapshot = {
      schemaVersion: 1,
      generatedAt: "2026-07-15T21:30:00Z",
      pillars: [{
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        name: "Lifestyle",
        colorHex: "FED3FF",
        role: "anchor",
        assignedWeekdays: [1],
      }],
      posts: [{
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        title: "An unfinished idea",
        premise: "",
        notes: "",
        status: "spark",
        durationSeconds: 45,
        hook: "",
        firstFrameText: "",
        script: [],
        ending: "",
        callToAction: "",
        createdAt: "2026-07-15T21:30:00Z",
        updatedAt: "2026-07-15T21:30:00Z",
        markdown: "# An unfinished idea",
        outputs: [{
          id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
          platform: "instagramReels",
          destination: "Instagram",
          format: "Reel",
          status: "draft",
          includesTargetTime: false,
          durationSeconds: 45,
          title: "",
          caption: "",
          openingAdjustment: "",
          callToAction: "",
          editNotes: "",
          publishedUrl: "",
        }],
        tasks: [],
      }],
      tasks: [],
    };

    expect(McpBridgeSnapshotSchema.safeParse(snapshot).success).toBe(true);
  });
});

describe("AI contracts", () => {
  it("accepts unique destination-format pairs and rejects duplicates", () => {
    const destination = {
      destinationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      formatId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      destinationName: "Newsletter",
      formatName: "Essay",
      format: "nonVideo",
      durationSeconds: null,
    };
    expect(SelectedDestinationsSchema.safeParse([destination]).success).toBe(true);
    expect(SelectedDestinationsSchema.safeParse([destination, destination]).success).toBe(false);
  });

  it("allows creator examples to be deferred", () => {
    expect(
      CreatorContextSchema.safeParse({
        ...creatorContext,
        voiceExamples: [],
        voiceProfile: undefined,
      }).success,
    ).toBe(true);
  });

  it("accepts compact post and task history for Cy", () => {
    const context = {
      ...creatorContext,
      librarySummaries: [
        {
          briefId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          title: "DITL vlog",
          notes: "Show the real version of the day.",
          hook: "This is what the day actually looked like.",
          caption: "A real day, not a perfect routine.",
          pillarId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          pillarName: "Lifestyle",
          format: "Reel",
          status: "scheduled",
          platforms: ["instagramReels"],
          targetDate: "2026-07-20T23:00:00.000Z",
          includesTargetTime: true,
          taskCount: 2,
          completedTaskCount: 1,
        },
      ],
      taskSummaries: [
        {
          taskId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
          title: "Edit the first cut",
          kind: "editing",
          priority: "high",
          isCompleted: false,
          targetDate: "2026-07-20T18:00:00.000Z",
          includesTargetTime: true,
          postId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          pillarId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        },
      ],
    };

    expect(CreatorContextSchema.safeParse(context).success).toBe(true);
  });

  it("requires complete task details for a create-task chat action", () => {
    const valid = {
      assistantMessage: "I prepared one editing task for you to review.",
      suggestions: [],
      proposedAction: {
        kind: "createTask",
        summary: "Edit the first cut for DITL vlog.",
        task: {
          title: "Edit the first cut",
          kind: "editing",
          priority: "high",
          includesTargetTime: false,
          postId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        },
      },
    };

    expect(ChatTurnResultSchema.safeParse(valid).success).toBe(true);
    expect(
      ChatTurnResultSchema.safeParse({
        ...valid,
        proposedAction: {
          kind: "createTask",
          summary: "Edit the first cut for DITL vlog.",
        },
      }).success,
    ).toBe(false);
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
      suggestedPillarId: null,
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

  it("normalizes a usable partial Spark response before strict validation", () => {
    const workingState = {
      premise: "Show how to narrow a rough idea.",
      audience: "Emerging solo creators.",
      creativeGoal: null,
      proofOrStory: null,
      desiredTakeaway: null,
      constraints: [],
    };
    const normalized = normalizeAiOperationResult(
      "spark_turn",
      {
        message: "Start with the single claim this post needs to prove.",
        workingState: { premise: "A sharper premise." },
        providerOnlyField: "ignored",
      },
      { workingState },
    );

    expect(SparkTurnResultSchema.parse(normalized)).toEqual({
      assistantMessage: "Start with the single claim this post needs to prove.",
      focusedQuestion: null,
      recommendedNextStep: "answerQuestion",
      readyToCompose: false,
      missingFields: [
        "creativeGoal",
        "proofOrStory",
        "desiredTakeaway",
        "constraints",
      ],
      workingState: {
        ...workingState,
        premise: "A sharper premise.",
      },
    });
  });

  it("normalizes a fenced nested Spark response returned by a provider SDK", () => {
    const normalized = normalizeAiOperationResult(
      "sparkTurn",
      {
        output: "```json\n{\"assistantMessage\":\"This is ready to shape.\",\"readyToCompose\":true}\n```",
      },
      { workingState: {
        premise: "A complete premise",
        audience: "Creators",
        creativeGoal: "Teach one idea",
        proofOrStory: "A real example",
        desiredTakeaway: "Choose one next step",
        constraints: ["Keep it short"],
      } },
    );

    expect(SparkTurnResultSchema.parse(normalized)).toMatchObject({
      assistantMessage: "This is ready to shape.",
      recommendedNextStep: "composeNow",
      readyToCompose: true,
      missingFields: [],
    });
  });

  it("normalizes Spark JSON wrapped in provider content blocks", () => {
    const normalized = normalizeAiOperationResult(
      "spark_turn",
      {
        content: [{
          type: "text",
          text: "```json\n{\"assistantMessage\":\"Choose the one result this post should create.\",\"readyToCompose\":false}\n```",
        }],
      },
      { workingState: {
        premise: "A complete premise",
        audience: "Creators",
        creativeGoal: null,
        proofOrStory: null,
        desiredTakeaway: null,
        constraints: [],
      } },
    );

    expect(SparkTurnResultSchema.parse(normalized)).toMatchObject({
      assistantMessage: "Choose the one result this post should create.",
      recommendedNextStep: "answerQuestion",
      readyToCompose: false,
    });
  });

  it("does not invent a successful Spark response when provider content is unusable", () => {
    const normalized = normalizeAiOperationResult(
      "spark_turn",
      { readyToCompose: false },
      { workingState: {} },
    );
    expect(SparkTurnResultSchema.safeParse(normalized).success).toBe(false);
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
  it("accepts optional machine-readable quota scopes without requiring them", () => {
    const base = {
      code: "quota_exceeded",
      message: "The allowance has been reached.",
      retryable: false,
    };
    expect(AiErrorSchema.safeParse(base).success).toBe(true);
    expect(
      AiErrorSchema.safeParse({ ...base, quotaScope: "freeAllowance" }).success,
    ).toBe(true);
    expect(
      AiErrorSchema.safeParse({ ...base, quotaScope: "unknownScope" }).success,
    ).toBe(false);
  });

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
