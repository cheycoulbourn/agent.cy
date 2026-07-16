import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { LocalCySchemaVersion } from "@agent-cy/contracts";
import { afterEach, describe, expect, it } from "vitest";

import { LocalCyHTTPServer } from "../src/local-cy-http-server.js";
import { LocalCyRuntime } from "../src/local-cy-runtime.js";
import { AgentCyWorkspace } from "../src/workspace.js";

const temporaryDirectories: string[] = [];
const servers: LocalCyHTTPServer[] = [];

afterEach(async () => {
  for (const server of servers.splice(0)) await server.stop();
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("LocalCyHTTPServer", () => {
  it("requires the connection token", async () => {
    const { server, baseURL } = await makeServer();
    const response = await fetch(`${baseURL}/healthz`);
    expect(response.status).toBe(401);
    await server.stop();
  });

  it("returns a structured result without waiting for iCloud propagation", async () => {
    const { server, baseURL, token, workspace } = await makeServer();
    const runtime = new LocalCyRuntime(workspace, async () => ({
      model: "claude-sonnet-test",
      result: {
        assistantMessage: "Start with the rough note exactly as it is.",
        suggestions: [],
        proposedAction: null,
      },
    }));
    const id = "be4d7760-0d3e-4d67-9221-2d5d5162a277";
    const request = fetch(`${baseURL}/v1/local-cy`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        schemaVersion: LocalCySchemaVersion,
        id,
        operation: "chatTurn",
        createdAt: new Date().toISOString(),
        workspaceId: null,
        payload: validChatRequest(id),
      }),
    });

    await wait(25);
    await expect(runtime.runOnce()).resolves.toBe(1);
    const response = await request;
    const responseText = await response.text();
    expect(response.status, responseText).toBe(200);
    const body = JSON.parse(responseText) as { status: string; result?: { assistantMessage?: string } };
    expect(body.status).toBe("succeeded");
    expect(body.result?.assistantMessage).toContain("rough note");
    await server.stop();
  });
});

async function makeServer() {
  const directory = mkdtempSync(join(tmpdir(), "agentcy-local-cy-http-"));
  temporaryDirectories.push(directory);
  const workspace = new AgentCyWorkspace(directory);
  const token = "test-token-that-is-at-least-thirty-two-characters";
  const server = new LocalCyHTTPServer(workspace, {
    schemaVersion: 1,
    baseURL: "http://127.0.0.1:0",
    token,
    updatedAt: new Date().toISOString(),
  });
  servers.push(server);
  await server.start();
  const baseURL = server.boundBaseURL;
  if (!baseURL) throw new Error("The Local Cy test server did not bind.");
  return { server, baseURL, token, workspace };
}

function validChatRequest(operationId: string) {
  return {
    schemaVersion: "agent-cy.ai.v1",
    promptVersion: "chat-turn.v1",
    operationId,
    appBuild: "test",
    assistanceMode: "collaborate",
    creatorContext: {
      name: "Chey",
      primaryGoal: "Create useful content",
      selectedPlatforms: ["instagramReels"],
      voiceExamples: [],
      pillars: [],
      librarySummaries: [],
    },
    conversation: [{
      messageId: "ffbdf55b-d39e-47ac-aa52-29e7b41e832a",
      role: "user",
      content: "Turn this rough note into a post.",
    }],
    relevantBriefIds: [],
  };
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
