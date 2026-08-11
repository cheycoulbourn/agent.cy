import { randomUUID, timingSafeEqual } from "node:crypto";
import Fastify, {
  type FastifyInstance,
  type FastifyReply,
  type FastifyRequest,
} from "fastify";
import {
  AppleAccountAuthorizationRequestSchema,
  AppleAccountAuthorizationResultSchema,
  HealthResultSchema,
  InspirationExtractRequestSchema,
  InspirationExtractResultSchema,
  InstallationRedeemRequestSchema,
  InstallationRedeemResultSchema,
  PrivacyDeleteRequestSchema,
  PrivacyDeleteResultSchema,
  RevenueCatWebhookRequestSchema,
  RevenueCatWebhookResultSchema,
  TelemetryEventsRequestSchema,
  TelemetryEventsResultSchema,
  normalizeAiOperationResult,
  type TelemetryEvent,
} from "@agent-cy/contracts";
import {
  AppleIdentityVerifier,
  type AppleIdentityVerifying,
} from "./apple-identity.js";
import {
  operationDefinitions,
  operationResultIntegrityIssue,
  type OperationDefinition,
} from "./ai-operations.js";
import type { ServerConfig } from "./config.js";
import { AppError, asAppError } from "./errors.js";
import { developmentFixtures } from "./fixtures.js";
import {
  PublicPostExtractor,
  type InspirationExtracting,
} from "./inspiration-extractor.js";
import {
  IdentityService,
  RotatingInstallationIdentityService,
  readBearerToken,
} from "./identity.js";
import {
  AnthropicAiProvider,
  FixtureAiProvider,
  modelMatchesRequested,
  type AiProvider,
  type ProviderRequest,
  type ProviderResult,
} from "./provider.js";
import { SseWriter } from "./sse.js";
import {
  JsonFileStateBackend,
  StateRepository,
  type AiOperation,
  type InstallationRecord,
  type OperationalTelemetry,
  type SubscriptionAccess,
} from "./store.js";

const camelOperation: Record<AiOperation, string> = {
  voice_profile: "voiceProfile",
  ideas: "ideas",
  inspiration_shape: "shapeInspiration",
  spark_turn: "sparkTurn",
  compose_brief: "composeBrief",
  revise_brief: "reviseBrief",
  chat_turn: "chatTurn",
  rhythm_proposal: "rhythmProposal",
  tasks_proposal: "tasksProposal",
};

const internalOperation: Record<string, AiOperation> = Object.fromEntries(
  Object.entries(camelOperation).map(([internal, camel]) => [camel, internal]),
) as Record<string, AiOperation>;

interface CachedResult {
  readonly expiresAt: number;
  readonly result: unknown;
}

const INVITE_RATE_WINDOW_MS = 10 * 60 * 1_000;
const MAX_INVITE_RATE_LIMIT_KEYS = 10_000;
const PROVIDER_RETRY_DELAYS_MS = [250, 1_000] as const;

export interface BuildAppOptions {
  readonly config: ServerConfig;
  readonly repository?: StateRepository;
  readonly provider?: AiProvider;
  readonly clock?: () => Date;
  readonly inspirationExtractor?: InspirationExtracting;
  readonly appleIdentityVerifier?: AppleIdentityVerifying;
}

export async function buildApp(options: BuildAppOptions): Promise<FastifyInstance> {
  const { config } = options;
  const clock = options.clock ?? (() => new Date());
  const repository =
    options.repository ??
    new StateRepository(new JsonFileStateBackend(config.dataFile));
  const inviteIdentity = new IdentityService(config.inviteHashSecret);
  const installationIdentity = new RotatingInstallationIdentityService(
    config.installationHashSecrets,
  );
  const provider = options.provider ?? createProvider(config);
  const inspirationExtractor = options.inspirationExtractor ?? new PublicPostExtractor();
  const appleIdentityVerifier =
    options.appleIdentityVerifier ?? new AppleIdentityVerifier(config.appleClientIds);
  const appleSubjectIdentity = new IdentityService(config.appleSubjectHashSecret);
  const activeInstallations = new Set<string>();
  const idempotencyCache = new Map<string, CachedResult>();
  const inviteRedemptionAttempts = new Map<string, number[]>();

  await repository.seedInviteHashes(
    config.inviteCodes.map((inviteCode) => inviteIdentity.hash(inviteCode)),
  );
  if (config.pilotCompedAccess) {
    const promotionStartedAt = clock();
    await repository.promoteActiveFreeJourneysToComped(
      new Date(
        promotionStartedAt.getTime() +
          config.pilotCompedDurationDays * 86_400_000,
      ),
    );
  }
  await repository.purgeTelemetryBefore(
    new Date(clock().getTime() - config.telemetryRetentionDays * 86_400_000),
  );

  const app = Fastify({
    logger: false,
    bodyLimit: config.bodyLimitBytes,
    requestIdHeader: false,
  });
  const telemetryPurgeInterval = setInterval(() => {
    const now = clock();
    void repository
      .purgeTelemetryBefore(telemetryCutoff(now, config.telemetryRetentionDays))
      .catch(() => undefined);
  }, 60 * 60 * 1_000);
  telemetryPurgeInterval.unref();
  app.addHook("onClose", async () => {
    clearInterval(telemetryPurgeInterval);
  });

  app.addHook("onSend", async (_request, reply, payload) => {
    reply.header("x-content-type-options", "nosniff");
    reply.header("referrer-policy", "no-referrer");
    return payload;
  });

  for (const definition of operationDefinitions) {
    app.post(definition.path, async (request, reply) => {
      await handleAiRequest({
        request,
        reply,
        definition,
        provider,
        repository,
        identity: installationIdentity,
        config,
        clock,
        activeInstallations,
        idempotencyCache,
      });
    });
  }

  app.post("/v1/inspiration/extract", async (request, reply) => {
    try {
      await authenticate(request, repository, installationIdentity, clock());
      const parsed = InspirationExtractRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        throw new AppError("invalid_input", "The shared post link is invalid.", {
          fieldIssues: safeFieldIssues(parsed.error.issues),
        });
      }
      const extracted = await inspirationExtractor.extract(parsed.data.canonicalUrl);
      return reply.send(InspirationExtractResultSchema.parse(extracted));
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.post("/v1/installations/redeem", async (request, reply) => {
    try {
      enforceInviteRedemptionRateLimit(
        inviteRedemptionAttempts,
        request.ip,
        clock(),
        config.shortWindowLimit,
      );
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
    const parsed = InstallationRedeemRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return sendHttpError(
        reply,
        new AppError("invalid_input", "The invitation request is invalid."),
      );
    }
    const rawCredential = installationIdentity.createInstallationToken();
    const redeemedAt = clock();
    const promotionalEntitlementEndsAt = config.pilotCompedAccess
      ? new Date(
          redeemedAt.getTime() +
            config.pilotCompedDurationDays * 86_400_000,
        )
      : null;
    try {
      const installation = await repository.redeemInvite(
        inviteIdentity.hash(parsed.data.inviteCode),
        installationIdentity.hash(rawCredential),
        redeemedAt,
        config.pilotCompedAccess ? "comped" : "freeJourney",
        promotionalEntitlementEndsAt,
      );
      const result = InstallationRedeemResultSchema.parse({
        installationId: installation.id,
        credential: rawCredential,
        access: installation.access,
        ...(config.pilotCompedAccess
          ? {
              promotionalEntitlementEndsAt:
                promotionalEntitlementEndsAt?.toISOString(),
            }
          : {}),
      });
      return reply.code(201).send(result);
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.post("/v1/accounts/apple/link", async (request, reply) => {
    try {
      const installation = await authenticate(
        request,
        repository,
        installationIdentity,
        clock(),
      );
      const rawCredential = readBearerToken(request.headers.authorization);
      const parsed = AppleAccountAuthorizationRequestSchema.safeParse(request.body);
      if (!parsed.success || !rawCredential) {
        throw new AppError("invalid_input", "The Apple sign-in request is invalid.");
      }
      const verified = await appleIdentityVerifier.verify(parsed.data);
      const account = await repository.linkInstallationToAppleAccount(
        installation.id,
        appleSubjectIdentity.hash(verified.subject),
        clock(),
      );
      return reply.send(
        AppleAccountAuthorizationResultSchema.parse({
          accountId: account.id,
          installationId: installation.id,
          credential: rawCredential,
          access: account.access,
          ...(account.promotionalEntitlementEndsAt
            ? {
                promotionalEntitlementEndsAt:
                  account.promotionalEntitlementEndsAt,
              }
            : {}),
        }),
      );
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.post("/v1/accounts/apple/sign-in", async (request, reply) => {
    try {
      const parsed = AppleAccountAuthorizationRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        throw new AppError("invalid_input", "The Apple sign-in request is invalid.");
      }
      const verified = await appleIdentityVerifier.verify(parsed.data);
      const rawCredential = installationIdentity.createInstallationToken();
      const result = await repository.createInstallationForAppleAccount(
        appleSubjectIdentity.hash(verified.subject),
        installationIdentity.hash(rawCredential),
        clock(),
      );
      return reply.code(201).send(
        AppleAccountAuthorizationResultSchema.parse({
          accountId: result.account.id,
          installationId: result.installation.id,
          credential: rawCredential,
          access: result.installation.access,
          ...(result.installation.promotionalEntitlementEndsAt
            ? {
                promotionalEntitlementEndsAt:
                  result.installation.promotionalEntitlementEndsAt,
              }
            : {}),
        }),
      );
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.post("/v1/telemetry/events", async (request, reply) => {
    try {
      const installation = await authenticate(
        request,
        repository,
        installationIdentity,
        clock(),
      );
      const parsed = TelemetryEventsRequestSchema.safeParse(request.body);
      if (!parsed.success || !sameUuid(parsed.data.installationId, installation.id)) {
        throw new AppError("invalid_input", "The telemetry envelope is invalid.");
      }
      const receivedAt = clock();
      const cutoff = telemetryCutoff(receivedAt, config.telemetryRetentionDays);
      for (const event of parsed.data.events) {
        await repository.appendTelemetry(
          clientTelemetry(installation.id, event, receivedAt),
          cutoff,
        );
      }
      const result = TelemetryEventsResultSchema.parse({
        accepted: parsed.data.events.length,
        rejected: 0,
      });
      return reply.code(202).send(result);
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.post("/v1/privacy/delete", async (request, reply) => {
    try {
      const installation = await authenticate(
        request,
        repository,
        installationIdentity,
        clock(),
      );
      const parsed = PrivacyDeleteRequestSchema.safeParse(request.body);
      if (!parsed.success || !sameUuid(parsed.data.installationId, installation.id)) {
        throw new AppError("invalid_input", "The deletion request is invalid.");
      }
      const deletedAt = clock();
      await repository.eraseInstallation(installation.id, deletedAt);
      for (const key of idempotencyCache.keys()) {
        if (key.startsWith(`${installation.id}:`)) idempotencyCache.delete(key);
      }
      const result = PrivacyDeleteResultSchema.parse({
        requestId: parsed.data.requestId,
        deletedAt: deletedAt.toISOString(),
        retained: [
          {
            category: "inviteRedemptionTombstone",
            reason: "fraudPrevention",
          },
          {
            category: "freeBriefConsumption",
            reason: "entitlementIntegrity",
          },
          {
            category: "entitlementHistory",
            reason: "entitlementIntegrity",
          },
        ],
      });
      return reply.send(result);
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.post("/v1/webhooks/revenuecat", async (request, reply) => {
    try {
      if (
        !config.revenueCatWebhookSecret ||
        !securelyMatchesBearer(
          request.headers.authorization,
          config.revenueCatWebhookSecret,
        )
      ) {
        throw new AppError("installation_invalid", "Webhook authorization failed.");
      }
      const parsed = RevenueCatWebhookRequestSchema.safeParse(request.body);
      if (!parsed.success) {
        throw new AppError("invalid_input", "The webhook payload is invalid.");
      }
      const access = revenueCatAccess(
        parsed.data.event.type,
        parsed.data.event.period_type ?? null,
      );
      const entitlementMatches =
        parsed.data.event.entitlement_ids?.includes(
          config.revenueCatEntitlementId,
        ) === true;
      let promotionalEntitlementEndsAt: Date | null = null;
      if (
        access === "comped" &&
        parsed.data.event.app_user_id &&
        entitlementMatches
      ) {
        const expirationAtMs = parsed.data.event.expiration_at_ms;
        if (expirationAtMs === null || expirationAtMs === undefined) {
          throw new AppError(
            "invalid_input",
            "Promotional entitlement expiration is required.",
          );
        }
        promotionalEntitlementEndsAt = new Date(expirationAtMs);
        if (Number.isNaN(promotionalEntitlementEndsAt.getTime())) {
          throw new AppError(
            "invalid_input",
            "Promotional entitlement expiration is invalid.",
          );
        }
      }
      const processed = parsed.data.event.app_user_id && entitlementMatches
        ? await repository.applyRevenueCatEntitlement(
            parsed.data.event.id,
            parsed.data.event.app_user_id,
            access,
            clock(),
            promotionalEntitlementEndsAt,
          )
        : false;
      const result = RevenueCatWebhookResultSchema.parse({
        received: true,
        eventId: parsed.data.event.id,
        processed,
      });
      return reply.send(result);
    } catch (error) {
      return sendHttpError(reply, asAppError(error));
    }
  });

  app.get("/healthz", async (_request, reply) => {
    return reply.send(
      HealthResultSchema.parse({
        status: "ok",
        service: "agent-cy-server",
        timestamp: clock().toISOString(),
      }),
    );
  });

  app.setErrorHandler((error, request, reply) => {
    const definition = operationDefinitions.find(
      (candidate) => candidate.path === request.routeOptions.url,
    );
    if (definition) {
      const operationId = readOperationId(request.body);
      const writer = new SseWriter(reply);
      const now = clock();
      sendMeta(writer, definition, operationId, randomUUID(), now, config.model);
      writer.send("phase", {
        operationId,
        phase: "accepted",
      });
      const payloadTooLarge =
        typeof error === "object" &&
        error !== null &&
        "code" in error &&
        error.code === "FST_ERR_CTP_BODY_TOO_LARGE";
      sendAiError(
        writer,
        operationId,
        payloadTooLarge
          ? new AppError("payload_too_large", "The request is larger than 128 KB.")
          : asAppError(error),
        clock(),
      );
      writer.close();
      return;
    }
    sendHttpError(reply, asAppError(error));
  });

  return app;
}

function createProvider(config: ServerConfig): AiProvider {
  if (config.provider === "fixture") {
    return new FixtureAiProvider(config.model, developmentFixtures);
  }
  if (!config.anthropicApiKey) {
    throw new Error("ANTHROPIC_API_KEY is required for the Anthropic provider");
  }
  return new AnthropicAiProvider(
    config.anthropicApiKey,
    config.model,
    config.requestTimeoutMs,
  );
}

interface AiHandlerContext {
  readonly request: FastifyRequest;
  readonly reply: FastifyReply;
  readonly definition: OperationDefinition;
  readonly provider: AiProvider;
  readonly repository: StateRepository;
  readonly identity: RotatingInstallationIdentityService;
  readonly config: ServerConfig;
  readonly clock: () => Date;
  readonly activeInstallations: Set<string>;
  readonly idempotencyCache: Map<string, CachedResult>;
}

async function handleAiRequest(context: AiHandlerContext): Promise<void> {
  const {
    request,
    reply,
    definition,
    provider,
    repository,
    identity,
    config,
    clock,
    activeInstallations,
    idempotencyCache,
  } = context;
  const startedAt = clock();
  const requestId = randomUUID();
  const operationId = readOperationId(request.body);
  const writer = new SseWriter(reply);
  sendMeta(writer, definition, operationId, requestId, startedAt, config.model);
  writer.send("phase", { operationId, phase: "accepted" });

  let installation: InstallationRecord | null = null;
  let reservationId: string | null = null;
  let timedOut = false;
  let providerResult: ProviderResult | null = null;
  try {
    installation = await authenticate(request, repository, identity, clock());
    const parsed = definition.requestSchema.safeParse(request.body);
    if (!parsed.success) {
      throw new AppError(
        "invalid_input",
        "Some request fields were missing or invalid.",
        { fieldIssues: safeFieldIssues(parsed.error.issues) },
      );
    }

    const cacheKey = `${installation.id}:${definition.operation}:${operationId}`;
    const cached = idempotencyCache.get(cacheKey);
    if (cached && cached.expiresAt > clock().getTime()) {
      writer.send("phase", { operationId, phase: "validating" });
      sendAiResult(writer, operationId, definition.operation, cached.result);
      writer.send("done", {
        operationId,
        status: "succeeded",
        completedAt: clock().toISOString(),
      });
      writer.close();
      return;
    }
    idempotencyCache.delete(cacheKey);

    if (activeInstallations.has(installation.id)) {
      throw new AppError(
        "conflict",
        "Another Cy request is already running for this installation.",
        { retryable: true },
      );
    }
    activeInstallations.add(installation.id);

    const freeAllowance = definition.allowanceFor(parsed.data);
    reservationId = await repository.reserveOperation({
      installationId: installation.id,
      operationId,
      operation: definition.operation,
      allowanceKey: freeAllowance.key,
      allowanceLimit: freeAllowance.limit,
      reservationCostMicros: definition.reservationCostMicros,
      shortWindowLimit: config.shortWindowLimit,
      dailyOperationLimit: config.dailyOperationLimit,
      dailyCostLimitMicros: config.dailyCostLimitMicros,
      now: clock(),
    });

    writer.send("phase", { operationId, phase: "generating" });
    const abortController = new AbortController();
    const abortOnDisconnect = () => abortController.abort();
    const responseSocket = request.raw.socket;
    request.raw.once("aborted", abortOnDisconnect);
    reply.raw.once("close", abortOnDisconnect);
    responseSocket?.once("close", abortOnDisconnect);
    if (
      request.raw.aborted ||
      reply.raw.destroyed ||
      reply.raw.writableEnded ||
      responseSocket?.destroyed
    ) {
      abortOnDisconnect();
    }
    const timeout = setTimeout(() => {
      timedOut = true;
      abortController.abort();
    }, config.requestTimeoutMs);
    timeout.unref();
    try {
      providerResult = await generateWithProviderRetries(provider, {
        operation: definition.operation,
        payload: parsed.data,
        outputSchema: definition.resultSchema,
        systemPrompt: definition.systemPrompt,
        effort: definition.effort,
        maxTokens: definition.maxTokens,
        signal: abortController.signal,
      });
    } finally {
      clearTimeout(timeout);
      request.raw.off("aborted", abortOnDisconnect);
      reply.raw.off("close", abortOnDisconnect);
      responseSocket?.off("close", abortOnDisconnect);
    }
    if (!modelMatchesRequested(providerResult.model, config.model)) {
      throw new AppError(
        "generation_invalid",
        "A result from an unexpected model was rejected.",
      );
    }

    writer.send("phase", { operationId, phase: "validating" });
    const normalizedResult = normalizeAiOperationResult(
      definition.operation,
      providerResult.output,
      parsed.data,
    );
    const result = definition.resultSchema.safeParse(normalizedResult);
    if (!result.success) {
      throw new AppError(
        "generation_invalid",
        "Cy produced an incomplete result. No partial content was saved.",
      );
    }
    const integrityIssue = operationResultIntegrityIssue(
      definition.operation,
      parsed.data,
      result.data,
    );
    if (integrityIssue !== null) {
      throw new AppError(
        "generation_invalid",
        `Cy produced a result that did not match this request (${integrityIssue}). No partial content was saved.`,
      );
    }

    const costMicros = estimateCostMicros(
      providerResult.inputTokens,
      providerResult.outputTokens,
    );
    const settledAt = clock();
    await repository.settleOperation({
      reservationId,
      outcome: "succeeded",
      actualCostMicros: costMicros,
      telemetry: executionTelemetry({
        installationId: installation.id,
        definition,
        providerResult,
        appBuild: readAppBuild(parsed.data),
        latencyMs: clock().getTime() - startedAt.getTime(),
        status: "success",
        costMicros,
        createdAt: settledAt,
        modelRequested: config.model,
      }),
      settledAt,
      telemetryCutoff: telemetryCutoff(
        settledAt,
        config.telemetryRetentionDays,
      ),
    });
    reservationId = null;
    idempotencyCache.set(cacheKey, {
      expiresAt: clock().getTime() + 15 * 60 * 1_000,
      result: result.data,
    });
    pruneIdempotencyCache(idempotencyCache, clock().getTime());

    sendAiResult(writer, operationId, definition.operation, result.data);
    writer.send("done", {
      operationId,
      status: "succeeded",
      completedAt: clock().toISOString(),
    });
  } catch (error) {
    const appError = timedOut
      ? new AppError("timeout", "Cy took too long to respond. Please try again.", {
          retryable: true,
        })
      : asAppError(error);
    if (reservationId !== null && installation !== null) {
      // Failed, cancelled, timed-out, and invalid generations never consume
      // creator allowance or credits. Only a validated result is billable.
      const failureCostMicros = 0;
      const settledAt = clock();
      await repository.settleOperation({
        reservationId,
        outcome: appError.code === "cancelled" ? "cancelled" : "failed",
        actualCostMicros: failureCostMicros,
        telemetry: executionTelemetry({
          installationId: installation.id,
          definition,
          providerResult,
          appBuild: readAppBuild(request.body),
          latencyMs: clock().getTime() - startedAt.getTime(),
          status: appError.code === "cancelled" ? "cancelled" : "error",
          costMicros: failureCostMicros,
          createdAt: settledAt,
          modelRequested: config.model,
        }),
        settledAt,
        telemetryCutoff: telemetryCutoff(
          settledAt,
          config.telemetryRetentionDays,
        ),
      });
    }
    sendAiError(writer, operationId, appError, clock());
  } finally {
    if (installation) activeInstallations.delete(installation.id);
    writer.close();
  }
}

async function generateWithProviderRetries(
  provider: AiProvider,
  request: ProviderRequest,
): Promise<ProviderResult> {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return await provider.generate(request);
    } catch (error) {
      const appError = asAppError(error);
      const retryDelay = PROVIDER_RETRY_DELAYS_MS[attempt];
      if (
        retryDelay === undefined ||
        request.signal.aborted ||
        !appError.retryable ||
        appError.code !== "upstream_unavailable"
      ) {
        throw error;
      }
      await waitForProviderRetry(retryDelay, request.signal);
    }
  }
}

function waitForProviderRetry(delayMs: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) {
    return Promise.reject(new DOMException("Aborted", "AbortError"));
  }
  return new Promise((resolve, reject) => {
    const abort = () => {
      clearTimeout(timeout);
      reject(new DOMException("Aborted", "AbortError"));
    };
    const timeout = setTimeout(() => {
      signal.removeEventListener("abort", abort);
      resolve();
    }, delayMs);
    timeout.unref();
    signal.addEventListener("abort", abort, { once: true });
  });
}

async function authenticate(
  request: FastifyRequest,
  repository: StateRepository,
  identity: RotatingInstallationIdentityService,
  now: Date,
): Promise<InstallationRecord> {
  const token = readBearerToken(request.headers.authorization);
  if (!token) {
    throw new AppError(
      "installation_invalid",
      "A valid installation credential is required.",
    );
  }
  const tokenHashes = identity.hashCandidates(token);
  const installation = await repository.findActiveInstallationByTokenHashes(
    tokenHashes,
    now,
  );
  if (!installation) {
    throw new AppError(
      "installation_invalid",
      "A valid installation credential is required.",
    );
  }
  if (installation.tokenHash !== tokenHashes[0]) {
    await repository.rotateInstallationTokenHash(
      installation.id,
      tokenHashes,
      tokenHashes[0]!,
    );
  }
  return installation;
}

function sendMeta(
  writer: SseWriter,
  definition: OperationDefinition,
  operationId: string,
  requestId: string,
  startedAt: Date,
  model: "claude-sonnet-5",
): void {
  writer.send("meta", {
    operationId,
    requestId,
    operation: camelOperation[definition.operation],
    schemaVersion: definition.resultSchemaVersion,
    model,
    startedAt: startedAt.toISOString(),
  });
}

function sendAiResult(
  writer: SseWriter,
  operationId: string,
  operation: AiOperation,
  result: unknown,
): void {
  writer.send("result", {
    operationId,
    payload: {
      operation: camelOperation[operation],
      result,
    },
  });
}

function sendAiError(
  writer: SseWriter,
  operationId: string,
  error: AppError,
  completedAt: Date,
): void {
  writer.send("error", {
    operationId,
    error: {
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      ...(error.retryAfterSeconds === null
        ? {}
        : { retryAfterSeconds: error.retryAfterSeconds }),
      ...(error.quotaScope === null ? {} : { quotaScope: error.quotaScope }),
      ...(error.fieldIssues === null ? {} : { fieldIssues: error.fieldIssues }),
    },
  });
  writer.send("done", {
    operationId,
    status: error.code === "cancelled" ? "cancelled" : "failed",
    completedAt: completedAt.toISOString(),
  });
}

function readOperationId(body: unknown): string {
  if (
    typeof body === "object" &&
    body !== null &&
    "operationId" in body &&
    typeof body.operationId === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      body.operationId,
    )
  ) {
    return body.operationId;
  }
  return randomUUID();
}

function sameUuid(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

function readAppBuild(body: unknown): string {
  if (
    typeof body === "object" &&
    body !== null &&
    "appBuild" in body &&
    typeof body.appBuild === "string"
  ) {
    return body.appBuild.slice(0, 64);
  }
  return "unknown";
}

function estimateCostMicros(inputTokens: number, outputTokens: number): number {
  // Sonnet 5 list pricing: $3 / MTok input and $15 / MTok output.
  return Math.max(0, inputTokens) * 3 + Math.max(0, outputTokens) * 15;
}

interface ExecutionTelemetryInput {
  readonly installationId: string;
  readonly definition: OperationDefinition;
  readonly providerResult: ProviderResult | null;
  readonly appBuild: string;
  readonly latencyMs: number;
  readonly status: "success" | "error" | "cancelled";
  readonly costMicros: number;
  readonly createdAt: Date;
  readonly modelRequested: string;
}

function executionTelemetry(input: ExecutionTelemetryInput): OperationalTelemetry {
  return {
    id: randomUUID(),
    installationId: input.installationId,
    category: "ai_execution",
    eventName: camelOperation[input.definition.operation],
    appBuild: input.appBuild,
    operation: input.definition.operation,
    promptVersion: input.definition.promptVersion,
    schemaVersion: input.definition.resultSchemaVersion,
    modelRequested: input.modelRequested,
    modelReturned: input.providerResult?.model ?? null,
    upstreamRequestId: input.providerResult?.upstreamRequestId ?? null,
    effort: input.definition.effort,
    inputTokens: input.providerResult?.inputTokens ?? null,
    outputTokens: input.providerResult?.outputTokens ?? null,
    latencyMs: Math.max(0, input.latencyMs),
    status: input.status,
    stopReason: input.providerResult?.stopReason ?? null,
    estimatedCostMicros: Math.max(0, input.costMicros),
    numericValue: null,
    createdAt: input.createdAt.toISOString(),
  };
}

function clientTelemetry(
  installationId: string,
  event: TelemetryEvent,
  receivedAt: Date,
): OperationalTelemetry {
  let operation: AiOperation | null = null;
  let latencyMs: number | null = null;
  let status: "success" | "error" | "cancelled" | null = null;
  let promptVersion: string | null = null;
  let schemaVersion: string | null = null;
  if (event.name === "aiOperationCompleted") {
    operation = internalOperation[event.properties.operation] ?? null;
    latencyMs = event.properties.latencyMs;
    status =
      event.properties.outcome === "succeeded"
        ? "success"
        : event.properties.outcome === "cancelled"
          ? "cancelled"
          : "error";
    promptVersion = event.properties.promptVersion;
    schemaVersion = event.properties.schemaVersion;
  }
  return {
    id: event.eventId,
    installationId,
    category: "client_event",
    eventName: event.name,
    appBuild: event.appBuild,
    operation,
    promptVersion,
    schemaVersion,
    modelRequested: null,
    modelReturned: null,
    upstreamRequestId: null,
    effort: null,
    inputTokens: null,
    outputTokens: null,
    latencyMs,
    status,
    stopReason: null,
    estimatedCostMicros: null,
    numericValue: null,
    createdAt: receivedAt.toISOString(),
  };
}

function revenueCatAccess(
  type: string,
  periodType: string | null,
): SubscriptionAccess | null {
  const grantsAccess = [
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "NON_RENEWING_PURCHASE",
    "PRODUCT_CHANGE",
    "TEMPORARY_ENTITLEMENT_GRANT",
  ].includes(type);
  if (grantsAccess && periodType === "PROMOTIONAL") return "comped";
  switch (type) {
    case "INITIAL_PURCHASE":
      return periodType === "TRIAL" ? "trial" : "paid";
    case "RENEWAL":
    case "UNCANCELLATION":
    case "NON_RENEWING_PURCHASE":
    case "PRODUCT_CHANGE":
      return "paid";
    case "TEMPORARY_ENTITLEMENT_GRANT":
      return "comped";
    case "EXPIRATION":
    case "BILLING_ISSUE":
    case "SUBSCRIPTION_PAUSED":
      return "expired";
    case "CANCELLATION":
    case "TRANSFER":
    case "TEST":
      return null;
    default:
      return null;
  }
}

function securelyMatchesBearer(
  authorization: string | undefined,
  expected: string,
): boolean {
  const actual = readBearerToken(authorization);
  if (actual === null) return false;
  const actualBuffer = Buffer.from(actual);
  const expectedBuffer = Buffer.from(expected);
  return (
    actualBuffer.length === expectedBuffer.length &&
    timingSafeEqual(actualBuffer, expectedBuffer)
  );
}

function sendHttpError(reply: FastifyReply, error: AppError): FastifyReply {
  const statusCode =
    error.code === "invalid_input"
      ? 400
      : error.code === "installation_invalid"
        ? 401
        : error.code === "rate_limited"
          ? 429
          : error.code === "conflict"
            ? 409
            : 503;
  if (error.retryAfterSeconds !== null) {
    reply.header("retry-after", String(error.retryAfterSeconds));
  }
  return reply.code(statusCode).send({
    error: {
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      ...(error.retryAfterSeconds === null
        ? {}
        : { retryAfterSeconds: error.retryAfterSeconds }),
      ...(error.quotaScope === null ? {} : { quotaScope: error.quotaScope }),
      ...(error.fieldIssues === null ? {} : { fieldIssues: error.fieldIssues }),
    },
  });
}

function safeFieldIssues(
  issues: readonly { readonly path: PropertyKey[]; readonly message: string }[],
): readonly { readonly path: readonly (string | number)[]; readonly message: string }[] {
  return issues.slice(0, 20).map((issue) => ({
    path: issue.path
      .filter((component): component is string | number =>
        typeof component === "string" || typeof component === "number",
      )
      .slice(0, 12),
    message: issue.message.slice(0, 300),
  }));
}

function pruneIdempotencyCache(cache: Map<string, CachedResult>, nowMs: number): void {
  for (const [key, value] of cache.entries()) {
    if (value.expiresAt <= nowMs) cache.delete(key);
  }
}

function enforceInviteRedemptionRateLimit(
  attemptsByAddress: Map<string, number[]>,
  address: string,
  now: Date,
  limit: number,
): void {
  const nowMs = now.getTime();
  for (const [key, attempts] of attemptsByAddress.entries()) {
    const recent = attempts.filter(
      (attemptedAt) => attemptedAt > nowMs - INVITE_RATE_WINDOW_MS,
    );
    if (recent.length === 0) attemptsByAddress.delete(key);
    else if (recent.length !== attempts.length) attemptsByAddress.set(key, recent);
  }

  const attempts = attemptsByAddress.get(address) ?? [];
  if (attempts.length >= limit) {
    const firstAttemptAt = Math.min(...attempts);
    throw new AppError(
      "rate_limited",
      "Too many invitation attempts. Please wait before trying again.",
      {
        retryable: true,
        retryAfterSeconds: Math.max(
          1,
          Math.ceil(
            (firstAttemptAt + INVITE_RATE_WINDOW_MS - nowMs) / 1_000,
          ),
        ),
      },
    );
  }

  if (
    !attemptsByAddress.has(address) &&
    attemptsByAddress.size >= MAX_INVITE_RATE_LIMIT_KEYS
  ) {
    const oldestAddress = attemptsByAddress.keys().next().value;
    if (oldestAddress !== undefined) attemptsByAddress.delete(oldestAddress);
  }
  attempts.push(nowMs);
  attemptsByAddress.set(address, attempts);
}

function telemetryCutoff(now: Date, retentionDays: number): Date {
  return new Date(now.getTime() - retentionDays * 86_400_000);
}
