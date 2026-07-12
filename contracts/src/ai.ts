import { z } from "zod";

import {
  ContextualAiRequestMetadataSchema,
  ConversationMessageSchema,
  DurationSecondsSchema,
  PlatformSchema,
  SelectedPlatformsSchema,
  SparkSchema,
  TaskKindSchema,
  VoiceProfileSchema,
} from "./common.js";

const shortText = z.string().trim().min(1).max(160);
const mediumText = z.string().trim().min(1).max(2_000);
const longText = z.string().trim().min(1).max(20_000);
const optionalDevelopmentText = z.string().trim().min(1).max(2_000).nullable();

export const VoiceProfileRequestSchema = ContextualAiRequestMetadataSchema.extend({
  intent: z.enum(["onboarding", "teachCy"]),
  teachingInstruction: mediumText.optional(),
})
  .strict()
  .superRefine((request, context) => {
    if (
      request.intent === "onboarding" &&
      request.creatorContext.voiceExamples.length < 3
    ) {
      context.addIssue({
        code: "custom",
        path: ["creatorContext", "voiceExamples"],
        message:
          "Initial voice-profile extraction requires at least three confirmed examples",
      });
    }

    if (
      request.intent === "teachCy" &&
      request.creatorContext.voiceProfile === undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["creatorContext", "voiceProfile"],
        message: "Teach Cy requires the currently approved voice profile",
      });
    }

    if (
      request.intent === "teachCy" &&
      request.teachingInstruction === undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["teachingInstruction"],
        message: "Teach Cy requires a specific teaching instruction",
      });
    }
  });

export const VoiceProfileResultSchema = z
  .object({
    profile: VoiceProfileSchema,
    assumptions: z.array(mediumText).max(8),
    evidenceNotes: z.array(mediumText).max(8),
  })
  .strict();

export const IdeaDirectionSchema = z
  .object({
    directionId: z.string().trim().min(1).max(64),
    title: shortText,
    premise: mediumText,
    opening: mediumText,
    whyItFits: mediumText,
    assumedTakeaway: mediumText,
    assumptions: z.array(mediumText).max(5),
  })
  .strict();

export const IdeasRequestSchema = ContextualAiRequestMetadataSchema.extend({
  count: z.literal(3),
  startingPoint: mediumText.optional(),
  constraints: z.array(mediumText).max(8),
}).strict();

export const IdeasResultSchema = z
  .object({
    ideas: z.array(IdeaDirectionSchema).length(3),
  })
  .strict();

export const SparkDevelopmentFieldSchema = z.enum([
  "premise",
  "audience",
  "creativeGoal",
  "proofOrStory",
  "desiredTakeaway",
  "constraints",
]);

export const SparkDevelopmentStateSchema = z
  .object({
    premise: optionalDevelopmentText,
    audience: optionalDevelopmentText,
    creativeGoal: optionalDevelopmentText,
    proofOrStory: optionalDevelopmentText,
    desiredTakeaway: optionalDevelopmentText,
    constraints: z.array(mediumText).max(10),
  })
  .strict();

export const SparkTurnRequestSchema = ContextualAiRequestMetadataSchema.extend({
  spark: SparkSchema,
  turnNumber: z.number().int().min(1).max(8),
  composeNow: z.boolean(),
  conversation: z.array(ConversationMessageSchema).max(16),
  workingState: SparkDevelopmentStateSchema,
}).strict();

export const SparkTurnResultSchema = z
  .object({
    assistantMessage: longText,
    focusedQuestion: mediumText.nullable(),
    recommendedNextStep: z.enum([
      "answerQuestion",
      "composeNow",
      "reviewWorkingState",
    ]),
    readyToCompose: z.boolean(),
    missingFields: z.array(SparkDevelopmentFieldSchema).max(6),
    workingState: SparkDevelopmentStateSchema,
  })
  .strict();

export const ScriptBeatSchema = z
  .object({
    order: z.number().int().min(0).max(20),
    label: shortText,
    purpose: mediumText,
    script: longText,
  })
  .strict();

export const FilmingGuidanceSchema = z
  .object({
    setup: mediumText,
    shots: z.array(mediumText).max(12),
    bRoll: z.array(mediumText).max(12),
    delivery: mediumText,
    editing: mediumText,
    audio: mediumText,
    onScreenText: z.array(mediumText).max(12),
  })
  .strict();

export const ProposedTaskSchema = z
  .object({
    title: shortText,
    kind: TaskKindSchema,
    notes: mediumText.optional(),
    estimatedMinutes: z.number().int().min(5).max(480).optional(),
    isRecordingMilestone: z.boolean(),
    order: z.number().int().min(0).max(30),
  })
  .strict();

export const PlatformVariantSchema = z
  .object({
    platform: PlatformSchema,
    caption: longText.optional(),
    title: shortText.optional(),
    openingAdjustment: mediumText.optional(),
    ctaAdjustment: mediumText.optional(),
    editChanges: z.array(mediumText).max(8),
  })
  .strict()
  .refine(
    (variant) =>
      variant.caption !== undefined ||
      variant.title !== undefined ||
      variant.openingAdjustment !== undefined ||
      variant.ctaAdjustment !== undefined ||
      variant.editChanges.length > 0,
    { message: "A platform variant must contain at least one meaningful difference" },
  );

export const ReadyBriefSchema = z
  .object({
    briefId: z.uuid(),
    title: shortText,
    premise: mediumText,
    audience: mediumText,
    creativeGoal: mediumText,
    desiredTakeaway: mediumText,
    durationSeconds: DurationSecondsSchema,
    spokenHook: mediumText,
    firstFrameText: mediumText,
    scriptBeats: z.array(ScriptBeatSchema).min(1).max(12),
    close: mediumText,
    ctaIntent: mediumText,
    filmingGuidance: FilmingGuidanceSchema,
    proposedTasks: z.array(ProposedTaskSchema).max(12),
    assumptions: z.array(mediumText).max(10),
    voiceConfidence: z.number().min(0).max(1),
    platformVariants: z.array(PlatformVariantSchema).min(1).max(3),
  })
  .strict()
  .superRefine((brief, context) => {
    const platforms = brief.platformVariants.map((variant) => variant.platform);
    if (new Set(platforms).size !== platforms.length) {
      context.addIssue({
        code: "custom",
        path: ["platformVariants"],
        message: "A brief may contain only one variant per platform",
      });
    }

    const recordingMilestones = brief.proposedTasks.filter(
      (task) => task.isRecordingMilestone,
    );
    if (recordingMilestones.length > 1) {
      context.addIssue({
        code: "custom",
        path: ["proposedTasks"],
        message: "At most one proposed task may emit the recording milestone",
      });
    }
    if (
      recordingMilestones.some((task) => task.kind !== "filming")
    ) {
      context.addIssue({
        code: "custom",
        path: ["proposedTasks"],
        message: "Only a filming task may emit the recording milestone",
      });
    }
  });

export const ComposeBriefRequestSchema = ContextualAiRequestMetadataSchema.extend({
  briefId: z.uuid(),
  spark: SparkSchema,
  conversation: z.array(ConversationMessageSchema).max(16),
  workingState: SparkDevelopmentStateSchema,
  durationSeconds: DurationSecondsSchema,
  selectedPlatforms: SelectedPlatformsSchema,
  additionalDirection: mediumText.optional(),
}).strict();

export const ComposeBriefResultSchema = z
  .object({
    brief: ReadyBriefSchema,
  })
  .strict();

export const BriefRevisionFieldSchema = z.enum([
  "title",
  "premise",
  "audience",
  "creativeGoal",
  "desiredTakeaway",
  "durationSeconds",
  "spokenHook",
  "firstFrameText",
  "scriptBeats",
  "close",
  "ctaIntent",
  "filmingGuidance",
  "proposedTasks",
  "assumptions",
  "platformVariants",
  "wholeBrief",
]);

export const ReviseBriefRequestSchema = ContextualAiRequestMetadataSchema.extend({
  brief: ReadyBriefSchema,
  // This is an ordinal, not an entitlement limit. The proxy separately enforces
  // the three-revision free allowance while paid creators may keep revising.
  revisionNumber: z.number().int().min(1).max(10_000),
  scope: BriefRevisionFieldSchema,
  instruction: mediumText,
}).strict();

export const ReviseBriefResultSchema = z
  .object({
    brief: ReadyBriefSchema,
    changedFields: z.array(BriefRevisionFieldSchema).min(1).max(16),
    explanation: mediumText,
  })
  .strict();

export const ChatTurnRequestSchema = ContextualAiRequestMetadataSchema.extend({
  conversation: z.array(ConversationMessageSchema).min(1).max(24),
  relevantBriefIds: z.array(z.uuid()).max(5),
}).strict();

export const ChatSuggestionSchema = z
  .object({
    label: shortText,
    prompt: mediumText,
  })
  .strict();

export const ChatTurnResultSchema = z
  .object({
    assistantMessage: longText,
    suggestions: z.array(ChatSuggestionSchema).max(3),
    proposedAction: z
      .object({
        kind: z.enum([
          "developSpark",
          "reviseBrief",
          "createTask",
          "planWeek",
        ]),
        summary: mediumText,
      })
      .strict()
      .nullable(),
  })
  .strict();

export const RhythmSlotSchema = z
  .object({
    weekday: z.number().int().min(1).max(7),
    startMinute: z.number().int().min(0).max(1_439),
    durationMinutes: z.number().int().min(15).max(480),
    kind: TaskKindSchema,
    label: shortText,
  })
  .strict();

export const RhythmProposalRequestSchema =
  ContextualAiRequestMetadataSchema.extend({
    desiredWeeklyOutputs: z.number().int().min(1).max(14),
    availableMinutesPerWeek: z.number().int().min(30).max(10_080),
    preferredWeekdays: z.array(z.number().int().min(1).max(7)).max(7),
    existingSlots: z.array(RhythmSlotSchema).max(30),
    constraints: z.array(mediumText).max(10),
  }).strict();

export const RhythmProposalResultSchema = z
  .object({
    name: shortText,
    rationale: mediumText,
    slots: z.array(RhythmSlotSchema).min(1).max(30),
    assumptions: z.array(mediumText).max(8),
  })
  .strict();

export const ExistingTaskSummarySchema = z
  .object({
    taskId: z.uuid(),
    title: shortText,
    kind: TaskKindSchema,
    completed: z.boolean(),
  })
  .strict();

export const TasksProposalRequestSchema = ContextualAiRequestMetadataSchema.extend({
  brief: ReadyBriefSchema,
  existingTasks: z.array(ExistingTaskSummarySchema).max(30),
  instruction: mediumText.optional(),
}).strict();

export const TasksProposalResultSchema = z
  .object({
    tasks: z.array(ProposedTaskSchema).min(1).max(12),
    rationale: mediumText,
  })
  .strict();

export type VoiceProfileRequest = z.infer<typeof VoiceProfileRequestSchema>;
export type VoiceProfileResult = z.infer<typeof VoiceProfileResultSchema>;
export type IdeaDirection = z.infer<typeof IdeaDirectionSchema>;
export type IdeasRequest = z.infer<typeof IdeasRequestSchema>;
export type IdeasResult = z.infer<typeof IdeasResultSchema>;
export type SparkDevelopmentField = z.infer<
  typeof SparkDevelopmentFieldSchema
>;
export type SparkDevelopmentState = z.infer<
  typeof SparkDevelopmentStateSchema
>;
export type SparkTurnRequest = z.infer<typeof SparkTurnRequestSchema>;
export type SparkTurnResult = z.infer<typeof SparkTurnResultSchema>;
export type ScriptBeat = z.infer<typeof ScriptBeatSchema>;
export type FilmingGuidance = z.infer<typeof FilmingGuidanceSchema>;
export type ProposedTask = z.infer<typeof ProposedTaskSchema>;
export type PlatformVariant = z.infer<typeof PlatformVariantSchema>;
export type ReadyBrief = z.infer<typeof ReadyBriefSchema>;
export type ComposeBriefRequest = z.infer<typeof ComposeBriefRequestSchema>;
export type ComposeBriefResult = z.infer<typeof ComposeBriefResultSchema>;
export type BriefRevisionField = z.infer<typeof BriefRevisionFieldSchema>;
export type ReviseBriefRequest = z.infer<typeof ReviseBriefRequestSchema>;
export type ReviseBriefResult = z.infer<typeof ReviseBriefResultSchema>;
export type ChatTurnRequest = z.infer<typeof ChatTurnRequestSchema>;
export type ChatTurnResult = z.infer<typeof ChatTurnResultSchema>;
export type RhythmSlot = z.infer<typeof RhythmSlotSchema>;
export type RhythmProposalRequest = z.infer<
  typeof RhythmProposalRequestSchema
>;
export type RhythmProposalResult = z.infer<
  typeof RhythmProposalResultSchema
>;
export type ExistingTaskSummary = z.infer<typeof ExistingTaskSummarySchema>;
export type TasksProposalRequest = z.infer<typeof TasksProposalRequestSchema>;
export type TasksProposalResult = z.infer<typeof TasksProposalResultSchema>;
