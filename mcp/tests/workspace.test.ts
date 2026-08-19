import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { AgentCyWorkspace, resolveDefaultWorkspaceDirectory } from "../src/workspace.js";

const now = "2026-07-15T12:00:00.000Z";

function snapshot(notification?: { endpoint: string; token: string }) {
  return {
    schemaVersion: 1,
    generatedAt: now,
    ...(notification ? { notification } : {}),
    workspaceId: "99999999-9999-4999-8999-999999999999",
    workspaceName: "@fromcheywithlove",
    profile: {
      id: "11111111-1111-4111-8111-111111111111",
      name: "Chey",
      goal: "Create consistently",
    },
    pillars: [],
    posts: [],
    tasks: [],
  };
}

describe("AgentCyWorkspace", () => {
  it("uses the creator's iCloud Drive on Windows", () => {
    expect(resolveDefaultWorkspaceDirectory("win32", {
      USERPROFILE: "C:\\Users\\Creator",
      iCloudDrive: "D:\\iCloudDrive",
    })).toBe("D:\\iCloudDrive\\agent.cy MCP");
  });

  it("validates the app snapshot before exposing it", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    writeFileSync(workspace.snapshotPath, JSON.stringify(snapshot()));
    expect(workspace.readSnapshot().profile?.name).toBe("Chey");
  });

  it("records the Claude and Codex clients the iPhone can detect", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);

    workspace.recordBridgeConnection(["claude"], "Installer verified.");
    workspace.recordBridgeConnection(["codex"], "bridge_status verified.");

    const stored = JSON.parse(readFileSync(workspace.bridgeStatusPath, "utf8")) as {
      status: string;
      clients: string[];
      message: string;
    };
    expect(stored.status).toBe("connected");
    expect(stored.clients).toEqual(["claude", "codex"]);
    expect(stored.message).toBe("bridge_status verified.");
  });

  it("queues a strict versioned request and waits for an app receipt", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    writeFileSync(workspace.snapshotPath, JSON.stringify(snapshot()));
    const request = workspace.queueRequest({
      type: "createIdea",
      payload: { title: "One clear angle", notes: "Keep it specific." },
    }, "codex");

    const stored = JSON.parse(
      readFileSync(join(workspace.requestsDirectory, `${request.id}.json`), "utf8"),
    ) as Record<string, unknown>;
    expect(stored).toMatchObject({
      schemaVersion: 1,
      source: "codex",
      type: "createIdea",
      workspaceId: "99999999-9999-4999-8999-999999999999",
    });
    expect(workspace.readReceipt(request.id)).toBeNull();
  });

  it("pushes a descriptive review notification and records delivery status", async () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const deliveries: Array<{ url: string; authorization: string | null; body: unknown }> = [];
    const workspace = new AgentCyWorkspace(directory, async (input, init) => {
      deliveries.push({
        url: String(input),
        authorization: new Headers(init?.headers).get("authorization"),
        body: JSON.parse(String(init?.body)),
      });
      return new Response(JSON.stringify({ accepted: true }), { status: 202 });
    });
    workspace.ensureDirectories();
    writeFileSync(workspace.snapshotPath, JSON.stringify(snapshot({
      endpoint: "https://agentcy.example/v1/bridge/notifications",
      token: "notification-capability-token-with-enough-entropy",
    })));
    const request = workspace.queueRequest({
      type: "createPostDraft",
      payload: { title: "The hidden bill behind cheap data" },
    }, "codex");

    await workspace.notifyQueuedRequest(request);

    expect(deliveries).toEqual([{
      url: "https://agentcy.example/v1/bridge/notifications",
      authorization: "Bearer notification-capability-token-with-enough-entropy",
      body: {
        requestId: request.id,
        workspaceId: "99999999-9999-4999-8999-999999999999",
        type: "createPostDraft",
        subject: "The hidden bill behind cheap data",
        pendingCount: 1,
      },
    }]);
    expect(JSON.parse(readFileSync(workspace.notificationStatusPath, "utf8"))).toMatchObject({
      status: "delivered",
      requestId: request.id,
    });
  });

  it("queues a post caption separately from production notes", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);
    const request = workspace.queueRequest({
      type: "createPostDraft",
      payload: {
        title: "A slower Asheville day",
        caption: "Asheville, slowly.",
        notes: "Use the arrival footage first.",
      },
    }, "claude");

    if (request.type !== "createPostDraft") {
      throw new Error("Expected a post-draft request");
    }
    expect(request.payload.caption).toBe("Asheville, slowly.");
    expect(request.payload.notes).toBe("Use the arrival footage first.");
  });

  it("queues a series only when its pillar is active in the app snapshot", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);
    workspace.ensureDirectories();
    const pillarId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    writeFileSync(workspace.snapshotPath, JSON.stringify({
      ...snapshot(),
      pillars: [{
        id: pillarId,
        parentPillarId: null,
        name: "SkipMatrix education",
        colorHex: "A78BFA",
        role: "anchor",
        assignedWeekdays: [],
      }],
    }));

    const request = workspace.queueRequest({
      type: "createSeries",
      payload: { name: "Data Diaries", pillarId },
    }, "codex");

    if (request.type !== "createSeries") {
      throw new Error("Expected a create-series request");
    }
    expect(request.payload.pillarId).toBe(pillarId);
    expect(() => workspace.queueRequest({
      type: "createSeries",
      payload: {
        name: "Unfiled series",
        pillarId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      },
    }, "codex")).toThrow(/active pillar/);
    expect(workspace.listPendingRequestIds()).toEqual([request.id]);
  });

  it("queues one review request for a newly scheduled post", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);
    const request = workspace.queueRequest({
      type: "createPostDraft",
      payload: {
        title: "A soft weekend in Charlotte",
        platform: "instagramReels",
        format: "Reel",
        targetDate: "2026-07-20T04:00:00.000Z",
        includesTargetTime: false,
      },
    }, "codex");

    if (request.type !== "createPostDraft") {
      throw new Error("Expected a post-draft request");
    }
    expect(request.payload.targetDate).toBe("2026-07-20T04:00:00.000Z");
    expect(request.payload.includesTargetTime).toBe(false);
    expect(workspace.listPendingRequestIds()).toEqual([request.id]);
  });

  it("does not queue a post when a posting date exists only in notes", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);

    expect(() => workspace.queueRequest({
      type: "createPostDraft",
      payload: {
        title: "A soft weekend in Charlotte",
        notes: "Intended publish date: Monday, July 20.",
      },
    }, "codex")).toThrow(/targetDate/);
    expect(workspace.listPendingRequestIds()).toEqual([]);
  });

  it("keeps a denied episode's identity when the creator resubmits a revision", () => {
    const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-"));
    const workspace = new AgentCyWorkspace(directory);
    const original = workspace.queueRequest({
      type: "createSeriesEpisode",
      payload: {
        seriesId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        title: "The premium-data break-even question",
        workDate: "2026-09-23T16:00:00.000Z",
      },
    }, "codex");
    if (original.type !== "createSeriesEpisode") {
      throw new Error("Expected a series-episode request");
    }
    expect(original.payload.episodeReviewId).toBeDefined();
    expect(original.payload.proposedEpisodeSlotId).toBeDefined();
    expect(original.payload.revisionNumber).toBe(1);

    workspace.recordEpisodeRevision({
      schemaVersion: 1,
      episodeReviewId: original.payload.episodeReviewId!,
      workspaceId: original.workspaceId ?? null,
      seriesId: original.payload.seriesId,
      episodeSlotId: original.payload.proposedEpisodeSlotId!,
      requestId: original.id,
      revisionNumber: 1,
      status: "needsRevision",
      decisionAt: "2026-08-17T13:00:00.000Z",
      decisionNote: "Show the formula and inputs.",
      request: original,
    });

    const revised = workspace.resubmitSeriesEpisode(original.payload.episodeReviewId!, {
      premise: "Show the inputs, formula, and worked result.",
    }, "codex");
    if (revised.type !== "createSeriesEpisode") {
      throw new Error("Expected a revised series-episode request");
    }
    expect(revised.id).not.toBe(original.id);
    expect(revised.payload.episodeReviewId).toBe(original.payload.episodeReviewId);
    expect(revised.payload.proposedEpisodeSlotId).toBe(original.payload.proposedEpisodeSlotId);
    expect(revised.payload.revisionNumber).toBe(2);
    expect(revised.payload.revisionOfRequestId).toBe(original.id);
    expect(revised.payload.premise).toBe("Show the inputs, formula, and worked result.");
    expect(workspace.readEpisodeRevision(original.payload.episodeReviewId!).status).toBe("readyForReview");
  });
});
