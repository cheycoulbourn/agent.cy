import { describe, expect, it } from "vitest";
import { AppError } from "../src/errors.js";
import {
  MemoryStateBackend,
  StateRepository,
  type OperationalTelemetry,
} from "../src/store.js";

const now = new Date("2026-07-11T16:00:00.000Z");

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
    ).rejects.toMatchObject({ code: "quota_exceeded" } satisfies Partial<AppError>);
  });

  it("enforces rolling short-window and global cost reservations", async () => {
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
});
