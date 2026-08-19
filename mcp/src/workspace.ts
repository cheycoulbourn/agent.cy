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
  McpBridgeEpisodeRevisionSchema,
  McpBridgeNotificationRequestSchema,
  McpBridgeReceiptSchema,
  McpBridgeSchemaVersion,
  McpBridgeSnapshotSchema,
  type McpBridgeChangeRequest,
  type McpBridgeChangeRequestInput,
  type McpBridgeEpisodeRevision,
  type McpBridgeReceipt,
  type McpBridgeSnapshot,
  type McpExternalPlanContext,
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

type BridgeFetch = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

type McpBridgeQueueRequest = McpBridgeChangeRequestInput extends infer Request
  ? Request extends McpBridgeChangeRequestInput
    ? Omit<Request, "schemaVersion" | "id" | "createdAt" | "source">
    : never
  : never;

export class AgentCyWorkspace {
  readonly directory: string;
  readonly requestsDirectory: string;
  readonly responsesDirectory: string;
  readonly episodeRevisionsDirectory: string;
  readonly localCyRequestsDirectory: string;
  readonly localCyResponsesDirectory: string;
  readonly localCyProcessingDirectory: string;
  readonly localCyStatusPath: string;
  readonly localCyConnectionPath: string;
  readonly bridgeStatusPath: string;
  readonly notificationStatusPath: string;
  readonly snapshotPath: string;

  constructor(
    directory = defaultWorkspaceDirectory,
    private readonly bridgeFetch: BridgeFetch = fetch,
  ) {
    this.directory = resolve(directory);
    this.requestsDirectory = join(this.directory, "requests");
    this.responsesDirectory = join(this.directory, "responses");
    this.episodeRevisionsDirectory = join(this.directory, "episode-revisions");
    this.localCyRequestsDirectory = join(this.directory, "cy-requests");
    this.localCyResponsesDirectory = join(this.directory, "cy-responses");
    this.localCyProcessingDirectory = join(this.directory, "cy-processing");
    this.localCyStatusPath = join(this.directory, "cy-runtime.json");
    this.localCyConnectionPath = join(this.directory, "cy-connection.json");
    this.bridgeStatusPath = join(this.directory, "bridge-status.json");
    this.notificationStatusPath = join(this.directory, "push-status.json");
    this.snapshotPath = join(this.directory, "snapshot.json");
  }

  ensureDirectories(): void {
    mkdirSync(this.requestsDirectory, { recursive: true });
    mkdirSync(this.responsesDirectory, { recursive: true });
    mkdirSync(this.episodeRevisionsDirectory, { recursive: true });
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
    request: McpBridgeQueueRequest,
    source: "claude" | "codex" | "mcp-client" = clientSource(),
  ): McpBridgeChangeRequest {
    this.ensureDirectories();
    const snapshot = existsSync(this.snapshotPath) ? this.readSnapshot() : null;
    if (request.type === "createSeries") {
      if (!snapshot) {
        throw new Error("Sync agent.cy before creating a series so its pillar can be verified.");
      }
      if (!snapshot.pillars.some((pillar) => pillar.id === request.payload.pillarId)) {
        throw new Error("Choose an active pillar from list_pillars before creating this series.");
      }
    }
    const enrichedRequest = request.type === "createSeries"
      ? {
          ...request,
          payload: {
            ...request.payload,
            seriesId: request.payload.seriesId ?? randomUUID(),
          },
        }
      : request.type === "createSeriesEpisode"
        ? {
            ...request,
            payload: {
              ...request.payload,
              episodeReviewId: request.payload.episodeReviewId ?? randomUUID(),
              proposedEpisodeSlotId: request.payload.episodeSlotId
                ? request.payload.proposedEpisodeSlotId
                : (request.payload.proposedEpisodeSlotId ?? randomUUID()),
              revisionNumber: request.payload.revisionNumber ?? 1,
            },
          }
        : request;
    const envelope = McpBridgeChangeRequestSchema.parse({
      schemaVersion: McpBridgeSchemaVersion,
      id: randomUUID(),
      createdAt: new Date().toISOString(),
      source,
      workspaceId: snapshot?.workspaceId ?? undefined,
      ...enrichedRequest,
    });
    writeJsonAtomically(join(this.requestsDirectory, `${envelope.id}.json`), envelope);
    return envelope;
  }

  async notifyQueuedRequest(request: McpBridgeChangeRequest): Promise<void> {
    if (!existsSync(this.snapshotPath)) {
      this.recordNotificationStatus(request.id, "unavailable", "Sync agent.cy before sending review notifications.");
      return;
    }
    const snapshot = this.readSnapshot();
    const capability = snapshot.notification;
    if (!capability) {
      this.recordNotificationStatus(request.id, "unavailable", "Push notifications are not connected.");
      return;
    }
    const linkedPostId = "postId" in request.payload ? request.payload.postId : undefined;
    const linkedPostTitle = linkedPostId
      ? snapshot.posts.find((post) => post.id === linkedPostId)?.title
      : undefined;
    const subject = (
      "title" in request.payload ? request.payload.title : undefined
    ) ?? (
      "name" in request.payload ? request.payload.name : undefined
    ) ?? linkedPostTitle ?? reviewTypeLabel(request.type);
    const body = McpBridgeNotificationRequestSchema.parse({
      requestId: request.id,
      workspaceId: request.workspaceId,
      type: request.type,
      subject,
      pendingCount: this.listPendingRequestIds().length,
    });

    try {
      const response = await this.bridgeFetch(capability.endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${capability.token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(3_000),
      });
      if (!response.ok) {
        throw new Error(`Notification service returned ${response.status}.`);
      }
      this.recordNotificationStatus(request.id, "delivered", "Sent to agent.cy for review.");
    } catch (error) {
      const message = error instanceof Error ? error.message : "Notification delivery failed.";
      this.recordNotificationStatus(request.id, "failed", message);
    }
  }

  private recordNotificationStatus(
    requestId: string,
    status: "delivered" | "failed" | "unavailable",
    message: string,
  ): void {
    writeJsonAtomically(this.notificationStatusPath, {
      schemaVersion: 1,
      requestId,
      status,
      updatedAt: new Date().toISOString(),
      message,
    });
  }

  readReceipt(requestId: string): McpBridgeReceipt | null {
    const path = join(this.responsesDirectory, `${requestId}.json`);
    if (!existsSync(path)) return null;
    const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
    return McpBridgeReceiptSchema.parse(parsed);
  }

  recordEpisodeRevision(revision: McpBridgeEpisodeRevision): McpBridgeEpisodeRevision {
    this.ensureDirectories();
    const parsed = McpBridgeEpisodeRevisionSchema.parse(revision);
    writeJsonAtomically(
      join(this.episodeRevisionsDirectory, `${parsed.episodeReviewId}.json`),
      parsed,
    );
    return parsed;
  }

  readEpisodeRevision(episodeReviewId: string): McpBridgeEpisodeRevision {
    this.ensureDirectories();
    const path = join(this.episodeRevisionsDirectory, `${episodeReviewId}.json`);
    if (!existsSync(path)) {
      throw new Error(`No episode revision exists with ID ${episodeReviewId}.`);
    }
    const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
    return McpBridgeEpisodeRevisionSchema.parse(parsed);
  }

  listEpisodeRevisions(
    status?: McpBridgeEpisodeRevision["status"],
  ): McpBridgeEpisodeRevision[] {
    this.ensureDirectories();
    return readdirSync(this.episodeRevisionsDirectory)
      .filter((name) => name.endsWith(".json"))
      .map((name) => {
        const parsed: unknown = JSON.parse(
          readFileSync(join(this.episodeRevisionsDirectory, name), "utf8"),
        );
        return McpBridgeEpisodeRevisionSchema.parse(parsed);
      })
      .filter((revision) => !status || revision.status === status)
      .sort((left, right) => left.decisionAt.localeCompare(right.decisionAt));
  }

  resubmitSeriesEpisode(
    episodeReviewId: string,
    patch: SeriesEpisodeRevisionPatch,
    source: "claude" | "codex" | "mcp-client" = clientSource(),
    externalPlan?: McpExternalPlanContext,
  ): Extract<McpBridgeChangeRequest, { type: "createSeriesEpisode" }> {
    const revision = this.readEpisodeRevision(episodeReviewId);
    if (revision.status !== "needsRevision") {
      throw new Error("Only an episode marked needsRevision can be resubmitted.");
    }
    const priorRequest = revision.request;
    const queued = this.queueRequest({
      type: "createSeriesEpisode",
      externalPlan: externalPlan ?? priorRequest.externalPlan,
      payload: {
        ...priorRequest.payload,
        ...patch,
        seriesId: priorRequest.payload.seriesId,
        episodeSlotId: priorRequest.payload.episodeSlotId,
        proposedEpisodeSlotId: priorRequest.payload.proposedEpisodeSlotId,
        episodeReviewId: priorRequest.payload.episodeReviewId ?? revision.episodeReviewId,
        revisionNumber: revision.revisionNumber + 1,
        revisionOfRequestId: priorRequest.id,
      },
    }, source);
    if (queued.type !== "createSeriesEpisode") {
      throw new Error("The revised episode request could not be created.");
    }
    this.recordEpisodeRevision({
      ...revision,
      requestId: queued.id,
      revisionNumber: queued.payload.revisionNumber,
      status: "readyForReview",
      decisionAt: new Date().toISOString(),
      request: queued,
    });
    return queued;
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

export type SeriesEpisodeRevisionPatch = Partial<Pick<
  Extract<McpBridgeChangeRequest, { type: "createSeriesEpisode" }>["payload"],
  | "title"
  | "premise"
  | "notes"
  | "episodeNumber"
  | "episodeLabel"
  | "platform"
  | "format"
  | "socialAccountId"
  | "hook"
  | "caption"
  | "callToAction"
  | "workDate"
  | "includesWorkTime"
  | "targetDate"
  | "includesTargetTime"
>>;

function reviewTypeLabel(type: McpBridgeChangeRequest["type"]): string {
  switch (type) {
    case "createIdea": return "New idea";
    case "createPostDraft": return "New post";
    case "updatePost": return "Post update";
    case "schedulePost": return "Posting date";
    case "reschedulePost": return "New posting date";
    case "markPostPosted": return "Posted status";
    case "createSeries": return "New series";
    case "createSeriesEpisode": return "New series episode";
    case "createBrandPartner": return "New brand partner";
    case "updateBrandPartner": return "Brand partner update";
    case "makeAnchorPillar": return "Pillar update";
    case "addTask": return "New task";
    case "completeTask": return "Task update";
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
