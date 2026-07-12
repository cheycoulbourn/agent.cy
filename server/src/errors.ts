export type AppErrorCode =
  | "invalid_input"
  | "payload_too_large"
  | "installation_invalid"
  | "entitlement_required"
  | "quota_exceeded"
  | "rate_limited"
  | "upstream_unavailable"
  | "generation_invalid"
  | "refusal"
  | "max_tokens"
  | "timeout"
  | "usage_limit"
  | "cancelled"
  | "conflict";

export class AppError extends Error {
  readonly code: AppErrorCode;
  readonly retryable: boolean;
  readonly retryAfterSeconds: number | null;

  constructor(
    code: AppErrorCode,
    message: string,
    options: {
      retryable?: boolean;
      retryAfterSeconds?: number | null;
      cause?: unknown;
    } = {},
  ) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = "AppError";
    this.code = code;
    this.retryable = options.retryable ?? false;
    this.retryAfterSeconds = options.retryAfterSeconds ?? null;
  }
}

export function asAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;

  if (error instanceof Error && error.name === "AbortError") {
    return new AppError("cancelled", "The request was cancelled.");
  }

  return new AppError(
    "upstream_unavailable",
    "Cy is unavailable right now. Your work is safe. Please try again.",
    { retryable: true, cause: error },
  );
}
