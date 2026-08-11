import { randomUUID } from "node:crypto";
import { request as nodeHttpRequest } from "node:http";
import {
  AiSseSequenceSchema,
  AppleAccountAuthorizationResultSchema,
  ComposeBriefResultSchema,
  InspirationShapeResultSchema,
  InspirationExtractResultSchema,
  PrivacyDeleteResultSchema,
  ReviseBriefResultSchema,
  SparkTurnResultSchema,
} from "@agent-cy/contracts";
import { afterEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import type { AppleIdentityVerifying } from "../src/apple-identity.js";
import type { InspirationExtracting } from "../src/inspiration-extractor.js";
import type { ServerConfig } from "../src/config.js";
import { AppError } from "../src/errors.js";
import { developmentFixtures } from "../src/fixtures.js";
import { FixtureAiProvider, type AiProvider } from "../src/provider.js";
import { parseSseForTests } from "../src/sse.js";
import {
  MemoryStateBackend,
  StateRepository,
  type OperationalTelemetry,
} from "../src/store.js";

const fixedNow = new Date("2026-07-11T16:00:00.000Z");
const openApps: Array<Awaited<ReturnType<typeof buildApp>>> = [];

const config: ServerConfig = {
  host: "127.0.0.1",
  port: 3_000,
  provider: "fixture",
  anthropicApiKey: undefined,
  model: "claude-sonnet-5",
  dataFile: "/tmp/unused-agent-cy-test.json",
  inviteHashSecret: "test-invite-secret-long-enough-for-hmac",
  installationHashSecrets: ["test-install-secret-long-enough-for-hmac"],
  appleSubjectHashSecret: "test-apple-subject-secret-long-enough-for-hmac",
  appleClientIds: ["com.agentcy.app"],
  inviteCodes: ["FOUNDER-ONE"],
  pilotCompedAccess: false,
  pilotCompedDurationDays: 28,
  revenueCatWebhookSecret: "revenuecat-test-secret",
  revenueCatEntitlementId: "creator_access",
  requestTimeoutMs: 5_000,
  bodyLimitBytes: 131_072,
  shortWindowLimit: 10,
  dailyOperationLimit: 50,
  dailyCostLimitMicros: 1_000_000,
  telemetryRetentionDays: 30,
};

afterEach(async () => {
  await Promise.all(openApps.splice(0).map((app) => app.close()));
});

async function harness(
  provider?: AiProvider,
  configOverrides: Partial<ServerConfig> = {},
  inspirationExtractor?: InspirationExtracting,
  appleIdentityVerifier?: AppleIdentityVerifying,
) {
  const selectedConfig = { ...config, ...configOverrides };
  const repository = new StateRepository(new MemoryStateBackend());
  const selectedProvider =
    provider ?? new FixtureAiProvider(selectedConfig.model, developmentFixtures);
  const app = await buildApp({
    config: selectedConfig,
    repository,
    provider: selectedProvider,
    clock: () => fixedNow,
    ...(inspirationExtractor ? { inspirationExtractor } : {}),
    ...(appleIdentityVerifier ? { appleIdentityVerifier } : {}),
  });
  openApps.push(app);
  const redeem = await app.inject({
    method: "POST",
    url: "/v1/installations/redeem",
    payload: {
      inviteCode: "FOUNDER-ONE",
      appBuild: "1.0 (1)",
      platform: "ios",
    },
  });
  expect(redeem.statusCode).toBe(201);
  const identity = redeem.json<{
    installationId: string;
    credential: string;
    access: string;
    promotionalEntitlementEndsAt?: string;
  }>();
  return { app, repository, provider: selectedProvider, identity };
}

describe("Apple account access", () => {
  const authorization = {
    identityToken: "verified-identity-token",
    authorizationCode: "single-use-authorization-code",
    nonce: "raw-nonce-with-at-least-thirty-two-characters",
    appBuild: "1.0 (1)",
    platform: "macCatalyst",
  } as const;

  it("links an invited iPhone and signs another device into that account", async () => {
    const verifier: AppleIdentityVerifying = {
      verify: vi.fn(async () => ({ subject: "apple-user-one" })),
    };
    const { app, identity } = await harness(undefined, {}, undefined, verifier);

    const linked = await app.inject({
      method: "POST",
      url: "/v1/accounts/apple/link",
      headers: auth(identity.credential),
      payload: { ...authorization, platform: "ios" },
    });
    expect(linked.statusCode).toBe(200);
    const linkedIdentity = AppleAccountAuthorizationResultSchema.parse(
      linked.json(),
    );
    expect(linkedIdentity.installationId).toBe(identity.installationId);

    const signedIn = await app.inject({
      method: "POST",
      url: "/v1/accounts/apple/sign-in",
      payload: authorization,
    });
    expect(signedIn.statusCode).toBe(201);
    const macIdentity = AppleAccountAuthorizationResultSchema.parse(
      signedIn.json(),
    );
    expect(macIdentity.accountId).toBe(linkedIdentity.accountId);
    expect(macIdentity.installationId).not.toBe(linkedIdentity.installationId);
    expect(macIdentity.credential).not.toBe(linkedIdentity.credential);
    expect(verifier.verify).toHaveBeenCalledTimes(2);
  });

  it("requires a linked account and a valid Apple credential", async () => {
    const verifier: AppleIdentityVerifying = {
      verify: vi.fn(async ({ identityToken }) => {
        if (identityToken === "invalid-token") {
          throw new AppError("installation_invalid", "Apple rejected this sign-in.");
        }
        return { subject: "unlinked-apple-user" };
      }),
    };
    const { app } = await harness(undefined, {}, undefined, verifier);

    const unlinked = await app.inject({
      method: "POST",
      url: "/v1/accounts/apple/sign-in",
      payload: authorization,
    });
    expect(unlinked.statusCode).toBe(401);

    const invalid = await app.inject({
      method: "POST",
      url: "/v1/accounts/apple/sign-in",
      payload: { ...authorization, identityToken: "invalid-token" },
    });
    expect(invalid.statusCode).toBe(401);
  });
});

describe("POST /v1/inspiration/extract", () => {
  it("requires installation authentication and returns validated extraction", async () => {
    const extraction = InspirationExtractResultSchema.parse({
      canonicalUrl: "https://www.instagram.com/reel/DbQtVSaMVlB/",
      platform: "instagram",
      mediaKind: "video",
      sourceTitle: "Mari Movie on Instagram",
      creatorName: "Mari Movie",
      creatorHandle: "mariimovie",
      caption: "A useful source caption.",
      thumbnailUrl: "https://scontent.cdninstagram.com/cover.jpg",
      mediaUrls: ["https://scontent.cdninstagram.com/clip.mp4"],
      durationSeconds: 37.2,
      evidence: ["postMetadata", "caption", "creator", "video"],
    });
    const extractor: InspirationExtracting = {
      extract: vi.fn(async () => extraction),
    };
    const { app, identity } = await harness(undefined, {}, extractor);

    const unauthorized = await app.inject({
      method: "POST",
      url: "/v1/inspiration/extract",
      payload: { canonicalUrl: extraction.canonicalUrl },
    });
    expect(unauthorized.statusCode).toBe(401);

    const response = await app.inject({
      method: "POST",
      url: "/v1/inspiration/extract",
      headers: auth(identity.credential),
      payload: { canonicalUrl: extraction.canonicalUrl },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual(extraction);
  });
});

const creatorContext = {
  name: "Maya",
  primaryGoal: "Publish useful short-form videos consistently.",
  selectedPlatforms: ["instagramReels", "tiktok", "youtubeShorts"],
  voiceExamples: [
    {
      exampleId: "33333333-3333-4333-8333-333333333331",
      order: 0,
      source: "text",
      text: "Make the next move smaller and clearer.",
      creatorConfirmed: true,
    },
    {
      exampleId: "33333333-3333-4333-8333-333333333332",
      order: 1,
      source: "publicPostText",
      text: "Start with the moment that made the lesson matter.",
      creatorConfirmed: true,
    },
    {
      exampleId: "33333333-3333-4333-8333-333333333333",
      order: 2,
      source: "screenshotText",
      text: "A useful idea gives someone one thing they can try today.",
      creatorConfirmed: true,
    },
  ],
  pillars: [],
  librarySummaries: [],
} as const;

function voiceRequest(operationId = randomUUID()) {
  return {
    schemaVersion: "voice-profile.request.v1",
    promptVersion: "voice-profile.v1",
    operationId,
    appBuild: "1.0 (1)",
    assistanceMode: "collaborate",
    creatorContext,
    intent: "onboarding",
  };
}

function auth(credential: string) {
  return { authorization: `Bearer ${credential}` };
}

function composeRequest(operationId = randomUUID()) {
  return {
    schemaVersion: "compose-brief.request.v1",
    promptVersion: "compose-brief.v1",
    operationId,
    appBuild: "1.0 (1)",
    assistanceMode: "collaborate",
    creatorContext,
    briefId: randomUUID(),
    spark: {
      sparkId: randomUUID(),
      source: "text",
      text: "Make the next creative step smaller.",
    },
    conversation: [],
    workingState: {
      premise: "Make the next creative step smaller.",
      audience: "Emerging solo creators",
      creativeGoal: "Make starting feel executable",
      proofOrStory: "A large brief repeatedly delayed filming",
      desiredTakeaway: "Choose the smallest filmable version",
      constraints: ["Film at a desk"],
    },
    durationSeconds: 45,
    selectedPlatforms: ["instagramReels", "tiktok"],
  } as const;
}

function sparkTurnRequest(operationId = randomUUID()) {
  return {
    schemaVersion: "agent-cy.ai.v1",
    promptVersion: "spark-turn.v1",
    operationId,
    appBuild: "1.0 (1)",
    assistanceMode: "collaborate",
    creatorContext,
    spark: {
      sparkId: randomUUID(),
      source: "text",
      text: "Anatomy of a rough hit rate",
    },
    turnNumber: 1,
    composeNow: false,
    conversation: [],
    workingState: {
      premise: "A rough hit rate can still contain useful evidence.",
      audience: "Data-curious creators",
      creativeGoal: null,
      proofOrStory: null,
      desiredTakeaway: null,
      constraints: [],
    },
  } as const;
}

function inspirationShapeRequest(operationId = randomUUID()) {
  return {
    schemaVersion: "inspiration-shape.request.v3",
    promptVersion: "inspiration-shape.v3",
    operationId,
    appBuild: "1.0 (1)",
    assistanceMode: "collaborate",
    creatorContext: {
      ...creatorContext,
      voiceExamples: [],
      librarySummaries: [],
    },
    sourcePlatform: "instagram",
    sourceMaterial: {
      title: "A practical filming reset",
      caption: "The hook creates tension before a practical reset.",
      transcript: "I made filming easier by shrinking one setup decision.",
      visualObservations: ["Direct-to-camera opening followed by a demonstration."],
      analyzedInputs: ["caption", "audioTranscript", "videoFrames"],
      durationSeconds: 45,
    },
  } as const;
}

function fixtureResult(operation: keyof typeof developmentFixtures, payload: unknown) {
  const fixture = developmentFixtures[operation];
  if (typeof fixture !== "function") throw new Error(`Missing ${operation} fixture`);
  return fixture(payload);
}

describe("agent.cy server", () => {
  it("shapes inspiration without accepting source URL fields", async () => {
    const { app, repository, identity } = await harness();
    const rejected = await app.inject({
      method: "POST",
      url: "/v1/ai/inspiration/shape",
      headers: auth(identity.credential),
      payload: {
        ...inspirationShapeRequest(),
        sourceURL: "https://www.instagram.com/reel/private-source/",
      },
    });
    expect(rejected.body).toContain("invalid_input");

    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/inspiration/shape",
      headers: auth(identity.credential),
      payload: inspirationShapeRequest(),
    });
    const events = parseSseForTests(response.body);
    const resultEvent = events.find((event) => event.event === "result");
    const result = InspirationShapeResultSchema.parse(
      (resultEvent?.data as { payload?: { result?: unknown } } | undefined)?.payload?.result,
    );
    expect(result.originalityGuardrails).toHaveLength(2);
    const snapshot = await repository.snapshotForTests();
    expect(snapshot.installations[identity.installationId]?.allowanceCounts.ideas).toBe(1);
  });

  it("retries a temporary provider interruption within the same inspiration analysis", async () => {
    const fixtureProvider = new FixtureAiProvider(config.model, developmentFixtures);
    const generate = vi.fn<AiProvider["generate"]>(async (request) => {
      if (generate.mock.calls.length <= 2) {
        throw new AppError(
          "upstream_unavailable",
          "Cy is temporarily unavailable.",
          { retryable: true },
        );
      }
      return fixtureProvider.generate(request);
    });
    const { app, identity } = await harness({ generate });

    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/inspiration/shape",
      headers: auth(identity.credential),
      payload: inspirationShapeRequest(),
    });

    const events = parseSseForTests(response.body);
    expect(events.find((event) => event.event === "result")).toBeDefined();
    expect(events.find((event) => event.event === "done")?.data).toMatchObject({
      status: "succeeded",
    });
    expect(generate).toHaveBeenCalledTimes(3);
  });

  it("allows a different post immediately after an analysis exhausts its retries", async () => {
    const fixtureProvider = new FixtureAiProvider(config.model, developmentFixtures);
    const generate = vi.fn<AiProvider["generate"]>(async (request) => {
      if (generate.mock.calls.length <= 3) {
        throw new AppError(
          "upstream_unavailable",
          "Cy is temporarily unavailable.",
          { retryable: true },
        );
      }
      return fixtureProvider.generate(request);
    });
    const { app, identity } = await harness(
      { generate },
      { shortWindowLimit: 1 },
    );

    const failed = await app.inject({
      method: "POST",
      url: "/v1/ai/inspiration/shape",
      headers: auth(identity.credential),
      payload: inspirationShapeRequest(),
    });
    expect(
      parseSseForTests(failed.body).find((event) => event.event === "error")?.data,
    ).toMatchObject({ error: { code: "upstream_unavailable", retryable: true } });

    const nextPost = await app.inject({
      method: "POST",
      url: "/v1/ai/inspiration/shape",
      headers: auth(identity.credential),
      payload: inspirationShapeRequest(),
    });
    expect(
      parseSseForTests(nextPost.body).find((event) => event.event === "done")?.data,
    ).toMatchObject({ status: "succeeded" });
    expect(generate).toHaveBeenCalledTimes(4);
  });

  it("accepts a usable partial hosted Spark response and consumes allowance only after success", async () => {
    const provider = new FixtureAiProvider(config.model, {
      ...developmentFixtures,
      spark_turn: {
        response: "What is the one belief this post should change?",
        workingState: { premise: "Explain the rough hit rate clearly." },
        extraProviderField: true,
      },
    });
    const { app, repository, identity } = await harness(provider);
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/spark/turn",
      headers: auth(identity.credential),
      payload: sparkTurnRequest(),
    });
    expect(response.statusCode).toBe(200);
    const events = parseSseForTests(response.body);
    const resultEvent = events.find((event) => event.event === "result");
    expect(resultEvent).toBeDefined();
    expect(
      SparkTurnResultSchema.parse(
        (
          (resultEvent?.data as { payload?: { result?: unknown } } | undefined)
            ?.payload
        )?.result,
      ),
    ).toMatchObject({
      assistantMessage: "What is the one belief this post should change?",
      readyToCompose: false,
    });
    const snapshot = await repository.snapshotForTests();
    expect(snapshot.installations[identity.installationId]?.allowanceCounts.sparkTurn).toBe(1);
  });

  it("does not consume hosted Spark allowance when the provider result is unusable", async () => {
    const provider = new FixtureAiProvider(config.model, {
      ...developmentFixtures,
      spark_turn: { readyToCompose: false },
    });
    const { app, repository, identity } = await harness(provider);
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/spark/turn",
      headers: auth(identity.credential),
      payload: sparkTurnRequest(),
    });
    expect(
      parseSseForTests(response.body).find((event) => event.event === "error")?.data,
    ).toMatchObject({ error: { code: "generation_invalid" } });
    const snapshot = await repository.snapshotForTests();
    expect(snapshot.installations[identity.installationId]?.allowanceCounts.sparkTurn).toBeUndefined();
  });
  it("rate-limits invitation redemption attempts by source address", async () => {
    const { app } = await harness(undefined, { shortWindowLimit: 2 });
    const invalid = await app.inject({
      method: "POST",
      url: "/v1/installations/redeem",
      payload: {
        inviteCode: "ANOTHER-INVITE",
        appBuild: "1.0 (1)",
        platform: "ios",
      },
    });
    expect(invalid.statusCode).toBe(401);

    const limited = await app.inject({
      method: "POST",
      url: "/v1/installations/redeem",
      payload: {
        inviteCode: "ONE-MORE-INVITE",
        appBuild: "1.0 (1)",
        platform: "ios",
      },
    });
    expect(limited.statusCode).toBe(429);
    expect(limited.headers["retry-after"]).toBe("600");
    expect(limited.json()).toMatchObject({
      error: { code: "rate_limited", retryable: true },
    });
  });

  it("returns the configured promotional entitlement end for a comped pilot", async () => {
    const { identity, repository } = await harness(undefined, {
      pilotCompedAccess: true,
      pilotCompedDurationDays: 28,
    });
    expect(identity).toMatchObject({
      access: "comped",
      promotionalEntitlementEndsAt: "2026-08-08T16:00:00.000Z",
    });
    expect(
      (await repository.snapshotForTests()).installations[
        identity.installationId
      ]?.promotionalEntitlementEndsAt,
    ).toBe("2026-08-08T16:00:00.000Z");
  });

  it("gives startup-promoted free journeys the configured promotional end", async () => {
    const repository = new StateRepository(new MemoryStateBackend());
    await repository.seedInviteHashes(["existing-free-invite"]);
    const installation = await repository.redeemInvite(
      "existing-free-invite",
      "existing-free-token",
      fixedNow,
    );
    const app = await buildApp({
      config: {
        ...config,
        pilotCompedAccess: true,
        pilotCompedDurationDays: 28,
      },
      repository,
      provider: new FixtureAiProvider(config.model, developmentFixtures),
      clock: () => fixedNow,
    });
    openApps.push(app);

    expect(
      (await repository.snapshotForTests()).installations[installation.id],
    ).toMatchObject({
      access: "comped",
      promotionalEntitlementEndsAt: "2026-08-08T16:00:00.000Z",
    });
  });
  it("reports health without exposing configuration", async () => {
    const { app } = await harness();
    const response = await app.inject({ method: "GET", url: "/healthz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      status: "ok",
      service: "agent-cy-server",
      timestamp: fixedNow.toISOString(),
    });
    expect(response.body).not.toContain(config.inviteHashSecret);
    expect(response.body).not.toContain(config.installationHashSecrets[0]);
  });

  it("allows creation before examples are supplied without consuming voice extraction", async () => {
    const { app, repository, identity } = await harness();
    const request = composeRequest();
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/brief/compose",
      headers: auth(identity.credential),
      payload: {
        ...request,
        creatorContext: {
          ...request.creatorContext,
          voiceExamples: [],
        },
      },
    });

    expect(
      parseSseForTests(response.body).find((event) => event.event === "done")?.data,
    ).toMatchObject({ status: "succeeded" });
    const snapshot = await repository.snapshotForTests();
    expect(
      snapshot.installations[identity.installationId]?.allowanceCounts,
    ).toMatchObject({ composeBrief: 1 });
    expect(
      snapshot.installations[identity.installationId]?.allowanceCounts.voiceProfile,
    ).toBeUndefined();
  });

  it("rejects unconfirmed creator examples before reserving an allowance", async () => {
    const { app, repository, identity } = await harness();
    const request = voiceRequest();
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: {
        ...request,
        creatorContext: {
          ...request.creatorContext,
          voiceExamples: request.creatorContext.voiceExamples.map(
            (example, index) => ({
              ...example,
              creatorConfirmed: index === 0 ? false : true,
            }),
          ),
        },
      },
    });

    expect(
      parseSseForTests(response.body).find((event) => event.event === "error")?.data,
    ).toMatchObject({ error: { code: "invalid_input" } });
    const snapshot = await repository.snapshotForTests();
    expect(
      snapshot.installations[identity.installationId]?.allowanceCounts.voiceProfile,
    ).toBeUndefined();
  });

  it("rejects source URLs before provider execution or allowance reservation", async () => {
    const provider = new FixtureAiProvider(config.model, developmentFixtures);
    const generate = vi.spyOn(provider, "generate");
    const { app, repository, identity } = await harness(provider);
    const request = voiceRequest();
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: {
        ...request,
        creatorContext: {
          ...request.creatorContext,
          voiceExamples: request.creatorContext.voiceExamples.map(
            (example, index) =>
              index === 0
                ? { ...example, url: "https://example.com/public-post" }
                : example,
          ),
        },
      },
    });

    expect(
      parseSseForTests(response.body).find((event) => event.event === "error")?.data,
    ).toMatchObject({ error: { code: "invalid_input" } });
    expect(generate).not.toHaveBeenCalled();
    const snapshot = await repository.snapshotForTests();
    expect(
      snapshot.installations[identity.installationId]?.allowanceCounts.voiceProfile,
    ).toBeUndefined();
  });

  it("streams a validated result and replays it idempotently", async () => {
    const provider = new FixtureAiProvider(config.model, developmentFixtures);
    const generate = vi.spyOn(provider, "generate");
    const { app, identity } = await harness(provider);
    const body = voiceRequest();

    const first = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: body,
    });
    expect(first.statusCode).toBe(200);
    expect(first.headers["content-type"]).toContain("text/event-stream");
    const firstEvents = parseSseForTests(first.body).map(({ event, data }) => ({
      event,
      data,
    }));
    expect(() => AiSseSequenceSchema.parse(firstEvents)).not.toThrow();
    expect(firstEvents.map((event) => event.event)).toEqual([
      "meta",
      "phase",
      "phase",
      "phase",
      "result",
      "done",
    ]);

    const replay = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: body,
    });
    expect(() =>
      AiSseSequenceSchema.parse(parseSseForTests(replay.body)),
    ).not.toThrow();
    expect(generate).toHaveBeenCalledTimes(1);
  });

  it("does not regenerate or consume an allowance when a completed operation is retried after restart", async () => {
    const backend = new MemoryStateBackend();
    const fixtureProvider = new FixtureAiProvider(
      config.model,
      developmentFixtures,
    );
    const generate = vi.fn<AiProvider["generate"]>(async (request) => ({
      ...(await fixtureProvider.generate(request)),
      inputTokens: 10,
      outputTokens: 20,
    }));
    const provider: AiProvider = { generate };
    const firstRepository = new StateRepository(backend);
    const firstApp = await buildApp({
      config,
      repository: firstRepository,
      provider,
      clock: () => fixedNow,
    });
    openApps.push(firstApp);
    const redeem = await firstApp.inject({
      method: "POST",
      url: "/v1/installations/redeem",
      payload: {
        inviteCode: "FOUNDER-ONE",
        appBuild: "1.0 (1)",
        platform: "ios",
      },
    });
    const identity = redeem.json<{ installationId: string; credential: string }>();
    const body = voiceRequest();
    const first = await firstApp.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: body,
    });
    expect(
      parseSseForTests(first.body).find((event) => event.event === "done")?.data,
    ).toMatchObject({ status: "succeeded" });
    await firstApp.close();
    openApps.splice(openApps.indexOf(firstApp), 1);

    const reopenedRepository = new StateRepository(backend);
    const reopenedApp = await buildApp({
      config,
      repository: reopenedRepository,
      provider,
      clock: () => new Date(fixedNow.getTime() + 1_000),
    });
    openApps.push(reopenedApp);
    const retry = await reopenedApp.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: body,
    });
    expect(
      parseSseForTests(retry.body).find((event) => event.event === "error")?.data,
    ).toMatchObject({ error: { code: "conflict", retryable: false } });
    expect(generate).toHaveBeenCalledTimes(1);
    const snapshot = await reopenedRepository.snapshotForTests();
    expect(snapshot.installations[identity.installationId]?.allowanceCounts).toEqual({
      voiceProfile: 1,
    });
    expect(snapshot.costEvents).toEqual([
      expect.objectContaining({
        installationId: identity.installationId,
        costMicros: 330,
      }),
    ]);
    expect(Object.values(snapshot.operations)).toMatchObject([
      { operationId: body.operationId, outcome: "succeeded" },
    ]);
  });

  it("cancels provider generation when the SSE response socket closes", async () => {
    let markStarted!: () => void;
    let markAborted!: () => void;
    const started = new Promise<void>((resolve) => {
      markStarted = resolve;
    });
    const aborted = new Promise<void>((resolve) => {
      markAborted = resolve;
    });
    const provider: AiProvider = {
      generate: async ({ signal }) => {
        markStarted();
        return new Promise((_, reject) => {
          signal.addEventListener(
            "abort",
            () => {
              markAborted();
              reject(new DOMException("Aborted", "AbortError"));
            },
            { once: true },
          );
        });
      },
    };
    const { app, repository, identity } = await harness(provider);
    await app.listen({ host: "127.0.0.1", port: 0 });
    const address = app.server.address();
    if (!address || typeof address === "string") throw new Error("Missing address");
    const body = JSON.stringify(voiceRequest());

    await new Promise<void>((resolve, reject) => {
      const request = nodeHttpRequest(
        {
          host: "127.0.0.1",
          port: address.port,
          path: "/v1/ai/voice-profile",
          method: "POST",
          headers: {
            ...auth(identity.credential),
            "content-type": "application/json",
            "content-length": Buffer.byteLength(body),
          },
        },
        (response) => {
          response.once("data", () => {
            response.destroy();
            resolve();
          });
        },
      );
      request.once("error", reject);
      request.end(body);
    });
    await started;
    await expect(
      Promise.race([
        aborted,
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error("Provider was not cancelled")), 1_000),
        ),
      ]),
    ).resolves.toBeUndefined();
    await vi.waitFor(async () => {
      expect(
        Object.values((await repository.snapshotForTests()).operations),
      ).toContainEqual(expect.objectContaining({ outcome: "cancelled" }));
    });
  });

  it.each(["briefId", "platformVariants"] as const)(
    "rejects a composed brief whose %s does not match the request before settlement",
    async (mismatch) => {
      const provider = new FixtureAiProvider(config.model, {
        ...developmentFixtures,
        compose_brief: (payload: unknown) => {
          const output = ComposeBriefResultSchema.parse(
            fixtureResult("compose_brief", payload),
          );
          if (mismatch === "briefId") output.brief.briefId = randomUUID();
          else output.brief.platformVariants = output.brief.platformVariants.slice(0, 1);
          return output;
        },
      });
      const { app, repository, identity } = await harness(provider);
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/brief/compose",
        headers: auth(identity.credential),
        payload: composeRequest(),
      });
      expect(
        parseSseForTests(response.body).find((event) => event.event === "error")?.data,
      ).toMatchObject({ error: { code: "generation_invalid" } });
      const snapshot = await repository.snapshotForTests();
      expect(
        snapshot.installations[identity.installationId]?.allowanceCounts
          .composeBrief,
      ).toBeUndefined();
      expect(Object.values(snapshot.operations)).toContainEqual(
        expect.objectContaining({ outcome: "failed" }),
      );
    },
  );

  it("rejects undeclared out-of-scope brief revision changes before settlement", async () => {
    const compose = composeRequest();
    const currentBrief = ComposeBriefResultSchema.parse(
      fixtureResult("compose_brief", compose),
    ).brief;
    const provider = new FixtureAiProvider(config.model, {
      ...developmentFixtures,
      revise_brief: (payload: unknown) => {
        const output = ReviseBriefResultSchema.parse(
          fixtureResult("revise_brief", payload),
        );
        output.brief.audience += " Undeclared change.";
        return output;
      },
    });
    const { app, repository, identity } = await harness(provider);
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/brief/revise",
      headers: auth(identity.credential),
      payload: {
        schemaVersion: "revise-brief.request.v1",
        promptVersion: "revise-brief.v1",
        operationId: randomUUID(),
        appBuild: "1.0 (1)",
        assistanceMode: "collaborate",
        creatorContext,
        brief: currentBrief,
        revisionNumber: 1,
        scope: "spokenHook",
        instruction: "Make the hook more concrete.",
      },
    });
    expect(
      parseSseForTests(response.body).find((event) => event.event === "error")?.data,
    ).toMatchObject({ error: { code: "generation_invalid" } });
    const snapshot = await repository.snapshotForTests();
    expect(
      snapshot.installations[identity.installationId]?.allowanceCounts
        .reviseBrief,
    ).toBeUndefined();
    expect(Object.values(snapshot.operations)).toContainEqual(
      expect.objectContaining({ outcome: "failed" }),
    );
  });

  it("returns calm structured errors for missing auth and consumed allowances", async () => {
    const { app, identity } = await harness();
    const unauthenticated = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      payload: voiceRequest(),
    });
    const unauthenticatedEvents = parseSseForTests(unauthenticated.body);
    expect(() => AiSseSequenceSchema.parse(unauthenticatedEvents)).not.toThrow();
    expect(unauthenticatedEvents.find((event) => event.event === "error")?.data).toMatchObject({
      error: { code: "installation_invalid", retryable: false },
    });

    await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: voiceRequest(),
    });
    const exceeded = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: voiceRequest(),
    });
    expect(parseSseForTests(exceeded.body).find((event) => event.event === "error")?.data).toMatchObject({
      error: { code: "quota_exceeded", quotaScope: "freeAllowance" },
    });
  });

  it("rejects unexpected model results and never persists creator content", async () => {
    const base = new FixtureAiProvider("unexpected-model", developmentFixtures);
    const { app, repository, identity } = await harness(base);
    const privatePhrase = "PRIVATE VOICE SAMPLE THAT MUST NOT BE STORED";
    const request = {
      ...voiceRequest(),
      creatorContext: {
        ...creatorContext,
        voiceExamples: creatorContext.voiceExamples.map((example, index) => ({
          ...example,
          text: index === 0 ? privatePhrase : example.text,
        })),
      },
    };
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: request,
    });
    expect(parseSseForTests(response.body).find((event) => event.event === "error")?.data).toMatchObject({
      error: { code: "generation_invalid" },
    });
    expect(JSON.stringify(await repository.snapshotForTests())).not.toContain(
      privatePhrase,
    );
  });

  it("accepts strict content-free telemetry and deletes addressable metadata", async () => {
    const { app, repository, identity } = await harness();
    const oldTelemetry: OperationalTelemetry = {
      id: randomUUID(),
      installationId: identity.installationId,
      category: "client_event",
      eventName: "appOpened",
      appBuild: "1.0 (1)",
      operation: null,
      promptVersion: null,
      schemaVersion: null,
      modelRequested: null,
      modelReturned: null,
      upstreamRequestId: null,
      effort: null,
      inputTokens: null,
      outputTokens: null,
      latencyMs: null,
      status: null,
      stopReason: null,
      estimatedCostMicros: null,
      numericValue: null,
      createdAt: "2026-01-01T00:00:00.000Z",
    };
    await repository.appendTelemetry(oldTelemetry);
    const telemetry = await app.inject({
      method: "POST",
      url: "/v1/telemetry/events",
      headers: auth(identity.credential),
      payload: {
        installationId: identity.installationId.toUpperCase(),
        events: [
          {
            eventId: randomUUID(),
            occurredAt: "2099-01-01T00:00:00.000Z",
            appBuild: "1.0 (1)",
            name: "recordingCompleted",
            properties: {},
          },
        ],
      },
    });
    expect(telemetry.statusCode).toBe(202);
    expect(telemetry.json()).toEqual({ accepted: 1, rejected: 0 });
    const retainedTelemetry = (await repository.snapshotForTests()).telemetry;
    expect(retainedTelemetry).toHaveLength(1);
    expect(retainedTelemetry[0]?.createdAt).toBe(fixedNow.toISOString());

    const requestId = randomUUID();
    const deletion = await app.inject({
      method: "POST",
      url: "/v1/privacy/delete",
      headers: auth(identity.credential),
      payload: {
        requestId,
        installationId: identity.installationId.toUpperCase(),
        appBuild: "1.0 (1)",
        scope: "serverMetadata",
        confirmation: "ERASE",
      },
    });
    expect(deletion.statusCode).toBe(200);
    expect(() => PrivacyDeleteResultSchema.parse(deletion.json())).not.toThrow();
    expect((await repository.snapshotForTests()).telemetry).toHaveLength(0);

    const retryInvite = await app.inject({
      method: "POST",
      url: "/v1/installations/redeem",
      payload: {
        inviteCode: "FOUNDER-ONE",
        appBuild: "1.0 (1)",
        platform: "ios",
      },
    });
    expect(retryInvite.statusCode).toBe(401);
  });

  it("applies RevenueCat entitlements once and blocks expired AI access", async () => {
    const { app, identity, repository } = await harness();
    const webhook = (
      id: string,
      type: string,
      periodType?: string,
      expirationAtMs?: number,
    ) => ({
      api_version: "1.0",
      event: {
        id,
        type,
        event_timestamp_ms: fixedNow.getTime(),
        app_user_id: identity.installationId,
        entitlement_ids: [config.revenueCatEntitlementId],
        ...(periodType ? { period_type: periodType } : {}),
        ...(expirationAtMs ? { expiration_at_ms: expirationAtMs } : {}),
      },
    });
    const purchase = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook("rc-purchase", "INITIAL_PURCHASE", "TRIAL"),
    });
    expect(purchase.json()).toMatchObject({ processed: true });
    const duplicate = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook("rc-purchase", "INITIAL_PURCHASE", "TRIAL"),
    });
    expect(duplicate.json()).toMatchObject({ processed: false });

    const unrelatedEntitlement = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: {
        ...webhook("rc-unrelated", "NON_RENEWING_PURCHASE", "PROMOTIONAL"),
        event: {
          ...webhook("rc-unrelated", "NON_RENEWING_PURCHASE", "PROMOTIONAL").event,
          entitlement_ids: ["another_product"],
        },
      },
    });
    expect(unrelatedEntitlement.json()).toMatchObject({ processed: false });

    const promotionalEnd = fixedNow.getTime() + 7 * 24 * 60 * 60 * 1_000;
    const promotional = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook(
        "rc-promotional",
        "NON_RENEWING_PURCHASE",
        "PROMOTIONAL",
        promotionalEnd,
      ),
    });
    expect(promotional.json()).toMatchObject({ processed: true });
    const promotionalState = await repository.snapshotForTests();
    expect(promotionalState.installations[identity.installationId]?.access).toBe(
      "comped",
    );
    expect(
      promotionalState.installations[identity.installationId]
        ?.promotionalEntitlementEndsAt,
    ).toBe(new Date(promotionalEnd).toISOString());

    await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook("rc-expired", "EXPIRATION"),
    });
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: auth(identity.credential),
      payload: voiceRequest(),
    });
    expect(parseSseForTests(response.body).find((event) => event.event === "error")?.data).toMatchObject({
      error: { code: "entitlement_required" },
    });
  });

  it("acknowledges RevenueCat events for unknown and erased installations", async () => {
    const { app, identity } = await harness();
    const webhook = (id: string, installationId: string) => ({
      api_version: "1.0",
      event: {
        id,
        type: "INITIAL_PURCHASE",
        event_timestamp_ms: fixedNow.getTime(),
        app_user_id: installationId,
        entitlement_ids: [config.revenueCatEntitlementId],
        period_type: "NORMAL",
      },
    });

    const unknown = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook("rc-unknown", randomUUID()),
    });
    expect(unknown.statusCode).toBe(200);
    expect(unknown.json()).toMatchObject({
      received: true,
      eventId: "rc-unknown",
      processed: false,
    });

    const deletion = await app.inject({
      method: "POST",
      url: "/v1/privacy/delete",
      headers: auth(identity.credential),
      payload: {
        requestId: randomUUID(),
        installationId: identity.installationId,
        appBuild: "1.0 (1)",
        scope: "serverMetadata",
        confirmation: "ERASE",
      },
    });
    expect(deletion.statusCode).toBe(200);

    const erased = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook("rc-erased", identity.installationId),
    });
    expect(erased.statusCode).toBe(200);
    expect(erased.json()).toMatchObject({
      received: true,
      eventId: "rc-erased",
      processed: false,
    });
  });

  it("converts oversized AI bodies into an SSE error sequence", async () => {
    const { app, identity } = await harness();
    const response = await app.inject({
      method: "POST",
      url: "/v1/ai/voice-profile",
      headers: {
        ...auth(identity.credential),
        "content-type": "application/json",
      },
      payload: JSON.stringify({
        ...voiceRequest(),
        padding: "x".repeat(config.bodyLimitBytes),
      }),
    });
    const events = parseSseForTests(response.body);
    expect(() => AiSseSequenceSchema.parse(events)).not.toThrow();
    expect(events.find((event) => event.event === "error")?.data).toMatchObject({
      error: { code: "payload_too_large" },
    });
  });
});
