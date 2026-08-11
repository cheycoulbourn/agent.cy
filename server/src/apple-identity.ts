import { createHash, timingSafeEqual } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";

import { AppError } from "./errors.js";

export interface AppleIdentityVerificationInput {
  readonly identityToken: string;
  readonly authorizationCode: string;
  readonly nonce: string;
}

export interface AppleIdentityVerificationResult {
  readonly subject: string;
}

export interface AppleIdentityVerifying {
  verify(
    input: AppleIdentityVerificationInput,
  ): Promise<AppleIdentityVerificationResult>;
}

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

export class AppleIdentityVerifier implements AppleIdentityVerifying {
  constructor(
    private readonly clientIds: readonly [string, ...string[]],
  ) {}

  async verify(
    input: AppleIdentityVerificationInput,
  ): Promise<AppleIdentityVerificationResult> {
    try {
      const { payload } = await jwtVerify(input.identityToken, APPLE_JWKS, {
        issuer: APPLE_ISSUER,
        audience: [...this.clientIds],
        algorithms: ["RS256"],
      });
      if (!payload.sub || typeof payload.nonce !== "string") {
        throw new Error("Apple identity token omitted required claims");
      }
      const expectedNonce = createHash("sha256")
        .update(input.nonce, "utf8")
        .digest("hex");
      if (!securelyMatches(payload.nonce, expectedNonce)) {
        throw new Error("Apple identity nonce did not match");
      }
      return { subject: payload.sub };
    } catch {
      throw new AppError(
        "installation_invalid",
        "Apple could not verify this sign-in. Please try again.",
      );
    }
  }
}

function securelyMatches(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left, "utf8");
  const rightBuffer = Buffer.from(right, "utf8");
  return (
    leftBuffer.length === rightBuffer.length &&
    timingSafeEqual(leftBuffer, rightBuffer)
  );
}
