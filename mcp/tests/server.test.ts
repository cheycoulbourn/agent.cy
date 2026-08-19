import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { afterEach, describe, expect, it } from "vitest";

import { createAgentCyMcpServer } from "../src/server.js";
import { AgentCyWorkspace } from "../src/workspace.js";

const clients: Client[] = [];

afterEach(async () => {
  await Promise.all(clients.splice(0).map((client) => client.close()));
});

async function connectedServer() {
  const directory = mkdtempSync(join(tmpdir(), "agentcy-mcp-server-"));
  const workspace = new AgentCyWorkspace(directory);
  workspace.ensureDirectories();
  writeFileSync(workspace.snapshotPath, JSON.stringify({
    schemaVersion: 1,
    generatedAt: "2026-08-17T21:30:00.000Z",
    workspaceId: "99999999-9999-4999-8999-999999999999",
    workspaceName: "SkipMatrix",
    profile: null,
    socialAccounts: [],
    pillars: [],
    posts: [],
    tasks: [],
    series: [],
    episodeSlots: [],
    brandPartners: [],
  }));

  const server = createAgentCyMcpServer(workspace);
  const client = new Client({ name: "agentcy-test", version: "1.0.0" });
  clients.push(client);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([
    server.connect(serverTransport),
    client.connect(clientTransport),
  ]);
  return { client, workspace };
}

describe("agent.cy MCP external plan preflight", () => {
  it("requires an external-plan answer on every write tool", async () => {
    const { client } = await connectedServer();
    const { tools } = await client.listTools();
    const writeTools = [
      "create_idea",
      "create_post_draft",
      "update_post",
      "set_post_work_date",
      "schedule_post",
      "reschedule_post",
      "mark_posted",
      "create_series",
      "create_series_episode",
      "resubmit_series_episode",
      "add_task",
      "add_post_task",
      "create_brand_partner",
      "update_brand_partner",
      "make_anchor_pillar",
      "complete_task",
    ];

    for (const name of writeTools) {
      const tool = tools.find((candidate) => candidate.name === name);
      expect(tool, name).toBeDefined();
      expect(tool?.inputSchema.required, name).toContain("externalPlan");
    }

    const createSeries = tools.find((candidate) => candidate.name === "create_series");
    expect(createSeries?.inputSchema.required).toContain("pillarId");
  });

  it("stores the verified Notion destination beside the agent.cy proposal", async () => {
    const { client, workspace } = await connectedServer();
    const result = await client.callTool({
      name: "create_post_draft",
      arguments: {
        externalPlan: {
          status: "linked",
          creatorConfirmed: true,
          system: "Notion",
          workspace: "SkipMatrix",
          destination: "Data Diaries production database",
          sourceOfTruth: "shared",
          syncDirection: "bidirectional",
          externalWritesRequireApproval: true,
        },
        title: "The hidden bill behind cheap data",
      },
    });

    expect(result.isError).not.toBe(true);
    const [requestId] = workspace.listPendingRequestIds();
    const stored = JSON.parse(
      readFileSync(join(workspace.requestsDirectory, `${requestId}.json`), "utf8"),
    ) as { externalPlan: Record<string, unknown> };
    expect(stored.externalPlan).toMatchObject({
      status: "linked",
      system: "Notion",
      workspace: "SkipMatrix",
      destination: "Data Diaries production database",
      externalWritesRequireApproval: true,
    });
  });
});
