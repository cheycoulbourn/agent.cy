import { z } from "zod";

import {
  ChatTurnResultSchema,
  ComposeBriefResultSchema,
  IdeasResultSchema,
  ReviseBriefResultSchema,
  RhythmProposalResultSchema,
  SparkTurnResultSchema,
  TasksProposalResultSchema,
  VoiceProfileResultSchema,
} from "./ai.js";
import {
  IsoDateTimeSchema,
  OperationIdSchema,
  SchemaVersionSchema,
} from "./common.js";

export const AiOperationSchema = z.enum([
  "voiceProfile",
  "ideas",
  "sparkTurn",
  "composeBrief",
  "reviseBrief",
  "chatTurn",
  "rhythmProposal",
  "tasksProposal",
]);

export const AiErrorCodeSchema = z.enum([
  "invalid_input",
  "payload_too_large",
  "installation_invalid",
  "entitlement_required",
  "quota_exceeded",
  "rate_limited",
  "upstream_unavailable",
  "generation_invalid",
  "refusal",
  "max_tokens",
  "timeout",
  "usage_limit",
  "cancelled",
  "conflict",
]);

export const AiQuotaScopeSchema = z.enum([
  "freeAllowance",
  "installationShortWindow",
  "installationDaily",
  "globalDailySpend",
  "providerRateLimit",
  "providerCredits",
]);

export const AiErrorSchema = z
  .object({
    code: AiErrorCodeSchema,
    message: z.string().trim().min(1).max(500),
    retryable: z.boolean(),
    retryAfterSeconds: z.number().int().positive().max(86_400).optional(),
    quotaScope: AiQuotaScopeSchema.optional(),
    fieldIssues: z
      .array(
        z
          .object({
            path: z.array(z.union([z.string(), z.number().int()])).max(12),
            message: z.string().trim().min(1).max(300),
          })
          .strict(),
      )
      .max(20)
      .optional(),
  })
  .strict();

export const SseMetaEventSchema = z
  .object({
    event: z.literal("meta"),
    data: z
      .object({
        operationId: OperationIdSchema,
        requestId: z.uuid(),
        operation: AiOperationSchema,
        schemaVersion: SchemaVersionSchema,
        model: z.literal("claude-sonnet-5"),
        startedAt: IsoDateTimeSchema,
      })
      .strict(),
  })
  .strict();

export const SsePhaseEventSchema = z
  .object({
    event: z.literal("phase"),
    data: z
      .object({
        operationId: OperationIdSchema,
        phase: z.enum(["accepted", "generating", "validating"]),
      })
      .strict(),
  })
  .strict();

export const AiOperationResultSchema = z.discriminatedUnion("operation", [
  z
    .object({
      operation: z.literal("voiceProfile"),
      result: VoiceProfileResultSchema,
    })
    .strict(),
  z
    .object({ operation: z.literal("ideas"), result: IdeasResultSchema })
    .strict(),
  z
    .object({ operation: z.literal("sparkTurn"), result: SparkTurnResultSchema })
    .strict(),
  z
    .object({
      operation: z.literal("composeBrief"),
      result: ComposeBriefResultSchema,
    })
    .strict(),
  z
    .object({
      operation: z.literal("reviseBrief"),
      result: ReviseBriefResultSchema,
    })
    .strict(),
  z
    .object({ operation: z.literal("chatTurn"), result: ChatTurnResultSchema })
    .strict(),
  z
    .object({
      operation: z.literal("rhythmProposal"),
      result: RhythmProposalResultSchema,
    })
    .strict(),
  z
    .object({
      operation: z.literal("tasksProposal"),
      result: TasksProposalResultSchema,
    })
    .strict(),
]);

export const SseResultEventSchema = z
  .object({
    event: z.literal("result"),
    data: z
      .object({
        operationId: OperationIdSchema,
        payload: AiOperationResultSchema,
      })
      .strict(),
  })
  .strict();

export const SseErrorEventSchema = z
  .object({
    event: z.literal("error"),
    data: z
      .object({
        operationId: OperationIdSchema,
        error: AiErrorSchema,
      })
      .strict(),
  })
  .strict();

export const SseDoneEventSchema = z
  .object({
    event: z.literal("done"),
    data: z
      .object({
        operationId: OperationIdSchema,
        status: z.enum(["succeeded", "failed", "cancelled"]),
        completedAt: IsoDateTimeSchema,
      })
      .strict(),
  })
  .strict();

export const AiSseEventSchema = z.discriminatedUnion("event", [
  SseMetaEventSchema,
  SsePhaseEventSchema,
  SseResultEventSchema,
  SseErrorEventSchema,
  SseDoneEventSchema,
]);

export const AiSseSequenceSchema = z
  .array(AiSseEventSchema)
  .min(4)
  .superRefine((events, context) => {
    if (events[0]?.event !== "meta") {
      context.addIssue({
        code: "custom",
        path: [0],
        message: "The first SSE event must be meta",
      });
    }
    if (events.at(-1)?.event !== "done") {
      context.addIssue({
        code: "custom",
        path: [events.length - 1],
        message: "The final SSE event must be done",
      });
    }

    const terminalEvents = events.filter(
      (event) => event.event === "result" || event.event === "error",
    );
    if (terminalEvents.length !== 1) {
      context.addIssue({
        code: "custom",
        message: "An SSE sequence must contain exactly one result or error event",
      });
    }

    const phaseEvents = events.filter((event) => event.event === "phase");
    if (phaseEvents.length === 0) {
      context.addIssue({
        code: "custom",
        message: "An SSE sequence must contain at least one phase event",
      });
    }

    const terminalIndex = events.findIndex(
      (event) => event.event === "result" || event.event === "error",
    );
    if (terminalIndex !== events.length - 2) {
      context.addIssue({
        code: "custom",
        path: [Math.max(terminalIndex, 0)],
        message: "The result or error event must immediately precede done",
      });
    }

    const operationIds = new Set(events.map((event) => event.data.operationId));
    if (operationIds.size !== 1) {
      context.addIssue({
        code: "custom",
        message: "All SSE events must use the same operation ID",
      });
    }

    const done = events.at(-1);
    const terminal = terminalEvents[0];
    const meta = events[0];
    if (
      meta?.event === "meta" &&
      terminal?.event === "result" &&
      meta.data.operation !== terminal.data.payload.operation
    ) {
      context.addIssue({
        code: "custom",
        message: "The result operation must match the meta operation",
      });
    }
    if (
      done?.event === "done" &&
      terminal?.event === "result" &&
      done.data.status !== "succeeded"
    ) {
      context.addIssue({
        code: "custom",
        message: "A result sequence must finish with succeeded status",
      });
    }
    if (
      done?.event === "done" &&
      terminal?.event === "error" &&
      done.data.status === "succeeded"
    ) {
      context.addIssue({
        code: "custom",
        message: "An error sequence cannot finish with succeeded status",
      });
    }
  });

export type AiOperation = z.infer<typeof AiOperationSchema>;
export type AiErrorCode = z.infer<typeof AiErrorCodeSchema>;
export type AiQuotaScope = z.infer<typeof AiQuotaScopeSchema>;
export type AiError = z.infer<typeof AiErrorSchema>;
export type SseMetaEvent = z.infer<typeof SseMetaEventSchema>;
export type SsePhaseEvent = z.infer<typeof SsePhaseEventSchema>;
export type AiOperationResult = z.infer<typeof AiOperationResultSchema>;
export type SseResultEvent = z.infer<typeof SseResultEventSchema>;
export type SseErrorEvent = z.infer<typeof SseErrorEventSchema>;
export type SseDoneEvent = z.infer<typeof SseDoneEventSchema>;
export type AiSseEvent = z.infer<typeof AiSseEventSchema>;
export type AiSseSequence = z.infer<typeof AiSseSequenceSchema>;
