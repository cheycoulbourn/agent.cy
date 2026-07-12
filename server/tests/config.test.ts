import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import {
  IdentityService,
  RotatingInstallationIdentityService,
} from "../src/identity.js";

describe("server secret configuration", () => {
  it("uses separate safe defaults for local invitation and installation hashing", () => {
    const config = loadConfig({ NODE_ENV: "development" });
    expect(config.inviteHashSecret).not.toBe(config.installationHashSecrets[0]);
    expect(config.inviteHashSecret.length).toBeGreaterThanOrEqual(32);
    expect(config.installationHashSecrets[0].length).toBeGreaterThanOrEqual(32);
  });

  it("requires separate strong secrets in production", () => {
    const production = {
      NODE_ENV: "production",
      AI_PROVIDER: "anthropic",
      ANTHROPIC_API_KEY: "test-key",
    };
    expect(() => loadConfig(production)).toThrow("INVITE_HASH_SECRET");
    expect(() =>
      loadConfig({
        ...production,
        INVITE_HASH_SECRET: "a".repeat(32),
        INSTALLATION_HASH_SECRET: "a".repeat(32),
      }),
    ).toThrow("must differ");
    expect(() =>
      loadConfig({
        ...production,
        INVITE_HASH_SECRET: "a".repeat(32),
        INSTALLATION_HASH_SECRET: "b".repeat(32),
        PREVIOUS_INSTALLATION_HASH_SECRETS: "short",
      }),
    ).toThrow("PREVIOUS_INSTALLATION_HASH_SECRETS[0]");
  });

  it("loads prior installation secrets for credential rotation", () => {
    const config = loadConfig({
      NODE_ENV: "development",
      INVITE_HASH_SECRET: "invite-secret-that-is-definitely-distinct",
      INSTALLATION_HASH_SECRET: "new-installation-secret",
      PREVIOUS_INSTALLATION_HASH_SECRETS:
        "old-installation-secret, oldest-installation-secret",
    });
    expect(config.installationHashSecrets).toEqual([
      "new-installation-secret",
      "old-installation-secret",
      "oldest-installation-secret",
    ]);
    const token = "credential-minted-before-rotation";
    const oldHash = new IdentityService("old-installation-secret").hash(token);
    expect(
      new RotatingInstallationIdentityService(
        config.installationHashSecrets,
      ).hashCandidates(token),
    ).toContain(oldHash);
  });

  it("does not allow telemetry retention beyond the public 30-day maximum", () => {
    expect(() =>
      loadConfig({
        NODE_ENV: "development",
        TELEMETRY_RETENTION_DAYS: "31",
      }),
    ).toThrow("cannot exceed 30");
    expect(loadConfig({ TELEMETRY_RETENTION_DAYS: "14" }).telemetryRetentionDays).toBe(
      14,
    );
  });
});
