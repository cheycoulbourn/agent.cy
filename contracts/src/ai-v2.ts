import { z } from "zod";
import { ContextualAiRequestMetadataSchema, DurationSecondsSchema } from "./common.js";
import {
  BriefRevisionFieldSchema,
  FilmingGuidanceSchema,
  ProposedTaskSchema,
  ScriptBeatSchema,
  SparkDevelopmentStateSchema,
} from "./ai.js";
import { ConversationMessageSchema, SparkSchema } from "./common.js";

const shortText = z.string().trim().min(1).max(160);
const mediumText = z.string().trim().min(1).max(2_000);
const longText = z.string().trim().min(1).max(20_000);

export const DestinationFormatSchema = z.enum(["shortVideo", "longVideo", "nonVideo"]);

export const SelectedDestinationSchema = z.object({
  destinationId: z.uuid(),
  formatId: z.uuid(),
  destinationName: shortText,
  formatName: shortText,
  format: DestinationFormatSchema,
  durationSeconds: z.number().int().min(1).max(10_800).nullable(),
}).strict();

export const SelectedDestinationsSchema = z.array(SelectedDestinationSchema).min(1).max(12).superRefine((items, context) => {
  const keys = items.map((item) => `${item.destinationId}:${item.formatId}`);
  if (new Set(keys).size !== keys.length) context.addIssue({ code: "custom", message: "Destinations and formats must be unique" });
});

export const DestinationVariantSchema = z.object({
  destinationId: z.uuid(),
  formatId: z.uuid(),
  caption: longText.optional(),
  title: shortText.optional(),
  openingAdjustment: mediumText.optional(),
  ctaAdjustment: mediumText.optional(),
  editChanges: z.array(mediumText).max(8),
}).strict();

export const ReadyBriefV2Schema = z.object({
  briefId: z.uuid(),
  title: shortText,
  premise: mediumText,
  audience: mediumText,
  creativeGoal: mediumText,
  desiredTakeaway: mediumText,
  durationSeconds: DurationSecondsSchema,
  spokenHook: mediumText,
  firstFrameText: mediumText,
  scriptBeats: z.array(ScriptBeatSchema).min(1).max(20),
  close: mediumText,
  ctaIntent: mediumText,
  filmingGuidance: FilmingGuidanceSchema,
  proposedTasks: z.array(ProposedTaskSchema).max(12),
  assumptions: z.array(mediumText).max(10),
  voiceConfidence: z.number().min(0).max(1),
  destinationVariants: z.array(DestinationVariantSchema).min(1).max(12),
}).strict().superRefine((brief, context) => {
  const keys = brief.destinationVariants.map((item) => `${item.destinationId}:${item.formatId}`);
  if (new Set(keys).size !== keys.length) context.addIssue({ code: "custom", path: ["destinationVariants"], message: "A brief may contain only one variant per destination format" });
  const milestones = brief.proposedTasks.filter((task) => task.isRecordingMilestone);
  if (milestones.length > 1 || milestones.some((task) => task.kind !== "filming")) context.addIssue({ code: "custom", path: ["proposedTasks"], message: "Only one filming task may be the recording milestone" });
});

export const ComposeBriefV2RequestSchema = ContextualAiRequestMetadataSchema.extend({
  briefId: z.uuid(),
  spark: SparkSchema,
  conversation: z.array(ConversationMessageSchema).max(16),
  workingState: SparkDevelopmentStateSchema,
  durationSeconds: DurationSecondsSchema,
  selectedDestinations: SelectedDestinationsSchema,
  additionalDirection: mediumText.optional(),
}).strict();

export const ComposeBriefV2ResultSchema = z.object({ brief: ReadyBriefV2Schema }).strict();

export const ReviseBriefV2RequestSchema = ContextualAiRequestMetadataSchema.extend({
  brief: ReadyBriefV2Schema,
  revisionNumber: z.number().int().min(1).max(10_000),
  scope: BriefRevisionFieldSchema,
  instruction: mediumText,
}).strict();

export const ReviseBriefV2ResultSchema = z.object({
  brief: ReadyBriefV2Schema,
  changedFields: z.array(BriefRevisionFieldSchema).min(1).max(16),
  explanation: mediumText,
}).strict();

export type ComposeBriefV2Request = z.infer<typeof ComposeBriefV2RequestSchema>;
export type ComposeBriefV2Result = z.infer<typeof ComposeBriefV2ResultSchema>;
export type ReviseBriefV2Request = z.infer<typeof ReviseBriefV2RequestSchema>;
export type ReviseBriefV2Result = z.infer<typeof ReviseBriefV2ResultSchema>;
