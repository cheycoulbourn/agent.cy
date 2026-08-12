import { existsSync } from "node:fs";
import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
// "(new)" after a redeploy means the volume at the state path did not persist.
process.stdout.write(
  `agent-cy-server state file: ${config.dataFile} ${existsSync(config.dataFile) ? "(exists)" : "(new)"}\n`,
);
const app = await buildApp({ config });

const shutdown = async (signal: string) => {
  try {
    await app.close();
    process.stdout.write(`agent-cy-server stopped after ${signal}\n`);
    process.exitCode = 0;
  } catch {
    process.exitCode = 1;
  }
};

process.once("SIGINT", () => void shutdown("SIGINT"));
process.once("SIGTERM", () => void shutdown("SIGTERM"));

try {
  await app.listen({ host: config.host, port: config.port });
  process.stdout.write(`agent-cy-server listening on ${config.host}:${config.port}\n`);
} catch (error) {
  process.stderr.write(
    `agent-cy-server failed to start: ${error instanceof Error ? error.message : String(error)}\n`,
  );
  process.exitCode = 1;
  await app.close();
}
