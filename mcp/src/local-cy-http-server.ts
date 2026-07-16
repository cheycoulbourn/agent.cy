import { timingSafeEqual } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";

import {
  LocalCyRequestSchema,
  LocalCyResponseSchema,
  type LocalCyConnectionConfig,
} from "@agent-cy/contracts";

import { AgentCyWorkspace, writeJsonAtomically } from "./workspace.js";

const maximumRequestBytes = 128 * 1_024;

export class LocalCyHTTPServer {
  private server: Server | null = null;

  constructor(
    private readonly workspace: AgentCyWorkspace,
    private readonly connection: LocalCyConnectionConfig,
  ) {}

  async start(): Promise<void> {
    if (this.server) return;
    const url = new URL(this.connection.baseURL);
    const port = Number(url.port || (url.protocol === "https:" ? 443 : 80));
    const server = createServer((request, response) => {
      void this.handle(request, response);
    });
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(port, "0.0.0.0", () => {
        server.off("error", reject);
        resolve();
      });
    });
    this.server = server;
  }

  async stop(): Promise<void> {
    const server = this.server;
    this.server = null;
    if (!server) return;
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }

  get boundBaseURL(): string | null {
    const address = this.server?.address();
    if (!address || typeof address === "string") return null;
    return `http://127.0.0.1:${(address as AddressInfo).port}`;
  }

  private async handle(request: IncomingMessage, response: ServerResponse): Promise<void> {
    try {
      if (!this.isAuthorized(request)) {
        sendJSON(response, 401, { error: "Local Cy authorization failed." });
        return;
      }
      if (request.method === "GET" && request.url === "/healthz") {
        sendJSON(response, 200, { status: "ready" });
        return;
      }
      if (request.method !== "POST" || request.url !== "/v1/local-cy") {
        sendJSON(response, 404, { error: "Not found." });
        return;
      }

      const body = await readBody(request);
      const envelope = LocalCyRequestSchema.parse(JSON.parse(body));
      this.workspace.ensureDirectories();
      const responsePath = join(this.workspace.localCyResponsesDirectory, `${envelope.id}.json`);
      const processingPath = join(this.workspace.localCyProcessingDirectory, `${envelope.id}.json`);
      const requestPath = join(this.workspace.localCyRequestsDirectory, `${envelope.id}.json`);
      if (!existsSync(responsePath) && !existsSync(processingPath) && !existsSync(requestPath)) {
        writeJsonAtomically(requestPath, envelope);
      }

      const result = await waitForResponse(responsePath, request);
      sendJSON(response, 200, result);
    } catch (error) {
      if (readErrorCode(error) === "PAYLOAD_TOO_LARGE") {
        sendJSON(response, 413, { error: "The Local Cy request was too large." });
      } else if (!response.headersSent) {
        sendJSON(response, 400, { error: "Local Cy could not read this request." });
      }
    }
  }

  private isAuthorized(request: IncomingMessage): boolean {
    const provided = request.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "";
    const expected = this.connection.token;
    const left = Buffer.from(provided);
    const right = Buffer.from(expected);
    return left.length === right.length && timingSafeEqual(left, right);
  }
}

async function waitForResponse(
  responsePath: string,
  request: IncomingMessage,
): Promise<unknown> {
  const deadline = Date.now() + 180_000;
  while (Date.now() < deadline) {
    if (request.aborted) throw new Error("The Local Cy client disconnected.");
    if (existsSync(responsePath)) {
      return LocalCyResponseSchema.parse(JSON.parse(readFileSync(responsePath, "utf8")));
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Local Cy timed out.");
}

async function readBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  let byteCount = 0;
  for await (const chunk of request) {
    const data = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteCount += data.length;
    if (byteCount > maximumRequestBytes) {
      const error = new Error("Payload too large.") as Error & { code?: string };
      error.code = "PAYLOAD_TOO_LARGE";
      throw error;
    }
    chunks.push(data);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function sendJSON(response: ServerResponse, status: number, value: unknown): void {
  const body = `${JSON.stringify(value)}\n`;
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
  });
  response.end(body);
}

function readErrorCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String((error as { code?: unknown }).code)
    : undefined;
}
