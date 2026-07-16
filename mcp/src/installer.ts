#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { isSea } from "node:sea";
import { stdin, stdout } from "node:process";

import { resolveDefaultWorkspaceDirectory } from "./workspace.js";

type Client = "claude" | "codex";

const args = process.argv.slice(2);
const nonInteractive = args.includes("--non-interactive");
const uninstall = args.includes("--uninstall");
const requestedClient = valueAfter("--client") ?? "both";
const workspace = resolve(valueAfter("--workspace") ?? resolveDefaultWorkspaceDirectory());
const serverPath = resolve(valueAfter("--server") ?? defaultServerPath());
const clients = detectedClients(requestedClient);

async function main(): Promise<void> {
  if (!["both", "claude", "codex"].includes(requestedClient)) {
    fail("Choose --client both, claude, or codex.");
  }

  if (clients.length === 0) {
    fail("Claude Code or Codex was not found. Install one of them, then run this installer again.");
  }

  if (!nonInteractive && !uninstall) {
    const confirmed = await confirmSetup();
    if (!confirmed) {
      stdout.write("Nothing changed.\n");
      return;
    }
  }

  if (uninstall) {
    for (const client of clients) removeClient(client);
    stdout.write("agent.cy was disconnected from Claude and Codex. Your iCloud Drive workspace was kept.\n");
    return;
  }

  mkdirSync(join(workspace, "requests"), { recursive: true });
  mkdirSync(join(workspace, "responses"), { recursive: true });

  for (const client of clients) {
    removeClient(client);
    registerClient(client);
  }

  const status = checkBridge();
  stdout.write([
    "",
    "agent.cy is ready for Claude & Codex.",
    `Workspace: ${workspace}`,
    `Connected: ${clients.map(capitalized).join(" and ")}`,
    `Status: ${status}`,
    "Next: on iPhone, open agent.cy > Settings > AI > Claude & Codex, choose this same iCloud Drive folder, and tap Sync now.",
    "",
  ].join("\n"));
}

void main().catch((error: unknown) => {
  fail(error instanceof Error ? error.message : String(error));
});

async function confirmSetup(): Promise<boolean> {
  stdout.write([
    "agent.cy Claude & Codex setup",
    "",
    `Computer: ${process.platform === "win32" ? "Windows" : "macOS"}`,
    `Workspace: ${workspace}`,
    `Found: ${clients.map(capitalized).join(" and ")}`,
    "",
    "This registers the local agentcy MCP server for your user account.",
  ].join("\n") + "\n");
  const prompt = createInterface({ input: stdin, output: stdout });
  const answer = await prompt.question("Continue? [Y/n] ");
  prompt.close();
  return answer.trim() === "" || answer.trim().toLowerCase().startsWith("y");
}

function detectedClients(requested: string): Client[] {
  const candidates: Client[] = requested === "both" ? ["claude", "codex"] : [requested as Client];
  return candidates.filter(commandExists);
}

function commandExists(command: Client): boolean {
  const result = spawnSync(command, ["--version"], { stdio: "ignore", shell: process.platform === "win32" });
  return result.status === 0;
}

function registerClient(client: Client): void {
  const command = serverCommand();
  const environmentArguments = [
    "--env", `AGENTCY_WORKSPACE_DIR=${workspace}`,
    "--env", `AGENTCY_MCP_CLIENT=${client}`,
  ];
  const clientArguments = client === "claude"
    ? ["mcp", "add", "agentcy", "--scope", "user", ...environmentArguments, "--", ...command]
    : ["mcp", "add", "agentcy", ...environmentArguments, "--", ...command];
  run(client, clientArguments);
}

function removeClient(client: Client): void {
  const clientArguments = client === "claude"
    ? ["mcp", "remove", "agentcy", "--scope", "user"]
    : ["mcp", "remove", "agentcy"];
  spawnSync(client, clientArguments, { stdio: "ignore", shell: process.platform === "win32" });
}

function serverCommand(): string[] {
  return extname(serverPath).toLowerCase() === ".js"
    ? [process.execPath, serverPath]
    : [serverPath];
}

function checkBridge(): string {
  try {
    const command = serverCommand();
    const executable = command.shift();
    if (!executable) return "Repair needed";
    const output = execFileSync(executable, [...command, "--check"], {
      encoding: "utf8",
      env: { ...process.env, AGENTCY_WORKSPACE_DIR: workspace },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const parsed = JSON.parse(output) as { snapshotAvailable?: boolean };
    return parsed.snapshotAvailable ? "Connected" : "Connected. Sync from iPhone to finish.";
  } catch {
    return "Repair needed. Run this installer again.";
  }
}

function defaultServerPath(): string {
  if (isSea()) {
    return join(dirname(process.execPath), process.platform === "win32" ? "agentcy-mcp.exe" : "agentcy-mcp");
  }
  const current = process.argv[1] ? resolve(process.argv[1]) : join(homedir(), "agentcy-installer");
  return resolve(dirname(current), "index.js");
}

function valueAfter(flag: string): string | undefined {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
}

function capitalized(value: string): string {
  return value === "claude" ? "Claude Code" : "Codex";
}

function run(command: string, commandArgs: string[]): void {
  try {
    execFileSync(command, commandArgs, { stdio: "inherit", shell: process.platform === "win32" });
  } catch {
    fail(`Could not configure ${capitalized(command)}. Check that it opens, then run the installer again.`);
  }
}

function fail(message: string): never {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}
