import {
    IdeasRequestSchema,
    IdeasResultSchema,
    InspirationShapeRequestSchema,
    InspirationShapeResultSchema,
    VoiceProfileRequestSchema,
  VoiceProfileResultSchema,
} from "@agent-cy/contracts";
import { describe, expect, it } from "vitest";
import { operationDefinitions, operationResultIntegrityIssue } from "../src/ai-operations.js";

const profile = {
  summary: "Clear, grounded teaching.",
  tone: ["warm", "direct"],
  sentenceStyle: "Short declarative sentences.",
  signatureQualities: ["specific"],
  phrasesToUse: ["start here"],
  phrasesToAvoid: ["you must"],
  guidance: ["Prefer one concrete next move."],
  confidence: 0.8,
};

const request = VoiceProfileRequestSchema.parse({
  schemaVersion: "1",
  promptVersion: "voice-profile.v1",
  operationId: "11111111-1111-4111-8111-111111111111",
  appBuild: "1.0 (1)",
  assistanceMode: "collaborate",
  creatorContext: {
    name: "Maya",
    primaryGoal: "Publish useful short videos.",
    selectedPlatforms: ["instagramReels"],
    voiceExamples: [
      {
        exampleId: "33333333-3333-4333-8333-333333333331",
        order: 0,
        source: "text",
        text: "Make one point useful before making it polished.",
        creatorConfirmed: true,
      },
      {
        exampleId: "33333333-3333-4333-8333-333333333332",
        order: 1,
        source: "publicPostText",
        text: "Start with the moment that made the lesson matter.",
        creatorConfirmed: true,
      },
      {
        exampleId: "33333333-3333-4333-8333-333333333333",
        order: 2,
        source: "screenshotText",
        text: "A smaller promise gives people something they can try.",
        creatorConfirmed: true,
      },
    ],
    voiceProfile: profile,
    pillars: [],
    librarySummaries: [],
  },
  intent: "teachCy",
  teachingInstruction: "Use fewer setup sentences before the point.",
});

describe("AI result integrity", () => {
  it("keeps v1 and v2 brief endpoints available during migration", () => {
    const paths = operationDefinitions.map((definition) => definition.path);
    expect(paths).toContain("/v1/ai/brief/compose");
    expect(paths).toContain("/v1/ai/brief/revise");
    expect(paths).toContain("/v2/ai/brief/compose");
    expect(paths).toContain("/v2/ai/brief/revise");
    expect(paths).toContain("/v1/ai/inspiration/shape");
  });

  it("rejects a no-op Teach Cy result before allowance settlement", () => {
    const result = VoiceProfileResultSchema.parse({
      profile,
      assumptions: [],
      evidenceNotes: ["Compared the instruction with the approved profile."],
    });
    expect(operationResultIntegrityIssue("voice_profile", request, result)).toBe(
      "Teach Cy made no material voice-profile change",
    );
  });

  it("accepts a materially changed Teach Cy result", () => {
    const result = VoiceProfileResultSchema.parse({
      profile: {
        ...profile,
        sentenceStyle: "Lead with the point, then add one short example.",
      },
      assumptions: [],
      evidenceNotes: ["Applied the creator's explicit instruction."],
    });
    expect(operationResultIntegrityIssue("voice_profile", request, result)).toBeNull();
  });

  it("rejects duplicate idea directions before allowance settlement", () => {
    const ideasRequest = IdeasRequestSchema.parse({
      schemaVersion: "1",
      promptVersion: "ideas.v1",
      operationId: "11111111-1111-4111-8111-111111111112",
      appBuild: "1.0 (1)",
      assistanceMode: "collaborate",
      creatorContext: {
        name: "Maya",
        primaryGoal: "Publish useful short videos.",
        selectedPlatforms: ["instagramReels"],
        voiceExamples: [],
        pillars: [],
        librarySummaries: [],
      },
      count: 3,
      constraints: [],
    });
    const duplicateIdea = {
      title: "Start with the smallest version",
      premise: "Show how a smaller first step makes creating easier.",
      opening: "You do not need the whole plan to begin.",
      whyItFits: "It supports the creator's practical teaching goal.",
      assumedTakeaway: "Choose one useful first move.",
      suggestedPillarId: null,
      assumptions: [],
    };
    const ideasResult = IdeasResultSchema.parse({
      ideas: [
        { ...duplicateIdea, directionId: "direction-1" },
        { ...duplicateIdea, directionId: "direction-2" },
        {
          ...duplicateIdea,
          directionId: "direction-3",
          title: "A different useful direction",
        },
      ],
    });

    expect(
      operationResultIntegrityIssue("ideas", ideasRequest, ideasResult),
    ).toBe("ideas must have distinct titles");
  });

  it("accepts three distinct idea directions", () => {
    const ideasRequest = IdeasRequestSchema.parse({
      schemaVersion: "1",
      promptVersion: "ideas.v1",
      operationId: "11111111-1111-4111-8111-111111111113",
      appBuild: "1.0 (1)",
      assistanceMode: "collaborate",
      creatorContext: {
        name: "Maya",
        primaryGoal: "Publish useful short videos.",
        selectedPlatforms: ["instagramReels"],
        voiceExamples: [],
        pillars: [],
        librarySummaries: [],
      },
      count: 3,
      constraints: [],
    });
    const ideasResult = IdeasResultSchema.parse({
      ideas: [
        {
          directionId: "direction-1",
          title: "The smallest useful version",
          premise: "Show how a smaller first step makes creating easier.",
          opening: "You do not need the whole plan to begin.",
          whyItFits: "It supports the creator's practical teaching goal.",
          assumedTakeaway: "Choose one useful first move.",
          suggestedPillarId: null,
          assumptions: [],
        },
        {
          directionId: "direction-2",
          title: "What changed my process",
          premise: "Walk through one decision that simplified the workflow.",
          opening: "I stopped rebuilding my process every morning.",
          whyItFits: "It turns lived experience into a useful lesson.",
          assumedTakeaway: "Reuse a process that already works.",
          suggestedPillarId: null,
          assumptions: [],
        },
        {
          directionId: "direction-3",
          title: "A realistic week behind the scenes",
          premise: "Share the imperfect sequence behind finished work.",
          opening: "Here is what actually happened before I posted.",
          whyItFits: "It keeps the creator's teaching grounded and honest.",
          assumedTakeaway: "Progress can look uneven and still count.",
          suggestedPillarId: null,
          assumptions: [],
        },
      ],
    });

    expect(
      operationResultIntegrityIssue("ideas", ideasRequest, ideasResult),
    ).toBeNull();
  });

  it("rejects an inspiration pillar that was not supplied in creator context", () => {
    const pillarId = "22222222-2222-4222-8222-222222222222";
    const inspirationRequest = InspirationShapeRequestSchema.parse({
      schemaVersion: "inspiration-shape.request.v3",
      promptVersion: "inspiration-shape.v3",
      operationId: "11111111-1111-4111-8111-111111111114",
      appBuild: "1.0 (1)",
      assistanceMode: "collaborate",
      creatorContext: {
        name: "Maya",
        primaryGoal: "Publish useful short videos.",
        selectedPlatforms: ["instagramReels"],
        voiceExamples: [],
        pillars: [{ pillarId, name: "Creator systems" }],
        librarySummaries: [],
      },
      sourcePlatform: "instagram",
      sourceMaterial: {
        title: "A practical filming reset",
        caption: "Make filming easier by shrinking one setup decision.",
        visualObservations: [],
        analyzedInputs: ["caption"],
      },
    });
    const inspirationResult = InspirationShapeResultSchema.parse({
      sourceSummary: "The post explains how one smaller setup decision reduces filming friction.",
      keyPoints: ["Shrink the setup before starting."],
      interpretedMechanic: {
        hookPattern: "Open with the friction",
        structurePattern: "Problem, reset, example",
        payoffPattern: "One practical next move",
      },
      originalityGuardrails: ["Use a firsthand example."],
      idea: {
        title: "The reset that made starting easier",
        premise: "Show one original setup change.",
        audience: "Solo creators",
        takeaway: "Shrink one setup decision.",
        spokenHook: "The plan was not the problem.",
        firstFrameText: "MAKE THE FIRST TAKE EASIER",
        filmingApproach: "Direct to camera with a firsthand demonstration.",
        recommendedFormat: "45-second vertical video",
        durationSeconds: 45,
      },
      suggestedPillarId: "33333333-3333-4333-8333-333333333333",
      assumptions: [],
    });

    expect(
      operationResultIntegrityIssue(
        "inspiration_shape",
        inspirationRequest,
        inspirationResult,
      ),
    ).toBe("suggested pillar is not in creator context");
  });
});
