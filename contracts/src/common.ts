import { z } from "zod";

const shortText = z.string().trim().min(1).max(160);
const mediumText = z.string().trim().min(1).max(2_000);
const longText = z.string().trim().min(1).max(20_000);

export const SchemaVersionSchema = z.string().trim().min(1).max(32);
export const PromptVersionSchema = z.string().trim().min(1).max(64);
export const OperationIdSchema = z.uuid();
export const AppBuildSchema = z.string().trim().min(1).max(64);
export const IsoDateTimeSchema = z.iso.datetime({ offset: true });
export const LocalDateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Expected a local date in YYYY-MM-DD format");

export const AssistanceModeSchema = z.enum(["drive", "collaborate", "lead"]);
export const SparkSourceSchema = z.enum([
  "text",
  "voiceTranscript",
  "cyDirection",
  "repurposedBrief",
  "sharedInspiration",
]);
export const PlatformSchema = z.enum([
  "instagramReels",
  "tiktok",
  "youtubeShorts",
  "youtubeVideo",
  "substack",
  "pinterest",
]);
export const BriefStatusSchema = z.enum([
  "spark",
  "developing",
  "ready",
  "scheduled",
  "posted",
  "archived",
]);
export const PlatformOutputStatusSchema = z.enum([
  "draft",
  "ready",
  "scheduled",
  "posted",
]);
export const TaskKindSchema = z.enum([
  "planning",
  "scripting",
  "filming",
  "editing",
  "publishing",
  "creatorBusiness",
]);
export const SubscriptionAccessSchema = z.enum([
  "freeJourney",
  "trial",
  "paid",
  "comped",
  "expired",
]);
export const DurationSecondsSchema = z.union([
  // Legacy values remain decodable so existing creator work can be edited.
  z.literal(15),
  z.literal(30),
  z.literal(45),
  z.literal(60),
  z.literal(90),
  z.literal(180),
  z.literal(300),
  z.literal(480),
  z.literal(600),
  z.literal(900),
  z.literal(1_200),
  z.literal(1_800),
  z.literal(2_700),
  z.literal(3_600),
]);

export const SelectedPlatformsSchema = z
  .array(PlatformSchema)
  .min(1)
  .max(4)
  .refine((platforms) => new Set(platforms).size === platforms.length, {
    message: "Selected platforms must be unique",
  });

export const CreatorExampleSourceSchema = z.enum([
  "text",
  "publicPostText",
  "screenshotText",
]);

export const VoiceExampleSchema = z
  .object({
    exampleId: z.uuid(),
    order: z.number().int().min(0).max(4),
    source: CreatorExampleSourceSchema,
    text: longText,
    creatorConfirmed: z.literal(true),
  })
  .strict();

export const VoiceProfileSchema = z
  .object({
    summary: mediumText,
    tone: z.array(shortText).min(1).max(8),
    sentenceStyle: mediumText,
    signatureQualities: z.array(shortText).min(1).max(8),
    phrasesToUse: z.array(shortText).max(12),
    phrasesToAvoid: z.array(shortText).max(12),
    guidance: z.array(mediumText).min(1).max(10),
    confidence: z.number().min(0).max(1),
  })
  .strict();

export const PillarSummarySchema = z
  .object({
    pillarId: z.uuid(),
    name: shortText,
    description: mediumText.optional(),
  })
  .strict();

export const BriefSummarySchema = z
  .object({
    briefId: z.uuid(),
    title: shortText,
    premise: mediumText.optional(),
    takeaway: mediumText.optional(),
    notes: z.string().trim().min(1).max(500).optional(),
    hook: z.string().trim().min(1).max(500).optional(),
    caption: z.string().trim().min(1).max(500).optional(),
    pillarId: z.uuid().optional(),
    pillarName: shortText.optional(),
    format: shortText.optional(),
    status: BriefStatusSchema,
    platforms: SelectedPlatformsSchema,
    targetDate: z.iso.datetime({ offset: true }).optional(),
    includesTargetTime: z.boolean().optional(),
    postedAt: z.iso.datetime({ offset: true }).optional(),
    taskCount: z.number().int().nonnegative().max(100).default(0),
    completedTaskCount: z.number().int().nonnegative().max(100).default(0),
  })
  .strict()
  .refine((summary) => summary.completedTaskCount <= summary.taskCount, {
    message: "Completed task count cannot exceed task count",
  });

export const TaskSummarySchema = z
  .object({
    taskId: z.uuid(),
    title: shortText,
    kind: TaskKindSchema,
    priority: z.enum(["none", "high", "urgent"]),
    isCompleted: z.boolean(),
    targetDate: z.iso.datetime({ offset: true }).optional(),
    includesTargetTime: z.boolean(),
    postId: z.uuid().optional(),
    pillarId: z.uuid().optional(),
  })
  .strict();

export const CreatorContextSchema = z
  .object({
    name: z.string().trim().min(1).max(80),
    primaryGoal: mediumText,
    selectedPlatforms: SelectedPlatformsSchema,
    voiceExamples: z
      .array(VoiceExampleSchema)
      .max(5)
      .describe(
        "Creator-confirmed example text only; combined UTF-8 text is limited to 40,000 bytes",
      ),
    voiceProfile: VoiceProfileSchema.optional(),
    pillars: z.array(PillarSummarySchema).max(10),
    librarySummaries: z.array(BriefSummarySchema).max(20),
    taskSummaries: z.array(TaskSummarySchema).max(20).default([]),
  })
  .strict()
  .superRefine((contextValue, refinementContext) => {
    const exampleIds = contextValue.voiceExamples.map(
      (example) => example.exampleId,
    );
    const exampleOrders = contextValue.voiceExamples.map((example) => example.order);
    if (new Set(exampleIds).size !== exampleIds.length) {
      refinementContext.addIssue({
        code: "custom",
        path: ["voiceExamples"],
        message: "Voice example IDs must be unique",
      });
    }
    if (new Set(exampleOrders).size !== exampleOrders.length) {
      refinementContext.addIssue({
        code: "custom",
        path: ["voiceExamples"],
        message: "Voice example order values must be unique",
      });
    }
    const exampleTextBytes = contextValue.voiceExamples.reduce(
      (total, example) => total + Buffer.byteLength(example.text, "utf8"),
      0,
    );
    if (exampleTextBytes > 40_000) {
      refinementContext.addIssue({
        code: "custom",
        path: ["voiceExamples"],
        message: "Creator example text must not exceed 40 KB in one request",
      });
    }
  });

export const AiRequestMetadataSchema = z
  .object({
    schemaVersion: SchemaVersionSchema,
    promptVersion: PromptVersionSchema,
    operationId: OperationIdSchema,
    appBuild: AppBuildSchema,
    assistanceMode: AssistanceModeSchema,
  })
  .strict();

export const ContextualAiRequestMetadataSchema = AiRequestMetadataSchema.extend({
  creatorContext: CreatorContextSchema,
}).strict();

export const ConversationMessageSchema = z
  .object({
    messageId: z.uuid(),
    role: z.enum(["user", "assistant"]),
    content: longText,
  })
  .strict();

export const SparkSchema = z
  .object({
    sparkId: z.uuid(),
    source: SparkSourceSchema,
    text: longText,
    sourceBriefId: z.uuid().optional(),
  })
  .strict();

export type AssistanceMode = z.infer<typeof AssistanceModeSchema>;
export type SparkSource = z.infer<typeof SparkSourceSchema>;
export type Platform = z.infer<typeof PlatformSchema>;
export type BriefStatus = z.infer<typeof BriefStatusSchema>;
export type PlatformOutputStatus = z.infer<typeof PlatformOutputStatusSchema>;
export type TaskKind = z.infer<typeof TaskKindSchema>;
export type SubscriptionAccess = z.infer<typeof SubscriptionAccessSchema>;
export type DurationSeconds = z.infer<typeof DurationSecondsSchema>;
export type CreatorExampleSource = z.infer<
  typeof CreatorExampleSourceSchema
>;
export type VoiceExample = z.infer<typeof VoiceExampleSchema>;
export type VoiceProfile = z.infer<typeof VoiceProfileSchema>;
export type PillarSummary = z.infer<typeof PillarSummarySchema>;
export type BriefSummary = z.infer<typeof BriefSummarySchema>;
export type TaskSummary = z.infer<typeof TaskSummarySchema>;
export type CreatorContext = z.infer<typeof CreatorContextSchema>;
export type AiRequestMetadata = z.infer<typeof AiRequestMetadataSchema>;
export type ContextualAiRequestMetadata = z.infer<
  typeof ContextualAiRequestMetadataSchema
>;
export type ConversationMessage = z.infer<typeof ConversationMessageSchema>;
export type Spark = z.infer<typeof SparkSchema>;
