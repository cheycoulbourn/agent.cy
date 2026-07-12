import { z } from "zod";

import {
  AppBuildSchema,
  AssistanceModeSchema,
  BriefStatusSchema,
  IsoDateTimeSchema,
  PlatformOutputStatusSchema,
  PlatformSchema,
  SubscriptionAccessSchema,
} from "./common.js";
import { AiErrorCodeSchema, AiOperationSchema } from "./sse.js";

export const InstallationRedeemRequestSchema = z
  .object({
    inviteCode: z.string().trim().min(6).max(128),
    appBuild: AppBuildSchema,
    platform: z.literal("ios"),
    appAttestAssertion: z.string().trim().min(1).max(16_384).optional(),
  })
  .strict();

export const InstallationRedeemResultSchema = z
  .object({
    installationId: z.uuid(),
    credential: z.string().min(32).max(512),
    access: SubscriptionAccessSchema,
    credentialExpiresAt: IsoDateTimeSchema.optional(),
    promotionalEntitlementEndsAt: IsoDateTimeSchema.optional(),
  })
  .strict();

const telemetryEnvelopeShape = {
  eventId: z.uuid(),
  occurredAt: IsoDateTimeSchema,
  appBuild: AppBuildSchema,
};

export const AppOpenedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("appOpened"),
    properties: z.object({}).strict(),
  })
  .strict();

export const OnboardingCompletedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("onboardingCompleted"),
    properties: z
      .object({
        assistanceMode: AssistanceModeSchema,
        platformCount: z.number().int().min(1).max(3),
      })
      .strict(),
  })
  .strict();

export const AiOperationCompletedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("aiOperationCompleted"),
    properties: z
      .object({
        operation: AiOperationSchema,
        outcome: z.enum(["succeeded", "failed", "cancelled"]),
        latencyMs: z.number().int().nonnegative().max(3_600_000),
        schemaVersion: z.string().trim().min(1).max(32),
        promptVersion: z.string().trim().min(1).max(64),
        errorCode: AiErrorCodeSchema.optional(),
      })
      .strict(),
  })
  .strict();

export const BriefLifecycleChangedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("briefLifecycleChanged"),
    properties: z
      .object({
        from: BriefStatusSchema,
        to: BriefStatusSchema,
      })
      .strict(),
  })
  .strict();

export const RecordingCompletedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("recordingCompleted"),
    properties: z.object({}).strict(),
  })
  .strict();

export const PlatformOutputStatusChangedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("platformOutputStatusChanged"),
    properties: z
      .object({
        platform: PlatformSchema,
        from: PlatformOutputStatusSchema,
        to: PlatformOutputStatusSchema,
      })
      .strict(),
  })
  .strict();

export const SubscriptionAccessChangedTelemetryEventSchema = z
  .object({
    ...telemetryEnvelopeShape,
    name: z.literal("subscriptionAccessChanged"),
    properties: z
      .object({
        from: SubscriptionAccessSchema,
        to: SubscriptionAccessSchema,
      })
      .strict(),
  })
  .strict();

export const TelemetryEventSchema = z.discriminatedUnion("name", [
  AppOpenedTelemetryEventSchema,
  OnboardingCompletedTelemetryEventSchema,
  AiOperationCompletedTelemetryEventSchema,
  BriefLifecycleChangedTelemetryEventSchema,
  RecordingCompletedTelemetryEventSchema,
  PlatformOutputStatusChangedTelemetryEventSchema,
  SubscriptionAccessChangedTelemetryEventSchema,
]);

export const TelemetryEventsRequestSchema = z
  .object({
    installationId: z.uuid(),
    events: z.array(TelemetryEventSchema).min(1).max(100),
  })
  .strict();

export const TelemetryEventsResultSchema = z
  .object({
    accepted: z.number().int().nonnegative(),
    rejected: z.number().int().nonnegative(),
  })
  .strict();

export const PrivacyDeleteRequestSchema = z
  .object({
    requestId: z.uuid(),
    installationId: z.uuid(),
    appBuild: AppBuildSchema,
    scope: z.literal("serverMetadata"),
    confirmation: z.literal("ERASE"),
  })
  .strict();

export const PrivacyRetainedCategorySchema = z.enum([
  "inviteRedemptionTombstone",
  "freeBriefConsumption",
  "entitlementHistory",
]);

export const PrivacyDeleteResultSchema = z
  .object({
    requestId: z.uuid(),
    deletedAt: IsoDateTimeSchema,
    retained: z.array(
      z
        .object({
          category: PrivacyRetainedCategorySchema,
          reason: z.enum(["fraudPrevention", "entitlementIntegrity"]),
        })
        .strict(),
    ),
  })
  .strict();

export const KnownRevenueCatEventTypeSchema = z.enum([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "CANCELLATION",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_PAUSED",
  "EXPIRATION",
  "BILLING_ISSUE",
  "PRODUCT_CHANGE",
  "TRANSFER",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "TEST",
]);

export const RevenueCatEventTypeSchema = z
  .string()
  .trim()
  .min(1)
  .max(128)
  .regex(/^[A-Z0-9_]+$/);

export const RevenueCatWebhookRequestSchema = z
  .object({
    api_version: z.literal("1.0"),
    event: z
      .object({
        id: z.string().trim().min(1).max(128),
        type: RevenueCatEventTypeSchema,
        event_timestamp_ms: z.number().int().nonnegative(),
        app_id: z.string().trim().min(1).max(255).optional(),
        app_user_id: z.string().trim().min(1).max(255).optional(),
        original_app_user_id: z.string().trim().min(1).max(255).optional(),
        aliases: z
          .array(z.string().trim().min(1).max(255))
          .max(20)
          .optional(),
        product_id: z.string().trim().min(1).max(255).nullable().optional(),
        entitlement_ids: z
          .array(z.string().trim().min(1).max(255))
          .max(20)
          .nullable()
          .optional(),
        period_type: z
          .enum(["TRIAL", "INTRO", "NORMAL", "PROMOTIONAL", "PREPAID"])
          .nullable()
          .optional(),
        purchased_at_ms: z.number().int().nonnegative().nullable().optional(),
        expiration_at_ms: z.number().int().nonnegative().nullable().optional(),
        environment: z.enum(["SANDBOX", "PRODUCTION"]).optional(),
        store: z
          .enum(["APP_STORE", "PROMOTIONAL"])
          .optional(),
        transaction_id: z
          .string()
          .trim()
          .min(1)
          .max(255)
          .nullable()
          .optional(),
        original_transaction_id: z
          .string()
          .trim()
          .min(1)
          .max(255)
          .nullable()
          .optional(),
        transferred_from: z
          .array(z.string().trim().min(1).max(255))
          .max(20)
          .optional(),
        transferred_to: z
          .array(z.string().trim().min(1).max(255))
          .max(20)
          .optional(),
      })
      .strip(),
  })
  .strict();

export const RevenueCatWebhookResultSchema = z
  .object({
    received: z.literal(true),
    eventId: z.string().trim().min(1).max(128),
    processed: z.boolean(),
  })
  .strict();

export const HealthResultSchema = z
  .object({
    status: z.literal("ok"),
    service: z.literal("agent-cy-server"),
    timestamp: IsoDateTimeSchema,
  })
  .strict();

export type InstallationRedeemRequest = z.infer<
  typeof InstallationRedeemRequestSchema
>;
export type InstallationRedeemResult = z.infer<
  typeof InstallationRedeemResultSchema
>;
export type TelemetryEvent = z.infer<typeof TelemetryEventSchema>;
export type TelemetryEventsRequest = z.infer<typeof TelemetryEventsRequestSchema>;
export type TelemetryEventsResult = z.infer<typeof TelemetryEventsResultSchema>;
export type PrivacyDeleteRequest = z.infer<typeof PrivacyDeleteRequestSchema>;
export type PrivacyRetainedCategory = z.infer<
  typeof PrivacyRetainedCategorySchema
>;
export type PrivacyDeleteResult = z.infer<typeof PrivacyDeleteResultSchema>;
export type KnownRevenueCatEventType = z.infer<
  typeof KnownRevenueCatEventTypeSchema
>;
export type RevenueCatEventType = z.infer<typeof RevenueCatEventTypeSchema>;
export type RevenueCatWebhookRequest = z.infer<
  typeof RevenueCatWebhookRequestSchema
>;
export type RevenueCatWebhookResult = z.infer<
  typeof RevenueCatWebhookResultSchema
>;
export type HealthResult = z.infer<typeof HealthResultSchema>;
