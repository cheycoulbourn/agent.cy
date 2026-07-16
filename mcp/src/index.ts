#!/usr/bin/env node

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createAgentCyMcpServer } from "./server.js";
import { AgentCyWorkspace } from "./workspace.js";

async function main(): Promise<void> {
  const workspace = new AgentCyWorkspace();
  workspace.ensureDirectories();
  if (process.argv.includes("--check")) {
    let snapshotAvailable = true;
    let workspaceName: string | null = null;
    try {
      workspaceName = workspace.readSnapshot().workspaceName ?? null;
    } catch {
      snapshotAvailable = false;
    }
    process.stdout.write(`${JSON.stringify({
      connected: true,
      workspace: workspace.directory,
      snapshotAvailable,
      workspaceName,
      pendingProposals: workspace.listPendingRequestIds().length,
    }, null, 2)}\n`);
    return;
  }
  const server = createAgentCyMcpServer(workspace);
  await server.connect(new StdioServerTransport());
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.stack ?? error.message : String(error);
  process.stderr.write(`agent.cy MCP failed: ${message}\n`);
  process.exitCode = 1;
});
