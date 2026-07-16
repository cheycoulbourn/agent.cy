import {
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
} from "node:fs";
import { join } from "node:path";

import { query } from "@anthropic-ai/claude-agent-sdk";
import {
  LocalCyRequestSchema,
  LocalCyResponseSchema,
  LocalCyRuntimeStatusSchema,
  LocalCySchemaVersion,
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
      const payload = definition.requestSchema.parse(request.payload);
      const generated = await this.generate({ ...request, payload }, definition.resultSchema);
      const result = definition.resultSchema.parse(generated.result);
      this.writeResponse({
        schemaVersion: LocalCySchemaVersion,
        id: request.id,
        operation: request.operation,
        completedAt: new Date().toISOString(),
        status: "succeeded",
        model: generated.model,
        result,
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
    const authenticationFailure = looksLikeAuthenticationFailure(error);
    process.stderr.write(`${JSON.stringify({
      event: "local_cy_generation_failed",
      operation: request.operation,
      errorType: error instanceof Error ? error.name : typeof error,
      detail: safeDiagnostic(error),
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
        code: authenticationFailure ? "upstream_unavailable" : "generation_invalid",
        message: authenticationFailure
          ? "Claude needs to be signed in on your Mac before Local Cy can respond."
          : "Local Cy could not finish this request. Your work is saved.",
        retryable: true,
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
  const options = {
    model: "claude-sonnet-5",
    effort: definition.effort,
    // Structured output is emitted through Claude's output tool. The SDK needs
    // one model turn to call it and a second turn to return the validated result.
    maxTurns: 2,
    tools: [],
    allowedTools: [],
    strictMcpConfig: true,
    settingSources: [],
    persistSession: false,
    permissionMode: "dontAsk" as const,
    systemPrompt: `${localCySystemPrompt}\n${definition.instruction}`,
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
