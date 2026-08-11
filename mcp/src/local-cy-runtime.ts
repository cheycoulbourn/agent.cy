import {
  accessSync,
  constants,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
} from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

import { query } from "@anthropic-ai/claude-agent-sdk";
import {
  LocalCyRequestSchema,
  LocalCyResponseSchema,
  LocalCyRuntimeStatusSchema,
  LocalCySchemaVersion,
  normalizeAiOperationResult,
  type LocalCyRequest,
  type LocalCyResponse,
} from "@agent-cy/contracts";
import { z } from "zod";

import { localCyOperations, localCySystemPrompt } from "./local-cy-operations.js";
import { AgentCyWorkspace, writeJsonAtomically } from "./workspace.js";

export type LocalCyGenerator = (
  request: LocalCyRequest,
  resultSchema: z.ZodType,
) => Promise<{ result: unknown; model: string }>;

export class LocalCyRuntime {
  private processing = false;
  private lastStatusWriteAt = 0;

  constructor(
    readonly workspace = new AgentCyWorkspace(),
    private readonly generate: LocalCyGenerator = generateWithClaude,
  ) {}

  async runOnce(): Promise<number> {
    if (this.processing) return 0;
    this.processing = true;
    this.workspace.ensureDirectories();
    let completed = 0;
    try {
      for (const name of this.pendingRequestNames()) {
        if (await this.process(name)) completed += 1;
      }
      if (completed > 0 || Date.now() - this.lastStatusWriteAt >= 30_000) {
        this.writeStatus("ready", "Local Cy is ready on this Mac.");
      }
      return completed;
    } finally {
      this.processing = false;
    }
  }

  async watch(signal?: AbortSignal): Promise<void> {
    this.workspace.ensureDirectories();
    this.writeStatus("ready", "Local Cy is ready on this Mac.");
    while (!signal?.aborted) {
      await this.runOnce();
      await wait(1_000, signal);
    }
  }

  private pendingRequestNames(): string[] {
    try {
      return readdirSync(this.workspace.localCyRequestsDirectory)
        .filter((name) => name.endsWith(".json"))
        .sort();
    } catch (error) {
      if (["EAGAIN", "EBUSY"].includes(readErrorCode(error) ?? "")) return [];
      throw error;
    }
  }

  private async process(name: string): Promise<boolean> {
    const sourcePath = join(this.workspace.localCyRequestsDirectory, name);
    const processingPath = join(this.workspace.localCyProcessingDirectory, name);
    try {
      renameSync(sourcePath, processingPath);
    } catch (error) {
      if (readErrorCode(error) === "ENOENT") return false;
      throw error;
    }

    let request: LocalCyRequest | null = null;
    try {
      const raw: unknown = JSON.parse(readFileSync(processingPath, "utf8"));
      request = LocalCyRequestSchema.parse(raw);
      this.writeStatus("working", "Cy is working on your request.");
      const definition = localCyOperations[request.operation];
      const payloadResult = definition.requestSchema.safeParse(request.payload);
      if (!payloadResult.success) {
        throw new LocalCyRuntimeError(
          "invalid_input",
          "Cy needs a valid version of this post before it can continue.",
          false,
          "request_validation_failed",
          payloadResult.error,
        );
      }

      let generated: Awaited<ReturnType<LocalCyGenerator>>;
      try {
        generated = await this.generate(
          { ...request, payload: payloadResult.data },
          definition.resultSchema,
        );
      } catch (error) {
        throw new LocalCyRuntimeError(
          looksLikeAuthenticationFailure(error) ? "upstream_unavailable" : "generation_invalid",
          looksLikeAuthenticationFailure(error)
            ? "Claude needs to be signed in on your Mac before Local Cy can respond."
            : "Local Cy could not finish this request. Your work is saved.",
          true,
          "provider_generation_failed",
          error,
        );
      }

      const normalizedResult = normalizeAiOperationResult(
        request.operation,
        generated.result,
        payloadResult.data,
      );
      const resultParse = definition.resultSchema.safeParse(normalizedResult);
      if (!resultParse.success) {
        throw new LocalCyRuntimeError(
          "generation_invalid",
          "Local Cy returned an incomplete result. Your work is saved.",
          true,
          "result_validation_failed",
          resultParse.error,
        );
      }
      this.writeResponse({
        schemaVersion: LocalCySchemaVersion,
        id: request.id,
        operation: request.operation,
        completedAt: new Date().toISOString(),
        status: "succeeded",
        model: generated.model,
        result: resultParse.data,
      });
      return true;
    } catch (error) {
      if (request) this.writeFailure(request, error);
      return true;
    } finally {
      rmSync(processingPath, { force: true });
    }
  }

  private writeFailure(request: LocalCyRequest, error: unknown): void {
    const runtimeError = error instanceof LocalCyRuntimeError ? error : null;
    const authenticationFailure = runtimeError?.code === "upstream_unavailable"
      || looksLikeAuthenticationFailure(error);
    process.stderr.write(`${JSON.stringify({
      event: "local_cy_generation_failed",
      operation: request.operation,
      errorType: error instanceof Error ? error.name : typeof error,
      phase: runtimeError?.phase ?? "runtime_failed",
      detail: safeDiagnostic(runtimeError?.diagnosticCause ?? error),
    })}\n`);
    if (authenticationFailure) {
      this.writeStatus("needsLogin", "Open Claude Code on this Mac and sign in again.");
    } else {
      this.writeStatus("error", "Local Cy could not finish the last request.");
    }
    this.writeResponse({
      schemaVersion: LocalCySchemaVersion,
      id: request.id,
      operation: request.operation,
      completedAt: new Date().toISOString(),
      status: "failed",
      error: {
        code: runtimeError?.code
          ?? (authenticationFailure ? "upstream_unavailable" : "generation_invalid"),
        message: runtimeError?.creatorMessage
          ?? (authenticationFailure
            ? "Claude needs to be signed in on your Mac before Local Cy can respond."
            : "Local Cy could not finish this request. Your work is saved."),
        retryable: runtimeError?.retryable ?? true,
        retryAfterSeconds: null,
        quotaScope: null,
      },
    });
  }

  private writeResponse(response: LocalCyResponse): void {
    const validated = LocalCyResponseSchema.parse(response);
    writeJsonAtomically(
      join(this.workspace.localCyResponsesDirectory, `${validated.id}.json`),
      validated,
    );
  }

  private writeStatus(
    status: "ready" | "working" | "needsLogin" | "error",
    message: string,
  ): void {
    this.lastStatusWriteAt = Date.now();
    writeJsonAtomically(
      this.workspace.localCyStatusPath,
      LocalCyRuntimeStatusSchema.parse({
        schemaVersion: LocalCySchemaVersion,
        status,
        updatedAt: new Date().toISOString(),
        model: "Claude Sonnet",
        message,
      }),
    );
  }
}

async function generateWithClaude(
  request: LocalCyRequest,
  resultSchema: z.ZodType,
): Promise<{ result: unknown; model: string }> {
  const definition = localCyOperations[request.operation];
  const schema = z.toJSONSchema(resultSchema, { target: "draft-07", io: "output" });
  const claudeExecutable = resolveClaudeCodeExecutable();
  if (!claudeExecutable) {
    throw new Error("Claude Code executable was not found.");
  }
  const options = {
    // The SDK's bundled CLI is a native executable. Without an explicit path,
    // some package-manager layouts try to launch it through Node and fail with
    // ENOEXEC before Claude ever receives the request.
    pathToClaudeCodeExecutable: claudeExecutable,
    model: "claude-sonnet-5",
    effort: definition.effort,
    // Structured output can require more than two model turns before the SDK
    // returns its validated result, even though Cy does not need external tools.
    maxTurns: 8,
    strictMcpConfig: true,
    settingSources: [],
    persistSession: false,
    permissionMode: "dontAsk" as const,
    systemPrompt: `${localCySystemPrompt}\n${definition.instruction}\nReturn the required structured result immediately. Do not use tools and do not output prose outside the requested schema.`,
    outputFormat: { type: "json_schema" as const, schema },
  };

  for await (const message of query({
    prompt: `Use only this request-scoped creator context.\n\n${JSON.stringify(request.payload)}`,
    options,
  })) {
    if (message.type !== "result") continue;
    if (message.subtype !== "success") {
      throw new Error(`Claude ended with ${message.subtype}.`);
    }
    const structuredOutput = message.structured_output
      ?? parseClaudeStructuredOutput(message.result);
    if (structuredOutput === undefined) throw new Error("Claude ended with success.");
    const usedModels = Object.keys(message.modelUsage);
    const model = usedModels.find((candidate) => candidate.includes("sonnet"))
      ?? usedModels[0]
      ?? "claude-sonnet-5";
    return { result: structuredOutput, model };
  }
  throw new Error("Claude ended without a structured result.");
}

export function resolveClaudeCodeExecutable(
  environment: NodeJS.ProcessEnv = process.env,
  homeDirectory = homedir(),
): string | undefined {
  const candidates = [
    environment.AGENTCY_CLAUDE_EXECUTABLE,
    join(homeDirectory, ".local", "bin", "claude"),
    ...((environment.PATH ?? "")
      .split(delimiter)
      .filter(Boolean)
      .map((directory) => join(directory, "claude"))),
  ];

  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      // Try the next supported Claude Code location.
    }
  }
  return undefined;
}

class LocalCyRuntimeError extends Error {
  constructor(
    readonly code: "invalid_input" | "upstream_unavailable" | "generation_invalid",
    readonly creatorMessage: string,
    readonly retryable: boolean,
    readonly phase: string,
    readonly diagnosticCause?: unknown,
  ) {
    super(creatorMessage);
    this.name = "LocalCyRuntimeError";
  }
}

export function parseClaudeStructuredOutput(result: string): unknown | undefined {
  const trimmed = result.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)?.[1];
  const objectStart = trimmed.indexOf("{");
  const objectEnd = trimmed.lastIndexOf("}");
  const embeddedObject = objectStart >= 0 && objectEnd > objectStart
    ? trimmed.slice(objectStart, objectEnd + 1)
    : undefined;
  for (const candidate of [trimmed, fenced, embeddedObject]) {
    if (!candidate) continue;
    try {
      return JSON.parse(candidate);
    } catch {
      // Try the next representation.
    }
  }
  return undefined;
}

function looksLikeAuthenticationFailure(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /auth|login|credential|subscription|unauthorized|401/i.test(message);
}

function safeDiagnostic(error: unknown): string {
  if (error instanceof z.ZodError) {
    const issues = error.issues.slice(0, 8).map((issue) => {
      const path = issue.path.length > 0 ? issue.path.join(".") : "root";
      return `${path}:${issue.code}`;
    });
    return `structured_output_validation_failed:${issues.join(",")}`;
  }
  const message = error instanceof Error ? error.message : String(error);
  const errorCode = readErrorCode(error);
  if (errorCode === "ENOEXEC") return "claude_executable_format_error";
  if (errorCode === "ENOENT" || /executable was not found/i.test(message)) {
    return "claude_executable_not_found";
  }
  const claudeSubtype = message.match(/^Claude ended with ([a-z0-9_-]+)\.?$/i)?.[1];
  if (claudeSubtype) return claudeSubtype;
  return "unexpected_local_generation_error";
}

function readErrorCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String((error as { code?: unknown }).code)
    : undefined;
}

async function wait(milliseconds: number, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) return;
  await new Promise<void>((resolve) => {
    const timer = setTimeout(resolve, milliseconds);
    signal?.addEventListener("abort", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
  });
}
