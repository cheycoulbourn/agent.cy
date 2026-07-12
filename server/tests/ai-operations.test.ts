import {
  VoiceProfileRequestSchema,
  VoiceProfileResultSchema,
} from "@agent-cy/contracts";
import { describe, expect, it } from "vitest";
import { operationResultIntegrityIssue } from "../src/ai-operations.js";

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
});
