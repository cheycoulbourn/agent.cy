#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";

import { LocalCyConnectionConfigSchema } from "@agent-cy/contracts";

import { LocalCyHTTPServer } from "./local-cy-http-server.js";
import { LocalCyRuntime } from "./local-cy-runtime.js";
import { AgentCyWorkspace } from "./workspace.js";

const controller = new AbortController();
process.once("SIGINT", () => controller.abort());
process.once("SIGTERM", () => controller.abort());

const workspace = new AgentCyWorkspace();
const runtime = new LocalCyRuntime(workspace);

if (process.argv.includes("--once")) {
  runtime.runOnce()
    .then((completed) => process.stdout.write(`${JSON.stringify({ completed })}\n`))
    .catch(fail);
} else {
  run().catch(fail);
}

async function run(): Promise<void> {
  const connection = existsSync(workspace.localCyConnectionPath)
    ? LocalCyConnectionConfigSchema.parse(JSON.parse(readFileSync(workspace.localCyConnectionPath, "utf8")))
    : null;
  const server = connection ? new LocalCyHTTPServer(workspace, connection) : null;
  if (server) await server.start();
  try {
    await runtime.watch(controller.signal);
  } finally {
    await server?.stop();
  }
}

function fail(error: unknown): void {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`Local Cy failed: ${message}\n`);
  process.exitCode = 1;
}
