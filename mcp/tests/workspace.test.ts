import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { AgentCyWorkspace, resolveDefaultWorkspaceDirectory } from "../src/workspace.js";

const now = "2026-07-15T12:00:00.000Z";

function snapshot() {
  return {
    schemaVersion: 1,
    generatedAt: now,
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
});
