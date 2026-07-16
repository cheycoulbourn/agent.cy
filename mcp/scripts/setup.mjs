#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { resolveDefaultWorkspaceDirectory } from "../dist/workspace.js";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageDirectory = resolve(scriptDirectory, "..");
const serverPath = join(packageDirectory, "dist", "index.js");
const defaultWorkspace = resolveDefaultWorkspaceDirectory();
const args = process.argv.slice(2);
const client = valueAfter("--client") ?? "both";
const workspace = resolve(valueAfter("--workspace") ?? defaultWorkspace);
const nodePath = resolve(valueAfter("--node") ?? process.env.AGENTCY_NODE_PATH ?? process.execPath);

if (!["both", "claude", "codex"].includes(client)) {
  throw new Error("--client must be both, claude, or codex");
}

mkdirSync(join(workspace, "requests"), { recursive: true });
mkdirSync(join(workspace, "responses"), { recursive: true });

if (client === "both" || client === "claude") {
  runOptional("claude", ["mcp", "remove", "agentcy", "--scope", "user"]);
  run("claude", [
    "mcp", "add", "agentcy", "--scope", "user",
    "--env", `AGENTCY_WORKSPACE_DIR=${workspace}`,
    "--env", "AGENTCY_MCP_CLIENT=claude",
    "--", nodePath, serverPath,
  ]);
}

if (client === "both" || client === "codex") {
  runOptional("codex", ["mcp", "remove", "agentcy"]);
  run("codex", [
    "mcp", "add", "agentcy",
    "--env", `AGENTCY_WORKSPACE_DIR=${workspace}`,
    "--env", "AGENTCY_MCP_CLIENT=codex",
    "--", nodePath, serverPath,
  ]);
}

process.stdout.write([
  "agent.cy is configured for Claude & Codex.",
  `Workspace: ${workspace}`,
  "Next: on iPhone, open agent.cy > Settings > AI > Claude & Codex and choose this same iCloud Drive folder.",
].join("\n") + "\n");

function valueAfter(flag) {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
}

function run(command, commandArgs) {
  execFileSync(command, commandArgs, { stdio: "inherit" });
}

function runOptional(command, commandArgs) {
  try {
    execFileSync(command, commandArgs, { stdio: "ignore" });
  } catch {
    // The server may not be configured yet.
  }
}
