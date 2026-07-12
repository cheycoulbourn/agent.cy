import { randomUUID } from "node:crypto";
import { request as nodeHttpRequest } from "node:http";
import {
  AiSseSequenceSchema,
  ComposeBriefResultSchema,
  PrivacyDeleteResultSchema,
  ReviseBriefResultSchema,
} from "@agent-cy/contracts";
import { afterEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import type { ServerConfig } from "../src/config.js";
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
  inviteCodes: ["FOUNDER-ONE"],
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

async function harness(provider?: AiProvider) {
  const repository = new StateRepository(new MemoryStateBackend());
  const selectedProvider =
    provider ?? new FixtureAiProvider(config.model, developmentFixtures);
  const app = await buildApp({
    config,
    repository,
    provider: selectedProvider,
    clock: () => fixedNow,
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
  }>();
  return { app, repository, provider: selectedProvider, identity };
}

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

function fixtureResult(operation: keyof typeof developmentFixtures, payload: unknown) {
  const fixture = developmentFixtures[operation];
  if (typeof fixture !== "function") throw new Error(`Missing ${operation} fixture`);
  return fixture(payload);
}

describe("agent.cy server", () => {
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
      error: { code: "quota_exceeded" },
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
        installationId: identity.installationId,
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
        installationId: identity.installationId,
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
    const webhook = (id: string, type: string, periodType?: string) => ({
      api_version: "1.0",
      event: {
        id,
        type,
        event_timestamp_ms: fixedNow.getTime(),
        app_user_id: identity.installationId,
        entitlement_ids: [config.revenueCatEntitlementId],
        ...(periodType ? { period_type: periodType } : {}),
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

    const promotional = await app.inject({
      method: "POST",
      url: "/v1/webhooks/revenuecat",
      headers: auth(config.revenueCatWebhookSecret ?? ""),
      payload: webhook(
        "rc-promotional",
        "NON_RENEWING_PURCHASE",
        "PROMOTIONAL",
      ),
    });
    expect(promotional.json()).toMatchObject({ processed: true });
    const promotionalState = await repository.snapshotForTests();
    expect(promotionalState.installations[identity.installationId]?.access).toBe(
      "comped",
    );

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
