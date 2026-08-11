#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

import { resolveDefaultWorkspaceDirectory } from "../dist/workspace.js";

if (process.platform !== "darwin") {
  throw new Error("The personal Local Cy installer currently supports macOS.");
}

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const runtimeDirectory = join(homedir(), "Library", "Application Support", "agent.cy", "local-cy");
const runtimePath = join(runtimeDirectory, "local-cy.mjs");
const workspace = resolve(valueAfter("--workspace") ?? resolveDefaultWorkspaceDirectory());
const nodePath = resolve(
  valueAfter("--node")
    ?? process.env.AGENTCY_NODE_PATH
    ?? launchSafeNodePath(),
);
const claudePath = commandPath("claude");
const uninstall = process.argv.includes("--uninstall");
const label = "com.agentcy.local-cy";
const launchAgents = join(homedir(), "Library", "LaunchAgents");
const plistPath = join(launchAgents, `${label}.plist`);
const logs = join(homedir(), "Library", "Logs", "agent.cy");
const domain = `gui/${process.getuid()}`;
const connectionPath = join(workspace, "cy-connection.json");
const port = 49_321;

runOptional("launchctl", ["bootout", domain, plistPath]);

if (uninstall) {
  rmSync(plistPath, { force: true });
  process.stdout.write("Local Cy was stopped. The shared workspace was kept.\n");
  process.exit(0);
}

if (!claudePath) throw new Error("Claude Code was not found. Install it and sign in first.");

const auth = JSON.parse(execFileSync(claudePath, ["auth", "status"], { encoding: "utf8" }));
if (auth.loggedIn !== true || auth.authMethod !== "claude.ai") {
  throw new Error("Claude Code is not signed in with a Claude subscription. Run claude and choose your Claude account first.");
}

mkdirSync(launchAgents, { recursive: true });
mkdirSync(logs, { recursive: true });
mkdirSync(runtimeDirectory, { recursive: true });
mkdirSync(join(workspace, "cy-requests"), { recursive: true });
mkdirSync(join(workspace, "cy-responses"), { recursive: true });
mkdirSync(join(workspace, "cy-processing"), { recursive: true });

const existingConnection = readJSON(connectionPath);
const localHostName = commandOutput("scutil", ["--get", "LocalHostName"])
  ?? commandOutput("hostname", ["-s"])
  ?? "localhost";
const connection = {
  schemaVersion: 1,
  baseURL: `http://${localHostName}.local:${port}`,
  token: typeof existingConnection?.token === "string"
    ? existingConnection.token
    : randomBytes(32).toString("base64url"),
  updatedAt: new Date().toISOString(),
};
writeFileSync(connectionPath, `${JSON.stringify(connection, null, 2)}\n`, {
  encoding: "utf8",
  mode: 0o600,
});

// LaunchAgents do not inherit Terminal's privacy permission for Documents.
// Bundle the service into Application Support so macOS can start it reliably
// after login without walking the source repository or pnpm symlinks.
await build({
  entryPoints: [join(packageDirectory, "src", "local-cy.ts")],
  outfile: runtimePath,
  bundle: true,
  platform: "node",
  target: "node24",
  format: "esm",
  minify: false,
  sourcemap: false,
});

writeFileSync(plistPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${xml(nodePath)}</string>
    <string>${xml(runtimePath)}</string>
  </array>
  <key>WorkingDirectory</key><string>${xml(runtimeDirectory)}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>AGENTCY_WORKSPACE_DIR</key><string>${xml(workspace)}</string>
    <key>AGENTCY_CLAUDE_EXECUTABLE</key><string>${xml(claudePath)}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>${xml(join(logs, "local-cy.log"))}</string>
  <key>StandardErrorPath</key><string>${xml(join(logs, "local-cy.error.log"))}</string>
</dict>
</plist>
`, { encoding: "utf8", mode: 0o600 });

execFileSync("launchctl", ["bootstrap", domain, plistPath], { stdio: "inherit" });
process.stdout.write([
  "Local Cy is running.",
  `Workspace: ${workspace}`,
  "Claude: subscription login confirmed",
  `Fast local connection: ${connection.baseURL}`,
  "On iPhone, open Settings > AI > Claude & Codex and enable Local Cy.",
].join("\n") + "\n");

function commandPath(command) {
  try {
    return execFileSync("which", [command], { encoding: "utf8" }).trim() || undefined;
  } catch {
    return undefined;
  }
}

function launchSafeNodePath() {
  const pathNode = commandPath("node");
  const candidates = [pathNode, process.execPath].filter(Boolean);
  const safeCandidate = candidates.find((candidate) => !candidate.includes("/Documents/"));
  if (safeCandidate) return safeCandidate;

  throw new Error([
    "The detected Node runtime is inside Documents, where macOS cannot launch it in the background.",
    "Install Node outside Documents or rerun with --node /absolute/path/to/node.",
  ].join(" "));
}

function commandOutput(command, args) {
  try {
    return execFileSync(command, args, { encoding: "utf8" }).trim() || undefined;
  } catch {
    return undefined;
  }
}

function readJSON(path) {
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function runOptional(command, args) {
  try {
    execFileSync(command, args, { stdio: "ignore" });
  } catch {
    // The service may not be installed yet.
  }
}

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function xml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}
