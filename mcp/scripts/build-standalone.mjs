#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const targetDirectory = resolve(
  valueAfter("--output") ?? join(packageDirectory, "artifacts", `${process.platform}-${process.arch}`),
);
const temporaryDirectory = join(targetDirectory, ".build");
const executableSuffix = process.platform === "win32" ? ".exe" : "";
const postject = join(
  packageDirectory,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "postject.cmd" : "postject",
);
const seaNode = resolve(
  process.env.AGENTCY_SEA_NODE
    ?? join(packageDirectory, "node_modules", "node", "bin", process.platform === "win32" ? "node.exe" : "node"),
);
const seaNodeVersion = execFileSync(seaNode, ["--version"], { encoding: "utf8" }).trim().replace(/^v/, "");
const [nodeMajor, nodeMinor] = seaNodeVersion.split(".").map(Number);
const supportsDirectSea = nodeMajor > 25 || (nodeMajor === 25 && nodeMinor >= 5);

rmSync(targetDirectory, { recursive: true, force: true });
mkdirSync(temporaryDirectory, { recursive: true });

await createExecutable("src/index.ts", `agentcy-mcp${executableSuffix}`);
await createExecutable("src/installer.ts", `agentcy-setup${executableSuffix}`);

writeFileSync(join(targetDirectory, "README.txt"), [
  "agent.cy Claude & Codex local bridge",
  "",
  `Run agentcy-setup${executableSuffix} and follow the prompts.`,
  "The installer finds iCloud Drive, registers the agentcy MCP server for Claude Code and Codex, and checks the connection.",
  "On iPhone, open agent.cy > Settings > AI > Claude & Codex and choose the same iCloud Drive folder.",
  "",
  `Repair: run agentcy-setup${executableSuffix} again.`,
  `Uninstall: run agentcy-setup${executableSuffix} --uninstall. Your iCloud Drive workspace is kept.`,
  "",
].join("\n"));

rmSync(temporaryDirectory, { recursive: true, force: true });
process.stdout.write(`Built ${targetDirectory}\n`);

async function createExecutable(entryPoint, name) {
  const stem = name.replace(/\.exe$/, "");
  const bundledPath = join(temporaryDirectory, `${stem}.cjs`);
  const blobPath = join(temporaryDirectory, `${stem}.blob`);
  const executablePath = join(targetDirectory, name);
  const configPath = join(temporaryDirectory, `${stem}.sea.json`);

  await build({
    entryPoints: [join(packageDirectory, entryPoint)],
    outfile: bundledPath,
    bundle: true,
    platform: "node",
    target: "node24",
    format: "cjs",
    minify: false,
    sourcemap: false,
    banner: { js: "globalThis.__filename = typeof __filename === 'undefined' ? '' : __filename;" },
  });

  writeFileSync(configPath, JSON.stringify({
    main: bundledPath,
    mainFormat: "commonjs",
    output: supportsDirectSea ? executablePath : blobPath,
    disableExperimentalSEAWarning: true,
    useSnapshot: false,
    useCodeCache: false,
  }, null, 2));

  if (supportsDirectSea) {
    execFileSync(seaNode, ["--build-sea", configPath], { stdio: "inherit" });
  } else {
    execFileSync(seaNode, ["--experimental-sea-config", configPath], { stdio: "inherit" });
    copyFileSync(seaNode, executablePath);
    chmodSync(executablePath, 0o755);
    if (process.platform === "darwin") {
      runOptional("codesign", ["--remove-signature", executablePath]);
    }
    execFileSync(postject, [
      executablePath,
      "NODE_SEA_BLOB",
      blobPath,
      "--sentinel-fuse",
      "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2",
      ...(process.platform === "darwin" ? ["--macho-segment-name", "NODE_SEA"] : []),
    ], { stdio: "inherit" });
  }

  if (process.platform === "darwin") {
    const identity = process.env.AGENTCY_MAC_SIGN_IDENTITY ?? "-";
    const signingArguments = identity === "-"
      ? ["--force", "--sign", identity, executablePath]
      : ["--force", "--options", "runtime", "--timestamp", "--sign", identity, executablePath];
    execFileSync("codesign", signingArguments, {
      stdio: "inherit",
    });
  }
  chmodSync(executablePath, 0o755);
}

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function runOptional(command, args) {
  try {
    execFileSync(command, args, { stdio: "ignore" });
  } catch {
    // The binary may not have an existing signature.
  }
}
