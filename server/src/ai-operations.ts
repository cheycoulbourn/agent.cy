import {
  BriefRevisionFieldSchema,
  ChatTurnRequestSchema,
  ChatTurnResultSchema,
  ComposeBriefRequestSchema,
  ComposeBriefResultSchema,
  IdeasRequestSchema,
  IdeasResultSchema,
  ReviseBriefRequestSchema,
  ReviseBriefResultSchema,
  RhythmProposalRequestSchema,
  RhythmProposalResultSchema,
  SparkTurnRequestSchema,
  SparkTurnResultSchema,
  TasksProposalRequestSchema,
  TasksProposalResultSchema,
  VoiceProfileRequestSchema,
  VoiceProfileResultSchema,
  ComposeBriefV2RequestSchema,
  ComposeBriefV2ResultSchema,
  ReviseBriefV2RequestSchema,
  ReviseBriefV2ResultSchema,
} from "@agent-cy/contracts";
import type {
  ComposeBriefRequest,
  ComposeBriefResult,
  Platform,
  ReviseBriefRequest,
  ReviseBriefResult,
  VoiceProfileRequest,
  VoiceProfileResult,
  ComposeBriefV2Request,
  ComposeBriefV2Result,
  ReviseBriefV2Request,
  ReviseBriefV2Result,
} from "@agent-cy/contracts";
import { isDeepStrictEqual } from "node:util";
import type { z } from "zod";
import type { AiOperation, AllowanceKey } from "./store.js";

export interface OperationDefinition {
  readonly path: string;
  readonly operation: AiOperation;
  readonly promptVersion: string;
  readonly resultSchemaVersion: string;
  readonly requestSchema: z.ZodType;
  readonly resultSchema: z.ZodType;
  readonly effort: "low" | "medium";
  readonly maxTokens: number;
  readonly reservationCostMicros: number;
  readonly systemPrompt: string;
  allowanceFor(request: unknown): {
    readonly key: AllowanceKey | null;
    readonly limit: number | null;
  };
}

const sharedSystemPrompt = `You are Cy, a creator-led video content copilot. Help an emerging solo creator move from a spark to content they can make. Use only the request-scoped context. Never claim access to live trends, platform analytics, platform algorithms, or viral guarantees. Never imply that a proposal was persisted or accepted; the creator must explicitly accept every change. Surface meaningful assumptions. Use supportive, direct language without streaks, pressure, shame, generic praise, or manipulative urgency. Return only the requested structured result.`;

function allowance(key: AllowanceKey, limit: number) {
  return () => ({ key, limit });
}

function paidOnly() {
  return { key: null, limit: null } as const;
}

export const operationDefinitions = [
  {
    path: "/v1/ai/voice-profile",
    operation: "voice_profile",
    promptVersion: "voice-profile.v1",
    resultSchemaVersion: "voice-profile.result.v1",
    requestSchema: VoiceProfileRequestSchema,
    resultSchema: VoiceProfileResultSchema,
    effort: "low",
    maxTokens: 1_000,
    reservationCostMicros: 20_000,
    systemPrompt: `${sharedSystemPrompt}\nExtract an editable voice profile grounded only in the supplied creator-confirmed text. Examples may be typed text, text copied from a public post, or text derived from on-device screenshot recognition. Treat source labels only as provenance. Never claim to have opened a URL, fetched a post, or inspected an image. Cite traits as evidence notes, not invented biography, and lower confidence when the examples are short, repetitive, or weakly representative.`,
    allowanceFor: (request: unknown) => ({
      key:
        (request as { intent: "onboarding" | "teachCy" }).intent === "teachCy"
          ? "teachCy"
          : "voiceProfile",
      limit: 1,
    }),
  },
  {
    path: "/v1/ai/ideas",
    operation: "ideas",
    promptVersion: "ideas.v1",
    resultSchemaVersion: "ideas.result.v1",
    requestSchema: IdeasRequestSchema,
    resultSchema: IdeasResultSchema,
    effort: "low",
    maxTokens: 900,
    reservationCostMicros: 20_000,
    systemPrompt: `${sharedSystemPrompt}\nReturn exactly three genuinely distinct directions tailored to the creator. For each direction, suggest the single best matching pillar by returning its exact pillarId from creatorContext.pillars, or null when no supplied pillar is a clear fit. Never invent a pillar ID. Do not fabricate external evidence or trend claims.`,
    allowanceFor: allowance("ideas", 3),
  },
  {
    path: "/v1/ai/spark/turn",
    operation: "spark_turn",
    promptVersion: "spark-turn.v1",
    resultSchemaVersion: "spark-turn.result.v1",
    requestSchema: SparkTurnRequestSchema,
    resultSchema: SparkTurnResultSchema,
    effort: "low",
    maxTokens: 700,
    reservationCostMicros: 15_000,
    systemPrompt: `${sharedSystemPrompt}\nDevelop the spark through at most one focused question. Respect the assistance mode: drive waits for scoped direction, collaborate recommends one next step, and lead takes the shortest assumption-visible path.`,
    allowanceFor: allowance("sparkTurn", 8),
  },
  {
    path: "/v1/ai/brief/compose",
    operation: "compose_brief",
    promptVersion: "compose-brief.v1",
    resultSchemaVersion: "compose-brief.result.v1",
    requestSchema: ComposeBriefRequestSchema,
    resultSchema: ComposeBriefResultSchema,
    effort: "medium",
    maxTokens: 5_000,
    reservationCostMicros: 100_000,
    systemPrompt: `${sharedSystemPrompt}\nCompose one complete master brief with modular script beats and only meaningful differences for the selected platforms. Generate no unselected platform variant. Respect the creator-selected duration. Treat youtubeVideo as long-form and give its script enough distinct beats, examples, and transitions to support the selected length; keep all other destinations concise and short-form.`,
    allowanceFor: allowance("composeBrief", 1),
  },
  {
    path: "/v1/ai/brief/revise",
    operation: "revise_brief",
    promptVersion: "revise-brief.v1",
    resultSchemaVersion: "revise-brief.result.v1",
    requestSchema: ReviseBriefRequestSchema,
    resultSchema: ReviseBriefResultSchema,
    effort: "medium",
    maxTokens: 5_000,
    reservationCostMicros: 100_000,
    systemPrompt: `${sharedSystemPrompt}\nApply the scoped revision and return a complete brief. Preserve fields outside the requested scope unless consistency requires a related change, then list it explicitly.`,
    allowanceFor: allowance("reviseBrief", 3),
  },
  {
    path: "/v2/ai/brief/compose",
    operation: "compose_brief",
    promptVersion: "compose-brief.v2",
    resultSchemaVersion: "compose-brief.result.v2",
    requestSchema: ComposeBriefV2RequestSchema,
    resultSchema: ComposeBriefV2ResultSchema,
    effort: "medium",
    maxTokens: 5_000,
    reservationCostMicros: 100_000,
    systemPrompt: `${sharedSystemPrompt}\nCompose one complete master brief and return exactly one meaningful variant for every selected destination-format pair. Destination names are creator-provided labels, not evidence of an account connection. Respect each selected format and duration.`,
    allowanceFor: allowance("composeBrief", 1),
  },
  {
    path: "/v2/ai/brief/revise",
    operation: "revise_brief",
    promptVersion: "revise-brief.v2",
    resultSchemaVersion: "revise-brief.result.v2",
    requestSchema: ReviseBriefV2RequestSchema,
    resultSchema: ReviseBriefV2ResultSchema,
    effort: "medium",
    maxTokens: 5_000,
    reservationCostMicros: 100_000,
    systemPrompt: `${sharedSystemPrompt}\nApply the scoped revision and return a complete brief. Preserve the selected destination-format set and fields outside the requested scope unless consistency requires a declared related change.`,
    allowanceFor: allowance("reviseBrief", 3),
  },
  {
    path: "/v1/ai/chat/turn",
    operation: "chat_turn",
    promptVersion: "chat-turn.v1",
    resultSchemaVersion: "chat-turn.result.v1",
    requestSchema: ChatTurnRequestSchema,
    resultSchema: ChatTurnResultSchema,
    effort: "low",
    maxTokens: 900,
    reservationCostMicros: 20_000,
    systemPrompt: `${sharedSystemPrompt}\nAnswer the creator’s current content-creation question using compact relevant context. Proposed actions remain proposals.`,
    allowanceFor: paidOnly,
  },
  {
    path: "/v1/ai/rhythm/propose",
    operation: "rhythm_proposal",
    promptVersion: "rhythm-proposal.v1",
    resultSchemaVersion: "rhythm-proposal.result.v1",
    requestSchema: RhythmProposalRequestSchema,
    resultSchema: RhythmProposalResultSchema,
    effort: "medium",
    maxTokens: 1_200,
    reservationCostMicros: 30_000,
    systemPrompt: `${sharedSystemPrompt}\nPropose a sustainable production rhythm within the supplied availability. Dates are flexible targets, never deadlines.`,
    allowanceFor: paidOnly,
  },
  {
    path: "/v1/ai/tasks/propose",
    operation: "tasks_proposal",
    promptVersion: "tasks-proposal.v1",
    resultSchemaVersion: "tasks-proposal.result.v1",
    requestSchema: TasksProposalRequestSchema,
    resultSchema: TasksProposalResultSchema,
    effort: "medium",
    maxTokens: 1_000,
    reservationCostMicros: 25_000,
    systemPrompt: `${sharedSystemPrompt}\nPropose a minimal, executable task sequence for this brief. Avoid duplicates with existing tasks and designate at most one filming task as the recording milestone.`,
    allowanceFor: paidOnly,
  },
] as const satisfies readonly OperationDefinition[];

const concreteBriefFields = BriefRevisionFieldSchema.options.filter(
  (field): field is Exclude<(typeof BriefRevisionFieldSchema.options)[number], "wholeBrief"> =>
    field !== "wholeBrief",
);

/**
 * Cross-object guarantees cannot be expressed by either standalone Zod schema.
 * Keep them at the trust boundary before usage and allowance settlement.
 */
export function operationResultIntegrityIssue(
  operation: AiOperation,
  request: unknown,
  result: unknown,
): string | null {
  if (operation === "voice_profile") {
    const voiceRequest = request as VoiceProfileRequest;
    const voiceResult = result as VoiceProfileResult;
    if (
      voiceRequest.intent === "teachCy" &&
      voiceRequest.creatorContext.voiceProfile !== undefined &&
      isDeepStrictEqual(
        voiceRequest.creatorContext.voiceProfile,
        voiceResult.profile,
      )
    ) {
      return "Teach Cy made no material voice-profile change";
    }
    return null;
  }

  if (operation === "compose_brief") {
    if ("selectedDestinations" in (request as Record<string, unknown>)) {
      const composeRequest = request as ComposeBriefV2Request;
      const composeResult = result as ComposeBriefV2Result;
      if (composeResult.brief.briefId !== composeRequest.briefId) return "brief ID changed";
      if (!sameDestinationSet(composeResult.brief.destinationVariants, composeRequest.selectedDestinations)) return "destination variants do not match the selected destinations";
      if (composeResult.brief.durationSeconds !== composeRequest.durationSeconds) return "duration changed from the creator selection";
      return null;
    }
    const composeRequest = request as ComposeBriefRequest;
    const composeResult = result as ComposeBriefResult;
    if (composeResult.brief.briefId !== composeRequest.briefId) {
      return "brief ID changed";
    }
    if (
      !samePlatformSet(
        composeResult.brief.platformVariants.map((variant) => variant.platform),
        composeRequest.selectedPlatforms,
      )
    ) {
      return "platform variants do not match the selected platforms";
    }
    if (composeResult.brief.durationSeconds !== composeRequest.durationSeconds) {
      return "duration changed from the creator selection";
    }
    return null;
  }

  if (operation === "revise_brief") {
    if ("destinationVariants" in (request as ReviseBriefV2Request).brief) {
      return revisionV2IntegrityIssue(request as ReviseBriefV2Request, result as ReviseBriefV2Result);
    }
    return revisionIntegrityIssue(
      request as ReviseBriefRequest,
      result as ReviseBriefResult,
    );
  }
  return null;
}

function sameDestinationSet(
  actual: readonly { destinationId: string; formatId: string }[],
  expected: readonly { destinationId: string; formatId: string }[],
): boolean {
  const keys = (items: readonly { destinationId: string; formatId: string }[]) => items.map((item) => `${item.destinationId}:${item.formatId}`).sort();
  return isDeepStrictEqual(keys(actual), keys(expected));
}

function revisionV2IntegrityIssue(request: ReviseBriefV2Request, result: ReviseBriefV2Result): string | null {
  if (result.brief.briefId !== request.brief.briefId) return "brief ID changed";
  if (!sameDestinationSet(result.brief.destinationVariants, request.brief.destinationVariants)) return "destination variants changed the selected destination set";
  if (isDeepStrictEqual(request.brief, result.brief)) return "revision made no material change";
  return null;
}

function revisionIntegrityIssue(
  request: ReviseBriefRequest,
  result: ReviseBriefResult,
): string | null {
  if (result.brief.briefId !== request.brief.briefId) {
    return "brief ID changed";
  }
  if (
    !samePlatformSet(
      result.brief.platformVariants.map((variant) => variant.platform),
      request.brief.platformVariants.map((variant) => variant.platform),
    )
  ) {
    return "platform variants changed the selected platform set";
  }

  const actualChanges = concreteBriefFields.filter(
    (field) => !isDeepStrictEqual(request.brief[field], result.brief[field]),
  );
  if (actualChanges.length === 0) return "revision made no material change";

  const declaredChanges = new Set(result.changedFields);
  if (request.scope === "wholeBrief") {
    if (declaredChanges.has("wholeBrief")) return null;
    const undeclared = actualChanges.find((field) => !declaredChanges.has(field));
    if (undeclared) return `${undeclared} changed without being declared`;
    const falseDeclaration = result.changedFields.find(
      (field) => field !== "wholeBrief" && !actualChanges.includes(field),
    );
    return falseDeclaration
      ? `${falseDeclaration} was declared changed but was preserved`
      : null;
  }

  if (!actualChanges.includes(request.scope)) {
    return `requested scope ${request.scope} was preserved`;
  }
  if (!declaredChanges.has(request.scope)) {
    return `requested scope ${request.scope} was not declared changed`;
  }
  if (declaredChanges.has("wholeBrief")) {
    return "wholeBrief cannot be declared for a scoped revision";
  }
  const undeclared = actualChanges.find((field) => !declaredChanges.has(field));
  if (undeclared) return `${undeclared} changed without being declared`;
  const falseDeclaration = result.changedFields.find(
    (field) => field !== "wholeBrief" && !actualChanges.includes(field),
  );
  return falseDeclaration
    ? `${falseDeclaration} was declared changed but was preserved`
    : null;
}

function samePlatformSet(
  left: readonly Platform[],
  right: readonly Platform[],
): boolean {
  return (
    left.length === right.length &&
    left.every((platform) => right.includes(platform))
  );
}
