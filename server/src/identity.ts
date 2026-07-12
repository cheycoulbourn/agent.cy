import { createHmac, randomBytes } from "node:crypto";

export class IdentityService {
  constructor(private readonly secret: string) {}

  hash(value: string): string {
    return createHmac("sha256", this.secret).update(value, "utf8").digest("hex");
  }

  createInstallationToken(): string {
    return randomBytes(32).toString("base64url");
  }
}

export class RotatingInstallationIdentityService {
  constructor(
    private readonly secrets: readonly [string, ...string[]],
  ) {}

  hash(value: string): string {
    return hashWithSecret(value, this.secrets[0]);
  }

  hashCandidates(value: string): readonly string[] {
    return this.secrets.map((secret) => hashWithSecret(value, secret));
  }

  createInstallationToken(): string {
    return randomBytes(32).toString("base64url");
  }
}

function hashWithSecret(value: string, secret: string): string {
  return createHmac("sha256", secret).update(value, "utf8").digest("hex");
}

export function readBearerToken(authorization: string | undefined): string | null {
  if (!authorization) return null;
  const match = /^Bearer\s+([^\s]+)$/i.exec(authorization);
  return match?.[1] ?? null;
}
