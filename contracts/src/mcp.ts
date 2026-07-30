import { z } from "zod";

import {
  BriefStatusSchema,
  IsoDateTimeSchema,
  PlatformOutputStatusSchema,
  PlatformSchema,
  TaskKindSchema,
} from "./common.js";

export const McpBridgeSchemaVersion = 1 as const;

const optionalText = (maximum: number) => z.string().trim().max(maximum).optional();
// Swift's JSONEncoder omits nil optionals instead of writing explicit nulls.
// Accept both representations so snapshots remain compatible across clients.
const NullableUuidSchema = z.uuid().nullish();

export const McpPublishingFormatSchema = z.enum([
  "Reel",
  "Carousel",
  "Feed post",
  "Story",
  "Short video",
  "Long video",
  "Short",
  "Video",
]);

const dateOnlyInNotesPattern = new RegExp(
  String.raw`\b(?:intended\s+publish\s+date|publish(?:ing)?\s+date|scheduled?\s+(?:for|on)|post\s+on)\b[\s\S]{0,100}\b(?:mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|\d{4}-\d{2}-\d{2})\b`,
  "i",
);

export const McpBridgePillarSchema = z
  .object({
    id: z.uuid(),
    parentPillarId: NullableUuidSchema,
    name: z.string().trim().min(1).max(160),
    colorHex: z.string().regex(/^[0-9A-Fa-f]{6}$/),
    role: z.enum(["anchor", "supporting"]),
    assignedWeekdays: z.array(z.number().int().min(1).max(7)).max(7),
  })
  .strict();

export const McpBridgeOutputSchema = z
  .object({
    id: z.uuid(),
    platform: PlatformSchema,
    destination: z.string().trim().max(160),
    format: z.string().trim().max(160),
    account: z.string().trim().max(160).nullish(),
    status: PlatformOutputStatusSchema,
    targetDate: IsoDateTimeSchema.nullish(),
    includesTargetTime: z.boolean(),
    durationSeconds: z.number().int().nonnegative().max(86_400),
    title: z.string().max(500),
    caption: z.string().max(20_000),
    openingAdjustment: z.string().max(5_000),
    callToAction: z.string().max(5_000),
    editNotes: z.string().max(10_000),
    publishedUrl: z.string().max(4_096),
  })
  .strict();

export const McpBridgeTaskSchema = z
  .object({
    id: z.uuid(),
    briefId: NullableUuidSchema,
    pillarId: NullableUuidSchema,
    outputId: NullableUuidSchema,
    parentTaskId: NullableUuidSchema,
    title: z.string().trim().min(1).max(500),
    notes: z.string().max(10_000),
    kind: TaskKindSchema,
    lane: z.enum(["pillar", "production"]),
    priority: z.enum(["none", "low", "medium", "high", "urgent"]),
    completed: z.boolean(),
    targetDate: IsoDateTimeSchema.nullish(),
    includesTargetTime: z.boolean(),
  })
  .strict();

export const McpBridgePostSchema = z
  .object({
    id: z.uuid(),
    title: z.string().trim().min(1).max(500),
    premise: z.string().max(20_000),
    notes: z.string().max(20_000),
    status: BriefStatusSchema,
    pillarId: NullableUuidSchema,
    workDate: IsoDateTimeSchema.nullish(),
    includesWorkTime: z.boolean().default(false),
    durationSeconds: z.number().int().nonnegative().max(86_400),
    hook: z.string().max(10_000),
    firstFrameText: z.string().max(5_000),
    script: z.array(z.string().max(10_000)).max(100),
    ending: z.string().max(10_000),
    callToAction: z.string().max(10_000),
    createdAt: IsoDateTimeSchema,
    updatedAt: IsoDateTimeSchema,
    markdown: z.string().max(250_000),
    outputs: z.array(McpBridgeOutputSchema).max(100),
    tasks: z.array(McpBridgeTaskSchema).max(500),
    seriesId: NullableUuidSchema,
    episodeNumber: z.number().int().positive().nullish(),
    episodeLabel: z.string().max(160).nullish(),
  })
  .strict();

export const McpBridgeSeriesTaskTemplateSchema = z
  .object({
    id: z.uuid(),
    title: z.string().trim().min(1).max(500),
    notes: z.string().max(10_000),
    kind: TaskKindSchema,
    priority: z.enum(["none", "low", "medium", "high", "urgent"]),
    estimatedMinutes: z.number().int().positive().max(10_000).nullish(),
    sortOrder: z.number().int().nonnegative(),
  })
  .strict();

export const McpBridgeSeriesSchema = z
  .object({
    id: z.uuid(),
    name: z.string().trim().min(1).max(160),
    pillarId: NullableUuidSchema,
    state: z.enum(["active", "paused", "archived"]),
    defaultPlatform: PlatformSchema.nullish(),
    defaultDestinationId: NullableUuidSchema,
    defaultFormatId: NullableUuidSchema,
    defaultSocialAccountId: NullableUuidSchema,
    defaultDurationSeconds: z.number().int().positive().max(86_400).nullish(),
    cadence: z.enum(["none", "daily", "weekly", "monthly"]),
    cadenceWeekdays: z.array(z.number().int().min(1).max(7)).max(7),
    cadenceMonthDay: z.number().int().min(1).max(31).nullish(),
    cadenceEndDate: IsoDateTimeSchema.nullish(),
    cadenceIncludesTime: z.boolean(),
    taskTemplate: z.array(McpBridgeSeriesTaskTemplateSchema).max(100),
  })
  .strict();

export const McpBridgeEpisodeSlotSchema = z
  .object({
    id: z.uuid(),
    seriesId: z.uuid(),
    plannedDate: IsoDateTimeSchema,
    includesTime: z.boolean(),
    status: z.enum(["open", "converted", "skipped"]),
    convertedPostId: NullableUuidSchema,
  })
  .strict();

export const McpBridgeProfileSchema = z
  .object({
    id: z.uuid(),
    name: z.string().max(160),
    goal: z.string().max(10_000),
  })
  .strict();

export const McpBridgeSnapshotSchema = z
  .object({
    schemaVersion: z.literal(McpBridgeSchemaVersion),
    generatedAt: IsoDateTimeSchema,
    workspaceId: NullableUuidSchema,
    workspaceName: z.string().trim().max(160).nullish(),
    profile: McpBridgeProfileSchema.nullish(),
    pillars: z.array(McpBridgePillarSchema).max(100),
    posts: z.array(McpBridgePostSchema).max(5_000),
    tasks: z.array(McpBridgeTaskSchema).max(10_000),
    series: z.array(McpBridgeSeriesSchema).max(1_000).default([]),
    episodeSlots: z.array(McpBridgeEpisodeSlotSchema).max(20_000).default([]),
  })
  .strict();

const requestEnvelope = {
  schemaVersion: z.literal(McpBridgeSchemaVersion),
  id: z.uuid(),
  createdAt: IsoDateTimeSchema,
  source: z.enum(["claude", "codex", "mcp-client"]),
  workspaceId: NullableUuidSchema.optional(),
};

export const McpCreateIdeaRequestSchema = z
  .object({
    ...requestEnvelope,
    type: z.literal("createIdea"),
    payload: z
      .object({
        title: z.string().trim().min(1).max(500),
        notes: optionalText(20_000),
        pillarId: NullableUuidSchema.optional(),
      })
      .strict(),
  })
  .strict();

export const McpCreatePostDraftRequestSchema = z
  .object({
    ...requestEnvelope,
    type: z.literal("createPostDraft"),
    payload: z
      .object({
        title: z.string().trim().min(1).max(500),
        premise: optionalText(20_000),
        notes: optionalText(20_000),
        pillarId: NullableUuidSchema.optional(),
        platform: PlatformSchema.optional(),
        format: McpPublishingFormatSchema.optional(),
        hook: optionalText(10_000),
        caption: optionalText(20_000),
        callToAction: optionalText(5_000),
        targetDate: IsoDateTimeSchema.optional(),
        includesTargetTime: z.boolean().default(false),
      })
      .strict()
      .superRefine((payload, context) => {
        if (!payload.targetDate && payload.notes && dateOnlyInNotesPattern.test(payload.notes)) {
          context.addIssue({
            code: "custom",
            path: ["targetDate"],
            message: "Use targetDate and includesTargetTime for scheduling. Do not put the posting date only in notes.",
          });
        }
      }),
  })
  .strict();

export const McpUpdatePostRequestSchema = z
  .object({
    ...requestEnvelope,
    type: z.literal("updatePost"),
    payload: z
      .object({
        postId: z.uuid(),
        title: optionalText(500),
        premise: optionalText(20_000),
        notes: optionalText(20_000),
        pillarId: NullableUuidSchema.optional(),
        hook: optionalText(10_000),
        caption: optionalText(20_000),
        format: McpPublishingFormatSchema.optional(),
        callToAction: optionalText(5_000),
      })
      .strict()
      .refine(
        (payload) => Object.keys(payload).some((key) => key !== "postId"),
        "At least one post field must be provided",
      ),
  })
  .strict();

export const McpSchedulePostRequestSchema = z
  .object({
    ...requestEnvelope,
    type: z.literal("schedulePost"),
    payload: z
      .object({
        postId: z.uuid(),
        outputId: z.uuid().optional(),
        targetDate: IsoDateTimeSchema,
        includesTargetTime: z.boolean().default(true),
      })
      .strict(),
  })
  .strict();

export const McpAddTaskRequestSchema = z
  .object({
    ...requestEnvelope,
    type: z.literal("addTask"),
    payload: z
      .object({
        title: z.string().trim().min(1).max(500),
        notes: optionalText(10_000),
        postId: z.uuid().optional(),
        outputId: z.uuid().optional(),
        pillarId: z.uuid().optional(),
        kind: TaskKindSchema.default("planning"),
        lane: z.enum(["pillar", "production"]).default("production"),
        priority: z.enum(["none", "low", "medium", "high", "urgent"]).default("none"),
        targetDate: IsoDateTimeSchema.optional(),
        includesTargetTime: z.boolean().default(false),
      })
      .strict(),
  })
  .strict();

export const McpCompleteTaskRequestSchema = z
  .object({
    ...requestEnvelope,
    type: z.literal("completeTask"),
    payload: z.object({ taskId: z.uuid() }).strict(),
  })
  .strict();

export const McpBridgeChangeRequestSchema = z.discriminatedUnion("type", [
  McpCreateIdeaRequestSchema,
  McpCreatePostDraftRequestSchema,
  McpUpdatePostRequestSchema,
  McpSchedulePostRequestSchema,
  McpAddTaskRequestSchema,
  McpCompleteTaskRequestSchema,
]);

export const McpBridgeReceiptSchema = z
  .object({
    schemaVersion: z.literal(McpBridgeSchemaVersion),
    requestId: z.uuid(),
    processedAt: IsoDateTimeSchema,
    status: z.enum(["approved", "rejected", "failed"]),
    message: z.string().trim().min(1).max(2_000),
  })
  .strict();

export type McpBridgeSnapshot = z.infer<typeof McpBridgeSnapshotSchema>;
export type McpBridgePost = z.infer<typeof McpBridgePostSchema>;
export type McpBridgeTask = z.infer<typeof McpBridgeTaskSchema>;
export type McpBridgeSeries = z.infer<typeof McpBridgeSeriesSchema>;
export type McpBridgeEpisodeSlot = z.infer<typeof McpBridgeEpisodeSlotSchema>;
export type McpBridgeChangeRequest = z.infer<typeof McpBridgeChangeRequestSchema>;
export type McpBridgeReceipt = z.infer<typeof McpBridgeReceiptSchema>;
