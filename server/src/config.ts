import { resolve } from "node:path";

export type ProviderKind = "anthropic" | "fixture";

export interface ServerConfig {
  readonly host: string;
  readonly port: number;
  readonly provider: ProviderKind;
  readonly anthropicApiKey: string | undefined;
  readonly model: "claude-sonnet-5";
  readonly dataFile: string;
  readonly inviteHashSecret: string;
  /** First value signs new credentials; later values verify credentials minted before rotation. */
  readonly installationHashSecrets: readonly [string, ...string[]];
  readonly appleSubjectHashSecret: string;
  readonly appleClientIds: readonly [string, ...string[]];
  readonly inviteCodes: readonly string[];
  readonly pilotCompedAccess: boolean;
  readonly pilotCompedDurationDays: number;
  readonly revenueCatWebhookSecret: string | undefined;
  readonly revenueCatEntitlementId: string;
  readonly requestTimeoutMs: number;
  readonly bodyLimitBytes: number;
  readonly shortWindowLimit: number;
  readonly dailyOperationLimit: number;
  readonly dailyCostLimitMicros: number;
  readonly telemetryRetentionDays: number;
}

function integer(
  value: string | undefined,
  fallback: number,
  name: string,
  minimum = 1,
): number {
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum) {
    throw new Error(`${name} must be an integer of at least ${minimum}`);
  }
  return parsed;
}

function boolean(
  value: string | undefined,
  fallback: boolean,
  name: string,
): boolean {
  if (value === undefined || value === "") return fallback;
  switch (value.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
      return false;
    default:
      throw new Error(`${name} must be true or false`);
  }
}

export function loadConfig(
  environment: NodeJS.ProcessEnv = process.env,
): ServerConfig {
  const production = environment.NODE_ENV === "production";
  const provider = environment.AI_PROVIDER ?? (production ? "anthropic" : "fixture");
  if (provider !== "anthropic" && provider !== "fixture") {
    throw new Error("AI_PROVIDER must be anthropic or fixture");
  }

  const anthropicApiKey = environment.ANTHROPIC_API_KEY;
  if (provider === "anthropic" && !anthropicApiKey) {
    throw new Error("ANTHROPIC_API_KEY is required when AI_PROVIDER=anthropic");
  }

  const inviteHashSecret =
    environment.INVITE_HASH_SECRET ??
    (production ? undefined : "agent-cy-local-invite-hash-secret-only");
  const installationHashSecret =
    environment.INSTALLATION_HASH_SECRET ??
    (production ? undefined : "agent-cy-local-installation-hash-secret-only");
  const appleSubjectHashSecret =
    environment.APPLE_SUBJECT_HASH_SECRET ??
    (production ? undefined : "agent-cy-local-apple-subject-hash-secret-only");
  if (!inviteHashSecret) {
    throw new Error("INVITE_HASH_SECRET is required in production");
  }
  if (!installationHashSecret) {
    throw new Error("INSTALLATION_HASH_SECRET is required in production");
  }
  if (!appleSubjectHashSecret) {
    throw new Error("APPLE_SUBJECT_HASH_SECRET is required in production");
  }
  const previousInstallationHashSecrets = (
    environment.PREVIOUS_INSTALLATION_HASH_SECRETS ?? ""
  )
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  const installationHashSecrets = [
    installationHashSecret,
    ...previousInstallationHashSecrets,
  ] as [string, ...string[]];

  if (production) {
    for (const [name, secret] of [
      ["INVITE_HASH_SECRET", inviteHashSecret],
      ["APPLE_SUBJECT_HASH_SECRET", appleSubjectHashSecret],
      ...installationHashSecrets.map(
        (secret, index) => [
          index === 0
            ? "INSTALLATION_HASH_SECRET"
            : `PREVIOUS_INSTALLATION_HASH_SECRETS[${index - 1}]`,
          secret,
        ] as const,
      ),
    ] as const) {
      if (secret.length < 32) {
        throw new Error(`${name} must contain at least 32 characters`);
      }
    }
  }
  if (new Set(installationHashSecrets).size !== installationHashSecrets.length) {
    throw new Error("Installation hash secrets must be unique");
  }
  if (installationHashSecrets.includes(inviteHashSecret)) {
    throw new Error(
      "INVITE_HASH_SECRET must differ from all installation hash secrets",
    );
  }
  if (
    appleSubjectHashSecret === inviteHashSecret ||
    installationHashSecrets.includes(appleSubjectHashSecret)
  ) {
    throw new Error(
      "APPLE_SUBJECT_HASH_SECRET must differ from invite and installation hash secrets",
    );
  }

  const appleClientIds = (environment.APPLE_CLIENT_IDS ?? "com.agentcy.app")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (appleClientIds.length === 0) {
    throw new Error("APPLE_CLIENT_IDS must contain at least one client identifier");
  }

  const inviteCodes = (environment.INVITE_CODES ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (new Set(inviteCodes).size !== inviteCodes.length) {
    throw new Error("INVITE_CODES must not contain duplicates");
  }
  if (production) {
    if (inviteCodes.length === 0) {
      throw new Error("INVITE_CODES must contain at least one production invitation");
    }
    for (const inviteCode of inviteCodes) {
      const characterClasses = [
        /[a-z]/.test(inviteCode),
        /[A-Z]/.test(inviteCode),
        /[0-9]/.test(inviteCode),
        /[^a-zA-Z0-9]/.test(inviteCode),
      ].filter(Boolean).length;
      if (inviteCode.length < 20 || characterClasses < 3) {
        throw new Error(
          "Each production INVITE_CODES value must contain at least 20 characters across at least three character classes",
        );
      }
    }
  }
  const revenueCatEntitlementId =
    environment.REVENUECAT_ENTITLEMENT_ID ??
    (production ? undefined : "creator_access");
  if (!revenueCatEntitlementId) {
    throw new Error("REVENUECAT_ENTITLEMENT_ID is required in production");
  }
  const telemetryRetentionDays = integer(
    environment.TELEMETRY_RETENTION_DAYS,
    30,
    "TELEMETRY_RETENTION_DAYS",
  );
  if (telemetryRetentionDays > 30) {
    throw new Error("TELEMETRY_RETENTION_DAYS cannot exceed 30");
  }
  const pilotCompedDurationDays = integer(
    environment.PILOT_COMPED_DURATION_DAYS,
    28,
    "PILOT_COMPED_DURATION_DAYS",
  );
  if (pilotCompedDurationDays > 365) {
    throw new Error("PILOT_COMPED_DURATION_DAYS cannot exceed 365");
  }

  return {
    host: environment.HOST ?? "0.0.0.0",
    port: integer(environment.PORT, 3_000, "PORT"),
    provider,
    anthropicApiKey,
    model: "claude-sonnet-5",
    dataFile: resolve(environment.DATA_FILE ?? "./data/agent-cy-state.json"),
    inviteHashSecret,
    installationHashSecrets,
    appleSubjectHashSecret,
    appleClientIds: appleClientIds as [string, ...string[]],
    inviteCodes,
    // The current external pilot is intentionally promotional. Set this to
    // false when the production App Store billing cohort begins.
    pilotCompedAccess: boolean(
      environment.PILOT_COMPED_ACCESS,
      production,
      "PILOT_COMPED_ACCESS",
    ),
    pilotCompedDurationDays,
    revenueCatWebhookSecret: environment.REVENUECAT_WEBHOOK_SECRET,
    revenueCatEntitlementId,
    requestTimeoutMs: integer(
      environment.REQUEST_TIMEOUT_MS,
      90_000,
      "REQUEST_TIMEOUT_MS",
      1_000,
    ),
    bodyLimitBytes: integer(environment.BODY_LIMIT_BYTES, 131_072, "BODY_LIMIT_BYTES"),
    shortWindowLimit: integer(
      environment.SHORT_WINDOW_LIMIT,
      10,
      "SHORT_WINDOW_LIMIT",
    ),
    dailyOperationLimit: integer(
      environment.DAILY_OPERATION_LIMIT,
      50,
      "DAILY_OPERATION_LIMIT",
    ),
    dailyCostLimitMicros: integer(
      environment.DAILY_COST_LIMIT_MICROS,
      1_000_000,
      "DAILY_COST_LIMIT_MICROS",
    ),
    telemetryRetentionDays,
  };
}
