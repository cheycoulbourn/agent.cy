import { describe, expect, it } from "vitest";
import { AppError } from "../src/errors.js";
import {
  MemoryStateBackend,
  StateRepository,
  type OperationalTelemetry,
  type StateBackend,
} from "../src/store.js";

const now = new Date("2026-07-11T16:00:00.000Z");

class FailOnceMemoryStateBackend extends MemoryStateBackend {
  failNextSave = false;

  override async save(
    state: Parameters<MemoryStateBackend["save"]>[0],
  ): Promise<void> {
    if (this.failNextSave) {
      this.failNextSave = false;
      throw new Error("simulated persistence failure");
    }
    await super.save(state);
  }
}

type StoredState = Awaited<ReturnType<MemoryStateBackend["load"]>>;

class SeededStateBackend implements StateBackend {
  constructor(private state: StoredState) {}

  async load(): Promise<StoredState> {
    return structuredClone(this.state);
  }

  async save(state: StoredState): Promise<void> {
    this.state = structuredClone(state);
  }
}

async function repositoryWithInstallation() {
  const backend = new MemoryStateBackend();
  const repository = new StateRepository(backend);
  await repository.seedInviteHashes(["invite-hash"]);
  const installation = await repository.redeemInvite(
    "invite-hash",
    "token-hash",
    now,
  );
  return { backend, repository, installation };
}

describe("StateRepository", () => {
  it("does not commit mutations when persistence fails", async () => {
    const backend = new FailOnceMemoryStateBackend();
    const repository = new StateRepository(backend);
    await repository.seedInviteHashes(["committed-invite"]);

    backend.failNextSave = true;
    await expect(
      repository.seedInviteHashes(["uncommitted-invite"]),
    ).rejects.toThrow("simulated persistence failure");

    const snapshot = await repository.snapshotForTests();
    expect(snapshot.invites).toHaveProperty("committed-invite");
    expect(snapshot.invites).not.toHaveProperty("uncommitted-invite");
  });

  it("rolls back draft mutations when a transaction later rejects", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const reservationId = await repository.reserveOperation({
      installationId: installation.id,
      operationId: crypto.randomUUID(),
      operation: "ideas",
      allowanceKey: "ideas",
      allowanceLimit: 20,
      reservationCostMicros: 1_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 1,
      dailyCostLimitMicros: 100_000,
      now,
    });

    await expect(
      repository.reserveOperation({
        installationId: installation.id,
        operationId: crypto.randomUUID(),
        operation: "ideas",
        allowanceKey: "ideas",
        allowanceLimit: 20,
        reservationCostMicros: 1_000,
        shortWindowLimit: 10,
        dailyOperationLimit: 1,
        dailyCostLimitMicros: 100_000,
        now: new Date(now.getTime() + 31 * 60 * 1_000),
      }),
    ).rejects.toMatchObject({
      code: "quota_exceeded",
      quotaScope: "installationDaily",
    });

    const snapshot = await repository.snapshotForTests();
    expect(snapshot.reservations).toHaveProperty(reservationId);
    expect(Object.values(snapshot.operations)).toContainEqual(
      expect.objectContaining({ outcome: "inProgress" }),
    );
  });

  it("redeems each invitation only once and survives repository recreation", async () => {
    const { backend, installation } = await repositoryWithInstallation();
    const reopened = new StateRepository(backend);

    expect(
      await reopened.findActiveInstallationByTokenHash("token-hash"),
    ).toMatchObject({ id: installation.id, access: "freeJourney" });
    await expect(
      reopened.redeemInvite("invite-hash", "another-token", now),
    ).rejects.toMatchObject({ code: "installation_invalid" } satisfies Partial<AppError>);
  });

  it("links an invited installation to Apple and creates a separate credential for another device", async () => {
    const { repository, installation } = await repositoryWithInstallation();

    const account = await repository.linkInstallationToAppleAccount(
      installation.id,
      "hashed-apple-subject",
      now,
    );
    const signedIn = await repository.createInstallationForAppleAccount(
      "hashed-apple-subject",
      "mac-token-hash",
      new Date(now.getTime() + 1_000),
    );

    expect(account).toMatchObject({ access: "freeJourney" });
    expect(signedIn.account.id).toBe(account.id);
    expect(signedIn.installation).toMatchObject({
      accountId: account.id,
      access: "freeJourney",
      tokenHash: "mac-token-hash",
    });
    expect(signedIn.installation.id).not.toBe(installation.id);
    await expect(
      repository.findActiveInstallationByTokenHash("token-hash"),
    ).resolves.toMatchObject({ accountId: account.id });
  });

  it("does not create an installation for an Apple account that was never linked", async () => {
    const repository = new StateRepository(new MemoryStateBackend());

    await expect(
      repository.createInstallationForAppleAccount(
        "unknown-apple-subject",
        "new-device-token-hash",
        now,
      ),
    ).rejects.toMatchObject({
      code: "installation_invalid",
    } satisfies Partial<AppError>);
  });

  it("rotates a verified installation hash without accepting an unrelated hash", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    await expect(
      repository.rotateInstallationTokenHash(
        installation.id,
        ["unrelated-hash"],
        "new-token-hash",
      ),
    ).resolves.toBe(false);
    await expect(
      repository.rotateInstallationTokenHash(
        installation.id,
        ["token-hash", "new-token-hash"],
        "new-token-hash",
      ),
    ).resolves.toBe(true);
    await expect(
      repository.findActiveInstallationByTokenHash("token-hash"),
    ).resolves.toBeNull();
    await expect(
      repository.findActiveInstallationByTokenHash("new-token-hash"),
    ).resolves.toMatchObject({ id: installation.id });
  });

  it("promotes active free pilot installations without reviving erased records", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const promotionalEndsAt = new Date(now.getTime() + 28 * 24 * 60 * 60 * 1_000);
    await repository.promoteActiveFreeJourneysToComped(promotionalEndsAt);

    await expect(
      repository.findActiveInstallationByTokenHash("token-hash"),
    ).resolves.toMatchObject({
      id: installation.id,
      access: "comped",
      promotionalEntitlementEndsAt: promotionalEndsAt.toISOString(),
    });
    await expect(
      repository.reserveOperation({
        installationId: installation.id,
        operationId: crypto.randomUUID(),
        operation: "ideas",
        allowanceKey: "ideas",
        allowanceLimit: 20,
        reservationCostMicros: 1_000,
        shortWindowLimit: 10,
        dailyOperationLimit: 50,
        dailyCostLimitMicros: 100_000,
        now: promotionalEndsAt,
      }),
    ).rejects.toMatchObject({ code: "entitlement_required" });
  });

  it("allows dated comped access before expiry and rejects it afterward", async () => {
    const repository = new StateRepository(new MemoryStateBackend());
    await repository.seedInviteHashes(["comped-invite"]);
    const endsAt = new Date(now.getTime() + 60 * 60 * 1_000);
    const installation = await repository.redeemInvite(
      "comped-invite",
      "comped-token",
      now,
      "comped",
      endsAt,
    );

    const reservationId = await repository.reserveOperation({
      installationId: installation.id,
      operationId: crypto.randomUUID(),
      operation: "ideas",
      allowanceKey: "ideas",
      allowanceLimit: 20,
      reservationCostMicros: 1_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
      now: new Date(endsAt.getTime() - 1),
    });
    await repository.settleOperation({
      reservationId,
      outcome: "failed",
      actualCostMicros: 0,
      telemetry: null,
      settledAt: new Date(endsAt.getTime() - 1),
    });

    await expect(
      repository.findActiveInstallationByTokenHash("comped-token", endsAt),
    ).resolves.toMatchObject({ access: "expired" });

    await expect(
      repository.reserveOperation({
        installationId: installation.id,
        operationId: crypto.randomUUID(),
        operation: "ideas",
        allowanceKey: "ideas",
        allowanceLimit: 20,
        reservationCostMicros: 1_000,
        shortWindowLimit: 10,
        dailyOperationLimit: 50,
        dailyCostLimitMicros: 100_000,
        now: endsAt,
      }),
    ).rejects.toMatchObject({
      code: "entitlement_required",
      retryable: false,
    } satisfies Partial<AppError>);
  });

  it("keeps legacy undated comped installations active", async () => {
    const backend = new MemoryStateBackend();
    const repository = new StateRepository(backend);
    await repository.seedInviteHashes(["legacy-comped-invite"]);
    const installation = await repository.redeemInvite(
      "legacy-comped-invite",
      "legacy-comped-token",
      now,
      "comped",
    );
    const legacyState = await backend.load();
    delete (
      legacyState.installations[installation.id] as {
        promotionalEntitlementEndsAt?: string | null;
      }
    ).promotionalEntitlementEndsAt;

    const reopened = new StateRepository(new SeededStateBackend(legacyState));
    await expect(
      reopened.findActiveInstallationByTokenHash("legacy-comped-token"),
    ).resolves.toMatchObject({
      access: "comped",
      promotionalEntitlementEndsAt: null,
    });
    await expect(
      reopened.reserveOperation({
        installationId: installation.id,
        operationId: crypto.randomUUID(),
        operation: "ideas",
        allowanceKey: "ideas",
        allowanceLimit: 20,
        reservationCostMicros: 1_000,
        shortWindowLimit: 10,
        dailyOperationLimit: 50,
        dailyCostLimitMicros: 100_000,
        now: new Date("2030-01-01T00:00:00.000Z"),
      }),
    ).resolves.toEqual(expect.any(String));
  });

  it("consumes a free allowance only after a successful generation", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const input = {
      installationId: installation.id,
      operationId: crypto.randomUUID(),
      operation: "compose_brief" as const,
      allowanceKey: "composeBrief" as const,
      allowanceLimit: 1,
      reservationCostMicros: 10_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
      now,
    };

    const failedReservation = await repository.reserveOperation(input);
    await repository.settleOperation({
      reservationId: failedReservation,
      outcome: "failed",
      actualCostMicros: 0,
      telemetry: null,
      settledAt: now,
    });

    const successfulReservation = await repository.reserveOperation({
      ...input,
      operationId: crypto.randomUUID(),
      now: new Date(now.getTime() + 1_000),
    });
    await repository.settleOperation({
      reservationId: successfulReservation,
      outcome: "succeeded",
      actualCostMicros: 2_500,
      telemetry: null,
      settledAt: new Date(now.getTime() + 1_000),
    });

    await expect(
      repository.reserveOperation({
        ...input,
        operationId: crypto.randomUUID(),
        now: new Date(now.getTime() + 2_000),
      }),
    ).rejects.toMatchObject({
      code: "quota_exceeded",
      quotaScope: "freeAllowance",
    } satisfies Partial<AppError>);
  });

  it("enforces rolling short-window reservations", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const base = {
      installationId: installation.id,
      operation: "ideas" as const,
      allowanceKey: "ideas" as const,
      allowanceLimit: 20,
      reservationCostMicros: 40_000,
      shortWindowLimit: 2,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
    };
    const first = await repository.reserveOperation({
      ...base,
      operationId: crypto.randomUUID(),
      now,
    });
    const second = await repository.reserveOperation({
      ...base,
      operationId: crypto.randomUUID(),
      now: new Date(now.getTime() + 1_000),
    });

    await expect(
      repository.reserveOperation({
        ...base,
        operationId: crypto.randomUUID(),
        now: new Date(now.getTime() + 2_000),
      }),
    ).rejects.toMatchObject({
      code: "rate_limited",
      retryable: true,
      quotaScope: "installationShortWindow",
    } satisfies Partial<AppError>);

    await repository.settleOperation({
      reservationId: first,
      outcome: "failed",
      actualCostMicros: 0,
      telemetry: null,
      settledAt: new Date(now.getTime() + 3_000),
    });
    await repository.settleOperation({
      reservationId: second,
      outcome: "failed",
      actualCostMicros: 0,
      telemetry: null,
      settledAt: new Date(now.getTime() + 3_000),
    });
  });

  it("identifies the shared daily spend ceiling separately", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const base = {
      installationId: installation.id,
      operation: "ideas" as const,
      allowanceKey: "ideas" as const,
      allowanceLimit: 20,
      reservationCostMicros: 60_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
    };
    await repository.reserveOperation({
      ...base,
      operationId: crypto.randomUUID(),
      now,
    });

    await expect(
      repository.reserveOperation({
        ...base,
        operationId: crypto.randomUUID(),
        now: new Date(now.getTime() + 1_000),
      }),
    ).rejects.toMatchObject({
      code: "quota_exceeded",
      quotaScope: "globalDailySpend",
    } satisfies Partial<AppError>);
  });

  it("erases addressable metadata but retains integrity tombstones", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const reservation = await repository.reserveOperation({
      installationId: installation.id,
      operationId: crypto.randomUUID(),
      operation: "compose_brief",
      allowanceKey: "composeBrief",
      allowanceLimit: 1,
      reservationCostMicros: 10_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
      now,
    });
    await repository.settleOperation({
      reservationId: reservation,
      outcome: "succeeded",
      actualCostMicros: 1_000,
      telemetry: null,
      settledAt: now,
    });

    await repository.eraseInstallation(
      installation.id,
      new Date(now.getTime() + 10_000),
    );

    expect(
      await repository.findActiveInstallationByTokenHash("token-hash"),
    ).toBeNull();
    const snapshot = await repository.snapshotForTests();
    expect(snapshot.installations[installation.id]).toMatchObject({
      tokenHash: null,
      deletedAt: "2026-07-11T16:00:10.000Z",
      allowanceCounts: { composeBrief: 1 },
    });
    expect(snapshot.invites["invite-hash"]?.redeemedAt).not.toBeNull();
  });

  it("purges old content-free telemetry without touching durable records", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const telemetry = (createdAt: string): OperationalTelemetry => ({
      id: crypto.randomUUID(),
      installationId: installation.id,
      category: "client_event",
      eventName: "appOpened",
      appBuild: "1",
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
      createdAt,
    });
    await repository.appendTelemetry(telemetry("2026-06-01T00:00:00.000Z"));
    await repository.appendTelemetry(telemetry("2026-07-10T00:00:00.000Z"));

    expect(
      await repository.purgeTelemetryBefore(new Date("2026-07-01T00:00:00.000Z")),
    ).toBe(1);
    expect((await repository.snapshotForTests()).telemetry).toHaveLength(1);
  });

  it("prunes expired operation and RevenueCat idempotency records", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const old = new Date(now.getTime() - 91 * 24 * 60 * 60 * 1_000);
    const reservation = await repository.reserveOperation({
      installationId: installation.id,
      operationId: crypto.randomUUID(),
      operation: "ideas",
      allowanceKey: "ideas",
      allowanceLimit: 20,
      reservationCostMicros: 1_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
      now: old,
    });
    await repository.settleOperation({
      reservationId: reservation,
      outcome: "succeeded",
      actualCostMicros: 0,
      telemetry: null,
      settledAt: old,
    });
    await repository.applyRevenueCatEntitlement(
      "old-revenuecat-event",
      installation.id,
      "paid",
      old,
    );

    await repository.reserveOperation({
      installationId: installation.id,
      operationId: crypto.randomUUID(),
      operation: "ideas",
      allowanceKey: "ideas",
      allowanceLimit: 20,
      reservationCostMicros: 1_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
      now,
    });
    await repository.applyRevenueCatEntitlement(
      "current-revenuecat-event",
      installation.id,
      "paid",
      now,
    );

    const snapshot = await repository.snapshotForTests();
    expect(Object.values(snapshot.operations)).toHaveLength(1);
    expect(snapshot.processedRevenueCatEvents).toEqual([
      "current-revenuecat-event",
    ]);
    expect(snapshot.processedRevenueCatEventTimes).toEqual({
      "current-revenuecat-event": now.toISOString(),
    });
  });

  it("persists RevenueCat promotional expiry and enforces its boundary", async () => {
    const { repository, installation } = await repositoryWithInstallation();
    const promotionalEnd = new Date(now.getTime() + 60_000);

    await repository.applyRevenueCatEntitlement(
      "temporary-grant",
      installation.id,
      "comped",
      now,
      promotionalEnd,
    );

    expect(
      (await repository.snapshotForTests()).installations[installation.id],
    ).toMatchObject({
      access: "comped",
      promotionalEntitlementEndsAt: promotionalEnd.toISOString(),
    });
    await expect(
      repository.findActiveInstallationByTokenHash("token-hash", promotionalEnd),
    ).resolves.toMatchObject({ access: "expired" });
  });

  it("caps the operation ledger at exactly 10,000 after a reservation", async () => {
    const backend = new MemoryStateBackend();
    const repository = new StateRepository(backend);
    await repository.seedInviteHashes(["operation-cap-invite"]);
    const installation = await repository.redeemInvite(
      "operation-cap-invite",
      "operation-cap-token",
      now,
      "paid",
    );
    const seededState = await backend.load();
    for (let index = 0; index < 10_000; index += 1) {
      const operationId = `old-${index}`;
      const operationKey = `${installation.id}:${operationId}`;
      const timestamp = new Date(now.getTime() - (10_000 - index)).toISOString();
      seededState.operations[operationKey] = {
        operationKey,
        operationId,
        installationId: installation.id,
        operation: "ideas",
        outcome: "succeeded",
        createdAt: timestamp,
        settledAt: timestamp,
      };
    }
    const cappedRepository = new StateRepository(
      new SeededStateBackend(seededState),
    );
    const newOperationId = crypto.randomUUID();
    await cappedRepository.reserveOperation({
      installationId: installation.id,
      operationId: newOperationId,
      operation: "ideas",
      allowanceKey: "ideas",
      allowanceLimit: 20,
      reservationCostMicros: 1_000,
      shortWindowLimit: 10,
      dailyOperationLimit: 50,
      dailyCostLimitMicros: 100_000,
      now,
    });

    const snapshot = await cappedRepository.snapshotForTests();
    expect(Object.keys(snapshot.operations)).toHaveLength(10_000);
    expect(snapshot.operations).toHaveProperty(
      `${installation.id}:${newOperationId}`,
    );
    expect(snapshot.operations).not.toHaveProperty(`${installation.id}:old-0`);
  });
});
