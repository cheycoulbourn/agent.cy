import { z } from "zod";

import { AiErrorCodeSchema, AiQuotaScopeSchema } from "./sse.js";

export const LocalCySchemaVersion = 1 as const;

export const LocalCyOperationSchema = z.enum([
  "voiceProfile",
  "ideas",
  "sparkTurn",
  "composeBrief",
  "reviseBrief",
  "chatTurn",
  "rhythmProposal",
  "tasksProposal",
]);

export const LocalCyRequestSchema = z
  .object({
    schemaVersion: z.literal(LocalCySchemaVersion),
    id: z.uuid(),
    operation: LocalCyOperationSchema,
    createdAt: z.iso.datetime({ offset: true }),
    workspaceId: z.uuid().nullish(),
    payload: z.unknown(),
  })
  .strict();

const localCyResponseEnvelope = {
  schemaVersion: z.literal(LocalCySchemaVersion),
  id: z.uuid(),
  operation: LocalCyOperationSchema,
  completedAt: z.iso.datetime({ offset: true }),
};

export const LocalCySuccessResponseSchema = z
  .object({
    ...localCyResponseEnvelope,
    status: z.literal("succeeded"),
    model: z.string().trim().min(1).max(160),
    result: z.unknown(),
  })
  .strict();

export const LocalCyFailureResponseSchema = z
  .object({
    ...localCyResponseEnvelope,
    status: z.literal("failed"),
    error: z
      .object({
        code: AiErrorCodeSchema,
        message: z.string().trim().min(1).max(2_000),
        retryable: z.boolean(),
        retryAfterSeconds: z.number().int().nonnegative().nullish(),
        quotaScope: AiQuotaScopeSchema.nullish(),
      })
      .strict(),
  })
  .strict();

export const LocalCyResponseSchema = z.discriminatedUnion("status", [
  LocalCySuccessResponseSchema,
  LocalCyFailureResponseSchema,
]);

export const LocalCyRuntimeStatusSchema = z
  .object({
    schemaVersion: z.literal(LocalCySchemaVersion),
    status: z.enum(["ready", "working", "needsLogin", "error"]),
    updatedAt: z.iso.datetime({ offset: true }),
    model: z.string().trim().min(1).max(160),
    message: z.string().trim().min(1).max(500),
  })
  .strict();

export const LocalCyConnectionConfigSchema = z
  .object({
    schemaVersion: z.literal(LocalCySchemaVersion),
    baseURL: z.url().refine((value) => value.startsWith("http://") || value.startsWith("https://")),
    token: z.string().min(32).max(256),
    updatedAt: z.iso.datetime({ offset: true }),
  })
  .strict();

export type LocalCyOperation = z.infer<typeof LocalCyOperationSchema>;
export type LocalCyRequest = z.infer<typeof LocalCyRequestSchema>;
export type LocalCyResponse = z.infer<typeof LocalCyResponseSchema>;
export type LocalCyRuntimeStatus = z.infer<typeof LocalCyRuntimeStatusSchema>;
export type LocalCyConnectionConfig = z.infer<typeof LocalCyConnectionConfigSchema>;
