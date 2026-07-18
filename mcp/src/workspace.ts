import { randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve, win32 } from "node:path";

import {
  McpBridgeChangeRequestSchema,
  McpBridgeReceiptSchema,
  McpBridgeSchemaVersion,
  McpBridgeSnapshotSchema,
  type McpBridgeChangeRequest,
  type McpBridgeReceipt,
  type McpBridgeSnapshot,
} from "@agent-cy/contracts";

export function resolveDefaultWorkspaceDirectory(
  platform = process.platform,
  environment: NodeJS.ProcessEnv = process.env,
): string {
  if (environment.AGENTCY_WORKSPACE_DIR) {
    return resolve(environment.AGENTCY_WORKSPACE_DIR);
  }
  if (platform === "win32") {
    const iCloudRoot = environment.iCloudDrive
      ?? environment.ICLOUD_DRIVE
      ?? win32.join(environment.USERPROFILE ?? homedir(), "iCloudDrive");
    return win32.join(iCloudRoot, "agent.cy MCP");
  }
  return join(
    homedir(),
    "Library",
    "Mobile Documents",
    "com~apple~CloudDocs",
    "agent.cy MCP",
  );
}

export const defaultWorkspaceDirectory = resolveDefaultWorkspaceDirectory();

export class AgentCyWorkspace {
  readonly directory: string;
  readonly requestsDirectory: string;
  readonly responsesDirectory: string;
  readonly localCyRequestsDirectory: string;
  readonly localCyResponsesDirectory: string;
  readonly localCyProcessingDirectory: string;
  readonly localCyStatusPath: string;
  readonly localCyConnectionPath: string;
  readonly bridgeStatusPath: string;
  readonly snapshotPath: string;

  constructor(directory = defaultWorkspaceDirectory) {
    this.directory = resolve(directory);
    this.requestsDirectory = join(this.directory, "requests");
    this.responsesDirectory = join(this.directory, "responses");
    this.localCyRequestsDirectory = join(this.directory, "cy-requests");
    this.localCyResponsesDirectory = join(this.directory, "cy-responses");
    this.localCyProcessingDirectory = join(this.directory, "cy-processing");
    this.localCyStatusPath = join(this.directory, "cy-runtime.json");
    this.localCyConnectionPath = join(this.directory, "cy-connection.json");
    this.bridgeStatusPath = join(this.directory, "bridge-status.json");
    this.snapshotPath = join(this.directory, "snapshot.json");
  }

  ensureDirectories(): void {
    mkdirSync(this.requestsDirectory, { recursive: true });
    mkdirSync(this.responsesDirectory, { recursive: true });
    mkdirSync(this.localCyRequestsDirectory, { recursive: true });
    mkdirSync(this.localCyResponsesDirectory, { recursive: true });
    mkdirSync(this.localCyProcessingDirectory, { recursive: true });
  }

  readSnapshot(): McpBridgeSnapshot {
    if (!existsSync(this.snapshotPath)) {
      throw new Error(
        `No agent.cy snapshot exists at ${this.snapshotPath}. In the iPhone app, open Settings > AI > Claude & Codex, choose this folder, and tap Sync now.`,
      );
    }
    const parsed: unknown = JSON.parse(readFileSync(this.snapshotPath, "utf8"));
    return McpBridgeSnapshotSchema.parse(parsed);
  }

  queueRequest(
    request: Omit<McpBridgeChangeRequest, "schemaVersion" | "id" | "createdAt" | "source">,
    source: "claude" | "codex" | "mcp-client" = clientSource(),
  ): McpBridgeChangeRequest {
    this.ensureDirectories();
    const snapshot = existsSync(this.snapshotPath) ? this.readSnapshot() : null;
    const envelope = McpBridgeChangeRequestSchema.parse({
      schemaVersion: McpBridgeSchemaVersion,
      id: randomUUID(),
      createdAt: new Date().toISOString(),
      source,
      workspaceId: snapshot?.workspaceId ?? undefined,
      ...request,
    });
    writeJsonAtomically(join(this.requestsDirectory, `${envelope.id}.json`), envelope);
    return envelope;
  }

  readReceipt(requestId: string): McpBridgeReceipt | null {
    const path = join(this.responsesDirectory, `${requestId}.json`);
    if (!existsSync(path)) return null;
    const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
    return McpBridgeReceiptSchema.parse(parsed);
  }

  listPendingRequestIds(): string[] {
    this.ensureDirectories();
    return readdirSync(this.requestsDirectory)
      .filter((name) => name.endsWith(".json"))
      .map((name) => name.slice(0, -5))
      .sort();
  }

  recordBridgeConnection(clients: Array<"claude" | "codex">, message: string): void {
    const existingClients = this.readBridgeClients();
    writeJsonAtomically(this.bridgeStatusPath, {
      schemaVersion: 1,
      status: "connected",
      updatedAt: new Date().toISOString(),
      clients: [...new Set([...existingClients, ...clients])].sort(),
      message,
    });
  }

  private readBridgeClients(): Array<"claude" | "codex"> {
    if (!existsSync(this.bridgeStatusPath)) return [];
    try {
      const parsed = JSON.parse(readFileSync(this.bridgeStatusPath, "utf8")) as { clients?: unknown };
      if (!Array.isArray(parsed.clients)) return [];
      return parsed.clients.filter((client): client is "claude" | "codex" => (
        client === "claude" || client === "codex"
      ));
    } catch {
      return [];
    }
  }
}

export function writeJsonAtomically(path: string, value: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  renameSync(temporaryPath, path);
}

export function clientSource(): "claude" | "codex" | "mcp-client" {
  const raw = process.env.AGENTCY_MCP_CLIENT?.toLowerCase();
  if (raw === "claude" || raw === "codex") return raw;
  return "mcp-client";
}
