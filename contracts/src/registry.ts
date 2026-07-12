import type { ZodType } from "zod";

import {
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
} from "./ai.js";
import {
  AiRequestMetadataSchema,
  CreatorContextSchema,
  VoiceProfileSchema,
} from "./common.js";
import {
  AiErrorSchema,
  AiSseEventSchema,
  SseDoneEventSchema,
  SseErrorEventSchema,
  SseMetaEventSchema,
  SsePhaseEventSchema,
  SseResultEventSchema,
} from "./sse.js";
import {
  HealthResultSchema,
  InstallationRedeemRequestSchema,
  InstallationRedeemResultSchema,
  PrivacyDeleteRequestSchema,
  PrivacyDeleteResultSchema,
  RevenueCatWebhookRequestSchema,
  RevenueCatWebhookResultSchema,
  TelemetryEventsRequestSchema,
  TelemetryEventsResultSchema,
} from "./supporting.js";

export const ContractSchemaRegistry = {
  AiRequestMetadata: AiRequestMetadataSchema,
  CreatorContext: CreatorContextSchema,
  VoiceProfile: VoiceProfileSchema,
  VoiceProfileRequest: VoiceProfileRequestSchema,
  VoiceProfileResult: VoiceProfileResultSchema,
  IdeasRequest: IdeasRequestSchema,
  IdeasResult: IdeasResultSchema,
  SparkTurnRequest: SparkTurnRequestSchema,
  SparkTurnResult: SparkTurnResultSchema,
  ComposeBriefRequest: ComposeBriefRequestSchema,
  ComposeBriefResult: ComposeBriefResultSchema,
  ReviseBriefRequest: ReviseBriefRequestSchema,
  ReviseBriefResult: ReviseBriefResultSchema,
  ChatTurnRequest: ChatTurnRequestSchema,
  ChatTurnResult: ChatTurnResultSchema,
  RhythmProposalRequest: RhythmProposalRequestSchema,
  RhythmProposalResult: RhythmProposalResultSchema,
  TasksProposalRequest: TasksProposalRequestSchema,
  TasksProposalResult: TasksProposalResultSchema,
  AiError: AiErrorSchema,
  AiSseEvent: AiSseEventSchema,
  SseMetaEvent: SseMetaEventSchema,
  SsePhaseEvent: SsePhaseEventSchema,
  SseResultEvent: SseResultEventSchema,
  SseErrorEvent: SseErrorEventSchema,
  SseDoneEvent: SseDoneEventSchema,
  InstallationRedeemRequest: InstallationRedeemRequestSchema,
  InstallationRedeemResult: InstallationRedeemResultSchema,
  TelemetryEventsRequest: TelemetryEventsRequestSchema,
  TelemetryEventsResult: TelemetryEventsResultSchema,
  PrivacyDeleteRequest: PrivacyDeleteRequestSchema,
  PrivacyDeleteResult: PrivacyDeleteResultSchema,
  RevenueCatWebhookRequest: RevenueCatWebhookRequestSchema,
  RevenueCatWebhookResult: RevenueCatWebhookResultSchema,
  HealthResult: HealthResultSchema,
} as const satisfies Readonly<Record<string, ZodType>>;

export const AiEndpointRegistry = {
  voiceProfile: {
    path: "/v1/ai/voice-profile",
    requestSchema: "VoiceProfileRequest",
    resultSchema: "VoiceProfileResult",
  },
  ideas: {
    path: "/v1/ai/ideas",
    requestSchema: "IdeasRequest",
    resultSchema: "IdeasResult",
  },
  sparkTurn: {
    path: "/v1/ai/spark/turn",
    requestSchema: "SparkTurnRequest",
    resultSchema: "SparkTurnResult",
  },
  composeBrief: {
    path: "/v1/ai/brief/compose",
    requestSchema: "ComposeBriefRequest",
    resultSchema: "ComposeBriefResult",
  },
  reviseBrief: {
    path: "/v1/ai/brief/revise",
    requestSchema: "ReviseBriefRequest",
    resultSchema: "ReviseBriefResult",
  },
  chatTurn: {
    path: "/v1/ai/chat/turn",
    requestSchema: "ChatTurnRequest",
    resultSchema: "ChatTurnResult",
  },
  rhythmProposal: {
    path: "/v1/ai/rhythm/propose",
    requestSchema: "RhythmProposalRequest",
    resultSchema: "RhythmProposalResult",
  },
  tasksProposal: {
    path: "/v1/ai/tasks/propose",
    requestSchema: "TasksProposalRequest",
    resultSchema: "TasksProposalResult",
  },
} as const;

export type ContractSchemaName = keyof typeof ContractSchemaRegistry;
export type AiEndpointName = keyof typeof AiEndpointRegistry;
