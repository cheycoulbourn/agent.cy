import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { randomUUID } from "node:crypto";
import { AppError } from "./errors.js";

export type SubscriptionAccess =
  | "freeJourney"
  | "trial"
  | "paid"
  | "comped"
  | "expired";

export type AiOperation =
  | "voice_profile"
  | "ideas"
  | "spark_turn"
  | "compose_brief"
  | "revise_brief"
  | "chat_turn"
  | "rhythm_proposal"
  | "tasks_proposal";

export type AllowanceKey =
  | "voiceProfile"
  | "teachCy"
  | "ideas"
  | "sparkTurn"
  | "composeBrief"
  | "reviseBrief";

export interface InstallationRecord {
  readonly id: string;
  tokenHash: string | null;
  access: SubscriptionAccess;
  promotionalEntitlementEndsAt: string | null;
  readonly createdAt: string;
  deletedAt: string | null;
  allowanceCounts: Partial<Record<AllowanceKey, number>>;
}

interface InviteRecord {
  readonly codeHash: string;
  redeemedAt: string | null;
  installationId: string | null;
}

interface QuotaEvent {
  readonly installationId: string;
  readonly at: string;
}

interface CostEvent {
  readonly installationId: string;
  readonly at: string;
  readonly costMicros: number;
}

interface ReservationRecord {
  readonly id: string;
  readonly installationId: string;
  readonly allowanceKey: AllowanceKey | null;
  readonly costMicros: number;
  readonly createdAt: string;
  readonly operationKey: string | null;
}

export type AiOperationOutcome =
  | "inProgress"
  | "succeeded"
  | "failed"
  | "cancelled";

interface AiOperationRecord {
  readonly operationKey: string;
  readonly operationId: string;
  readonly installationId: string;
  readonly operation: AiOperation;
  outcome: AiOperationOutcome;
  readonly createdAt: string;
  settledAt: string | null;
}

export interface OperationalTelemetry {
  readonly id: string;
  readonly installationId: string;
  readonly category: "ai_execution" | "client_event";
  readonly eventName: string;
  readonly appBuild: string;
  readonly operation: AiOperation | null;
  readonly promptVersion: string | null;
  readonly schemaVersion: string | null;
  readonly modelRequested: string | null;
  readonly modelReturned: string | null;
  readonly upstreamRequestId: string | null;
  readonly effort: "low" | "medium" | null;
  readonly inputTokens: number | null;
  readonly outputTokens: number | null;
  readonly latencyMs: number | null;
  readonly status: "success" | "error" | "cancelled" | null;
  readonly stopReason: string | null;
  readonly estimatedCostMicros: number | null;
  readonly numericValue: number | null;
  readonly createdAt: string;
}

interface PersistedState {
  readonly version: 1;
  invites: Record<string, InviteRecord>;
  installations: Record<string, InstallationRecord>;
  quotaEvents: QuotaEvent[];
  costEvents: CostEvent[];
  reservations: Record<string, ReservationRecord>;
  operations: Record<string, AiOperationRecord>;
  telemetry: OperationalTelemetry[];
  processedRevenueCatEvents: string[];
  processedRevenueCatEventTimes: Record<string, string>;
}

function emptyState(): PersistedState {
  return {
    version: 1,
    invites: {},
    installations: {},
    quotaEvents: [],
    costEvents: [],
    reservations: {},
    operations: {},
    telemetry: [],
    processedRevenueCatEvents: [],
    processedRevenueCatEventTimes: {},
  };
}

export interface StateBackend {
  load(): Promise<PersistedState>;
  save(state: PersistedState): Promise<void>;
}

export class MemoryStateBackend implements StateBackend {
  private state = emptyState();

  async load(): Promise<PersistedState> {
    return structuredClone(this.state);
  }

  async save(state: PersistedState): Promise<void> {
    this.state = structuredClone(state);
  }
}

export class JsonFileStateBackend implements StateBackend {
  constructor(private readonly path: string) {}

  async load(): Promise<PersistedState> {
    try {
      const contents = await readFile(this.path, "utf8");
      const parsed: unknown = JSON.parse(contents);
      if (
        typeof parsed !== "object" ||
        parsed === null ||
        !("version" in parsed) ||
        parsed.version !== 1
      ) {
        throw new Error("Unsupported state file format");
      }
      return normalizeState(parsed as PersistedState);
    } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") {
        return emptyState();
      }
      throw error;
    }
  }

  async save(state: PersistedState): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const temporaryPath = `${this.path}.${process.pid}.tmp`;
    await writeFile(temporaryPath, `${JSON.stringify(state)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    await rename(temporaryPath, this.path);
  }
}

export interface ReserveOperationInput {
  readonly installationId: string;
  readonly operationId: string;
  readonly operation: AiOperation;
  readonly allowanceKey: AllowanceKey | null;
  readonly allowanceLimit: number | null;
  readonly reservationCostMicros: number;
  readonly shortWindowLimit: number;
  readonly dailyOperationLimit: number;
  readonly dailyCostLimitMicros: number;
  readonly now: Date;
}

export interface SettleOperationInput {
  readonly reservationId: string;
  readonly outcome: Exclude<AiOperationOutcome, "inProgress">;
  readonly actualCostMicros: number;
  readonly telemetry: OperationalTelemetry | null;
  readonly settledAt: Date;
  readonly telemetryCutoff?: Date;
}

const TEN_MINUTES_MS = 10 * 60 * 1_000;
const DAY_MS = 24 * 60 * 60 * 1_000;
const STALE_RESERVATION_MS = 30 * 60 * 1_000;
const OPERATION_RETENTION_MS = DAY_MS;
const MAX_OPERATION_RECORDS = 10_000;
const REVENUECAT_EVENT_RETENTION_MS = 90 * DAY_MS;
const MAX_REVENUECAT_EVENT_RECORDS = 10_000;

export class StateRepository {
  private statePromise: Promise<PersistedState>;
  private transactionTail: Promise<void> = Promise.resolve();

  constructor(private readonly backend: StateBackend) {
    this.statePromise = backend.load().then(normalizeState);
  }

  private transact<T>(mutate: (state: PersistedState) => T | Promise<T>): Promise<T> {
    const pending = this.transactionTail.then(async () => {
      const committedState = await this.statePromise;
      const nextState = structuredClone(committedState);
      const result = await mutate(nextState);
      await this.backend.save(nextState);
      this.statePromise = Promise.resolve(nextState);
      return result;
    });
    this.transactionTail = pending.then(
      () => undefined,
      () => undefined,
    );
    return pending;
  }

  async seedInviteHashes(hashes: readonly string[]): Promise<void> {
    await this.transact((state) => {
      for (const codeHash of hashes) {
        state.invites[codeHash] ??= {
          codeHash,
          redeemedAt: null,
          installationId: null,
        };
      }
    });
  }

  async redeemInvite(
    codeHash: string,
    tokenHash: string,
    now: Date,
    access: SubscriptionAccess = "freeJourney",
    promotionalEntitlementEndsAt: Date | null = null,
  ): Promise<InstallationRecord> {
    return this.transact((state) => {
      const invite = state.invites[codeHash];
      if (!invite || invite.redeemedAt !== null) {
        throw new AppError(
          "installation_invalid",
          "That invitation is invalid or has already been used.",
        );
      }

      const installation: InstallationRecord = {
        id: randomUUID(),
        tokenHash,
        access,
        promotionalEntitlementEndsAt:
          access === "comped"
            ? promotionalEntitlementEndsAt?.toISOString() ?? null
            : null,
        createdAt: now.toISOString(),
        deletedAt: null,
        allowanceCounts: {},
      };
      invite.redeemedAt = now.toISOString();
      invite.installationId = installation.id;
      state.installations[installation.id] = installation;
      return structuredClone(installation);
    });
  }

  async promoteActiveFreeJourneysToComped(
    promotionalEntitlementEndsAt: Date,
  ): Promise<void> {
    await this.transact((state) => {
      for (const installation of Object.values(state.installations)) {
        if (installation.deletedAt === null && installation.access === "freeJourney") {
          installation.access = "comped";
          installation.promotionalEntitlementEndsAt =
            promotionalEntitlementEndsAt.toISOString();
        }
      }
    });
  }

  async findActiveInstallationByTokenHash(
    tokenHash: string,
    at?: Date,
  ): Promise<InstallationRecord | null> {
    return this.findActiveInstallationByTokenHashes([tokenHash], at);
  }

  async findActiveInstallationByTokenHashes(
    tokenHashes: readonly string[],
    at?: Date,
  ): Promise<InstallationRecord | null> {
    const candidateHashes = new Set(tokenHashes);
    return this.transact((state) => {
      const installation = Object.values(state.installations).find(
        (candidate) =>
          candidate.tokenHash !== null &&
          candidateHashes.has(candidate.tokenHash) &&
          candidate.deletedAt === null,
      );
      if (!installation) return null;
      const result = structuredClone(installation);
      if (at && isCompedAccessExpired(result, at.getTime())) {
        result.access = "expired";
      }
      return result;
    });
  }

  async rotateInstallationTokenHash(
    installationId: string,
    acceptedCurrentHashes: readonly string[],
    newHash: string,
  ): Promise<boolean> {
    const acceptedHashes = new Set(acceptedCurrentHashes);
    return this.transact((state) => {
      const installation = state.installations[installationId];
      if (
        !installation ||
        installation.deletedAt !== null ||
        installation.tokenHash === null ||
        !acceptedHashes.has(installation.tokenHash)
      ) {
        return false;
      }
      installation.tokenHash = newHash;
      return true;
    });
  }

  async reserveOperation(input: ReserveOperationInput): Promise<string> {
    return this.transact((state) => {
      const nowMs = input.now.getTime();
      expireStaleReservations(state, nowMs);
      pruneOperationRecords(state, nowMs);
      const installation = state.installations[input.installationId];
      if (!installation || installation.deletedAt !== null) {
        throw new AppError("installation_invalid", "This installation is not active.");
      }
      const operationKey = operationLedgerKey(
        input.installationId,
        input.operationId,
      );
      const priorOperation = state.operations[operationKey];
      if (priorOperation) {
        if (priorOperation.outcome === "inProgress") {
          throw new AppError(
            "conflict",
            "This Cy request is already in progress. Please wait before trying it again.",
            { retryable: true },
          );
        }
        throw new AppError(
          "conflict",
          "This Cy request already finished, but its earlier result is no longer available. Start a new request if you want Cy to try again.",
        );
      }
      if (
        installation.access === "expired" ||
        isCompedAccessExpired(installation, nowMs)
      ) {
        throw new AppError(
          "entitlement_required",
          "A trial or membership is needed to ask Cy for new work.",
        );
      }
      if (installation.access === "freeJourney" && input.allowanceKey === null) {
        throw new AppError(
          "entitlement_required",
          "This request is available during a trial or membership.",
        );
      }

      state.quotaEvents = state.quotaEvents.filter(
        (event) => Date.parse(event.at) > nowMs - DAY_MS,
      );
      state.costEvents = state.costEvents.filter(
        (event) => Date.parse(event.at) > nowMs - DAY_MS,
      );
      const installationEvents = state.quotaEvents.filter(
        (event) => event.installationId === input.installationId,
      );
      const shortEvents = installationEvents.filter(
        (event) => Date.parse(event.at) > nowMs - TEN_MINUTES_MS,
      );
      if (shortEvents.length >= input.shortWindowLimit) {
        const firstAt = Math.min(...shortEvents.map((event) => Date.parse(event.at)));
        throw new AppError(
          "rate_limited",
          "Cy needs a short pause before another request.",
          {
            retryable: true,
            quotaScope: "installationShortWindow",
            retryAfterSeconds: Math.max(
              1,
              Math.ceil((firstAt + TEN_MINUTES_MS - nowMs) / 1_000),
            ),
          },
        );
      }
      if (installationEvents.length >= input.dailyOperationLimit) {
        const firstAt = Math.min(
          ...installationEvents.map((event) => Date.parse(event.at)),
        );
        throw new AppError(
          "quota_exceeded",
          "Today’s Cy allowance has been reached.",
          {
            retryable: true,
            quotaScope: "installationDaily",
            retryAfterSeconds: Math.max(
              1,
              Math.ceil((firstAt + DAY_MS - nowMs) / 1_000),
            ),
          },
        );
      }

      if (
        installation.access === "freeJourney" &&
        input.allowanceKey !== null &&
        input.allowanceLimit !== null
      ) {
        const completed = installation.allowanceCounts[input.allowanceKey] ?? 0;
        const reserved = Object.values(state.reservations).filter(
          (reservation) =>
            reservation.installationId === input.installationId &&
            reservation.allowanceKey === input.allowanceKey,
        ).length;
        if (completed + reserved >= input.allowanceLimit) {
          throw new AppError(
            "quota_exceeded",
            "That part of the free first brief has already been used.",
            { quotaScope: "freeAllowance" },
          );
        }
      }

      const dailySpend = state.costEvents.reduce(
        (total, event) => total + event.costMicros,
        0,
      );
      const reservedSpend = Object.values(state.reservations).reduce(
        (total, reservation) => total + reservation.costMicros,
        0,
      );
      if (
        dailySpend + reservedSpend + input.reservationCostMicros >
        input.dailyCostLimitMicros
      ) {
        throw new AppError(
          "quota_exceeded",
          "Cy has reached today’s shared generation limit. Please try tomorrow.",
          { retryable: true, quotaScope: "globalDailySpend" },
        );
      }

      const reservationId = randomUUID();
      state.quotaEvents.push({
        installationId: input.installationId,
        at: input.now.toISOString(),
      });
      state.reservations[reservationId] = {
        id: reservationId,
        installationId: input.installationId,
        allowanceKey: input.allowanceKey,
        costMicros: input.reservationCostMicros,
        createdAt: input.now.toISOString(),
        operationKey,
      };
      state.operations[operationKey] = {
        operationKey,
        operationId: input.operationId,
        installationId: input.installationId,
        operation: input.operation,
        outcome: "inProgress",
        createdAt: input.now.toISOString(),
        settledAt: null,
      };
      pruneOperationRecords(state, nowMs);
      if (Object.keys(state.operations).length > MAX_OPERATION_RECORDS) {
        throw new AppError(
          "usage_limit",
          "Cy is finishing too many requests right now. Please try again shortly.",
          { retryable: true },
        );
      }
      return reservationId;
    });
  }

  async settleOperation(input: SettleOperationInput): Promise<void> {
    await this.transact((state) => {
      if (input.telemetryCutoff) {
        purgeTelemetryFromState(state, input.telemetryCutoff);
      }
      const reservation = state.reservations[input.reservationId];
      if (!reservation) return;
      delete state.reservations[input.reservationId];

      if (reservation.operationKey !== null) {
        const operation = state.operations[reservation.operationKey];
        if (operation?.outcome === "inProgress") {
          operation.outcome = input.outcome;
          operation.settledAt = input.settledAt.toISOString();
        }
      }

      const installation = state.installations[reservation.installationId];
      if (installation && installation.deletedAt === null) {
        if (input.outcome === "succeeded" && reservation.allowanceKey !== null) {
          installation.allowanceCounts[reservation.allowanceKey] =
            (installation.allowanceCounts[reservation.allowanceKey] ?? 0) + 1;
        }
        if (input.actualCostMicros > 0) {
          state.costEvents.push({
            installationId: reservation.installationId,
            at: input.settledAt.toISOString(),
            costMicros: input.actualCostMicros,
          });
        }
      }
      if (input.telemetry !== null) state.telemetry.push(input.telemetry);
    });
  }

  async appendTelemetry(
    event: OperationalTelemetry,
    cutoff?: Date,
  ): Promise<void> {
    await this.transact((state) => {
      if (cutoff) purgeTelemetryFromState(state, cutoff);
      state.telemetry.push(event);
    });
  }

  async purgeTelemetryBefore(cutoff: Date): Promise<number> {
    return this.transact((state) => {
      return purgeTelemetryFromState(state, cutoff);
    });
  }

  async eraseInstallation(installationId: string, now: Date): Promise<void> {
    await this.transact((state) => {
      const installation = state.installations[installationId];
      if (!installation) return;
      installation.tokenHash = null;
      installation.deletedAt = now.toISOString();
      // The access marker and consumed free allowances are content-free integrity
      // records. They remain on the non-addressable tombstone after deletion so an
      // erased installation cannot mint a second free journey.
      state.quotaEvents = state.quotaEvents.filter(
        (event) => event.installationId !== installationId,
      );
      state.costEvents = state.costEvents.filter(
        (event) => event.installationId !== installationId,
      );
      state.telemetry = state.telemetry.filter(
        (event) => event.installationId !== installationId,
      );
      for (const [id, reservation] of Object.entries(state.reservations)) {
        if (reservation.installationId === installationId) {
          delete state.reservations[id];
        }
      }
      for (const [key, operation] of Object.entries(state.operations)) {
        if (operation.installationId === installationId) {
          delete state.operations[key];
        }
      }
    });
  }

  async applyRevenueCatEntitlement(
    eventId: string,
    installationId: string,
    access: SubscriptionAccess | null,
    processedAt: Date,
    promotionalEntitlementEndsAt: Date | null = null,
  ): Promise<boolean> {
    return this.transact((state) => {
      if (state.processedRevenueCatEvents.includes(eventId)) return false;
      pruneRevenueCatEventRecords(state, processedAt.getTime());
      const installation = state.installations[installationId];
      if (!installation || installation.deletedAt !== null) {
        rememberRevenueCatEvent(state, eventId, processedAt);
        return false;
      }
      if (access !== null) {
        installation.access = access;
        installation.promotionalEntitlementEndsAt =
          access === "comped"
            ? promotionalEntitlementEndsAt?.toISOString() ?? null
            : null;
      }
      rememberRevenueCatEvent(state, eventId, processedAt);
      return true;
    });
  }

  async snapshotForTests(): Promise<Readonly<PersistedState>> {
    return this.transact((state) => structuredClone(state));
  }
}

function normalizeState(state: PersistedState): PersistedState {
  const legacyState = state as PersistedState & {
    operations?: Record<string, AiOperationRecord>;
    processedRevenueCatEventTimes?: Record<string, string>;
    reservations: Record<
      string,
      ReservationRecord & { operationKey?: string | null }
    >;
  };
  legacyState.operations ??= {};
  legacyState.processedRevenueCatEventTimes ??= {};
  for (const installation of Object.values(legacyState.installations) as Array<
    InstallationRecord & { promotionalEntitlementEndsAt?: string | null }
  >) {
    installation.promotionalEntitlementEndsAt ??= null;
  }
  for (const reservation of Object.values(legacyState.reservations)) {
    reservation.operationKey ??= null;
  }
  return legacyState;
}

function isCompedAccessExpired(
  installation: InstallationRecord,
  nowMs: number,
): boolean {
  if (
    installation.access !== "comped" ||
    installation.promotionalEntitlementEndsAt === null
  ) {
    return false;
  }
  const endsAtMs = Date.parse(installation.promotionalEntitlementEndsAt);
  return !Number.isFinite(endsAtMs) || endsAtMs <= nowMs;
}

function pruneOperationRecords(state: PersistedState, nowMs: number): void {
  const activeOperationKeys = new Set(
    Object.values(state.reservations)
      .map((reservation) => reservation.operationKey)
      .filter((operationKey): operationKey is string => operationKey !== null),
  );
  for (const [key, operation] of Object.entries(state.operations)) {
    if (operation.outcome === "inProgress") {
      const createdAt = Date.parse(operation.createdAt);
      if (
        activeOperationKeys.has(key) ||
        (Number.isFinite(createdAt) && createdAt > nowMs - STALE_RESERVATION_MS)
      ) {
        continue;
      }
      operation.outcome = "failed";
      operation.settledAt = new Date(nowMs).toISOString();
    }
    const settledAt = operation.settledAt
      ? Date.parse(operation.settledAt)
      : Date.parse(operation.createdAt);
    if (!Number.isFinite(settledAt) || settledAt <= nowMs - OPERATION_RETENTION_MS) {
      delete state.operations[key];
    }
  }

  const excess = Object.keys(state.operations).length - MAX_OPERATION_RECORDS;
  if (excess <= 0) return;
  const oldestSettled = Object.values(state.operations)
    .filter((operation) => operation.outcome !== "inProgress")
    .sort(
      (left, right) =>
        Date.parse(left.settledAt ?? left.createdAt) -
        Date.parse(right.settledAt ?? right.createdAt),
    );
  for (const operation of oldestSettled.slice(0, excess)) {
    delete state.operations[operation.operationKey];
  }
}

function pruneRevenueCatEventRecords(
  state: PersistedState,
  nowMs: number,
): void {
  const retained = state.processedRevenueCatEvents.filter((eventId) => {
    const processedAt = state.processedRevenueCatEventTimes[eventId];
    if (!processedAt) return true;
    const processedAtMs = Date.parse(processedAt);
    if (
      Number.isFinite(processedAtMs) &&
      processedAtMs > nowMs - REVENUECAT_EVENT_RETENTION_MS
    ) {
      return true;
    }
    delete state.processedRevenueCatEventTimes[eventId];
    return false;
  });
  state.processedRevenueCatEvents = retained.slice(
    -MAX_REVENUECAT_EVENT_RECORDS,
  );
  const retainedIds = new Set(state.processedRevenueCatEvents);
  for (const eventId of Object.keys(state.processedRevenueCatEventTimes)) {
    if (!retainedIds.has(eventId)) {
      delete state.processedRevenueCatEventTimes[eventId];
    }
  }
}

function rememberRevenueCatEvent(
  state: PersistedState,
  eventId: string,
  processedAt: Date,
): void {
  state.processedRevenueCatEvents.push(eventId);
  state.processedRevenueCatEventTimes[eventId] = processedAt.toISOString();
  if (state.processedRevenueCatEvents.length <= MAX_REVENUECAT_EVENT_RECORDS) {
    return;
  }
  const removed = state.processedRevenueCatEvents.splice(
    0,
    state.processedRevenueCatEvents.length - MAX_REVENUECAT_EVENT_RECORDS,
  );
  for (const removedId of removed) {
    delete state.processedRevenueCatEventTimes[removedId];
  }
}

function operationLedgerKey(installationId: string, operationId: string): string {
  return `${installationId}:${operationId}`;
}

function expireStaleReservations(state: PersistedState, nowMs: number): void {
  for (const [id, reservation] of Object.entries(state.reservations)) {
    if (Date.parse(reservation.createdAt) > nowMs - STALE_RESERVATION_MS) continue;
    delete state.reservations[id];
    if (reservation.operationKey === null) continue;
    const operation = state.operations[reservation.operationKey];
    if (operation?.outcome === "inProgress") {
      operation.outcome = "failed";
      operation.settledAt = new Date(nowMs).toISOString();
    }
  }
}

function purgeTelemetryFromState(
  state: PersistedState,
  cutoff: Date,
): number {
  const before = state.telemetry.length;
  state.telemetry = state.telemetry.filter(
    (event) => Date.parse(event.createdAt) >= cutoff.getTime(),
  );
  return before - state.telemetry.length;
}
