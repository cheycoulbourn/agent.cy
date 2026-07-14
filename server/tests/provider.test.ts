import { describe, expect, it, vi } from "vitest";
import {
  classifyAnthropicFailure,
  type ProviderFailureDiagnostic,
} from "../src/provider.js";

describe("Anthropic provider failure diagnostics", () => {
  it.each([
    {
      status: 401,
      type: "authentication_error",
      message: "Cy’s server credential needs attention. Your work is safe.",
    },
    {
      status: 400,
      type: "billing_error",
      message: "Cy’s API billing is unavailable. Check the funded Anthropic workspace used by the app.",
    },
    {
      status: 403,
      type: "permission_error",
      message: "Cy’s Anthropic workspace does not currently allow this request.",
    },
    {
      status: 404,
      type: "not_found_error",
      message: "Cy’s configured AI model is unavailable to this Anthropic workspace.",
    },
    {
      status: 400,
      type: "invalid_request_error",
      message: "Cy’s request was rejected by the AI provider. Your work is safe.",
    },
  ])("maps $type without logging private request data", ({ status, type, message }) => {
    const diagnostics: ProviderFailureDiagnostic[] = [];
    const error = classifyAnthropicFailure(
      "ideas",
      {
        status,
        type,
        requestID: "req_safe_identifier",
        message: "must never appear in diagnostics",
        error: { message: "must never appear in diagnostics" },
      },
      (diagnostic) => diagnostics.push(diagnostic),
    );

    expect(error.message).toBe(message);
    expect(diagnostics).toEqual([
      {
        event: "anthropic_request_failed",
        operation: "ideas",
        status,
        errorType: type,
        requestId: "req_safe_identifier",
        retryable: false,
      },
    ]);
    expect(JSON.stringify(diagnostics)).not.toContain("must never appear");
  });

  it("keeps rate-limit retry timing and records only safe metadata", () => {
    const diagnostic = vi.fn();
    const error = classifyAnthropicFailure(
      "ideas",
      {
        status: 429,
        type: "rate_limit_error",
        requestID: "req_rate_limit",
        headers: new Headers({ "retry-after": "12" }),
      },
      diagnostic,
    );

    expect(error).toMatchObject({
      code: "rate_limited",
      retryable: true,
      retryAfterSeconds: 12,
      quotaScope: "providerRateLimit",
    });
    expect(diagnostic).toHaveBeenCalledWith({
      event: "anthropic_request_failed",
      operation: "ideas",
      status: 429,
      errorType: "rate_limit_error",
      requestId: "req_rate_limit",
      retryable: true,
    });
  });

  it("marks provider billing failures as a provider credit issue", () => {
    const error = classifyAnthropicFailure("ideas", {
      status: 400,
      type: "billing_error",
      requestID: "req_billing",
    });

    expect(error).toMatchObject({
      code: "upstream_unavailable",
      retryable: false,
      quotaScope: "providerCredits",
    });
  });

  it("marks connection and provider outages as retryable", () => {
    const diagnostics: ProviderFailureDiagnostic[] = [];
    const error = classifyAnthropicFailure(
      "ideas",
      new Error("socket closed"),
      (diagnostic) => diagnostics.push(diagnostic),
    );

    expect(error).toMatchObject({ code: "upstream_unavailable", retryable: true });
    expect(diagnostics[0]).toMatchObject({
      status: null,
      errorType: "connection_error",
      requestId: null,
      retryable: true,
    });
  });
});
